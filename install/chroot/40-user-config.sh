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

# Cria as pastas XDG padrão (Desktop, Documentos, Downloads, ...) no idioma do
# sistema para o Nautilus mostrar na lista lateral já no primeiro login.
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  LANG="$LOCALE" runuser -u "$INSTALL_USER" -- xdg-user-dirs-update 2>/dev/null \
    || log "xdg-user-dirs-update falhou; criando pastas padrão manualmente"
else
  log "xdg-user-dirs-update não instalado; criando pastas padrão manualmente"
fi
if [[ ! -f "$user_home/.config/user-dirs.dirs" ]]; then
  for d in Desktop Documents Downloads Music Pictures Public Templates Videos Projetos; do
    install -d -o "$INSTALL_USER" -g "$INSTALL_USER" "$user_home/$d"
  done
fi

ok "Configurações do usuário aplicadas."