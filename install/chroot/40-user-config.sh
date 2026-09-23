#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

user_home="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

log "Configurando $INSTALL_USER ($user_home)"

# Layout XKB derivado do KEYMAP do instalador (br-abnt2 -> br, us -> us, ...)
xkb_layout="${KEYMAP%%-*}"

if [[ -d "$SHARE_DIR/config/.config" ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$SHARE_DIR/config/.config"/}"
    target="$user_home/.config/$rel"
    mkdir -p "$(dirname "$target")"
    if grep -q '__KEYBOARD_LAYOUT__' "$f"; then
      sed "s/__KEYBOARD_LAYOUT__/$xkb_layout/g" "$f" > "${target%.tpl}"
    else
      cp -a "$f" "${target%.tpl}"
    fi
  done < <(find "$SHARE_DIR/config/.config" -type f -print0)
fi

# Ícones/cursor (.local): cópia íntegra (binários e symlinks preservados)
if [[ -d "$SHARE_DIR/config/.local" ]]; then
  mkdir -p "$user_home/.local"
  cp -a "$SHARE_DIR/config/.local/." "$user_home/.local/"
fi

chown -R "$INSTALL_USER:$INSTALL_USER" "$user_home/.config" "$user_home/.local" 2>/dev/null || true

ok "Configurações do usuário aplicadas."