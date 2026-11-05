# NLinux — release 2026.11.05

## Download

[Baixar a ISO NLinux no Google Drive](https://drive.google.com/file/d/1fllkqBJmYWshmXiQydkkjDAWxXW-pV4i/view?usp=sharing) — ISO live para `x86_64`, aproximadamente 3,0 GiB.

SHA-256: `b115c14221fda008864d8834ed8b7c3c23c251044db7c75d0f5834d87fdec8b5`

## Novidades

- **Identidade NLinux consolidada** no instalador, na loja, nos atalhos, no fastfetch, nos temas de som e na arte do sistema; referências antigas foram removidas.
- **Instalador com btrfs e modo Rápido offline como padrão**, mantendo as opções de ext4 e instalação Completa online.
- **MOTD da NLinux** renderizado com FIGlet.
- **Arte de boot atualizada**, com nova imagem de splash e branding do menu de boot.
- **Catálogo da loja** na revisão **374**.
- **Assinatura GPG das releases** configurada para os próximos builds.

## Requisitos e instalação

- Arquitetura `x86_64`; pendrive de 8 GB ou mais.
- UEFI necessário para instalar. A ISO também oferece opções BIOS para experimentar o ambiente live.
- A instalação rápida funciona offline; a instalação completa requer internet.
- Login do ambiente live: usuário `nlinux`, senha `nlinux`.
- Para conferir o download: `sha256sum nlinux-2026.11.05-x86_64.iso`.

Faça backup antes de alterar partições. Em dual boot com Windows, desative BitLocker, Inicialização Rápida e hibernação antes de prosseguir.

## Documentação

- [Documentação do NLinux](https://nilsonlinux.github.io/docs.html)
- [Changelog](https://nilsonlinux.github.io/changelog.html)
- [Recursos](https://nilsonlinux.github.io/recursos.html)
- [Loja NLinux Software](https://nilsonlinux.github.io/loja.html)
- [Código e instruções para compilar a ISO](https://github.com/Nilsonlinux/nlinux-iso-build)

## Versões anteriores

- [NLinux 2026.10.15](https://github.com/Nilsonlinux/nlinux-iso-build/releases/tag/2026.10.15) — opencode incluído, GPL-3.0 explícito e atualização sem interrupções.
- [NLinux 2026.10.09](https://github.com/Nilsonlinux/nlinux-iso-build/releases/tag/2026.10.09) — primeira release pública.
