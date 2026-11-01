#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# Converte uma imagem (JPG/PNG etc.) em splash.png (640x480 PNG) para o
# menu de boot do syslinux (BIOS). O build-iso.sh copia splash.png para o
# perfil automaticamente; basta rodar este script ao trocar a imagem.

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo -e "\e[31m[erro]\e[0m $*" >&2; exit 1; }
info() { echo -e "\e[36m[splash]\e[0m $*"; }

SRC="${1:-$BASE/FalconOS.jpg}"

if [[ ! -f "$SRC" ]]; then
  die "Imagem não encontrada: $SRC (passe o caminho como argumento ou salve como $BASE/FalconOS.jpg)"
fi

if ! command -v magick >/dev/null 2>&1; then
  die "ImageMagick (magick) não instalado. Instale com: sudo pacman -S imagemagick"
fi

info "Gerando splash.png a partir de $SRC"
# Redimensiona preenchendo 640x480 (mantém a proporção) e recorta o excedente
# pelo centro. Sem Pillow: o próprio ImageMagick faz o trabalho.
magick "$SRC" -resize '640x480^' -gravity center -extent 640x480 \
  -depth 8 -strip -define png:compression-level=9 "$BASE/splash.png"

ls -lh "$BASE/splash.png"
info "Pronto. Rode ./build-iso.sh para incluir o novo splash."
