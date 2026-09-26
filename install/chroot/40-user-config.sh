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

# Atalho da loja de software na Área de Trabalho do usuário.
if [[ -f /usr/share/applications/nlinuxstore.desktop ]]; then
  mkdir -p "$user_home/Desktop"
  cp -a /usr/share/applications/nlinuxstore.desktop "$user_home/Desktop/"
  chmod +x "$user_home/Desktop/nlinuxstore.desktop" 2>/dev/null || true
  chown -R "$INSTALL_USER:$INSTALL_USER" "$user_home/Desktop" 2>/dev/null || true
fi

# Loja gravável pelo usuário: o app sincroniza o catálogo e compila bytecode
# na própria árvore (/opt/nlinux-software). Sem isso o sync falha com
# "Permission denied" e o __pycache__ não é gravado.
if [[ -d /opt/nlinux-software ]]; then
  chown -R "$INSTALL_USER:$INSTALL_USER" /opt/nlinux-software
  chmod -R u+rwX /opt/nlinux-software
fi

# Marca os atalhos da Área de Trabalho como confiáveis (senão o GNOME cobra
# permissão a cada clique e dá impressão de que o app "não abre").
command -v gio >/dev/null 2>&1 && for d in nlinux-installer nlinuxstore; do
  gio set "$user_home/Desktop/$d.desktop" metadata::trusted true 2>/dev/null || true
done

ok "Configurações do usuário aplicadas."