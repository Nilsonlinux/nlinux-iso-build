# Testes do instalador web

O painel do instalador é difícil de exercitar de verdade: só roda numa máquina
real, do zero, por ~25 minutos, com rede, disco e compilação Rust. Estas
suítes existem para dar retorno rápido e determinístico quando algo no painel
muda — principalmente o **anel de progresso** e a **linha `etapa · atividade`**.

Nada aqui é necessário para o build do ISO: o `build-iso.sh` remove `web/tests`
de `/opt/noctalia-installer` ao embutir o instalador, então as suítes (e o
`node_modules` delas) não vão para a imagem.

## Rodar

```bash
web/tests/run-tests.sh              # o que der para rodar
web/tests/run-tests.sh --install    # baixa o node_modules antes (precisa de rede)
```

Ou uma suíte por vez, da raiz do repositório:

```bash
python3 web/tests/server_test.py    # servidor
python3 web/tests/e2e_test.py       # ponta a ponta
cd web/tests && npm install         # uma vez, precisa de node >= 18
node web/tests/client_test.js       # painel (jsdom)
node web/tests/css_test.js          # css (css-tree)
```

As duas Python usam **só a biblioteca padrão** (Python >= 3.6), não precisam de
nada instalado e não pedem root. Elas também não encostam nos arquivos de
instalação de verdade (`/tmp/nlinux-install.log`, `/tmp/nlinux-install-state.json`):
criam uma pasta temporária e passam o caminho por `NLINUX_LOG_PATH` /
`NLINUX_STATE_PATH` / `NLINUX_CACHE_DIRS`, que é a mesma engrenagem que o
servidor usa para o checkpoint. Por isso dá para rodar as duas em paralelo.

As duas de JavaScript dependem de `jsdom` e `css-tree` (`npm install` em
`web/tests/`). Sem node, o `run-tests.sh` avisa e segue com as Python — mas
nesse caso **nada** checa o `app.js` e o `style.css`.

Cada suíte imprime `ok`/`FAIL` por checagem e sai com status 1 se alguma falhar.

## O que cada uma cobre

| Suíte | Alvo | Papel |
|---|---|---|
| `server_test.py` | `web/server.py` | O cérebro. Importa o módulo e alimenta o log com as linhas que o `install.sh` **realmente** escreve (`NLSTEPS`, `NLPROGRESS`, `NLSTEP`, `NLNOTE`, `NLACT`, `NLRESULT`), conferindo o que o painel receberia. |
| `e2e_test.py` | log → servidor → HTTP | Sobe o servidor de verdade numa porta livre, escreve no arquivo de log e lê `/api/stream` e `/api/status` como o navegador leria. É o que garante o formato do `event: progress` **na fio**. |
| `client_test.js` | `web/static/app.js` | O que o usuário vê: a linha `etapa · atividade`, a lista destacando a etapa certa, o plano de reserva, o log ao vivo, a queda do stream e o reset ao iniciar outra instalação. Roda o `app.js` inteiro no DOM do `index.html` (jsdom), com `fetch`/`EventSource` controlados. |
| `css_test.js` | `web/static/style.css` | Sintaxe (erro de CSS é descartado calado pelo navegador) e as regras de que o painel depende — por exemplo a altura da fita do relógio (`1.2em`) tem que bater com o `DIGIT_STEP` do `app.js`. |

### `server_test.py` em detalhe

- **anel: ritmo do plano** — o plano online/offline é consumido e a etapa atual
  fica no ponto certo do plano; o anel anda dentro da etapa e chega a 99%
  (100% é só no fim); o plano corrige o anel atrasado; o anel adiantado não
  volta; o piso do ritmo evita o salto quando a instalação atrasa muito; a
  etapa fora do plano não tem ritmo e o anel para.
- **anel: os primeiros segundos (relógio de verdade)** — o começo da execução,
  com a thread do anel de verdade e o relógio de verdade, online e offline: sem
  plano, só com o plano e ainda sem a primeira etapa, e com a primeira etapa. O
  anel tem que ficar em 0% e depois andar devagar. É o grupo que pegou o
  defeito do "99% logo no começo": o instalador manda `NLSTEPS` antes da
  primeira etapa, e a espera por essa etapa estava tratando "sem plano" como
  "faça a instalação inteira em 1 segundo".
- **anel: a instalação inteira em tempo simulado** — os tempos de cada etapa
  saem dos pesos do próprio plano (o peso é a fatia da instalação, logo é
  também a fatia do tempo), e a instalação inteira roda com o relógio
  controlado: o anel não volta atrás, bate com o plano em cada troca de etapa
  (tolerância de 6 pontos), cresce etapa a etapa, passa pelo progresso real
  dentro da etapa de download/cópia/compilação, nunca sai de 99% antes do fim
  e chega em 99% no fim previsto — nos dois modos.
- **anel: progresso real manda** — o total que o pacman diz que vai baixar
  (nos dois formatos de número, com e sem separador de milhar) alimenta a
  fração real; a fração não regride a cada tique e expira depois de `REAL_TTL`;
  o `N/M` do pacman, o `%`/`xfr#` do rsync e o `NN%|…| n/m` do meson também.
- **atividade** — `NLACT` traduzida nos 7 idiomas com o item no `%s`; ela não
  mexe na etapa nem na %, a repetida não polui o stream, a linha comum do log
  vira log e não atividade, o item longo é cortado, e a atividade some quando a
  etapa muda (a nota `NLNOTE` continua aparecendo sozinha).
- **plano e chroot** — o `build_plan` do `install.sh` tem os 10 passos do
  online e os 9 do offline, com o número sendo o **começo** da etapa e os pesos
  certos (AUR a mais pesada no online, cópia no offline); o `FALLBACK_STEPS` do
  `app.js` bate com o plano nos dois modos; a tabela de pesos do README bate
  com o plano; `20-aur.sh` anuncia o que compila e a nota morta do yay saiu.
- **traduções** — toda chave usada pelo `install.sh` e pelo `app.js` existe em
  pt/en/es/fr/de/it/ja, o `%s` da atividade está nos 7 e não sobra chave morta
  no código.
- **estado e resiliência** — o anel é uma thread que anda sozinha e para no
  fim; 100% só no sucesso, e a falha publica o erro sem marcar 100%; o
  checkpoint guarda etapa, %, atividade e argumento, e o estado reanexado traz
  a etapa, o plano e o anel voltando a ter ritmo.

### `client_test.js` em detalhe

- a página abre direto no painel quando já há instalação em curso, com a lista
  do servidor e a primeira etapa em destaque;
- a linha abaixo do anel é `etapa · atividade`, a atividade troca junto com a
  etapa e some quando a etapa nova começa;
- a lista é destacada pelo **índice** do servidor, não pela % (o anel anda
  dentro da etapa e passaria à frente), e a etapa seguinte não acende;
- sem `NLSTEPS` no log (execução antiga), entra o plano de reserva do próprio
  app, online e offline, sem destacar duas etapas;
- queda e volta do stream: aparece "Reconectando" e o progresso que chega pelo
  watchdog não atropela esse rótulo;
- log e cauda ao vivo, e o reset completo ao iniciar outra instalação (rótulo,
  atividade, índice, anel, lista e log antigo).

## Ao mexer no painel

Rode `run-tests.sh` antes do commit. As suítes existem para pegar justamente o
tipo de defeito que não aparece olhando o código: um peso de etapa
deslocado, uma chave de tradução que sumiu, um `idx` que desalinha a lista, o
plano de reserva que não redesenha a caixa, uma propriedade de CSS que o
navegador ignora.

Quando uma checagem nova entrar, escreva o nome dela **em português** e
descreva o defeito, não a implementação: o nome é o que aparece quando algo
quebra, e é o que quem lê daqui a seis meses vai entender.
