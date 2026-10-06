-- LatteOS › relácia „Marea (Hyprland)“ (latte-marea hyprland): pôvodná Marea (k4ditano/marea-plm) ako shell na
-- Hyprlande, s jej vlastnými skratkami z návodu, bez úprav LatteOS — na pokusy a porovnanie s Kvapkami.
-- Pôvodný pleamar a marea sú v PATH z ~/.local/share/marea-povodna/bin (latte-marea).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
-- obrazovky uložené v LatteOS (Nastavenia › Hardvér › Obrazovky): ten istý hlavný monitor a frekvencia ako v LatteOS GOO
-- (6. 10.: bez toho bol vedľajší monitor vľavo na 0,0 a hlavný bežal na 60 Hz)
do
    local f = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/latteos/monitors.lua"
    local h = io.open(f, "r")
    if h then h:close(); pcall(dofile, f) end
end
hl.config({
    input = { kb_layout = "sk,us", kb_options = "grp:alt_shift_toggle", follow_mouse = 1 },
    general = { layout = "dwindle", gaps_in = 5, gaps_out = 10 },
    decoration = { rounding = 12 },
})

local function run(cmd) return hl.dsp.exec_cmd(cmd) end
-- myšou: Super + ťahanie presúva / mení veľkosť okna; Marea sa ovláda myšou (klik na guľu)
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- skratky z návodu Marey
hl.bind("SUPER + Space", run("marea search"))
hl.bind("SUPER + L", run("marea lock"))
hl.bind("Print", run("marea shot_region"))
hl.bind("SHIFT + Print", run("marea shot_screen"))
hl.bind("CTRL + Print", run("marea shot_window"))
hl.bind("SUPER + SHIFT + C", run("marea record_toggle"))
hl.bind("SUPER + Return", run("latte-terminal"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())

hl.on("hyprland.start", function()
    local n = 0
    for _, m in ipairs(hl.get_monitors() or {}) do if m.name ~= "FALLBACK" then n = n + 1 end end
    if n == 0 then hl.exec_cmd("hyprctl output create headless LATTE-VIRT") end
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE'")
    hl.exec_cmd("sh -c 'swaybg -i \"${PLEAMAR_WALLPAPER:-/usr/share/backgrounds/latteos/latteos-wallpaper1.jpg}\" -m fill'")
    hl.exec_cmd("marea start")
    hl.exec_cmd("/usr/libexec/hyprpolkitagent")
end)
