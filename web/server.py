#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Instalador web do NLinux — servidor local (127.0.0.1).

Serve a interface (HTML/CSS/JS), coleta as escolhas e executa o install.sh
em subprocesso (GUI_DRIVEN=1), transmitindo o progresso para o navegador
via Server-Sent Events (SSE):

  event: state      {pct, label, steps, mode, lines, running, done, code, error}  ressincroniza
  event: progress   {pct, label}      atualiza a barra/anel
  event: log        {lines: [...]}    linhas de log (enviadas em lote)
  event: download   {bytes, total, rate, files}   download (modo online)
  event: done       {code}            fim da instalação
  event: error      {message}

Robustez — a instalação NÃO pode depender do navegador nem do servidor:

  * a saída do install.sh vai para um ARQUIVO de log e o servidor apenas o
    acompanha (em vez de ler um pipe): se o servidor cair, a instalação
    continua até o fim e, quando ele volta, reanexa a execução em andamento
    (estado em disco + log) em vez de perdê-la;
  * o estado (etapa, %, código de saída, últimas linhas) fica no servidor e é
    reenviado a cada cliente que (re)conecta: recarregar a página ou reconectar
    depois de uma queda devolve a tela de progresso, sem reinstalar nada;
  * queda de conexão é tratada como o que é — transitória. O navegador
    reconecta sozinho e nunca a transforma em falha de instalação;
  * POST /api/install enquanto já existe uma instalação em andamento devolve
    409 + o estado atual (impede apagar o disco por cima da instalação).

Dependências: apenas a biblioteca padrão do Python.
"""

import json
import os
import re
import stat
import subprocess
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))
STATIC = os.path.join(ROOT, "static")
INSTALL_SH = os.path.join(os.path.dirname(ROOT), "install.sh")
HOST = "127.0.0.1"
PORT = int(os.environ.get("NLINUX_WEB_PORT", "8765"))

# Log da execução atual e "checkpoint" do estado (reanexação após queda do
# servidor). Ambos no /tmp do live.
LOG_PATH = os.environ.get("NLINUX_LOG_PATH", "/tmp/nlinux-install.log")
STATE_PATH = os.environ.get("NLINUX_STATE_PATH", "/tmp/nlinux-install-state.json")

# Reusa as traduções (install/translations.py): as etapas do install.sh chegam
# como CHAVES (ex.: stage.copy.offline) e aqui são traduzidas para o idioma
# escolhido na página (NLLANG).
INSTALL_DIR = os.path.join(os.path.dirname(ROOT), "install")
sys.path.insert(0, INSTALL_DIR)
try:
    import translations
except Exception:  # noqa: BLE001
    translations = None

# Idioma da INTERFACE derivado do locale escolhido (país/região), quando a
# página não envia NLLANG explicitamente.
LANG_FROM_LOCALE = {
    "pt_BR.UTF-8": "pt", "pt_PT.UTF-8": "pt",
    "en_US.UTF-8": "en", "en_GB.UTF-8": "en",
    "es_ES.UTF-8": "es", "fr_FR.UTF-8": "fr",
    "de_DE.UTF-8": "de", "it_IT.UTF-8": "it",
    "ja_JP.UTF-8": "ja",
}
DEFAULT_LANG = "pt"
NTFS_RESIZE_RESERVE = 1024**3
MIB = 1024**2

# Etapas em que o painel mostra progresso real de bytes/arquivos (o resto
# segue o ritmo do plano). O resto das etapas não tem nada mensurável: o
# mkinitcpio, o chown e a configuração não dizem quanto falta.
COPY_STEPS = ("stage.copy.offline", "stage.pac.download", "stage.copy.online")

# Ritmo do anel (porcentagem REAL da instalação inteira, não da etapa).
#
# O número de cada etapa no plano (NLSTEPS) é o ponto em que ela começa, e a
# distância entre duas etapas é o PESO dela. A cada troca de etapa o anel se
# sincroniza com o plano (sem nunca voltar atrás) e volta a caminhar até 100%
# no tempo que a instalação inteira deveria levar dali para frente. É isso que
# faz o anel andar o tempo todo e terminar em 100% -- mesmo quando uma etapa
# estoura o previsto, porque o que sobrou é repartido pelas seguintes.
#
# Onde existe progresso real (bytes do cache do pacman, % do rsync, N/M do
# pacman, meson) ele entra na frente da estimativa: ali o anel mostra a
# porcentagem verdadeira da etapa. Depois de REAL_TTL segundos sem medida nova
# a estimativa assume de volta, para o anel não travar se o download travar.
PACE_TOTAL_S = 1500.0       # ~25 min: perto da mediana de uma instalação real
PACE_INTERVAL = 1.0         # com que o anel é recalculado
PACE_MAX_RUNNING = 99       # 100% só quando a instalação termina com sucesso
REAL_TTL = 20.0             # segundos que uma medida real continua valendo
ACT_MAX_ITEM = 80           # tamanho do item da atividade (ver _set_act)

# Atividades lidas do log para a linha abaixo do anel. Só entram padrões de
# ferramentas que NÃO traduzem a saída (cargo, meson, rsync) ou padrões
# numéricos do pacman: casar com as palavras do pacman quebraria em qualquer
# idioma diferente do pt-BR.
RE_BUILD = re.compile(r"^\s*Compiling\s+(\S+)")
# meson: "Generating targets:  45%|########     | 18/40" (a barra fica entre
# as duas réguas, então são dois "|" — um para a %, outro para o contador).
RE_MESON = re.compile(
    r"^\s*(?:Generating targets|Writing build\.ninja):\s*\d+%\|[^|]*\|\s*(\d+)/(\d+)")
# rsync --info=progress2 (o separador de milhar segue o idioma do live):
#   45% 1,20G 2,60G  0:01:23 (xfr#1.234, to-chk=5.678/12.345) 12,00MB/s
# O número é \d+([.,]\d+)* para a vírgula final do xfr# não ser comida.
RE_RSYNC = re.compile(
    r"(\d+)%.*?xfr#(\d+(?:[.,]\d+)*)(?:,\s*to-chk=(\d+(?:[.,]\d+)*)"
    r"/(\d+(?:[.,]\d+)*))?")
# pacman (só quando há TTY, sem isso ele não escreve a linha de progresso):
#   [ 350/705] Installing glibc (350/705)  120.5 MiB      45%
# O par [N/M] no começo da linha é o que dá a fração, em qualquer idioma.
RE_PACMAN = re.compile(r"^\s*\[\s*(\d+)\s*/\s*(\d+)\s*\]")
# "Tamanho total download:  1658,48 MiB" / "Total Download Size: 1658.48 MiB".
# O rótulo em volta é traduzido, o VALOR não — e é a única forma de saber, sem
# TTY, quantos bytes o pacman vai baixar antes de começar. O que separa o
# TOTAL das linhas por pacote (que trazem o tamanho no meio e a velocidade
# depois) é a forma: o valor vem logo depois de ":" e fecha a linha.
RE_SIZE = re.compile(r":\s*([\d][\d.,]*)\s*([KMGT]i?B)\s*$", re.I)
SIZE_MULT = {"B": 1, "KB": 1000, "KIB": 1024, "MB": 1000**2, "MIB": 1024**2,
             "GB": 1000**3, "GIB": 1024**3, "TB": 1000**4, "TIB": 1024**4}

# Cache do pacman como contador de download (modo online): o pacstrap baixa no
# cache do ALVO (só o `pacstrap -c` usa o do host) e o yay dentro do chroot usa
# o mesmo. Medir a soma dos dois conta tudo o que foi baixado, sem depender do
# idioma do pacman nem do formato das linhas dele.
CACHE_DIRS = [d for d in os.environ.get(
    "NLINUX_CACHE_DIRS", "/mnt/var/cache/pacman/pkg:/var/cache/pacman/pkg").split(":") if d]

LOG_MAX_LINES = 400        # linhas de log mantidas para ressincronizar a tela
LOG_SENT_LINES = 300       # linhas enviadas a cada cliente
FOLLOW_POLL = 0.2          # intervalo de leitura do arquivo de log
BATCH_INTERVAL = 0.2       # agrupa linhas de log em um único evento
PROGRESS_SCAN = 0.25       # cadência da leitura da linha incompleta (\r)
SAVE_INTERVAL = 5.0        # persiste o estado em disco
DL_INTERVAL = 1.0          # amostragem do cache do pacman (bytes baixados)
KEEPALIVE_S = 5.0          # heartbeat do SSE
WRITE_TIMEOUT = 30.0       # escrita travada por cliente não segura a thread
DRAIN_TIMEOUT = 30.0       # espera o log terminar de ser lido ao encerrar o run

# O install.sh desta execução já terminou: o laço que segue o log pode fechar.
# Sem isso, um run que acaba rápido publicaria o `done` antes das últimas
# linhas/progresso, e o painel perderia o fim da instalação.
_log_eof = threading.Event()

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".ico": "image/x-icon",
}

_ui_lang = DEFAULT_LANG
_state_lock = threading.RLock()


def _tr(key):
    """Traduz uma chave de etapa para o idioma da interface (ou devolve a chave)."""
    if translations is None or not key:
        return key
    return translations.T(_ui_lang, key)


# ---------------------------------------------------------------------------
# Estado da instalação
# ---------------------------------------------------------------------------
# Fonte da verdade do progresso. Vive no processo do servidor E é persistido
# em disco a cada poucos segundos: é o que permite retomar a interface depois
# de recarregar a página ou de o servidor ter morrido durante a instalação.
STATE = {
    "running": False,
    "pid": None,
    "pct": 0,
    "label": "stage.start",
    "step": "",             # chave da etapa atual
    "steps": [],            # plano ordenado: [{"pct": int, "key": str}]
    "mode": "",             # "offline" | "online"
    "lines": [],
    "done": False,
    "code": None,
    "error": None,
    "started": 0.0,
    "finished": 0.0,
    "log": LOG_PATH,
    # Atividade do momento ("Compilando umbriel-git"), que aparece ao lado da
    # etapa na linha abaixo do anel. Guarda a chave + os argumentos para que o
    # texto saia traduzido também no estado salvo em disco.
    "act_key": "",
    "act_args": [],
}
# Ritmo do anel (ver PACE_*):
#   base   = onde o anel está quando a etapa começou (nunca volta atrás disso)
#   plan_w = peso da etapa no plano (a fatia onde o progresso REAL é desenhado)
#   span   = segundos que falta para o fim previsto; 0 = SEM RITMO, o anel
#            espera parado (antes de o plano chegar) em vez de adivinhar
#   at     = quando a etapa começou
#   real   = fração real da etapa, quando dá para medir (bytes, % do rsync…)
_pace = {"base": 0.0, "plan_w": 0.0, "span": 0.0, "at": 0.0,
         "real": None, "real_at": 0.0}
_pace_thread = {"thread": None}

# Total que o pacman disse que vai baixar na etapa atual ("Tamanho total
# download: 1658,48 MiB"). É o que fecha a conta do anel nas etapas de
# download: sem TTY o pacman não escreve "(N/M) x%", então o tamanho é a única
# forma de saber aonde a etapa vai terminar.
_size_total = {"bytes": 0}

# Monitor de download (modo online): bytes/arquivos já baixados para o cache do
# pacman, medidos a partir de uma linha de base (base/base_files) tirada no
# início da execução. Também vai no checkpoint, para a contagem não zerar se o
# servidor cair no meio da instalação.
_dl = {"base": 0, "base_files": 0, "bytes": 0, "files": 0, "rate": 0.0}


def _cache_usage():
    """(bytes, arquivos) do cache do pacman somando os diretórios observados."""
    total = files = 0
    for path in CACHE_DIRS:
        try:
            with os.scandir(path) as it:
                for entry in it:
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if not stat.S_ISREG(st.st_mode):
                        continue
                    total += st.st_size
                    files += 1
        except OSError:
            continue
    return total, files


def _reset_download():
    """Zera a contagem de download, usando o cache atual como linha de base."""
    total, files = _cache_usage()
    with _state_lock:
        _dl.update(base=total, base_files=files, bytes=0, files=0, rate=0.0)
        _size_total["bytes"] = 0


def follow_download():
    """Publica os bytes baixados para o monitor do painel do instalador.

    Sonda o cache do pacman (DL_INTERVAL) e emite um evento `download` por
    segundo. Medir o cache — em vez de parsear as linhas do pacman — é o que
    mantém o monitor correto em qualquer idioma do sistema, já que o
    instalador roda no live com LANG do usuário (pt, en, ja…).

    A mesma contagem alimenta o anel: se o pacman disse quanto vai baixar na
    etapa (ver RE_SIZE), a fração de bytes vira a porcentagem real dela.
    """
    prev_bytes = 0.0
    prev_t = time.time()
    while True:
        time.sleep(DL_INTERVAL)
        total, files = _cache_usage()
        now = time.time()
        with _state_lock:
            # O cache nunca encolhe por conta própria; se encolher (limpeza,
            # live reiniciado), zera em vez de mostrar número negativo.
            if total < _dl["base"]:
                _dl["base"], _dl["base_files"] = total, files
            _dl["bytes"] = total - _dl["base"]
            _dl["files"] = max(0, files - _dl["base_files"])
            dt = max(0.2, now - prev_t)
            inst = max(0.0, (_dl["bytes"] - prev_bytes) / dt)
            # Média móvel: a taxa cai sozinha quando o download para.
            _dl["rate"] = inst if _dl["rate"] <= 0 else _dl["rate"] * 0.6 + inst * 0.4
            done = bool(STATE["done"]) and not STATE["running"]
            payload = _download_event()
            if _size_total["bytes"] > 0 and STATE["step"] in COPY_STEPS:
                # Bytes baixados ÷ total que o pacman disse: a fração real
                # da etapa, em qualquer idioma.
                _pace["real"] = _dl["bytes"] / _size_total["bytes"]
                _pace["real_at"] = now
        BROADCAST.push("download", payload)
        prev_bytes, prev_t = payload["bytes"], now
        if done:
            return


def _download_event():
    """Uma amostra do download para o painel do instalador.

    `bytes` é o que já foi baixado desde o começo da etapa, `total` é o que o
    pacman anunciou antes de começar (0 enquanto ele não falou), `rate` é a
    média de bytes/s e `files` quantos pacotes já chegaram ao cache.
    """
    with _state_lock:
        return {
            "bytes": _dl["bytes"],
            "files": _dl["files"],
            "rate": int(_dl["rate"]),
            "total": int(_size_total["bytes"]),
        }


def _act_text():
    """Atividade atual já formatada e traduzida ("" se não houver)."""
    key = STATE["act_key"]
    if not key:
        return ""
    text = _tr(key)
    for arg in STATE["act_args"]:
        text = text.replace("%s", str(arg), 1)
    return text


def _step_index():
    """Posição da etapa atual no plano (-1 se ela não está no plano)."""
    for i, s in enumerate(STATE["steps"]):
        if s["key"] == STATE["step"]:
            return i
    return -1


def _public_state():
    """Estado pronto para o navegador (SSE /api/status)."""
    with _state_lock:
        return {
            "running": bool(STATE["running"]),
            "pct": int(STATE["pct"]),
            "label": _tr(STATE["label"]),
            "act": _act_text(),
            "step": STATE["step"],
            "idx": _step_index(),
            "steps": [{"pct": s["pct"], "label": _tr(s["key"])} for s in STATE["steps"]],
            "mode": STATE["mode"],
            "lang": _ui_lang,
            "done": bool(STATE["done"]),
            "code": STATE["code"],
            "error": STATE["error"],
            "started": STATE["started"],
            "finished": STATE["finished"],
            "download": dict(_dl),
            "lines": list(STATE["lines"][-LOG_SENT_LINES:]),
        }


def _state_save():
    """Checkpoint do estado em disco (para reanexar após queda do servidor)."""
    try:
        with _state_lock:
            data = dict(STATE)
        data["lines"] = data["lines"][-100:]
        data["lang"] = _ui_lang
        data["download"] = dict(_dl)
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp, STATE_PATH)
    except OSError:
        pass


def _state_load():
    try:
        with open(STATE_PATH, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def _pid_alive(pid):
    """True se o install.sh indicado ainda estiver em execução."""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as fh:
            cmdline = fh.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return False
    return "install.sh" in cmdline


class Broadcaster:
    """Distribui eventos para todos os clientes SSE conectados."""

    def __init__(self):
        self._subs = []
        self._lock = threading.Lock()

    def subscribe(self, initial=None):
        q = deque()
        if initial:
            q.append(initial)
        with self._lock:
            self._subs.append(q)
        return q

    def unsubscribe(self, q):
        with self._lock:
            if q in self._subs:
                self._subs.remove(q)

    def push(self, event, data):
        payload = "event: %s\ndata: %s\n\n" % (
            event, json.dumps(data, ensure_ascii=False))
        with self._lock:
            for q in self._subs:
                if len(q) > 500:
                    q.clear()
                q.append(payload)


BROADCAST = Broadcaster()


def _payload(event, data):
    return "event: %s\ndata: %s\n\n" % (event, json.dumps(data, ensure_ascii=False))


# ---------------------------------------------------------------------------
# Progresso e eventos
# ---------------------------------------------------------------------------
def _clean(raw):
    return ANSI_RE.sub("", raw.decode("utf-8", "replace")).rstrip("\r").strip()


def _plan_ensure(key, pct):
    """Garante que a etapa exista no plano, mantendo a ordem por porcentagem.

    Rede de segurança para um install.sh antigo (que não manda NLSTEPS) ou que
    anuncie uma etapa nova: ela entra na posição certa em vez de sumir do
    painel — assim as etapas seguem sempre a ordem em que o script as executa.
    """
    for s in STATE["steps"]:
        if s["key"] == key:
            return False
    steps = STATE["steps"]
    pos = len(steps)
    for i, s in enumerate(steps):
        if pct < s["pct"]:
            pos = i
            break
    steps.insert(pos, {"pct": int(pct), "key": key})
    return True


def _progress_payload(pct=None):
    """Evento de progresso: % do anel, etapa, atividade e índice da etapa."""
    with _state_lock:
        return {
            "pct": int(STATE["pct"] if pct is None else pct),
            "label": _tr(STATE["label"]),
            "act": _act_text(),
            "step": STATE["step"],
            "idx": _step_index(),
        }


def _plan_reevaluate():
    """Prepara o ritmo do anel para a etapa que acabou de começar.

    Três coisas:
      - base: onde o anel está. Ele nunca volta atrás: se a etapa começa com o
        anel adiantado, a base é a posição real dele, não a do plano; e se ele
        ficou para trás do previsto, a base sobe para o ponto do plano (é a
        correção do Cronômetro, uma vez por etapa, e só quando ela acumulou).
      - plan_w: o peso da etapa no plano, que é a fatia onde o progresso real
        (bytes, %) é desenhado.
      - span: o tempo que falta para o fim previsto da instalação. O anel
        caminha de base a 100% nesse intervalo, então ele anda o tempo todo e
        chega a 100% — mesmo se a etapa estourar o previsto, mesmo se as
        etapas anteriores já tiverem comido a parte das seguintes. Sem plano
        não dá para estimar nada: span=0 deixa o anel parado até o plano
        chegar (é o que acontece no primeiro segundo da execução).
    """
    with _state_lock:
        steps = STATE["steps"]
        idx = _step_index()
        now = time.time()
        if idx < 0:
            # Etapa fora do plano (ou plano ainda não chegou): sem pesos para
            # seguir, o anel ESPERA PARADO, onde está. Ritmo aqui seria
            # adivinhação — e adivinhando, o anel chegava a 99% em um segundo e
            # ficava lá, porque nunca volta atrás.
            _pace.update(base=float(STATE["pct"]), plan_w=0.0, span=0.0,
                         at=now, real=None, real_at=0.0)
            return

        def weight(i):
            if i + 1 < len(steps):
                return float(steps[i + 1]["pct"] - steps[i]["pct"])
            return max(0.0, 100.0 - float(steps[i]["pct"]))

        start = float(STATE["started"]) or now
        _pace.update(
            # Atrás do previsto, o plano corrige; adiantado, quem manda é o anel.
            base=max(float(STATE["pct"]), float(steps[idx]["pct"])),
            plan_w=weight(idx),
            # Tempo até o fim previsto. O piso evita que uma instalação muito
            # mais lenta que o previsto faça o anel saltar de uma vez.
            span=max(PACE_TOTAL_S * 0.15, start + PACE_TOTAL_S - now),
            at=now, real=None, real_at=0.0)


def _ring_apply(frac=None):
    """Atualiza o anel e avisa os clientes (devolve a nova %, ou None).

    Duas fontes, e o anel só anda para frente:
      - o RITMO: caminha de base a 100% no tempo que a instalação inteira
        deveria levar a partir da última troca de etapa. É o que garante que o
        anel nunca congele e sempre termine em 100%. Sem plano (span == 0) não
        há ritmo: o anel fica parado onde está, esperando o install.sh mandar o
        plano, e só o progresso real o move.
      - o REAL: quando o log, o pacman ou a contagem de bytes dizem quanto da
        etapa já foi. Fica valendo por REAL_TTL segundos; depois disso volta a
        valer só o ritmo, para o anel não travar se o download travar.
    """
    with _state_lock:
        now = time.time()
        if frac is not None:
            _pace["real"] = min(max(frac, 0.0), 1.0)
            _pace["real_at"] = now
        base, span, at = _pace["base"], _pace["span"], _pace["at"]
        if span > 0.0:
            pct = int(base + (100.0 - base) * min(max((now - at) / span, 0.0), 1.0))
        else:
            pct = int(base)
        real = _pace["real"]
        if real is not None and now - _pace["real_at"] <= REAL_TTL:
            # A verdade da etapa, quando ela é mais adiante que a estimativa.
            pct = max(pct, int(base + _pace["plan_w"] * real))
        pct = min(pct, PACE_MAX_RUNNING)
        if pct <= int(STATE["pct"]):
            return None
        STATE["pct"] = pct
        payload = _progress_payload(pct)
    BROADCAST.push("progress", payload)
    return pct


def _pace_thread_loop():
    """Anel: um tique por segundo, andando enquanto a instalação roda."""
    while True:
        time.sleep(PACE_INTERVAL)
        with _state_lock:
            if not STATE["running"] or STATE["done"]:
                return
        _ring_apply()


def _start_pace():
    """Sobe a thread do anel (uma por execução)."""
    with _state_lock:
        if _pace_thread["thread"] is not None and _pace_thread["thread"].is_alive():
            return
        _pace_thread["thread"] = threading.Thread(
            target=_pace_thread_loop, name="nlinux-pace", daemon=True)
    _pace_thread["thread"].start()


def _set_step(key, pct, plan_changed=False):
    """Fixa a etapa atual e avisa os clientes (progresso + plano, se mudou)."""
    key = key.strip()
    with _state_lock:
        plan_changed = _plan_ensure(key, pct) or plan_changed
        changed = STATE["step"] != key
        STATE["step"] = key
        STATE["label"] = key
        # A atividade pertence à etapa anterior: some quando a próxima começa.
        STATE["act_key"], STATE["act_args"] = "", []
        # O anel não volta atrás: se a etapa começa com o anel adiantado (a
        # anterior estourou o previsto), ele fica onde está.
        STATE["pct"] = min(100, max(int(STATE["pct"]), int(pct)))
        # O total de download pertence à etapa que começou agora.
        _size_total["bytes"] = 0
    if changed:
        _plan_reevaluate()
    BROADCAST.push("progress", _progress_payload())
    if plan_changed:
        _push_state()


def _set_act(key, *args):
    """Fixa a atividade do momento (linha abaixo do anel) e avisa os clientes."""
    with _state_lock:
        # O item é um nome (pacote, crate, arquivo), não uma frase: uma lista de
        # AUR muito grande é cortada para a linha abaixo do anel não virar um
        # parágrafo.
        args = [(a if len(a) <= ACT_MAX_ITEM else a[:ACT_MAX_ITEM - 1].rstrip() + "…")
                for a in (str(x) for x in args)]
        if STATE["act_key"] == key and STATE["act_args"] == args:
            return
        STATE["act_key"], STATE["act_args"] = key, args
        payload = _progress_payload()
    BROADCAST.push("progress", payload)


def _number(text):
    """Número de ferramenta que formata no idioma do live (1.234 / 1,5 / 1234).

    "1.234" e "1,234" podem ser milhar ou decimal; o que decide é o número de
    casas depois do separador — três casas é milhar, qualquer outra é decimal.
    """
    raw = str(text).strip()
    m = re.match(r"^(\d+)[.,](\d+)$", raw)
    if m:
        whole, frac = m.groups()
        return float(whole + frac) if len(frac) == 3 else float(whole + "." + frac)
    try:
        return float(re.sub(r"[^\d.]", "", raw) or 0)
    except ValueError:
        return 0.0


def _push_real_progress(seg):
    """Progresso real da etapa em curso, lido da linha viva do log.

    Só entram padrões que não dependem do idioma: o % do rsync
    (--info=progress2) e o "(N/M) x%" do pacman. Sem TTY o pacman não escreve a
    linha de progresso — e aí quem manda é a contagem de bytes do cache.
    """
    m = RE_RSYNC.search(seg)
    if m:
        _ring_apply(min(float(m.group(1)), 100.0) / 100.0)
        # Cópia offline: o rsync diz quantos arquivos já copiaram e quantos
        # ainda faltam — o mesmo detalhe que a etapa da AUR dá com o nome do
        # pacote.
        if m.group(4):
            _set_act("web.act.files", m.group(2), m.group(4))
        return
    m = RE_PACMAN.match(seg)
    if not m:
        return
    total = float(m.group(2))
    if total <= 0:
        return
    _ring_apply(min(float(m.group(1)) / total, 1.0))


def _on_plan(line):
    """NLSTEPS|<pct>:<chave>,…: plano completo das etapas, na ordem real.

    É o install.sh quem define o plano (e ele é diferente entre offline e
    online); o painel só desenha o que chega aqui.
    """
    steps = []
    for item in line.split("|", 1)[1].split(","):
        pct_s, sep, key = item.strip().partition(":")
        if not sep or not key:
            continue
        try:
            pct = int(float(pct_s))
        except ValueError:
            continue
        steps.append({"pct": max(0, min(100, pct)), "key": key.strip()})
    if not steps:
        return
    with _state_lock:
        STATE["steps"] = steps
    _plan_reevaluate()
    _push_state()


def _on_progress(line):
    _, p, key = line.split("|", 2)
    try:
        pct = int(float(p.strip()))
    except ValueError:
        pct = 0
    _set_step(key, pct)


def _on_step(line):
    """NLSTEP|<chave>: etapa anunciada de dentro do chroot; o pct vem do plano."""
    key = line.split("|", 1)[1].strip()
    with _state_lock:
        pct = int(STATE["pct"])
        for s in STATE["steps"]:
            if s["key"] == key:
                pct = s["pct"]
                break
    _set_step(key, pct)


def _on_note(line):
    """NLNOTE|<chave>: atividade temporária — muda o rótulo, não a etapa."""
    key = line.split("|", 1)[1].strip()
    with _state_lock:
        STATE["label"] = key
    BROADCAST.push("progress", _progress_payload())


def _on_act(line):
    """NLACT|<chave>|<item>: atividade com nome ("Compilando umbriel-git").

    É o install.sh dizendo o que está acontecendo AGORA dentro da etapa; o texto
    final sai traduzido pelo servidor, com o <item> no %s da chave.
    """
    _, key, item = line.split("|", 2)
    _set_act(key.strip(), item.strip())


def _on_result(line):
    """NLRESULT|<rc>: última linha escrita pelo install.sh (EXIT trap)."""
    try:
        code = int(line.split("|", 1)[1].strip())
    except (IndexError, ValueError):
        code = 1
    _finish(code)


def _log_activity(line):
    """Atividade lida do log, para a linha abaixo do anel.

    Só casam ferramentas que não traduzem a saída (cargo, meson, rsync) ou
    padrões numéricos do pacman: casar com as palavras do pacman ("instalando",
    "downloading") quebraria em qualquer idioma diferente do pt-BR.
    """
    m = RE_BUILD.match(line)
    if m:
        # cargo: "   Compiling proc-macro2 v1.0.103"
        _set_act("web.act.build", m.group(1))
        return
    m = RE_MESON.match(line)
    if m:
        # meson: "Generating targets:  45%|########     | 18/40 (2 min)"
        done, total = float(m.group(1)), float(m.group(2))
        if total > 0:
            _ring_apply(done / total)
        return
    m = RE_SIZE.search(line)
    if m:
        # "Tamanho total download:  1658,48 MiB" — o pacman diz quanto vai
        # baixar antes de começar. A partir daí a etapa tem um total em bytes.
        # Fica o PRIMEIRO total da etapa (o do download vem antes do tamanho
        # instalado): somar as linhas daria um total que cresce junto com o
        # download, e a fração real da etapa ficaria sempre em 100%.
        size = _number(m.group(1)) * SIZE_MULT.get(m.group(2).upper(), 1)
        if size > 0:
            with _state_lock:
                if _size_total["bytes"] <= 0:
                    _size_total["bytes"] = size


def _finish(code, error=None):
    """Marca a instalação como encerrada e avisa os clientes (uma única vez).

    No sucesso sai um `progress` com 100% ANTES do `done`: as três últimas
    etapas (desktop, bootloader, finalização) são rápidas e chegam ao mesmo
    tempo que o fim da execução. Sem esse quadro, o painel só via o `done` e
    trocava direto para a tela de sucesso com o anel ainda no meio do caminho.
    """
    with _state_lock:
        if STATE["done"]:
            return
        STATE["running"] = False
        STATE["done"] = True
        STATE["code"] = code
        STATE["error"] = error
        STATE["finished"] = time.time()
        if code == 0 and not error:
            STATE["pct"] = 100
    _state_save()
    if error:
        BROADCAST.push("error", {"message": error})
    if code == 0 and not error:
        BROADCAST.push("progress", _progress_payload(100))
    BROADCAST.push("done", {"code": code})


def _push_state():
    BROADCAST.push("state", _public_state())


def _handle_line(raw, pending):
    """Traduz uma linha do log em evento (ou a guarda no lote de log)."""
    line = _clean(raw)
    if not line:
        return
    if line.startswith("NLSTEPS|"):
        _on_plan(line)
    elif line.startswith("NLPROGRESS|"):
        _on_progress(line)
    elif line.startswith("NLSTEP|"):
        _on_step(line)
    elif line.startswith("NLNOTE|"):
        _on_note(line)
    elif line.startswith("NLACT|"):
        _on_act(line)
    elif line.startswith("NLRESULT|"):
        _on_result(line)
    else:
        pending.append(line)
        with _state_lock:
            STATE["lines"].append(line)
            if len(STATE["lines"]) > LOG_MAX_LINES:
                del STATE["lines"][:-LOG_MAX_LINES]
        _log_activity(line)


def _push_logs(pending):
    if not pending:
        return
    BROADCAST.push("log", {"lines": list(pending)})
    del pending[:]


def follow_log(path=None):
    """Acompanha o arquivo de log do install.sh e publica os eventos.

    Segue o ARQUIVO (e não um pipe) de propósito: se o servidor cair, o
    install.sh continua escrevendo no log — quando o servidor volta, este
    laço reproduz o log já gravado e reanexa a execução em andamento.
    """
    path = path or LOG_PATH
    pending = []
    buf = b""
    last_partial = last_push = last_save = 0.0
    try:
        fh = open(path, "rb")
    except OSError:
        return
    try:
        while True:
            try:
                chunk = fh.read(65536)
            except OSError:
                chunk = b""
            now = time.time()
            if chunk:
                buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                _handle_line(raw, pending)
            # Linha incompleta (o \r do rsync/pacman): só interessa o progresso
            # real que sai dela — a caixinha que mostrava o texto da linha
            # "viva" no painel foi removida, e a linha completa continua
            # chegando pelo lote de log quando o programa termina a linha.
            if b"\r" in buf and now - last_partial >= PROGRESS_SCAN:
                # Alguns programas escrevem o \r no FIM da linha (outros no
                # começo): o rstrip evita que a linha "suma" só porque o
                # buffer terminou exatamente no \r.
                seg = buf.rstrip(b"\r").rsplit(b"\r", 1)[-1].decode("utf-8", "replace").strip()
                if seg:
                    _push_real_progress(ANSI_RE.sub("", seg))
                last_partial = now
            # Lote de log (evita um evento por linha durante os builds AUR).
            if pending and (now - last_push >= BATCH_INTERVAL or len(pending) >= 100):
                _push_logs(pending)
                last_push = now
            if now - last_save >= SAVE_INTERVAL:
                _state_save()
                last_save = now
            if not chunk:
                with _state_lock:
                    finished = STATE["done"] and not STATE["running"]
                if finished or _log_eof.is_set():
                    # Última linha parcial (install.sh morto sem \n final).
                    if buf.strip():
                        _handle_line(buf.rstrip(b"\r\n"), pending)
                    _push_logs(pending)
                    _push_state()
                    return
                time.sleep(FOLLOW_POLL)
    finally:
        fh.close()


def adopt_running_install():
    """Reanexa uma instalação que continuou rodando enquanto o servidor caiu.

    Sem isso, uma queda do servidor (OOM, Ctrl+C, reinício do launcher)
    deixaria a interface órfã mesmo com a instalação seguindo no disco.
    """
    data = _state_load()
    if not data:
        return
    global _ui_lang
    with _state_lock:
        for key in ("pct", "label", "step", "mode", "done", "code", "error",
                    "started", "finished", "log", "act_key", "act_args"):
            if data.get(key) is not None:
                STATE[key] = data[key]
        steps = data.get("steps")
        if isinstance(steps, list):
            STATE["steps"] = [s for s in steps
                              if isinstance(s, dict) and "key" in s and "pct" in s]
        # A linha de base do download vem junto: sem ela a contagem de MB
        # reiniciaria do zero quando o servidor volta no meio da instalação.
        if isinstance(data.get("download"), dict):
            _dl.update(data["download"])
        # As linhas do checkpoint NÃO são recarregadas: o laço que segue o log
        # abaixo reproduz o arquivo desde o começo, e as duas cópias apareceriam
        # duplicadas no painel.
        STATE["lines"] = []
        STATE["running"] = bool(data.get("running"))
    if not STATE["running"]:
        return
    if isinstance(data.get("lang"), str) and data["lang"]:
        _ui_lang = data["lang"]
    pid = data.get("pid")
    if not _pid_alive(pid):
        # O install.sh morreu junto com o servidor: o disco pode estar pela
        # metade, então o painel assume falha em vez de oferecer reinstalar.
        with _state_lock:
            STATE["pid"] = None
        _finish(1, "A instalação foi interrompida (o instalador foi fechado).")
        return
    with _state_lock:
        STATE["pid"] = pid
    log = data.get("log") or LOG_PATH
    with _state_lock:
        STATE["log"] = log
    if not os.path.isfile(log):
        # Sem log para reanexar: marca como falha em vez de prometer progresso.
        with _state_lock:
            STATE["pid"] = None
        _finish(1, "A instalação foi interrompida (log indisponível).")
        return
    threading.Thread(target=follow_log, args=(log,), daemon=True).start()
    threading.Thread(target=_watch_pid, args=(pid,), daemon=True).start()
    # O anel volta a andar de onde parou: a etapa atual é a mesma, e o plano
    # (que vem do checkpoint) é reaplicado para redistribuir o que falta.
    _plan_reevaluate()
    _start_pace()
    with _state_lock:
        online = STATE["mode"] == "online"
    if online:
        threading.Thread(target=follow_download, daemon=True).start()


def _watch_pid(pid, poll=1.0):
    """Segue o install.sh adotado até ele terminar.

    O resultado normal chega pelo sentinela NLRESULT (lido pelo laço do log). Se o
    processo morrer sem escrevê-lo (morto por sinal, OOM), o painel ficaria
    girando para sempre — aqui ele é encerrado como falha explícita.
    """
    while _pid_alive(pid):
        time.sleep(poll)
    # O NLRESULT é a última coisa escrita no log: dá uma folga para ele ser lido.
    for _ in range(25):
        with _state_lock:
            if STATE["done"]:
                return
        time.sleep(0.2)
    with _state_lock:
        running = STATE["running"]
    if running:
        _finish(1, "A instalação foi encerrada sem informar o resultado "
                   "(o processo do instalador terminou).")


ESP_TYPE = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"


def _disk_esp(disk):
    """Retorna o caminho da ESP (partição EFI System FAT32) existente no disco, ou None."""
    try:
        out = subprocess.run(
            ["lsblk", "-lnpo", "NAME,PARTTYPE", disk],
            capture_output=True, text=True).stdout
    except Exception:  # noqa: BLE001
        return None
    esp = None
    for ln in out.splitlines():
        parts = ln.split()
        if len(parts) == 2 and parts[1] == ESP_TYPE:
            esp = parts[0]
            break
    if not esp:
        return None
    try:
        typ = subprocess.run(
            ["blkid", "-s", "TYPE", "-o", "value", esp],
            capture_output=True, text=True).stdout.strip()
    except Exception:  # noqa: BLE001
        typ = ""
    return esp if typ == "vfat" else None


def _parse_free_bytes(text):
    """Maior trecho livre em bytes, independente do idioma do parted.

    'parted -s <disk> unit B print free' imprime partições com número na
    primeira coluna e trechos livres sem número:
        17408B   1048575B   1031168B  Espaço livre  | Free Space
    Então basta casar linhas sem número cujas três primeiras colunas sejam
    tamanhos em bytes.
    """
    best = 0
    for ln in text.splitlines():
        cols = ln.split()
        if len(cols) < 4:
            continue
        if cols[0].isdigit():
            continue
        if not all(c.endswith("B") for c in cols[:3]):
            continue
        try:
            size = int(cols[2][:-1])
        except ValueError:
            continue
        if size > best:
            best = size
    return best


def _disk_free_bytes(disk):
    """Maior bloco contínuo livre do disco, em bytes (para o dual boot)."""
    # parted (presente no live) reporta o espaço livre em bytes, sem assumir
    # tamanho de setor. Pega o MAIOR trecho 'Free Space'.
    try:
        out = subprocess.run(
            ["parted", "-s", disk, "unit", "B", "print", "free"],
            capture_output=True, text=True).stdout
        best = _parse_free_bytes(out)
        if best > 0:
            return best
    except Exception:  # noqa: BLE001
        pass
    # Fallback: sgdisk (setor 512B). Só se parted falhou.
    try:
        first = subprocess.run(["sgdisk", "-F", disk], capture_output=True, text=True).stdout.strip()
        last = subprocess.run(["sgdisk", "-E", disk], capture_output=True, text=True).stdout.strip()
        return max(0, (int(last) - int(first) + 1) * 512)
    except Exception:  # noqa: BLE001
        return 0


def _disk_dual_ok(disk):
    """True se o disco tem ESP FAT32 e espaço livre aproveitável (>~5 GiB).

    Funciona para qualquer sistema coexistente (Windows ou outra distro com
    ESP FAT32): a instalação ao lado só depende disso, não do sistema em si.
    """
    if not _disk_esp(disk):
        return False
    return _disk_free_bytes(disk) > 5 * 1024**3


def _ntfs_minimum_size(partition):
    """Ask ntfsresize for the smallest safe filesystem size without modifying it."""
    result = subprocess.run(
        ["ntfsresize", "--info", "--no-progress-bar", partition],
        capture_output=True, text=True, timeout=30,
        env={**os.environ, "LC_ALL": "C"},
    )
    output = result.stdout + "\n" + result.stderr
    if result.returncode:
        raise RuntimeError(output.strip() or "ntfsresize não conseguiu verificar a partição")
    match = re.search(r"you might resize at\s+([\d,]+)\s+bytes", output, re.IGNORECASE)
    if not match:
        raise RuntimeError("não foi possível determinar o tamanho mínimo seguro do NTFS")
    return int(match.group(1).replace(",", ""))


def get_ntfs_partitions(disk):
    """Return directly attached NTFS partitions and their safe shrink limits."""
    if not isinstance(disk, str) or not disk.startswith("/dev/"):
        raise ValueError("disco inválido")
    disk = os.path.realpath(disk)
    if not stat.S_ISBLK(os.stat(disk).st_mode):
        raise ValueError("o dispositivo selecionado não é um disco")

    result = subprocess.run(
        ["lsblk", "--json", "--bytes", "--paths",
         "--output", "NAME,TYPE,FSTYPE,SIZE,PARTN,PKNAME,PARTLABEL,MOUNTPOINTS", disk],
        capture_output=True, text=True, check=True, timeout=15,
    )
    tree = json.loads(result.stdout).get("blockdevices", [])
    if len(tree) != 1 or tree[0].get("type") != "disk":
        raise ValueError("o dispositivo selecionado não é um disco")

    partitions = []
    for part in tree[0].get("children", []):
        if part.get("type") != "part" or part.get("fstype", "").lower() != "ntfs":
            continue
        name = part.get("name")
        size = int(part.get("size") or 0)
        mountpoints = part.get("mountpoints") or []
        if any(mountpoints):
            partitions.append({
                "path": name,
                "label": part.get("partlabel") or name,
                "size": size,
                "resizable": False,
                "error": "a partição está montada; ela precisa estar desmontada",
            })
            continue
        try:
            minimum = _ntfs_minimum_size(name)
        except (KeyError, TypeError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
            partitions.append({
                "path": name,
                "label": part.get("partlabel") or name,
                "size": size,
                "resizable": False,
                "error": str(exc),
            })
            continue
        max_shrink = max(0, size - minimum - NTFS_RESIZE_RESERVE)
        partitions.append({
            "path": name,
            "label": part.get("partlabel") or name,
            "size": size,
            "minimum": minimum,
            "max_shrink": max_shrink,
            "resizable": max_shrink >= 8 * 1024**3 + 2 * MIB,
        })
    return partitions


def get_disks():
    out = subprocess.run(
        ["lsblk", "-dpno", "NAME,SIZE,MODEL,TYPE"],
        capture_output=True, text=True).stdout
    disks = []
    for ln in out.splitlines():
        parts = ln.split()
        if not parts:
            continue
        name, size, kind = parts[0], parts[1], parts[-1]
        model = " ".join(parts[2:-1]) if len(parts) > 3 else ""
        if kind != "disk" or "loop" in name or "zram" in name:
            continue
        disks.append({
            "name": name, "size": size, "model": model,
            "esp": _disk_esp(name) is not None,
            "free": _disk_free_bytes(name),
            "dual_ok": _disk_dual_ok(name),
        })
    return disks


def _begin_run(mode="offline"):
    """Prepara estado e arquivo de log para uma nova instalação."""
    with _state_lock:
        STATE.update(
            running=True, pid=None, pct=0, label="stage.start", step="",
            steps=[], mode=mode, lines=[],
            done=False, code=None, error=None, started=time.time(), finished=0.0,
            log=LOG_PATH, act_key="", act_args=[],
        )
        # span=0: sem plano não há ritmo, o anel espera em 0% até o install.sh
        # mandar o plano e a primeira etapa.
        _pace.update(base=0.0, plan_w=0.0, span=0.0, at=time.time(),
                     real=None, real_at=0.0)
    _log_eof.clear()
    _reset_download()
    try:
        # Log da execução anterior fica em .1 (o install.sh consulta
        # /tmp/nlinux-install.log para gravar o marcador de erro no disco).
        if os.path.exists(LOG_PATH):
            os.replace(LOG_PATH, LOG_PATH + ".1")
    except OSError:
        pass
    _start_pace()
    _state_save()


def run_install(config):
    """Roda o install.sh com as escolhas do navegador e transmite o progresso."""
    global _ui_lang
    nllang = str(config.get("NLLANG") or LANG_FROM_LOCALE.get(str(config.get("LOCALE", ""))) or DEFAULT_LANG)
    nllang = nllang.split("_")[0].split("-")[0].lower()
    if nllang not in (translations.TRANSLATIONS if translations is not None else ()):
        nllang = DEFAULT_LANG
    _ui_lang = nllang

    # O modo define o plano de etapas que o install.sh vai mandar e se o
    # monitor de download aparece no painel (só faz sentido baixando pacotes).
    offline = str(config.get("OFFLINE", "1")).strip().lower() not in ("0", "false", "no", "")
    mode = "offline" if offline else "online"

    _begin_run(mode)
    BROADCAST.push("progress", _progress_payload())
    env = dict(os.environ)
    for k, v in config.items():
        env[str(k)] = str(v)
    env["GUI_DRIVEN"] = "1"
    env["NLINUX_WEB"] = "1"
    env["NLLANG"] = _ui_lang
    proc = None
    try:
        # A saída vai para o ARQUIVO de log: o install.sh não depende do
        # servidor para continuar (se o servidor cair, ele não leva SIGPIPE)
        # e o log continua completo para reanexar a execução.
        logfh = open(LOG_PATH, "ab", buffering=0)
        try:
            logfh.write(b"\n========== instalacao iniciada: %s ==========\n" % time.asctime().encode())
            proc = subprocess.Popen(
                ["bash", INSTALL_SH],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=logfh,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        finally:
            logfh.close()
        with _state_lock:
            STATE["pid"] = proc.pid
        _state_save()
        log_thread = threading.Thread(target=follow_log, args=(LOG_PATH,), daemon=True)
        log_thread.start()
        if mode == "online":
            threading.Thread(target=follow_download, daemon=True).start()
        code = proc.wait()
        # Espera o log ser lido até o fim antes de fechar o run: o `done` tem de
        # ser o ÚLTIMO evento, senão uma instalação rápida perde o trecho final.
        _log_eof.set()
        log_thread.join(timeout=DRAIN_TIMEOUT)
    except Exception as exc:  # noqa: BLE001
        _finish(1, str(exc))
        return
    _finish(code)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "NLinux/1.0"

    def log_message(self, *args):
        pass

    def _json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _i18n(self):
        if translations is None:
            return self._json({"error": "i18n indisponível"}, 500)
        qs = urlparse(self.path).query
        lang = "pt"
        for pair in qs.split("&"):
            if pair.startswith("lang="):
                lang = pair.split("=", 1)[1].split("_")[0].split("-")[0].lower()
        if lang not in translations.TRANSLATIONS:
            lang = DEFAULT_LANG
        # tabela do idioma com fallback para pt (chaves ainda não traduzidas)
        table = dict(translations.TRANSLATIONS[DEFAULT_LANG])
        table.update(translations.TRANSLATIONS[lang])
        return self._json({"lang": lang, "table": table})

    def _file(self, path):
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            return self._json({"error": "not found"}, 404)
        ext = os.path.splitext(path)[1]
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        # Imagens podem ser cacheadas (evita o logo piscar até o success.png
        # baixar); código/HTML seguem no-store para não servir versão velha.
        if ext in (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"):
            self.send_header("Cache-Control", "public, max-age=3600")
        else:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = urlparse(self.path).path
        if p in ("/", "/index.html"):
            return self._file(os.path.join(STATIC, "index.html"))
        if p.startswith("/static/"):
            return self._file(os.path.join(ROOT, p.lstrip("/")))
        if p == "/api/disks":
            return self._json({"disks": get_disks()})
        if p == "/api/ntfs-partitions":
            disk = parse_qs(urlparse(self.path).query).get("disk", [""])[0]
            try:
                partitions = get_ntfs_partitions(disk)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError,
                    json.JSONDecodeError) as exc:
                return self._json({"error": str(exc)}, 400)
            return self._json({"partitions": partitions})
        if p == "/api/i18n":
            return self._i18n()
        if p == "/api/status":
            return self._json(_public_state())
        if p == "/api/stream":
            return self._stream()
        return self._json({"error": "not found"}, 404)

    def _stream(self):
        # Esta conexão vive até o fim (SSE): nada de atende outro pedido nela.
        self.close_connection = True
        q = BROADCAST.subscribe(_payload("state", _public_state()))
        try:
            # Escrita travada (cliente que parou de ler) não pode prender a
            # thread nem a conexão para sempre: expira e o cliente reconecta.
            self.connection.settimeout(WRITE_TIMEOUT)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            self.wfile.write(b"retry: 1500\n: connected\n\n")
            last_kb = time.time()
            while True:
                wrote = False
                while q:
                    payload = q.popleft()
                    self.wfile.write(payload.encode())
                    wrote = True
                    if payload.startswith(("event: done\n", "event: error\n")):
                        return
                # Espera curta quando não há nada a enviar: sem isso, o
                # progresso da instalação só apareceria a cada KEEPALIVE_S.
                now = time.time()
                if now - last_kb >= KEEPALIVE_S:
                    self.wfile.write(b": keepalive\n\n")
                    last_kb = now
                if not wrote:
                    time.sleep(FOLLOW_POLL)
        except (OSError, ValueError):
            # Queda de conexão é rotina: o EventSource do navegador reconecta
            # e recebe o estado atual no evento `state`. Não é erro de
            # instalação — por isso nada é propagado como falha.
            return
        finally:
            BROADCAST.unsubscribe(q)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/install":
            try:
                n = int(self.headers.get("Content-Length", "0"))
                config = json.loads(self.rfile.read(n) or b"{}")
            except Exception:  # noqa: BLE001
                return self._json({"error": "json inválido"}, 400)
            if not config.get("INSTALL_DISK"):
                return self._json({"error": "disco não informado"}, 400)
            with _state_lock:
                busy = bool(STATE["running"])
            if busy:
                # Duas instalações no mesmo /mnt destruiriam o disco: devolve
                # o estado em andamento para a página voltar ao painel.
                return self._json({"error": "instalação já em andamento",
                                   "state": _public_state()}, 409)
            threading.Thread(target=run_install, args=(config,), daemon=True).start()
            return self._json({"ok": True})
        if path == "/api/reboot":
            threading.Thread(
                target=os.system, args=("systemctl reboot",), daemon=True
            ).start()
            return self._json({"ok": True})
        if path == "/api/quit":
            threading.Thread(
                target=os.system, args=("pkill -f '[f]irefox.*--kiosk' || true",), daemon=True
            ).start()
            return self._json({"ok": True})
        return self._json({"error": "not found"}, 404)


def main():
    if not os.path.isfile(INSTALL_SH):
        print("install.sh não encontrado: %s" % INSTALL_SH, file=sys.stderr)
        return 1
    # Retoma uma instalação que sobreviveu à queda do servidor (se houver).
    adopt_running_install()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print("NLinux web installer em http://%s:%d" % (HOST, PORT), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
