# NLinux

Distro-instalador do Arch Linux + Noctalia, reproduzível em qualquer máquina.
O projeto gera um **ISO próprio** (base `archiso`/releng) que **boota direto
para o desktop ao vivo**, onde a instalação é feita **exclusivamente pelo
instalador web** (atendente no navegador, janela kiosk, com assistente visual).
Não há opção separada de instalação por TUI.

Resultado instalado / ao vivo:

- **Umbriel** — compositor Wayland (AUR `umbriel-git` + `xdg-desktop-portal-umbriel-git`)
- **Noctalia** — shell/desktop (repositório oficial `[extra]`)
- **greetd** + **noctalia-greeter** — tela de login Wayland (AUR)
- **systemd-boot**, **LUKS2 opcional**, **ext4 ou btrfs** (subvolumes `@`, `@home`, `@log`, `@pkg`)
- **Shell padrão do usuário: fish**; terminal padrão: **kitty** (`Mod+T` / `Mod+Shift+T`)
- **App Center do GNOME** (gnome-software com PackageKit + metadados AppStream + Flathub)
- **Boas-vindas no primeiro login** do sistema instalado (janela única, `zenity`)
- **fastfetch** mostra a logo do NLinux (PNG via protocolo kitty em `config/.config/fastfetch/img/nlinux.png`) + especificações do sistema em pt-BR
- **Desktop no live** com os mesmos apps da instalação (Firefox, kitty, Gnome Software…)

---

<img width="640" height="480" alt="image" src="https://github.com/user-attachments/assets/a8d601e4-ad83-4b77-933a-a67312f9afcd" />


## Estrutura do projeto

```
build-iso.sh                     gera a ISO (precisa de sudo; limpa mounts de builds interrompidas)
make-splash.sh                   gera splash.png a partir de NLinux.jpg (menu de boot BIOS)
install.sh                       instalador principal (web-installed; GUI_DRIVEN=1 do servidor web)
install/translations.py           tabela de traduções (7 idiomas) usada pelo instalador web
install/chroot/                  etapas executadas dentro do chroot do sistema instalado
packages/                        listas de pacotes do sistema instalado
iso/packages.live                pacotes extras do live (ISO)
iso/airootfs/                    camada over de arquivos do live (branding, auto-run, personalize)
iso/profiledef.sh                metadados da ISO (nome, label, versão)
config/                          dotfiles aplicados ao usuário (live e instalado)
nlinux-software/                 loja de software embarcada em /opt (build publicado; ver "Atualizar a loja")
NLinux.jpg / splash.png          arte do menu de boot
```

---

## Como usar — apenas instalar (sem ISO)

Monte/copie este projeto na máquina alvo e execute como root:

```bash
./install.sh
```

O instalador:

1. **Pré-checagens** (`preflight`): exige root, UEFI e internet (avisa se sem rede);
   garante `gdisk`/`cryptsetup`.
2. **Escolhas do assistente web** (forma exclusiva de instalar, no desktop do
   live via `nlinux-installer-gui`): o mesmo passo a passo abaixo roda no
   navegador; o `install.sh` é disparado pelo servidor web com `GUI_DRIVEN=1`.
   Os 10 passos correspondem às etapas do wizard (`web/static/app.js`):
   - **1/10** Disco de destino (via `lsblk`; ignora `loop`/`zram`);
   - **2/10** Sistema de arquivos: `ext4` ou `btrfs`;
   - **3/10** **Idioma (locale)**: `pt_BR.UTF-8`, `en_US.UTF-8`, `pt_PT`, `es_ES`,
     `fr_FR`, `de_DE`, `it_IT`, `ja_JP`;
   - **4/10** **Layout do teclado (keymap)**: `br-abnt2`, `us`, `us-intl`, `pt`,
     `de`, `fr`, `es`, `it`, `uk`, `no`;
   - **5/10** **Espelho de repositórios**: UFSCar, UFRJ, UFMG, PoP-SC (RNP),
     Kernel.org, CDN oficial (fastly) ou Auto/padrão;
   - **6/10** **Tipo de instalação**: **Rápida (offline)** — padrão, copia o
     sistema do pendrive para o disco, sem internet · **Completa (online)** —
     baixa e instala os pacotes do zero (`pacstrap` + AUR);
   - **7/10** Criptografia LUKS2: Não/Sim;
   - **8/10** GPU: `intel` / `amd` / `nvidia` / `vm`;
   - **9/10** **Nome de usuário** (digitado; minúsculas/números/`_`/`-`);
   - **10/10** **Senha do usuário** (digitada e mascarada, com confirmação);
   - **Resumo** com "Confirmar e iniciar" / "Recomeçar".
   - Caixa **larga (até 118 colunas)** e textos que **não são cortados**:
     sobre a largura da janela, entram com `…` quando necessário; itens com
     muitos textos (localidades, espelhos, tipo de instalação) cabem sem corte.
   - **Após confirmar, a MESMA caixa vira o painel de instalação**: lista de
     etapas (✓ concluída, ▸ atual, ○ pendente), **barra de progresso
     `[███░░░] 45%`** e as duas últimas linhas de log (com o progresso real do
     `rsync`/`pacstrap` ao vivo). O motor roda em subprocesso com
     `GUI_DRIVEN=1` e sinaliza via `NLPROGRESS|<pct>|<etapa>`.
   - Fontes maiores no live: instalador via menu abre o kitty com
     `font_size 18`; no modo direto (tty) o console usa `ter-120b`.
   - Navegação: **setas** ou **k/j** · **Enter** seleciona · **Backspace** apaga na
     digitação · **Esc/q** cancela (saída `2`).
   - Fixos: hostname `nlinux`, zona `America/Sao_Paulo`, senha LUKS `nlinux`; a
     senha informada vale para o usuário **e** para o root.
   - Ao confirmar grava `DISK`, `FS_TYPE`, `LOCALE`, `KEYMAP`, `MIRROR`,
     `OFFLINE`, `USE_LUKS`, `GPU`, `INSTALL_USER`, `INSTALL_USER_PASS`,
     `ROOT_PASS` via `--out arquivo` (sem `--out`, imprime no stdout). Sem tty
     → sai com status `1`.
- **Fallback (legado, não usado no boot)**: se `install.sh` for chamado
      manualmente num terminal sem o web, usa prompts de texto
      (`collect_options_prompt`) com confirmação de senhas (`read_secret`).
     O menu em si é atualizado ao vivo: **locale/keymap aplicados no ambiente
     live** (`locale-gen`, `vconsole.conf`, `loadkeys`) e **mirror definido no
     topo do `mirrorlist`** + `DisableDownloadTimeout` no `pacman.conf`.
3. **Particionamento**: GPT — `1G` EFI (FAT32, montada em `/boot`) + restante na
   partição raiz (tipo `8309` `cryptroot` com LUKS, ou `8304` `archroot`).

No modo **dual boot**, o instalador preserva a ESP existente e cria a partição
NLinux em espaço livre. Se não houver espaço livre suficiente, a interface web
pode reduzir uma partição Windows NTFS com um controle deslizante. A redução só
é aplicada após confirmação; faça backup e desative BitLocker e Inicialização
Rápida/hibernação do Windows antes de prosseguir. O Windows pode executar uma
verificação de disco no primeiro início após o ajuste. Outros sistemas de
arquivos não são redimensionados.

### Modo Rápido offline (padrão) vs Completo online

| | **Rápida offline** (padrão) | **Completa online** |
|---|---|---|
| Etapa de pacotes | **cópia do live do pendrive** (`rsync` `/` → disco, ~2–4 min) | `pacstrap` (baixa ~2 GB + instala, lento em conexão ruim) |
| Internet | **não precisa** | precisa |
| AUR (Umbriel/Noctalia) | já vem no sistema copiado (pula o yay) | compila via `yay` no chroot |
| Boot/setup | chroot finaliza: bootloader, initramfs, usuário, serviços | idem |
| Variável | `OFFLINE=1` | `OFFLINE=0` |

Na cópia offline o rsync **tolera avisos não fatais** (rc 23/24 — arquivos que
mudam/somem num live, atributos em ESP FAT): eles não abortam mais a instalação.
Se o rsync for interrompido (rc 10–13/30), ele **retoma sozinho** com
`--partial`; só erros fatais (sem espaço, I/O, read-only) interrompem, exibindo
as últimas linhas do log. O log completo fica em `/tmp/offline-rsync.log` e é
copiado para `/var/log/offline-rsync.log` no sistema instalado.

Nos dois modos o chroot roda `10-system.sh` (gera `systemd-boot` + `initramfs`),
cria o usuário, aplica dotfiles e habilita os serviços — o boot **Sempre** tem a
opção "NLinux". Ao final, o instalador **registra a entrada "NLinux" na lista de
boot UEFI** (`efibootmgr --create`, rótulo próprio; o "Linux Boot Manager" do
`bootctl` é removido) e grava o **fallback `/EFI/BOOT/BOOTX64.EFI`** — assim o
disco aparece como **"NLinux"** na lista do firmware **e**, em firmwares sem
NVRAM, como opção genérica `UEFI: <disco>`.
4. **Sistema de arquivos**: LUKS2 (`cryptroot`) quando escolhido; btrfs com subvolumes
   `@`, `@home`, `@log`, `@pkg`, ou ext4.
5. **Instalação dos pacotes** (ver tabela acima): modo **rápido offline** copia o
   sistema do pendrive; modo **completo online** usa `pacstrap`
   (`base.packages` + `desktop.packages` + drivers de GPU intel/amd/nvidia/vm +
   microcódigo `intel-ucode`/`amd-ucode`).
6. **Etapas no chroot** (tabela abaixo; no offline o yay/AUR é pulado).
7. Desmonta tudo sozinho (`trap`).

> **Aviso:** o disco de destino é apagado por completo.

### Variáveis substituem o menu

Para instalação não-interativa, exporte antes de rodar:

```bash
sudo env INSTALL_USER=felipe INSTALL_USER_PASS=senha123 ROOT_PASS=senha123 \
  INSTALL_DISK=/dev/nvme0n1 FS_TYPE=btrfs USE_LUKS=1 GPU=amd ./install.sh
```

Variáveis e padrões (`install.sh`, linha 26+):

| Variável | Padrão |
|---|---|
| `INSTALL_USER` / `INSTALL_USER_PASS` | perguntados no menu (padrão do script: `nlinux` / `nlinux`) |
| `ROOT_PASS` / `LUKS_PASS` | mesma senha do usuário / `nlinux` |
| `HOSTNAME` | `nlinux` |
| `LOCALE` / `KEYMAP` / `ZONEINFO` | `pt_BR.UTF-8` / `br-abnt2` / `America/Sao_Paulo` |
| `MIRROR` | espelho de repositórios (URL base ou vazio = padrão); definido no menu |
| `OFFLINE` | `1` = instalação rápida offline (padrão), `0` = completa online |
| `INSTALL_DISK` (`DISK`) / `FS_TYPE` / `USE_LUKS` / `GPU` | escolhidos no menu |
| `MICROCODE` | auto-detectado (intel/amd) |

---

## Gerar o ISO

Na sua máquina Arch Linux:

```bash
./build-iso.sh
```

O que ele faz:

1. Instala `archiso` se faltar e **regenera** `iso/profile/` do zero a partir do
   releng instalado (compatível com a versão do `mkarchiso`);
2. Aplica os metadados de `iso/profiledef.sh` (nome/label/versão = `nlinux`);
3. Anexa `iso/packages.live` à lista de pacotes do live;
4. Copia a camada `iso/airootfs/` (autologin, auto-run, branding, serviços do live);
5. **Embuta este projeto** em `/opt/noctalia-installer` no live:
   `install.sh`, `install/`, `config/`, `packages/`;
6. Transforma o boot: **systemd-boot** (UEFI), **GRUB** (UEFI/BIOS boot) e
   **syslinux** (BIOS) — títulos, items e a splash NLinux;
7. Roda `mkarchiso -v` → ISO em `iso/out/nlinux-<data>-x86_64.iso`.

> **Não rode `build-iso.sh` enquanto outro build está ativo.** A compilação roda
> em um namespace de mounts privado, evitando que ferramentas do host varram
> pseudo-filesystems temporários do chroot. Antes de iniciar, o script também
> desmonta mounts deixados em `iso/work/` por builds interrompidas.

O build compila os pacotes AUR (**`umbriel-git`, `noctalia-greeter`,
`xwayland-satellite-git`, `whatsapp-linux-desktop-bin`**) dentro do chroot do
live via `yay` (veja `customize_airootfs.sh`). Por isso a geração é **lenta**
(cargo/Rust, testes inclusos) e precisa de **internet + AUR**; a ISO sai com
~2 GB+.

Os builds AUR usam `install/chroot/makepkg-no-debug.conf`, que mantém as
opções padrão do `makepkg`, mas desativa a geração de pacotes de depuração.
Isso evita avisos do `gdb-add-index` em binários pré-compilados do WhatsApp,
que não contêm símbolos de depuração; os pacotes instalados continuam normais.

Grave e boote:

```bash
sudo dd if=iso/out/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Menu de boot

- **UEFI** (systemd-boot, padrão): **NLinux ao vivo** (padrão) · **NLinux ao vivo - leitor de tela** · **Memtest86+**. O GRUB (menu alternativo) tem as mesmas opções.
- **BIOS** (syslinux): título **"Bem-vindo ao NLinux"** com a arte `splash.png`
  (gerada de `NLinux.jpg`) e o item **"Iniciar NLinux"** + Memtest/HDT/reboot.

### O que acontece ao bootar

- Toda opção de boot (UEFI/GRUB/BIOS) leva ao **desktop no live**: autologin
  root no tty1 inicia o greetd (vt7) + noctalia-greeter + Umbriel/Noctalia, sem
  prompt de instalação no console. Login do live: usuário **`nlinux`**, senha
  **`nlinux`**. Traz NetworkManager, PipeWire e cursor Bibata.
- **Instalar** (somente pelo live): atalho **Instalar NLinux** do desktop/menu
  (roda `/usr/local/bin/nlinux-installer-gui`) abre o Firefox em kiosk apontando
  para o servidor web local (`http://127.0.0.1:8765`, root via sudo). Não há
  instalador TUI.
- Consoles extras do live: CTRL+ALT+F2 (shell root). Terminais no desktop:
  `Mod+T` / `Mod+Shift+T` (kitty).

### Branding no ISO (live e instalado)

- `/etc/os-release` → `NAME="NLinux"`, `PRETTY_NAME="NLinux"` (mantendo
  `ID=arch`/`ID_LIKE=arch` para AUR/pacman) — no live via `iso/airootfs/etc/os-release`
  e no instalado via `10-system.sh`;
- `/etc/issue` → `NLinux \r (\l)` (live e instalado);
- `/etc/motd` → ASCII-art "Bem-vindo ao NLinux!";
- título do bootloader instalado → `NLinux` (systemd-boot `arch.conf`).

---

## Etapas no chroot (sistema instalado)

Roteiro: `install.sh` → `install/chroot/all.sh` → cada etapa abaixo.

| Etapa | Arquivo | Função |
|---|---|---|
| 1 | `10-system.sh` | fuso, locale, keymap, hostname/hosts, `issue`, branding `os-release`, pacman (ParallelDownloads/Color), `pacman-key`, initramfs com `sd-encrypt` (quando LUKS), **zram** (`zram-generator`, zstd), usuários/senhas (shell padrão **fish**), sudoers, **systemd-boot** (entrada `NLinux`, UUID+LUKS) |
| 2 | `20-aur.sh` | usuário de sistema `greeter`; usuário temporário `builder` (sudo sem senha) para instalar **yay-bin** (makepkg) e rodar `yay -S` dos `aur.packages`; remove o `builder` no final |
| 3 | `30-greetd.sh` | `/etc/greetd/config.toml` com o **noctalia-greeter** (sessão padrão `umbriel`) + setup do pacote |
| 4 | `40-user-config.sh` | copia `config/.config` → `~/.config` do usuário (`.tpl` resolvidos com `__KEYBOARD_LAYOUT__` derivado do keymap) e `config/.local` → `~/.local` (ícones/cursor Bibata, logo do fastfetch), delega ao usuário |
| 5 | `41-welcome.sh` | marca `/etc/nlinux-installed` e instala `/usr/local/bin/nlinux-welcome` (janela de boas-vindas única no 1º login; no live é inócuo) — acionado pelo autostart do Umbriel |
| 6 | `50-services.sh` | habilita NetworkManager, bluetooth, greetd, accounts-daemon, **packagekit**; adiciona o **Flathub** para o usuário (App Center); **`appstreamcli refresh --force`** (metadados para a loja); `/etc/environment` (Wayland + `XCURSOR_THEME=Bibata-Modern-Ice`); NTP (`systemd-timesyncd`) |

---

## Pacotes

| Lista | Conteúdo |
|---|---|
| `packages/base.packages` | kernel, firmware, rede, áudio (PipeWire), ferramentas (fzf/ripgrep/starship…), `cryptsetup`, fontes |
| `packages/desktop.packages` | stack Noctalia + apps: firefox, **kitty** e fish, starship, fastfetch, nautilus, gnome-text-editor, **gnome-software** (App Center: PackageKit + AppStream + Flatpak + **zenity** [boas-vindas]), spotify-launcher, discord, telegram-desktop, gpu-screen-recorder, eartag, swaylock/idle, zram-generator, mpv/ffmpeg/imagemagick |
| `packages/aur.packages` | `umbriel-git`, `noctalia-greeter`, `xwayland-satellite-git` (X11 no Umbriel), `whatsapp-linux-desktop-bin` — via `yay` no chroot |
| `iso/packages.live` | ferramentas do instalador (cryptsetup/gdisk/btrfs-progs/parted/python…), `noctalia`, `greetd`, NetworkManager, e os mesmos apps do desktop + Flatpak/gnome-software/packagekit/appstream para o live |

`gnome-software` lista apps de repositório via
**PackageKit** e Flatpaks via **Flathub** (adicionado automaticamente ao usuário
no live e na instalação). Para a loja listar programas, o live (no build) e a
instalação rodam **`appstreamcli refresh --force`** para baixar os metadados
AppStream do Arch — o primeiro acesso ainda baixa um pouco de dados (precisa de
rede).
A mesma senha do usuário vale para o root; o shell padrão do usuário é o **fish**.

---

## Dotfiles (`config/`)

Aplicados ao usuário do **live** (`~/home/nlinux`) e do **sistema instalado**
(`~/.config` do `INSTALL_USER`):

- `config/.config/kitty/kitty.conf` + `themes/noctalia.conf`
- `config/.config/fish/config.fish`
- `config/.config/starship.toml`
- `config/.config/fastfetch/config.jsonc` + `img/nlinux.png` (logo via protocolo kitty; fallback ANSI em `config/.local/share/fastfetch/logos/nlinux.txt`)
- `config/.config/umbriel/…` (`config.toml`, `noctalia.toml`, `src/*`)
- `config/.local/share/icons/Bibata-Modern-{Ice,Amber,Classic}` (cursor; Ice é o padrão via `/etc/environment`)

> Arquivo com sufixo `.tpl` é template: `__KEYBOARD_LAYOUT__` é substituído pelo
> layout derivado do keymap escolhido (`br-abnt2` → `br`, `us` → `us`, …).
> `fish_variables` não é versionado (contém caminhos específicos da máquina).

---

## Splash do boot (BIOS)

- `NLinux.jpg` (fonte) → `splash.png` (640×480 PNG, crop central 4:3).
- Gerar/atualizar: `./make-splash.sh` (usa `NLinux.jpg` da raiz, ou passe um
  caminho). Requer Python + Pillow; opcionalmente passe a imagem como argumento.
- O `build-iso.sh` copia `splash.png` para o perfil syslinux e mantém
  `MENU BACKGROUND splash.png` no `archiso_head.cfg` (título permanece
  "Bem-vindo ao NLinux").

---

## Personalizando

- **Metadados da ISO** (nome/label/app/versão): `iso/profiledef.sh`.
- **Pacotes**: edite as listas de `packages/` e `iso/packages.live`.
- **Dotfiles**: edite `config/`.
- **Auto-run / serviços / branding do live**: `iso/airootfs/` —
  `root/customize_airootfs.sh` (roda no chroot do build), `root/.bash_profile`,
  `root/.zprofile`, `etc/systemd/system/getty@tty1.service.d/autologin.conf`,
  `usr/local/bin/nlinux-installer{,-gui}`.
- **Etapas da instalação**: `install/chroot/*.sh`.
- Trocar o logo/arte do menu de boot: substitua `NLinux.jpg` e rode
  `./make-splash.sh`.

### Atualizar a loja embarcada

`nlinux-software/` é a cópia do build publicado da loja
(`github.com/Nilsonlinux/nlinux-software`) que o `build-iso.sh` embute em
`/opt/nlinux-software`. Para atualizar, gere a nova versão pela curadoria
(ela já publica no GitHub) e substitua o conteúdo:

```bash
cd /home/nilsonlinux/nlinux-iso-build
rm -rf nlinux-software && mkdir nlinux-software
git clone --depth 1 https://github.com/Nilsonlinux/nlinux-software.git /tmp/loja
cp -a /tmp/loja/. nlinux-software/
rm -rf nlinux-software/.git nlinux-software/*.tar.gz nlinux-software/*.tar.gz.asc
```

Confirme com `cat nlinux-software/catalog-head.json` (a revisão tem que ser a
mais recente) e conferindo que a assinatura bate:
`gpg --verify nlinux-software/nlinux-software-v<N>.tar.gz.asc nlinux-software/nlinux-software-v<N>.tar.gz`
(precisa do `.tar.gz`, que só existe no repositório, não na pasta embute).

Desde a v117 o app **não grava mais dentro do `/opt`**: o catálogo e a mídia
vão para `~/.local/share/nlinux/store/apps` e o `/opt` é só a semente. Por
isso `customize_airootfs.sh` (live) e `40-user-config.sh` (instalado) semeiam
essa pasta do usuário em vez de dar escrita no `/opt`.

## Pós-instalação sugerida

- Ajuste `~/.config/umbriel/config.toml` (teclas, layouts, regras de janela).
- Hardware especial, atualizações e AUR usam `yay` (já instalado).
- Dependências de build (compiladores, `meson`, `wlroots0.20`, Rust) ficam no
  sistema — remova-as depois se quiser enxugar.
