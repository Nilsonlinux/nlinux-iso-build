#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Janela de boas-vindas no primeiro login do sistema instalado"
touch /etc/falconos-installed

WELCOME_SRC="$SHARE_DIR/chroot/falconos-welcome"
WELCOME_DST="/usr/share/falconos-welcome"

# --- App GTK (mesma stack da loja: python-gobject + GTK3) + asset ---
log "Instalando o app de boas-vindas em $WELCOME_DST"
install -d -m 0755 "$WELCOME_DST"
install -d -m 0755 /usr/share/applications
install -d -m 0755 /usr/share/icons/hicolor/256x256/apps
if [[ -d "$WELCOME_SRC" ]]; then
  install -m 0644 "$WELCOME_SRC/welcome.py" "$WELCOME_DST/welcome.py"
  install -m 0644 "$WELCOME_SRC/welcome-logo.png" "$WELCOME_DST/welcome-logo.png"
  install -m 0644 "$WELCOME_SRC/github.png" "$WELCOME_DST/github.png"
  install -m 0644 "$WELCOME_SRC/falconos-welcome.desktop" \
    /usr/share/applications/falconos-welcome.desktop
else
  die "Pasta de assets da boas-vindas ausente: $WELCOME_SRC"
fi
if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$WELCOME_DST/welcome.py" 2>/dev/null || true
fi

# --- /etc/falconos-release: identidade da distro (nome, versão, data) -----
# No modo offline a data do build já veio do live; o que falta (modo online)
# é gravado aqui com a data da instalação.
if [[ ! -f /etc/falconos-release ]]; then
  log "Gravando /etc/falconos-release (data da instalação)"
  {
    echo 'FALCONOS_NAME="FalconOS"'
    echo "FALCONOS_VERSION=\"$(date +%Y.%m.%d)\""
    echo "FALCONOS_BUILT=\"$(date -Is)\""
  } > /etc/falconos-release
fi

# --- Atalho do app no menu e na área de trabalho do usuário ------------
chmod 0644 /usr/share/applications/falconos-welcome.desktop
mkdir -p /usr/share/pixmaps
install -m 0644 "$WELCOME_DST/welcome-logo.png" /usr/share/pixmaps/falconos-welcome.png
install -m 0644 "$WELCOME_DST/welcome-logo.png" \
  /usr/share/icons/hicolor/256x256/apps/falconos-welcome.png
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

# --- Launcher (autostart do Umbriel / atalho) --------------------------
cat > /usr/local/bin/falconos-welcome <<'EOF'
#!/bin/bash
# Boas-vindas FalconOS: janela GTK (live e sistema instalado).
#   --menu   -> abre sempre (atalho do menu), marcando como visto ao final.
#   padrão   -> abre uma vez por usuário (marcador ~/.config/falconos-welcome-v1).
if [[ -f /usr/share/falconos-welcome/welcome.py ]] && command -v python3 >/dev/null 2>&1; then
  exec python3 /usr/share/falconos-welcome/welcome.py "$@"
fi
zenity --info --title="Bem-vindo ao FalconOS" --text="Bem-vindo ao FalconOS!" 2>/dev/null || true
EOF
chmod 0755 /usr/local/bin/falconos-welcome

ok "Boas-vindas configurado."