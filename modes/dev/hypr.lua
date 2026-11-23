-- Tide · Dev mode: Hyprland settings taken from the design canvas.
-- Loaded at the end of ~/.config/Tide/hypr/hyprland.lua:
--     dofile(os.getenv("HOME") .. "/.config/Tide/modes/dev/hypr.lua")
-- (The mode manager will apply this per mode later.)

-- Settings → Appearance writes these to theme.json (and applies them live):
--   "roundness" 0–24 (18 = the design: 14px window corners), "glassBlur" 0–60 (36 = size 9)
local function setting(key, fallback)
    local f = io.open(os.getenv("HOME") .. "/.config/Tide/modes/dev/theme.json", "r")
    if not f then return fallback end
    local s = f:read("*a")
    f:close()
    local v = s:match('"' .. key .. '"%s*:%s*([%d.]+)')
    return tonumber(v) or fallback
end
-- Settings → Appearance → Interface size ("uiScale": 1 / 1.15 / 1.3). The Eve panel
-- (a Quickshell window) floats on the right just under the bar, which grows with it;
-- Mod+drag moves it and Mod+right-drag resizes it like any window.
local uiScale = setting("uiScale", 1)
local function px(n) return math.floor(n * uiScale + 0.5) end
hl.window_rule({ ["name"] = "tide-eve", ["float"] = true, ["move"] = "monitor_w-window_w-" .. px(12) .. " " .. px(58), ["rounding"] = px(24), ["border_size"] = 0, ["no_shadow"] = true, match = { ["class"] = "org.quickshell", ["title"] = "^Eve$" } })

local windowRounding = math.floor(14 * setting("roundness", 18) / 18 + 0.5)
local blurSize = math.floor(setting("glassBlur", 36) / 4 + 0.5)

hl.config({
    -- windows sit 12px from the screen edges and 12px apart; the bar reserves 48px
    ["general.gaps_in"] = 6,
    ["general.gaps_out"] = 12,
    -- 1px borders: focused window rgba(255,255,255,0.22), others 0.08
    ["general.border_size"] = 1,
    ["general.col.active_border"] = "rgba(255, 255, 255, 0.22)",
    ["general.col.inactive_border"] = "rgba(255, 255, 255, 0.08)",
    -- window corners 14px
    ["decoration.rounding"] = windowRounding,
    -- frosted glass behind the bar, panels and island.
    -- The design asks for blur(28px) saturate(180%) on the bar and blur(40px) on panels;
    -- Hyprland uses one blur for everything, so this is the closest single setting.
    ["decoration.blur.enabled"] = true,
    ["decoration.blur.size"] = blurSize,
    ["decoration.blur.passes"] = 3,
    ["decoration.blur.vibrancy"] = 0.8,
    ["decoration.blur.vibrancy_darkness"] = 0.2,
})

-- Blur only where the shell draws a surface. ignore_alpha 0.4 sits above the shadows
-- (max 0.28) and the dim (0.35), and below the glass bar (0.42), so neither the
-- shadows nor the dimmed screen get blurred.
hl.layer_rule({ match = { namespace = "tide-shell" }, blur = true, ignore_alpha = 0.4 })

-- Keys live in ~/.config/Tide/hypr/hyprland.lua (SUPER+SPACE launcher, SUPER+C calculator, SUPER+D control center).
