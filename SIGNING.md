# Assinatura de commits e tags

Este documento descreve como configurar a assinatura GPG do NLinux nas duas
máquinas (casa e trabalho), como publicar a chave e como fazer backup/rotação.

O script que faz o trabalho pesado é
[`scripts/setup-signing.sh`](scripts/setup-signing.sh).

## Por que uma chave nova

A chave antiga (`69B8B38D1DFF6CDA`) assinou as releases até 2026.10.15, mas não
há backup da parte secreta dela. Sem a chave secreta não é possível assinar
novos commits/tags nem emitir um certificado de revogação. Por isso ela fica
**aposentada**: continua servindo para verificar as tags antigas, e a chave nova
passa a assinar as próximas releases. Como a parte secreta não existe mais, não
é possível revogar a chave antiga; use-a apenas para conferir o histórico.

## Modelo: uma subchave por máquina

```
chave primária  (só certifica; guardada OFFLINE, fora das duas máquinas)
  ├── subchave de assinatura — casa
  └── subchave de assinatura — trabalho
```

- Cada máquina recebe **somente a sua subchave secreta**.
- A chave primária secreta não fica em nenhuma das duas: existe apenas no
  backup completo, que deve ser guardado em pendrive/cofre offline.
- Se uma máquina for perdida ou comprometida, só aquela subchave precisa ser
  revogada; a outra continua válida.
- O GitHub mostra **Verified** para commits/tags assinados por qualquer uma das
  subchaves, porque a verificação sobe até a chave primária publicada.

A chave de releases atual usa o UID
`NLinux Releases <nilsonlinux@users.noreply.github.com>`. Chaves novas podem
usar `nilsonlinux@gmail.com` ou o endereço `users.noreply.github.com`; em ambos
os casos o e-mail precisa estar associado à sua conta do GitHub para o selo
**Verified** aparecer.

```bash
# conferir o UID da chave que está no repositório
gpg --show-keys --with-colons nlinux-releases-gpg-pub.asc | grep '^uid'
```

## Pré-requisitos

Em qualquer Linux com `bash`, `gpg` 2.2+ e `git` 2.20+:

| Distro | Pacotes |
| --- | --- |
| Arch/NLinux | `gnupg pinentry git` |
| Debian/Ubuntu | `gnupg pinentry-curses git` |
| Fedora | `gnupg2 pinentry git` |

No Arch/NLinux:

```bash
sudo pacman -S --needed gnupg pinentry git
```

Não é preciso ser root para usar o script.

## Máquina 1 — criar a chave (bootstrap)

Escolha uma máquina para ser a primeira (o exemplo usa `casa`). No repositório:

```bash
cd ~/Projetos/nlinux-iso-build     # ajuste o caminho
git pull
./scripts/setup-signing.sh bootstrap --machine casa --other trabalho
```

O script vai:

1. pedir uma **passphrase** (mínimo 12 caracteres) — use uma frase longa e
   guarde-a no gerenciador de senhas;
2. criar a chave primária (só certificação, validade de 2 anos);
3. criar duas subchaves de assinatura (uma para cada máquina);
4. exportar os pacotes, o backup completo e o certificado de revogação em
   `~/.config/nlinux-signing/`;
5. validar o backup importando-o num chaveiro temporário;
6. apagar desta máquina a chave primária secreta e a subchave da outra máquina;
7. configurar o Git global (`user.signingkey`, `commit.gpgsign`,
   `tag.gpgSign`, `log.showSignature`) e o pinentry do GnuPG.

No fim, a pasta `~/.config/nlinux-signing/` terá algo como:

| Arquivo | O que é | Onde guardar |
| --- | --- | --- |
| `machine-casa.asc` | subchave secreta desta máquina | pode ficar nesta máquina |
| `machine-trabalho.asc` | subchave secreta da outra máquina | levar para a outra máquina |
| `full-secret-backup.asc` | chave primária + as duas subchaves | **offline** (pendrive/cofre) |
| `revocation.asc` | certificado de revogação da chave primária | **offline** |
| `public.asc` | chave pública | pode ser publicada |
| `keys.env` | metadados locais (não contém segredo) | pode ficar |
| `SHA256SUMS` | conferência de integridade | junto do backup |

> **Importante:** depois de conferir que o backup abre, mova
> `full-secret-backup.asc`, `revocation.asc` e `SHA256SUMS` para um pendrive ou
> cofre offline e **apague-os desta máquina**. Sem esse backup não dá para criar
> novas subchaves nem revogar a chave. Se quiser manter uma cópia local, saiba
> que ela reduz o ganho de segurança do modelo.

### Teste imediato

```bash
./scripts/setup-signing.sh verify
```

Saída esperada: commit com status `G` (ou `U`, se a confiança ainda não subiu) e
tag com “Assinatura válida”.

## Máquina 2 — entrar com a subchave (join)

Leve `machine-trabalho.asc` para a outra máquina por pendrive ou por um canal
criptografado. **Não** mande a chave secreta por chat/e-mail comum nem commite
nada disso no repositório.

Na máquina 2:

```bash
cd ~/Projetos/nlinux-iso-build     # ajuste o caminho
git pull
./scripts/setup-signing.sh join \
  --bundle /caminho/para/machine-trabalho.asc \
  --machine trabalho
./scripts/setup-signing.sh verify
```

O `join` importa a subchave, marca a chave primária como confiável e configura
o Git global daquela máquina. A chave primária secreta **não** é importada.

Depois de confirmar o `verify`, apague o `machine-trabalho.asc` do pendrive (ou
guarde-o no mesmo cofre offline do backup).

## GitHub — cadastrar a chave pública

Isso é feito **uma vez só**, em qualquer uma das máquinas:

1. Abra <https://github.com/settings/gpg/new>.
2. Cole o conteúdo de `~/.config/nlinux-signing/public.asc`:

   ```bash
   cat ~/.config/nlinux-signing/public.asc
   ```

3. Confirme em <https://github.com/settings/emails> que o e-mail do UID
   (`nilsonlinux@users.noreply.github.com` ou `nilsonlinux@gmail.com`) está
   associado à conta.

A partir daí, commits e tags assinados por `casa` ou `trabalho` aparecem como
**Verified**.

## Publicar a chave nova no repositório

Ainda na máquina 1:

```bash
./scripts/setup-signing.sh publish
```

O comando:

- preserva a chave antiga em `nlinux-releases-gpg-pub-legacy.asc`;
- copia a chave nova para `nlinux-releases-gpg-pub.asc`;
- atualiza a seção “Assinatura das releases (GPG)” do `README.md`;
- mostra o `git diff` (não commita nada).

Revise e commite **com assinatura**:

```bash
git diff
git add nlinux-releases-gpg-pub.asc nlinux-releases-gpg-pub-legacy.asc README.md
git commit -S -m "assinatura: nova chave de releases NLinux"
git push
```

## Rotina de release

Sempre que for marcar uma release:

```bash
# tag assinada (o -s já cria uma tag anotada)
git tag -s 2026.12.01 -m "NLinux 2026.12.01"

# confira antes de enviar
git tag -v 2026.12.01
git push origin 2026.12.01
```

Com `tag.gpgSign = true` no Git global, até `git tag -a ...` sai assinada. Tags
**lightweight** (`git tag nome`, sem `-a`/`-s`) não têm assinatura e não devem ser
usadas em release. A tag `2026.11.05` é anotada e sua assinatura GPG é válida.
Não recrie tags já publicadas; para corrigir uma release, publique uma nova
versão:

```bash
git tag -s 2026.11.04 -m "NLinux 2026.11.04"
git tag -v 2026.11.04
git push origin 2026.11.04
```

Para verificar tags antigas depois da troca, importe também a chave legada:

```bash
gpg --import nlinux-releases-gpg-pub-legacy.asc
git tag -v 2026.10.15
```

## Backup, restauração e rotação

### O que guardar

- `full-secret-backup.asc` — sem ele não há como emitir novas subchaves.
- `revocation.asc` — usado se a chave primária for comprometida.
- A passphrase — no gerenciador de senhas, nunca junto do backup.
- `SHA256SUMS` — para conferir se o backup não corrompeu.

O backup completo já sai protegido pela passphrase da chave. Ainda assim,
mantenha-o fora de máquinas conectadas e, de preferência, em duas mídias
diferentes (pendrive + cofre).

### Restaurar numa máquina nova

```bash
export GNUPGHOME="$HOME/.gnupg-restore"
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --import /caminho/full-secret-backup.asc
gpg --list-secret-keys --keyid-format=long
```

Com a chave primária restaurada você pode:

- criar outra subchave: `gpg --quick-add-key <FPR> ed25519 sign 2y`;
- revogar uma subchave perdida: `gpg --edit-key <FPR>`, `key N`, `revkey`;
- exportar a chave pública atualizada e rodar `publish` de novo.

Depois de usar, apague o chaveiro temporário ou volte o backup para o cofre.

### Se uma máquina for perdida

1. Restaure o backup completo num ambiente controlado.
2. Revogue **apenas** a subchave daquela máquina.
3. Exporte a chave pública atualizada.
4. Rode `./scripts/setup-signing.sh publish` e commite.
5. Cadastre/atualize a chave pública no GitHub.

Não é necessário revogar a chave primária nem a subchave da outra máquina.

## Problemas comuns

**“Inappropriate ioctl for device” / “Sem pinentry” / pinentry não abre**

O setup prefere `pinentry-curses`, que funciona em Wayland, X11, SSH e console.
Se o `gpg-agent.conf` ainda apontar para um pinentry gráfico (por exemplo,
`pinentry-gnome3`) e a sessão não for GNOME, troque:

```bash
sed -i 's|^pinentry-program .*|pinentry-program /usr/bin/pinentry-curses|' \
  ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

No `fish`, garanta também o terminal correto:

```fish
set -gx GPG_TTY (tty)
```

No `bash`/`zsh`:

```bash
export GPG_TTY="$(tty)"
```

Depois rode `./scripts/setup-signing.sh verify` de novo. Se quiser mesmo o
pinentry gráfico, edite `~/.gnupg/gpg-agent.conf` manualmente e mate o agente
com `gpgconf --kill gpg-agent`.

**Commit falha com “gpg failed to sign the data”**

```bash
gpg --list-secret-keys --keyid-format=long
git config --global --get user.signingkey
git config --global --get gpg.program
```

O `user.signingkey` precisa ser a impressão digital da **chave primária** (40
caracteres). O GnuPG escolhe sozinho a subchave de assinatura disponível.

**GitHub mostra “Unverified”**

- Confirme que o e-mail do commit é exatamente um UID da chave
  (`nilsonlinux@gmail.com`).
- Confirme que a chave pública foi cadastrada em
  <https://github.com/settings/gpg/new>.
- Confirme que o e-mail está verificado em <https://github.com/settings/emails>.
- Em commits antigos, o selo continua vermelho: eles foram assinados com a chave
  antiga ou não foram assinados.

**Verificar o estado atual**

```bash
./scripts/setup-signing.sh doctor
```

## O que nunca fazer

- Commitar `full-secret-backup.asc`, `machine-*.asc`, `revocation.asc` ou
  `keys.env`.
- Guardar a passphrase no histórico do shell, em script ou no repositório.
- Usar a mesma chave secreta nas duas máquinas (era o modelo antigo; perde a
  vantagem de revogação independente).
- Criar tags de release com `git tag nome` (lightweight).
