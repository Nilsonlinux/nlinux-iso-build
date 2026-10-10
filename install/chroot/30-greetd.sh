#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

if [[ ! -x /usr/bin/noctalia-greeter-session ]]; then
  die "noctalia-greeter-session não encontrado. Pacote AUR não foi instalado?"
fi

log "Escrevendo /etc/greetd/config.toml (usa o noctalia-greeter)"
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session -- --session umbriel"
user = "greeter"
EOF

log "Executando setup do noctalia-greeter (PAM, diretórios e estado)"
NOCTALIA_GREETER_SESSION_BIN=/usr/bin/noctalia-greeter-session \
  /usr/share/noctalia-greeter/setup_greeter_system.sh || true

chmod 0750 /var/lib/noctalia-greeter 2>/dev/null || true

ok "greetd + noctalia-greeter configurado (sessão padrão: umbriel)."