#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Configura a assinatura GPG de commits e tags do NLinux.
#
# Modelo usado (recomendado para chave de releases):
#
#   chave primária (só certifica, guardada offline)
#     ├── subchave de assinatura da máquina de casa
#     └── subchave de assinatura da máquina do trabalho
#
# Cada máquina recebe SÓ a sua subchave secreta. A chave primária secreta não
# fica em nenhuma das duas: ela existe apenas no backup completo, guardado
# offline. Assim, perder/comprometer uma máquina não compromete a outra nem a
# capacidade de emitir novas subchaves.
#
# Uso:
#   ./scripts/setup-signing.sh doctor
#   ./scripts/setup-signing.sh bootstrap          # na primeira máquina (cria a chave)
#   ./scripts/setup-signing.sh join --bundle ...  # na segunda máquina
#   ./scripts/setup-signing.sh verify
#   ./scripts/setup-signing.sh publish            # atualiza a chave pública do repo
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${NLINUX_SIGNING_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nlinux-signing}"
KEYS_ENV="$CONFIG_DIR/keys.env"
PUBLIC_ASC="$CONFIG_DIR/public.asc"

# Identidade e validade da chave. Podem ser sobrescritas por variáveis de
# ambiente, mas o padrão é o que o README e o GitHub esperam.
KEY_NAME="${NLINUX_SIGNING_NAME:-NLinux Releases}"
KEY_EMAIL="${NLINUX_SIGNING_EMAIL:-nilsonlinux@gmail.com}"
KEY_EXPIRE="${NLINUX_SIGNING_EXPIRE:-2y}"
GIT_NAME="${NLINUX_GIT_NAME:-Nilsonlinux}"
GIT_EMAIL="${NLINUX_GIT_EMAIL:-$KEY_EMAIL}"

MACHINE=""
OTHER_MACHINE=""
BUNDLE=""
FORCE=0
PASS=""

die()  { echo -e "\e[31m[sign] erro:\e[0m $*" >&2; exit 1; }
info() { echo -e "\e[36m[sign]\e[0m $*"; }
ok()   { echo -e "\e[32m[sign]\e[0m $*"; }
warn() { echo -e "\e[33m[sign] aviso:\e[0m $*" >&2; }

usage() {
  cat <<'EOF'
Uso: setup-signing.sh <comando> [opções]

Comandos:
  bootstrap   Cria a chave de releases e configura ESTA máquina.
              Gera também o pacote da outra máquina e o backup completo.
  join        Importa o pacote de uma subchave e configura ESTA máquina.
              Requer --bundle <arquivo.asc>.
  verify      Faz um commit e uma tag de teste num repo temporário e
              confere as assinaturas.
  publish     Copia a chave pública nova para o repo, preserva a antiga em
              nlinux-releases-gpg-pub-legacy.asc e atualiza o README.
  doctor      Mostra o estado da chave, do agente, do Git e das tags.
  help        Esta ajuda.

Opções do bootstrap:
  --machine NOME   Nome desta máquina (padrão: pergunta). Ex.: casa
  --other NOME     Nome da outra máquina (padrão: pergunta). Ex.: trabalho
  --name NOME      Nome real da chave (padrão: NLinux Releases)
  --email EMAIL    E-mail/UID da chave (padrão: nilsonlinux@gmail.com)
  --expire PRAZO   Validade (padrão: 2y)
  --force          Refaz a configuração mesmo se já existir uma chave local

Opções do join:
  --bundle ARQUIVO Pacote .asc exportado pelo bootstrap na outra máquina
  --machine NOME   Nome desta máquina (padrão: nome do arquivo)

Exemplos:
  ./scripts/setup-signing.sh bootstrap --machine casa --other trabalho
  ./scripts/setup-signing.sh join --bundle machine-trabalho.asc --machine trabalho
  ./scripts/setup-signing.sh verify
  ./scripts/setup-signing.sh publish
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "comando '$1' não encontrado. Instale: $2"
}

gpg_pass() {
  # Usa a passphrase em PASS sem deixá-la na linha de comando (fd 3).
  gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 "$@" 3<<<"$PASS"
}

read_passphrase() {
  local p1 p2
  while :; do
    read -rsp "Passphrase da chave de releases (mínimo 12 caracteres): " p1; echo
    read -rsp "Repita a passphrase: " p2; echo
    if (( ${#p1} < 12 )); then
      warn "passphrase curta demais."
      continue
    fi
    if [[ "$p1" != "$p2" ]]; then
      warn "as passphrases não conferem."
      continue
    fi
    PASS="$p1"
    unset p1 p2
    return 0
  done
}

load_env() {
  [[ -f "$KEYS_ENV" ]] || die "configuração não encontrada em $KEYS_ENV. Rode 'bootstrap' ou 'join' primeiro."
  # shellcheck disable=SC1090
  source "$KEYS_ENV"
  [[ -n "${FPR:-}" ]] || die "$KEYS_ENV não tem FPR."
}

write_env() {
  local fpr="$1" sub_this="$2" sub_other="$3" machine="$4" other="$5"
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  cat > "$KEYS_ENV" <<EOF
# Gerado por scripts/setup-signing.sh em $(date -Iseconds)
# NÃO versionar este arquivo.
FPR=$(printf '%q' "$fpr")
KEY_NAME=$(printf '%q' "$KEY_NAME")
KEY_EMAIL=$(printf '%q' "$KEY_EMAIL")
MACHINE=$(printf '%q' "$machine")
OTHER_MACHINE=$(printf '%q' "$other")
SUB_THIS=$(printf '%q' "$sub_this")
SUB_OTHER=$(printf '%q' "$sub_other")
EOF
  chmod 600 "$KEYS_ENV"
}

configure_pinentry() {
  # Respeita GNUPGHOME (usado nos testes e por quem separa o chaveiro).
  local gpg_home conf pin=""
  gpg_home="$(gpgconf --list-dirs homedir)"
  mkdir -p "$gpg_home"
  chmod 700 "$gpg_home"

  conf="$gpg_home/gpg-agent.conf"
  touch "$conf"
  chmod 600 "$conf"

  if ! grep -q '^[[:space:]]*pinentry-program' "$conf"; then
    # Para git em terminal, pinentry-curses é o mais confiável: funciona em
    # Wayland, X11, SSH e console. Pinentry gráfico só entra se não houver
    # nenhum pinentry de terminal (ou se o usuário pedir por variável).
    if [[ -n "${NLINUX_PINENTRY:-}" ]]; then
      pin="$(command -v "${NLINUX_PINENTRY}" || true)"
    fi
    if [[ -z "$pin" ]]; then
      for candidate in pinentry-curses pinentry-tty pinentry; do
        if command -v "$candidate" >/dev/null 2>&1; then
          pin="$(command -v "$candidate")"
          break
        fi
      done
    fi
    if [[ -z "$pin" && -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
      for candidate in pinentry-gnome3 pinentry-qt pinentry-gtk; do
        if command -v "$candidate" >/dev/null 2>&1; then
          pin="$(command -v "$candidate")"
          break
        fi
      done
    fi
    [[ -n "$pin" ]] || die "nenhum pinentry encontrado (instale pinentry)."
    {
      echo "# Adicionado por scripts/setup-signing.sh"
      echo "pinentry-program $pin"
    } >> "$conf"
  fi

  grep -q '^[[:space:]]*default-cache-ttl' "$conf" || echo 'default-cache-ttl 3600' >> "$conf"
  grep -q '^[[:space:]]*max-cache-ttl'     "$conf" || echo 'max-cache-ttl 28800' >> "$conf"

  # pinentry-curses/tty precisa saber em qual terminal falar.
  if grep -q 'pinentry-program .*pinentry-\(curses\|tty\)' "$conf"; then
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [[ -f "$rc" ]] || continue
      if ! grep -q 'NLINUX_SIGNING_GPG_TTY' "$rc"; then
        {
          echo ''
          echo '# NLINUX_SIGNING_GPG_TTY: pinentry no terminal precisa do tty'
          echo 'export GPG_TTY="$(tty 2>/dev/null || true)"'
        } >> "$rc"
      fi
    done
    rc="$HOME/.config/fish/config.fish"
    if [[ -f "$rc" ]] && ! grep -q 'NLINUX_SIGNING_GPG_TTY' "$rc"; then
      {
        echo ''
        echo '# NLINUX_SIGNING_GPG_TTY: pinentry no terminal precisa do tty'
        echo 'set -gx GPG_TTY (tty 2>/dev/null)'
      } >> "$rc"
    fi
  fi

  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  if [[ -t 0 ]]; then
    export GPG_TTY="$(tty)"
    gpg-connect-agent updatestartuptty /bye >/dev/null
  fi
  ok "pinentry configurado: ${pin:-já existente}"
}

configure_git() {
  local fpr="$1" old_key
  old_key="$(git config --global --get user.signingkey 2>/dev/null || true)"
  if [[ -n "$old_key" && "$old_key" != "$fpr" ]]; then
    warn "substituindo user.signingkey global antigo ($old_key) por $fpr."
  fi
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global user.signingkey "$fpr"
  git config --global gpg.program gpg
  git config --global gpg.format openpgp
  git config --global commit.gpgsign true
  git config --global tag.gpgSign true
  git config --global log.showSignature true
  ok "Git configurado: $GIT_NAME <$GIT_EMAIL>, chave $fpr"
}

subkey_fprs() {
  # Só as impressões digitais das subchaves, na ordem em que o GnuPG lista.
  gpg --with-colons --list-keys "$1" | awk -F: '/^fpr:/{print $10}' | tail -n +2
}

newest_subkey_fpr() {
  subkey_fprs "$1" | tail -n1
}

secret_summary() {
  gpg --list-secret-keys --keyid-format=long "$1" 2>&1 \
    | grep -E '^(sec|ssb)' || true
}

validate_backup() {
  local backup="$1" fpr="$2" tmp sub_count
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/nlinux-signing-check.XXXXXX")"
  chmod 700 "$tmp"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  GNUPGHOME="$tmp" gpg --batch --quiet --import "$backup" \
    || die "o backup completo não pôde ser importado."
  sub_count="$(GNUPGHOME="$tmp" gpg --with-colons --list-secret-keys "$fpr" | grep -c '^ssb:')"
  [[ "$sub_count" == "2" ]] \
    || die "backup inválido: esperava 2 subchaves secretas, encontrei $sub_count."
  rm -rf "$tmp"
  trap - RETURN
  ok "backup completo validado (chave primária + 2 subchaves)."
}

cmd_bootstrap() {
  require_cmd gpg "gnupg"
  require_cmd git "git"
  require_cmd sha256sum "coreutils"

  if [[ -e "$KEYS_ENV" && "$FORCE" != 1 ]]; then
    die "já existe $KEYS_ENV. Use --force só se quiser mesmo criar OUTRA chave."
  fi
  if gpg --with-colons --list-secret-keys "$KEY_EMAIL" 2>/dev/null | grep -q '^sec:'; then
    [[ "$FORCE" == 1 ]] || die "já existe chave secreta com o e-mail $KEY_EMAIL. Use --force para ignorar (não recomendado)."
  fi

  if [[ -z "$MACHINE" ]]; then
    read -rp "Nome desta máquina (ex.: casa): " MACHINE
  fi
  if [[ -z "$OTHER_MACHINE" ]]; then
    read -rp "Nome da outra máquina (ex.: trabalho): " OTHER_MACHINE
  fi
  [[ "$MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "nome de máquina inválido: $MACHINE"
  [[ "$OTHER_MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "nome de máquina inválido: $OTHER_MACHINE"
  [[ "$MACHINE" != "$OTHER_MACHINE" ]] || die "os nomes das duas máquinas precisam ser diferentes."

  info "Chave: $KEY_NAME <$KEY_EMAIL>"
  info "Esta máquina: $MACHINE   Outra máquina: $OTHER_MACHINE"
  info "Validade: $KEY_EXPIRE   Destino: $CONFIG_DIR"
  echo
  warn "A chave primária secreta NÃO ficará nesta máquina depois do bootstrap."
  warn "Guarde o backup completo e o certificado de revogação fora do computador."
  echo
  read_passphrase

  configure_pinentry

  info "gerando chave primária (só certificação)..."
  gpg_pass --quick-generate-key "$KEY_NAME <$KEY_EMAIL>" ed25519 cert "$KEY_EXPIRE"

  local fpr sub_this sub_other
  fpr="$(gpg --with-colons --list-keys "$KEY_EMAIL" | awk -F: '/^fpr:/{print $10; exit}')"
  [[ -n "$fpr" ]] || die "não consegui obter a impressão digital da chave criada."

  info "gerando subchave de assinatura de $MACHINE..."
  gpg_pass --quick-add-key "$fpr" ed25519 sign "$KEY_EXPIRE"
  sub_this="$(newest_subkey_fpr "$fpr")"
  sleep 1

  info "gerando subchave de assinatura de $OTHER_MACHINE..."
  gpg_pass --quick-add-key "$fpr" ed25519 sign "$KEY_EXPIRE"
  sub_other="$(newest_subkey_fpr "$fpr")"

  [[ -n "$sub_this" && -n "$sub_other" && "$sub_this" != "$sub_other" ]] \
    || die "não consegui separar as duas subchaves."

  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  umask 077

  info "exportando pacotes e backup..."
  gpg_pass --armor --export-secret-subkeys "$sub_this!"  > "$CONFIG_DIR/machine-$MACHINE.asc"
  gpg_pass --armor --export-secret-subkeys "$sub_other!" > "$CONFIG_DIR/machine-$OTHER_MACHINE.asc"
  gpg_pass --armor --export-secret-keys "$fpr"           > "$CONFIG_DIR/full-secret-backup.asc"
  gpg --batch --armor --export "$fpr"                    > "$PUBLIC_ASC"

  local gpg_home rev
  gpg_home="$(gpgconf --list-dirs homedir)"
  rev="$gpg_home/openpgp-revocs.d/$fpr.rev"
  if [[ -f "$rev" ]]; then
    cp "$rev" "$CONFIG_DIR/revocation.asc"
  else
    warn "certificado de revogação automático não encontrado em $rev"
  fi

  { echo "$fpr:6:"; } | gpg --batch --import-ownertrust >/dev/null 2>&1 || true

  validate_backup "$CONFIG_DIR/full-secret-backup.asc" "$fpr"

  info "removendo a chave primária secreta desta máquina..."
  gpg_pass --yes --delete-secret-keys "$fpr!"

  info "removendo desta máquina a subchave de $OTHER_MACHINE..."
  gpg_pass --yes --delete-secret-keys "$sub_other!"

  # Depois da limpeza, o GnuPG ainda lista as duas subchaves: a desta máquina
  # como `ssb` (com segredo) e a da outra como `ssb#` (só o stub público).
  local summary
  summary="$(secret_summary "$fpr")"
  [[ "$(grep -cE '^ssb[[:space:]]' <<<"$summary" || true)" == "1" ]] \
    || die "esperava exatamente 1 subchave secreta nesta máquina."
  [[ "$(grep -c '^ssb#' <<<"$summary" || true)" == "1" ]] \
    || die "esperava a subchave da outra máquina apenas como stub (ssb#)."

  configure_git "$fpr"
  write_env "$fpr" "$sub_this" "$sub_other" "$MACHINE" "$OTHER_MACHINE"

  (
    cd "$CONFIG_DIR"
    sha256sum public.asc full-secret-backup.asc revocation.asc \
      "machine-$MACHINE.asc" "machine-$OTHER_MACHINE.asc" > SHA256SUMS
  )

  echo
  ok "bootstrap concluído."
  echo
  echo "  Chave primária : $fpr"
  echo "  Subchave $MACHINE : $sub_this"
  echo "  Subchave $OTHER_MACHINE : $sub_other"
  echo
  echo "  Pacote desta máquina  : $CONFIG_DIR/machine-$MACHINE.asc"
  echo "  Pacote da outra máquina: $CONFIG_DIR/machine-$OTHER_MACHINE.asc"
  echo "  Backup completo       : $CONFIG_DIR/full-secret-backup.asc"
  echo "  Revogação             : $CONFIG_DIR/revocation.asc"
  echo "  Chave pública         : $PUBLIC_ASC"
  echo
  warn "MOVA full-secret-backup.asc, revocation.asc e SHA256SUMS para um pendrive"
  warn "ou cofre offline e APAGUE-OS desta máquina depois de conferir o backup."
  warn "Sem eles não dá para criar novas subchaves nem revogar a chave."
  echo
  echo "Próximos passos:"
  echo "  1. ./scripts/setup-signing.sh verify"
  echo "  2. ./scripts/setup-signing.sh publish   # chave pública no repo"
  echo "  3. Leve $CONFIG_DIR/machine-$OTHER_MACHINE.asc para a outra máquina"
  echo "     e rode lá: ./scripts/setup-signing.sh join --bundle machine-$OTHER_MACHINE.asc"
  echo "  4. Cadastre $PUBLIC_ASC em https://github.com/settings/gpg/new"
}

cmd_join() {
  require_cmd gpg "gnupg"
  require_cmd git "git"
  [[ -n "$BUNDLE" ]] || die "informe --bundle <arquivo.asc>."
  [[ -f "$BUNDLE" ]] || die "pacote não encontrado: $BUNDLE"

  if [[ -e "$KEYS_ENV" && "$FORCE" != 1 ]]; then
    die "já existe $KEYS_ENV. Use --force só se quiser substituir a configuração."
  fi

  local fpr
  fpr="$(gpg --batch --with-colons --import-options show-only --import "$BUNDLE" 2>/dev/null \
    | awk -F: '/^fpr:/{print $10; exit}')"
  [[ -n "$fpr" ]] || die "não consegui ler a impressão digital de $BUNDLE."

  if [[ -z "$MACHINE" ]]; then
    MACHINE="$(basename "$BUNDLE" .asc)"
    MACHINE="${MACHINE#machine-}"
  fi
  [[ "$MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "nome de máquina inválido: $MACHINE"

  info "importando subchave de $MACHINE (chave $fpr)..."
  gpg --batch --quiet --import "$BUNDLE"

  { echo "$fpr:6:"; } | gpg --batch --import-ownertrust >/dev/null 2>&1 || true

  local summary
  summary="$(secret_summary "$fpr")"
  grep -qE '^ssb[[:space:]]' <<<"$summary" || die "o pacote não trouxe nenhuma subchave secreta."
  if grep -q '^sec ' <<<"$summary"; then
    warn "este pacote contém a chave primária secreta; o esperado era só a subchave."
  fi

  configure_pinentry
  configure_git "$fpr"
  write_env "$fpr" "" "" "$MACHINE" ""

  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  gpg --batch --armor --export "$fpr" > "$PUBLIC_ASC"
  chmod 600 "$PUBLIC_ASC"

  echo
  ok "join concluído nesta máquina ($MACHINE)."
  echo
  echo "  Chave primária: $fpr"
  secret_summary "$fpr" | sed 's/^/  /'
  echo
  echo "Rode: ./scripts/setup-signing.sh verify"
}

cmd_verify() {
  require_cmd gpg "gnupg"
  require_cmd git "git"
  load_env
  configure_pinentry

  gpg --list-secret-keys "$FPR" >/dev/null 2>&1 \
    || die "chave secreta $FPR não está disponível nesta máquina."

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/nlinux-signing-test.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  info "criando repo de teste e assinando commit + tag..."
  (
    cd "$tmp"
    git init -q
    git config user.name "$GIT_NAME"
    git config user.email "$GIT_EMAIL"
    git config user.signingkey "$FPR"
    git config gpg.program gpg
    git config commit.gpgsign true
    git config tag.gpgSign true
    echo "teste $(date -Iseconds)" > teste.txt
    git add teste.txt
    git commit -q -m "teste de assinatura"
    git tag -s -m "teste de tag assinada" teste-assinatura
  )

  local commit_status tag_status
  commit_status="$(git -C "$tmp" -c log.showSignature=false log -1 --format='%G? %GS')"
  tag_status="$(git -C "$tmp" tag -v teste-assinatura 2>&1 | grep -E 'Assinatura válida|Good signature' || true)"

  rm -rf "$tmp"
  trap - RETURN

  echo
  [[ "$commit_status" == G* || "$commit_status" == U* ]] \
    || die "o commit de teste NÃO ficou assinado (status: $commit_status)."
  [[ -n "$tag_status" ]] \
    || die "a tag de teste NÃO foi verificada."

  ok "commit: $commit_status"
  ok "tag: $tag_status"
  echo
  echo "Obs.: status 'G' = assinatura boa e chave confiável; 'U' = assinatura boa,"
  echo "mas a chave ainda não tem confiança local. Para o seu próprio commit,"
  echo "o normal é 'G' depois do import de ownertrust feito pelo setup."
}

cmd_publish() {
  load_env
  [[ -f "$PUBLIC_ASC" ]] || die "chave pública não encontrada em $PUBLIC_ASC."
  [[ -f "$REPO_DIR/README.md" ]] || die "README.md não encontrado em $REPO_DIR."

  local short fpr_fmt
  short="$(gpg --with-colons --list-keys "$FPR" | awk -F: '/^pub:/{print $5; exit}')"
  fpr_fmt="$(gpg --with-colons --list-keys "$FPR" | awk -F: '/^fpr:/{print $10; exit}' \
    | sed 's/\(....\)/\1 /g' | sed 's/ $//')"

  if [[ -f "$REPO_DIR/nlinux-releases-gpg-pub.asc" ]] \
     && ! cmp -s "$PUBLIC_ASC" "$REPO_DIR/nlinux-releases-gpg-pub.asc"; then
    if [[ ! -f "$REPO_DIR/nlinux-releases-gpg-pub-legacy.asc" ]]; then
      cp "$REPO_DIR/nlinux-releases-gpg-pub.asc" \
         "$REPO_DIR/nlinux-releases-gpg-pub-legacy.asc"
      info "chave antiga preservada em nlinux-releases-gpg-pub-legacy.asc"
    fi
  fi

  cp "$PUBLIC_ASC" "$REPO_DIR/nlinux-releases-gpg-pub.asc"
  chmod 644 "$REPO_DIR/nlinux-releases-gpg-pub.asc"

  # Atualiza as linhas da seção "Assinatura das releases (GPG)".
  perl -0pi -e "s/^- Chave: \`[0-9A-F]+\`\$/- Chave: \`$short\`/m" "$REPO_DIR/README.md"
  perl -0pi -e "s/^- Impressão digital: \`[0-9A-F ]+\`\$/- Impressão digital: \`$fpr_fmt\`/m" "$REPO_DIR/README.md"

  if ! grep -q 'nlinux-releases-gpg-pub-legacy.asc' "$REPO_DIR/README.md"; then
    perl -0pi -e 's/(- Impressão digital: `[^`]+`\n)/$1- Chave legada (releases antigas): [`nlinux-releases-gpg-pub-legacy.asc`](nlinux-releases-gpg-pub-legacy.asc)\n/' \
      "$REPO_DIR/README.md"
  fi

  if ! grep -q 'gpg --import nlinux-releases-gpg-pub-legacy.asc' "$REPO_DIR/README.md"; then
    perl -0pi -e 's/(gpg --import nlinux-releases-gpg-pub\.asc[^\n]*\n)/$1gpg --import nlinux-releases-gpg-pub-legacy.asc   # opcional: releases antigas\n/' \
      "$REPO_DIR/README.md"
  fi

  echo
  ok "chave pública publicada no repo."
  echo "  Chave: $short"
  echo "  Impressão digital: $fpr_fmt"
  echo
  git -C "$REPO_DIR" --no-pager diff --stat -- README.md nlinux-releases-gpg-pub.asc nlinux-releases-gpg-pub-legacy.asc || true
  echo
  echo "Revise com: git -C \"$REPO_DIR\" diff"
  echo "Depois assine e commite:"
  echo "  git -C \"$REPO_DIR\" add nlinux-releases-gpg-pub.asc nlinux-releases-gpg-pub-legacy.asc README.md"
  echo "  git -C \"$REPO_DIR\" commit -S -m 'assinatura: nova chave de releases NLinux'"
}

cmd_doctor() {
  echo "== GnuPG =="
  gpg --version | head -n2
  echo
  echo "== pinentry =="
  local agent_conf
  agent_conf="$(gpgconf --list-dirs homedir)/gpg-agent.conf"
  if [[ -f "$agent_conf" ]]; then
    grep -E '^[[:space:]]*(pinentry-program|default-cache-ttl|max-cache-ttl)' "$agent_conf" || true
  else
    echo "  (sem gpg-agent.conf)"
  fi
  echo "  GPG_TTY: ${GPG_TTY:-(vazio)}"
  echo
  echo "== chaves secretas =="
  gpg --list-secret-keys --keyid-format=long 2>&1 || true
  echo
  echo "== configuração local =="
  if [[ -f "$KEYS_ENV" ]]; then
    sed 's/^/  /' "$KEYS_ENV"
  else
    warn "sem $KEYS_ENV (rode bootstrap ou join)."
  fi
  echo
  echo "== Git =="
  for key in user.name user.email user.signingkey gpg.program gpg.format \
             commit.gpgsign tag.gpgSign log.showSignature; do
    printf '  %-20s %s\n' "$key" "$(git config --global --get "$key" || echo '(vazio)')"
  done
  echo
  echo "== repositório =="
  echo "  HEAD: $(git -C "$REPO_DIR" -c log.showSignature=false log -1 --format='%G? %h %s' 2>/dev/null || echo 'sem commits')"
  echo "  tags:"
  local t kind
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    kind="$(git -C "$REPO_DIR" cat-file -t "refs/tags/$t" 2>/dev/null || echo '?')"
    printf '    %-14s %s\n' "$t" "$kind"
  done < <(git -C "$REPO_DIR" tag -l)
}

while (( $# > 0 )); do
  case "$1" in
    bootstrap|join|verify|publish|doctor|help|-h|--help)
      CMD="$1"; shift ;;
    --machine)  MACHINE="$2"; shift 2 ;;
    --other)    OTHER_MACHINE="$2"; shift 2 ;;
    --name)     KEY_NAME="$2"; shift 2 ;;
    --email)    KEY_EMAIL="$2"; shift 2 ;;
    --expire)   KEY_EXPIRE="$2"; shift 2 ;;
    --bundle)   BUNDLE="$2"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    *) die "opção desconhecida: $1 (use 'help')" ;;
  esac
done

case "${CMD:-help}" in
  bootstrap) cmd_bootstrap ;;
  join)      cmd_join ;;
  verify)    cmd_verify ;;
  publish)   cmd_publish ;;
  doctor)    cmd_doctor ;;
  help|-h|--help) usage ;;
  *) usage; exit 1 ;;
esac
