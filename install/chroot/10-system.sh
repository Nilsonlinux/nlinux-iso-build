#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Fuso horário: $ZONEINFO"
ln -sf "/usr/share/zoneinfo/$ZONEINFO" /etc/localtime

log "Locale: $LOCALE"
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen >/dev/null
echo "LANG=$LOCALE" > /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf

log "Layout de teclado: $KEYMAP"
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

log "Hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname
{
  echo "127.0.0.1   localhost"
  echo "::1         localhost"
  echo "127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME"
} > /etc/hosts

echo "NLinux \r (\l)" > /etc/issue

log "Branding NLinux no /etc/os-release"
cat > /etc/os-release <<'EOF'
NAME="NLinux"
PRETTY_NAME="NLinux"
ID=arch
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com"
LOGO=nlinux
EOF

log "Ativando downloads paralelos e cores no pacman"
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

# multilib: programas 32-bit. A loja do NLinux já esperava por isso — o
# REPO_FILES dela (nlinux-software/src/nlinux/pacman_db.py) lê core, extra e
# multilib — mas sem a seção no pacman.conf o sync db do multilib nunca baixa e
# a loja fica sem os pacotes de lá, incluindo o Steam.
# ATENÇÃO: este mesmo bloco está em install/chroot/10-system.sh, para o sistema
# instalado, e os dois precisam ficar iguais.
log "Habilitando o repositório multilib (programas 32-bit)"
# O releng do archiso deixa o bloco comentado. Descomenta em vez de acrescentar
# uma seção nova, para o arquivo continuar igual ao da wiki do Arch.
sed -i '/^#\[multilib\]$/,/^\[/ s/^#Include/Include/; s/^#\[multilib\]$/[multilib]/' /etc/pacman.conf
# Um pacman novo pode não trazer o bloco comentado: nesse caso acrescentar.
if ! grep -q '^\[multilib\]$' /etc/pacman.conf; then
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
  log "aviso: bloco [multilib] não encontrado no pacman.conf; acrescentado ao fim."
fi
# O multilib exige 'SigLevel = Required DatabaseOptional' em [options]. Já é o
# padrão do Arch, mas descomenta se vier comentado — sem isso o multilib não é
# lido. Por precaução, porque um build novo do pacman pode mudar esse texto.
sed -i 's/^#SigLevel *= *Required *DatabaseOptional/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
log "repos do pacman: $(pacman-conf --repo-list 2>/dev/null | tr '\n' ' ')"
# No modo offline o /etc/pacman.conf vem do live, que já vem com o multilib
# habilitado pelo customize_airootfs.sh; na instalação online quem decide é o
# pacman.conf do pacstrap. Fazer aqui deixa os dois caminhos iguais em vez de
# depender do que o live herdou.

log "Garantindo keyring do pacman (init + populate archlinux)"
if ! pacman-key --list-keys archlinux >/dev/null 2>&1; then
  log "Keyring ausente/incompleto; inicializando..."
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux >/dev/null 2>&1 || true
fi
chmod -R 700 /etc/pacman.d/gnupg 2>/dev/null || true
chown -R root:root /etc/pacman.d/gnupg 2>/dev/null || true

# Garantias p/ instalação rápida offline: /boot copiado do live vem vazio
# (no archiso o /boot do rootfs é vazio; o kernel vive no bootmnt). O vmlinuz
# precisa existir ANTES do mkinitcpio -P (que extrai a versão do kernel).
if [[ ! -f /boot/vmlinuz-linux ]]; then
  log "/boot sem kernel; copiando vmlinuz do pacote linux"
  kdir="/usr/lib/modules/$(uname -r)"
  [[ -f "$kdir/vmlinuz" ]] || kdir="$(ls -d /usr/lib/modules/linux* 2>/dev/null | sort -V | tail -1)"
  [[ -f "$kdir/vmlinuz" ]] || exit 1
  cp -f "$kdir/vmlinuz" /boot/vmlinuz-linux
fi

log "Configurando initramfs para sd-encrypt (quando LUKS)"
# O /etc/mkinitcpio.d/linux.preset clonado do live é o do archiso e referencia
# /etc/mkinitcpio.conf.d/archiso.conf (inexistente/ilegível no disco instalado)
# → mkinitcpio -P falha com "Invalid option -c ... must be readable". Regenera o
# preset padrão e remove o drop-in do archiso.
rm -f /etc/mkinitcpio.d/*.preset
rm -rf /etc/mkinitcpio.conf.d
cat > /etc/mkinitcpio.d/linux.preset <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-linux.img"
default_options=""
fallback_image="/boot/initramfs-linux-fallback.img"
fallback_options="-S autodetect"
EOF
encrypt_hook=""
if [[ "$USE_LUKS" == "1" ]]; then
  encrypt_hook="sd-encrypt "
fi
sed -i "s|^HOOKS=(.*)|HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block ${encrypt_hook}filesystems fsck)|" /etc/mkinitcpio.conf
if ! mkinitcpio -P; then
  warn "mkinitcpio falhou com autodetect; tentando gerar initramfs com todos os módulos."
  fallback_config="$(mktemp /tmp/nlinux-mkinitcpio.XXXXXX)"
  if ! sed -E '/^HOOKS=/s/(^|[[:space:]])autodetect([[:space:])]|$)/\1\2/g' \
    /etc/mkinitcpio.conf > "$fallback_config"; then
    rm -f "$fallback_config"
    die "Não foi possível preparar a configuração alternativa do mkinitcpio."
  fi

  if mkinitcpio -k /boot/vmlinuz-linux -c "$fallback_config" \
      -g /boot/initramfs-linux.img &&
    mkinitcpio -k /boot/vmlinuz-linux -c "$fallback_config" \
      -g /boot/initramfs-linux-fallback.img -S autodetect; then
    rm -f "$fallback_config"
    warn "Initramfs gerado sem autodetect; a configuração original foi mantida."
  else
    rm -f "$fallback_config"
    die "mkinitcpio falhou também sem autodetect; consulte o log do instalador."
  fi
fi

log "Swap via zram"
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF

log "Criando usuários e senhas"
echo "root:$ROOT_PASS" | chpasswd

if ! id -u "$INSTALL_USER" >/dev/null 2>&1; then
  useradd -m -G wheel,audio,video,input,storage,network -s /usr/bin/fish "$INSTALL_USER"
fi
echo "$INSTALL_USER:$INSTALL_USER_PASS" | chpasswd

if ! grep -q '^%wheel' /etc/sudoers; then
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
fi

log "Instalando bootloader (systemd-boot)"
bootctl --esp-path=/boot install >/dev/null

# Fallback obrigatório p/ firmwares sem entrada NVRAM ("UEFI: <disco>").
mkdir -p /boot/EFI/BOOT
cp -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 4
console-mode max
editor no
auto-entries yes
EOF

root_uuid="$(findmnt -no UUID /)"

microcode_initrd=""
case "$MICROCODE" in
  intel) [[ -f /boot/intel-ucode.img ]] && microcode_initrd="initrd /intel-ucode.img" ;;
  amd)   [[ -f /boot/amd-ucode.img ]] && microcode_initrd="initrd /amd-ucode.img" ;;
esac

options="root=UUID=$root_uuid rw"
if [[ "$FS_TYPE" == "btrfs" ]]; then
  options="$options rootflags=subvol=/@"
fi
if [[ "$USE_LUKS" == "1" && -n "${LUKS_UUID:-}" ]]; then
  options="$options rd.luks.name=$LUKS_UUID=cryptroot rd.luks.options=discard"
fi

cat > /boot/loader/entries/arch.conf <<EOF
title   NLinux
linux   /vmlinuz-linux
$microcode_initrd
initrd  /initramfs-linux.img
options $options
EOF

ok "Sistema base configurado e bootloader instalado."