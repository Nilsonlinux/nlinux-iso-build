# NLinux — release 2026.10.15

<h2 align="center">⬇️ Download</h2>

<p align="center">
  <a href="https://drive.google.com/file/d/1OGHENI3Fs6Up4eLDzPFMtUIGkut3XqV2/view?usp=sharing">NLinux ISO (Google Drive)</a> — ISO live, ~2,9 GB, para <code>x86_64</code>.<br>
  sha256 da ISO <code>ec807478bfe6ef9b1b9bb837de6213e1b08ab32b7abf2a3ff29caff762ebe55b</code>
</p>

Segunda release pública do NLinux. Mantém a base Arch Linux com desktop Wayland Umbriel, shell Noctalia V5, instalador visual em 10 etapas e a loja NLinux Software — e agora traz o agente de programação **opencode** já instalado, licenciamento GPL-3.0 explícito, atualização do sistema sem interrupções e uma janela de boas-vindas mais informativa.

## ✨ Novidades

- **opencode incluído no sistema**: o agente de programação com IA (repositório `extra`) vem pré-instalado tanto no ambiente live quanto no sistema instalado, e ganha **atalho próprio na lista de aplicativos** — abre no terminal kitty. Antes ele só podia ser instalado pela loja.

![opencode no NLinux](https://raw.githubusercontent.com/Nilsonlinux/nlinux-software/main/src/apps/assets/opencode-1.png)

- **Atualização do sistema sem interrupções**: a atualização pela loja passou a rodar `pacman -Syu` de forma automática. Não é mais preciso digitar `s`/`y`, e a caixa "Resposta solicitada pelo pacman" deixou de aparecer quando não há pergunta real. Instalação, remoção e pacotes da AUR continuam pedindo confirmação quando de fato existe uma pergunta.
- **Janela de boas-vindas mais clara**: passa a mostrar a **Data de instalação** e a **Versão atual (releases)**, consultada na última release publicada. O nome "App Center" foi trocado por **NLinux Software** nos sete idiomas.
- **Licenciamento explícito**: a distribuição e a loja embarcada agora trazem a licença **GPL-3.0-or-later**, o arquivo **THIRD_PARTY_NOTICES.md** com os avisos de terceiros e cabeçalhos **SPDX** nos fontes.

## 🔧 Também nesta versão

- **Catálogo da loja atualizado**: revisão 373, com **63 aplicativos** — entrou o **guvcview** (visualização de webcam de dispositivos V4L2). A loja baixa o catálogo novo automaticamente.
- **Assinatura GPG das releases**: a chave pública passa a ser publicada no repositório (`nlinux-releases-gpg-pub.asc`), junto das instruções de verificação de tags e commits.
- **Noctalia**: atalhos de sessão desativados na tela de bloqueio (`show_shortcuts = false`).
- **Documentação** do projeto atualizada, incluindo as seções de licença, assinatura GPG e do opencode.

## ⬆️ Já tem o NLinux instalado?

- Atualize o sistema: `sudo pacman -Syu`.
- Instale o opencode: `sudo pacman -S opencode` — o atalho aparece no menu depois disso.
- A loja NLinux Software baixa o catálogo novo (revisão 373) automaticamente.

## 💾 Requisitos

- Arquitetura `x86_64`; pendrive de 8 GB ou mais.
- **UEFI é necessário para instalar.** A ISO também inclui opções de boot BIOS para experimentar o ambiente live.
- Internet: opcional na instalação rápida offline; necessária na instalação completa online.

> Antes de alterar partições, faça backup dos dados. Em dual boot com Windows, desative o BitLocker e a Inicialização Rápida/hibernação antes de prosseguir.

## 📚 Documentação

- [Documentação do NLinux](https://nilsonlinux.github.io/docs.html)
- [Changelog](https://nilsonlinux.github.io/changelog.html)
- [Recursos da distribuição](https://nilsonlinux.github.io/recursos.html)
- [Loja NLinux Software](https://nilsonlinux.github.io/loja.html)
- [Código e instruções para compilar a ISO](https://github.com/Nilsonlinux/nlinux-iso-build)

## 📦 Versões anteriores

- [NLinux 2026.10.09](https://github.com/Nilsonlinux/nlinux-iso-build/releases/tag/2026.10.09) — primeira release pública.
