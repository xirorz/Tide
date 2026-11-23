#!/usr/bin/env python3
# Bambu Lab printer status for the 3D printer widget: read-only, local network only,
# Python's standard library only (a minimal MQTT 3.1.1 client over TLS).
#
#   bambu.py watch HOST SERIAL      one JSON line per change: {state, seen, job...}
#   bambu.py watch --replay FILE    the same, from recorded reports (one JSON per line)
#   bambu.py test HOST SERIAL       connect once, wait for a report: {ok, error|model}
#   bambu.py find [SECONDS]         listen for printers announcing themselves (SSDP, UDP 2021)
#   bambu.py set-code               read the access code from stdin and keep it in
#                                   ~/.local/state/tide/secrets.json (chmod 600)
#   bambu.py has-code               true / false
#   bambu.py firewall               {fw: ufw|firewalld|none, subnet, cmd}: what would let
#                                   Find hear printers (UDP 2021), for Settings to show
#   bambu.py send HOST SERIAL CMD   one command, then wait for the printer's answer:
#                                   light-on, light-off, pause, resume, stop
#
# Controls (LAN mode only): while watching, a JSON line on stdin like {"cmd": "pause"}
# is sent to device/<serial>/request with its own sequence_id; the printer's answer
# (or 8 s of silence) comes back as {"ack": {"cmd", "ok", "reason"}}.
#
# The access code is read from secrets.json here and never printed or passed on a
# command line. The printer's certificate is self-signed, so it isn't verified; the
# connection only ever goes to the address set in Settings.
import ctypes, json, os, select, socket, ssl, struct, sys, time

STATE = os.path.expanduser("~/.local/state/tide")
SECRETS = os.environ.get("TIDE_BAMBU_SECRETS") or os.path.join(STATE, "secrets.json")


def die_with_parent():
    try:
        ctypes.CDLL("libc.so.6").prctl(1, 15)  # PR_SET_PDEATHSIG, SIGTERM
    except Exception:
        pass


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# ---------- secrets ----------
def read_secrets():
    try:
        with open(SECRETS) as f:
            return json.load(f)
    except Exception:
        return {}


def access_code():
    return (read_secrets().get("bambu") or {}).get("code", "")


def set_code(code):
    os.makedirs(STATE, exist_ok=True)
    s = read_secrets()
    s["bambu"] = {"code": code.strip()}
    fd = os.open(SECRETS + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(s, f)
    os.chmod(SECRETS + ".tmp", 0o600)
    os.replace(SECRETS + ".tmp", SECRETS)


# ---------- MQTT 3.1.1 ----------
def _str(s):
    b = s.encode()
    return struct.pack("!H", len(b)) + b


def _packet(kind, body):
    n, rl = len(body), bytearray()
    while True:
        d, n = n % 128, n // 128
        rl.append(d | (0x80 if n else 0))
        if not n:
            break
    return bytes([kind]) + bytes(rl) + body


class Mqtt:
    def __init__(self, host, user, password, keepalive=30):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE  # the printer's own self-signed certificate
        raw = socket.create_connection((host, 8883), timeout=8)
        self.s = ctx.wrap_socket(raw, server_hostname=host)
        self.keepalive = keepalive
        self.buf = b""
        body = _str("MQTT") + bytes([4, 0xC2]) + struct.pack("!H", keepalive)
        body += _str("tide-%d" % os.getpid()) + _str(user) + _str(password)
        self.s.sendall(_packet(0x10, body))
        kind, pkt = self.read(8)
        data = pkt[1] if pkt else b""
        if kind != 2:
            raise ConnectionError("The printer didn't answer")
        code = data[1] if len(data) > 1 else 255
        if code in (4, 5):
            raise PermissionError("The access code was refused")
        if code:
            raise ConnectionError("The printer refused the connection (%d)" % code)
        self.last_send = time.time()

    def _fill(self, timeout):
        r, _, _ = select.select([self.s], [], [], timeout) if not self.s.pending() else ([self.s], [], [])
        if not r:
            return False
        chunk = self.s.recv(65536)
        if not chunk:
            raise ConnectionError("The printer closed the connection")
        self.buf += chunk
        return True

    def read(self, timeout):
        """One packet as (type, body), or (None, None) after timeout seconds."""
        end = time.time() + timeout
        while True:
            if len(self.buf) >= 2:
                mult, n, i = 1, 0, 1
                while i < len(self.buf):
                    b = self.buf[i]
                    n += (b & 127) * mult
                    mult *= 128
                    i += 1
                    if not b & 0x80:
                        break
                else:
                    i = None
                if i is not None and len(self.buf) >= i + n:
                    kind, body = self.buf[0], self.buf[i:i + n]
                    self.buf = self.buf[i + n:]
                    return kind >> 4, (kind, body)
            left = end - time.time()
            if left <= 0:
                return None, None
            self._fill(min(left, 1))

    def send(self, data):
        self.s.sendall(data)
        self.last_send = time.time()

    def subscribe(self, topic):
        self.send(_packet(0x82, struct.pack("!H", 1) + _str(topic) + b"\x00"))

    def publish(self, topic, payload):
        self.send(_packet(0x30, _str(topic) + payload.encode()))

    def ping_if_due(self):
        if time.time() - self.last_send > self.keepalive * 0.6:
            self.send(b"\xc0\x00")

    def close(self):
        try:
            self.s.sendall(b"\xe0\x00")
            self.s.close()
        except Exception:
            pass


def parse_publish(packet):
    kind, body = packet
    tl = struct.unpack("!H", body[:2])[0]
    topic = body[2:2 + tl].decode(errors="replace")
    rest = body[2 + tl:]
    if (kind >> 1) & 3:  # QoS > 0 carries a packet id
        rest = rest[2:]
    return topic, rest


# ---------- the printer's report ----------
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        else:
            a[k] = v
    return a


STATES = {"RUNNING": "printing", "PREPARE": "printing", "SLICING": "printing", "PAUSE": "paused",
          "FINISH": "finished", "FAILED": "error", "IDLE": "idle"}


def summary(p):
    """What the widget shows, from the merged "print" report."""
    def num(k, d=-1):
        try:
            return float(p.get(k, d))
        except (TypeError, ValueError):
            return d
    g = str(p.get("gcode_state", "")).upper()
    state = STATES.get(g, "idle")
    if p.get("print_error") and state not in ("finished", "idle"):
        state = "error"
    trays, active = [], -1
    ams = p.get("ams") or {}
    try:
        now = int(ams.get("tray_now", -1))
    except (TypeError, ValueError):
        now = -1
    for unit in ams.get("ams") or []:
        for t in unit.get("tray") or []:
            try:
                idx = int(unit.get("id", 0)) * 4 + int(t.get("id", 0))
            except (TypeError, ValueError):
                continue
            if t.get("tray_color"):
                trays.append({"color": "#" + str(t["tray_color"])[:6], "type": t.get("tray_type", ""), "active": idx == now})
    vt = p.get("vt_tray") or {}
    if vt.get("tray_color") and now == 254:
        trays.append({"color": "#" + str(vt["tray_color"])[:6], "type": vt.get("tray_type", ""), "active": True})
    return {
        "status": state, "raw": g, "preparing": g in ("PREPARE", "SLICING"),
        "file": p.get("subtask_name") or p.get("gcode_file") or "",
        "percent": int(num("mc_percent", 0)), "minutesLeft": int(num("mc_remaining_time", -1)),
        "layer": int(num("layer_num", -1)), "layers": int(num("total_layer_num", -1)),
        "nozzle": round(num("nozzle_temper")), "nozzleTarget": round(num("nozzle_target_temper")),
        "bed": round(num("bed_temper")), "bedTarget": round(num("bed_target_temper")),
        "error": p.get("print_error") or 0, "trays": trays,
        "light": next((l.get("mode", "") for l in p.get("lights_report") or [] if l.get("node") == "chamber_light"), ""),
    }


SEQ = [int(time.time()) % 100000]


def command(cmd):
    """(sequence_id, payload) for a control command, or (None, None)."""
    SEQ[0] += 1
    seq = str(SEQ[0])
    if cmd in ("light-on", "light-off"):
        return seq, {"system": {"sequence_id": seq, "command": "ledctrl", "led_node": "chamber_light",
                                "led_mode": "on" if cmd == "light-on" else "off", "led_on_time": 500,
                                "led_off_time": 500, "loop_times": 1, "interval_time": 1000}}
    if cmd in ("pause", "resume", "stop"):
        return seq, {"print": {"sequence_id": seq, "command": cmd, "param": ""}}
    return None, None


def answer(report, seq):
    """The printer's answer to sequence_id seq inside a report: (ok, reason) or None."""
    for part in ("print", "system"):
        r = report.get(part)
        if isinstance(r, dict) and str(r.get("sequence_id")) == seq and "result" in r:
            ok = str(r["result"]).lower() == "success"
            return ok, "" if ok else (r.get("reason") or r.get("result") or "rejected")
    return None


def reports_from_replay(path):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                yield line.encode()
                time.sleep(0.2)


def watch(host, serial, replay=None):
    die_with_parent()
    merged, last, seen = {}, None, 0

    def emit(state, err=""):
        nonlocal last
        msg = {"state": state, "seen": seen, "error": err, "job": summary(merged.get("print", {}))}
        key = json.dumps(msg, sort_keys=True)
        if key != last:
            last = key
            out(msg)

    if replay:
        for payload in reports_from_replay(replay):
            merge(merged, json.loads(payload))
            seen = int(time.time())
            emit("online")
        while True:
            time.sleep(3600)

    backoff = 2
    while True:
        code = access_code()
        if not code:
            emit("offline", "No access code yet: add it in Settings → Widgets")
            time.sleep(10)
            continue
        try:
            c = Mqtt(host, "bblp", code)
            c.subscribe("device/%s/report" % serial)
            c.publish("device/%s/request" % serial,
                      json.dumps({"pushing": {"sequence_id": "0", "command": "pushall", "version": 1, "push_target": 1}}))
            backoff = 2
            pending = {}   # sequence_id -> (cmd, deadline)
            while True:
                kind, pkt = c.read(0.5)
                c.ping_if_due()
                if select.select([sys.stdin], [], [], 0)[0]:
                    line = sys.stdin.readline()
                    if not line:
                        sys.exit(0)
                    try:
                        cmd = json.loads(line).get("cmd", "")
                    except ValueError:
                        cmd = ""
                    seq, payload = command(cmd)
                    if seq:
                        c.publish("device/%s/request" % serial, json.dumps(payload))
                        pending[seq] = (cmd, time.time() + 8)
                for seq, (cmd, until) in list(pending.items()):
                    if time.time() > until:
                        del pending[seq]
                        out({"ack": {"cmd": cmd, "ok": False, "reason": "No answer from the printer"}})
                if kind == 3:
                    _, payload = parse_publish(pkt)
                    try:
                        report = json.loads(payload)
                    except ValueError:
                        continue
                    for seq in list(pending):
                        a = answer(report, seq)
                        if a:
                            out({"ack": {"cmd": pending.pop(seq)[0], "ok": a[0], "reason": a[1]}})
                    merge(merged, report)
                    seen = int(time.time())
                    emit("online")
                elif kind is None and seen and time.time() - seen > 90:
                    raise ConnectionError("No word from the printer")
        except PermissionError as e:
            emit("offline", str(e))
            time.sleep(60)
        except (OSError, ConnectionError, ssl.SSLError) as e:
            emit("offline", "Can't reach printer")
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)
        finally:
            try:
                c.close()
            except Exception:
                pass


def test(host, serial):
    code = access_code()
    if not code:
        return out({"ok": False, "error": "Add the access code first"})
    try:
        c = Mqtt(host, "bblp", code)
    except PermissionError as e:
        return out({"ok": False, "error": str(e)})
    except socket.timeout:
        return out({"ok": False, "error": "No answer from " + host + " (is it on and in LAN mode?)"})
    except (OSError, ConnectionError, ssl.SSLError) as e:
        return out({"ok": False, "error": "Can't reach " + host + ": " + (getattr(e, "strerror", None) or str(e))})
    try:
        c.subscribe("device/%s/report" % serial)
        c.publish("device/%s/request" % serial, json.dumps({"pushing": {"sequence_id": "0", "command": "pushall"}}))
        end = time.time() + 8
        while time.time() < end:
            kind, pkt = c.read(end - time.time())
            if kind == 3:
                p = json.loads(parse_publish(pkt)[1]).get("print", {})
                return out({"ok": True, "state": summary(p)["status"]})
        out({"ok": False, "error": "Connected, but no status came back: check the serial number"})
    finally:
        c.close()


def send(host, serial, cmd):
    seq, payload = command(cmd)
    if not seq:
        return out({"ok": False, "error": "Unknown command"})
    code = access_code()
    if not code:
        return out({"ok": False, "error": "Add the access code first"})
    try:
        c = Mqtt(host, "bblp", code)
    except PermissionError as e:
        return out({"ok": False, "error": str(e)})
    except (OSError, ConnectionError, ssl.SSLError):
        return out({"ok": False, "error": "Can't reach " + host})
    try:
        c.subscribe("device/%s/report" % serial)
        c.publish("device/%s/request" % serial, json.dumps(payload))
        end = time.time() + 8
        while time.time() < end:
            kind, pkt = c.read(end - time.time())
            if kind == 3:
                try:
                    a = answer(json.loads(parse_publish(pkt)[1]), seq)
                except ValueError:
                    continue
                if a:
                    return out({"ok": a[0], "error": a[1]})
        out({"ok": False, "error": "No answer from the printer"})
    finally:
        c.close()


def firewall():
    import ipaddress, subprocess
    def active(unit):
        return subprocess.run(["systemctl", "is-active", "--quiet", unit]).returncode == 0
    fw = "ufw" if active("ufw") else "firewalld" if active("firewalld") else "none"
    subnet = ""
    try:
        dev = subprocess.run(["ip", "-4", "route", "show", "default"], capture_output=True, text=True).stdout.split()
        dev = dev[dev.index("dev") + 1]
        addr = subprocess.run(["ip", "-4", "-o", "addr", "show", "dev", dev], capture_output=True, text=True).stdout.split()
        subnet = str(ipaddress.ip_interface(addr[addr.index("inet") + 1]).network)
    except (ValueError, IndexError):
        pass
    cmd = ("ufw allow proto udp from %s to any port 2021" % (subnet or "any")) if fw == "ufw" else \
          "firewall-cmd --add-port=2021/udp --permanent && firewall-cmd --reload" if fw == "firewalld" else ""
    out({"fw": fw, "subnet": subnet, "cmd": cmd})


def find(seconds):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("", 2021))
    except OSError:
        return out([])
    found, end = {}, time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([s], [], [], max(0, end - time.time()))
        if not r:
            break
        data, addr = s.recvfrom(4096)
        h = {}
        for line in data.decode(errors="replace").split("\r\n"):
            k, _, v = line.partition(":")
            h[k.strip().lower()] = v.strip()
        serial = h.get("usn", "")
        if serial and ("bambu" in (h.get("nt", "") + h.get("st", "") + h.get("server", "")).lower() or h.get("devmodel.bambu.com")):
            found[serial] = {"serial": serial, "host": h.get("location", addr[0]), "model": h.get("devmodel.bambu.com", ""),
                             "name": h.get("devname.bambu.com", "")}
    out(list(found.values()))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["watch"] and len(a) >= 3 and a[1] == "--replay":
        watch(None, None, replay=a[2])
    elif a[:1] == ["watch"] and len(a) >= 3:
        watch(a[1], a[2])
    elif a[:1] == ["test"] and len(a) >= 3:
        test(a[1], a[2])
    elif a[:1] == ["send"] and len(a) >= 4:
        send(a[1], a[2], a[3])
    elif a[:1] == ["find"]:
        find(float(a[1]) if len(a) > 1 else 6)
    elif a[:1] == ["set-code"]:
        set_code(sys.stdin.readline())
    elif a[:1] == ["firewall"]:
        firewall()
    elif a[:1] == ["has-code"]:
        out(bool(access_code()))
    else:
        sys.exit(__doc__ or "usage: see the top of this file")
