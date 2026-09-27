#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Criando usuário de sistema para o greetd (greeter)"
if ! id -u greeter >/dev/null 2>&1; then
  useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter greeter
fi

log "Criando usuário temporário para build de pacotes AUR"
if ! id -u builder >/dev/null 2>&1; then
  useradd -m -s /bin/bash builder
fi
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-noctalia-builder
chmod 440 /etc/sudoers.d/10-noctalia-builder

log "Instalando yay (yay-bin) via makepkg"
as_user builder bash -c '
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  cd /tmp/yay-bin
  makepkg --config "$SHARE_DIR/chroot/makepkg-no-debug.conf" -si --noconfirm
' >/dev/null

aur_pkgs="$(grep -vE '^\s*(#|$)' "$SHARE_DIR/packages/aur.packages")"
log "Instalando pacotes AUR: $aur_pkgs"
as_user builder bash -c "
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --mflags \"--config $SHARE_DIR/chroot/makepkg-no-debug.conf\" \
    $aur_pkgs
" >/dev/null

log "Removendo usuário temporário builder"
userdel -r builder 2>/dev/null || true
rm -f /etc/sudoers.d/10-noctalia-builder

ok "Pacotes AUR instalados (yay, umbriel-git, noctalia-greeter, xdg-desktop-portal-umbriel-git)."