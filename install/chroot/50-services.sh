#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Habilitando serviços do sistema"
# No modo offline o sistema é um clone do live: se um pacote (ex.: bluez) não
# estiver no live, a unidade não existe e o `systemctl enable` DEVERIA abortar
# (set -e). Tolerar ausência: avisa e segue, sem derrubar a instalação.
for svc in NetworkManager bluetooth greetd accounts-daemon packagekit rtkit-daemon; do
  if systemctl enable "$svc" 2>/dev/null; then
    log "habilitado: $svc"
  else
    log "aviso: serviço '$svc' ausente no clone offline; ignorado."
  fi
done

# Rede: o NetworkManager tem de ser o único gerente. O preset do Arch
# (90-systemd.preset, linhas 32-33) HABILITA o systemd-networkd, e com os dois no
# boot eles disputam o mesmo link: o networkd sobe antes, mexe no sysctl da
# interface por baixo do NetworkManager, e o NetworkManager briga para reassertar
# (aparece no journal como "Foreign process 'NetworkManager' changed sysctl
# .../use_tempaddr"). O live já desliga os dois em customize_airootfs.sh; aqui é
# preciso de novo porque na instalação online quem habilita é o preset, e na
# offline o estado herdado do live não deve ser a única defesa.
log "Deixando o NetworkManager como único gerente de rede"
for svc in systemd-networkd systemd-networkd-wait-online; do
  if systemctl is-enabled "$svc" >/dev/null 2>&1; then
    systemctl disable "$svc" >/dev/null 2>&1 && log "desabilitado: $svc"
  fi
done

# Os dois gerentes ligados ao mesmo tempo é justamente o defeito, então confere
# em vez de confiar que o disable pegou. O motivo do aviso é o preset: ele
# reabilida o networkd em qualquer instalação online futura.
log "Verificando o gerente de rede"
net_nm="$(systemctl is-enabled NetworkManager.service 2>/dev/null || true)"
net_nd="$(systemctl is-enabled systemd-networkd.service 2>/dev/null || true)"
if [[ "$net_nd" == "enabled" ]]; then
  log "aviso: systemd-networkd segue habilitado (NetworkManager=$net_nm); os dois vão disputar o link."
elif [[ "$net_nm" == "enabled" ]]; then
  log "rede: só o NetworkManager habilitado (systemd-networkd=$net_nd)."
else
  log "aviso: nenhum gerente de rede habilitado (NetworkManager=$net_nm, systemd-networkd=$net_nd)."
fi

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