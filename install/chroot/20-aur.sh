#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
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
# A atividade vale mais que a nota "Instalando o yay": ela diz também o que está
# sendo compilado agora (e o log refina para o crate/arquivo em andamento).
cact web.act.build yay-bin
as_user builder bash -c '
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  cd /tmp/yay-bin
  makepkg --config "$SHARE_DIR/chroot/makepkg-no-debug.conf" -si --noconfirm
'

aur_package_file="$SHARE_DIR/packages/aur.packages"
[[ -r "$aur_package_file" ]] || die "Lista de pacotes AUR indisponível: $aur_package_file"
aur_initial_pkgs=()
aur_dependent_pkgs=()
while IFS= read -r pkg; do
  case "$pkg" in
    umbriel-git|whatsapp-linux-desktop-bin) aur_dependent_pkgs+=("$pkg") ;;
    *) aur_initial_pkgs+=("$pkg") ;;
  esac
done < <(awk 'NF && $1 !~ /^#/ { print $1 }' "$aur_package_file")
((${#aur_initial_pkgs[@]} > 0)) || die "A lista inicial de pacotes AUR está vazia."
((${#aur_dependent_pkgs[@]} > 0)) || die "A lista dependente de pacotes AUR está vazia."

install_aur_packages() {
  # Sem >/dev/null: o download e a compilação da AUR aparecem no log do
  # instalador web (é a etapa mais longa e a que mais parece travada).
  # O painel é avisado do que está sendo compilado: sem isso a etiqueta ficaria
  # presa no nome da etapa durante 20 minutos de compilação em Rust/Meson.
  # A lista vem inteira porque o yay resolve o grupo numa transação só.
  cact web.act.build "$(IFS=', '; echo "${*}")"
  as_user builder bash -c '
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --mflags "--config $SHARE_DIR/chroot/makepkg-no-debug.conf" \
    "$@"
' _ "$@"
}

log "Instalando pacotes AUR iniciais: ${aur_initial_pkgs[*]}"
install_aur_packages "${aur_initial_pkgs[@]}"
log "Instalando pacotes AUR dependentes: ${aur_dependent_pkgs[*]}"
install_aur_packages "${aur_dependent_pkgs[@]}"

log "Removendo usuário temporário builder"
userdel -r builder 2>/dev/null || true
rm -f /etc/sudoers.d/10-noctalia-builder

ok "Pacotes AUR instalados (yay, umbriel-git, noctalia-greeter, xdg-desktop-portal-umbriel-git)."