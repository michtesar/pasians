-- Pasians in Hyprland: a fixed-size floating window instead of a tile
-- stretched across the monitor. Copy to ~/.config/hypr/pasians.lua and add
-- require("hypr.pasians") to ~/.config/hypr/hyprland.lua.
o.window({ title = "^pasians$" }, { float = true, center = true, size = { 1280, 860 } })

-- Optional launcher shortcut (SUPER + SHIFT + P is Google Photos).
-- o.bind("SUPER + ALT + P", "Pasians", "pasians")
