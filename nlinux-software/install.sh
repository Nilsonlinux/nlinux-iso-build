#!/bin/sh
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
TARBALL="$(ls "$SRC"/nlinux-software-v*.tar.gz "$SRC"/../nlinux-software-v*.tar.gz 2>/dev/null | head -n1)"
if [ -n "$TARBALL" ] && [ -f "$TARBALL.asc" ]; then
  gpg --batch --import "$SRC/nlinux-software_pub.asc" >/dev/null 2>&1
  if ! gpg --batch --verify "$TARBALL.asc" "$TARBALL" >/dev/null 2>&1; then
    echo "ERRO: assinatura GPG do pacote INVÁLIDA. Instalação abortada." >&2
    echo "O arquivo (ou o repositório) pode ter sido adulterado. Baixe de novo." >&2
    exit 1
  fi
  echo "Verificação GPG: OK (pacote autêntico da curadoria)."
else
  echo "Aviso: assinatura (.asc) não encontrada junto do pacote; sem validação."
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
# --- ícone + atalho no menu de aplicativos --------------------------
cat > "$DEST/icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1f6feb"/>
      <stop offset="1" stop-color="#0d3b8f"/>
    </linearGradient>
    <linearGradient id="bag" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#58c25e"/>
      <stop offset="1" stop-color="#2ea043"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="24" fill="url(#bg)"/>
  <rect x="8" y="8" width="112" height="112" rx="24" fill="none" stroke="#12233f" stroke-width="4"/>
  <path d="M8 74 C34 54 66 46 120 40 L120 34 C64 38 26 50 8 66 Z" fill="#ffffff" opacity="0.08"/>
  <path d="M48 40 C48 30 58 24 64 24 C70 24 80 30 80 40" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round"/>
  <path d="M40 40 H88 L96 84 Q96 98 86 98 H42 Q32 98 32 84 Z" fill="url(#bag)"/>
  <path d="M64 40 L64 96" stroke="#1a7a2e" stroke-width="3" opacity="0.35"/>
  <ellipse cx="46" cy="60" rx="10" ry="7" fill="#ffffff" opacity="0.3"/>
  <rect x="55" y="62" width="18" height="18" rx="5" fill="#ffffff"/>
  <path d="M63.5 66 V72 L60 72 L64 77 L68 72 L64.5 72 V66 Z" fill="#2ea043"/>
  <rect x="59" y="78" width="10" height="2" rx="1" fill="#2ea043"/>
</svg>
SVG
mkdir -p /usr/share/icons/hicolor/scalable/apps
cp "$DEST/icon.svg" /usr/share/icons/hicolor/scalable/apps/nlinux-software.svg
(command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t /usr/share/icons/hicolor) || true
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
echo "Instalado: NLinux Software v113 (/usr/local/bin/nlinux-software)"
