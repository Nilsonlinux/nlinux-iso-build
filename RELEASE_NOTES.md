# NLinux — primeira release pública

<h2 align="center">⬇️ Download</h2>

<p align="center">
  <a href="https://drive.google.com/file/d/1f0HvYCJiIE4ApkFo9eoXRj1szay_rCk1/view?usp=sharing">NLinux ISO (Google Drive)</a> — ISO live, ~2,9 GB, para <code>x86_64</code>.<br>
  sha256 da ISO <code>5f51a47fff0ebd6472a079cded43023e87b4835cfdb073381397636922b85c81</code>
</p>

A primeira release pública do NLinux: uma distribuição baseada em Arch Linux, com desktop Wayland Umbriel, shell Noctalia V5, instalador visual e a loja NLinux Software já incluída.

<img width="1366" height="768" alt="image" src="https://github.com/user-attachments/assets/814eb651-1da1-45c5-9e1d-a1a14cd815a8" />

## ✨ O que vem no NLinux

- **Arch Linux rolling**, em uma ISO ao vivo para computadores `x86_64`.
- **Desktop Wayland** com compositor Umbriel, shell Noctalia V5 e tela de login greetd com noctalia-greeter.
- **Instalador visual em 10 etapas**, aberto no navegador a partir do ambiente live. Ele mostra o progresso real da instalação.
- **Instalação rápida offline**, a opção padrão, que copia o sistema a partir do pendrive sem precisar de internet.
<img width="1366" height="768" alt="nlinux-instalador-17" src="https://github.com/user-attachments/assets/298f0c84-a0ff-4bb1-a3e5-981b83c32736" />
- **Instalação completa online**, que instala os pacotes com `pacstrap` e compila os componentes AUR necessários.
- **Escolha de ext4 ou btrfs**. No btrfs, o instalador cria subvolumes para raiz, home, logs e cache de pacotes.
- **Criptografia opcional com LUKS2**.
- **Opções de instalação** para apagar o disco ou instalar ao lado de outro sistema, incluindo Windows.
- **Seleção de perfil gráfico**.

## 🧭 Instalador

O assistente reúne as principais escolhas em um fluxo guiado:
<img width="1366" height="768" alt="nlinux-instalador-01" src="https://github.com/user-attachments/assets/b74f15c7-b56e-4071-a318-4ab7a280a461" />

1. Idioma, teclado e fuso horário.
2. Disco de destino.
3. Instalação apagando o disco ou ao lado de outro sistema.
4. Sistema de arquivos: ext4 ou btrfs.
5. Espelho de pacotes.
6. Instalação rápida offline ou completa online.
7. Criptografia LUKS2 opcional.
8. Perfil gráfico.
9. Usuário, nome da máquina e senha.
10. Revisão das escolhas e confirmação.

A instalação rápida copia o sistema do pendrive e pode ser feita sem rede. A instalação online baixa os pacotes e precisa de conexão. O painel de progresso acompanha a execução; se a janela ou o navegador for fechado, a instalação continua em segundo plano e pode ser retomada no painel.

## 🛍️ NLinux Software
<img width="1366" height="768" alt="nlinux-instalador-23" src="https://github.com/user-attachments/assets/faf26600-6c2a-4a40-9f50-ff518d4ee0d7" />

A loja acompanha a distro como aplicativo nativo, não como uma aba de navegador. Ela oferece:

- Busca, categorias, filtro de aplicativos instalados e detalhes dos pacotes.
- Instalação com autenticação do sistema e progresso da transação.
- Aplicativos dos repositórios do Arch e opções AUR compatíveis com `paru` ou `yay`.
- Catálogo e mídias armazenados localmente, para continuar abrindo sem conexão.
- Atualização automática do catálogo quando uma nova versão é publicada.
- Verificação SHA-256 dos assets do catálogo e assinatura GPG do pacote da loja.
- Interface em português, inglês, espanhol, francês, alemão, italiano e japonês.
- Tema claro e escuro.

## 🌐 Idiomas

O instalador permite selecionar entre Brasil, Estados Unidos, Portugal, Reino Unido, Espanha, França, Alemanha, Itália e Japão. A escolha configura conjuntamente o idioma do sistema, o teclado, o fuso horário e o idioma do instalador.

A interface da loja está disponível em sete idiomas: português, inglês, espanhol, francês, alemão, italiano e japonês.

## 💾 Requisitos e instalação

- Arquitetura: `x86_64`.
- ISO: aproximadamente 2,9 GB.
- Pendrive recomendado: 8 GB ou maior.
- **UEFI é necessário para instalar.** A ISO também inclui opções de boot BIOS para experimentar o ambiente live, mas o instalador exige UEFI.
- Para dual boot, é necessária uma partição EFI FAT32 existente e mais de 5 GiB livres. O instalador pode oferecer o redimensionamento de partição NTFS quando necessário.
- Como referência, 20 GB ou mais de espaço em disco deixam margem para o sistema, aplicativos e atualizações.
- Internet: opcional na instalação rápida offline; necessária na instalação completa online.

> Antes de alterar partições ou redimensionar NTFS, faça backup dos dados. Em dual boot com Windows, desative o BitLocker e a Inicialização Rápida/hibernação antes de prosseguir. No modo de apagar o disco, os dados do disco selecionado serão removidos.

## ⚙️ Sistema instalado

- Boot com systemd-boot e suporte a LUKS2 no initramfs quando a criptografia é escolhida.
- Swap em zram, configurado até metade da memória RAM, com limite de 4 GB.
- Repositórios `core`, `extra` e `multilib`; multilib vem habilitado.
- NetworkManager como gerenciador de rede, Bluetooth e sincronização de horário.
- `yay` incluído para tarefas relacionadas à AUR.
- Atualize o sistema com `sudo pacman -Syu`.

## 📝 Destaques desta primeira versão

- Atualização do sistema com indicação do progresso real.
- Catálogo da loja disponível no ambiente live, inclusive sem conexão.
- Multilib habilitado por padrão.
- Som de notificação próprio do NLinux e ajustes no áudio da interface.
- Melhorias no boot UEFI, incluindo compatibilidade com firmwares que não mantêm variáveis de boot na NVRAM.
- Barra superior reorganizada, relógio com segundos e indicadores de sistema simplificados.

## 📚 Documentação

- [Documentação do NLinux](https://nilsonlinux.github.io/docs.html)
- [Recursos da distribuição](https://nilsonlinux.github.io/recursos.html)
- [Loja NLinux Software](https://nilsonlinux.github.io/loja.html)
- [Código e instruções para compilar a ISO](https://github.com/Nilsonlinux/nlinux-iso-build)
