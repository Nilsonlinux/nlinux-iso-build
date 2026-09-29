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
web/server.py                    servidor local do instalador (SSE, estado, execução do install.sh)
web/static/                      interface do instalador (wizard + painel de progresso)
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
   - **1/10** **Idioma, teclado e fuso** (uma escolha define os três):
     `pt_BR.UTF-8`, `en_US.UTF-8`, `pt_PT`, `en_GB`, `es_ES`, `fr_FR`, `de_DE`,
     `it_IT`, `ja_JP` (keymap e zona derivam da escolha);
   - **2/10** Disco de destino (via `lsblk`; ignora `loop`/`zram`);
   - **3/10** Modo: **Apagar tudo** ou **Dual boot** (preserva a ESP e instala em
     espaço livre, com redução opcional de uma partição NTFS do Windows);
   - **4/10** Sistema de arquivos: `ext4` ou `btrfs`;
   - **5/10** **Espelho de repositórios**: UFSCar, Leaseweb, Dogado, Kyoto ou
     Automático (padrão);
   - **6/10** **Tipo de instalação**: **Rápida (offline)** — padrão, copia o
     sistema do pendrive para o disco, sem internet · **Completa (online)** —
     baixa e instala os pacotes do zero (`pacstrap` + AUR);
   - **7/10** Criptografia LUKS2: Não/Sim;
   - **8/10** GPU: `auto` / `amd` / `nvidia` / `intel`;
   - **9/10** **Hostname, nome de usuário e senha** (usuário em minúsculas com
     números/`_`/`-`, senha mascarada com confirmação; por padrão a mesma senha
     vale também para o root);
   - **10/10** **Resumo** com "Confirmar e iniciar" / "Recomeçar" (no dual boot,
     a redução da partição NTFS é confirmada aqui).
   - **Após confirmar, a MESMA caixa vira o painel de instalação**: lista de
     etapas (✓ concluída, ▸ atual, ○ pendente), **anel de progresso da
     instalação inteira** com a % no centro, **relógio digital** e a linha de
     *etapa · atividade* logo abaixo do anel (mais o log com o progresso real do
     `rsync`/`pacstrap`/`cargo` ao vivo). O motor roda em subprocesso com
     `GUI_DRIVEN=1` e sinaliza pelo protocolo `NL*` do log (ver
     "Instalador web"). Se a página recarregar, a conexão cair ou o servidor
     morrer, o painel volta sozinho ao ponto em que a instalação está — nada é
     reiniciado.
   - Ao confirmar, o servidor passa as escolhas ao `install.sh` por **variáveis
     de ambiente** (`INSTALL_DISK`, `FS_TYPE`, `LOCALE`, `KEYMAP`, `ZONEINFO`,
     `MIRROR`, `OFFLINE`, `INSTALL_MODE`, `USE_LUKS`, `GPU`, `HOSTNAME`,
     `INSTALL_USER`, `INSTALL_USER_PASS`, `ROOT_PASS`, `NLLANG`, `GUI_DRIVEN=1`),
     que são as mesmas aceitas na linha de comando (ver "Variáveis substituem o
     menu"). A senha informada vale para o usuário **e** para o root; LUKS e
     hostname têm padrão (`nlinux`).
   - Navegação: **Enter** (ou o botão) avança; o painel não recua sozinho — ele
     acompanha a instalação.
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
   `install.sh`, `install/`, `config/`, `packages/`, `web/`;
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
  instalador TUI. O servidor roda sob um **supervisor** (reinicia em 2 s se
  cair) e a instalação é desacoplada dele: uma queda não interrompe nem
  reinicia a instalação (ver "Instalador web").
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

## Instalador web (painel, etapas e resiliência)

O instalador do live é um servidor local (`web/server.py`, só biblioteca padrão do
Python) que serve a interface de `web/static/` e executa o `install.sh` em
subprocesso com `GUI_DRIVEN=1`. O painel do navegador acompanha o progresso por
**SSE** (`/api/stream`).

**Regra central: a instalação não depende do navegador nem do servidor.** A saída
do `install.sh` vai para um **arquivo** de log (`/tmp/nlinux-install.log`) que o
servidor apenas acompanha — não um pipe — e o estado (etapa, %, últimas linhas,
código de saída) fica no servidor, com checkpoint em
`/tmp/nlinux-install-state.json` a cada 5 s. Consequências:

| Situação | O que acontece |
|---|---|
| Queda de conexão, reload do kiosk, suspensão do Firefox | O `EventSource` reconecta sozinho e a tela mostra *"Reconectando ao instalador… (a instalação continua)"*. **Nunca** vira falha de instalação. |
| Servidor cai (falta de memória, Ctrl+C, reabrir o atalho) | O `install.sh` continua até o fim escrevendo no arquivo. Ao voltar, o supervisor do launcher o reinicia e o servidor **reanexa** a execução em andamento (log + checkpoint). |
| Página recarregada com a instalação rodando | O boot da página consulta `/api/status` e volta direto ao painel de progresso (adota também o idioma da execução) em vez do assistente. |
| Formulário enviado duas vezes | `POST /api/install` devolve **409** com o estado atual e a página volta ao painel: ninguém apaga o disco por cima da instalação que roda. |
| `install.sh` morre sem escrever o resultado (morto por sinal/OOM) | Watchdog da execução reanexada encerra o painel como falha explícita, em vez de girar para sempre. |
| Erro de verdade na instalação | `die` no `install.sh` → `_save_error_marker` grava `/var/log/install-error.log` **no disco instalado** (com as últimas 150 linhas do log) antes de desmontar. |
| Falha de espelho no modo online | `pacstrap` tenta até 3 vezes (o pacman reaproveita o cache) antes de abortar com dica de rede/mirror. |

### Protocolo (SSE) e API

| Evento SSE | Dados | Para que serve |
|---|---|---|
| `state` | `{pct, label, act, step, idx, steps, mode, started, finished, download, lines, running, done, code, error, lang}` | Ressincroniza tudo a cada (re)conexão |
| `progress` | `{pct, label, act, step, idx}` | Anel + linha de etapa/atividade |
| `log` | `{lines: [...]}` | Linhas do log, em lote (não um evento por linha) |
| `download` | `{bytes, total, rate, files}` | Baixado, total, velocidade e nº de pacotes (modo online) |
| `done` | `{code}` | Fim da execução (o `state` final vem logo em seguida) |
| `error` | `{message}` | Falha real do servidor/execução |

Trocar de etapa, nota e atividade **não** têm evento próprio: as três coisas vão
no `progress` (e no `state`), que é o único evento que mexe na tela do anel —
assim uma troca de etapa nunca chega "solta" e o rótulo nunca pisca para um
estado intermediário.

A linha incompleta do log (o `\r` do `rsync`/`pacman`) **não** é transmitida:
quem consome esse `\r` é o servidor, para extrair o progresso real da etapa
abaixo. A linha completa continua chegando pelo evento `log` quando o programa
termina a linha.

| Endpoint | Uso |
|---|---|
| `GET /` | interface (`web/static/index.html`) |
| `GET /api/stream` | stream SSE (keepalive a cada 5 s) |
| `GET /api/status` | estado atual sem SSE — usado no boot da página e pelo watchdog do cliente |
| `GET /api/disks` | discos candidatos (`lsblk`, ignora `loop`/`zram`) |
| `GET /api/ntfs-partitions?disk=…` | partições NTFS e o limite seguro de redução (dual boot) |
| `GET /api/i18n?lang=…` | tabela de traduções (pt/en/es/fr/de/it/ja) |
| `POST /api/install` | inicia a instalação (**409** se já houver uma em andamento) |
| `POST /api/reboot` · `POST /api/quit` | reinicia a máquina · fecha o Firefox kiosk |

### Conversa entre o servidor e o `install.sh`

O `install.sh` fala com o painel por **linhas de sentinela** no próprio log
(`NL<tipo>|…`). Cada `<chave>` é uma chave de tradução de
`install/translations.py`; o servidor a traduz para o idioma escolhido na
página. Só são emitidas com `GUI_DRIVEN=1`, para não poluir o modo standalone.

| Linha | Significado |
|---|---|
| `NLSTEPS\|<pct>:<chave>,…` | **Plano completo e ordenado** das etapas, enviado uma vez. O número de cada etapa é o **ponto em que ela começa**; a distância entre duas etapas é o **peso** dela (ver abaixo). |
| `NLPROGRESS\|<pct>\|<chave>` | Etapa atual com a porcentagem (uso pontual). |
| `NLSTEP\|<chave>` | Etapa atual; a porcentagem sai do plano. É o que os scripts do chroot usam. |
| `NLNOTE\|<chave>` | Texto temporário dentro da etapa (salvar pacotes, montar/desmontar…), sem trocar de etapa. |
| `NLACT\|<chave>\|<item>` | **Atividade do momento com nome** — o que está sendo feito agora: `Compilando umbriel-git`, `Compilando yay-bin`, `1.234 de 12.345 arquivos`. O `<item>` entra no `%s` da tradução, então o texto sai no idioma escolhido (e nunca em português hard-coded). |
| `NLRESULT\|<rc>` | Resultado final, escrito pelo `trap … EXIT`. **Sempre a última linha do log**, o que permite a uma execução *reanexada* (servidor que caiu no meio) reportar o fim. |

`NLLANG=<idioma>` fixa o idioma das etapas.

#### Etapas na tela: o plano manda

A lista de etapas da tela **não é uma constante do navegador**: é o plano do
`install.sh` (`build_plan` em `install.sh`), que é montado conforme o modo e
enviado no primeiro `NLSTEPS`. Os dois modos instalam coisas diferentes, então
também têm planos diferentes. O número é o **começo** da etapa — a distância
entre duas é o quanto ela pesa na instalação inteira (esses pesos vieram de uma
instalação real):

| Começo (%) | Peso | Online (pacstrap + AUR) | Offline (cópia do pendrive) |
|---|---|---|---|
| 0 | 2 | Idioma e layout de teclado | Idioma e layout de teclado |
| 2 | 2 | espelho (mirror) | espelho (mirror) |
| 4 | 5 | Particionar o disco | Particionar o disco |
| 9 | 4 | Formatar e montar | Formatar e montar |
| 13 | 25 / **59** | **Baixar / instalar pacotes** (`pacstrap`) | **Copiar o sistema do pendrive** (rsync) |
| 38 / 72 | 16 / 13 | Sistema no chroot (locale, keymap, usuários, zram) | Sistema no chroot (locale, keymap, usuários, zram) |
| 54 | **31** | **Compilar pacotes AUR (yay)** | — |
| 85 | 11 | Área de trabalho, greeter, serviços e dotfiles | idem |
| 96 | 3 | Bootloader | Bootloader |
| 99 | 1 | Finalização (desmontar, sincronizar) | idem |

Ou seja: no online a AUR é a etapa mais pesada (compilar o yay em Rust + os
pacotes da AUR) e no offline a cópia do pendrive é quase tudo.

Os scripts do chroot anunciam as suas etapas com `cstage`/`cnote`/`cact`
(`install/chroot/helpers.sh`, chamadas de `all.sh` e `20-aur.sh`) — por isso
"compilar os pacotes AUR" aparece como etapa própria em vez de ficar escondido
em "bootloader e finalização". A saída do `yay` deixou de ir para `/dev/null` e
passa a aparecer no log da tela.

Se o `install.sh` for uma versão antiga (sem `NLSTEPS`), o servidor monta a
lista pela ordem das porcentagens das etapas que aparecerem no log, e o
navegador tem um plano reserva por modo (`FALLBACK_STEPS` em
`web/static/app.js`) — a tela nunca fica vazia.

#### O anel: porcentagem real da instalação inteira

O anel mostra a **porcentagem do todo**, e ela anda o tempo todo — nunca congela
entre uma etapa e outra e nunca anda para trás. Duas fontes, combinadas em
`web/server.py` (`_ring_apply`):

1. **O ritmo** — a cada troca de etapa o anel se sincroniza com o ponto do
   plano e volta a caminhar de onde está até 100% no tempo que falta para o fim
   previsto da instalação (`PACE_TOTAL_S`, ~25 min, perto da mediana de uma
   instalação real). É o que garante que o anel sempre termine em 100%, mesmo
   quando uma etapa estoura o previsto: o que sobrou é repartido pelas
   seguintes. Se a instalação atrasar muito, o passo tem um piso
   (`PACE_TOTAL_S * 0.15`) para o anel ficar lento em vez de dar um salto.
2. **O progresso real** — onde o log, o pacman ou a contagem de bytes dizem
   quanto da etapa já foi, essa fração é desenhada na fatia da etapa (`plan_w`):
   `Tamanho total download:` do pacman + os bytes do cache (funciona em qualquer
   idioma), o `N/M` do pacman, o `%`/`xfr#` do `rsync --info=progress2` e o
   `NN%|…| n/m` do meson. O real só vale por `REAL_TTL` (20 s): depois disso a
   estimativa assume de volta, para o anel não travar se o download travar.

O anel é limitado a `PACE_MAX_RUNNING = 99` durante a execução: **100% só
quando a instalação termina com sucesso**. E, no primeiro segundo — antes de o
instalador mandar o plano e a primeira etapa — o anel fica parado em 0%: sem
plano não há como estimar quanto da instalação já foi, e estimar errado era o
que fazia o anel aparecer em 99% logo no começo.

**No fim, o anel aparece em 100% antes da tela de sucesso.** As três últimas
etapas (desktop/boas-vindas, bootloader e finalização) são rápidas e as suas
linhas chegam no mesmo instante em que o `install.sh` escreve `NLRESULT|0` —
antes, o painel via só o `done` e trocava direto para a tela de sucesso com o
anel ainda no meio do caminho (73% → sucesso, pulando as três etapas). Agora o
servidor publica um `progress` com 100% **antes** do `done`, e o navegador segura
esse quadro por `DONE_HOLD_MS` (1,6 s) antes de trocar de tela. É só
apresentação: nada espera mais do que a instalação, e **no erro a troca continua
sendo na hora**.

#### A linha abaixo do anel: etapa · atividade

A linha mostra a etapa (ou a nota dela) **e o que está acontecendo agora**,
separados por `·`:

```
Baixar e compilar pacotes da AUR · Compilando umbriel-git
Copiando o sistema do pendrive (modo rápido, sem internet) · 3.120 de 48.902 arquivos
Habilitando serviços do sistema
```

A atividade vem de duas fontes, sempre traduzidas pelo servidor:

- **`NLACT`** do instalador — o que ele sabe: `Compilando yay-bin`,
  `Compilando umbriel-git, whatsapp-linux-desktop-bin`, o grupo inteiro de AUR de
  uma vez (o `yay` resolve o grupo numa transação só).
- **linhas do log** que são inequívocas e **não traduzidas** pelo programa que
  as escreve: `Compiling <crate>` do cargo, `NN%|#### | n/m` do meson e o
  `xfr#`/`to-chk` do rsync (que também dão o progresso real da cópia). O log do
  pacman é de propósito ignorado aqui: as palavras dele vêm traduzidas, e o
  `NLPROGRESS`/`Tamanho total` já cuidam da etapa.

A atividade **pertence à etapa**: quando a próxima etapa começa, ela some (e o
item longo é cortado para a linha não virar um parágrafo). A lista de etapas é
destacada pelo `idx` que o servidor manda, e não pela porcentagem — senão o
anel, que anda dentro da etapa, passaria à frente da lista.

#### Relógio e download no painel

- **Relógio digital** (`H:MM:SS`) no topo do painel: cada dígito é uma fita
  0-9 que rola com `translateY` quando o número muda. O tempo vem do
  `started` do servidor, então **recarregar a página no meio não volta a
  zero**; o total (`X min Y s`) aparece na tela de fim, nos dois modos.
- **Monitor de download** (só no modo online): quatro medidas em MB —
  `Tamanho total` (o que o pacman anunciou antes de começar), `Baixando`,
  `Média` (MB/s) e o nº de pacotes. A contagem é feita **medindo o cache do
  pacman** (`/var/cache/pacman/pkg` do alvo e o do chroot), com uma linha de
  base tirada no início da execução e guardada no checkpoint — assim uma
  execução reanexada continua contando do ponto em que parou, e o total não
  zera. Não depende do idioma do pacman nem do formato das linhas dele.
  Os caminhos podem ser sobrescritos com `NLINUX_CACHE_DIRS` (separados por
  `:`).
  O **total é um número, não uma soma**: das linhas com a forma
  `…: 1658,48 MiB` (o valor vem logo depois de `:` e fecha a linha, sem casar
  palavra traduzida) fica a **menor** da etapa, acima de 1 MiB. O pacman
  imprime dois totais — o de download e o instalado — e o de download é sempre
  o menor, porque `%CSIZE` é o `.pkg.tar.zst` comprimido e `%ISIZE` é o que fica
  instalado; escolher pelo menor funciona em qualquer ordem, enquanto somar as
  linhas daria um total que cresceria junto com o download e a fração real da
  etapa ficaria sempre em 100%, com o anel pulando para o fim dela. A medida do
  total só aparece durante a etapa que está baixando; fora dela some, em vez de
  mostrar um número velho, e a média some quando decai para zero.
  **De onde vem o número:** não é mensagem do espelho. O espelho entrega o banco
  sincronizado (cada pacote com `%CSIZE`/`%ISIZE` no `desc`) e os `.pkg.tar.zst`;
  o pacman soma esses campos dos pacotes da transação e imprime o resultado. Por
  isso o valor muda a cada execução (versões, espelho, o que já está no cache) —
  o painel mostra o que o pacman disse na hora e não tem nenhum número fixo.

### Testes do instalador web

O painel só dá para exercitar de verdade numa máquina real, do zero e por ~25
minutos. Para isso existe `web/tests/`, com quatro suítes que dão retorno
rápido quando o painel muda:

```bash
web/tests/run-tests.sh              # o que der para rodar
web/tests/run-tests.sh --install    # baixa o node_modules antes (precisa de rede)
```

| Suíte | Alvo | O que confere |
|---|---|---|
| `server_test.py` | `web/server.py` | anel (ritmo do plano, progresso real, cap de 99%, `progress` de 100% antes do `done`), total do download (o menor da etapa, em qualquer ordem, e com teto na fração), atividade `NLACT` traduzida nos 7 idiomas, resiliência/checkpoint, e a coerência entre o plano do `install.sh`, o reserva do `app.js`, a tabela de pesos acima e as traduções |
| `e2e_test.py` | log → servidor → HTTP | o `event: progress` **na fio** e o `state` de reconexão, com o servidor de verdade numa porta livre |
| `client_test.js` | `web/static/app.js` | o que o usuário vê: a linha `etapa · atividade`, a lista destacada pelo índice, o plano de reserva, queda de stream, o monitor do download (total/baixando/média), o anel em 100% segurado antes da tela de sucesso, log e relógio (jsdom) |
| `css_test.js` | `web/static/style.css` | sintaxe do CSS, as regras de que o anel e o relógio dependem, a linha do download e a ausência da caixinha azul sobre o log (css-tree) |

As duas Python usam só a biblioteca padrão, não pedem root e não encostam nos
arquivos de `/tmp/nlinux-*` (criam uma pasta temporária). As duas de
JavaScript precisam de node + `npm install` em `web/tests/`. Detalhes em
[`web/tests/README.md`](web/tests/README.md). Nada disso é usado pelo build do
ISO.

### Arquivos e variáveis

| Caminho (live) | Papel |
|---|---|
| `/tmp/nlinux-install.log` | saída completa da execução atual (o `install.sh` a relê ao falhar, para gravar o marcador de erro no disco) |
| `/tmp/nlinux-install.log.1` | log da execução anterior (rotacionado a cada novo `POST /api/install`) |
| `/tmp/nlinux-install-state.json` | checkpoint do estado (reanexação após queda do servidor) |
| `/tmp/nlinux-web.log` | stdout/stderr do servidor, com marcador de cada reinício do supervisor |
| `/var/log/install-error.log` (instalado) | resumo da falha + últimas linhas do log, para ler depois sem o live |

Variáveis de ambiente do servidor: `NLINUX_WEB_PORT` (padrão `8765`),
`NLINUX_LOG_PATH` e `NLINUX_STATE_PATH` (útil para testar fora do live),
`NLINUX_CACHE_DIRS` (diretórios do cache do pacman usados como contador de
download, separados por `:`).

### Diagnóstico

```bash
curl -s http://127.0.0.1:8765/api/status   # estado real da execução (pct, etapa, code)
tail -f /tmp/nlinux-install.log            # log vivo da instalação
tail -f /tmp/nlinux-web.log                # reinícios e erros do servidor
```

O live também tem **swap em RAM comprimida**: `iso/airootfs/etc/systemd/zram-generator.conf`
(`zram-size = min(ram / 2, 4096)`, zstd) com o `zram-generator` de
`iso/packages.live`. Sem ele, `rsync`/`pacstrap`/`mkinitcpio` disputam memória com
o Firefox e o OOM killer encerra a janela do instalador no meio da cópia.

---

## Etapas no chroot (sistema instalado)

Roteiro: `install.sh` → `install/chroot/all.sh` → cada etapa abaixo.

No painel web essas etapas viram os blocos "Sistema no chroot", "Compilar
pacotes AUR" (só no online) e "Área de trabalho" da lista de progresso: quem
avisa é o `all.sh`, com `cstage`/`cnote`/`cact` (ver
[Conversa entre o servidor e o `install.sh`](#conversa-entre-o-servidor-e-o-installsh)).

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
  `etc/systemd/zram-generator.conf` (swap em RAM comprimida),
  `usr/local/bin/nlinux-installer{,-gui}`.
- **Etapas da instalação**: `install/chroot/*.sh`.
- **Textos do instalador web** (7 idiomas): `install/translations.py` — é a fonte
  única; o `web/server.py` e o `web/static/app.js` só pedem as chaves
  (`stage.*`, `web.*`, `tui.*`, `part.*`).
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
