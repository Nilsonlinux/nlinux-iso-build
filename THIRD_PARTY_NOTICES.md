# Avisos de terceiros (Third-Party Notices)

Este repositório é licenciado sob **GPL-3.0-or-later** (veja [`LICENSE`](LICENSE)).
Ele incorpora, referencia ou deriva de obras de terceiros. Os termos de cada uma
prevalecem sobre os arquivos/partes correspondentes e são reproduzidos/indicados
abaixo.

---

## 1. Bibata Cursor — `config/.local/share/icons/Bibata-Modern-{Ice,Amber,Classic}`

Conjunto de cursores embutido no repositório (aplicado ao live e ao sistema
instalado via `config/`).

- **Licença:** GNU General Public License v3.0 (GPL-3.0)
- **Copyright:** Copyright (C) 2018 Abdulkaiz Khatri
- **Origem:** https://github.com/ful1e5/Bibata_Cursor

Os arquivos de cursor permanecem sob GPL-3.0. Eles **não** são relicenciados por
este projeto. O texto integral da GPL-3.0 está no arquivo [`LICENSE`](LICENSE)
deste repositório (mesma licença). O código-fonte correspondente está disponível
no endereço acima.

## 2. archiso / releng — base do build (`build-iso.sh`)

O `build-iso.sh` **regenera** o perfil `iso/profile/` a partir do pacote
`archiso`/releng instalado no sistema de build (não é versionado neste
repositório, mas é utilizado e adaptado durante a geração da ISO).

- **Licença:** GNU General Public License v3.0 (GPL-3.0)
- **Autor/projeto:** Arch Linux — https://github.com/archlinux/archiso
- **Pacote:** `archiso` (repositório `[extra]` do Arch Linux)

## 3. sound-theme-freedesktop — som de volume `audio-volume-change.oga`

Referenciado (e **não** embutido) pelo tema de som `nlinux`, via
`Inherits=freedesktop` em `config/.local/share/sounds/nlinux/index.theme`. O
pacote `sound-theme-freedesktop` é uma dependência declarada em
`packages/base.packages`.

- **Licença:** Creative Commons Attribution-ShareAlike (CC-BY-SA)
- **Pacote:** `sound-theme-freedesktop` (repositório do Arch Linux)
- **Observação:** o arquivo `audio-volume-change.oga` foi propositalmente
  **não** copiado para este repositório, justamente por causa da licença
  CC-BY-SA. Ele é fornecido pelo pacote acima.

## 4. nlinux-software — `nlinux-software/`

Cópia do build publicado da loja de software do NLinux, embutida na ISO em
`/opt`, a partir de outro repositório do mesmo autor.

- **Origem:** https://github.com/Nilsonlinux/nlinux-software
- **Licença:** consulte o repositório de origem (é um projeto do próprio autor
  deste repositório). Distribuída aqui como componente do sistema.

## 5. Arte do projeto — `NLinux.jpg`, `splash.png`, logo do fastfetch, tema de som `nlinux`

Imagens, splash do boot, logo (`config/.config/fastfetch/img/nlinux.png` e
`config/.local/share/fastfetch/logos/nlinux.txt`) e o tema de som próprio
(`config/.local/share/sounds/nlinux/`) são de autoria do projeto e ficam
cobertos pela licença GPL-3.0-or-later deste repositório, salvo indicação em
contrário.

---

## 6. Pacotes do Arch Linux embutidos na ISO

A ISO resultante empacota centenas de pacotes dos repositórios oficiais do Arch
(`core`, `extra`, `multilib`) e do AUR. Cada pacote mantém a **sua própria
licença** (GPL, MIT, Apache, BSD, CC, etc.) e **não** é relicenciado por este
projeto. Ao redistribuir a ISO, preserve os avisos de licença — eles ficam em
`/usr/share/licenses/` no sistema instalado — e cumpra as obrigações de cada
licença (por exemplo, oferecer o código-fonte correspondente quando a licença
exigir).
