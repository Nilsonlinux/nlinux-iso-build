#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: GPL-3.0-or-later
"""Janela de boas-vindas do NLinux (primeiro login / atalho manual).

Usa python-gobject + GTK4 e carrega o idioma que foi escolhido no instalador
web (lido de /etc/locale.conf no sistema instalado).

Modos:
  padrão        -> exibe uma vez por usuário (marcador ~/.config/nlinux-welcome-v1),
                   no sistema instalado.
  --menu        -> abre sempre (atalho), e marca como visto no final.
"""

import os
import sys
import time
import webbrowser
from datetime import datetime

APP_DIR = os.environ.get("NLINUX_WELCOME_DIR", "/usr/share/nlinux-welcome")
MARKER = os.path.expanduser("~/.config/nlinux-welcome-v1")

REPO_URL = "https://github.com/Nilsonlinux/nlinux-iso-build"
SITE_URL = "https://nilsonlinux.github.io/"
DONATE_URL = "https://nilsonlinux.github.io/doar.html"
ABOUT_URL = "https://nilsonlinux.github.io/sobre.html"
AUTHOR = "Nilsonlinux"

# Última release publicada (a data que aparece em "Versão atual"). Consultada
# online e guardada em cache por 24h; sem rede, vale o que estiver no cache —
# e, sem cache nenhum, cai para a versão gravada na instalação.
RELEASES_API = (
    "https://api.github.com/repos/Nilsonlinux/nlinux-iso-build/releases/latest"
)
LATEST_CACHE = os.path.expanduser("~/.cache/nlinux-welcome-latest")

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
        "label.update": "Data de instalação",
        "label.iso_latest": "Versão atual (releases)",
        "label.author": "Autor",
        "features.title": "Destaques",
        "features": [
            "NLinux Software para instalar programas",
            "Terminal kitty  (Mod+T)",
            "Shell padrão: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Ver código no GitHub",
        "tip.github": "Abrir github.com/Nilsonlinux/nlinux-iso-build",
        "btn.site": "Acessar o site",
        "tip.site": "Abrir nilsonlinux.github.io",
        "menu.donate": "Fazer doação",
        "menu.about": "Sobre o NLinux",
        "menu.tooltip": "Mais opções",
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
        "label.update": "Installation date",
        "label.iso_latest": "Latest version (releases)",
        "label.author": "Author",
        "features.title": "Highlights",
        "features": [
            "NLinux Software to install programs",
            "kitty terminal  (Mod+T)",
            "Default shell: fish",
            "Umbriel + Noctalia compositor",
        ],
        "btn.github": "View code on GitHub",
        "tip.github": "Open github.com/Nilsonlinux/nlinux-iso-build",
        "btn.site": "Visit the website",
        "tip.site": "Open nilsonlinux.github.io",
        "menu.donate": "Make a donation",
        "menu.about": "About",
        "menu.tooltip": "More options",
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
        "label.update": "Fecha de instalación",
        "label.iso_latest": "Última versión (releases)",
        "label.author": "Autor",
        "features.title": "Destacados",
        "features": [
            "NLinux Software para instalar programas",
            "Terminal kitty  (Mod+T)",
            "Shell por defecto: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Ver código en GitHub",
        "tip.github": "Abrir github.com/Nilsonlinux/nlinux-iso-build",
        "btn.site": "Visitar el sitio",
        "tip.site": "Abrir nilsonlinux.github.io",
        "menu.donate": "Hacer una donación",
        "menu.about": "Acerca de",
        "menu.tooltip": "Más opciones",
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
        "label.update": "Date d'installation",
        "label.iso_latest": "Dernière version (releases)",
        "label.author": "Auteur",
        "features.title": "Points forts",
        "features": [
            "NLinux Software pour installer des programmes",
            "Terminal kitty  (Mod+T)",
            "Shell par défaut : fish",
            "Compositeur Umbriel + Noctalia",
        ],
        "btn.github": "Voir le code sur GitHub",
        "tip.github": "Ouvrir github.com/Nilsonlinux/nlinux-iso-build",
        "btn.site": "Visiter le site",
        "tip.site": "Ouvrir nilsonlinux.github.io",
        "menu.donate": "Faire un don",
        "menu.about": "À propos",
        "menu.tooltip": "Plus d'options",
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
        "label.update": "Installationsdatum",
        "label.iso_latest": "Aktuelle Version (Releases)",
        "label.author": "Autor",
        "features.title": "Highlights",
        "features": [
            "NLinux Software zum Installieren von Programmen",
            "kitty-Terminal  (Mod+T)",
            "Standard-Shell: fish",
            "Umbriel + Noctalia-Compositor",
        ],
        "btn.github": "Code auf GitHub ansehen",
        "tip.github": "github.com/Nilsonlinux/nlinux-iso-build öffnen",
        "btn.site": "Website besuchen",
        "tip.site": "nilsonlinux.github.io öffnen",
        "menu.donate": "Spenden",
        "menu.about": "Über",
        "menu.tooltip": "Weitere Optionen",
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
        "label.update": "Data di installazione",
        "label.iso_latest": "Ultima versione (releases)",
        "label.author": "Autore",
        "features.title": "In evidenza",
        "features": [
            "NLinux Software per installare programmi",
            "Terminale kitty  (Mod+T)",
            "Shell predefinita: fish",
            "Compositor Umbriel + Noctalia",
        ],
        "btn.github": "Vedi il codice su GitHub",
        "tip.github": "Apri github.com/Nilsonlinux/nlinux-iso-build",
        "btn.site": "Visita il sito",
        "tip.site": "Apri nilsonlinux.github.io",
        "menu.donate": "Fai una donazione",
        "menu.about": "Informazioni",
        "menu.tooltip": "Altre opzioni",
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
        "label.update": "インストール日",
        "label.iso_latest": "最新バージョン（リリース）",
        "label.author": "作者",
        "features.title": "特長",
        "features": [
            "NLinux Software でアプリをインストール",
            "kitty ターミナル (Mod+T)",
            "デフォルトのシェル: fish",
            "Umbriel と Noctalia コンポジター",
        ],
        "btn.github": "GitHub でコードを見る",
        "tip.github": "github.com/Nilsonlinux/nlinux-iso-build を開く",
        "btn.site": "ウェブサイトへ",
        "tip.site": "nilsonlinux.github.io を開く",
        "menu.donate": "寄付する",
        "menu.about": "NLinux について",
        "menu.tooltip": "その他のオプション",
        "btn.close": "はじめる",
        "footer": "Nilsonlinux によって作られた NLinux",
        "date_fmt": "%Y/%m/%d",
        "built_at": "{date} に生成",
    },
}

CSS = """
window {
  background-color: @window_bg_color;
  background-image: none;
}

headerbar {
  background: transparent;
  border: none;
  box-shadow: none;
  min-height: 38px;
}

headerbar .title,
.window-title {
  color: @window_fg_color;
  font-weight: 700;
}

menubutton.welcome-menu-button > button {
  background: transparent;
  border: none;
  border-radius: 6px;
  box-shadow: none;
}

menubutton.welcome-menu-button > button:hover {
  background-color: alpha(@window_fg_color, 0.12);
}

button.highlighted:hover,
menubutton.highlighted > button:hover {
  background-color: alpha(@window_fg_color, 0.12);
}

button.highlighted,
menubutton.highlighted > button {
  background-color: transparent;
}

button.highlighted:active > *,
menubutton.highlighted > button:active > * {
  transform: scale(0.8);
}

button.highlighted > *,
menubutton.highlighted > button > * {
  transition: transform 0.2s;
}

/* Mantém o botão do menu destacado enquanto o popover está aberto. */
menubutton.welcome-menu-button > button:checked,
menubutton.highlighted > button:checked {
  background-color: alpha(@window_fg_color, 0.12);
}

menubutton.welcome-menu-button > button:checked:hover,
menubutton.highlighted > button:checked:hover {
  background-color: alpha(@window_fg_color, 0.15);
}

/* Botão de fechar: círculo de fundo como no Nautilus (libadwaita). */
windowcontrols.overlaid > button > image {
  color: @window_fg_color;
  min-width: 24px;
  min-height: 24px;
  background-color: alpha(@window_fg_color, 0.10);
  border-radius: 100%;
  transition: background-color 200ms ease, transform 0.2s;
}

windowcontrols.overlaid > button:hover > image {
  background-color: alpha(@window_fg_color, 0.15);
}

windowcontrols.overlaid > button:active > image {
  background-color: alpha(@window_fg_color, 0.30);
}

image.overlaid,
menubutton.overlaid > button > box > image {
  color: @window_fg_color;
  filter: drop-shadow(0 0 1px alpha(black, 0.4))
    drop-shadow(0 0 3px alpha(black, 0.1))
    drop-shadow(0 0 9px alpha(black, 0.3));
}

popover.welcome-menu.background {
  background-color: transparent;
  background-image: none;
  box-shadow: none;
}

popover.welcome-menu.background > arrow,
popover.welcome-menu.background > contents {
  background-color: @popover_bg_color;
  background-image: none;
  color: @popover_fg_color;
  border: 1px solid alpha(@popover_fg_color, 0.12);
  box-shadow: none;
}

popover.welcome-menu.background > contents {
  background-clip: padding-box;
  border-radius: 12px;
}

popover.welcome-menu modelbutton:hover,
popover.welcome-menu modelbutton:selected {
  background-color: alpha(@popover_fg_color, 0.12);
}

.hello {
  font-size: 28px;
  font-weight: 800;
  color: @window_fg_color;
}

.msg {
  font-size: 13px;
  color: alpha(@window_fg_color, 0.72);
}

.card {
  background-color: @card_bg_color;
  border-radius: 16px;
  border: 1px solid alpha(@card_fg_color, 0.12);
  padding: 14px 16px;
}

.card-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 2px;
  color: alpha(@card_fg_color, 0.66);
}

.info-label {
  font-size: 13px;
  color: alpha(@card_fg_color, 0.66);
}

.info-value {
  font-size: 14px;
  font-weight: 600;
  color: @card_fg_color;
}

.feature {
  font-size: 13px;
  color: alpha(@card_fg_color, 0.88);
}

.btn-label {
  font-size: 13px;
  font-weight: 600;
}

button {
  transition: all 150ms ease-in-out;
}

button.link {
  background-image: none;
  background-color: alpha(@window_fg_color, 0.02);
  border-radius: 999px;
  border: 1px solid alpha(@window_fg_color, 0.22);
  padding: 10px 26px;
  box-shadow: 0 1px 2px alpha(@window_fg_color, 0.12);
}

button.link:hover {
  background-color: @theme_selected_bg_color;
  border-color: @theme_selected_bg_color;
  box-shadow: 0 0 0 1px alpha(@theme_selected_bg_color, 0.45);
}

button.link:active {
  background-color: @theme_selected_bg_color;
  border-color: @theme_selected_bg_color;
  box-shadow: inset 0 1px 3px alpha(@accent_fg_color, 0.25);
}

button.link:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px alpha(@theme_selected_bg_color, 0.85);
}

button.link label {
  color: @window_fg_color;
  font-weight: 600;
}

button.link:hover label {
  color: @theme_selected_fg_color;
}

.github-icon {
  opacity: 0.92;
}

.github-icon.dark {
  filter: invert(1);
}

button.link:hover .github-icon {
  filter: none;
  opacity: 1;
}

button.primary {
  background-image: none;
  background-color: alpha(@window_fg_color, 0.02);
  border-radius: 999px;
  border: 1px solid alpha(@window_fg_color, 0.22);
  padding: 10px 22px;
  box-shadow: 0 1px 2px alpha(@window_fg_color, 0.12);
}

button.primary:hover {
  background-color: @theme_selected_bg_color;
  border-color: @theme_selected_bg_color;
  box-shadow: 0 0 0 1px alpha(@theme_selected_bg_color, 0.45);
}

button.primary:active {
  background-color: @theme_selected_bg_color;
  border-color: @theme_selected_bg_color;
  box-shadow: inset 0 1px 3px alpha(@accent_fg_color, 0.25);
}

button.primary:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px alpha(@theme_selected_bg_color, 0.85);
}

button.primary label {
  color: @window_fg_color;
  font-size: 13px;
  font-weight: 700;
}

button.primary:hover label {
  color: @theme_selected_fg_color;
}

.footer {
  font-size: 11px;
  color: alpha(@window_fg_color, 0.56);
}

tooltip {
  padding: 7px 12px;
  border-radius: 12px;
  box-shadow: none;
}

tooltip.background {
  background-color: alpha(@popover_bg_color, 0.97);
  background-clip: padding-box;
  border: 1px solid alpha(@popover_fg_color, 0.2);
  border-radius: 12px;
  color: @popover_fg_color;
  box-shadow: inset 0 1px 0 alpha(@popover_fg_color, 0.08);
}

tooltip > box {
  border-spacing: 6px;
}

tooltip label {
  color: @popover_fg_color;
  font-size: 12px;
  font-weight: 500;
}

tooltip.csd {
  border-radius: 12px;
  box-shadow: none;
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


def installed_at(release):
    """Data em que o sistema foi instalado.

    Preferência: chave NLINUX_INSTALLED gravada pelo instalador. Em sistemas
    instalados antes dessa chave existir, usa a data do marcador
    /etc/nlinux-installed. Por último (ex.: execução no live) usa a data do
    build da ISO.
    """
    ts = release.get("NLINUX_INSTALLED")
    if ts:
        return ts
    try:
        with open("/etc/nlinux-installed") as fh:
            marker = fh.read().strip()
        if marker:
            return marker
    except OSError:
        pass
    try:
        st = os.stat("/etc/nlinux-installed")
        birth = getattr(st, "st_birthtime", None)
        return datetime.fromtimestamp(
            birth if birth else st.st_mtime).strftime("%Y-%m-%dT%H:%M:%S")
    except OSError:
        pass
    return release.get("NLINUX_BUILT") or release.get("NLINUX_VERSION")


def format_date(ts, lang):
    """Formata uma data da ISO (2026.10.09) ou um timestamp para exibição."""
    if not ts:
        return "—"
    parsed = None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%d", "%Y.%m.%d"):
        try:
            parsed = datetime.strptime(ts, fmt)
            break
        except ValueError:
            continue
    if parsed is None:
        return ts
    return parsed.strftime(T[lang]["date_fmt"])


def cached_latest_release():
    """Última release em cache (< 24h), ou None. Não acessa a rede."""
    try:
        if (os.path.exists(LATEST_CACHE)
                and time.time() - os.path.getmtime(LATEST_CACHE) < 24 * 3600):
            with open(LATEST_CACHE) as fh:
                tag = fh.read().strip()
            return tag or None
    except OSError:
        pass
    return None


def fetch_latest_release():
    """Consulta a última release no GitHub e atualiza o cache.

    Retorna a tag (ex.: "2026.10.09") ou None se estiver offline. Quem chama
    deve rodar isto fora da thread da interface: a janela não pode esperar
    pela rede para aparecer.
    """
    try:
        import json
        import urllib.request
        req = urllib.request.Request(
            RELEASES_API, headers={"User-Agent": "nlinux-welcome"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        tag = (data.get("tag_name") or "").strip()
        if tag:
            try:
                os.makedirs(os.path.dirname(LATEST_CACHE), exist_ok=True)
                with open(LATEST_CACHE, "w") as fh:
                    fh.write(tag + "\n")
            except OSError:
                pass
            return tag
    except Exception:
        pass
    # Sem rede: usa o cache antigo, se houver.
    try:
        with open(LATEST_CACHE) as fh:
            return fh.read().strip() or None
    except OSError:
        return None


def _apply_css():
    import gi

    gi.require_version("Gdk", "4.0")
    from gi.repository import Gdk, Gtk

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS.encode("utf-8"))
    display = Gdk.Display.get_default()
    if display is not None:
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def build_ui(lang, release):
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import Gio, Gtk

    app = Gtk.Application(
        application_id="org.nlinux.Welcome",
        flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
    )

    def on_activate(application):
        _apply_css()
        win = build_window(application, lang, release)
        win.present()

    app.connect("activate", on_activate)
    return app.run([])


def build_window(app, lang, release):
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import Gio, GLib, Gtk

    t = T.get(lang, T["pt"])

    def _open_donation(*_args):
        try:
            webbrowser.open(DONATE_URL)
        except Exception:
            pass

    def _open_about(*_args):
        try:
            webbrowser.open(ABOUT_URL)
        except Exception:
            pass

    win = Gtk.ApplicationWindow(application=app)
    win.set_title(t["window.title"])
    win.set_default_size(660, 560)
    win.set_resizable(False)
    try:
        win.set_icon_name("nlinux-welcome")
    except Exception:
        pass

    header = Gtk.HeaderBar()
    header.set_show_title_buttons(False)
    title = Gtk.Label(label=t["window.title"])
    title.add_css_class("window-title")
    header.set_title_widget(title)

    donate_action = Gio.SimpleAction.new("donate", None)
    donate_action.connect("activate", _open_donation)
    win.add_action(donate_action)
    about_action = Gio.SimpleAction.new("about", None)
    about_action.connect("activate", _open_about)
    win.add_action(about_action)

    menu = Gio.Menu()
    donate_item = Gio.MenuItem.new(
        t.get("menu.donate", "Fazer doação"), "win.donate")
    try:
        donate_item.set_icon(Gio.ThemedIcon.new("emote-love-symbolic"))
    except Exception:
        pass
    menu.append_item(donate_item)
    menu.append(
        t.get("menu.about", "Sobre"), "win.about")

    menu_button = Gtk.MenuButton()
    menu_button.set_icon_name("open-menu-symbolic")
    menu_button.set_tooltip_text(t.get("menu.tooltip", "Mais opções"))
    menu_button.set_valign(Gtk.Align.CENTER)
    menu_button.set_primary(True)
    menu_popover = Gtk.PopoverMenu.new_from_model(menu)
    menu_popover.add_css_class("welcome-menu")
    menu_popover.set_position(Gtk.PositionType.BOTTOM)
    menu_popover.set_has_arrow(True)
    menu_button.set_popover(menu_popover)
    for css_class in ("highlighted", "overlaid", "welcome-menu-button"):
        menu_button.add_css_class(css_class)

    header_end = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
    header_end.set_margin_top(6)
    header_end.set_margin_bottom(3)
    header_end.set_margin_start(3)
    header_end.set_margin_end(6)
    header_end.append(menu_button)

    window_controls = Gtk.WindowControls.new(Gtk.PackType.END)
    window_controls.set_valign(Gtk.Align.CENTER)
    window_controls.add_css_class("overlaid")
    header_end.append(window_controls)
    header.pack_end(header_end)

    win.set_titlebar(header)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    root.set_margin_top(10)
    root.set_margin_bottom(14)
    root.set_margin_start(42)
    root.set_margin_end(42)
    win.set_child(root)

    logo_path = os.path.join(APP_DIR, "welcome-logo.png")
    if os.path.exists(logo_path):
        logo = Gtk.Image.new_from_file(logo_path)
        logo.set_pixel_size(128)
        logo.set_halign(Gtk.Align.CENTER)
    else:
        logo = Gtk.Label(label="NLinux")
        logo.add_css_class("hello")
    root.append(logo)

    hello = Gtk.Label(label=t["hello"])
    hello.add_css_class("hello")
    hello.set_margin_top(8)
    root.append(hello)

    msg = Gtk.Label(label=t["msg"])
    msg.add_css_class("msg")
    msg.set_wrap(True)
    msg.set_justify(Gtk.Justification.CENTER)
    msg.set_margin_top(2)
    root.append(msg)

    board = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
    board.set_homogeneous(True)
    board.set_margin_top(14)
    root.append(board)

    info_card = _card(t["card.title"])
    installed = format_date(installed_at(release), lang)
    latest = cached_latest_release() or release.get("NLINUX_VERSION", "rolling")
    info_card.append(_info_row(t["label.name"], "NLinux"))
    info_card.append(_info_row(t["label.update"], installed))
    latest_row = _info_row(t["label.iso_latest"], latest)
    info_card.append(latest_row)
    info_card.append(_info_row(t["label.author"], AUTHOR))
    board.append(info_card)

    feat_card = _card(t["features.title"])
    for feat in t["features"]:
        feat_label = Gtk.Label(label="•  " + feat)
        feat_label.add_css_class("feature")
        feat_label.set_halign(Gtk.Align.START)
        feat_label.set_xalign(0.0)
        feat_label.set_wrap(True)
        feat_label.set_margin_top(2)
        feat_card.append(feat_label)
    board.append(feat_card)

    btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    btns.set_homogeneous(True)
    btns.set_margin_top(14)
    root.append(btns)

    def _open(url):
        try:
            webbrowser.open(url)
        except Exception:
            pass

    github_btn = _link_button(t["btn.github"], t["tip.github"],
                              github=True,
                              on_click=lambda *_: _open(REPO_URL))
    github_icon = github_btn.get_child().get_first_child()
    settings = Gtk.Settings.get_default()
    if github_icon is not None and settings is not None:
        def _sync_github_icon(*_args):
            is_dark = (
                settings.get_property("gtk-interface-color-scheme")
                == Gtk.InterfaceColorScheme.DARK
                or settings.get_property("gtk-application-prefer-dark-theme")
            )
            if is_dark:
                github_icon.add_css_class("dark")
            else:
                github_icon.remove_css_class("dark")

        _sync_github_icon()
        settings.connect(
            "notify::gtk-interface-color-scheme", _sync_github_icon)
        settings.connect(
            "notify::gtk-application-prefer-dark-theme", _sync_github_icon)
    github_btn.set_hexpand(True)
    btns.append(github_btn)

    site_btn = _link_button(t["btn.site"], t["tip.site"],
                            on_click=lambda *_: _open(SITE_URL))
    site_btn.set_hexpand(True)
    btns.append(site_btn)

    close = Gtk.Button()
    close_content = Gtk.Box(
        orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    close_content.append(Gtk.Label(label="🚀"))
    close_content.append(Gtk.Label(label=t["btn.close"]))
    close.set_child(close_content)
    close.add_css_class("primary")
    close.set_margin_top(10)
    close.set_halign(Gtk.Align.CENTER)
    close.connect("clicked", lambda *_: win.close())
    root.append(close)

    footer = Gtk.Label(label=("© NLinux   ·   " + t["footer"]))
    footer.add_css_class("footer")
    footer.set_margin_top(10)
    root.append(footer)

    # A "versão atual" vem da rede; a janela não espera por ela. Aparece já com
    # o cache (ou com a versão instalada) e é atualizada quando a resposta
    # chegar — sem travar a abertura quando não há internet.
    def _load_latest():
        tag = fetch_latest_release()
        if not tag:
            return

        def _apply():
            try:
                latest_row.value_label.set_text(tag)
            except Exception:
                pass
            return False

        GLib.idle_add(_apply)

    import threading
    threading.Thread(target=_load_latest, daemon=True).start()
    return win


def _card(title):
    from gi.repository import Gtk

    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    card.add_css_class("card")
    card.set_hexpand(True)
    title_label = Gtk.Label(label=title)
    title_label.add_css_class("card-title")
    title_label.set_halign(Gtk.Align.START)
    card.append(title_label)
    return card


def _info_row(label, value):
    from gi.repository import Gtk

    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    row.set_margin_top(3)
    left = Gtk.Label(label=label)
    left.add_css_class("info-label")
    left.set_halign(Gtk.Align.START)
    left.set_xalign(0.0)
    right = Gtk.Label(label=value)
    right.add_css_class("info-value")
    right.set_halign(Gtk.Align.END)
    right.set_xalign(1.0)
    right.set_hexpand(True)
    row.append(left)
    row.append(right)
    # Guarda o rótulo do valor para poder atualizá-lo depois (ex.: "Versão
    # atual" chega da rede após a janela já estar visível).
    row.value_label = right
    return row


def _link_button(text, tooltip, on_click, github=False):
    from gi.repository import Gtk

    btn = Gtk.Button()
    btn.add_css_class("link")
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_halign(Gtk.Align.CENTER)
    box.set_valign(Gtk.Align.CENTER)
    if github:
        try:
            img = Gtk.Image.new_from_file(
                os.path.join(APP_DIR, "github.png"))
            img.set_pixel_size(18)
            img.add_css_class("github-icon")
            box.append(img)
        except Exception:
            pass
    lbl = Gtk.Label(label=text)
    lbl.add_css_class("btn-label")
    box.append(lbl)
    btn.set_child(box)
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