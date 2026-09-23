#!/usr/bin/env bash
# Rodado pelo mkarchiso dentro do chroot do live system durante o build
# (mecanismo oficial "customize_airootfs.sh"). Prepara o ambiente ao vivo
# para o modo "Experimentar": pacotes AUR, greetd + noctalia-greeter e o
# usuário "nlinux" com o desktop Umbriel + Noctalia.
set -euo pipefail

log() { echo -e "\e[36m[nlinux-live]\e[0m $*"; }
die() { echo -e "\e[31m[nlinux-live][erro]\e[0m $*" >&2; exit 1; }

log "==> Iniciando configuração do live system"

# Dentro do chroot do archiso a raiz '/' não é um mountpoint, então o check de
# espaço do pacman falha sempre ("could not determine root mount point" →
# "not enough free disk space"). Desativa o CheckSpace durante o build AUR e
# restaura o estado original ao final.
if grep -q '^CheckSpace$' /etc/pacman.conf; then
  sed -i 's/^CheckSpace$/#CheckSpace/' /etc/pacman.conf
  trap 'sed -i "s/^#CheckSpace$/CheckSpace/" /etc/pacman.conf' EXIT
fi

# O mkarchiso instala os pacotes sem inicializar a keyring do pacman no chroot
# (pacstrap com -G e sem -K). Qualquer `pacman -S` de pacote de repositório —
# como faz o yay para instalar as dependências dos AUR — falha então com
# "Public keyring not found" / "keyring is not writable". Inicializa e popula
# aqui (offline: as chaves vêm do pacote archlinux-keyring já instalado).
log "Inicializando keyring do pacman (pacman-key --init + populate)"
if [[ ! -d /etc/pacman.d/gnupg ]] || ! pacman-key --list-keys archlinux >/dev/null 2>&1; then
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux >/dev/null 2>&1 || true
fi
chmod -R 700 /etc/pacman.d/gnupg 2>/dev/null || true
chown -R root:root /etc/pacman.d/gnupg 2>/dev/null || true

# O packagekit instala um hook alpm pós-transação ("Refreshing PackageKit...")
# que reinicia o packagekit via D-Bus — inexistente dentro do chroot do build.
# Quando um pacote AUR dispara esse hook, o pacman falha (exit status 4) e o
# yay aborta a instalação. Desativa o hook antes de qualquer transação.
log "Desativando hook alpm do PackageKit (sem D-Bus em chroot)"
for h in /usr/share/libalpm/hooks/*.hook /etc/pacman.d/hooks/*.hook; do
  [[ -e "$h" ]] || continue
  grep -qil "packagekit" "$h" && { log "removido: $h"; rm -f "$h"; } || true
done

# A fase `check` de pacotes AUR Rust (xwayland-satellite-git, umbriel-git) roda
# `cargo test` que comanda um display X/wayland — inexistente em chroot — e o
# build fica travado (ex.: "test copy_from_x11 ..."). O makepkg não tem opção
# em makepkg.conf para isso; o `--nocheck` é repassado via --mflags do yay nos
# passos abaixo (e via --nocheck no makepkg do yay-bin).
log "Nota: fase check desativada via --mflags '--nocheck' nos builds do yay"

# --- Pacotes AUR: umbriel-git, xdg-desktop-portal-umbriel-git, noctalia-greeter
log "Criando usuário temporário para build de pacotes AUR"
useradd -m -s /bin/bash builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-nlinux-builder
chmod 440 /etc/sudoers.d/10-nlinux-builder

log "Instalando yay (yay-bin) via makepkg"
runuser -u builder -- bash -c '
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  cd /tmp/yay-bin
  makepkg -si --noconfirm --nocheck
'

log "Instalando pacotes AUR — etapa 1 (dependências: greeter, portal, xwayland)"
# Nota: o umbriel-git depende do xdg-desktop-portal-umbriel-git. Se ambos forem
# alvos explícitos no MESMO `yay -S`, o yay builda tudo mas só instala no final,
# e o makepkg do umbriel falha com "Could not resolve all dependencies" (o portal
# ainda não existe instalado). Por isso o portal/greeter/xwayland vão primeiro e
# o umbriel-git em um segundo yay, já com a dependência instalada.
runuser -u builder -- bash -c '
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --answerdiff None --answerclean None --answeredit None --answerupgrade None \
    --mflags "--nocheck" \
    noctalia-greeter xdg-desktop-portal-umbriel-git xwayland-satellite-git
'

log "Instalando pacotes AUR — etapa 2 (umbriel-git + apps, com o portal já instalado)"
runuser -u builder -- bash -c '
  export GOCACHE=/tmp/gocache CARGO_HOME=/tmp/cargo
  yay -S --noconfirm --needed \
    --answerdiff None --answerclean None --answeredit None --answerupgrade None \
    --mflags "--nocheck" \
    umbriel-git whatsapp-linux-desktop-bin
'

log "Removendo usuário temporário builder"
userdel -r builder 2>/dev/null || true
rm -f /etc/sudoers.d/10-nlinux-builder
rm -rf /tmp/yay-bin /tmp/gocache /tmp/cargo

# --- greetd + noctalia-greeter
[[ -x /usr/bin/noctalia-greeter-session ]] || die "noctalia-greeter-session não encontrado."

log "Criando usuário de sistema do greetd (greeter)"
id -u greeter >/dev/null 2>&1 || useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter greeter

log "Escrevendo /etc/greetd/config.toml (vt 7, noctalia-greeter)"
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 7

[default_session]
command = "/usr/bin/noctalia-greeter-session -- --session umbriel"
user = "greeter"
EOF

log "Executando setup do noctalia-greeter (PAM, diretórios e estado)"
NOCTALIA_GREETER_SESSION_BIN=/usr/bin/noctalia-greeter-session \
  /usr/share/noctalia-greeter/setup_greeter_system.sh || true

chmod 0750 /var/lib/noctalia-greeter 2>/dev/null || true

# --- Usuário do live (login no greeter: nlinux / nlinux)
log "Criando usuário 'nlinux' (grupos de mídia/input/sudo)"
id nlinux >/dev/null 2>&1 || useradd -m -G wheel,video,input,audio,storage,network,users -s /usr/bin/fish nlinux
echo "nlinux:nlinux" | chpasswd

# --- Sudo para o usuário do live (senha: nlinux)
log "Adicionando usuário 'nlinux' ao sudoers (sem senha — instalador web live)"
echo 'nlinux ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-nlinux-user
chmod 440 /etc/sudoers.d/10-nlinux-user

# --- Rede no live: NetworkManager assume as interfaces
log "Habilitando NetworkManager e desativando o systemd-networkd do releng"
systemctl enable NetworkManager 2>/dev/null || true
systemctl disable systemd-networkd 2>/dev/null || true
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# --- GNOME Software: habilita PackageKit e adiciona o Flathub ao usuário
log "Habilitando PackageKit, metadados AppStream e Flathub (gnome-software)"
systemctl enable packagekit 2>/dev/null || true
mkdir -p /home/nlinux/.local/share/flatpak
runuser -u nlinux -- flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
if command -v appstreamcli >/dev/null 2>&1; then
  log "Baixando metadados AppStream do Arch (para a loja listar programas)..."
  appstreamcli refresh --force >/dev/null 2>&1 || log "aviso: refresh AppStream falhou (sem rede?)"
fi

# --- Configurações do Umbriel e ícones (cursor) para o desktop no live
log "Configurando dotfiles do usuário nlinux (umbriel, Bibata)"
mkdir -p /home/nlinux/.config
if [[ -d /opt/noctalia-installer/config/.config ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#/opt/noctalia-installer/config/.config/}"
    target="/home/nlinux/.config/$rel"
    mkdir -p "$(dirname "$target")"
    if grep -q '__KEYBOARD_LAYOUT__' "$f"; then
      sed 's/__KEYBOARD_LAYOUT__/us/g' "$f" > "${target%.tpl}"
    else
      cp -a "$f" "${target%.tpl}"
    fi
  done < <(find /opt/noctalia-installer/config/.config -type f -print0)
fi

# Ícones/cursor (.local): cópia íntegra (binários e symlinks preservados)
if [[ -d /opt/noctalia-installer/config/.local ]]; then
  mkdir -p /home/nlinux/.local
  cp -a /opt/noctalia-installer/config/.local/. /home/nlinux/.local/
fi
chown -R nlinux:nlinux /home/nlinux/.config /home/nlinux/.local 2>/dev/null || true

# --- PipeWire/WirePlumber no live: habilita a session de usuário do 'nlinux'
# (o umbriel sobe via systemd --user, então basta ativar os sockets/services
# no default.target da sessão do usuário)
log "Habilitando PipeWire + WirePlumber na sessão do usuário nlinux"
mkdir -p /home/nlinux/.config/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/pipewire.socket \
  /home/nlinux/.config/systemd/user/default.target.wants/pipewire.socket
ln -sf /usr/lib/systemd/user/pipewire-pulse.socket \
  /home/nlinux/.config/systemd/user/default.target.wants/pipewire-pulse.socket
ln -sf /usr/lib/systemd/user/wireplumber.service \
  /home/nlinux/.config/systemd/user/default.target.wants/wireplumber.service
chown -R nlinux:nlinux /home/nlinux/.config/systemd 2>/dev/null || true

log "Variáveis de ambiente do live (Wayland + cursor Bibata)"
{
  echo "MOZ_ENABLE_WAYLAND=1"
  echo "ELECTRON_OZONE_PLATFORM_HINT=auto"
  echo "XDG_SESSION_TYPE=wayland"
  echo "XCURSOR_THEME=Bibata-Modern-Ice"
  echo "XCURSOR_SIZE=20"
} >> /etc/environment

# --- Atalho do instalador no menu (e na Área de Trabalho do live)
log "Instalando atalho 'Instalar NLinux' (menu + Desktop do live)"
if [[ -f /usr/share/applications/nlinux-installer.desktop ]]; then
  mkdir -p /home/nlinux/Desktop
  cp -a /usr/share/applications/nlinux-installer.desktop /home/nlinux/Desktop/
  chmod +x /home/nlinux/Desktop/nlinux-installer.desktop 2>/dev/null || true
fi
chown -R nlinux:nlinux /home/nlinux/Desktop 2>/dev/null || true

# --- nlinux-welcome: inócuo no live (exige /etc/nlinux-installed), presente para
# o autostart do Umbriel do live não reclamar; só mostra janela no sistema instalado.
log "Instalando nlinux-welcome (inócuo no live)"
cat > /usr/local/bin/nlinux-welcome <<'EOF'
#!/bin/bash
marker="${HOME}/.config/nlinux-welcome-v1"
[[ -e /etc/nlinux-installed ]] || exit 0
[[ -e "$marker" ]] && exit 0
zenity --info \
  --title="Bem-vindo ao NLinux" \
  --text="Seja bem-vindo ao seu novo sistema NLinux!

Instalação concluída com sucesso.

  * App Center para instalar programas
  * Terminais:  kitty  (Mod+T / Mod+Shift+T)
  * Shell padrão: fish
  * Compositor Umbriel + Noctalia
" \
  --width=460 --height=260 2>/dev/null
touch "$marker"
EOF
chmod 0755 /usr/local/bin/nlinux-welcome

log "==> Live system configurado. Desktop disponível via greetd (usuário nlinux)."