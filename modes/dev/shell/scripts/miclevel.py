#!/usr/bin/env python3
"""Print the default mic's level as 5 values (0..1) for the 5 bars, 20 times a second.
Used by services/Voice.qml for the voice pill's level bars; it reads its own
small capture stream (parec) and never touches the recording itself."""
import array
import math
import subprocess
import sys

RATE = 16000
CHUNK = RATE // 20  # 50ms of mono s16
p = subprocess.Popen(["parec", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=1",
                      "--latency-msec=50"], stdout=subprocess.PIPE)
try:
    while True:
        data = p.stdout.read(CHUNK * 2)
        if not data:
            break
        a = array.array("h", data[: len(data) // 2 * 2])
        # 5 slices of the last 50ms, one per bar; speech sits around 0.02-0.2 RMS
        n = max(1, len(a) // 5)
        out = []
        for i in range(5):
            part = a[i * n:(i + 1) * n] or a
            rms = math.sqrt(sum(x * x for x in part) / len(part)) / 32768
            out.append(f"{min(1.0, rms * 6):.3f}")
        print(",".join(out), flush=True)
except (BrokenPipeError, KeyboardInterrupt):
    pass
finally:
    p.terminate()
