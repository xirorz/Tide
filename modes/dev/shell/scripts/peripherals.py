#!/usr/bin/env python3
# Wireless device batteries straight from the kernel (/sys/class/power_supply, scope
# Device), every 2 seconds, printing one JSON line only when something changes.
# UPower reads the same files but only on its own slow poll, so a headset that was
# just switched on took about a minute to show up in the bar.
import json, os, re, sys, time

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


last = None
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
        out.append({"id": dev, "kind": k, "model": model, "percent": int(cap),
                    "charging": read(p, "status") == "Charging"})
    line = json.dumps(out)
    if line != last:
        print(line, flush=True)
        last = line
    time.sleep(2)
