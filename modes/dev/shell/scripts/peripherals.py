#!/usr/bin/env python3
# Wireless device batteries straight from the kernel (/sys/class/power_supply, scope
# Device), every 2 seconds, printing one JSON line only when something changes.
# UPower reads the same files but only on its own slow poll, so a headset that was
# just switched on took about a minute to show up in the bar.
import json, os, re, subprocess, sys, time

ROOT = "/sys/class/power_supply"


def read(path, name):
    try:
        with open(os.path.join(path, name)) as f:
            return f.read().strip()
    except OSError:
        return ""


def kind(dev, model):
    s = (dev + " " + model).lower()
    if re.search(r"headset|headphone|void|arctis|cloud|buds|earbuds|nova|barracuda", s):
        return "headset"
    if re.search(r"mouse|hidpp|g502|g pro|deathadder|viper|basilisk|mx master", s):
        return "mouse"
    if re.search(r"controller|gamepad|dualsense|dualshock|xbox|joy-?con|8bitdo|ps-controller|sony", s):
        return "controller"
    if re.search(r"keyboard|kbd", s):
        return "keyboard"
    if re.search(r"phone", s):
        return "phone"
    return ""


# Charging. Some headsets (Corsair Void) don't report their level while they charge:
# they say 100% the moment they're plugged in, or keep the level they had when the
# cable went in. While a device charges and its number doesn't climb believably, its
# level is estimated from when charging started, its last level on battery and how fast
# it charges (learned from its own past charges; 30% an hour until then), marked
# "estimated" and never past 99% until the device says it's full. When it's charged
# (it says so, or the estimate gets there) a notification says so.
# Kept across restarts in ~/.cache/tide/peripherals.json.
KEEP = os.path.expanduser("~/.cache/tide/peripherals.json")
DEFAULT_RATE = 30.0          # percent an hour
try:
    with open(KEEP) as f:
        state = json.load(f)
except (OSError, ValueError):
    state = {}
if "levels" not in state:     # the first version kept only the levels
    state = {"levels": {k: v for k, v in state.items() if isinstance(v, int)}}
levels = state["levels"]                      # last level on battery
charges = state.setdefault("charges", {})     # charging now: start time, start level, reported then
rates = state.setdefault("rates", {})         # learned percent per hour


def keep():
    try:
        os.makedirs(os.path.dirname(KEEP), exist_ok=True)
        with open(KEEP, "w") as f:
            json.dump(state, f)
    except OSError:
        pass


NAMES = {"headset": "Headset", "mouse": "Mouse", "controller": "Controller", "keyboard": "Keyboard", "phone": "Phone"}


def notify(k, text):
    try:
        subprocess.Popen(["notify-send", "-a", "Tide", "-i", "battery-full-charged", NAMES.get(k, "Device") + " charged", text],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def charging_level(dev, k, reported, full):
    """(percent, estimated) for a device on its charger."""
    now = time.time()
    c = charges.get(dev)
    if c is None:
        start = levels.get(dev, reported if reported < 100 else None)
        c = charges[dev] = {"t": now, "start": start, "reported": reported, "told": False}
        keep()
    hours = (now - c["t"]) / 3600
    start = c["start"]
    # the device's own number, if it climbs like a battery charging (not 4 -> 100 in a minute)
    climbing = reported != c["reported"] and reported < 100 and start is not None \
        and reported > start and (reported - start) <= 2 + hours * 120
    if full:
        pct, est = 100, False
    elif climbing or start is None:
        pct, est = reported, start is None and reported == 100
    else:
        pct = min(99, int(start + hours * rates.get(dev, DEFAULT_RATE)))
        est = True
    if not c["told"] and (full or pct >= 99 and est or pct >= 100):
        c["told"] = True
        keep()
        notify(k, "Fully charged." if full or not est else "Should be fully charged by now.")
    return pct, est


def unplugged(dev, reading):
    """Off the charger: learn how fast it charged from where it got to."""
    c = charges.pop(dev, None)
    if c is None:
        return
    hours = (time.time() - c["t"]) / 3600
    if c["start"] is not None and hours > 0.25 and reading > c["start"] + 5:
        rate = (reading - c["start"]) / hours
        old = rates.get(dev)
        rates[dev] = round(rate if old is None else (old + rate) / 2, 1)
    keep()


last = None
seen_full = set()
while True:
    out = []
    try:
        names = sorted(os.listdir(ROOT))
    except OSError:
        names = []
    for dev in names:
        p = os.path.join(ROOT, dev)
        if read(p, "scope") != "Device" or read(p, "type") != "Battery":
            continue
        if read(p, "present") == "0":
            continue
        cap = read(p, "capacity")
        if not cap.isdigit():
            continue
        model = read(p, "model_name")
        k = kind(dev, model)
        if not k:
            continue
        status = read(p, "status")
        reported = int(cap)
        charging = status == "Charging"
        full = status == "Full"
        if charging or (full and dev in charges):
            if full and dev not in seen_full:
                seen_full.add(dev)
                c = charges.get(dev)
                if c and c["start"] is not None:
                    hours = (time.time() - c["t"]) / 3600
                    if hours > 0.25:
                        rates[dev] = round((100 - c["start"]) / hours, 1)
            pct, estimated = charging_level(dev, k, reported, full)
        else:
            seen_full.discard(dev)
            unplugged(dev, reported)
            pct, estimated = reported, False
            if not full and levels.get(dev) != pct:
                levels[dev] = pct
                keep()
        out.append({"id": dev, "kind": k, "model": model, "percent": pct,
                    "charging": charging or full and dev in charges, "full": pct >= 100 and (charging or full),
                    "estimated": estimated})
    line = json.dumps(out)
    if line != last:
        print(line, flush=True)
        last = line
    time.sleep(2)
