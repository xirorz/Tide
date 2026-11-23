#!/usr/bin/env python3
# Sound for the kid space (park mode). Voice lines are spoken once by Breeze TTS (Eve's
# voice server, 127.0.0.1:8180) and kept as files, so they play instantly and Breeze is
# left to Eve the rest of the time; effects (pop, ding, chime) are made here. Everything
# plays as the app "Tide Park", the one sound tide-park doesn't mute while parked.
#   park-sound.py say <key>      a voice line (made first if it isn't yet)
#   park-sound.py fx <name>      pop | ding | chime | boop
#   park-sound.py prepare [--again]   make every voice line that's missing (or all again)
import json, math, os, struct, subprocess, sys, urllib.request, uuid, wave
from pathlib import Path

CACHE = Path.home() / ".cache/tide/park-sound"
TTS = "http://127.0.0.1:8180/v1/audio/speech"
# the voice your system already speaks with: Eve's (eve/speech.py), same settings, so
# he hears the same voice everywhere
VOICE = "eve-42"
SETTINGS = {"seed": "7", "temperature": "0.3", "top_k": "20", "depth_temperature": "0.3", "depth_top_k": "10", "split_chars": "0"}
RATE = 24000
LINES = {
    "hello": "Hi! Let's play!",
    "pop": "Pop the bubbles!",
    "letters": "Press the letter you see!",
    "great": "Great job!",
    "wow": "Wow, you did it!",
    "more": "Let's do more!",
    "timesup": "Time to rest now. You played so well today!",
    "home": "Press the house to go back.",
}
for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    LINES["letter-" + c.lower()] = c + "."


def play(path):
    subprocess.Popen(["pw-play", "-P", '{ application.name = "Tide Park" }', str(path)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def save(path, frames):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    tmp.replace(path)


def speak(key):
    """Ask Breeze for one line; False when it isn't there or is busy (Eve speaking)."""
    text = LINES.get(key)
    if not text:
        return False
    b = "----tide" + uuid.uuid4().hex
    body = b"".join(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
                    for k, v in [("text", text), ("voice_id", VOICE)] + list(SETTINGS.items())) + f"--{b}--\r\n".encode()
    req = urllib.request.Request(TTS, data=body, headers={"Content-Type": "multipart/form-data; boundary=" + b})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            if not r.headers.get("X-Sample-Format", "").startswith("s16"):
                return False
            pcm = r.read()
    except (OSError, ValueError):
        return False
    if len(pcm) < RATE // 5:
        return False
    save(CACHE / f"{key}.wav", pcm)
    return True


def tone(parts):
    """parts: [(start Hz, end Hz, seconds, volume)] one after another, soft edges."""
    out = bytearray()
    for f0, f1, sec, vol in parts:
        n = int(RATE * sec)
        ph = 0.0
        for i in range(n):
            t = i / n
            f = f0 + (f1 - f0) * t
            ph += 2 * math.pi * f / RATE
            env = min(1.0, i / (RATE * 0.005)) * (1 - t) ** 2
            out += struct.pack("<h", int(32767 * vol * env * math.sin(ph)))
    return bytes(out)


FX = {
    "pop": [(900, 180, 0.09, 0.6)],
    "ding": [(1320, 1320, 0.25, 0.35)],
    "chime": [(880, 880, 0.35, 0.3), (1100, 1100, 0.35, 0.3), (1320, 1320, 0.6, 0.3)],
    "boop": [(300, 220, 0.15, 0.4)],
}


def main(a):
    if len(a) >= 2 and a[0] == "say":
        f = CACHE / f"{a[1]}.wav"
        if f.is_file() or speak(a[1]):
            play(f)
        return 0
    if len(a) >= 2 and a[0] == "fx" and a[1] in FX:
        f = CACHE / f"fx-{a[1]}.wav"
        if not f.is_file():
            save(f, tone(FX[a[1]]))
        play(f)
        return 0
    if a[:1] == ["prepare"]:
        # --again: make every line again (after the voice changed)
        for k in LINES:
            if "--again" in a or not (CACHE / f"{k}.wav").is_file():
                speak(k)
        for k in FX:
            if not (CACHE / f"fx-{k}.wav").is_file():
                save(CACHE / f"fx-{k}.wav", tone(FX[k]))
        print(json.dumps({"lines": sum((CACHE / f"{k}.wav").is_file() for k in LINES), "of": len(LINES)}))
        return 0
    print(__doc__ or "park-sound.py say <key> | fx <name> | prepare", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
