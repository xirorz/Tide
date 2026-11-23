pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Desktop widgets (Settings → Widgets): on/off, which screen, which widgets and where
// (theme.json "widgets"), plus the little data they need: weather (Open-Meteo, only
// once a location is set), reminders and quick notes (kept by Tide in
// ~/.local/state/tide/), and the "While you're away" status (a stub to fill in, like
// EveData.qml).
Singleton {
    id: root
    readonly property var cfg: Theme.opt("widgets", ({}))
    readonly property bool enabled: cfg.enabled === true
    // "" = the main screen (Theme.monitor)
    readonly property string screen: cfg.screen || ""
    readonly property string units: cfg.units || "F"
    // card style: "bar" follows the bar (dark when the bar is Text and icons), or "dark" / "glass"
    // the big clock: a soft shadow for light wallpapers (off by default) and its color ("white" or the wallpaper's "accent")
    readonly property bool clockShadow: cfg.clockShadow === true
    readonly property string clockColor: cfg.clockColor || "white"
    // the System widget's sections (cpu, memory, gpu, network, drives), all shown unless switched off
    function systemShows(section) { return !cfg.system || cfg.system[section] !== false; }
    function setSystemShows(section, on) { const s = Object.assign({}, cfg.system || {}); s[section] = on; save({ system: s }); }
    readonly property string cardStyle: cfg.cardStyle || "bar"
    readonly property bool cardGlass: cardStyle === "glass" || (cardStyle === "bar" && Theme.surface === "glass" && Theme.barStyle !== "text")
    readonly property var location: cfg.location || null      // { name, lat, lon }
    property bool editing: false

    // the six from the design, plus optional extras; x/y are pixels from the screen's top-left, -1 = default
    readonly property var catalog: [
        { type: "clock", scale: [0.5, 3], label: "Clock", icon: "M12 4 A8 8 0 1 0 12.01 4 M12 8 V12 L15 14" },
        { type: "weather", sizes: ["small", "medium", "large"], label: "Weather", icon: "M7 18 A4 4 0 0 1 7 10 A5 5 0 0 1 16.6 8.5 A3.5 3.5 0 1 1 17 18 Z" },
        { type: "nowplaying", sizes: ["small", "medium", "large"], label: "Now playing", icon: "M9 18 V6 L19 4 V16 M6.5 15.5 A2.5 2.5 0 1 0 6.51 15.5 M16.5 13.5 A2.5 2.5 0 1 0 16.51 13.5" },
        { type: "notes", box: [260, 120, 560, 520], label: "Quick notes", icon: "M6 4 H18 V20 H6 Z M9 9 H15 M9 13 H15 M9 17 H12" },
        { type: "calendar", sizes: ["small", "medium"], label: "Calendar", icon: "M5 6 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7" },
        { type: "status", label: "While you're away", icon: "M4 17 L10 12 L4 7 M12 19 H20" },
        // optional: not in the default layout, only added from the gallery
        { type: "system", sizes: ["small", "medium"], label: "System", icon: "M4 18 A8 8 0 1 1 20 18 M12 18 L16 11", optional: true },
        { type: "printer", sizes: ["small", "medium"], label: "3D printer", icon: "M5 20h14M7 20V9h10v11M9 9V5h6v4M10 13h4", optional: true }
    ]
    readonly property var items: cfg.items || catalog.filter(c => !c.optional).map(c => ({ type: c.type, x: -1, y: -1 }))
    function has(type) { return items.some(i => i.type === type); }

    function save(patch) { Theme.set("widgets", Object.assign({}, cfg, patch)); }
    function setEnabled(on) { save({ enabled: on }); if (!on) editing = false; }
    function add(type) { if (!has(type)) save({ items: items.concat([{ type: type, x: -1, y: -1 }]) }); }
    function remove(type) { save({ items: items.filter(i => i.type !== type) }); }
    function move(type, x, y) { save({ items: items.map(i => i.type === type ? Object.assign({}, i, { x: Math.round(x), y: Math.round(y) }) : i) }); }
    // Sizing, from the catalog: "sizes" widgets snap between layouts (small / medium /
    // large, each its own design); "scale" widgets grow and shrink as a whole within
    // [min, max]; "box" widgets (Quick notes) change their width and height within
    // [minW, minH, maxW, maxH] with the text at its normal size; none of these (While
    // you're away) keeps its size. An item saved before sizes existed lands on the
    // size nearest its old scale.
    function spec(type) { return catalog.find(c => c.type === type) || {}; }
    function sizeOf(item) {
        const z = spec(item.type).sizes;
        if (!z) return "";
        if (z.indexOf(item.size) >= 0) return item.size;
        const s = item.s || 1;
        return s < 0.85 ? z[0] : s > 1.2 && z.length > 2 ? z[2] : "medium";
    }
    function setBox(type, w, h) { save({ items: items.map(i => i.type === type ? Object.assign({}, i, { w: Math.round(w), h: Math.round(h), s: undefined }) : i) }); }
    function setSize(type, size) { save({ items: items.map(i => i.type === type ? Object.assign({}, i, { size: size, s: undefined }) : i) }); }
    // scale: a multiple of the design's size, set with the corner handle in edit mode
    function resize(type, s) { save({ items: items.map(i => i.type === type ? Object.assign({}, i, { s: Math.round(s * 100) / 100 }) : i) }); }
    function resetLayout() { save({ items: items.map(i => ({ type: i.type, x: -1, y: -1 })) }); }

    // the clock widget's own font (Settings → Widgets; the choices live in Fonts.qml)
    readonly property var clockFont: Fonts.clockFonts.find(f => f.value === cfg.clockFont) || Fonts.clockFonts[0]

    // ---------- weather (Open-Meteo, no key) ----------
    property var weather: null    // { temp, code, high, low, hours: [{t, d}], days: [{name, code, high, low}] }
    property string weatherError: ""
    function refreshWeather() {
        if (!enabled || !has("weather") || !location) return;
        const u = units === "C" ? "celsius" : "fahrenheit";
        wx.command = ["curl", "-s", "-m", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + location.lat + "&longitude=" + location.lon +
            "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m&daily=temperature_2m_max,temperature_2m_min,weather_code&forecast_days=6&timezone=auto&temperature_unit=" + u];
        wx.running = true;
    }
    Process {
        id: wx
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { root.weatherError = "Weather isn't available right now"; return; }
                if (!d.current) { root.weatherError = "Weather isn't available right now"; return; }
                // times are the place's own local time: compare as text, read the hour from it
                const idx = d.hourly.time.findIndex(t => t > d.current.time);
                const hours = [];
                for (let k = 0; k < 5 && idx >= 0 && idx + k * 2 < d.hourly.time.length; k++) {
                    const i = idx + k * 2;
                    const h = parseInt(d.hourly.time[i].slice(11, 13));
                    hours.push({ t: (h % 12 || 12) + (h < 12 ? " AM" : " PM"), d: Math.round(d.hourly.temperature_2m[i]) + "°" });
                }
                // the next five days (the large weather widget)
                const days = [];
                for (let i = 1; i < d.daily.time.length && days.length < 5; i++)
                    days.push({ name: Qt.formatDate(new Date(d.daily.time[i] + "T12:00:00"), "ddd"), code: d.daily.weather_code[i],
                                high: Math.round(d.daily.temperature_2m_max[i]), low: Math.round(d.daily.temperature_2m_min[i]) });
                root.weather = { temp: Math.round(d.current.temperature_2m), code: d.current.weather_code, day: d.current.is_day === 1,
                                 high: Math.round(d.daily.temperature_2m_max[0]), low: Math.round(d.daily.temperature_2m_min[0]), hours: hours, days: days };
                root.weatherError = "";
            }
        }
    }
    Timer { interval: 1800000; repeat: true; running: root.enabled && root.has("weather"); triggeredOnStart: true; onTriggered: root.refreshWeather() }
    Connections {
        target: root
        // no place: forget the last forecast
        function onLocationChanged() { if (!root.location) root.weather = null; root.refreshWeather(); }
        function onUnitsChanged() { root.refreshWeather(); }
    }
    // the sky as an icon path: sun or moon, cloud, rain
    function weatherIcon(code, day) {
        if (code === 0) return day ? "M12 4 V2 M12 22 V20 M4 12 H2 M22 12 H20 M5.6 5.6 L4.2 4.2 M19.8 19.8 L18.4 18.4 M5.6 18.4 L4.2 19.8 M19.8 4.2 L18.4 5.6 M12 7 A5 5 0 1 0 12.01 7" : "M20 14.5 A8 8 0 0 1 9.5 4 A7 7 0 1 0 20 14.5 Z";
        if (code >= 51) return "M7 15 A4 4 0 0 1 7 7 A5 5 0 0 1 16.6 5.5 A3.5 3.5 0 1 1 17 15 Z M8 18 L7 21 M12 18 L11 21 M16 18 L15 21";
        return "M7 18 A4 4 0 0 1 7 10 A5 5 0 0 1 16.6 8.5 A3.5 3.5 0 1 1 17 18 Z";
    }
    function weatherText(code) {
        if (code === 0) return "Clear";
        if (code <= 2) return "Partly cloudy";
        if (code === 3) return "Cloudy";
        if (code <= 48) return "Fog";
        if (code <= 57) return "Drizzle";
        if (code <= 67) return "Rain";
        if (code <= 77) return "Snow";
        if (code <= 82) return "Showers";
        if (code <= 86) return "Snow showers";
        return "Thunderstorms";
    }

    // looking up a place for Settings (Open-Meteo geocoding)
    property var places: []
    function findPlace(q) {
        if (!q.trim()) { places = []; return; }
        geo.command = ["curl", "-s", "-m", "8", "https://geocoding-api.open-meteo.com/v1/search?count=5&name=" + encodeURIComponent(q.trim())];
        geo.running = true;
    }
    Process {
        id: geo
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.places = (d.results || []).map(r => ({ name: r.name + (r.admin1 ? ", " + r.admin1 : "") + (r.country_code ? " · " + r.country_code : ""), short: r.name, lat: r.latitude, lon: r.longitude }));
                } catch (e) { root.places = []; }
            }
        }
    }
    function setLocation(p) { places = []; save({ location: { name: p.short, lat: p.lat, lon: p.lon } }); }

    // ---------- reminders and notes (kept by Tide) ----------
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/tide"
    property var reminders: []      // [{ id, title, date: "YYYY-MM-DD", time: "9:00 AM" }]
    FileView {
        id: remFile
        path: root.stateDir + "/reminders.json"
        printErrors: false
        onLoaded: { try { root.reminders = JSON.parse(text()); } catch (e) { root.reminders = []; } }
    }
    function addReminder(title, date, time) {
        if (!title.trim()) return;
        reminders = reminders.concat([{ id: String(Date.now()), title: title.trim(), date: date, time: time.trim() }]);
        remFile.setText(JSON.stringify(reminders));
    }
    function removeReminder(id) {
        reminders = reminders.filter(r => r.id !== id);
        remFile.setText(JSON.stringify(reminders));
    }
    property string notes: ""
    FileView {
        id: notesFile
        path: root.stateDir + "/notes.md"
        printErrors: false
        onLoaded: root.notes = text()
    }
    function setNotes(t) { notes = t; noteSaver.restart(); }
    Timer { id: noteSaver; interval: 600; onTriggered: notesFile.setText(root.notes) }

    // ---------- "While you're away" (stub: fill in to show your agents and tests) ----------
    property var status: []         // [{ label, icon, value, progress (0-1 or -1) }]

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    IpcHandler {
        target: "widgets"
        function refreshWeather(): void { root.refreshWeather(); }
        function weather(): string { return JSON.stringify(root.weather); }
    }
}
