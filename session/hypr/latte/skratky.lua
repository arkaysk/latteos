-- latte/skratky.lua — profily ovládania (alfatest 1, odpovede 25. 9.): klávesové skratky, fokus a stredný klik podľa toho,
-- odkiaľ používateľ prichádza. Predvolený je Windows (LatteOS je hlavne pre bývalých používateľov Windows).
--   windows  Windows 7–11: Alt+Tab, Alt+F4, Ctrl+Alt+Del, samotný Win = Štart (App Manager), Ctrl+Esc = Štart
--            (klávesnice bez Win), Win+E/I/A/N/V/./D/L/M/Home/Shift+S/šípky/Ctrl+D…; fokus kliknutím
--   linux    GNOME/KDE + tiling (pôvodné skratky LatteOS): Super+Enter, Super+Q, Super+šípky fokus, Super+1…9 plochy…
--   mac      macOS na PC klávesnici (Cmd = Super): Cmd+Medzerník, Cmd+Tab, Cmd+Q/M/H, Cmd+Shift+3/4/5, Ctrl+↑…
-- Voľba: ~/.config/latteos/profil-ovladania (Nastavenia › Hardvér › Klávesnica a skratky). Zmena platí po
-- `hyprctl reload` (Nastavenia ho spustia). Spoločné skratky (hlasitosť, snímky, Monitor…) majú všetky profily.
-- Kláves Win nesmie byť jediná cesta: herné klávesnice ho často nemajú (všetko ide aj myšou z lišty).
local K = {}

local cfgdir = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/latteos"

function K.profile()
    local f = io.open(cfgdir .. "/profil-ovladania", "r")
    if not f then return "windows" end
    local p = (f:read("*l") or ""):match("%a+") or ""
    f:close()
    return (p == "linux" or p == "mac") and p or "windows"
end

local function bind(keys, action, opts) hl.bind(keys, action, opts) end
local function run(cmd) return hl.dsp.exec_cmd(cmd) end
local function panel(id, ctx) return run("noctalia msg panel-toggle " .. id .. (ctx and (" " .. ctx) or "")) end

-- ── pomocné akcie okien (Windows) ─────────────────────────────────────────────
local function cur_ws() local ws = hl.get_active_workspace(); return ws and ws.id end
local function normal_windows(ws_id)
    local out = {}
    for _, w in ipairs(hl.get_windows() or {}) do
        local ws = w.workspace
        if w.mapped and ws and (ws_id == nil or ws.id == ws_id) and not tostring(ws.name or ""):find("^special") then table.insert(out, w) end
    end
    return out
end
local function minimize(w)
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:" .. w.address }))
end

latte = latte or {}
latte.keys = latte.keys or {}
-- Win+M: minimalizovať všetko na ploche; Win+Home: všetko okrem aktívneho
function latte.keys.minimize_all(keep_active)
    local a = hl.get_active_window()
    for _, w in ipairs(normal_windows(cur_ws())) do
        if not (keep_active and a and w.address == a.address) then minimize(w) end
    end
end
-- Win+Shift+M: vrátiť minimalizované okná na aktuálnu plochu
function latte.keys.restore_all()
    local ws = cur_ws()
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.workspace and tostring(w.workspace.name or ""):find("^special:minimized") then
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws), follow = false, window = "address:" .. w.address }))
        end
    end
end
-- Win+↑ / Win+↓ / Win+←→ v režime plávajúcich okien ako Windows, v páske a dlaždiciach ako Linux (fokus)
local function floating_mode() local ok, W = pcall(require, "latte.windows"); return ok and W.current == "plavajuce" end
function latte.keys.win_arrow(dir)
    local w = hl.get_active_window()
    if not floating_mode() or not w then hl.dispatch(hl.dsp.focus({ direction = dir })); return end
    local snap = require("latte.snap")
    if dir == "up" then
        if w.fullscreen ~= 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })) end
    elseif dir == "down" then
        if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
        elseif snap.is_snapped(w) then snap.restore(w)
        else minimize(w) end
    else
        if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })) end
        snap.apply(dir == "left" and "lava" or "prava")
    end
end
-- Win+1…9: N-té okno na lište (poradie zľava ako v páske); ak je aktívne, minimalizuje ho (ako panel úloh)
function latte.keys.nth_window(n)
    local list = normal_windows(cur_ws())
    table.sort(list, function(a, b)
        local ax, bx = (a.at and (a.at.x or a.at[1])) or 0, (b.at and (b.at.x or b.at[1])) or 0
        return ax < bx
    end)
    local w = list[n]
    if not w then return end
    if w.active then minimize(w) else hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address })) end
end
-- Win+Ctrl+D / Win+Ctrl+←→ / Win+Ctrl+F4: virtuálne plochy (Windows ich radí za sebou)
function latte.keys.desk_new() hl.dispatch(hl.dsp.focus({ workspace = "empty" })) end
function latte.keys.desk_step(d)
    local ws = cur_ws() or 1
    local t = ws + d
    if t < 1 then return end
    hl.dispatch(hl.dsp.focus({ workspace = t }))
end
function latte.keys.desk_close()
    local ws = cur_ws() or 1
    local to = ws > 1 and ws - 1 or ws + 1
    for _, w in ipairs(normal_windows(ws)) do
        hl.dispatch(hl.dsp.window.move({ workspace = tostring(to), follow = false, window = "address:" .. w.address }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = to }))
end
-- Alt+F4 ako vo Windows: zavrie aktívne okno; na prázdnej ploche otvorí ponuku Vypnúť
function latte.keys.alt_f4()
    if hl.get_active_window() then hl.dispatch(hl.dsp.window.close()) else hl.exec_cmd("latte-ponuka vypnut") end
end
-- ponuka okna (pravý klik na titulok, Alt+Medzerník; apps/ponuka.qml): akcie nad oknom podľa adresy
latte.okno = latte.okno or {}
local function by_addr(a) return a and hl.get_window("address:" .. a) end
function latte.okno.obnovit(a)
    local w = by_addr(a); if not w then return end
    if w.fullscreen ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ mode = w.fullscreen == 1 and "maximized" or "fullscreen", action = "unset", window = "address:" .. a }))
    else local S = require("latte.snap"); if S.is_snapped(w) then S.restore(w) end end
end
function latte.okno.minimalizovat(a) local w = by_addr(a); if w then minimize(w) end end
function latte.okno.maximalizovat(a)
    hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = "address:" .. a }))
end
function latte.okno.rozlozenie(a, z) local w = by_addr(a); if w then require("latte.snap").apply(z, w) end end
function latte.okno.navrchu(a)
    local w = by_addr(a); if not w then return end
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = "address:" .. a })) end
    hl.dispatch(hl.dsp.window.pin({ window = "address:" .. a }))
end
function latte.okno.na_plochu(a, n)
    hl.dispatch(hl.dsp.window.move({ workspace = n == 0 and "empty" or tostring(n), follow = false, window = "address:" .. a }))
end
function latte.okno.zavriet(a) hl.dispatch(hl.dsp.window.close({ window = "address:" .. a })) end

-- lupa (Win+Plus / Win+Mínus / Win+Esc): zväčšenie okolo kurzora (Hyprland cursor:zoom_factor)
local zoom = 1
-- priamo nastaviť zväčšenie (Nastavenia › Prístupnosť › Lupa)
function latte.keys.zoomTo(f)
    zoom = math.max(1, math.min(8, tonumber(f) or 1))
    hl.config({ cursor = { zoom_factor = zoom } })
end
function latte.keys.zoom(step)
    zoom = step == 0 and 1 or math.max(1, math.min(8, zoom * (step > 0 and 1.25 or 0.8)))
    if zoom < 1.05 then zoom = 1 end
    hl.config({ cursor = { zoom_factor = zoom } })
end

-- ── spoločné pre všetky profily ────────────────────────────────────────────────
local function common()
    bind("ALT + Tab", run("noctalia msg window-switcher"))                       -- drž Alt, Tab = ďalšie, pusti = prepni
    bind("ALT + SHIFT + Tab", run("noctalia msg window-switcher"))
    bind("ALT + F4", function() latte.keys.alt_f4() end)
    bind("CTRL + ALT + Delete", run("latte-ponuka zabezpecenie"))                -- ako Windows: zamknúť, odhlásiť, Monitor…
    bind("CTRL + SHIFT + Escape", run("latte-app monitor"))                      -- Správca úloh
    -- snímky obrazovky (vstavané v Noctalii): oblasť, celá obrazovka, s kreslením
    bind("Print", run("noctalia msg screenshot-region"))
    bind("SHIFT + Print", run("noctalia msg screenshot-annotate"))
    bind("ALT + Print", run("noctalia msg screenshot-fullscreen"))
    -- multimediálne a špeciálne klávesy
    bind("XF86AudioRaiseVolume", run("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    bind("XF86AudioLowerVolume", run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
    bind("XF86AudioMute",        run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
    bind("XF86AudioMicMute",     run("noctalia msg mic-mute"),                         { locked = true })
    bind("XF86AudioPlay",        run("noctalia msg media play-pause"),                 { locked = true })
    bind("XF86AudioPause",       run("noctalia msg media play-pause"),                 { locked = true })
    bind("XF86AudioNext",        run("noctalia msg media next"),                       { locked = true })
    bind("XF86AudioPrev",        run("noctalia msg media previous"),                   { locked = true })
    bind("XF86AudioStop",        run("noctalia msg media stop"),                       { locked = true })
    bind("XF86MonBrightnessUp",  run("brightnessctl set 5%+"),                         { locked = true, repeating = true })
    bind("XF86MonBrightnessDown",run("brightnessctl set 5%-"),                         { locked = true, repeating = true })
    bind("XF86KbdBrightnessUp",  run("noctalia msg keyboard-backlight-up"),            { locked = true })
    bind("XF86KbdBrightnessDown",run("noctalia msg keyboard-backlight-down"),          { locked = true })
    bind("XF86Calculator",       run("noctalia msg panel-toggle launcher"))             -- Text Bar počíta príklady
    bind("XF86Explorer",         run("latte-app subory"))
    bind("XF86HomePage",         run("xdg-open https://"))
    bind("XF86Mail",             run("xdg-open mailto:"))
    bind("XF86Search",           run("noctalia msg panel-toggle launcher"))
    bind("XF86Tools",            run("latte-app nastavenia"))
    -- myš: Super + ťahanie presúva / mení veľkosť okna, Super + koliesko prepína plochy (zvyk z Linuxu, nič neprekáža)
    bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
    bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
    bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    bind("SUPER + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
    -- LatteOS doplnky (nekolidujú s Windows): Herňa, rozloženia okna, prehľad pásky, plocha, zamknúť, Súbory
    bind("SUPER + G", panel("latteos/games:panel"))
    bind("SUPER + Z", panel("latteos/snap:panel"))
    bind("SUPER + Tab", panel("latteos/overview:panel"))
    bind("SUPER + L", run("noctalia msg session lock"))
    bind("SUPER + E", run("latte-app subory"))
    bind("SUPER + SHIFT + left",  hl.dsp.window.move({ monitor = "l" }))
    bind("SUPER + SHIFT + right", hl.dsp.window.move({ monitor = "r" }))
    bind("SUPER + ALT + W", run("latte-tapety dalsia"))
    bind("SUPER + ALT + P", run("latte-tapety pauza"))
end

-- ── Windows 7–11 ───────────────────────────────────────────────────────────────
local function windows()
    -- Štart; v hernom režime samotný Win nič neotvorí (ako herný režim klávesníc a Windows), Ctrl+Esc áno
    local game_file = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/latteos/game-mode"
    local function start_key()
        local f = io.open(game_file, "r")
        if f then local v = f:read("*l"); f:close(); if v == "1" then return end end
        hl.exec_cmd("latte-spustac prepni")
    end
    local start = run("latte-spustac prepni")
    bind("SUPER + SUPER_L", start_key, { release = true })                       -- samotný Win = Štart (App Manager)
    bind("SUPER + SUPER_R", start_key, { release = true })
    bind("CTRL + Escape", start)                                                  -- Štart aj bez klávesu Win
    bind("SUPER + S", panel("launcher"))                                          -- hľadať (Text Bar)
    bind("SUPER + Q", panel("launcher"))
    bind("SUPER + R", panel("launcher"))                                          -- Spustiť
    bind("SUPER + Space", panel("launcher"))                                      -- Text Bar (rozloženie: Alt+Shift)
    bind("SUPER + X", run("latte-ponuka win-x"))                                  -- ponuka pre pokročilých
    bind("SUPER + I", run("latte-app nastavenia"))
    bind("SUPER + A", run("latte-rychle prepni"))                                 -- Rýchle nastavenia (Zariadenia)
    bind("SUPER + N", panel("latteos/time:panel", "oznamenia"))                   -- oznámenia a kalendár
    bind("SUPER + ALT + D", panel("latteos/time:panel", "kalendar"))
    bind("SUPER + V", panel("latteos/kapsa:panel"))                               -- história schránky = Kapsa
    bind("SUPER + period", run("latte-emoji"))                                     -- emoji (vloží sa rovno)
    bind("SUPER + semicolon", run("latte-emoji"))
    bind("SUPER + SHIFT + S", run("noctalia msg screenshot-region"))              -- Výstrižky
    bind("SUPER + Print", run("latte-snimka ulozit"))                             -- celá obrazovka do Obrázky/Snímky obrazovky
    bind("SUPER + ALT + R", run("latte-nahravanie prepni"))                       -- nahrávanie obrazovky (ako Xbox Game Bar)
    bind("SUPER + SHIFT + R", run("latte-nahravanie oblast"))                     -- nahrávanie oblasti (ako Výstrižky)
    bind("SUPER + D", function() latte.keys.show_desktop() end)
    bind("SUPER + M", function() latte.keys.minimize_all(false) end)
    bind("SUPER + SHIFT + M", function() latte.keys.restore_all() end)
    bind("SUPER + Home", function() latte.keys.minimize_all(true) end)
    for _, d in ipairs({ "up", "down", "left", "right" }) do
        bind("SUPER + " .. d, function() latte.keys.win_arrow(d) end)
    end
    bind("SUPER + CTRL + D", function() latte.keys.desk_new() end)
    bind("SUPER + CTRL + left",  function() latte.keys.desk_step(-1) end)
    bind("SUPER + CTRL + right", function() latte.keys.desk_step(1) end)
    bind("SUPER + CTRL + F4", function() latte.keys.desk_close() end)
    for i = 1, 9 do bind("SUPER + " .. i, function() latte.keys.nth_window(i) end) end
    bind("SUPER + P", run("latte-ponuka projekcia"))                              -- premietanie (Iba PC / Duplikovať / Rozšíriť / Iba druhá)
    bind("SUPER + equal", function() latte.keys.zoom(1) end)                      -- lupa
    bind("SUPER + KP_Add", function() latte.keys.zoom(1) end)
    bind("SUPER + minus", function() latte.keys.zoom(-1) end)
    bind("SUPER + KP_Subtract", function() latte.keys.zoom(-1) end)
    bind("SUPER + Escape", function() latte.keys.zoom(0) end)
    bind("SUPER + C", panel("latteos/ai:chat"))                                   -- AI (ako Copilot vo Win11)
    bind("ALT + Space", run("latte-ponuka okno"))                                 -- ponuka okna
    return { follow_mouse = 2, middle_click_paste = false }
end

-- ── Linux (GNOME / KDE / tiling) — pôvodné skratky LatteOS ────────────────────
local function linux()
    local W = require("latte.windows")
    bind("SUPER + SUPER_L", run("latte-spustac prepni"), { release = true })     -- GNOME/KDE: samotný Super = spúšťač
    bind("SUPER + Return", run("latte-terminal"))
    bind("CTRL + ALT + T", run("latte-terminal"))
    bind("SUPER + Space", panel("launcher"))
    bind("ALT + F2", panel("launcher"))
    bind("SUPER + SHIFT + Tab", run("noctalia msg window-switcher"))
    bind("SUPER + A", run("latte-rychle prepni"))
    bind("SUPER + I", panel("latteos/ai:chat"))
    bind("SUPER + Q", hl.dsp.window.close())
    bind("SUPER + N", function() latte.win.minimize() end)
    bind("SUPER + SHIFT + N", hl.dsp.workspace.toggle_special("minimized"))
    bind("SUPER + F", hl.dsp.window.fullscreen())
    bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
    bind("SUPER + W", function() W.cycle() end)
    bind("SUPER + D", function() latte.keys.show_desktop() end)
    bind("SUPER + SHIFT + S", run("noctalia msg screenshot-region"))
    for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
        bind("SUPER + " .. key,        hl.dsp.focus({ direction = dir }))
        bind("SUPER + CTRL + " .. key, hl.dsp.window.move({ direction = dir }))
    end
    bind("CTRL + ALT + left",  function() latte.keys.desk_step(-1) end)
    bind("CTRL + ALT + right", function() latte.keys.desk_step(1) end)
    bind("SUPER + Page_Up",    function() latte.keys.desk_step(-1) end)
    bind("SUPER + Page_Down",  function() latte.keys.desk_step(1) end)
    for i = 1, 9 do
        bind("SUPER + " .. i,         hl.dsp.focus({ workspace = i }))
        bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
    end
    return { follow_mouse = 1, middle_click_paste = true }
end

-- ── macOS (Cmd = Super) — skratky v aplikáciách (Cmd+C…) rieši neskôr xremap ──────
local function mac()
    bind("SUPER + Space", panel("launcher"))                                      -- Spotlight
    bind("SUPER + Tab", run("noctalia msg window-switcher"))                      -- Cmd+Tab (pusti Cmd = prepni)
    bind("SUPER + SHIFT + Tab", run("noctalia msg window-switcher"))
    bind("SUPER + grave", run("noctalia msg window-switcher"))                    -- Cmd+`
    bind("SUPER + Q", hl.dsp.window.close())
    bind("SUPER + W", hl.dsp.window.close())
    bind("SUPER + M", function() latte.win.minimize() end)
    bind("SUPER + H", function() latte.win.minimize() end)
    bind("SUPER + ALT + H", function() latte.keys.minimize_all(true) end)
    bind("SUPER + CTRL + Q", run("noctalia msg session lock"))
    bind("SUPER + ALT + Escape", run("latte-app monitor"))                        -- vynútiť ukončenie
    bind("SUPER + SHIFT + 3", run("latte-snimka ulozit"))
    bind("SUPER + SHIFT + 4", run("noctalia msg screenshot-region"))
    bind("SUPER + SHIFT + 5", run("noctalia msg screenshot-annotate"))
    bind("SUPER + SHIFT + 6", run("latte-nahravanie prepni"))                     -- nahrávanie (Cmd+Shift+5 na Macu ponúka aj video)
    bind("SUPER + CTRL + space", panel("launcher", "/emo"))
    bind("SUPER + CTRL + F", hl.dsp.window.fullscreen())
    bind("SUPER + comma", run("latte-app nastavenia"))
    -- Mission Control a Spaces (Ctrl+↑, Ctrl+←→) a F11 zatiaľ nie: na PC by vzali skok po slovách v texte
    -- a celú obrazovku v prehliadači. Prídu s premapovaním Cmd/Option (xremap); dovtedy gestá 3 a 4 prstami.
    bind("SUPER + CTRL + up", panel("latteos/overview:panel"))
    bind("SUPER + CTRL + left",  function() latte.keys.desk_step(-1) end)
    bind("SUPER + CTRL + right", function() latte.keys.desk_step(1) end)
    bind("SUPER + D", function() latte.keys.show_desktop() end)
    bind("SUPER + V", panel("latteos/kapsa:panel"))
    return { follow_mouse = 2, middle_click_paste = false }
end

-- „Zobraziť plochu“: prepne na prázdnu plochu a rovnakou skratkou späť (Win+D, F11 na Macu)
local desktop_from = nil
function latte.keys.show_desktop()
    local ws = hl.get_active_workspace()
    if desktop_from and ws and ws.id ~= desktop_from then
        hl.dispatch(hl.dsp.focus({ workspace = desktop_from }))
        desktop_from = nil
    else
        desktop_from = ws and ws.id or nil
        hl.dispatch(hl.dsp.focus({ workspace = "empty" }))
    end
end

-- stolný počítač (typ šasi zo SMBIOS) → Num Lock zapnutý; notebook nie (na starších stroj s vloženou numerickou
-- klávesnicou by zapnutý Num Lock menil písmená na čísla). Voľba v Nastaveniach prebije odhad: ~/.config/latteos/numlock (on/off)
local function numlock()
    local f = io.open(cfgdir .. "/numlock", "r")
    if f then local v = (f:read("*l") or ""):match("%a+"); f:close(); if v == "on" then return true elseif v == "off" then return false end end
    local c = io.open("/sys/class/dmi/id/chassis_type", "r")
    if not c then return false end
    local t = tonumber(c:read("*l") or "") or 0
    c:close()
    -- 3 Desktop, 4 Low Profile, 5 Pizza Box, 6 Mini Tower, 7 Tower, 13 All in One, 15 Space-saving, 16 Lunch Box,
    -- 17 Main Server, 23 Rack Mount, 24 Sealed-case PC, 35 Mini PC; VirtualBox hlási 1 (Other) → stolný
    local desk = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [13] = true, [15] = true,
                   [16] = true, [17] = true, [23] = true, [24] = true, [35] = true }
    return desk[t] == true
end

function K.setup()
    local p = K.profile()
    K.current = p
    common()
    local opts = (p == "linux" and linux) or (p == "mac" and mac) or windows
    local o = opts()
    hl.config({
        input = { follow_mouse = o.follow_mouse, numlock_by_default = numlock() },
        misc = { middle_click_paste = o.middle_click_paste },
    })
end

return K
