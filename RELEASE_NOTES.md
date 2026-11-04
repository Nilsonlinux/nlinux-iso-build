# FalconOS — release 2026.11.03

> **Nota de renomeação (2026-11-04):** a distribuição passou a se chamar
> **NLinux**. Estas notas documentam a release **2026.11.03**, publicada
> originalmente sob o nome **FalconOS**; nomes de arquivos, URLs e
> identificadores dessa versão são mantidos como registro histórico.

<h2 align="center">⬇️ Download</h2>

<p align="center">
  <a href="https://drive.google.com/file/d/1OwX09j8_L7ikGAhdyWwYPVtuHDfo1CtK/view?usp=sharing">FalconOS ISO (Google Drive)</a> — ISO live, ~2,9 GB, para <code>x86_64</code>.<br>
  sha256 da ISO <code>92ce5f420d335d23f4bf64ec6fe61886166163e7eb48fe1af459b9cec2754551</code>
</p>

Terceira release pública do FalconOS. A grande mudança desta versão é a **identidade definitiva da distribuição**: o antigo nome NLinux sai de cena e tudo passa a se chamar **FalconOS** — nome do sistema, usuário do ambiente live, hostname padrão, instalador, loja, serviços, arquivos de configuração, arte e repositórios. Junto vêm o **Timeshift** para snapshots do sistema, o **mpv-mpris** para integração de mídia com o player e ajustes visuais no Noctalia.

## ✨ Novidades

- **NLinux agora é FalconOS**: a renomeação foi completa e não ficou só na tela.
  - `/etc/os-release`, `/etc/issue`, `/etc/motd`, hostname e label da ISO usam **FalconOS**.
  - O usuário do ambiente live passa a ser **`falconos`**, com senha **`falconos`**.
  - O hostname padrão da instalação passa a ser **`falconos`**.
  - Instalador, loja, serviços systemd, pacote Python da loja e arquivos internos foram renomeados de `nlinux-*` para `falconos-*`.
  - Os repositórios oficiais também mudaram: [`falconos-iso-build`](https://github.com/Nilsonlinux/falconos-iso-build), [`falconos-software`](https://github.com/Nilsonlinux/falconos-software) e [`falconos-software-admin`](https://github.com/Nilsonlinux/falconos-software-admin).

- **Nova identidade visual**: logo novo no menu de boot, no fastfetch, na tela de boas-vindas, no instalador, na loja e nos ícones do sistema, com a arte de fundo atualizada (`FalconOS.jpg` / `splash.png`). Os temas de som e os nomes dos arquivos de arte também seguem a nova marca.

![FalconOS](https://raw.githubusercontent.com/Nilsonlinux/nlinux-iso-build/main/install/chroot/nlinux-welcome/welcome-logo.png)

- **Timeshift incluído**: o Timeshift vem na lista de pacotes do desktop e é instalado tanto no modo **Rápido offline** quanto no **Completo online**. Dá para criar snapshots do sistema e restaurar depois, com interface gráfica e assistente próprio.

- **mpv-mpris**: o mpv passa a expor controles de mídia pelo MPRIS, então as teclas **Play/Pause/Próxima/Anterior** e os widgets de mídia do Noctalia controlam o player direto, sem plugin extra.

- **Noctalia**: os grupos da barra (RAM/CPU/temperatura e clima/relógio) passaram a usar `surface_container` como preenchimento, com contraste mais consistente com o tema.

- **Comunidade no Telegram**: o site oficial agora aponta para o grupo [FalconOS Community](https://t.me/FalconOSCommunity).

## 🔧 Também nesta versão

- **Instalador e loja com a marca nova**: janela, atalhos, caminhos em `/opt`, nomes dos binários e mensagens internas foram ajustados para FalconOS; o instalador continua com as **10 etapas** e os dois modos de instalação.
- **Serviços renomeados**: `falconos-pacman-refresh.service` e os arquivos de sudoers do build agora usam o prefixo `falconos-`.
- **Documentação atualizada**: README, notas de licença e textos de terceiros acompanham o novo nome, os novos repositórios e os pacotes incluídos.
- **Catálogo da loja**: revisão 373, com **63 aplicativos**, servida automaticamente pelo FalconOS Software.

## ⬆️ Já tem o FalconOS/NLinux instalado?

- Atualize os pacotes normalmente: `sudo pacman -Syu`.
- Para ter a identidade nova por completo — usuário live `falconos`, caminhos `falconos-*`, arte e menu atualizados — o caminho recomendado é **instalar a ISO 2026.11.03**. A renomeação mexe em caminhos do sistema que não são migrados por uma atualização de pacotes.
- O Timeshift pode ser instalado em sistemas já existentes com `sudo pacman -S timeshift`.
- O mpv-mpris pode ser instalado com `sudo pacman -S mpv-mpris`.

## 💾 Requisitos

- Arquitetura `x86_64`; pendrive de 8 GB ou mais.
- **UEFI é necessário para instalar.** A ISO também inclui opções de boot BIOS para experimentar o ambiente live.
- Internet: opcional na instalação rápida offline; necessária na instalação completa online.
- Login do ambiente live: usuário **`falconos`**, senha **`falconos`**.

> Antes de alterar partições, faça backup dos dados. Em dual boot com Windows, desative o BitLocker e a Inicialização Rápida/hibernação antes de prosseguir.

## ✅ Como conferir o download

```bash
sha256sum falconos-2026.11.03-x86_64.iso
# 92ce5f420d335d23f4bf64ec6fe61886166163e7eb48fe1af459b9cec2754551
```

## 📚 Documentação

- [Documentação do FalconOS](https://nilsonlinux.github.io/docs.html)
- [Changelog](https://nilsonlinux.github.io/changelog.html)
- [Recursos da distribuição](https://nilsonlinux.github.io/recursos.html)
- [Loja FalconOS Software](https://nilsonlinux.github.io/loja.html)
- [Código e instruções para compilar a ISO](https://github.com/Nilsonlinux/falconos-iso-build)

## 📦 Versões anteriores

- [FalconOS 2026.10.15](https://github.com/Nilsonlinux/falconos-iso-build/releases/tag/2026.10.15) — opencode incluído, GPL-3.0 explícito e atualização sem interrupções.
- [FalconOS 2026.10.09](https://github.com/Nilsonlinux/falconos-iso-build/releases/tag/2026.10.09) — primeira release pública.
