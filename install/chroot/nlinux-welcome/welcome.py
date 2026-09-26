#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Janela de boas-vindas do NLinux (primeiro login / atalho manual).

Usa a mesma stack da loja (python-gobject + GTK3) e carrega o idioma que foi
escolhido no instalador web (lido de /etc/locale.conf no sistema instalado).

Modos:
  padrão        -> exibe uma vez por usuário (marcador ~/.config/nlinux-welcome-v1),
                   no sistema instalado.
  --menu        -> abre sempre (atalho), e marca como visto no final.
"""

import os
import sys
import webbrowser
from datetime import datetime

APP_DIR = "/usr/share/nlinux-welcome"
MARKER = os.path.expanduser("~/.config/nlinux-welcome-v1")

REPO_URL = "https://github.com/Nilsonlinux"
SITE_URL = "https://nilsonlinux.github.io/nlinux.html"
AUTHOR = "Nilsonlinux"

LANG_ALIASES = {
    "pt-br": "pt",
    "pt-pt": "pt",
    "en-us": "en",
    "en-gb": "en",
    "es-es": "es",
    "fr-fr": "fr",
    "de-de": "de",
    "it-it": "it",
    "ja-jp": "ja",
}

T = {
    "pt": {
        "window.title": "Boas-vindas ao NLinux",
        "hello": "Seja bem-vindo ao NLinux!",
        "msg": "Instalação concluída com sucesso. Seu sistema está pronto.",
        "card.title": "Sobre o sistema",
        "label.name": "Nome",
        "label.version": "Versão",
        "label.update": "Data de atualização",
        "label.author": "Autor",
        "features.title": "Destaques",
        "features": [
            "App Center para instalar programas",
            "Terminal kitty  (Mod+T)",
            "Shell padrão: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Ver código no GitHub",
        "tip.github": "Abrir github.com/Nilsonlinux",
        "btn.site": "Acessar o site",
        "tip.site": "Abrir nilsonlinux.github.io/nlinux.html",
        "btn.close": "Começar a usar",
        "footer": "Feito com carinho por Nilsonlinux",
        "date_fmt": "%d/%m/%Y",
        "built_at": "gerado em {date}",
    },
    "en": {
        "window.title": "Welcome to NLinux",
        "hello": "Welcome to NLinux!",
        "msg": "Installation completed successfully. Your system is ready.",
        "card.title": "About the system",
        "label.name": "Name",
        "label.version": "Version",
        "label.update": "Update date",
        "label.author": "Author",
        "features.title": "Highlights",
        "features": [
            "App Center to install programs",
            "kitty terminal  (Mod+T)",
            "Default shell: fish",
            "Umbriel + Noctalia compositor",
        ],
        "btn.github": "View code on GitHub",
        "tip.github": "Open github.com/Nilsonlinux",
        "btn.site": "Visit the website",
        "tip.site": "Open nilsonlinux.github.io/nlinux.html",
        "btn.close": "Get started",
        "footer": "Made with love by Nilsonlinux",
        "date_fmt": "%m/%d/%Y",
        "built_at": "built on {date}",
    },
    "es": {
        "window.title": "Bienvenido a NLinux",
        "hello": "¡Bienvenido a NLinux!",
        "msg": "Instalación completada con éxito. Tu sistema está listo.",
        "card.title": "Acerca del sistema",
        "label.name": "Nombre",
        "label.version": "Versión",
        "label.update": "Fecha de actualización",
        "label.author": "Autor",
        "features.title": "Destacados",
        "features": [
            "App Center para instalar programas",
            "Terminal kitty  (Mod+T)",
            "Shell por defecto: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Ver código en GitHub",
        "tip.github": "Abrir github.com/Nilsonlinux",
        "btn.site": "Visitar el sitio",
        "tip.site": "Abrir nilsonlinux.github.io/nlinux.html",
        "btn.close": "Empezar",
        "footer": "Hecho con cariño por Nilsonlinux",
        "date_fmt": "%d/%m/%Y",
        "built_at": "generado el {date}",
    },
    "fr": {
        "window.title": "Bienvenue sur NLinux",
        "hello": "Bienvenue sur NLinux !",
        "msg": "L'installation s'est terminée avec succès. Votre système est prêt.",
        "card.title": "À propos du système",
        "label.name": "Nom",
        "label.version": "Version",
        "label.update": "Date de mise à jour",
        "label.author": "Auteur",
        "features.title": "Points forts",
        "features": [
            "App Center pour installer des programmes",
            "Terminal kitty  (Mod+T)",
            "Shell par défaut : fish",
            "Compositeur Umbriel + Noctalia",
        ],
        "btn.github": "Voir le code sur GitHub",
        "tip.github": "Ouvrir github.com/Nilsonlinux",
        "btn.site": "Visiter le site",
        "tip.site": "Ouvrir nilsonlinux.github.io/nlinux.html",
        "btn.close": "Commencer",
        "footer": "Fait avec amour par Nilsonlinux",
        "date_fmt": "%d/%m/%Y",
        "built_at": "généré le {date}",
    },
    "de": {
        "window.title": "Willkommen bei NLinux",
        "hello": "Willkommen bei NLinux!",
        "msg": "Die Installation war erfolgreich. Ihr System ist bereit.",
        "card.title": "Über das System",
        "label.name": "Name",
        "label.version": "Version",
        "label.update": "Aktualisierungsdatum",
        "label.author": "Autor",
        "features.title": "Highlights",
        "features": [
            "App Center zum Installieren von Programmen",
            "kitty-Terminal  (Mod+T)",
            "Standard-Shell: fish",
            "Umbriel + Noctalia-Compositor",
        ],
        "btn.github": "Code auf GitHub ansehen",
        "tip.github": "github.com/Nilsonlinux öffnen",
        "btn.site": "Website besuchen",
        "tip.site": "nilsonlinux.github.io/nlinux.html öffnen",
        "btn.close": "Loslegen",
        "footer": "Mit Liebe von Nilsonlinux erstellt",
        "date_fmt": "%d.%m.%Y",
        "built_at": "erstellt am {date}",
    },
    "it": {
        "window.title": "Benvenuto su NLinux",
        "hello": "Benvenuto su NLinux!",
        "msg": "Installazione completata con successo. Il tuo sistema è pronto.",
        "card.title": "Informazioni sul sistema",
        "label.name": "Nome",
        "label.version": "Versione",
        "label.update": "Data di aggiornamento",
        "label.author": "Autore",
        "features.title": "In evidenza",
        "features": [
            "App Center per installare programmi",
            "Terminale kitty  (Mod+T)",
            "Shell predefinita: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Vedi il codice su GitHub",
        "tip.github": "Apri github.com/Nilsonlinux",
        "btn.site": "Visita il sito",
        "tip.site": "Apri nilsonlinux.github.io/nlinux.html",
        "btn.close": "Inizia",
        "footer": "Creato con amore da Nilsonlinux",
        "date_fmt": "%d/%m/%Y",
        "built_at": "creato il {date}",
    },
    "ja": {
        "window.title": "NLinux へようこそ",
        "hello": "NLinux へようこそ！",
        "msg": "インストールが正常に完了しました。システムの準備ができました。",
        "card.title": "システムについて",
        "label.name": "名前",
        "label.version": "バージョン",
        "label.update": "更新日",
        "label.author": "作者",
        "features.title": "特長",
        "features": [
            "アプリをインストールする App Center",
            "kitty ターミナル (Mod+T)",
            "デフォルトのシェル: fish",
            "Umbriel と Noctalia コンポジター",
        ],
        "btn.github": "GitHub でコードを見る",
        "tip.github": "github.com/Nilsonlinux を開く",
        "btn.site": "ウェブサイトへ",
        "tip.site": "nilsonlinux.github.io/nlinux.html を開く",
        "btn.close": "はじめる",
        "footer": "Nilsonlinux によって作られた NLinux",
        "date_fmt": "%Y/%m/%d",
        "built_at": "{date} に生成",
    },
}

CSS = """
window {
  background-image: linear-gradient(to bottom, #171738, #0b0b18);
}

.hello {
  font-size: 26px;
  font-weight: 700;
  color: #ffffff;
}

.msg {
  font-size: 13px;
  color: #b8b8d0;
}

#card {
  background-color: rgba(255, 255, 255, 0.06);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.card-title {
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 2px;
  color: #9d9dbb;
}

.info-label {
  font-size: 13px;
  color: #9d9dbb;
}

.info-value {
  font-size: 14px;
  font-weight: 600;
  color: #ffffff;
}

.feature {
  font-size: 13px;
  color: #d8d8ec;
}

.btn-label {
  font-size: 13px;
  font-weight: 600;
}

button {
  transition: all 150ms ease-in-out;
}

button.link {
  background-image: linear-gradient(to bottom, rgba(255, 255, 255, 0.12), rgba(255, 255, 255, 0.04));
  background-color: transparent;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  padding: 10px 14px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.10);
}

button.link:hover {
  background-image: linear-gradient(to bottom, rgba(31, 111, 235, 0.60), rgba(31, 111, 235, 0.28));
  border-color: #7fb0ff;
  box-shadow: 0 0 0 1px rgba(31, 111, 235, 0.55), 0 4px 16px rgba(31, 111, 235, 0.35);
}

button.link:active {
  background-image: linear-gradient(to bottom, rgba(31, 111, 235, 0.75), rgba(31, 111, 235, 0.45));
  border-color: #9cc2ff;
  box-shadow: inset 0 2px 6px rgba(0, 0, 0, 0.35);
}

button.link label {
  color: #eaf1ff;
  font-weight: 600;
}

button.primary {
  background-image: linear-gradient(to bottom, #3583f6, #1a5fd6);
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.18);
  padding: 10px 22px;
  box-shadow: 0 2px 10px rgba(31, 111, 235, 0.40), inset 0 1px 0 rgba(255, 255, 255, 0.22);
}

button.primary:hover {
  background-image: linear-gradient(to bottom, #4b90f8, #2a6fe0);
  border-color: #9cc2ff;
  box-shadow: 0 4px 18px rgba(31, 111, 235, 0.55), inset 0 1px 0 rgba(255, 255, 255, 0.30);
}

button.primary:active {
  background-image: linear-gradient(to bottom, #1556c9, #0f4ab0);
  box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.40);
}

button.primary label {
  color: #ffffff;
  font-size: 13px;
  font-weight: 700;
}

.footer {
  font-size: 11px;
  color: #6f6f92;
}
"""


def resolve_lang():
    code = None
    try:
        with open("/etc/locale.conf") as fh:
            for line in fh:
                if line.startswith("LANG="):
                    code = line.split("=", 1)[1].strip().strip('"')
                    break
    except OSError:
        pass
    if not code:
        code = os.environ.get("LANG")
    if not code:
        try:
            import locale as _l
            code = _l.setlocale(_l.LC_CTYPE, None)
        except Exception:
            code = None
    base = (code or "").split(".", 1)[0].lower().replace("_", "-")
    if base in LANG_ALIASES:
        return LANG_ALIASES[base]
    first = base.split("-", 1)[0]
    return first if first in LANG_ALIASES.values() else "pt"


def read_release():
    data = {}
    try:
        with open("/etc/nlinux-release") as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.split("=", 1)
                    data[k.strip()] = v.strip().strip('"')
    except OSError:
        pass
    return data


def format_built(ts, lang):
    if not ts:
        return "—"
    parsed = None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            parsed = datetime.strptime(ts, fmt)
            break
        except ValueError:
            continue
    if parsed is None:
        return ts
    return T[lang]["built_at"].format(date=parsed.strftime(T[lang]["date_fmt"]))


def build_ui(lang, release):
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

    t = T.get(lang, T["pt"])

    wm_class = "nlinux-welcome"
    GLib.set_prgname(wm_class)
    try:
        Gdk.set_program_class(wm_class)
    except Exception:
        pass

    win = Gtk.Window()
    win.set_wmclass(wm_class, wm_class)
    win.set_title(t["window.title"])
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_default_size(580, 430)
    win.set_resizable(False)
    try:
        win.set_icon(
            GdkPixbuf.Pixbuf.new_from_file_at_scale(
                os.path.join(APP_DIR, "welcome-logo.png"), 128, 128, True))
    except Exception:
        pass

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS.encode("utf-8"))
    screen = Gdk.Screen.get_default()
    if screen is not None:
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    root.set_margin_top(14)
    root.set_margin_bottom(12)
    root.set_margin_start(40)
    root.set_margin_end(40)
    win.add(root)

    try:
        logo_pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
            os.path.join(APP_DIR, "welcome-logo.png"), 140, 140, True)
        logo = Gtk.Image.new_from_pixbuf(logo_pixbuf)
    except Exception:
        logo = Gtk.Label()
        logo.set_text("NLinux")
        logo.set_name("hello")
    root.pack_start(logo, False, False, 0)

    hello = Gtk.Label(label=t["hello"])
    hello.get_style_context().add_class("hello")
    hello.set_margin_top(8)
    root.pack_start(hello, False, False, 0)

    msg = Gtk.Label(label=t["msg"])
    msg.get_style_context().add_class("msg")
    msg.set_line_wrap(True)
    msg.set_justify(Gtk.Justification.CENTER)
    msg.set_margin_top(2)
    root.pack_start(msg, False, False, 0)

    board = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    board.set_margin_top(12)

    info_card = _card(board, t["card.title"])
    version = release.get("NILINUX_VERSION", "rolling")
    info_card.pack_start(_info_row(t["label.name"], "NLinux"), False, False, 5)
    info_card.pack_start(_info_row(t["label.version"], version), False, False, 5)
    info_card.pack_start(_info_row(t["label.update"],
                                   format_built(release.get("NILINUX_BUILT"), lang)),
                         False, False, 5)
    info_card.pack_start(_info_row(t["label.author"], AUTHOR), False, False, 5)

    feat_card = _card(board, t["features.title"])
    for feat in t["features"]:
        feat_label = Gtk.Label(label="•  " + feat)
        feat_label.get_style_context().add_class("feature")
        feat_label.set_halign(Gtk.Align.START)
        feat_label.set_margin_top(2)
        feat_card.pack_start(feat_label, False, False, 0)

    root.pack_start(board, False, False, 0)

    btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    btns.set_homogeneous(True)
    btns.set_margin_top(12)

    def _open(url):
        try:
            webbrowser.open(url)
        except Exception:
            pass

    btns.pack_start(_link_button(t["btn.github"], t["tip.github"],
                                 github=True, on_click=lambda *_: _open(REPO_URL)),
                    True, True, 0)
    btns.pack_start(_link_button(t["btn.site"], t["tip.site"],
                                 on_click=lambda *_: _open(SITE_URL)),
                    True, True, 0)
    root.pack_start(btns, False, False, 0)

    close = Gtk.Button(label=t["btn.close"])
    close.get_style_context().add_class("primary")
    close.set_margin_top(8)
    close.set_halign(Gtk.Align.CENTER)
    close.connect("clicked", lambda *_: win.destroy())
    root.pack_start(close, False, False, 0)

    footer = Gtk.Label(label=("© NLinux   ·   " + t["footer"]))
    footer.get_style_context().add_class("footer")
    footer.set_margin_top(10)
    root.pack_start(footer, False, False, 0)

    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


def _card(parent, title):
    from gi.repository import Gtk
    card = Gtk.Frame()
    card.set_name("card")
    card.set_shadow_type(Gtk.ShadowType.NONE)
    card.set_hexpand(True)
    inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    inner.set_margin_start(14)
    inner.set_margin_end(14)
    inner.set_margin_top(8)
    inner.set_margin_bottom(8)
    card.add(inner)
    ctitle = Gtk.Label(label=title)
    ctitle.get_style_context().add_class("card-title")
    ctitle.set_halign(Gtk.Align.START)
    inner.pack_start(ctitle, False, False, 0)
    parent.pack_start(card, True, True, 0)
    return inner


def _info_row(label, value):
    from gi.repository import Gtk
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
    row.set_margin_top(3)
    l1 = Gtk.Label(label=label)
    l1.get_style_context().add_class("info-label")
    l1.set_halign(Gtk.Align.START)
    v1 = Gtk.Label(label=value)
    v1.get_style_context().add_class("info-value")
    v1.set_halign(Gtk.Align.END)
    v1.set_hexpand(True)
    sep = "  "
    row.pack_start(l1, False, False, 0)
    row.pack_start(v1, True, True, 0)
    return row


def _link_button(text, tooltip, on_click, github=False):
    from gi.repository import Gtk
    btn = Gtk.Button()
    btn.get_style_context().add_class("link")
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    center = Gtk.Align.CENTER
    if github:
        try:
            img = Gtk.Image.new_from_file(
                os.path.join(APP_DIR, "github.png"))
            box.pack_start(img, False, False, 0)
        except Exception:
            pass
        box.set_halign(center)
        box.set_valign(center)
    lbl = Gtk.Label(label=text)
    lbl.get_style_context().add_class("btn-label")
    box.pack_start(lbl, False, False, 0)
    box.set_halign(center)
    box.set_valign(center)
    btn.add(box)
    btn.set_tooltip_text(tooltip)
    btn.connect("clicked", on_click)
    return btn


def main():
    once = "--menu" not in sys.argv
    if once and os.path.exists(MARKER):
        return 0
    lang = resolve_lang()
    release = read_release()
    # Garante o Gtk importado apenas no escopo certo; roda com fallback x11.
    try:
        build_ui(lang, release)
    except Exception:
        # Tenta de novo forçando X11 (mais confiável sob o Umbriel).
        os.environ["GDK_BACKEND"] = "x11"
        try:
            build_ui(lang, release)
        except Exception:
            return 1
    try:
        with open(MARKER, "w") as fh:
            fh.write("v1\n")
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())