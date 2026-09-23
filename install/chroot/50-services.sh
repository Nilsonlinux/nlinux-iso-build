#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Habilitando serviços do sistema"
# No modo offline o sistema é um clone do live: se um pacote (ex.: bluez) não
# estiver no live, a unidade não existe e o `systemctl enable` DEVERIA abortar
# (set -e). Tolerar ausência: avisa e segue, sem derrubar a instalação.
for svc in NetworkManager bluetooth greetd accounts-daemon packagekit; do
  if systemctl enable "$svc" 2>/dev/null; then
    log "habilitado: $svc"
  else
    log "aviso: serviço '$svc' ausente no clone offline; ignorado."
  fi
done

log "Adicionando Flathub ao usuário (App Center do GNOME)"
mkdir -p "/home/$INSTALL_USER/.local/share/flatpak"
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
runuser -u "$INSTALL_USER" -- flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

log "Baixando metadados AppStream do Arch (para o App Center listar programas)"
command -v appstreamcli >/dev/null 2>&1 && appstreamcli refresh --force >/dev/null 2>&1 || true

log "Variáveis de ambiente globais (Wayland + cursor Bibata)"
{
  echo "MOZ_ENABLE_WAYLAND=1"
  echo "ELECTRON_OZONE_PLATFORM_HINT=auto"
  echo "XDG_SESSION_TYPE=wayland"
  echo "XCURSOR_THEME=Bibata-Modern-Ice"
  echo "XCURSOR_SIZE=20"
} >> /etc/environment

log "Sincronização de horário (NTP)"
mkdir -p /etc/systemd/timesyncd.conf.d
printf '[Time]\nNTP=true\n' > /etc/systemd/timesyncd.conf.d/noctalia.conf
systemctl enable systemd-timesyncd

ok "Serviços habilitados."