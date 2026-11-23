"""Profile storage and management."""
import json
from pathlib import Path

from models import AppConfig

# Tide's copy: the profiles live next to this plugin (one folder up from engine/),
# so nothing depends on the original autswitch project or its config.
CONFIG_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = CONFIG_DIR / "profiles.json"


def load_config() -> AppConfig:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        return AppConfig()
    try:
        with open(CONFIG_FILE) as f:
            data = json.load(f)
        return AppConfig.from_dict(data)
    except (json.JSONDecodeError, KeyError, TypeError):
        return AppConfig()


def save_config(config: AppConfig) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(config.to_dict(), f, indent=2)
