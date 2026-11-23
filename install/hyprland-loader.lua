-- Hyprland loader. The real config depends on the active Tide mode
-- (~/.config/Tide/mode): each mode's ~/.config/Tide/modes/<mode>/mode.json names its
-- config in "hypr" (relative to ~/.config/Tide). For example:
--   dev            ~/.config/Tide/hypr/hyprland.lua
--   ax-classic     ~/.config/Tide/modes/ax-classic/hypr/hypr/hyprland.lua (the old setup;
--                  hidden from Tide's UI, `tide-mode ax-classic` still switches to it)
-- Switch with `tide-mode <mode>` or the island's theme picker (Super+T).
-- If anything is missing it falls back to dev.
-- The config from before Tide is kept next to this file as hyprland.lua.ax-classic.bak.
local home = os.getenv("HOME")
local tide = home .. "/.config/Tide"

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local mode = ((read(tide .. "/mode") or "dev"):match("^%s*(.-)%s*$"))
if mode == "" or not mode:match("^[%w._-]+$") then mode = "dev" end

local config = tide .. "/hypr/hyprland.lua"
local manifest = read(tide .. "/modes/" .. mode .. "/mode.json")
local rel = manifest and manifest:match('"hypr"%s*:%s*"([^"]+)"')
if rel and read(tide .. "/" .. rel) then config = tide .. "/" .. rel end

dofile(config)
