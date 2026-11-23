"""Background daemon: ties together the Hyprland watcher and tablet remapper."""
import asyncio
import threading
from typing import Callable, Optional

from models import AppConfig, Profile
from profiles import load_config, save_config
from tablet import TabletRemapper
from watcher import HyprlandWatcher


class Daemon:
    """Orchestrates window watching and tablet remapping."""

    def __init__(self, on_profile_change: Optional[Callable[[str, Optional[str]], None]] = None):
        """
        Args:
            on_profile_change: Called with (app_class, profile_name_or_None) when profile switches.
        """
        self._config: AppConfig = load_config()
        self._active_class: str = ""
        self._on_change = on_profile_change or (lambda *_: None)

        self._watcher = HyprlandWatcher(on_window_change=self._on_window_change)
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread: Optional[threading.Thread] = None
        self._watch_task: Optional[asyncio.Task] = None
        self._status_cb: Optional[Callable[[str], None]] = None
        self._dial_popup_cb: Optional[Callable[[dict], None]] = None

        self._remapper = TabletRemapper(
            get_active_profile=self._get_active_profile,
            on_status_change=self._on_tablet_status,
            on_dial_popup=self._on_dial_popup,
        )

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._remapper.start()
        self._thread = threading.Thread(target=self._run_loop, daemon=True, name="daemon-loop")
        self._thread.start()

    def stop(self) -> None:
        self._remapper.stop()
        self._watcher.stop()
        loop = self._loop
        if loop and loop.is_running():
            loop.call_soon_threadsafe(self._request_loop_stop)
        if self._thread and self._thread.is_alive() and threading.current_thread() is not self._thread:
            self._thread.join(timeout=2)
        self._thread = None

    def reload_config(self) -> None:
        self._config = load_config()

    def save(self) -> None:
        save_config(self._config)

    @property
    def config(self) -> AppConfig:
        return self._config

    def set_status_callback(self, cb: Callable[[str], None]) -> None:
        self._status_cb = cb

    def set_dial_popup_callback(self, cb: Callable[[dict], None]) -> None:
        self._dial_popup_cb = cb

    def set_capture_mode(self, callback) -> None:
        self._remapper.set_capture_mode(callback)

    def set_dial_mode_selection(self, app_class: str, dial_id: str, selected_index: int) -> None:
        self._remapper.set_dial_mode_selection(app_class, dial_id, selected_index)

    @property
    def active_class(self) -> str:
        return self._active_class

    # ----------------------------------------------------------------- private

    def _run_loop(self) -> None:
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        self._watch_task = loop.create_task(self._watcher.start())
        try:
            loop.run_forever()
        finally:
            self._watcher.stop()
            pending = [task for task in asyncio.all_tasks(loop) if not task.done()]
            for task in pending:
                task.cancel()
            if pending:
                loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.run_until_complete(loop.shutdown_asyncgens())
            if hasattr(loop, "shutdown_default_executor"):
                loop.run_until_complete(loop.shutdown_default_executor())
            asyncio.set_event_loop(None)
            loop.close()
            self._watch_task = None
            self._loop = None

    def _request_loop_stop(self) -> None:
        if self._watch_task is not None and not self._watch_task.done():
            self._watch_task.cancel()
        if self._loop is not None and self._loop.is_running():
            self._loop.stop()

    def _get_active_profile(self) -> Optional[Profile]:
        if not self._config.enabled:
            return None
        profile = self._config.profiles.get(self._active_class)
        if profile:
            return profile
        if self._config.default_profile:
            return self._config.profiles.get(self._config.default_profile)
        return None

    def _on_window_change(self, app_class: str, title: str) -> None:
        self._active_class = app_class
        profile = self._get_active_profile()
        self._on_change(app_class, profile.app_name if profile else None)
        if self._status_cb:
            if profile:
                self._status_cb(f"Profile: {profile.app_name}  [{app_class}]")
            else:
                self._status_cb(f"No profile for [{app_class}]")

    def _on_tablet_status(self, msg: str) -> None:
        if self._status_cb:
            self._status_cb(msg)

    def _on_dial_popup(self, payload: dict) -> None:
        if self._dial_popup_cb:
            self._dial_popup_cb(payload)
