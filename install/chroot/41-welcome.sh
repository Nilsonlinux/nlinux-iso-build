#!/bin/bash
set -euo pipefail

source "$SHARE_DIR/chroot/helpers.sh"

log "Janela de boas-vindas no primeiro login do sistema instalado"
touch /etc/nlinux-installed

cat > /usr/local/bin/nlinux-welcome <<'EOF'
#!/bin/bash
# Boas-vindas exibida apenas na primeira sessão gráfica do sistema instalado.
# No modo live não faz nada (sai silenciosamente quando /etc/nlinux-installed
# não existe) - usado pelo autostart do Umbriel apenas de forma inócua no live.
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

ok "Boas-vindas configurado."