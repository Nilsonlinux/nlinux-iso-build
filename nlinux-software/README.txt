NLinux Software v113 - loja de aplicativos (distribuicao)
Sem opcao de administracao.

Dependencias (veja DEPENDENCIES.txt):
  - python
  - python-gobject
  - gtk3
  - webkit2gtk-4.1
  - polkit
  - gnupg
  - git

Instalar (o instalador verifica e instala as dependencias faltantes):
  sudo ./install.sh
Executar:
  nlinux-software
  Na abertura, a loja atualiza os bancos do pacman com `pacman -Sy`
  e solicita autorização administrativa.
