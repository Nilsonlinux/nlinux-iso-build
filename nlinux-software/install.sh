#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -e
if [ "$(id -u)" -ne 0 ]; then
  echo "Executando com sudo..."
  exec sudo "$0" "$@"
fi
require() { pacman -Q "$1" >/dev/null 2>&1; }
# --- dependências de execução ----------------------------------------
MISSING=""
for p in python python-gobject gtk3 webkit2gtk-4.1 polkit gnupg git; do
  require "$p" || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then
  echo "Instalando dependências:${MISSING}"
  pacman -S --noconfirm --needed $MISSING
fi
# paru ou yay (AUR) e curl são opcionais; avisa só o que faltar
if ! command -v paru >/dev/null 2>&1 && ! command -v yay >/dev/null 2>&1; then
  echo "Aviso: nenhum auxiliar AUR encontrado (paru ou yay)."
fi
command -v curl >/dev/null 2>&1 || echo "Aviso: 'curl' não encontrado."
# --- autentica o pacote com GPG (assinatura da curadoria) ------------
SRC="$(cd "$(dirname "$0")" && pwd)"
if ! command -v gpg >/dev/null 2>&1; then
  echo "ERRO: gpg ausente; não é possível validar a assinatura." >&2
  exit 1
fi
# ls ordena alfabeticamente, e 'v115' < 'v211': com varios
# tarballs na pasta, head -n1 pegava o MAIS ANTIGO, nao o
# mais novo. sort -V ordena por numero de versao.
TARBALL="$(ls "$SRC"/nlinux-software-v*.tar.gz "$SRC"/../nlinux-software-v*.tar.gz 2>/dev/null | sort -V | tail -n1)"
if [ -z "$TARBALL" ]; then
  # fallback para o nome antigo (FalconOS), caso a pasta venha de
  # uma publicação anterior à padronização do nome
  TARBALL="$(ls "$SRC"/falconos-software-v*.tar.gz "$SRC"/../falconos-software-v*.tar.gz 2>/dev/null | sort -V | tail -n1)"
fi
PUBASC="$SRC/nlinux-software_pub.asc"
[ -f "$PUBASC" ] || PUBASC="$SRC/falconos-software_pub.asc"
if [ -z "$TARBALL" ]; then
  echo "Aviso: nenhum nlinux-software-v<N>.tar.gz encontrado em $SRC."
  echo "         Instalando a loja a partir do src/ sem validar assinatura."
elif [ -f "$TARBALL.asc" ] && [ -f "$PUBASC" ]; then
  # set -e + redirecionamento silencioso aqui ja matou o
  # instalador sem mensagem alguma quando a chave publica faltava.
  if ! gpg --batch --import "$PUBASC" >/dev/null 2>&1; then
    echo "ERRO: $(basename "$PUBASC") não pôde ser importada." >&2
    echo "O pacote está sem a chave pública: baixe o repositório inteiro." >&2
    exit 1
  fi
  if ! gpg --batch --verify "$TARBALL.asc" "$TARBALL" >/dev/null 2>&1; then
    echo "ERRO: assinatura GPG do pacote INVÁLIDA. Instalação abortada." >&2
    echo "O arquivo (ou o repositório) pode ter sido adulterado. Baixe de novo." >&2
    exit 1
  fi
  echo "Verificação GPG: OK (pacote autêntico da curadoria)."
else
  echo "ERRO: assinatura ou chave pública ausente; sem validação." >&2
  echo "Esperado junto de $(basename "$TARBALL"):" >&2
  echo "  $(basename "$TARBALL").asc  e  $(basename "$PUBASC")" >&2
  echo "O pacote está incompleto. Baixe o repositório inteiro." >&2
  exit 1
fi
# --- instala a loja ----------------------------------------------------
DEST="/opt/nlinux-software"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC/src" "$DEST/"
cp "$SRC/nlinux-software" "$DEST/"
chmod +x "$DEST/nlinux-software"
cat > /usr/local/bin/nlinux-software <<'EOF'
#!/bin/sh
exec /opt/nlinux-software/nlinux-software "$@"
EOF
chmod +x /usr/local/bin/nlinux-software
# --- dados gravaveis, fora do /opt ---------------------------------
# O catalogo e a midia mudam toda vez que a loja sincroniza com o
# GitHub. Em /opt isso pediria root, entao vao para o HOME do
# usuario que instalou, com a propriedade dele.
STORE_USER="${SUDO_USER:-root}"
STORE_HOME="$(getent passwd "$STORE_USER" | cut -d: -f6)"
if [ -n "$STORE_HOME" ] && [ "$STORE_USER" != "root" ]; then
  STORE_DATA="${XDG_DATA_HOME:-$STORE_HOME/.local/share}"
  # migra a pasta de dados do nome antigo (FalconOS) sem sobrescrever
  if [ -d "$STORE_DATA/falconos" ]; then
    mkdir -p "$STORE_DATA/nlinux"
    cp -an "$STORE_DATA/falconos/." "$STORE_DATA/nlinux/" 2>/dev/null || true
    rm -rf "$STORE_DATA/falconos"
  fi
  APP_DATA="$STORE_DATA/nlinux"
  DATA_DIR="$APP_DATA/store"
  mkdir -p "$DATA_DIR"
  if [ ! -d "$DATA_DIR/apps" ]; then
    cp -a "$DEST/src/apps" "$DATA_DIR/apps"
  fi
  # a logo mudou de nome e de conteudo: atualiza a copia gravavel
  rm -f "$DATA_DIR/apps/falconos-logo.png"
  cp -f "$DEST/src/apps/nlinux-logo.png" "$DATA_DIR/apps/nlinux-logo.png"
  # dados de site/cache do WebKit que ficaram com o nome antigo
  rm -rf "$STORE_DATA/falconosstore" "$STORE_HOME/.cache/falconosstore"
  # o chown tem de pegtar a arvore inteira: um 'mkdir -p' como root
  # deixa os diretorios intermediarios do root, e sem dono o usuario
  # nao consegue criar mais nada dentro deles
  chown -R "$STORE_USER" "$APP_DATA"
  echo "Catalogo e midia: $DATA_DIR/apps"
fi
# --- ícone + atalho no menu de aplicativos --------------------------
# remove a instalação anterior com a marca FalconOS (nome antigo)
rm -rf /opt/falconos-software
rm -f /usr/local/bin/falconos-software
rm -f /usr/share/applications/falconosstore.desktop
rm -f /usr/share/applications/falconossoftware.desktop
rm -f /usr/share/pixmaps/falconos-software.png
mkdir -p /usr/share/pixmaps
cp "$DEST/src/apps/nlinux-logo.png" /usr/share/pixmaps/nlinux-software.png
rm -f /usr/share/icons/hicolor/scalable/apps/nlinux-software.svg
rm -f /usr/share/applications/nlinux-software.desktop
rm -f /usr/share/applications/nlinuxsoftware.desktop
cat > /usr/share/applications/nlinuxstore.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=NLinux Software
GenericName=Loja de aplicativos
Comment=Loja de aplicativos do NLinux (distribuição)
Exec=/usr/local/bin/nlinux-software
Icon=nlinux-software
Terminal=false
Categories=Network;Utility;
StartupNotify=true
StartupWMClass=nlinuxstore
X-GNOME-UsesNotifications=false
EOF
(command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications) || true
echo "Instalado: NLinux Software v374 (/usr/local/bin/nlinux-software)"
