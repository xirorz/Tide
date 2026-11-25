#!/usr/bin/env python3
# Tide's Bluetooth pairing agent (services/BtAgent.qml runs it while there's an
# adapter). Devices that pair with a code (keyboards, phones) need one: BlueZ asks the
# agent to show the code, confirm it, or ask for one. Each question goes to the shell as
# one JSON line on stdout, and the answer comes back as one JSON line on stdin:
#   out: {"id": 3, "kind": "confirm", "device": "Keyboard K380", "code": "123456"}
#        kind: confirm (does the device show this code?), pin / passkey (type the code
#        the device shows), display (type this code on the device; no answer),
#        authorize (allow this device to pair?), cancel (BlueZ gave up)
#   in:  {"id": 3, "ok": true, "value": "0000"}
import json, sys, threading
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

PATH = "/org/tide/bt_agent"
XML = """<node><interface name="org.bluez.Agent1">
  <method name="Release"/>
  <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
  <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
  <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
  <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
  <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
  <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
  <method name="Cancel"/>
</interface></node>"""

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
pending = {}          # id -> (invocation, kind)
next_id = [0]


def out(d):
    sys.stdout.write(json.dumps(d) + "\n")
    sys.stdout.flush()


def device_prop(path, name):
    try:
        v = bus.call_sync("org.bluez", path, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", ("org.bluez.Device1", name)), GLib.VariantType("(v)"),
                          Gio.DBusCallFlags.NONE, 2000, None)
        return v.unpack()[0]
    except GLib.Error:
        return None


def device_name(path):
    return device_prop(path, "Alias") or device_prop(path, "Name") or path.rsplit("/", 1)[-1]


def ask(inv, kind, path, code=""):
    next_id[0] += 1
    pending[next_id[0]] = (inv, kind)
    out({"id": next_id[0], "kind": kind, "device": device_name(path), "code": code})


def reject(inv):
    inv.return_dbus_error("org.bluez.Error.Rejected", "Rejected")


def on_call(conn, sender, path, iface, method, params, inv):
    a = params.unpack()
    if method == "RequestConfirmation":
        ask(inv, "confirm", a[0], "%06d" % a[1])
    elif method == "RequestPinCode":
        ask(inv, "pin", a[0])
    elif method == "RequestPasskey":
        ask(inv, "passkey", a[0])
    elif method == "RequestAuthorization":
        ask(inv, "authorize", a[0])
    elif method == "DisplayPinCode":
        out({"id": 0, "kind": "display", "device": device_name(a[0]), "code": a[1]})
        inv.return_value(None)
    elif method == "DisplayPasskey":
        out({"id": 0, "kind": "display", "device": device_name(a[0]), "code": "%06d" % a[1]})
        inv.return_value(None)
    elif method == "AuthorizeService":
        # a paired device asking for a service (audio, input): yes; anything else: no
        if device_prop(a[0], "Paired"):
            inv.return_value(None)
        else:
            reject(inv)
    elif method == "Cancel":
        for i, (v, _) in list(pending.items()):
            reject(v)
            del pending[i]
        out({"id": 0, "kind": "cancel"})
        inv.return_value(None)
    else:            # Release
        inv.return_value(None)


def answer(line):
    try:
        d = json.loads(line)
    except ValueError:
        return False
    inv, kind = pending.pop(d.get("id"), (None, None))
    if inv is None:
        return False
    if not d.get("ok"):
        reject(inv)
    elif kind == "pin":
        v = str(d.get("value", ""))[:16]
        inv.return_value(GLib.Variant("(s)", (v,))) if v else reject(inv)
    elif kind == "passkey":
        try:
            inv.return_value(GLib.Variant("(u)", (int(d.get("value", "")) % 1000000,)))
        except ValueError:
            reject(inv)
    else:
        inv.return_value(None)
    return False


def read_stdin():
    for line in sys.stdin:
        GLib.idle_add(answer, line)
    GLib.idle_add(loop.quit)


node = Gio.DBusNodeInfo.new_for_xml(XML)
bus.register_object(PATH, node.interfaces[0], on_call, None, None)
try:
    for m, args in (("RegisterAgent", GLib.Variant("(os)", (PATH, "KeyboardDisplay"))),
                    ("RequestDefaultAgent", GLib.Variant("(o)", (PATH,)))):
        bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", m, args, None,
                      Gio.DBusCallFlags.NONE, 5000, None)
except GLib.Error as e:
    print("bt-agent: " + e.message, file=sys.stderr)
    sys.exit(1)

loop = GLib.MainLoop()
threading.Thread(target=read_stdin, daemon=True).start()
loop.run()
