#!/usr/bin/env python3
"""Live numbers for the resource center, one JSON line per second.

GPU: the card with the most VRAM (amdgpu via sysfs, else nvidia-smi), with VRAM per
process from the amdgpu driver's fdinfo. CPU, memory, the root disk, the default
network interface, uptime, and the processes worth listing.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
UID = os.getuid()
# never offered "End": ending these breaks the session, the shell, audio or login
PROTECTED = {
    "Hyprland", "Xwayland", "qs", "quickshell", "uwsm", "systemd", "dbus-daemon",
    "dbus-broker", "dbus-broker-lau", "pipewire", "pipewire-pulse", "wireplumber",
    "xdg-desktop-por", "xdg-document-po", "xdg-permission-", "gnome-keyring-d",
    "hyprpolkitagent", "hypridle", "hyprlock", "awww-daemon", "sddm", "login",
    "kwalletd6", "at-spi-bus-laun", "at-spi2-registr", "start-hyprland",
}


# the session's own family by name (Hyprland, uwsm, the portals, audio…): never End
CRITICAL = re.compile(r"hypr|uwsm|sddm|systemd|dbus|pipewire|wireplumber|portal|polkit|keyring|xwayland|login|seatd|greetd", re.I)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def cpu_times():
    f = read("/proc/stat").split("\n")[0].split()[1:]
    v = list(map(int, f[:8]))
    return sum(v), v[3] + v[4]


def cpu_temp():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if read(h + "/name").strip() in ("k10temp", "coretemp", "zenpower"):
            t = read(h + "/temp1_input").strip()
            if t:
                return int(t) // 1000
    return -1


def cpu_freq():
    fs = [int(read(p).strip() or 0) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    return max(fs) / 1e6 if fs else 0


def amd_gpu_at(d):
    tot = read(d + "/mem_info_vram_total").strip()
    if not tot:
        return None
    hw = (glob.glob(d + "/hwmon/hwmon*") or [""])[0]
    temp = read(hw + "/temp1_input").strip()
    power = read(hw + "/power1_average").strip() or read(hw + "/power1_input").strip()
    pci = os.path.basename(os.path.realpath(d))
    return {
        "name": gpu_name(pci),
        "busy": int(read(d + "/gpu_busy_percent").strip() or 0),
        "vramUsed": int(read(d + "/mem_info_vram_used").strip() or 0),
        "vramTotal": int(tot),
        "temp": int(temp) // 1000 if temp else -1,
        "power": round(int(power) / 1e6) if power else -1,
        "pci": pci,
    }


def nvidia_gpu():
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2).stdout
        b, u, t, temp, p = [x.strip() for x in out.split("\n")[0].split(",")]
        return {"busy": int(b), "vramUsed": int(u) * 1048576, "vramTotal": int(t) * 1048576,
                "temp": int(temp), "power": round(float(p)), "pci": ""}
    except Exception:
        return None


_names = {}


def gpu_name(pci):
    """A short, readable name: the board's own name when lspci has it."""
    if pci in _names:
        return _names[pci]
    _names[pci] = _gpu_name(pci)
    return _names[pci]


def _gpu_name(pci):
    try:
        f = re.findall(r'"([^"]*)"', subprocess.run(["lspci", "-mm", "-s", pci], capture_output=True, text=True, timeout=2).stdout)
        # f = [class, vendor, device, subsystem vendor, subsystem device]
        if len(f) >= 5 and f[4]:
            return f[4]
        if len(f) >= 3:
            m = re.search(r"\[(.+?)\]", f[2])
            return m.group(1).split("/")[0] if m else f[2]
    except Exception:
        pass
    return "GPU"


def all_gpus():
    """Every GPU: amdgpu cards from sysfs, NVIDIA ones from nvidia-smi. Biggest VRAM first."""
    gpus = []
    for d in glob.glob("/sys/class/drm/card*/device"):
        if not read(d + "/mem_info_vram_total").strip() or re.search(r"card\d+-", d):
            continue
        g = amd_gpu_at(d)
        if g:
            gpus.append(g)
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,pci.bus_id",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2).stdout
        for line in out.strip().split("\n"):
            f = [x.strip() for x in line.split(",")]
            if len(f) < 7:
                continue
            gpus.append({"name": f[0].replace("NVIDIA ", "").replace("GeForce ", ""), "busy": int(float(f[1])),
                         "vramUsed": int(float(f[2])) * 1048576, "vramTotal": int(float(f[3])) * 1048576,
                         "temp": int(float(f[4])), "power": round(float(f[5])) if f[5] not in ("[N/A]", "") else -1,
                         "pci": nv_bus(f[6]), "nvidia": True})
    except Exception:
        pass
    gpus.sort(key=lambda g: g["vramTotal"], reverse=True)
    return gpus


def nv_bus(b):
    # "00000000:0F:00.0" -> "0000:0f:00.0", the same form as amdgpu's
    return b[-12:].lower()


def nvidia_procs():
    """VRAM per process on NVIDIA cards (compute apps)."""
    out = {}
    try:
        r = subprocess.run(["nvidia-smi", "--query-compute-apps=pid,used_memory,gpu_bus_id", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=2).stdout
        for line in r.strip().split("\n"):
            f = [x.strip() for x in line.split(",")]
            if len(f) == 3 and f[0].isdigit():
                per = out.setdefault(int(f[0]), {})
                bus = nv_bus(f[2])
                per[bus] = per.get(bus, 0) + int(float(f[1])) * 1048576
    except Exception:
        pass
    return out


def root_disk():
    src = subprocess.run(["findmnt", "-no", "SOURCE", "/"], capture_output=True, text=True).stdout.strip()
    src = re.sub(r"\[.*\]$", "", src)
    dev = os.path.basename(src)
    # nvme1n1p1 -> nvme1n1, sda2 -> sda
    m = re.match(r"(nvme\d+n\d+|mmcblk\d+|[a-z]+)", dev)
    return m.group(1) if m else dev


def disk_bytes(dev):
    for line in read("/proc/diskstats").split("\n"):
        f = line.split()
        if len(f) > 9 and f[2] == dev:
            return int(f[5]) * 512, int(f[9]) * 512
    return 0, 0


def default_iface():
    for line in read("/proc/net/route").split("\n")[1:]:
        f = line.split()
        if len(f) > 2 and f[1] == "00000000":
            return f[0]
    return ""


def net_bytes(iface):
    for line in read("/proc/net/dev").split("\n")[2:]:
        if ":" in line:
            name, rest = line.split(":", 1)
            if name.strip() == iface:
                f = rest.split()
                return int(f[0]), int(f[8])
    return 0, 0


def uptime():
    s = int(float(read("/proc/uptime").split()[0]))
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    parts = []
    if d:
        parts.append(f"{d} day{'s' if d != 1 else ''}")
    if h:
        parts.append(f"{h} hour{'s' if h != 1 else ''}")
    if not d:
        parts.append(f"{m} minute{'s' if m != 1 else ''}")
    return "up " + ", ".join(parts[:2])


class Procs:
    def __init__(self, pci):
        self.prev = {}
        self.pci = pci
        self.drm_fds = {}
        self.drm_scan = 0

    def vram(self, now):
        """VRAM per pid from amdgpu fdinfo (deduplicated by drm-client-id)."""
        if now - self.drm_scan > 5:
            self.drm_fds = {}
            for p in os.listdir("/proc"):
                if not p.isdigit():
                    continue
                try:
                    for fd in os.listdir(f"/proc/{p}/fd"):
                        try:
                            if os.readlink(f"/proc/{p}/fd/{fd}").startswith("/dev/dri/"):
                                self.drm_fds.setdefault(int(p), []).append(fd)
                        except OSError:
                            pass
                except OSError:
                    pass
            self.drm_scan = now
        out, seen = {}, set()
        for pid, fds in self.drm_fds.items():
            for fd in fds:
                info = read(f"/proc/{pid}/fdinfo/{fd}")
                if "drm-memory-vram" not in info:
                    continue
                pdev = re.search(r"drm-pdev:\s*(\S+)", info)
                pdev = pdev.group(1) if pdev else ""
                cid = re.search(r"drm-client-id:\s*(\d+)", info)
                if cid and cid.group(1) in seen:
                    continue
                if cid:
                    seen.add(cid.group(1))
                m = re.search(r"drm-memory-vram:\s*(\d+)\s*KiB", info)
                if m:
                    per = out.setdefault(pid, {})
                    per[pdev] = per.get(pdev, 0) + int(m.group(1)) * 1024
        return out

    def sample(self, dt, total_dt):
        now = time.time()
        vram = self.vram(now)            # pid -> {gpu pci: bytes}
        for pid, per in nvidia_procs().items():
            mine = vram.setdefault(pid, {})
            for bus, b in per.items():
                mine[bus] = mine.get(bus, 0) + b
        rows, cur, count = [], {}, 0
        for p in os.listdir("/proc"):
            if not p.isdigit():
                continue
            pid = int(p)
            st = read(f"/proc/{p}/stat")
            if not st:
                continue
            count += 1
            comm = st[st.find("(") + 1:st.rfind(")")]
            f = st[st.rfind(")") + 2:].split()
            ticks = int(f[11]) + int(f[12])
            rss = int(f[21]) * PAGE
            cur[pid] = ticks
            cpu = 0.0
            if pid in self.prev and total_dt > 0:
                # share of the whole machine (all cores = 100%)
                cpu = 100.0 * (ticks - self.prev[pid]) / total_dt
            by = vram.get(pid, {})
            v = sum(by.values())
            if cpu < 0.05 and rss < 64 * 1048576 and v == 0:
                continue
            name, note = comm, ""
            if len(comm) == 15:
                # the kernel cuts names at 15 characters; use the full program name
                a0 = os.path.basename(read(f"/proc/{p}/cmdline").split("\0")[0])
                if a0.startswith(comm):
                    name = a0
            if comm in ("python", "python3", "node", "bash", "sh", "java") or comm.startswith("python3."):
                args = read(f"/proc/{p}/cmdline").split("\0")
                script = ""
                rest = args[1:]
                for k, a in enumerate(rest):
                    if a == "-c":
                        break                      # inline code: keep the interpreter's name
                    if a == "-m" and k + 1 < len(rest):
                        script = rest[k + 1]       # python -m module
                        break
                    if a and not a.startswith("-"):
                        script = os.path.basename(a)
                        break
                if script:
                    name, note = script, comm
            try:
                own = (os.stat(f"/proc/{p}").st_uid == UID and comm not in PROTECTED and pid != os.getpid()
                       and not CRITICAL.search(comm) and not CRITICAL.search(name))
            except OSError:
                own = False
            rows.append({"pid": pid, "name": name, "note": note, "cpu": round(cpu, 1),
                         "ram": rss, "vram": v, "vramBy": by, "own": own})
        self.prev = cur
        rows.sort(key=lambda r: (r["vram"], r["cpu"], r["ram"]), reverse=True)
        keep = {r["pid"] for r in sorted(rows, key=lambda r: r["cpu"], reverse=True)[:25]}
        keep |= {r["pid"] for r in sorted(rows, key=lambda r: r["ram"], reverse=True)[:25]}
        keep |= {r["pid"] for r in rows if r["vram"] > 0}
        return [r for r in rows if r["pid"] in keep], count


def main():
    g0 = (all_gpus() or [{}])[0]
    procs = Procs(g0.get("pci", ""))
    disk = root_disk()
    iface = default_iface()
    kind = "Wi-Fi" if iface.startswith("wl") else "Ethernet" if iface else "Offline"
    t_prev, i_prev = cpu_times()
    r_prev, w_prev = disk_bytes(disk)
    rx_prev, tx_prev = net_bytes(iface)
    last = time.time()
    procs.sample(1, 0)
    while True:
        time.sleep(1)
        now = time.time()
        dt = max(0.2, now - last)
        last = now
        t, i = cpu_times()
        total_dt = t - t_prev
        cpu = 100.0 * (total_dt - (i - i_prev)) / total_dt if total_dt > 0 else 0
        t_prev, i_prev = t, i
        mem = {k: int(v.split()[0]) * 1024 for k, v in (l.split(":", 1) for l in read("/proc/meminfo").strip().split("\n"))}
        r, w = disk_bytes(disk)
        rx, tx = net_bytes(iface)
        rows, count = procs.sample(dt, total_dt * HZ / HZ)
        gpus = all_gpus()
        g = gpus[0] if gpus else {}
        out = {
            "cpu": round(cpu, 1), "cpuFreq": round(cpu_freq(), 1), "cpuTemp": cpu_temp(),
            "ramUsed": mem["MemTotal"] - mem["MemAvailable"], "ramTotal": mem["MemTotal"],
            "swapUsed": mem["SwapTotal"] - mem["SwapFree"],
            "diskRead": max(0, (r - r_prev) / dt), "diskWrite": max(0, (w - w_prev) / dt), "disk": disk,
            "rx": max(0, (rx - rx_prev) / dt), "tx": max(0, (tx - tx_prev) / dt), "net": kind,
            "gpu": g.get("busy", -1), "vramUsed": g.get("vramUsed", -1), "vramTotal": g.get("vramTotal", -1),
            "gpuTemp": g.get("temp", -1), "gpuPower": g.get("power", -1), "gpuName": g.get("name", ""),
            "gpus": gpus,
            "uptime": uptime(), "procCount": count, "procs": rows,
        }
        r_prev, w_prev, rx_prev, tx_prev = r, w, rx, tx
        print(json.dumps(out), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
