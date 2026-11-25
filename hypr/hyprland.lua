-- Tide · Hyprland config (dev mode)
-- Built 2026-11-22 from the previous config (backed up in
-- ~/.config/Tide/modes/ax-classic/hypr/). Machine setup, apps, window rules and
-- window keys are unchanged; Ax-Shell's autostart and keys are gone, and the
-- look (gaps, borders, rounding, blur, the tide-shell layer rule) comes from
-- ~/.config/Tide/modes/dev/hypr.lua, loaded at the end.
-- monitor=NAME,MODE,POSITION,SCALE[,key,value...] (written by Tide's Settings → Monitors)
-- extra keys: transform, vrr, bitdepth (numbers), cm (color preset), sdrbrightness, sdrsaturation
-- Tide's own folder, from $HOME (no user name in the config)
local TIDE = os.getenv("HOME") .. "/.config/Tide"
-- this PC's own extras (its hardware, apps, games, startup): hypr/local.lua, kept out of
-- the repo; it returns { start = function() ... end } for the login-only part
local LOCAL = nil
do
    local f = io.open(TIDE .. "/hypr/local.lua", "r")
    if f then f:close(); LOCAL = dofile(TIDE .. "/hypr/local.lua") end
end
local monitorKeys = { transform = true, vrr = true, bitdepth = true, cm = "string", sdrbrightness = true, sdrsaturation = true }
for line in io.lines(os.getenv("HOME") .. "/.config/hypr/monitors.conf") do
    local output, mode, position, scale, rest = line:match("^%s*monitor%s*=%s*([^,]*),%s*([^,]+),%s*([^,]+),%s*([%d%.]+)%s*(.-)%s*$")
    if output then
        local m = { output = output, mode = mode, position = position, scale = tonumber(scale) }
        for k, v in rest:gmatch(",%s*([%a_]+)%s*,%s*([^,%s]+)") do
            if monitorKeys[k] == "string" then m[k] = v
            elseif monitorKeys[k] and tonumber(v) then m[k] = tonumber(v) end
        end
        hl.monitor(m)
    end
end
hl.config({ ["render.cm_auto_hdr"] = 1 })
hl.config({ ["quirks.prefer_hdr"] = 2 })
hl.config({ ["general.resize_on_border"] = false })
hl.config({ ["general.allow_tearing"] = false })
hl.config({ ["decoration.rounding_power"] = 2 })
hl.config({ ["decoration.active_opacity"] = 1.0 })
hl.config({ ["decoration.inactive_opacity"] = 1.0 })
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5}, {0.75, 1} } })
hl.curve("quick", { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })
hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })
hl.config({ ["dwindle.preserve_split"] = true })
hl.config({ ["master.new_status"] = "master" })
hl.config({ ["misc.force_default_wallpaper"] = -1 })
hl.config({ ["misc.disable_hyprland_logo"] = false })
hl.config({ ["input.kb_layout"] = "us" })
hl.config({ ["input.kb_variant"] = "" })
hl.config({ ["input.kb_model"] = "" })
hl.config({ ["input.kb_options"] = "" })
hl.config({ ["input.kb_rules"] = "" })
hl.config({ ["input.follow_mouse"] = 1 })
hl.config({ ["input.sensitivity"] = 0 })
hl.config({ ["input.touchpad.natural_scroll"] = false })
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-open terminal"))  -- default terminal (Settings → Apps)
hl.bind("SUPER + E", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-open files"))  -- default file manager (Settings → Apps)
-- Tide: shell keys (global shortcuts the shell registers as tide:*)
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SPACE", hl.dsp.global("tide:launcher"))
hl.bind("SUPER + C", hl.dsp.global("tide:calculator"))
hl.bind("SUPER + D", hl.dsp.global("tide:controlcenter"))
hl.bind("SUPER + V", hl.dsp.global("tide:clipboard"))
hl.bind("SUPER + S", hl.dsp.global("tide:capture"))
hl.bind("SUPER + ESCAPE", hl.dsp.global("tide:power"))
hl.bind("SUPER + G", hl.dsp.global("tide:games"))
hl.bind("CTRL + SHIFT + ESCAPE", hl.dsp.global("tide:resources"))
hl.bind("SUPER + DELETE", hl.dsp.global("tide:cleanup"))
hl.bind("SUPER + W", hl.dsp.global("tide:wallpapers"))
hl.bind("SUPER + T", hl.dsp.global("tide:themes"))
hl.bind("SUPER + ALT + B", hl.dsp.exec_cmd(TIDE .. "/modes/dev/shell/scripts/restart.sh"))

hl.bind("SUPER + A", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" }))
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ action = "set", internal = 0, client = 2 }))
-- voice dictation through Tide's wrapper (the scripts run unchanged; the island shows the state)
hl.bind("SUPER + R", hl.dsp.exec_cmd(TIDE .. "/modes/dev/shell/scripts/voice.sh whisper-paste toggle"))  -- dictation -> clipboard
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(TIDE .. "/modes/dev/shell/scripts/voice.sh obs-voice toggle"))  -- dictation -> note in the vault
hl.bind("SUPER + ALT + E", hl.dsp.global("tide:eve"))  -- talk to Eve (live mode in the island)
-- Park mode (services/Park.qml, bin/tide-park): hold Super+Alt+P to park / unpark. While
-- parked the "tide-park" key map is on, so the kid space's keys reach it and nothing else
-- works: only the hold, and Super+Ctrl+Alt+P, which unparks without the shell (if it's
-- ever not running)
hl.bind("SUPER + ALT + P", hl.dsp.global("tide:park"))
hl.define_submap("tide-park", function()
    hl.bind("SUPER + ALT + P", hl.dsp.global("tide:park"))
    hl.bind("SUPER + CTRL + ALT + P", hl.dsp.exec_cmd(TIDE .. "/bin/tide-park unpark"))
end)
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = "1" }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = "2" }))
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = "3" }))
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = "4" }))
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = "5" }))
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = "6" }))
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = "7" }))
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = "8" }))
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = "9" }))
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }))
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = "1", follow = true }))
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = "2", follow = true }))
hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = "3", follow = true }))
hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = "4", follow = true }))
hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = "5", follow = true }))
hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = "6", follow = true }))
hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = "7", follow = true }))
hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = "8", follow = true }))
hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = "9", follow = true }))
hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "10", follow = true }))
-- themes, in picker order (Settings → Themes); a locked-in theme refuses to switch
hl.bind("SUPER + CTRL + 1", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 1"))
hl.bind("SUPER + CTRL + 2", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 2"))
hl.bind("SUPER + CTRL + 3", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 3"))
hl.bind("SUPER + CTRL + 4", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 4"))
hl.bind("SUPER + CTRL + 5", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 5"))
hl.bind("SUPER + CTRL + 6", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 6"))
hl.bind("SUPER + CTRL + 7", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 7"))
hl.bind("SUPER + CTRL + 8", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 8"))
hl.bind("SUPER + CTRL + 9", hl.dsp.exec_cmd("~/.config/Tide/bin/tide-mode nth 9"))
hl.bind("SUPER + ALT + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic", follow = true }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+; qs -p " .. TIDE .. "/modes/dev/shell ipc call island volume"), { release = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-; qs -p " .. TIDE .. "/modes/dev/shell ipc call island volume"), { release = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle; qs -p " .. TIDE .. "/modes/dev/shell ipc call island volume"), { release = true, locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { release = true, locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+; qs -p " .. TIDE .. "/modes/dev/shell ipc call island brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-; qs -p " .. TIDE .. "/modes/dev/shell ipc call island brightness"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.window_rule({ ["name"] = "suppress-maximize-events", ["suppress_event"] = "maximize", match = { ["class"] = ".*" } })
hl.window_rule({ ["name"] = "copilot-attach-file", ["float"] = true, ["center"] = true, match = { ["class"] = "xdg-desktop-portal-gtk" } })
hl.window_rule({ ["name"] = "fix-xwayland-drags", ["no_focus"] = true, match = { ["class"] = "^$", ["title"] = "^$", ["xwayland"] = true, ["float"] = true, ["fullscreen"] = false, ["pin"] = false } })
hl.window_rule({ ["name"] = "move-hyprland-run", ["move"] = "19 monitor_h-120", ["float"] = true, match = { ["class"] = "hyprland-run" } })
-- Tide: the Eve panel's window rule lives in modes/dev/hypr.lua (it follows the
-- interface size)
-- Tide: the updates panel runs pacman in this floating terminal
hl.window_rule({ ["name"] = "tide-updates", ["float"] = true, ["size"] = "1120 720", ["center"] = true, ["rounding"] = 18, ["no_blur"] = true, match = { ["class"] = "tide-updates" } })
hl.config({ ["general.layout"] = "dwindle" })
hl.config({ ["cursor.no_warps"] = false })
hl.config({ ["decoration.blur.new_optimizations"] = true })
hl.config({ ["decoration.blur.contrast"] = 1 })
hl.config({ ["decoration.blur.brightness"] = 1 })
hl.config({ ["decoration.shadow.enabled"] = true })
hl.config({ ["decoration.shadow.range"] = 10 })
hl.config({ ["decoration.shadow.render_power"] = 2 })
hl.config({ ["decoration.shadow.color"] = "rgba(0,0,0,0.25)" })
hl.config({ ["animations.enabled"] = true })
hl.curve("myBezier", { type = "bezier", points = { {0.4, 0.0}, {0.2, 1.0} } })
hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "myBezier", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 2.5, bezier = "myBezier" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "myBezier" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "myBezier", style = "slidefade 20%" })

-- Login-only applications; reloads do not restart existing services.
hl.on("hyprland.start", function()
    -- idle and lock: hypridle's own user unit (restarts on failure; Tide's Idle service
    -- starts it again if it's ever missing, e.g. after a Hyprland crash)
    hl.exec_cmd("systemctl --user start hypridle.service")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("pgrep -f '^(/usr/bin/)?qs -p " .. TIDE .. "/modes/dev/shell$' >/dev/null || uwsm-app -- qs -p " .. TIDE .. "/modes/dev/shell")
    -- wallpaper daemon (awww), kept for every mode. It needs this session's display: hand it
    -- to systemd first (after a log out the old one is gone), and start clean (a failed
    -- try from before would stop systemd from starting it)
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; systemctl --user reset-failed tide-awww.service; systemctl --user restart tide-awww.service")
    -- clipboard history: cliphist, plus which app and when (Tide's clip-store.sh)
    hl.exec_cmd("wl-paste --type text --watch " .. TIDE .. "/modes/dev/shell/scripts/clip-store.sh")
    hl.exec_cmd("wl-paste --type image --watch " .. TIDE .. "/modes/dev/shell/scripts/clip-store.sh")
    if LOCAL and LOCAL.start then LOCAL.start() end
end)

-- Dev mode look: gaps, borders, rounding, blur and the tide-shell layer rule
dofile(TIDE .. "/modes/dev/hypr.lua")
