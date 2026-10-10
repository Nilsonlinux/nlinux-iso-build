#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# Converte uma imagem (JPG/PNG etc.) em splash.png (640x480 PNG) para o
# menu de boot do syslinux (BIOS). O build-iso.sh copia splash.png para o
# perfil automaticamente; basta rodar este script ao trocar a imagem.

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo -e "\e[31m[erro]\e[0m $*" >&2; exit 1; }
info() { echo -e "\e[36m[splash]\e[0m $*"; }

SRC="${1:-$BASE/NLinux.jpg}"

if [[ ! -f "$SRC" ]]; then
  die "Imagem não encontrada: $SRC (passe o caminho como argumento ou salve como $BASE/NLinux.jpg)"
fi

if ! python3 - <<'EOF' 2>/dev/null; then
import PIL
EOF
  die "Pillow (PIL) não instalado. Instale com: sudo pacman -S python-pillow"
fi

info "Gerando splash.png a partir de $SRC"
python3 - "$SRC" "$BASE/splash.png" <<'EOF'
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
w, h = im.size

target_ratio = 4 / 3
cur_ratio = w / h
if cur_ratio > target_ratio:
    nw = int(h * target_ratio)
    x = (w - nw) // 2
    im = im.crop((x, 0, x + nw, h))
else:
    nh = int(w / target_ratio)
    y = (h - nh) // 2
    im = im.crop((0, y, w, y + nh))

im = im.resize((640, 480), Image.LANCZOS)
im.save(dst, 'PNG')
print('ok')
EOF

ls -lh "$BASE/splash.png"
info "Pronto. Rode ./build-iso.sh para incluir o novo splash."