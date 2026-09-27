import sys

from nlinux.web_server import sync_package_databases


def _pick_runner():
    try:
        from nlinux.native_window import run_window

        return run_window
    except Exception as e:  # no introspection/Gtk available
        print(f"Janela nativa indisponível ({e}); tentando pywebview.")
    try:
        from nlinux.webview_launcher import run_webview

        return run_webview
    except Exception as e:
        print(f"pywebview indisponível ({e}).")
        from nlinux.web_server import run

        return lambda: run(open_browser=False)


def _show_sync_error(message: str) -> None:
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except (ImportError, ValueError) as exc:
        print(
            f"Não foi possível abrir a loja: {message}\n(GTK indisponível: {exc})",
            file=sys.stderr,
        )
        return

    dialog = Gtk.MessageDialog(
        None,
        Gtk.DialogFlags.MODAL,
        Gtk.MessageType.ERROR,
        Gtk.ButtonsType.CLOSE,
        "Não foi possível atualizar os bancos do pacman.",
    )
    dialog.format_secondary_text(message)
    dialog.run()
    dialog.destroy()


if "__main__" == __name__:
    try:
        sync_package_databases()
    except RuntimeError as exc:
        _show_sync_error(str(exc))
        raise SystemExit(1) from exc
    _pick_runner()()