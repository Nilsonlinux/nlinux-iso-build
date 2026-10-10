#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Ponta a ponta: o log que o instalador escreve -> servidor -> SSE na fio.

Sobe o web/server.py de verdade numa porta livre, faz o que o install.sh faz
(linhas de protocolo no log) e lê /api/stream como o navegador leria. É o que
confere o formato do evento `progress` no fio — inclusive os campos novos
(`act` e `idx`) — e o `state` que a página recebe ao (re)conectar.

    python3 web/tests/e2e_test.py           # da raiz do repositório

Só usa a biblioteca padrão: não precisa de nada instalado, nem de root.
"""
import atexit
import http.client
import importlib.util
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time

# Raiz do repositório: web/tests/ -> web/ -> <repo>.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Log/estado/cache de mentira, numa pasta temporária: a instalação de verdade
# (que usa /tmp/nlinux-*) não é encostada.
TMP = tempfile.mkdtemp(prefix="nlinux-e2e-")
atexit.register(shutil.rmtree, TMP, True)
LOG = os.path.join(TMP, "install.log")
STATE = os.path.join(TMP, "state.json")
CACHE = os.path.join(TMP, "cache")
PORT = 0

os.environ["NLINUX_LOG_PATH"] = LOG
os.environ["NLINUX_STATE_PATH"] = STATE
os.environ["NLINUX_CACHE_DIRS"] = CACHE
os.environ["NLINUX_PORT"] = str(PORT)

spec = importlib.util.spec_from_file_location("srv", os.path.join(REPO, "web", "server.py"))
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

# Porta livre e servidor em segundo plano.
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
PORT = sock.getsockname()[1]
sock.close()
httpd = srv.ThreadingHTTPServer(("127.0.0.1", PORT), srv.Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
time.sleep(0.2)

fails = []


def check(name, cond, extra=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s -> %s" % (name, extra))
        fails.append(name)


def conn():
    return http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)


# ---------------------------------------------------------------------------
print("== /api/stream: o que o navegador recebe ==")
c = conn()
c.request("GET", "/api/stream")
res = c.getresponse()
check("stream abre com 200", res.status == 200, res.status)
check("é text/event-stream", res.getheader("Content-Type", "").startswith("text/event-stream"),
      res.getheader("Content-Type"))
f = res.fp

events = {}


def pump(seconds):
    """Lê o stream pelo tempo dado e guarda os eventos por nome."""
    end = time.time() + seconds
    buf = b""
    f.flush = lambda: None
    while time.time() < end:
        srv.BROADCAST.push  # mantém a referência viva
        chunk = _read(f, 0.25)
        if not chunk:
            continue
        buf += chunk
        while b"\n\n" in buf:
            raw, buf = buf.split(b"\n\n", 1)
            name, data = "message", None
            for line in raw.decode("utf-8", "replace").split("\n"):
                if line.startswith("event: "):
                    name = line[7:]
                elif line.startswith("data: "):
                    data = line[6:]
            if data is None or data.strip() == ": keep-alive":
                continue
            events.setdefault(name, []).append(json.loads(data))


def _read(fobj, timeout):
    """Lê o que já chegou na socket sem esperar encher o buffer."""
    import select
    r, _, _ = select.select([fobj], [], [], timeout)
    return fobj.read1(4096) if r else b""


def log_line(text):
    """O que o install.sh faz: a linha vai para o arquivo e o servidor, que
    segue o arquivo (follow_log), é quem lê e publica."""
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(text + "\n")
    time.sleep(0.3)
    pump(0.2)


srv._begin_run("online")
srv._ui_lang = "pt"
open(LOG, "w").close()                       # o instalador cria o log
threading.Thread(target=srv.follow_log, args=(LOG,), daemon=True).start()
pump(0.4)
events.clear()

PLAN = ("NLSTEPS|0:stage.lang_key,2:stage.mirror,4:stage.disk,9:stage.fs,"
        "13:stage.pac.download,38:stage.chroot.system,54:stage.chroot.aur,"
        "85:stage.chroot.desktop,96:stage.boot,99:stage.final")
log_line(PLAN)
log_line("NLPROGRESS|54|stage.chroot.aur")
log_line("NLACT|web.act.build|yay-bin")
log_line("   Compiling umbriel-git v0.1.0")
pump(0.6)

check("chegou evento progress", "progress" in events, list(events))
prog = events.get("progress", [])
check("payload tem pct/label/step/idx/act",
      prog and all(k in prog[-1] for k in ("pct", "label", "step", "idx", "act")), prog[-1:])
check("payload não carrega o que o cliente não usa",
      all(set(e) <= {"pct", "label", "act", "step", "idx"} for e in prog),
      sorted(set().union(*[set(e) for e in prog])))
check("etapa traduzida no payload",
      prog[-1]["label"] == "Baixar e compilar pacotes da AUR", prog[-1]["label"])
check("idx da etapa no payload", prog[-1]["idx"] == 6, prog[-1]["idx"])
acts = [e["act"] for e in prog]
check("NLACT vira atividade no payload", "Compilando yay-bin" in acts, acts)
# A última linha do log (cargo) vira a atividade mais recente: só o nome do
# pacote, sem a versão, que é o que o log do build repete a cada linha.
log_line("   Compiling noctalia-shell v0.1.0")
check("atividade acompanha o log", events["progress"][-1]["act"] == "Compilando noctalia-shell",
      events["progress"][-1]["act"])
# Uma linha de log comum vira linha de log, não atividade.
log_line("   warning: 1 warning emitted")
check("linha comum vai para o log", events.get("log"), list(events))
check("linha comum não vira atividade",
      events["progress"][-1]["act"] == "Compilando noctalia-shell",
      events["progress"][-1]["act"])

# ---------------------------------------------------------------------------
print("== /api/status: o quadro que a página recebe ao reconectar ==")
c2 = conn()
c2.request("GET", "/api/status")
st = json.loads(c2.getresponse().read().decode("utf-8"))
check("status traz a etapa", st["step"] == "stage.chroot.aur", st["step"])
check("status traz a atividade", st["act"] == "Compilando noctalia-shell", st["act"])
check("status traz o índice", st["idx"] == 6, st["idx"])
check("status traz o plano com 10 etapas", len(st["steps"]) == 10, len(st["steps"]))
check("status traz os rótulos traduzidos",
      st["steps"][6]["label"] == "Baixar e compilar pacotes da AUR", st["steps"][6])
check("status traz as últimas linhas do log", len(st["lines"]) >= 3, len(st["lines"]))

# ---------------------------------------------------------------------------
print("== fim da instalação ==")
log_line("NLRESULT|0")
pump(0.6)
check("chegou evento done", events.get("done", [])[-1]["code"] == 0, events.get("done"))
check("anel em 100%", srv.STATE["pct"] == 100, srv.STATE["pct"])
c3 = conn()
c3.request("GET", "/api/status")
st3 = json.loads(c3.getresponse().read().decode("utf-8"))
check("status final: done e 100%", st3["done"] and st3["pct"] == 100, (st3["done"], st3["pct"]))

httpd.shutdown()
c.close()
print()
if fails:
    print("FALHAS: %d -> %s" % (len(fails), fails))
    sys.exit(1)
print("todas as checagens passaram")
