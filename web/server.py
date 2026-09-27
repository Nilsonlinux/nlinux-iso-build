#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Instalador web do NLinux — servidor local (127.0.0.1).

Serve a interface (HTML/CSS/JS), coleta as escolhas e executa o install.sh
em subprocesso (GUI_DRIVEN=1), transmitindo o progresso para o navegador
via Server-Sent Events (SSE):

  event: progress   {pct, label}      atualiza a barra/anel
  event: tail       {line}            linha viva (ex.: progresso do rsync)
  event: log        {line}            linha de log permanente
  event: done       {code}            fim da instalação
  event: error      {message}

Dependências: apenas a biblioteca padrão do Python.
"""

import json
import os
import re
import select
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

_ui_lang = DEFAULT_LANG

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


class Broadcaster:
    """Distribui eventos para todos os clientes SSE conectados."""

    def __init__(self):
        self._subs = []
        self._lock = threading.Lock()

    def subscribe(self):
        q = deque()
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

# Slice de porcentagem ocupado pela etapa de cópia (rsync/pacstrap). O
# progresso real (progress2 do rsync, "N/M" do pacman) é interpolado nele.
COPY_SLICE = (35, 90)
_ctx = {"copying": False, "label": ""}


def _clean(raw):
    return ANSI_RE.sub("", raw.decode("utf-8", "replace")).rstrip("\r").strip()


def _push_real_progress(seg):
    """Interpola o progresso real (rsync progress2 ou N/M do pacman) no slice
    da etapa de cópia e emite um evento de progresso para o anel."""
    if not _ctx["copying"]:
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
    BROADCAST.push("progress", {"pct": int(base + (end - base) * frac), "label": _ctx["label"]})


def emit_line(raw):
    line = _clean(raw)
    if not line:
        return
    if line.startswith("NLPROGRESS|"):
        _, p, lab = line.split("|", 2)
        try:
            pct = int(float(p.strip()))
        except ValueError:
            pct = 0
        label = lab.strip()
        if label.startswith("stage.copy.offline") or label.startswith("stage.copy.online"):
            _ctx["copying"] = True
        elif label.startswith("stage.copy.") or label == "stage.pac.done":
            _ctx["copying"] = False
        if translations is not None:
            translated = translations.T(_ui_lang, label)
            if translated != label:
                label = translated
        if _ctx["copying"]:
            _ctx["label"] = label
        BROADCAST.push("progress", {"pct": pct, "label": label})
    else:
        BROADCAST.push("log", {"line": line})


def drain(proc, logfh=None):
    """Lê stdout do install.sh de forma reativa (suporta \r do rsync).

    Se logfh for informado, grava TODA a saída em bytes nele (persistência do
    log da instalação em /tmp/nlinux-install.log, independente do painel).
    """
    fd = proc.stdout.fileno()
    buf = b""
    last_tail = 0.0
    while True:
        r, _, _ = select.select([fd], [], [], 0.2)
        if fd in r:
            chunk = os.read(fd, 8192)
            if not chunk:
                break
            if logfh:
                logfh.write(chunk)
                logfh.flush()
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                emit_line(raw)
        now = time.time()
        if buf and b"\r" in buf and now - last_tail > 0.25:
            seg = buf.rsplit(b"\r", 1)[-1].decode("utf-8", "replace").strip()
            if seg:
                clean_seg = ANSI_RE.sub("", seg)
                BROADCAST.push("tail", {"line": clean_seg})
                _push_real_progress(clean_seg)
            last_tail = now


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
                "size": int(part.get("size") or 0),
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


def run_install(config):
    """Roda o install.sh com as escolhas do navegador e transmite o progresso."""
    global _ui_lang
    nllang = str(config.get("NLLANG") or LANG_FROM_LOCALE.get(str(config.get("LOCALE", ""))) or DEFAULT_LANG)
    nllang = nllang.split("_")[0].split("-")[0].lower()
    if nllang not in (translations.TRANSLATIONS if translations is not None else ()):
        nllang = DEFAULT_LANG
    _ui_lang = nllang

    if translations is not None:
        BROADCAST.push("progress", {"pct": 2, "label": translations.T(_ui_lang, "stage.start")})
    else:
        BROADCAST.push("progress", {"pct": 2, "label": "Preparando instalação"})
    env = dict(os.environ)
    for k, v in config.items():
        env[str(k)] = str(v)
    env["GUI_DRIVEN"] = "1"
    env["NLINUX_WEB"] = "1"
    env["NLLANG"] = _ui_lang
    logfh = open("/tmp/nlinux-install.log", "ab")
    logfh.write(b"\n========== instalacao iniciada: %s ==========\n" % time.asctime().encode())
    try:
        proc = subprocess.Popen(
            ["bash", INSTALL_SH],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        drain(proc, logfh)
        code = proc.wait()
    except Exception as exc:  # noqa: BLE001
        BROADCAST.push("error", {"message": str(exc)})
        code = 1
    finally:
        logfh.close()
    BROADCAST.push("done", {"code": code})


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
        if p == "/api/stream":
            return self._stream()
        return self._json({"error": "not found"}, 404)

    def _stream(self):
        q = BROADCAST.subscribe()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        try:
            self.wfile.write(": connected\n\n".encode())
            self.wfile.flush()
            while True:
                while q:
                    payload = q.popleft()
                    try:
                        self.wfile.write(payload.encode())
                        self.wfile.flush()
                    except OSError:
                        return
                    if payload.startswith(("event: done\n", "event: error\n")):
                        return
                time.sleep(8)
                try:
                    self.wfile.write(": keepalive\n\n".encode())
                    self.wfile.flush()
                except OSError:
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
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print("NLinux web installer em http://%s:%d" % (HOST, PORT), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())