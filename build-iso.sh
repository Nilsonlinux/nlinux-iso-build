#!/bin/bash
set -euo pipefail

# Metadados editáveis (nome/label/versão da ISO):
#   iso/profiledef.sh

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELENG="/usr/share/archiso/configs/releng"
PROFILE_DIR="$BASE/iso/profile"
WORK_DIR="$BASE/iso/work"
OUT_DIR="$BASE/iso/out"

die() { echo -e "\e[31m[erro]\e[0m $*" >&2; exit 1; }
info() { echo -e "\e[36m[iso]\e[0m $*"; }

run_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

info "Verificando o pacote archiso..."
if ! command -v mkarchiso >/dev/null 2>&1 || [ ! -d "$RELENG" ]; then
  info "Instalando archiso (será solicitada a senha do sudo)..."
  run_root pacman -S --needed --noconfirm archiso
  hash -r
fi
command -v mkarchiso >/dev/null 2>&1 || die "mkarchiso não encontrado após instalar o archiso."
[ -d "$RELENG" ] || die "Perfil releng não encontrado em $RELENG."

info "Montando perfil de build em $PROFILE_DIR"
run_root rm -rf "$PROFILE_DIR" "$WORK_DIR"
mkdir -p "$PROFILE_DIR"
cp -a "$RELENG/." "$PROFILE_DIR/"

info "Tomando posse do perfil (pacote archiso é do usuário root)"
run_root chown -R "$(id -u):$(id -g)" "$PROFILE_DIR"

info "Herdando profiledef do releng e aplicando metadados"
for var in iso_name iso_label iso_publisher iso_application iso_version; do
  val_line="$(grep -E "^${var}=" "$BASE/iso/profiledef.sh")"
  sed -i "s|^${var}=.*|${val_line}|" "$PROFILE_DIR/profiledef.sh"
done
sed -i 's|^)$|  ["/opt/noctalia-installer/install.sh"]="0:0:755"\n  ["/opt/noctalia-installer/web/server.py"]="0:0:755"\n  ["/usr/local/bin/nlinux-installer"]="0:0:755"\n  ["/usr/local/bin/nlinux-installer-gui"]="0:0:755"\n  ["/usr/share/applications/nlinux-installer.desktop"]="0:0:644"\n  ["/usr/share/pixmaps/nlinux-installer.png"]="0:0:644"\n)|' "$PROFILE_DIR/profiledef.sh"

info "Aplicando pacotes customizados do live"
cat "$BASE/iso/packages.live" >> "$PROFILE_DIR/packages.x86_64"

info "Aplicando camada airootfs customizada (autologin + auto-run)"
if [ -d "$BASE/iso/airootfs" ]; then
  cp -a "$BASE/iso/airootfs/." "$PROFILE_DIR/airootfs/"
fi

info "Embutindo o instalador em /opt/noctalia-installer"
INSTALLER_DST="$PROFILE_DIR/airootfs/opt/noctalia-installer"
mkdir -p "$INSTALLER_DST"
cp -a "$BASE/install.sh" "$BASE/install" "$BASE/config" "$BASE/packages" "$BASE/web" "$INSTALLER_DST/"
run_root chown -R "$(id -u):$(id -g)" "$PROFILE_DIR"

info "Embutindo a loja de software em /opt/nlinux-software"
if [[ -d /opt/nlinux-software ]]; then
  SOFT_DST="$PROFILE_DIR/airootfs/opt/nlinux-software"
  mkdir -p "$SOFT_DST"
  cp -a /opt/nlinux-software/. "$SOFT_DST/"
  rm -rf "$SOFT_DST/src/nlinux/__pycache__"
  chmod -R a+rX "$SOFT_DST"
  chmod 0755 "$SOFT_DST/nlinux-software"
  # Ícone da loja para o atalho (.desktop) do menu e do Desktop.
  mkdir -p "$PROFILE_DIR/airootfs/usr/share/pixmaps"
  cp -f "$SOFT_DST/icon.svg" "$PROFILE_DIR/airootfs/usr/share/pixmaps/nlinux-software.svg"
  run_root chown -R "$(id -u):$(id -g)" "$PROFILE_DIR"
else
  info "aviso: /opt/nlinux-software ausente; a loja NÃO será incluída na ISO"
fi

info "Criando o menu de boot 'NLinux ao vivo' (sem opção separada de instalação; o instalador é só web, no desktop do live)"

transform_systemdboot_entries() {
  local ent="$PROFILE_DIR/efiboot/loader/entries"
  [[ -d "$ent" ]] || return 0

  local main="$ent/01-archiso-linux.conf"
  if [[ -f "$main" ]]; then
    sed -i \
      -e 's|^title.*|title    NLinux ao vivo (%ARCH%, UEFI)|' \
      -e 's|^sort-key.*|sort-key 01|' \
      "$main"
    mv "$main" "$ent/01-nlinux-live.conf"
  fi

  local speech="$ent/02-archiso-speech-linux.conf"
  if [[ -f "$speech" ]]; then
    sed -i \
      -e 's|^title.*|title    NLinux ao vivo (%ARCH%, UEFI) - leitor de tela|' \
      -e 's|^sort-key.*|sort-key 02|' \
      "$speech"
    mv "$speech" "$ent/02-nlinux-live-voz.conf"
  fi

  if [[ -f "$ent/03-archiso-memtest86+x64.conf" ]]; then
    sed -i 's|^sort-key.*|sort-key 03|' "$ent/03-archiso-memtest86+x64.conf"
  fi

  local loader="$PROFILE_DIR/efiboot/loader/loader.conf"
  [[ -f "$loader" ]] && sed -i 's|^default .*|default 01-nlinux-live.conf|' "$loader"
}

transform_syslinux_entries() {
  local d="$PROFILE_DIR/syslinux"
  [[ -d "$d" ]] || return 0

  if [[ -f "$d/archiso_head.cfg" ]]; then
    sed -i \
      -e 's|^MENU TITLE .*|MENU TITLE Bem-vindo ao NLinux|' \
      "$d/archiso_head.cfg"
  fi

  if [[ -f "$BASE/splash.png" ]]; then
    cp -f "$BASE/splash.png" "$d/splash.png"
  fi

  local f
  for f in "$d"/archiso_sys-linux.cfg "$d"/archiso_pxe-linux.cfg; do
    [[ -f "$f" ]] || continue
    sed -i \
      -e 's|Arch Linux|NLinux|g' \
      -e 's|NLinux install medium|Iniciar NLinux|g' \
      -e 's|NLinux live medium|Iniciar NLinux|g' \
      "$f"
  done
}

transform_grub_cfg() {
  local grub_cfg="$PROFILE_DIR/grub/grub.cfg"
  [[ -f "$grub_cfg" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  {
    awk '
      /^default=archlinux$/ {
        print "default=nlinux-live"
        next
      }
      /--id .archlinux. \{/ {
        q = sprintf("%c", 39)
        line = $0
        sub(/menuentry "[^"]*"/, "menuentry \"NLinux ao vivo (%ARCH%, ${archiso_platform})\"", line)
        sub(/--id .archlinux./, "--id " q "nlinux-live" q, line)
        print line
        next
      }
      { print }
    ' "$grub_cfg"
  } > "$tmp" && mv "$tmp" "$grub_cfg"
}

transform_systemdboot_entries
transform_grub_cfg
transform_syslinux_entries

mkdir -p "$OUT_DIR"
info "Gerando ISO (pode levar vários minutos e baixar ~1-2GB)..."
run_root mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

run_root rm -rf "$WORK_DIR"
run_root chown -R "$(id -u):$(id -g)" "$OUT_DIR" 2>/dev/null || true

info "ISO gerada com sucesso:"
ls -lh "$OUT_DIR"/*.iso