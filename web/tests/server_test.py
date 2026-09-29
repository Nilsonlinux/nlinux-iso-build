#!/usr/bin/env python3
"""Testes do web/server.py: anel com ritmo real, atividade e resiliência.

Roda o servidor de verdade (importa o módulo, com log/estado/cache apontados
para uma pasta temporária) e alimenta o log como o install.sh faria, conferindo
os eventos que o painel recebe. Também cruza o plano do install.sh com o
reserva do app.js, com a tabela do README e com as traduções.

    python3 web/tests/server_test.py        # da raiz do repositório
"""
import atexit
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

# Raiz do repositório: web/tests/ -> web/ -> <repo>.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Nada é escrito fora da pasta temporária: os testes podem rodar em paralelo e
# não dependem de /tmp/nlinux-*, que pertence à instalação de verdade.
TMP = tempfile.mkdtemp(prefix="nlinux-tests-")
atexit.register(shutil.rmtree, TMP, True)
LOG = os.path.join(TMP, "install.log")
STATE = os.path.join(TMP, "state.json")
CACHE = os.path.join(TMP, "cache")
os.environ["NLINUX_LOG_PATH"] = LOG
os.environ["NLINUX_STATE_PATH"] = STATE
os.environ["NLINUX_CACHE_DIRS"] = CACHE

fails = []


def check(name, cond, extra=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s -> %s" % (name, extra))
        fails.append(name)


def load():
    spec = importlib.util.spec_from_file_location(
        "srv", os.path.join(REPO, "web", "server.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # Um assinante permanente: o Broadcaster não guarda histórico, então é
    # preciso estar conectado ANTES de o evento ser publicado.
    mod._subs_q = mod.BROADCAST.subscribe()
    return mod


def drain(mod):
    """Drena a fila do assinante: [(evento, dados), ...], na ordem de chegada."""
    out = []
    q = mod._subs_q
    while True:
        try:
            payload = q.popleft()
        except IndexError:
            return out
        head, _, rest = payload.partition("\n")
        out.append((head[len("event: "):], json.loads(rest[len("data: "):].strip())))


def heads(mod):
    """Drena a fila do assinante e devolve os nomes dos eventos, na ordem."""
    return [nome for nome, _ in drain(mod)]


def events(mod, sub):
    """Drena os eventos SSE acumulados do assinante para o evento `sub`."""
    return [dados for nome, dados in drain(mod) if nome == sub]


# Plano novo: o número é o COMEÇO da etapa e a distância entre duas é o peso.
#   online : 0, 2, 4, 9, 13, 38, 54, 85, 96, 99
#   offline: 0, 2, 4, 9, 13, 72, 85, 96, 99
ONLINE_PLAN = "NLSTEPS|0:stage.lang_key,2:stage.mirror,4:stage.disk,9:stage.fs," \
              "13:stage.pac.download,38:stage.chroot.system,54:stage.chroot.aur," \
              "85:stage.chroot.desktop,96:stage.boot,99:stage.final"
OFFLINE_PLAN = "NLSTEPS|0:stage.lang_key,2:stage.mirror,4:stage.disk,9:stage.fs," \
               "13:stage.copy.offline,72:stage.chroot.system,85:stage.chroot.desktop," \
               "96:stage.boot,99:stage.final"


def fresh(mod, plan, mode="online", lang="pt", total_s=1500.0, interval=1.0):
    for sub in ("progress", "state", "done", "log", "download", "error"):
        events(mod, sub)
    mod.PACE_TOTAL_S = total_s
    mod.PACE_INTERVAL = interval
    mod._begin_run(mode)
    mod._ui_lang = lang
    mod._handle_line(plan.encode(), [])
    return mod


def feed(mod, text):
    for line in text.split("\n"):
        mod._handle_line(line.encode(), [])


def elapsed_to(mod, frac, of="span"):
    """Empurra o relógio da thread do anel para uma fração do tempo."""
    mod._pace["at"] = time.time() - mod._pace[of] * frac


def fake_install(seconds=30):
    """Um processo que se apresenta como install.sh, para o teste de reanexar.

    O cmdline de um processo recém-criado pode sair vazio de /proc por alguns
    milissegundos (o kernel ainda não publicou o argv) — e o _pid_alive() do
    servidor, que é justamente o que decide se a instalação pode ser reanexada,
    olha esse arquivo. Por isso o teste ESPERA o cmdline aparecer em vez de
    apostar que já apareceu: no install de verdade a checagem acontece segundos
    depois do fork, mas aqui ela é imediata e viraria uma moeda.
    """
    proc = subprocess.Popen(
        ["bash", "-c", "exec -a 'bash /tmp/install.sh' sleep %d" % seconds])
    deadline = time.time() + 5.0
    while time.time() < deadline:
        try:
            with open("/proc/%d/cmdline" % proc.pid, "rb") as fh:
                if b"install.sh" in fh.read():
                    return proc
        except OSError:
            pass
        time.sleep(0.01)
    proc.terminate()
    raise SystemExit("o processo falso não ficou visível em /proc")


# ---------------------------------------------------------------------------
print("== anel: ritmo do plano ==")
m = load()
fresh(m, ONLINE_PLAN, total_s=1000.0)          # instalação de 1000 s = 16,7 min
feed(m, "NLPROGRESS|38|stage.chroot.system")   # a etapa vai de 38 a 54
ev = events(m, "progress")
check("plano online com 10 etapas", len(m.STATE["steps"]) == 10)
check("etapa atual = 38%", m.STATE["pct"] == 38)
check("idx da etapa no payload", ev[-1]["idx"] == 5, ev[-1])
check("payload traz o campo de atividade", ev[-1]["act"] == "", ev[-1])
check("peso da etapa no plano", m._pace["plan_w"] == 16, m._pace["plan_w"])
check("tempo até o fim previsto", 900 < m._pace["span"] <= 1000, m._pace["span"])

# O anel caminha de base a 100% no tempo que falta: 38 + 62*0,25.
elapsed_to(m, 0.25)
m._ring_apply()
check("anel avança dentro da etapa", 53 <= m.STATE["pct"] <= 54, m.STATE["pct"])
elapsed_to(m, 0.5)
m._ring_apply()
check("anel segue andando", 68 <= m.STATE["pct"] <= 69, m.STATE["pct"])
elapsed_to(m, 1.0)
m._ring_apply()
check("anel chega a 99% (100% é só no fim)", m.STATE["pct"] == 99, m.STATE["pct"])

# Etapa mais lenta que o previsto: o anel não congela, e quando a etapa
# acaba o plano o corrige para onde a instalação de fato está.
m = load()
fresh(m, ONLINE_PLAN, total_s=1000.0)
feed(m, "NLPROGRESS|54|stage.chroot.aur")     # a etapa vai de 54 a 85
elapsed_to(m, 0.25)
m._ring_apply()
aur_pct = m.STATE["pct"]
check("anel na etapa da AUR (54 + 46*0,25)", 65 <= aur_pct <= 66, aur_pct)
feed(m, "NLPROGRESS|85|stage.chroot.desktop")  # a AUR levou mais que o previsto
check("o plano corrige o anel atrasado", m.STATE["pct"] == 85, m.STATE["pct"])
check("base = o ponto do plano", m._pace["base"] == 85, m._pace["base"])
check("peso da etapa seguinte", m._pace["plan_w"] == 11, m._pace["plan_w"])
elapsed_to(m, 0.5)
m._ring_apply()
check("anel continua andando", 92 <= m.STATE["pct"] <= 93, m.STATE["pct"])
desk_pct = m.STATE["pct"]

# Etapa mais rápida que o previsto: o anel já passou do ponto do plano e é ele
# que manda — a lista e o anel nunca andam para trás.
feed(m, "NLPROGRESS|2|stage.mirror")
check("anel adiantado não volta", m.STATE["pct"] == desk_pct, m.STATE["pct"])
check("base = onde o anel está", m._pace["base"] == desk_pct, m._pace["base"])

# Instalação muito mais lenta que o previsto: o anel não salta para 100%,
# ele só passa a andar mais devagar.
m = load()
fresh(m, ONLINE_PLAN, total_s=100.0)
m.STATE["started"] = time.time() - 90          # já passou 90% do tempo previsto
feed(m, "NLPROGRESS|54|stage.chroot.aur")
check("piso do ritmo evita o salto", m._pace["span"] == 15.0, m._pace["span"])
m._ring_apply()
check("sem salto quando a instalação atrasa muito", m.STATE["pct"] == 54, m.STATE["pct"])
elapsed_to(m, 0.5)
m._ring_apply()
check("atrasado ainda anda, devagar", m.STATE["pct"] == 77, m.STATE["pct"])

# Nunca volta: uma medida atrás é ignorada.
before = m.STATE["pct"]
m._ring_apply(0.01)
check("anel não anda para trás", m.STATE["pct"] == before, m.STATE["pct"])

# Etapa fora do plano (install.sh antigo, sem NLSTEPS): só o real mexe.
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|38|stage.chroot.system")
m.STATE["step"] = "stage.desconhecida"
m._plan_reevaluate()
check("etapa fora do plano não tem ritmo", m._pace["span"] == 0.0, m._pace["span"])
check("anel parado sem plano e sem real", m._ring_apply() is None)

# ---------------------------------------------------------------------------
# O começo da execução, com o relógio de verdade.
#
# Foi aqui que o anel apareceu em 99%: o install.sh manda o plano (NLSTEPS)
# antes de mandar a primeira etapa, e a espera por essa etapa usava span=1.0
# como "sem ritmo" — que na verdade é "de 0 a 100% em um segundo". Um segundo
# depois o anel já estava em 99% e nunca mais voltava, porque o anel não anda
# para trás. Estes testes usam o relógio de verdade (e um tique curto) porque
# é exatamente o relógio que denuncia esse tipo de defeito.
# ---------------------------------------------------------------------------
print("== anel: os primeiros segundos (relógio de verdade) ==")


def primeiros_segundos(plan, feed_step, segundos=0.4):
    """Rode como o POST /api/install: começa e deixa a thread do anel trabalhar."""
    m = load()
    m.PACE_TOTAL_S, m.PACE_INTERVAL = 1500.0, 0.02
    m._begin_run("online")
    m._start_pace()
    if plan:
        feed(m, plan)
    if feed_step:
        feed(m, feed_step)
    time.sleep(segundos)
    return m


m = primeiros_segundos(None, None)
check("anel começa em 0%, sem o plano", m.STATE["pct"] == 0, m.STATE["pct"])
check("sem plano o anel não tem ritmo", m._pace["span"] == 0.0, m._pace["span"])

m = primeiros_segundos(ONLINE_PLAN, None)
check("anel continua em 0% depois do plano", m.STATE["pct"] == 0, m.STATE["pct"])
check("etapa ainda vazia", m.STATE["step"] == "", m.STATE["step"])

m = primeiros_segundos(ONLINE_PLAN, "NLSTEP|stage.lang_key")
check("primeira etapa não dispara o anel", m.STATE["pct"] == 0, m.STATE["pct"])
check("a primeira etapa dá o ritmo", m._pace["span"] > 1000, m._pace["span"])
time.sleep(1.2)
# 1% leva uns 15 s (a primeira etapa vale 2% de uma instalação de 25 min), o
# que importa é não ter pulado para a frente.
check("anel segue devagar no começo", 0 <= m.STATE["pct"] <= 2, m.STATE["pct"])

# O mesmo no offline: a diferença entre os modos não pode mudar o começo.
m = load()
m.PACE_TOTAL_S, m.PACE_INTERVAL = 1500.0, 0.02
m._begin_run("offline")
m._start_pace()
feed(m, OFFLINE_PLAN)
time.sleep(0.4)
check("offline também começa em 0%", m.STATE["pct"] == 0, m.STATE["pct"])
feed(m, "NLSTEP|stage.lang_key")
time.sleep(0.4)
check("offline não dispara o anel", m.STATE["pct"] == 0, m.STATE["pct"])

# ---------------------------------------------------------------------------
print("== anel: a instalação inteira em tempo simulado ==")


class relog:
    """Relógio controlado: a instalação inteira roda em tempo simulado.

    Substitui time.time() (só dentro do `with`) e dá um tique do anel por
    segundo simulado. É determinístico e instantâneo, ao contrário de dormir
    os 25 minutos de uma instalação de verdade.
    """

    def __init__(self):
        self._real = time.time
        self.base = self._real()
        self.advance = 0.0

    def __enter__(self):
        relog.time = self
        time.time = self.now
        return self

    def __exit__(self, *exc):
        time.time = self._real
        return False

    def now(self):
        return self.base + self.advance

    def passa(self, segundos, mod):
        """Avança o relógio, um tique de anel por segundo."""
        for _ in range(int(segundos)):
            self.advance += 1.0
            mod._ring_apply()


# Os tempos de cada etapa saem dos PESOS do próprio plano: o peso é a fatia da
# instalação, então a etapa que pesa 31 dura 31% do tempo. Assim a simulação
# mede o modelo do anel em vez de uma lista de tempos que o contradizia.
TOTAL_S = 1500.0


def tempos_do_plano(plan):
    """[(chave, % do plano, segundo em que a etapa começa)] tirados do plano."""
    itens = [(k, int(p)) for p, k in
             (par.split(":") for par in plan[len("NLSTEPS|"):].split(","))]
    out, t = [], 0.0
    for i, (chave, pct) in enumerate(itens):
        out.append((chave, pct, t))
        fim = itens[i + 1][1] if i + 1 < len(itens) else 100
        t += TOTAL_S * (fim - pct) / 100.0
    return out


def simula(plan, reais=()):
    """Roda a instalação inteira simulada; devolve (curva, erro).

    Cada etapa é anunciada no segundo que o plano diz, como o install.sh faz.
    """
    m = load()
    m.PACE_TOTAL_S, m.PACE_INTERVAL = TOTAL_S, 3600.0   # tiques à mão
    curva, anterior, t = [], -1, 0.0
    with relog() as rel:
        m._begin_run("online" if plan == ONLINE_PLAN else "offline")
        feed(m, plan)
        for i, (chave, pct, quando_i) in enumerate(tempos_do_plano(plan)):
            rel.passa(max(0, round(quando_i - t)), m)
            t = rel.advance
            feed(m, "NLSTEP|" + chave)
            if m.STATE["pct"] < anterior:
                return None, "anel voltou de %d para %d na %s" % (
                    anterior, m.STATE["pct"], chave)
            anterior = m.STATE["pct"]
            curva.append((quando_i, m.STATE["pct"], pct))
            if chave in reais:
                # Etapas com progresso real de verdade: a fração anda de 10 em
                # 10 por cento dentro da etapa.
                for k in range(1, 11):
                    m._ring_apply(k / 10.0)
                    curva.append((quando_i, m.STATE["pct"], None))
        rel.passa(int(TOTAL_S - t) + 1, m)
    return curva, None


for nome, plan, reais, tol in (
        ("online", ONLINE_PLAN, ("stage.pac.download", "stage.chroot.aur"), 6),
        ("offline", OFFLINE_PLAN, ("stage.copy.offline",), 6)):
    curva, erro = simula(plan, reais)
    check("%s: o anel não volta atrás na instalação inteira" % nome, erro is None, erro)
    if not curva:
        continue
    # A cada troca de etapa o anel tem que estar perto do ponto do plano: é
    # isso que faz a % ser crível (e o que denuncia um peso errado).
    fora = [(t, a, p) for t, a, p in curva if p is not None and abs(a - p) > tol]
    check("%s: o anel bate com o plano em cada etapa (tolerância %d)" % (nome, tol),
          not fora, fora)
    # E nunca sai de 99% antes do fim, para 100% significar "terminou".
    check("%s: nunca passa de 99%% antes do fim" % nome,
          max(a for _, a, _ in curva) <= 99, max(a for _, a, _ in curva))
    # A curva anda: entre duas etapas o anel sempre avançou.
    marcas = [a for _, a, p in curva if p is not None]
    check("%s: o anel cresce etapa a etapa" % nome,
          all(b >= a for a, b in zip(marcas, marcas[1:])), marcas)
    fim = curva[-1][1]
    check("%s: chega em 99%% no fim previsto" % nome, fim == 99, fim)
    # Antes da primeira etapa não acontece nada (foi o defeito do 99% cedo).
    comecou = [a for t, a, _ in curva if t == 0.0]
    check("%s: no primeiro segundo o anel está em 0%%" % nome,
          comecou and comecou[0] == 0, comecou)

# ---------------------------------------------------------------------------
print("== anel: progresso real manda ==")
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|13|stage.pac.download")   # 13 -> 38 (peso 25)
feed(m, "Tamanho total download:   1658,48 MiB")
check("total de download lido do log (pt, vírgula)",
      abs(m._size_total["bytes"] - 1658.48 * 1024**2) < 1, m._size_total["bytes"])
m = load()
fresh(m, ONLINE_PLAN, lang="en")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Total Download Size:  1658.48 MiB")
check("total de download lido do log (en, ponto)",
      abs(m._size_total["bytes"] - 1658.48 * 1024**2) < 1, m._size_total["bytes"])
m = load()
fresh(m, ONLINE_PLAN, lang="de")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, " resolvendo dependências...")
check("linha sem tamanho não conta", m._size_total["bytes"] == 0)

# O total é UM número, não uma soma: o "Total Installed Size" (que vem logo
# depois) e as linhas por pacote (tamanho no meio, velocidade depois) não podem
# mexer nele — senão o total cresceria junto com o download e a fração real da
# etapa ficaria sempre em 100% (o anel pulando para o fim da etapa).
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Total Download Size:   1658.48 MiB")
feed(m, "Total Installed Size:   4830.37 MiB")
feed(m, " glibc-2.44-1-x86_64.pkg.tar.zst         12.34 MiB  900.00 KiB/s 00:14")
check("o total do download não é somado nem trocado",
      abs(m._size_total["bytes"] - 1658.48 * 1024**2) < 1, m._size_total["bytes"])
ev = m._download_event()
check("o evento de download leva o total", abs(ev["total"] - 1658.48 * 1024**2) < 1, ev)
m._dl.update(bytes=700 * 1024**2, files=123, rate=5.0 * 1024**2)
ev = m._download_event()
check("evento de download com bytes, média e arquivos",
      ev["bytes"] == 700 * 1024**2 and ev["files"] == 123
      and abs(ev["rate"] - 5.0 * 1024**2) < 1024**2, ev)
check("total zerado quando o pacman não falou", load()._download_event()["total"] == 0)

# O total é escolhido pelo MENOR, não pela ordem: o pacman imprime o total de
# download e o total instalado, e a ordem dos dois não é contrato. Como o
# %CSIZE é o pacote comprimido e o %ISIZE é o instalado, o de download é
# sempre o menor — e é ele que interessa.
m = load()
fresh(m, ONLINE_PLAN, lang="en")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Total Installed Size:   4830.37 MiB")
feed(m, "Total Download Size:   1658.48 MiB")
check("total na ordem invertida ainda é o do download",
      abs(m._size_total["bytes"] - 1658.48 * 1024**2) < 1, m._size_total["bytes"])
m = load()
fresh(m, ONLINE_PLAN, lang="en")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Total Download Size:   1658.48 MiB")
feed(m, "Total Download Size:   1658.48 MiB")
feed(m, "Total Installed Size:   4830.37 MiB")
check("total repetido não vira soma",
      abs(m._size_total["bytes"] - 1658.48 * 1024**2) < 1, m._size_total["bytes"])
# O valor muda a cada execução (versões, espelho, cache): nada aqui pode
# depender do número — só da forma da linha. E uma linha qualquer do log que
# case com a forma não pode virar o total.
m = load()
fresh(m, ONLINE_PLAN, lang="en")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Algum passo levou 00:12 (cache: 512 B)")
feed(m, "Total Download Size:   8421.77 MiB")
check("linha miúda não vira total",
      abs(m._size_total["bytes"] - 8421.77 * 1024**2) < 1, m._size_total["bytes"])
# Total subestimado (o cache já vinha cheio de outra execução): a fração tem
# teto, senão o anel pularia para depois do fim da etapa.
m = load()
fresh(m, ONLINE_PLAN, lang="en")
feed(m, "NLPROGRESS|13|stage.pac.download")
feed(m, "Total Download Size:   100.00 MiB")
m._dl.update(bytes=500 * 1024**2, files=10, rate=0.0)
m._dl["base"], m._dl["base_files"] = 0, 0
m._pace["base"], m._pace["plan_w"] = 13.0, 25.0
m._pace["real"] = min(1.0, m._dl["bytes"] / m._size_total["bytes"])
m._pace["real_at"] = 0.0
m._ring_apply()
check("fração acima de 1 não empurra o anel para depois da etapa",
      13 <= m.STATE["pct"] <= 38, m.STATE["pct"])

# 50% dos bytes = 50% da etapa (13 + 25/2 = 25)
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|13|stage.pac.download")
m._size_total["bytes"] = int(1658.48 * 1024**2)
m._dl["bytes"] = m._size_total["bytes"] // 2
m._pace["real"] = m._dl["bytes"] / m._size_total["bytes"]
m._pace["real_at"] = time.time()
m._ring_apply()
check("anel usa a fração real dos bytes", 25 <= m.STATE["pct"] <= 26, m.STATE["pct"])
# A taxa de download alimenta o anel sozinha, sem passar pelo log.
m._ring_apply()
check("fração real não regride a cada tique", m.STATE["pct"] == 25, m.STATE["pct"])

# Medida velha: o ritmo assume de volta (para o anel não travar se o download travar)
m._pace["real_at"] = time.time() - m.REAL_TTL - 1
elapsed_to(m, 0.5)
m._ring_apply()
check("medida velha deixa de valer", m.STATE["pct"] == 56, m.STATE["pct"])

# A linha de progresso do pacman também vale (quando há TTY).
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|13|stage.pac.download")
m._push_real_progress("[ 350/705] Installing glibc (350/705)  120.5 MiB      45%")
check("pacman [N/M] vira fração real", 24 <= m.STATE["pct"] <= 25, m.STATE["pct"])
m = load()
fresh(m, ONLINE_PLAN, lang="ja")
feed(m, "NLPROGRESS|13|stage.pac.download")
m._push_real_progress("[ 700/705] インストール glibc (700/705)  1,2 GiB      99%")
check("pacman funciona em qualquer idioma", 37 <= m.STATE["pct"] <= 38, m.STATE["pct"])

# rsync --info=progress2 (cópia offline): a etapa vai de 13 a 72
m = load()
fresh(m, OFFLINE_PLAN, mode="offline")
feed(m, "NLPROGRESS|13|stage.copy.offline")
m._push_real_progress(
    " 45% 1,20G 2,60G  0:01:23 (xfr#1.234, to-chk=5.678/12.345) 12,00MB/s")
check("rsync vira fração real", 39 <= m.STATE["pct"] <= 40, m.STATE["pct"])
ev = events(m, "progress")
check("atividade da cópia sai do rsync",
      ev[-1]["act"] == "1.234 de 12.345 arquivos", ev[-1]["act"])
check("a % real vai no evento", ev[-1]["pct"] == 39, ev[-1]["pct"])
m = load()
fresh(m, OFFLINE_PLAN, mode="offline", lang="en")
feed(m, "NLPROGRESS|13|stage.copy.offline")
m._push_real_progress(
    " 45% 1.20G 2.60G  0:01:23 (xfr#1,234, to-chk=5,678/12,345) 12.00MB/s")
ev = events(m, "progress")
check("atividade da cópia em inglês", ev[-1]["act"] == "1,234 of 12,345 files", ev[-1]["act"])
# Em pt o milhar é ponto; o texto sai como o rsync escreveu.
m = load()
fresh(m, OFFLINE_PLAN, mode="offline")
feed(m, "NLPROGRESS|13|stage.copy.offline")
m._push_real_progress("  0% 0,00G 2,60G  0:00:01 (xfr#0, to-chk=1/12) 0,00MB/s")
ev = events(m, "progress")
check("rsync sem separador de milhar", ev[-1]["act"] == "0 de 12 arquivos", ev[-1]["act"])

# ---------------------------------------------------------------------------
print("== atividade: NLACT e log ==")
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|54|stage.chroot.aur")
feed(m, "NLACT|web.act.build|yay-bin")
ev = events(m, "progress")
check("NLACT vira texto traduzido", ev[-1]["act"] == "Compilando yay-bin", ev[-1])
check("NLACT não muda a etapa", m.STATE["step"] == "stage.chroot.aur")
check("NLACT não mexe na %", m.STATE["pct"] == 54, m.STATE["pct"])
feed(m, "NLACT|web.act.build|umbriel-git, whatsapp-linux-desktop-bin")
check("NLACT com lista de pacotes",
      events(m, "progress")[-1]["act"] ==
      "Compilando umbriel-git, whatsapp-linux-desktop-bin")
feed(m, "   Compiling proc-macro2 v1.0.103")
check("cargo vira atividade", events(m, "progress")[-1]["act"] == "Compilando proc-macro2")
feed(m, "Generating targets:  75%|########       | 27/36 eta 0:02")
check("meson vira fração real", abs(m._pace["real"] - 0.75) < 0.01, m._pace["real"])
feed(m, "NLSTEP|stage.chroot.desktop")
check("atividade some na próxima etapa", m.STATE["act_key"] == "")
check("payload sem atividade", events(m, "progress")[-1]["act"] == "")
feed(m, "NLPROGRESS|38|stage.chroot.system")
feed(m, "NLNOTE|stage.note.services")
feed(m, "NLACT|web.act.build|linux-zen")
ev = events(m, "progress")
check("rótulo = nota", ev[-1]["label"] == "Habilitando serviços do sistema", ev[-1]["label"])
check("atividade ao lado", ev[-1]["act"] == "Compilando linux-zen", ev[-1]["act"])
# Atividade repetida não gera evento (o log do build repete as mesmas linhas).
feed(m, "NLACT|web.act.build|linux-zen")
n = len(events(m, "progress"))
feed(m, "NLACT|web.act.build|linux-zen")
check("atividade repetida não polui o stream", len(events(m, "progress")) == n)

# Item longo (lista de AUR grande) não vira parágrafo na linha do anel.
long_list = ", ".join("pacote-%02d" % i for i in range(20))
feed(m, "NLACT|web.act.build|" + long_list)
act = events(m, "progress")[-1]["act"]
check("item longo é cortado", act.endswith("…") and len(act) < 100, act)
check("item cortado guarda o começo", act.startswith("Compilando pacote-00"), act)

# ---------------------------------------------------------------------------
print("== anel: thread, fim e resiliência ==")
m = load()
fresh(m, ONLINE_PLAN, total_s=4.0, interval=0.1)
feed(m, "NLPROGRESS|38|stage.chroot.system")
time.sleep(0.5)
check("thread do anel anda sozinha", m.STATE["pct"] > 38, m.STATE["pct"])
check("thread do anel está nomeada", m._pace_thread["thread"].name == "nlinux-pace")
m._finish(0)
check("100% ao terminar com sucesso", m.STATE["pct"] == 100, m.STATE["pct"])
check("evento done emitido", events(m, "done")[-1]["code"] == 0)
time.sleep(0.3)
check("thread do anel para no fim", not m._pace_thread["thread"].is_alive())

# O fim tem que passar pelas etapas de verdade (desktop, bootloader,
# finalização) e o anel chega a 100% ANTES do `done`: o painel segura o 100%
# na tela antes de trocar para a tela de sucesso, e sem esse quadro ele trocava
# de tela no mesmo instante em que o `done` chegava.
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|85|stage.chroot.desktop")
feed(m, "NLPROGRESS|96|stage.boot")
feed(m, "NLPROGRESS|99|stage.final")
ev = [e for e in events(m, "progress")]
check("as três últimas etapas viram eventos", [e["pct"] for e in ev[-3:]] == [85, 96, 99], ev[-3:])
heads(m)
m._finish(0)
saiu = drain(m)
nomes = [nome for nome, _ in saiu]
check("100% é publicado antes do done", nomes == ["progress", "done"], nomes)
quadro = [dados for nome, dados in saiu if nome == "progress"]
check("o quadro final vai a 100%", quadro and quadro[-1]["pct"] == 100, quadro)
# Na falha não vem esse quadro: o painel mostra o erro onde parou.
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|96|stage.boot")
heads(m)
m._finish(1, "falhou")
check("na falha não sai progresso de 100%", heads(m) == ["error", "done"], heads(m))

# Falha: o anel para onde estava e o painel mostra o erro.
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|13|stage.pac.download")
m._finish(1, "algo deu errado")
check("falha não marca 100%", m.STATE["pct"] == 13, m.STATE["pct"])
check("falha publica o erro", events(m, "error")[-1]["message"] == "algo deu errado")
check("checkpoint guarda a etapa",
      json.load(open(STATE, encoding="utf-8")).get("step") == "stage.pac.download")

# Reanexar uma instalação em andamento: o anel volta a andar.
# O painel só reanexa se o install.sh daquele PID ainda estiver vivo
# (web/server.py confere o cmdline em /proc), então o teste usa um processo
# que se apresenta como install.sh.
fake = fake_install()
with m._state_lock:
    m.STATE.update(running=True, done=False, code=None, error=None, pid=fake.pid,
                   step="stage.pac.download", pct=13, finished=0.0,
                   started=time.time() - 120)
    m.STATE["steps"] = [{"pct": int(pair.split(":")[0]), "key": pair.split(":")[1]}
                        for pair in ONLINE_PLAN.split("|")[1].split(",")]
m._state_save()
# O log precisa existir: sem ele o painel trata como instalação interrompida.
with open(LOG, "w", encoding="utf-8") as fh:
    fh.write(ONLINE_PLAN + "\nNLPROGRESS|13|stage.pac.download\n")
m = load()
m.adopt_running_install()
time.sleep(0.3)
with m._state_lock:
    check("estado reanexado traz a etapa", m.STATE["step"] == "stage.pac.download",
          m.STATE["step"])
    check("estado reanexado traz a %", m.STATE["pct"] == 13, m.STATE["pct"])
    check("plano reanexado", len(m.STATE["steps"]) == 10, len(m.STATE["steps"]))
    check("anel reanexado tem ritmo", m._pace["span"] > 1 and m._pace["base"] == 13,
          (m._pace["span"], m._pace["base"]))
    check("plano do anel reanexado", m._pace["plan_w"] == 25, m._pace["plan_w"])
fake.terminate()

# ---------------------------------------------------------------------------
print("== estado público ==")
m = load()
fresh(m, ONLINE_PLAN)
feed(m, "NLPROGRESS|54|stage.chroot.aur")
feed(m, "NLACT|web.act.build|umbriel-git")
pub = m._public_state()
check("steps no estado público têm pct e rótulo",
      pub["steps"][5]["pct"] == 38 and
      pub["steps"][5]["label"] == "Preparar o sistema (boot, initramfs, usuário)",
      pub["steps"][5])
check("estado público tem %, etapa e índice",
      pub["pct"] == 54 and pub["step"] == "stage.chroot.aur" and pub["idx"] == 6, pub["idx"])
check("estado público tem a atividade", pub["act"] == "Compilando umbriel-git")
m._state_save()
saved = json.load(open(STATE, encoding="utf-8"))
check("checkpoint guarda a atividade", saved["act_key"] == "web.act.build", saved.get("act_key"))
check("checkpoint guarda o argumento", saved["act_args"] == ["umbriel-git"], saved.get("act_args"))
for lang, expect in (("en", "Building umbriel-git"), ("de", "umbriel-git wird gebaut"),
                     ("ja", "umbriel-git をビルド中"), ("fr", "Compilation de umbriel-git"),
                     ("it", "Compilazione di umbriel-git"),
                     ("es", "Compilando umbriel-git")):
    m._ui_lang = lang
    check("atividade traduzida em %s" % lang,
          m._public_state()["act"] == expect, m._public_state()["act"])

# ---------------------------------------------------------------------------
print("== plano: install.sh ==")
sh = open(os.path.join(REPO, "install.sh"), encoding="utf-8").read()
modes = re.search(r"if \(\( OFFLINE \)\); then(.*?)else(.*?)fi\n", sh, re.S)
check("plano tem ramo offline e online", modes is not None)
common = re.findall(r"plan_add (\S+) (\d+)", sh[sh.index("build_plan() {"):
                                           sh.index("if (( OFFLINE ))")])
off = re.findall(r"plan_add (\S+) (\d+)", modes.group(1))
onl = re.findall(r"plan_add (\S+) (\d+)", modes.group(2))
tail = re.findall(r"plan_add (\S+) (\d+)",
                  sh[modes.end():sh.index("local item", modes.end())])
full_on = common + onl + tail
full_off = common + off + tail
check("plano completo do online", full_on == [
    ("stage.lang_key", "0"), ("stage.mirror", "2"), ("stage.disk", "4"),
    ("stage.fs", "9"), ("stage.pac.download", "13"), ("stage.chroot.system", "38"),
    ("stage.chroot.aur", "54"), ("stage.chroot.desktop", "85"),
    ("stage.boot", "96"), ("stage.final", "99")], full_on)
check("plano completo do offline", full_off == [
    ("stage.lang_key", "0"), ("stage.mirror", "2"), ("stage.disk", "4"),
    ("stage.fs", "9"), ("stage.copy.offline", "13"), ("stage.chroot.system", "72"),
    ("stage.chroot.desktop", "85"), ("stage.boot", "96"),
    ("stage.final", "99")], full_off)
pcts = [int(p) for _, p in full_on]
check("começos crescentes", pcts == sorted(pcts), pcts)
check("primeira etapa começa em 0%", pcts[0] == 0, pcts[0])
check("última etapa começa antes de 100%", pcts[-1] == 99, pcts[-1])


def slices(plan):
    """Peso de cada etapa: a distância (em %) até a próxima do plano."""
    return {plan[i][0]: int(plan[i + 1][1]) - int(plan[i][1])
            for i in range(len(plan) - 1)}


sl_on, sl_off = slices(full_on), slices(full_off)
check("AUR é a etapa mais pesada do online",
      max(sl_on, key=sl_on.get) == "stage.chroot.aur", sl_on)
check("cópia é a mais pesada do offline",
      max(sl_off, key=sl_off.get) == "stage.copy.offline", sl_off)
check("etapas iniciais são o que há de mais curto", sl_on["stage.lang_key"] == 2 and
      sl_on["stage.mirror"] == 2, sl_on)
check("online: download e AUR somam mais da metade",
      sl_on["stage.pac.download"] + sl_on["stage.chroot.aur"] > 50, sl_on)
check("offline: a cópia é quase tudo",
      sl_off["stage.copy.offline"] > 50, sl_off)
check("online tem etapa de AUR", "stage.chroot.aur" in sl_on)
check("offline não tem etapa de AUR", "stage.chroot.aur" not in sl_off)
check("plano enviado uma vez só", sh.count("printf 'NLSTEPS|%s\\n'") == 1)
check("act() emite NLACT", "printf 'NLACT|%s|%s\\n'" in sh)
check("helpers tem cact", "printf 'NLACT|%s|%s\\n'" in
      open(os.path.join(REPO, "install/chroot/helpers.sh"), encoding="utf-8").read())
aur = open(os.path.join(REPO, "install/chroot/20-aur.sh"), encoding="utf-8").read()
check("AUR anuncia o que compila", aur.count("cact web.act.build") == 2, aur.count("cact"))
check("AUR não deixa a nota fixa do yay", "stage.note.yay" not in aur)
check("tradução da nota do yay removida",
      "stage.note.yay" not in open(os.path.join(REPO, "install/translations.py"),
                                   encoding="utf-8").read())

# O mesmo plano no reserva do cliente.
app = open(os.path.join(REPO, "web/static/app.js"), encoding="utf-8").read()
for mode, plan in (("online", full_on), ("offline", full_off)):
    body = re.search(r"%s: \[(.*?)\n  \]" % mode, app, re.S).group(1)
    pairs = re.findall(r"\[(\d+), " + r'"(\S+)"\]', body)
    check("reserva do cliente bate com o plano (%s)" % mode,
          pairs == [(p, k) for k, p in plan], pairs)

# A tabela de pesos do README precisa bater com o plano, senão a documentação
# mente sobre quanto a etapa ocupa da instalação inteira.
def pesos(plan):
    out = []
    for i, (_, pct) in enumerate(plan):
        prox = int(plan[i + 1][1]) if i + 1 < len(plan) else 100
        out.append((int(pct), prox - int(pct)))
    return out


readme = open(os.path.join(REPO, "README.md"), encoding="utf-8").read()
tabela = re.search(r"\| Começo \(%\) \| Peso \|.*?\n\n", readme, re.S).group(0)
doc_on, doc_off = {}, {}
for linha in tabela.splitlines()[2:]:
    cel = [c.strip() for c in linha.strip().strip("|").split("|")]
    if len(cel) < 4 or not re.match(r"^[\d\s/]+$", cel[0].replace("**", "")):
        continue
    comes = [int(x) for x in cel[0].replace("**", "").split("/")]
    ps = [int(x) for x in cel[1].replace("**", "").split("/")]
    # "38 / 72 | 16 / 13" = começa em 38 no online e 72 no offline; já
    # "13 | 25 / 59" = mesmo começo, pesos diferentes. A coluna "—" diz que a
    # etapa não existe no outro modo.
    if len(comes) == 2:
        doc_on[comes[0]], doc_off[comes[1]] = ps[0], ps[1]
    else:
        doc_on[comes[0]] = ps[0]
        if cel[3] != "—":
            doc_off[comes[0]] = ps[1] if ps[1:] else ps[0]
check("README: pesos do online batem com o plano", doc_on == dict(pesos(full_on)),
      (doc_on, dict(pesos(full_on))))
check("README: pesos do offline batem com o plano", doc_off == dict(pesos(full_off)),
      (doc_off, dict(pesos(full_off))))

# ---------------------------------------------------------------------------
print("== traduções: cobertura das 7 línguas ==")
sys.path.insert(0, os.path.join(REPO, "install"))
import translations as TR  # noqa: E402

LANGS = ("pt", "en", "es", "fr", "de", "it", "ja")

# Toda chave que o instalador ou o painel pede tem de existir nos 7 idiomas.
shells = [os.path.join(REPO, "install.sh")] + [
    os.path.join(REPO, "install", "chroot", f)
    for f in sorted(os.listdir(os.path.join(REPO, "install", "chroot")))
    if f.endswith(".sh")]
used = set()
for path in shells:
    body = open(path, encoding="utf-8").read()
    used |= set(re.findall(r'"(?:c?stage|c?note|c?act) ([a-z][\w.]*)"', body))
# (?<![\w.]) evita casar o "t" final de createElement("div") e companhia.
used |= set(re.findall(r'(?<![\w.])t\("([\w.]+)"\)', app))
used |= set(re.findall(r"plan_add (\S+)", sh))
used |= {"stage.start", "web.act.build", "web.act.files"}
check("chaves usadas foram coletadas", len(used) > 40, len(used))
for lang in LANGS:
    missing = sorted(k for k in used if TR.T(lang, k) == k)
    check("todas as chaves existem em %s" % lang, not missing, missing)
# A Tradução com %s não pode vir sem o buraco, senão o item some.
for lang in LANGS:
    bad = [k for k in ("web.act.build", "web.act.files") if "%s" not in TR.T(lang, k)]
    check("atividade com o %s em %s" % ("%s", lang), not bad, bad)
# Chave morta: some do arquivo inteiro.
dead = "stage.note.yay"
uses = sum(open(p, encoding="utf-8").read().count(dead) for p in shells + [
    os.path.join(REPO, "web", "server.py"), os.path.join(REPO, "web", "static", "app.js"),
    os.path.join(REPO, "install", "translations.py")])
check("nenhuma chave morta no código", uses == 0, uses)

print()
if fails:
    print("FALHAS: %d -> %s" % (len(fails), fails))
    sys.exit(1)
print("todas as checagens passaram")
