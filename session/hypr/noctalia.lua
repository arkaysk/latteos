-- LatteOS › relácia „Noctalia (čistá)“ (latte-session noctalia): Hyprland a pôvodná Noctalia s jej predvolenými
-- nastaveniami, bez úprav LatteOS (lišta, témy, skratky Windows, kvapky) — na pokusy a porovnanie. Noctalia
-- používa svoje pôvodné priečinky ~/.config/noctalia a ~/.local/state/noctalia; LatteOS má vlastné pod latteos/.
-- Ostáva iba to, bez čoho by sa nedalo pracovať: klávesnica sk/us, virtuálna obrazovka bez monitora a portály.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({
    input = { kb_layout = "sk,us", kb_options = "grp:alt_shift_toggle", follow_mouse = 1 },
    general = { layout = "dwindle", gaps_in = 5, gaps_out = 10 },
    decoration = { rounding = 12 },
})

local function run(cmd) return hl.dsp.exec_cmd(cmd) end
-- myšou: Super + ťahanie presúva / mení veľkosť okna; klávesy iba doplnok (Super = kláves Windows)
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("SUPER + Return", run("latte-terminal"))
hl.bind("SUPER + Space", run("noctalia msg panel-toggle launcher"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))

hl.on("hyprland.start", function()
    -- bez fyzického monitora (vzdialený prístup): virtuálna obrazovka, ako v LatteOS
    local n = 0
    for _, m in ipairs(hl.get_monitors() or {}) do if m.name ~= "FALLBACK" then n = n + 1 end end
    if n == 0 then hl.exec_cmd("hyprctl output create headless LATTE-VIRT") end
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE "
        .. "HYPRLAND_INSTANCE_SIGNATURE LATTE_VARIANT; systemctl --user start latte-session.target'")
    hl.exec_cmd("env -u NOCTALIA_CONFIG_HOME -u NOCTALIA_STATE_HOME noctalia")
end)
