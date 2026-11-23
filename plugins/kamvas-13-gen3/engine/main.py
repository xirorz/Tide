#!/usr/bin/env python3
"""autswitch – Huion Kamvas tablet profile auto-switcher.

Detects the active Hyprland window and switches tablet button mappings accordingly.

Tide's copy. `main.py --daemon` runs only the remapper, with no window, and reloads
profiles.json whenever it changes (Tide starts it while the tablet is connected).
Without --daemon it is the original window app.
"""
import sys
import os

# imports resolve from this folder even when run with python3 -I
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Ensure PyQt6 platform plugins are found
os.environ.setdefault("QT_QPA_PLATFORM", "wayland")

from daemon import Daemon


def run_headless() -> None:
    """The remapper with no window: reload profiles.json on change, stop on SIGTERM."""
    import signal
    import threading
    from profiles import CONFIG_FILE

    # exit with whoever started us (Tide's shell), so a shell restart never leaves an
    # old daemon behind; and only one daemon at a time (both would grab the tablet)
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except Exception:
        pass
    import fcntl
    lock_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "tide-kamvas-daemon.lock")
    lock = open(lock_path, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("another Kamvas daemon is already running", flush=True)
        return

    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())

    def mtime() -> float:
        try:
            return CONFIG_FILE.stat().st_mtime
        except OSError:
            return 0.0

    daemon = Daemon(on_profile_change=lambda cls, name: print(f"window {cls}: {name or 'no profile'}", flush=True))
    daemon.set_status_callback(lambda msg: print(msg, flush=True))
    daemon.start()
    print(f"daemon running, profiles: {CONFIG_FILE}", flush=True)
    seen = mtime()
    while not stop.wait(1.0):
        now = mtime()
        if now != seen:
            seen = now
            daemon.reload_config()
            print("profiles reloaded", flush=True)
    # the remapper's threads can block on the device; give a clean stop 3 seconds,
    # then leave anyway (the kernel releases the tablet grab when we exit)
    stopper = threading.Thread(target=daemon.stop, daemon=True)
    stopper.start()
    stopper.join(3)
    print("daemon stopped", flush=True)
    os._exit(0)


def main() -> None:
    if "--daemon" in sys.argv:
        run_headless()
        return
    from PyQt6.QtWidgets import QApplication
    from gui.main_window import MainWindow

    app = QApplication(sys.argv)
    app.setApplicationName("autoswitch")
    app.setApplicationDisplayName("autoswitch")
    app.setQuitOnLastWindowClosed(False)

    # Dark palette
    app.setStyle("Fusion")
    _apply_dark_palette(app)

    daemon = Daemon()
    daemon.start()

    window = MainWindow(daemon)
    window.show()

    exit_code = app.exec()
    daemon.stop()
    sys.exit(exit_code)


def _apply_dark_palette(app: "QApplication") -> None:
    from PyQt6.QtGui import QPalette, QColor
    from gui import theme
    palette = QPalette()
    c = {
        "window":        theme.BG,
        "windowText":    theme.TEXT,
        "base":          theme.SURFACE,
        "alternateBase": theme.SURFACE_HOVER,
        "text":          theme.TEXT,
        "button":        theme.SURFACE_HOVER,
        "buttonText":    theme.TEXT,
        "highlight":     theme.ACCENT_DIM,
        "highlightText": theme.TEXT,
        "link":          theme.ACCENT,
        "dark":          theme.BG,
        "mid":           theme.BORDER,
        "shadow":        theme.BG,
        "light":         theme.BORDER,
    }
    mapping = {
        QPalette.ColorRole.Window:          c["window"],
        QPalette.ColorRole.WindowText:      c["windowText"],
        QPalette.ColorRole.Base:            c["base"],
        QPalette.ColorRole.AlternateBase:   c["alternateBase"],
        QPalette.ColorRole.Text:            c["text"],
        QPalette.ColorRole.Button:          c["button"],
        QPalette.ColorRole.ButtonText:      c["buttonText"],
        QPalette.ColorRole.Highlight:       c["highlight"],
        QPalette.ColorRole.HighlightedText: c["highlightText"],
        QPalette.ColorRole.Link:            c["link"],
        QPalette.ColorRole.Dark:            c["dark"],
        QPalette.ColorRole.Mid:             c["mid"],
        QPalette.ColorRole.Shadow:          c["shadow"],
        QPalette.ColorRole.Light:           c["light"],
    }
    for role, color in mapping.items():
        palette.setColor(role, QColor(color))
    app.setPalette(palette)


if __name__ == "__main__":
    main()
