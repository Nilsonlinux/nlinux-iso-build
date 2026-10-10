#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Rodado pelo mkarchiso dentro do chroot do live system durante o build
# (mecanismo oficial "customize_airootfs.sh"). Prepara o ambiente ao vivo
# para o modo "Experimentar": pacotes AUR, greetd + noctalia-greeter e o
# usuário "nlinux" com o desktop Umbriel + Noctalia.
set -euo pipefail

log() { echo -e "\e[36m[nlinux-live]\e[0m $*"; }
die() { echo -e "\e[31m[nlinux-live][erro]\e[0m $*" >&2; exit 1; }

log "==> Iniciando configuração do live system"

# Dentro do chroot do archiso a raiz '/' não é um mountpoint, então o check de
# espaço do pacman falha sempre ("could not determine root mount point" →
# "not enough free disk space"). Desativa o CheckSpace durante o build AUR e
# restaura o estado original ao final.
if grep -q '^CheckSpace$' /etc/pacman.conf; then
  sed -i 's/^CheckSpace$/#CheckSpace/' /etc/pacman.conf
  trap 'sed -i "s/^#CheckSpace$/CheckSpace/" /etc/pacman.conf' EXIT
fi

# O mkarchiso instala os pacotes sem inicializar a keyring do pacman no chroot
# (pacstrap com -G e sem -K). Qualquer `pacman -S` de pacote de repositório —
# como faz o yay para instalar as dependências dos AUR — falha então com
# "Public keyring not found" / "keyring is not writable". Inicializa e popula
# aqui (offline: as chaves vêm do pacote archlinux-keyring já instalado).
# O 700 vem ANTES de qualquer --init/--populate: o chmod de depois nao recupera o
# que o --init ja nao gravou. E' higiene, nao a correcao do bug da loja — o gpg
# aceita gravar em 755 (so avisa "permissoes inseguras"). O que abortava o
# `pacman -Syu` era o tmpfs do archiso mascarar este diretorio no sistema
# instalado; ver install/chroot/50-services.sh.
if [[ -d /etc/pacman.d/gnupg ]]; then
  chmod 700 /etc/pacman.d/gnupg 2>/dev/null || true
  chown root:root /etc/pacman.d/gnupg 2>/dev/null || true
fi

log "Inicializando keyring do pacman (pacman-key --init + populate)"
if [[ ! -d /etc/pacman.d/gnupg ]] || ! pacman-key --list-keys archlinux >/dev/null 2>&1; then
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux >/dev/null 2>&1 || true
fi
chmod -R 700 /etc/pacman.d/gnupg 2>/dev/null || true
chown -R root:root /etc/pacman.d/gnupg 2>/dev/null || true

# multilib: programas 32-bit. A loja do NLinux já esperava por isso — o
# REPO_FILES dela (nlinux-software/src/nlinux/pacman_db.py) lê core, extra e
# multilib — mas sem a seção no pacman.conf o sync db do multilib nunca baixa e
# a loja fica sem os pacotes de lá, incluindo o Steam.
# ATENÇÃO: este mesmo bloco está em install/chroot/10-system.sh, para o sistema
# instalado, e os dois precisam ficar iguais.
log "Habilitando o repositório multilib (programas 32-bit)"
# O releng do archiso deixa o bloco comentado. Descomenta em vez de acrescentar
# uma seção nova, para o arquivo continuar igual ao da wiki do Arch.
sed -i '/^#\[multilib\]$/,/^\[/ s/^#Include/Include/; s/^#\[multilib\]$/[multilib]/' /etc/pacman.conf
# Um pacman novo pode não trazer o bloco comentado: nesse caso acrescentar.
if ! grep -q '^\[multilib\]$' /etc/pacman.conf; then
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
  log "aviso: bloco [multilib] não encontrado no pacman.conf; acrescentado ao fim."
fi
# O multilib exige 'SigLevel = Required DatabaseOptional' em [options]. Já é o
# padrão do Arch, mas descomenta se vier comentado — sem isso o multilib não é
# lido. Por precaução, porque um build novo do pacman pode mudar esse texto.
sed -i 's/^#SigLevel *= *Required *DatabaseOptional/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
log "repos do pacman: $(pacman-conf --repo-list 2>/dev/null | tr '\n' ' ')"
# Não dá para habilitar isso em iso/profile/pacman.conf: essa pasta é
# gitignored e o build-iso.sh recopia do releng do archiso a cada build, de
# modo que a mudança se perderia. Por isso é aqui, no chroot da ISO.
# O multilib-testing fica comentado: é repositório de teste.


# O packagekit instala um hook alpm pós-transação ("Refreshing PackageKit...")
# que reinicia o packagekit via D-Bus — inexistente dentro do chroot do build.
# Quando um pacote AUR dispara esse hook, o pacman falha (exit status 4) e o
# yay aborta a instalação. Desativa o hook antes de qualquer transação.
log "Desativando hook alpm do PackageKit (sem D-Bus em chroot)"
for h in /usr/share/libalpm/hooks/*.hook /etc/pacman.d/hooks/*.hook; do
  [[ -e "$h" ]] || continue
  grep -qil "packagekit" "$h" && { log "removido: $h"; rm -f "$h"; } || true
done

# O pacstrap do archiso so baixou os dbs de core e extra: na hora do pacstrap a
# secao [multilib] ainda estava comentado no pacman.conf do profile. Deixar a
# secao habilitada sem o db faz QUALQUER transacao seguinte falhar com
# "failed to prepare transaction (could not find database)" — foi exatamente o
# que quebrou este build na primeira tentativa, na transacao do yay dos pacotes
# AUR. Baixa os dbs agora, ja com o multilib habilitado, e antes do primeiro
# `pacman -S`. Fica depois da remocao dos hooks acima para nao depender de um
# `-Sy` puro nao disparar hook de pacote, e o CheckSpace continua desativado
# neste ponto (a trap do comeco do script so restaura no EXIT), que e o que
# permite ao pacman rodar dentro deste chroot.
# So no live: aqui a rede e garantida (o build ja baixa do AUR e de espelhos).
# No chroot da instalacao o sync NAO e feito de proposito — na instalacao
# offline pode nao haver rede e isso quebraria a instalacao; e o db chega pelo
# clone do live ou pelo nlinux-pacman-refresh.service no primeiro boot.
log "Sincronizando bancos de pacotes (inclui o db do multilib)"
pacman -Sy
test -f /var/lib/pacman/sync/multilib.db \
  || die "sync terminou sem multilib.db — o primeiro pacman -S vai falhar"

# A fase `check` de pacotes AUR Rust (xwayland-satellite-git, umbriel-git) roda
# `cargo test` que comanda um display X/wayland — inexistente em chroot — e o
# build fica travado (ex.: "test copy_from_x11 ..."). O makepkg não tem opção
# em makepkg.conf para isso; o `--nocheck` é repassado via --mflags do yay nos
# passos abaixo (e via --nocheck no makepkg do yay-bin).
log "Nota: fase check desativada via --mflags '--nocheck' nos builds do yay"

# --- Pacotes AUR: umbriel-git, xdg-desktop-portal-umbriel-git, noctalia-greeter
log "Criando usuário temporário para build de pacotes AUR"
useradd -m -s /bin/bash builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-nlinux-builder
chmod 440 /etc/sudoers.d/10-nlinux-builder

log "Instalando yay (yay-bin) via makepkg"
# O git:// do AUR cai com 502 o suficiente para abortar o build inteiro, e sem
# isto a falha vira uma mensagem que não ajuda: o clone deixa só um diretório
# parcial (ou nada), o `cd` falha, e o makepkg reporta "You do not have write
# permission for the directory $BUILDDIR (/)" — que não é a causa. Então: limpa o
# diretório entre tentativas, repete, e se falhar de vez diz o que aconteceu.
tentativas=3
for (( i = 1; i <= tentativas; i++ )); do
  rm -rf /tmp/yay-bin
  if runuser -u builder -- git clone --depth 1 \
       https://aur.archlinux.org/yay-bin.git /tmp/yay-bin; then
    break
  fi
  if (( i < tentativas )); then
    log "clone do yay falhou (tentativa $i/$tentativas); repetindo em 10s"
    sleep 10
  fi
done
[[ -f /tmp/yay-bin/PKGBUILD ]] \
  || die "não consegui clonar yay-bin do AUR em $tentativas tentativas. É falha de rede — o build inteiro aborta aqui, mas é seguro repetir do começo."
runuser -u builder -- bash -c '
  cd /tmp/yay-bin
  makepkg --config /opt/noctalia-installer/install/chroot/makepkg-no-debug.conf \
    -si --noconfirm --nocheck
'

log "Instalando pacotes AUR — etapa 1 (dependências: greeter, portal, xwayland)"
# Nota: o umbriel-git depende do xdg-desktop-portal-umbriel-git. Se ambos forem
# alvos explícitos no MESMO `yay -S`, o yay builda tudo mas só instala no final,
# e o makepkg do umbriel falha com "Could not resolve all dependencies" (o portal
# ainda não existe instalado). Por isso o portal/greeter/xwayland vão primeiro e
# o umbriel-git em um segundo yay, já com a dependência instalada.
runuser -u builder -- bash -c '
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --answerdiff None --answerclean None --answeredit None --answerupgrade None \
    --mflags "--nocheck --config /opt/noctalia-installer/install/chroot/makepkg-no-debug.conf" \
    noctalia-greeter xdg-desktop-portal-umbriel-git xwayland-satellite-git
'

log "Instalando pacotes AUR — etapa 2 (umbriel-git + apps, com o portal já instalado)"
runuser -u builder -- bash -c '
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --answerdiff None --answerclean None --answeredit None --answerupgrade None \
    --mflags "--nocheck --config /opt/noctalia-installer/install/chroot/makepkg-no-debug.conf" \
    umbriel-git whatsapp-linux-desktop-bin
'

log "Removendo usuário temporário builder"
userdel -r builder 2>/dev/null || true
rm -f /etc/sudoers.d/10-nlinux-builder
rm -rf /tmp/yay-bin /tmp/gocache /tmp/cargo

# --- greetd + noctalia-greeter
[[ -x /usr/bin/noctalia-greeter-session ]] || die "noctalia-greeter-session não encontrado."

log "Criando usuário de sistema do greetd (greeter)"
id -u greeter >/dev/null 2>&1 || useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter greeter

log "Escrevendo /etc/greetd/config.toml (vt 7, noctalia-greeter)"
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 7

[default_session]
command = "/usr/bin/noctalia-greeter-session -- --session umbriel"
user = "greeter"
EOF

log "Executando setup do noctalia-greeter (PAM, diretórios e estado)"
NOCTALIA_GREETER_SESSION_BIN=/usr/bin/noctalia-greeter-session \
  /usr/share/noctalia-greeter/setup_greeter_system.sh || true

chmod 0750 /var/lib/noctalia-greeter 2>/dev/null || true

# --- Usuário do live (login no greeter: nlinux / nlinux)
log "Criando usuário 'nlinux' (grupos de mídia/input/sudo)"
id nlinux >/dev/null 2>&1 || useradd -m -G wheel,video,input,audio,storage,network,users -s /usr/bin/fish nlinux
echo "nlinux:nlinux" | chpasswd

# --- Sudo para o usuário do live (senha: nlinux)
log "Adicionando usuário 'nlinux' ao sudoers (sem senha — instalador web live)"
echo 'nlinux ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-nlinux-user
chmod 440 /etc/sudoers.d/10-nlinux-user

# --- Rede no live: NetworkManager assume as interfaces
log "Habilitando NetworkManager e desativando o systemd-networkd do releng"
systemctl enable NetworkManager 2>/dev/null || true
systemctl disable systemd-networkd 2>/dev/null || true
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# --- Banco de dados do pacman sincronizado a cada boot do live
# A unit ja vem no airootfs (iso/airootfs/etc/systemd/system/); aqui so
# habilitamos. O modo RÁPido offline clona o live com rsync sem excluir nada de
# /etc/systemd, entao o sistema instalado herda a unit e o symlink de
# habilitação — nao e preciso instalar nada no chroot.
log "Habilitando sincronizacao do banco do pacman no boot"
if [[ -f /etc/systemd/system/nlinux-pacman-refresh.service ]]; then
  systemctl enable nlinux-pacman-refresh.service 2>/dev/null || true
  log "habilitado: nlinux-pacman-refresh.service (pacman -Sy no boot)"
else
  log "aviso: unit do pacman-refresh ausente; a sincronizacao no boot ficou desativada"
fi

# --- Configurações do Umbriel e ícones (cursor) para o desktop no live
log "Configurando dotfiles do usuário nlinux (umbriel, Bibata)"
mkdir -p /home/nlinux/.config
if [[ -d /opt/noctalia-installer/config/.config ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#/opt/noctalia-installer/config/.config/}"
    target="/home/nlinux/.config/$rel"
    mkdir -p "$(dirname "$target")"
    if grep -q '__KEYBOARD_LAYOUT__' "$f"; then
      sed 's/__KEYBOARD_LAYOUT__/us/g' "$f" > "${target%.tpl}"
    else
      cp -a "$f" "${target%.tpl}"
    fi
  done < <(find /opt/noctalia-installer/config/.config -type f -print0)
fi

# As boas-vindas são instaladas e iniciadas somente após a instalação do sistema.
LIVE_UMBRIEL_CONFIG="/home/nlinux/.config/umbriel/src/general.toml"
if [[ -f "$LIVE_UMBRIEL_CONFIG" ]]; then
  sed -i '/^[[:space:]]*"nlinux-welcome",[[:space:]]*$/d' "$LIVE_UMBRIEL_CONFIG"
fi

# Ícones/cursor (.local): cópia íntegra (binários e symlinks preservados)
if [[ -d /opt/noctalia-installer/config/.local ]]; then
  mkdir -p /home/nlinux/.local
  cp -a /opt/noctalia-installer/config/.local/. /home/nlinux/.local/
fi
chown -R nlinux:nlinux /home/nlinux/.config /home/nlinux/.local 2>/dev/null || true

# Dock no live: fixa também o instalador NLinux. No sistema instalado ele é
# removido (install.sh), então o pin vive só aqui; o arquivo é carregado por
# último pelo Noctalia e sobrescreve o "pinned" do config.toml base.
if [[ -f /home/nlinux/.config/noctalia/config.toml ]]; then
  cat > /home/nlinux/.config/noctalia/z-live.toml <<'EOF'
[dock]
pinned = [
    "org.telegram.desktop",
    "whatsapp-linux-desktop",
    "firefox",
    "discord",
    "kitty",
    "org.gnome.Nautilus",
    "spotify-launcher",
    "nlinuxstore",
    "nlinux-installer",
]
EOF
  chown nlinux:nlinux /home/nlinux/.config/noctalia/z-live.toml
fi

# --- PipeWire/WirePlumber no live: habilita a session de usuário do 'nlinux'
# (o umbriel sobe via systemd --user, então basta ativar os sockets/services
# no default.target da sessão do usuário)
log "Habilitando PipeWire + WirePlumber na sessão do usuário nlinux"
mkdir -p /home/nlinux/.config/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/pipewire.socket \
  /home/nlinux/.config/systemd/user/default.target.wants/pipewire.socket
ln -sf /usr/lib/systemd/user/pipewire-pulse.socket \
  /home/nlinux/.config/systemd/user/default.target.wants/pipewire-pulse.socket
ln -sf /usr/lib/systemd/user/wireplumber.service \
  /home/nlinux/.config/systemd/user/default.target.wants/wireplumber.service
chown -R nlinux:nlinux /home/nlinux/.config/systemd 2>/dev/null || true

log "Variáveis de ambiente do live (Wayland + cursor Bibata)"
{
  echo "MOZ_ENABLE_WAYLAND=1"
  echo "ELECTRON_OZONE_PLATFORM_HINT=auto"
  echo "XDG_SESSION_TYPE=wayland"
  echo "XCURSOR_THEME=Bibata-Modern-Ice"
  echo "XCURSOR_SIZE=20"
} >> /etc/environment

# --- Atalho do instalador no menu (e na Área de Trabalho do live)
log "Instalando atalho 'Instalar NLinux' (menu + Desktop do live)"
if [[ -f /usr/share/applications/nlinux-installer.desktop ]]; then
  mkdir -p /home/nlinux/Desktop
  cp -a /usr/share/applications/nlinux-installer.desktop /home/nlinux/Desktop/
  chmod +x /home/nlinux/Desktop/nlinux-installer.desktop 2>/dev/null || true
fi

# --- Loja de software no menu e na Área de Trabalho do live
log "Instalando atalho 'Loja de Software' (menu + Desktop do live)"
if [[ -f /usr/share/applications/nlinuxstore.desktop ]]; then
  mkdir -p /home/nlinux/Desktop
  cp -a /usr/share/applications/nlinuxstore.desktop /home/nlinux/Desktop/
  chmod +x /home/nlinux/Desktop/nlinuxstore.desktop 2>/dev/null || true
fi
chmod +x /usr/local/bin/nlinux-software 2>/dev/null || true
chmod 0755 /opt/nlinux-software/nlinux-software 2>/dev/null || true

# --- Loja gravável: o app NÃO escreve mais em /opt. Desde a v117 o catálogo e a
# mídia da loja foram para ~/.local/share/nlinux/store e o /opt é só a semente
# embarcada, então a árvore pode ficar no root (o app só precisa ler). Semear
# a pasta do usuário aqui evita que a primeira abertura espere a cópia.
if [[ -d /opt/nlinux-software/src/apps ]]; then
  store_data="/home/nlinux/.local/share/nlinux/store"
  mkdir -p "$store_data"
  if [[ ! -d "$store_data/apps" ]]; then
    cp -a /opt/nlinux-software/src/apps "$store_data/apps"
  fi
  chown -R nlinux:nlinux /home/nlinux/.local/share/nlinux
  chmod -R u+rwX /home/nlinux/.local/share/nlinux
fi

# --- Marca os atalhos da Área de Trabalho como confiáveis (GNOME pediria
# permissão a cada clique e poderia "não abrir" o app).
command -v gio >/dev/null 2>&1 && for d in nlinux-installer nlinuxstore; do
  gio set "/home/nlinux/Desktop/$d.desktop" metadata::trusted true 2>/dev/null || true
done
chown -R nlinux:nlinux /home/nlinux/Desktop 2>/dev/null || true

# Identidade da distro gerada no build (persiste no sistema instalado via
# cópia offline). Usa a mesma numeração do profiledef (Y.M.D da ISO).
{
  echo 'NILINUX_NAME="NLinux"'
  echo "NILINUX_VERSION=\"$(date +%Y.%m.%d)\""
  echo "NILINUX_BUILT=\"$(date -Is)\""
} > /etc/nlinux-release

log "==> Live system configurado. Desktop disponível via greetd (usuário nlinux)."