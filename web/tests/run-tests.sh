#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Roda as suítes do instalador web (painel, CSS e ponta a ponta).
#
#   web/tests/run-tests.sh              # o que der para rodar
#   web/tests/run-tests.sh --install    # baixa o node_modules antes (precisa de rede)
#
# As duas suítes Python rodam em qualquer máquina com Python 3, sem instalar
# nada e sem root. As duas de JavaScript precisam de node + jsdom/css-tree: sem
# node (ou sem o `npm install`) o script diz o que falta e segue com as outras
# — nesse caso nada checa o app.js nem o style.css, então vale instalar.
set -u
cd "$(dirname "$0")"
RAIZ="$(cd ../.. && pwd)"

py="${PYTHON:-python3}"
falhou=0
rodadas=0

run() {
  # run <rótulo> <comando...>
  local rotulo="$1"; shift
  echo
  echo "── ${rotulo} "
  if "$@"; then
    return 0
  fi
  echo "   FALHOU: ${rotulo}"
  falhou=1
  return 1
}

# Node e dependências: opcional.
tem_js=0
if command -v node >/dev/null 2>&1 && [[ -d node_modules ]]; then
  tem_js=1
fi

if [[ "${1:-}" == "--install" ]]; then
  echo "npm install em web/tests (precisa de rede)…"
  if command -v npm >/dev/null 2>&1; then
    npm install --no-audit --no-fund || { echo "npm install falhou"; exit 1; }
    tem_js=1
  else
    echo "npm não encontrado: instale o node (>= 18) para as suítes de JavaScript"
  fi
fi

echo "Repositório: ${RAIZ}"
echo "Python:      $("$py" --version 2>&1)"

run "servidor (anel, atividade, plano, traduções)" "$py" server_test.py
rodadas=$((rodadas + 1))
run "ponta a ponta (log -> servidor -> SSE)" "$py" e2e_test.py
rodadas=$((rodadas + 1))

if (( tem_js )); then
  run "painel no jsdom (app.js)" node client_test.js
  rodadas=$((rodadas + 1))
  run "css (style.css + app.js)" node css_test.js
  rodadas=$((rodadas + 1))
else
  echo
  echo "── suítes de JavaScript puladas (precisam de node + jsdom/css-tree)"
  echo "   node:    $(command -v node || echo não encontrado)"
  if [[ -d node_modules ]]; then
    echo "   npm install  # ou rode: web/tests/run-tests.sh --install"
  else
    echo "   cd web/tests && npm install"
  fi
fi

echo
if (( falhou )); then
  echo "FALHOU (${rodadas} suítes rodadas)"
  exit 1
fi
if (( tem_js )); then
  echo "ok: ${rodadas} suítes, todas verdes"
else
  echo "ok: ${rodadas} suítes verdes (faltam as 2 de JavaScript)"
fi
