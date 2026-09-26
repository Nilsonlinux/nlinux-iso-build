#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Janela de boas-vindas no primeiro login do sistema instalado"
touch /etc/nlinux-installed

WELCOME_SRC="$SHARE_DIR/chroot/nlinux-welcome"
WELCOME_DST="/usr/share/nlinux-welcome"

# --- App GTK (mesma stack da loja: python-gobject + GTK3) + asset ---
log "Instalando o app de boas-vindas em $WELCOME_DST"
install -d -m 0755 "$WELCOME_DST"
if [[ -d "$WELCOME_SRC" ]]; then
  install -m 0644 "$WELCOME_SRC/welcome.py" "$WELCOME_DST/welcome.py"
  install -m 0644 "$WELCOME_SRC/logo.png"   "$WELCOME_DST/logo.png"
  install -m 0644 "$WELCOME_SRC/github.png" "$WELCOME_DST/github.png"
else
  die "Pasta de assets da boas-vindas ausente: $WELCOME_SRC"
fi
if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$WELCOME_DST/welcome.py" 2>/dev/null || true
fi

# --- /etc/nlinux-release: identidade da distro (nome, versão, data) -----
# No modo offline a data do build já veio do live; o que falta (modo online)
# é gravado aqui com a data da instalação.
if [[ ! -f /etc/nlinux-release ]]; then
  log "Gravando /etc/nlinux-release (data da instalação)"
  {
    echo 'NILINUX_NAME="NLinux"'
    echo "NILINUX_VERSION=\"$(date +%Y.%m.%d)\""
    echo "NILINUX_BUILT=\"$(date -Is)\""
  } > /etc/nlinux-release
fi

# --- Atalho na área de trabalho do usuário (app store-installed) ------
mkdir -p /usr/share/applications
cat > /usr/share/applications/nlinux-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=nlinux-welcome
GenericName=Boas-vindas do NLinux
Comment=Janela de boas-vindas e informações da distro
Comment[en]=NLinux welcome window and distro info
Comment[es]=Ventana de bienvenida e información de la distro
Comment[fr]=Fenêtre de bienvenue et infos de la distro
Comment[de]=NLinux-Willkommensfenster und Distro-Infos
Comment[it]=Finestra di benvenuto e info sulla distro
Comment[ja]=NLinux のウェルカムウィンドウとディストロ情報
Exec=/usr/local/bin/nlinux-welcome --menu
Icon=nlinux-welcome
Terminal=false
Categories=System;Utility;
StartupNotify=false
EOF
chmod 0644 /usr/share/applications/nlinux-welcome.desktop
mkdir -p /usr/share/pixmaps
install -m 0644 "$WELCOME_DST/logo.png" /usr/share/pixmaps/nlinux-welcome.png

# --- Launcher (autostart do Umbriel / atalho) --------------------------
cat > /usr/local/bin/nlinux-welcome <<'EOF'
#!/bin/bash
# Boas-vindas NLinux: janela GTK no primeiro login do sistema instalado.
# No live (sem /etc/nlinux-installed) sai em silêncio — o autostart do
# Umbriel o chama também no live, de forma inócua.
marker="${HOME}/.config/nlinux-welcome-v1"
[[ -e /etc/nlinux-installed ]] || exit 0
[[ -e "$marker" ]] && exit 0
if [[ -f /usr/share/nlinux-welcome/welcome.py ]] && command -v python3 >/dev/null 2>&1; then
  python3 /usr/share/nlinux-welcome/welcome.py
else
  zenity --info --title="Bem-vindo ao NLinux" --text="Bem-vindo ao NLinux!" 2>/dev/null || true
fi
touch "$marker"
EOF
chmod 0755 /usr/local/bin/nlinux-welcome

ok "Boas-vindas configurado."