#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Janela de boas-vindas no primeiro login do sistema instalado"
INSTALLED_AT="$(date -Is)"
mkdir -p /etc
printf '%s\n' "$INSTALLED_AT" > /etc/nlinux-installed

WELCOME_SRC="$SHARE_DIR/chroot/nlinux-welcome"
WELCOME_DST="/usr/share/nlinux-welcome"

# --- App GTK (mesma stack da loja: python-gobject + GTK3) + asset ---
log "Instalando o app de boas-vindas em $WELCOME_DST"
install -d -m 0755 "$WELCOME_DST"
install -d -m 0755 /usr/share/applications
install -d -m 0755 /usr/share/icons/hicolor/256x256/apps
if [[ -d "$WELCOME_SRC" ]]; then
  install -m 0644 "$WELCOME_SRC/welcome.py" "$WELCOME_DST/welcome.py"
  install -m 0644 "$WELCOME_SRC/welcome-logo.png" "$WELCOME_DST/welcome-logo.png"
  install -m 0644 "$WELCOME_SRC/github.png" "$WELCOME_DST/github.png"
  install -m 0644 "$WELCOME_SRC/nlinux-welcome.desktop" \
    /usr/share/applications/nlinux-welcome.desktop
else
  die "Pasta de assets da boas-vindas ausente: $WELCOME_SRC"
fi
if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$WELCOME_DST/welcome.py" 2>/dev/null || true
fi

# --- /etc/nlinux-release: identidade da distro (nome, versão, data) -----
# No modo offline a identidade e a data do BUILD já vieram do live; no modo
# online elas são geradas aqui. A data de INSTALAÇÃO é sempre gravada nesta
# etapa, pois é ela que o NLinux Welcome mostra em "Data de instalação" (o
# arquivo copiado do live carrega apenas a data em que a ISO foi gerada).
if [[ ! -f /etc/nlinux-release ]]; then
  log "Gravando /etc/nlinux-release (identidade da distro)"
  {
    echo 'NLINUX_NAME="NLinux"'
    echo "NLINUX_VERSION=\"$(date +%Y.%m.%d)\""
    echo "NLINUX_BUILT=\"$INSTALLED_AT\""
  } > /etc/nlinux-release
fi

log "Registrando a data de instalação em /etc/nlinux-release"
sed -i '/^NLINUX_INSTALLED=/d' /etc/nlinux-release
printf 'NLINUX_INSTALLED="%s"\n' "$INSTALLED_AT" >> /etc/nlinux-release

# --- Atalho do app no menu ---------------------------------------------
chmod 0644 /usr/share/applications/nlinux-welcome.desktop
mkdir -p /usr/share/pixmaps
install -m 0644 "$WELCOME_DST/welcome-logo.png" /usr/share/pixmaps/nlinux-welcome.png
install -m 0644 "$WELCOME_DST/welcome-logo.png" \
  /usr/share/icons/hicolor/256x256/apps/nlinux-welcome.png
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

# --- Launcher (autostart do Umbriel / atalho) --------------------------
cat > /usr/local/bin/nlinux-welcome <<'EOF'
#!/bin/bash
# Boas-vindas NLinux: janela GTK (live e sistema instalado).
#   --menu   -> abre sempre (atalho do menu), marcando como visto ao final.
#   padrão   -> abre uma vez por usuário (marcador ~/.config/nlinux-welcome-v1).
if [[ -f /usr/share/nlinux-welcome/welcome.py ]] && command -v python3 >/dev/null 2>&1; then
  exec python3 /usr/share/nlinux-welcome/welcome.py "$@"
fi
zenity --info --title="Bem-vindo ao NLinux" --text="Bem-vindo ao NLinux!" 2>/dev/null || true
EOF
chmod 0755 /usr/local/bin/nlinux-welcome

ok "Boas-vindas configurado."