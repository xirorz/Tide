"""Hyprland IPC watcher for active window changes."""
import asyncio
import os
from pathlib import Path
from typing import Callable, Optional


def _get_socket2_path() -> Optional[Path]:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    instance_sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not instance_sig:
        hypr_dir = Path(runtime) / "hypr"
        if hypr_dir.exists():
            instances = [p for p in hypr_dir.iterdir() if p.is_dir()]
            if instances:
                instance_sig = instances[0].name
    if not instance_sig:
        return None
    return Path(runtime) / "hypr" / instance_sig / ".socket2.sock"


class HyprlandWatcher:
    """Watches Hyprland IPC socket for active window change events."""

    def __init__(self, on_window_change: Callable[[str, str], None]):
        """
        Args:
            on_window_change: Called with (app_class, title) when active window changes.
        """
        self._on_change = on_window_change
        self._running = False
        self._task: Optional[asyncio.Task] = None

    async def start(self) -> None:
        self._running = True
        await self._connect_loop()

    def stop(self) -> None:
        self._running = False

    async def _connect_loop(self) -> None:
        while self._running:
            sock_path = _get_socket2_path()
            if not sock_path or not sock_path.exists():
                await asyncio.sleep(2)
                continue
            try:
                reader, _ = await asyncio.open_unix_connection(str(sock_path))
                await self._read_events(reader)
            except (ConnectionError, OSError):
                pass
            if self._running:
                await asyncio.sleep(1)

    async def _read_events(self, reader: asyncio.StreamReader) -> None:
        while self._running:
            try:
                line = await asyncio.wait_for(reader.readline(), timeout=5.0)
            except asyncio.TimeoutError:
                continue
            if not line:
                break
            event = line.decode(errors="replace").strip()
            # Events: "activewindow>>class,title" or "activewindowv2>>address"
            if event.startswith("activewindow>>"):
                payload = event[len("activewindow>>"):]
                parts = payload.split(",", 1)
                app_class = parts[0] if parts else ""
                title = parts[1] if len(parts) > 1 else ""
                if app_class:
                    self._on_change(app_class, title)
