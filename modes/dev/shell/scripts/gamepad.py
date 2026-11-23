#!/usr/bin/env python3
# Controllers for the game launcher, straight from the kernel (/dev/input, you're in
# the "input" group; Python's standard library only). Runs only while the launcher is
# open (services/Games.qml) and prints one word per press:
#   present <name> | none                 at start and when a pad comes or goes
#   up down left right                    D-pad or left stick (held: repeats)
#   ok back fav search prev next play     A, B, Y, X, LB, RB, Start
#   gamepad.py guide                      always on: prints "guide" when the Guide / Home /
#                                         PS button is pressed (held 1 s while a fullscreen
#                                         window has focus, so a game keeps it)
# Face buttons by position (the kernel reports them differently): Xbox-style pads
# (Xbox, 8BitDo, Steam Controller) send BTN_X 307 for X and BTN_Y 308 for Y;
# PlayStation pads send 307 for triangle (top) and 308 for square (left).
# Reading doesn't grab the pad: games and Steam still see it.
import glob, os, select, struct, sys, time

EV_KEY, EV_ABS = 1, 3
BUTTONS = {304: "ok", 305: "back", 308: "fav", 307: "search", 310: "prev", 311: "next", 315: "play",
           544: "up", 545: "down", 546: "left", 547: "right"}
SONY = {307: "fav", 308: "search"}       # triangle (top) and square (left)
GUIDE = 316
FMT = "llHHi"
SIZE = struct.calcsize(FMT)


def say(word):
    sys.stdout.write(word + "\n")
    sys.stdout.flush()


def bits(dev, kind):
    words = open(f"/sys/class/input/{dev}/device/capabilities/{kind}").read().split()
    n = 0
    for w in words:
        n = (n << 64) | int(w, 16)
    return n


def is_pad(dev):
    """A gamepad: the A button (BTN_SOUTH) plus a stick or D-pad axis. (Virtual input
    devices like ydotool's claim every button but have no axes.)"""
    name = open(f"/sys/class/input/{dev}/device/name").read().lower()
    if "ydotool" in name or "virtual" in name:
        return False
    return bool(bits(dev, "key") >> 304 & 1) and bool(bits(dev, "abs") & ((1 << 0) | (1 << 16)))


VENDOR = {}                              # fd -> USB vendor id


def pads():
    out = {}
    for path in glob.glob("/dev/input/event*"):
        dev = os.path.basename(path)
        try:
            if is_pad(dev):
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                out[fd] = open(f"/sys/class/input/{dev}/device/name").read().strip()
                VENDOR[fd] = open(f"/sys/class/input/{dev}/device/id/vendor").read().strip().lower()
        except OSError:
            pass
    return out


def word_for(fd, code):
    if VENDOR.get(fd) == "054c" and code in SONY:
        return SONY[code]
    return BUTTONS.get(code)


def fullscreen_focused():
    import json, subprocess
    try:
        w = json.loads(subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=2).stdout or "{}")
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return False
    return bool(w.get("fullscreen"))


def guide():
    """Only the Guide button: "guide" on a press, or after a 1 s hold over a fullscreen game."""
    devs = pads()
    down, fired, last_scan = None, False, time.time()
    while True:
        r = select.select(list(devs), [], [], 0.1)[0] if devs else (time.sleep(2) or [])
        for fd in r:
            try:
                data = os.read(fd, SIZE * 64)
            except OSError:
                os.close(fd); devs.pop(fd, None)
                continue
            for i in range(0, len(data) - SIZE + 1, SIZE):
                _, _, typ, code, val = struct.unpack(FMT, data[i:i + SIZE])
                if typ == EV_KEY and code == GUIDE:
                    if val == 1:
                        down, fired = time.time(), False
                        if not fullscreen_focused():
                            say("guide"); fired = True
                    elif val == 0:
                        down = None
        if down and not fired and time.time() - down >= 1.0:
            say("guide"); fired = True
        if time.time() - last_scan > 3:
            last_scan = time.time()
            known = set(devs.values())
            for fd, name in pads().items():
                if name in known:
                    os.close(fd)
                else:
                    devs[fd] = name


def main():
    devs = pads()
    say("present " + next(iter(devs.values())) if devs else "none")
    stick = {0: 0, 1: 0}                 # ABS_X, ABS_Y: -1, 0, 1
    held, next_repeat = None, 0.0
    last_scan = time.time()
    while True:
        timeout = 0.05 if held else 1.0
        r = select.select(list(devs), [], [], timeout)[0] if devs else (time.sleep(1) or [])
        for fd in r:
            try:
                data = os.read(fd, SIZE * 64)
            except OSError:
                os.close(fd)
                devs.pop(fd, None)
                say("present " + next(iter(devs.values())) if devs else "none")
                continue
            for i in range(0, len(data) - SIZE + 1, SIZE):
                _, _, typ, code, val = struct.unpack(FMT, data[i:i + SIZE])
                if typ == EV_KEY and word_for(fd, code):
                    word = word_for(fd, code)
                    if val == 1:
                        say(word)
                        if word in ("up", "down", "left", "right"):
                            held, next_repeat = word, time.time() + 0.4
                    elif val == 0 and held == word:
                        held = None
                elif typ == EV_ABS and code in (16, 17):          # D-pad as a hat
                    word = {(16, -1): "left", (16, 1): "right", (17, -1): "up", (17, 1): "down"}.get((code, val))
                    if word:
                        say(word)
                        held, next_repeat = word, time.time() + 0.4
                    else:
                        held = None
                elif typ == EV_ABS and code in (0, 1):            # left stick, past halfway
                    pos = -1 if val < -16000 else 1 if val > 16000 else 0
                    if pos != stick[code]:
                        stick[code] = pos
                        if pos:
                            word = ("left", "right")[pos > 0] if code == 0 else ("up", "down")[pos > 0]
                            say(word)
                            held, next_repeat = word, time.time() + 0.4
                        else:
                            held = None
        if held and time.time() >= next_repeat:
            say(held)
            next_repeat = time.time() + 0.15
        # a pad plugged in later
        if time.time() - last_scan > 3:
            last_scan = time.time()
            known = set(devs.values())
            for fd, name in pads().items():
                if name in known:
                    os.close(fd)
                else:
                    devs[fd] = name
                    say("present " + name)


if __name__ == "__main__":
    try:
        guide() if sys.argv[1:] == ["guide"] else main()
    except KeyboardInterrupt:
        pass
