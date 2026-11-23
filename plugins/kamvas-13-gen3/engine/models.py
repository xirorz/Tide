"""Data models for autswitch profiles."""
from dataclasses import dataclass, field
from typing import Optional

from dial_actions import sanitize_modes


def _auto_huion_dial_bindings(dial_id: str) -> tuple[str, str, str]:
    return (
        f"VENDORDIAL:{dial_id}:press",
        f"VENDORDIAL:{dial_id}:ccw",
        f"VENDORDIAL:{dial_id}:cw",
    )


def _normalize_loaded_dial(dial_id: str, dial: "DialConfig") -> "DialConfig":
    if dial_id not in {"0", "8"}:
        return dial

    expected_switch, expected_ccw, expected_cw = _auto_huion_dial_bindings(dial_id)
    if (
        dial.switch_key == expected_switch
        and dial.ccw_key == expected_ccw
        and dial.cw_key == expected_cw
    ):
        return dial

    return DialConfig(
        label=dial.label,
        switch_key=expected_switch,
        ccw_key=expected_ccw,
        cw_key=expected_cw,
        modes=sanitize_modes(dial.modes),
    )


@dataclass
class ButtonAction:
    """Action assigned to a tablet express key."""
    keys: str           # Key combo, e.g. "ctrl+z", "f5", "ctrl+shift+alt+r"
    label: str          # Human-readable label, e.g. "Undo"
    passthrough: bool = False  # If True, send original keycode unchanged
    # Pen / tablet express keys: optional second binding — double-tap (press, release, press) then hold uses keys_double.
    keys_double: str = ""
    label_double: str = ""


@dataclass
class DialConfig:
    """Per-app dial configuration."""
    label: str = ""
    switch_key: str = ""
    ccw_key: str = ""
    cw_key: str = ""
    modes: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "label": self.label,
            "switch_key": self.switch_key,
            "ccw_key": self.ccw_key,
            "cw_key": self.cw_key,
            "modes": [dict(mode) for mode in sanitize_modes(self.modes)],
        }

    @classmethod
    def from_dict(cls, data: dict) -> "DialConfig":
        return cls(
            label=data.get("label", ""),
            switch_key=data.get("switch_key", ""),
            ccw_key=data.get("ccw_key", ""),
            cw_key=data.get("cw_key", ""),
            modes=sanitize_modes(data.get("modes", [])),
        )


@dataclass
class Profile:
    """Profile for a specific application."""
    app_class: str
    app_name: str
    # Freedesktop Icon= name or path; resolved via .desktop StartupWMClass match + QIcon.fromTheme
    icon: str = ""
    # slot_id (int) -> keycode string — which physical key is at each slot
    slots: dict = field(default_factory=dict)
    # keycode -> ButtonAction — what that key does in this profile
    buttons: dict = field(default_factory=dict)
    # dial_id (str) -> DialConfig
    dials: dict = field(default_factory=dict)

    def set_slot(self, slot_id: int, keycode: str, action: "ButtonAction") -> None:
        """Assign a keycode + action to a slot, clearing any previous assignment."""
        # Remove old keycode at this slot
        old_kc = self.slots.get(slot_id)
        if old_kc and old_kc in self.buttons:
            del self.buttons[old_kc]

        # Keep the physical keycode unique across slots.
        for existing_slot, existing_kc in list(self.slots.items()):
            if existing_slot != slot_id and existing_kc == keycode:
                del self.slots[existing_slot]

        for dial_id, dial in list(self.dials.items()):
            if keycode not in {dial.switch_key, dial.ccw_key, dial.cw_key}:
                continue
            self.dials[dial_id] = DialConfig(
                label=dial.label,
                switch_key="" if dial.switch_key == keycode else dial.switch_key,
                ccw_key="" if dial.ccw_key == keycode else dial.ccw_key,
                cw_key="" if dial.cw_key == keycode else dial.cw_key,
                modes=sanitize_modes(dial.modes),
            )

        self.slots[slot_id] = keycode
        self.buttons[keycode] = action

    def clear_slot(self, slot_id: int) -> None:
        kc = self.slots.pop(slot_id, None)
        if kc and kc in self.buttons:
            del self.buttons[kc]

    def get_slot(self, slot_id: int) -> "tuple[str, ButtonAction | None]":
        kc = self.slots.get(slot_id, "")
        return kc, self.buttons.get(kc)

    def set_dial(self, dial_id: str, dial: "DialConfig") -> None:
        """Assign a dial config, clearing conflicting button or dial bindings."""
        dial = DialConfig(
            label=dial.label,
            switch_key=dial.switch_key,
            ccw_key=dial.ccw_key,
            cw_key=dial.cw_key,
            modes=sanitize_modes(dial.modes),
        )
        dial_keys = {k for k in (dial.switch_key, dial.ccw_key, dial.cw_key) if k}
        if not dial_keys:
            self.dials.pop(dial_id, None)
            return

        for slot_id, keycode in list(self.slots.items()):
            if keycode in dial_keys:
                self.clear_slot(slot_id)

        for other_id, other in list(self.dials.items()):
            if other_id == dial_id:
                continue
            other_keys = {k for k in (other.switch_key, other.ccw_key, other.cw_key) if k}
            shared_switch = (
                dial.switch_key
                and other.switch_key
                and dial.switch_key == other.switch_key
            )
            actual_conflicts = (other_keys & dial_keys) - ({dial.switch_key} if shared_switch else set())
            if actual_conflicts:
                self.dials[other_id] = DialConfig(
                    label=other.label,
                    switch_key="" if other.switch_key in actual_conflicts else other.switch_key,
                    ccw_key="" if other.ccw_key in actual_conflicts else other.ccw_key,
                    cw_key="" if other.cw_key in actual_conflicts else other.cw_key,
                    modes=sanitize_modes(other.modes),
                )

        self.dials[dial_id] = dial

    def clear_dial(self, dial_id: str) -> None:
        self.dials.pop(dial_id, None)

    def to_dict(self) -> dict:
        return {
            "app_class": self.app_class,
            "app_name":  self.app_name,
            "icon": self.icon,
            "slots":     {str(k): v for k, v in self.slots.items()},
            "buttons": {
                k: (
                    {"keys": v.keys, "label": v.label, "passthrough": v.passthrough}
                    | (
                        {"keys_double": v.keys_double, "label_double": v.label_double}
                        if (v.keys_double or v.label_double)
                        else {}
                    )
                )
                for k, v in self.buttons.items()
            },
            "dials": {
                k: v.to_dict()
                for k, v in self.dials.items()
            },
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Profile":
        buttons = {
            k: ButtonAction(
                keys=v.get("keys", ""),
                label=v.get("label", ""),
                passthrough=v.get("passthrough", False),
                keys_double=v.get("keys_double", ""),
                label_double=v.get("label_double", ""),
            )
            for k, v in data.get("buttons", {}).items()
        }
        dials = {
            k: _normalize_loaded_dial(k, DialConfig.from_dict(v))
            for k, v in data.get("dials", {}).items()
        }
        # Migrate old format (no slots key) — assign buttons sequentially
        raw_slots = data.get("slots", {})
        if raw_slots:
            slots = {int(k): v for k, v in raw_slots.items()}
        else:
            slots = {i: kc for i, kc in enumerate(buttons)}
        return cls(
            app_class=data["app_class"],
            app_name=data["app_name"],
            icon=data.get("icon", ""),
            slots=slots,
            buttons=buttons,
            dials=dials,
        )


@dataclass
class AppConfig:
    """Top-level application configuration."""
    profiles: dict = field(default_factory=dict)  # app_class -> Profile
    default_profile: Optional[str] = None
    enabled: bool = True

    def to_dict(self) -> dict:
        return {
            "profiles": {k: v.to_dict() for k, v in self.profiles.items()},
            "default_profile": self.default_profile,
            "enabled": self.enabled,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "AppConfig":
        profiles = {
            k: Profile.from_dict(v)
            for k, v in data.get("profiles", {}).items()
        }
        return cls(
            profiles=profiles,
            default_profile=data.get("default_profile"),
            enabled=data.get("enabled", True),
        )
