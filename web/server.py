#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Instalador web do NLinux — servidor local (127.0.0.1).

Serve a interface (HTML/CSS/JS), coleta as escolhas e executa o install.sh
em subprocesso (GUI_DRIVEN=1), transmitindo o progresso para o navegador
via Server-Sent Events (SSE):

  event: state      {pct, label, lines, running, done, code, error}  ressincroniza
  event: progress   {pct, label}      atualiza a barra/anel
  event: tail       {line}            linha viva (ex.: progresso do rsync)
  event: log        {lines: [...]}    linhas de log (enviadas em lote)
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

# Slice de porcentagem ocupado pela etapa de cópia (rsync/pacstrap). O
# progresso real (progress2 do rsync, "N/M" do pacman) é interpolado nele.
COPY_SLICE = (35, 90)

LOG_MAX_LINES = 400        # linhas de log mantidas para ressincronizar a tela
LOG_SENT_LINES = 300       # linhas enviadas a cada cliente
FOLLOW_POLL = 0.2          # intervalo de leitura do arquivo de log
BATCH_INTERVAL = 0.2       # agrupa linhas de log em um único evento
TAIL_INTERVAL = 0.25       # cadência do "tail" (progresso com \r)
SAVE_INTERVAL = 5.0        # persiste o estado em disco
KEEPALIVE_S = 5.0          # heartbeat do SSE
WRITE_TIMEOUT = 30.0       # escrita travada por cliente não segura a thread

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
    "lines": [],
    "done": False,
    "code": None,
    "error": None,
    "started": 0.0,
    "finished": 0.0,
    "log": LOG_PATH,
}
# Progresso real da etapa de cópia (rsync/pacman): última etiqueta traduzida.
_copying = {"on": False, "label": ""}


def _public_state():
    """Estado pronto para o navegador (SSE /api/status)."""
    with _state_lock:
        return {
            "running": bool(STATE["running"]),
            "pct": int(STATE["pct"]),
            "label": _tr(STATE["label"]),
            "lang": _ui_lang,
            "done": bool(STATE["done"]),
            "code": STATE["code"],
            "error": STATE["error"],
            "started": STATE["started"],
            "finished": STATE["finished"],
            "lines": list(STATE["lines"][-LOG_SENT_LINES:]),
        }


def _state_save():
    """Checkpoint do estado em disco (para reanexar após queda do servidor)."""
    try:
        with _state_lock:
            data = dict(STATE)
        data["lines"] = data["lines"][-100:]
        data["lang"] = _ui_lang
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


def _push_real_progress(seg):
    """Interpola o progresso real (rsync progress2 ou N/M do pacman) no slice
    da etapa de cópia e emite um evento de progresso para o anel."""
    with _state_lock:
        if not _copying["on"]:
            return
        base, end = COPY_SLICE
        m = re.search(r"(\d+)%\s+.*to-chk=", seg)
        if m:
            frac = min(float(m.group(1)), 100.0) / 100.0
        else:
            m = re.search(r"\(\s*(\d+)\s*/\s*(\d+)\s*\)\s*\d+%", seg)
            if not m:
                return
            done, total = float(m.group(1)), float(m.group(2))
            if total <= 0:
                return
            frac = min(done / total, 1.0)
        pct = int(base + (end - base) * frac)
        label = _copying["label"]
        STATE["pct"] = pct
    BROADCAST.push("progress", {"pct": pct, "label": label})


def _on_progress(line):
    _, p, key = line.split("|", 2)
    try:
        pct = int(float(p.strip()))
    except ValueError:
        pct = 0
    key = key.strip()
    with _state_lock:
        if key.startswith("stage.copy.offline") or key.startswith("stage.copy.online"):
            _copying["on"] = True
        elif key.startswith("stage.copy.") or key == "stage.pac.done":
            _copying["on"] = False
        STATE["pct"] = pct
        STATE["label"] = key
    BROADCAST.push("progress", {"pct": pct, "label": _tr(key)})


def _on_result(line):
    """NLRESULT|<rc>: última linha escrita pelo install.sh (EXIT trap)."""
    try:
        code = int(line.split("|", 1)[1].strip())
    except (IndexError, ValueError):
        code = 1
    _finish(code)


def _finish(code, error=None):
    """Marca a instalação como encerrada e avisa os clientes (uma única vez)."""
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
        _copying["on"] = False
    _state_save()
    if error:
        BROADCAST.push("error", {"message": error})
    BROADCAST.push("done", {"code": code})


def _push_state():
    BROADCAST.push("state", _public_state())


def _handle_line(raw, pending):
    """Traduz uma linha do log em evento (ou a guarda no lote de log)."""
    line = _clean(raw)
    if not line:
        return
    if line.startswith("NLPROGRESS|"):
        _on_progress(line)
    elif line.startswith("NLRESULT|"):
        _on_result(line)
    else:
        pending.append(line)
        with _state_lock:
            STATE["lines"].append(line)
            if len(STATE["lines"]) > LOG_MAX_LINES:
                del STATE["lines"][:-LOG_MAX_LINES]


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
    last_tail = last_push = last_save = 0.0
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
            # "Linha viva": progresso com \r do rsync/pacman.
            if b"\r" in buf and now - last_tail >= TAIL_INTERVAL:
                seg = buf.rsplit(b"\r", 1)[-1].decode("utf-8", "replace").strip()
                if seg:
                    clean_seg = ANSI_RE.sub("", seg)
                    BROADCAST.push("tail", {"line": clean_seg})
                    _push_real_progress(clean_seg)
                last_tail = now
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
                if finished:
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
        for key in ("pct", "label", "done", "code", "error", "started", "finished", "log"):
            if data.get(key) is not None:
                STATE[key] = data[key]
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


def _begin_run():
    """Prepara estado e arquivo de log para uma nova instalação."""
    with _state_lock:
        STATE.update(
            running=True, pid=None, pct=0, label="stage.start", lines=[],
            done=False, code=None, error=None, started=time.time(), finished=0.0,
            log=LOG_PATH,
        )
        _copying["on"] = False
        _copying["label"] = ""
    try:
        # Log da execução anterior fica em .1 (o install.sh consulta
        # /tmp/nlinux-install.log para gravar o marcador de erro no disco).
        if os.path.exists(LOG_PATH):
            os.replace(LOG_PATH, LOG_PATH + ".1")
    except OSError:
        pass
    _state_save()


def run_install(config):
    """Roda o install.sh com as escolhas do navegador e transmite o progresso."""
    global _ui_lang
    nllang = str(config.get("NLLANG") or LANG_FROM_LOCALE.get(str(config.get("LOCALE", ""))) or DEFAULT_LANG)
    nllang = nllang.split("_")[0].split("-")[0].lower()
    if nllang not in (translations.TRANSLATIONS if translations is not None else ()):
        nllang = DEFAULT_LANG
    _ui_lang = nllang

    _begin_run()
    BROADCAST.push("progress", {"pct": 2, "label": _tr("stage.start")})
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
        threading.Thread(target=follow_log, args=(LOG_PATH,), daemon=True).start()
        code = proc.wait()
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
