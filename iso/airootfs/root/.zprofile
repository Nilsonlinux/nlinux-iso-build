# Live NLinux: boot direto para o desktop ao vivo. A instalação é
# EXCLUSIVAMENTE pelo instalador web (app "Instalar NLinux" no menu /
# Área de Trabalho do live). Sem TUI / prompt de instalação no console.
echo
echo "==> NLinux ao vivo."
echo "    Instalar: app 'Instalar NLinux' no menu do desktop (instalador web)."
echo "    Terminais no desktop:  Mod+T  (kitty)   Mod+Shift+T  (ghostty)."
echo "    Consoles: CTRL+ALT+F1 (este) / CTRL+ALT+F2 (shell extra)."
if command -v systemctl >/dev/null 2>&1; then
  systemctl start greetd 2>/dev/null || true
fi