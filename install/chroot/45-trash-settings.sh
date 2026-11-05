#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Instala o painel local de "Configurações da Lixeira" do Nautilus.
#
# O Nautilus 51 nao tem tela propria: ele chama org.gnome.Settings
# (gnome-control-center) para abrir o painel privacy/usage. Como a NLinux nao
# instala o gnome-control-center, o botao falhava com
# "org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable".
#
# Este script e chamado em dois lugares:
#   - customize_airootfs.sh, para o ambiente live da ISO;
#   - all.sh, para o sistema instalado (modo online; no offline o rsync do
#     live ja traz os arquivos, e a reinstalacao e idempotente).
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$here/helpers.sh"

src="$here/nlinux-trash-settings"
dest="${DESTDIR:-}"

[[ -f "$src/nautilus-trash-settings" ]] \
  || die "Painel da lixeira ausente: $src/nautilus-trash-settings"
[[ -f "$src/org.gnome.Settings.service" ]] \
  || die "Serviço D-Bus ausente: $src/org.gnome.Settings.service"
[[ -f "$src/org.nlinux.TrashSettings.desktop" ]] \
  || die "Atalho/identidade visual ausente: $src/org.nlinux.TrashSettings.desktop"

log "Instalando o painel local de Configurações da Lixeira (Nautilus)"
install -d -m 0755 "$dest/usr/local/bin" \
  "$dest/usr/local/share/dbus-1/services" \
  "$dest/usr/local/share/applications"
install -m 0755 "$src/nautilus-trash-settings" \
  "$dest/usr/local/bin/nautilus-trash-settings"
install -m 0644 "$src/org.gnome.Settings.service" \
  "$dest/usr/local/share/dbus-1/services/org.gnome.Settings.service"
# O .desktop tem o MESMO nome do app id (org.nlinux.TrashSettings) para o
# dock do Noctalia resolver o icone do Nautilus e o nome da janela.
install -m 0644 "$src/org.nlinux.TrashSettings.desktop" \
  "$dest/usr/local/share/applications/org.nlinux.TrashSettings.desktop"

grep -qx 'Exec=/usr/local/bin/nautilus-trash-settings' \
  "$dest/usr/local/share/dbus-1/services/org.gnome.Settings.service" \
  || die "O serviço D-Bus não aponta para /usr/local/bin/nautilus-trash-settings."
grep -qx 'Icon=org.gnome.Nautilus' \
  "$dest/usr/local/share/applications/org.nlinux.TrashSettings.desktop" \
  || die "O .desktop não usa o ícone do Nautilus."
grep -qx 'NoDisplay=true' \
  "$dest/usr/local/share/applications/org.nlinux.TrashSettings.desktop" \
  && die "O .desktop não pode ser NoDisplay (o Noctalia o ignoraria no dock)."

# Valida a sintaxe sem criar __pycache__ dentro de /usr/local/bin.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$dest/usr/local/bin/nautilus-trash-settings" <<'PY'
import ast
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fp:
    ast.parse(fp.read(), filename=path)
PY
else
  warn "python3 ausente; a sintaxe do painel da lixeira não foi validada."
fi

ok "Configurações da Lixeira instaladas em /usr/local/bin/nautilus-trash-settings"
