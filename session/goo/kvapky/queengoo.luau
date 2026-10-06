-- QueenGoo (App Manager a Správca zariadení, LATTEOS-GOO.md §4.4 — voliteľná): ikona aplikácií, guľky podľa pravidla 15 — červená = zariadenia, ktoré
-- potrebujú pozornosť (latte-devices list › faults), zelená = výpadok siete, modrá = čakajúce aktualizácie
-- (latte-apps updates). Ľavý klik = App Manager (pri aktualizáciách rovno na nich), pravý = Správca zariadení (pri
-- výpadku siete na Sieťach). Riadne okná sa rodia z bubliny (pravidlo 14): kráľovná ostane na mieste, vypľuje bublinu,
-- tá preletí vedľa nej a nafúkne sa na okno; zatvorené okno praskne. Ak je okno už otvorené, iba sa ukáže.
local E = require("lib/engine")
local goobar = require("lib/goobar")
local WIN = { aplikacie = { title = "Aplikácie — LatteOS", w = 1220, h = 780 }, zariadenia = { title = "Správca zariadení — LatteOS", w = 1100, h = 780 } }
local faults, offline, updates = 0, false, 0
local born = {}

local function paint(d)
    local cols = {}
    if faults > 0 then cols[#cols + 1] = "hardver" end
    if offline then cols[#cols + 1] = "siet" end
    if updates > 0 then cols[#cols + 1] = "softver" end
    d:gulky(#cols, cols)
end

local function open(d, app)
    local q = WIN[app]
    for _, w in ipairs(goobar.wins()) do
        if w.title == q.title then run("hyprctl", { "eval", "latte.win.focus_by('org.quickshell', '" .. q.title .. "')" }) return end
    end
    -- okno vedľa kráľovnej, celé na obrazovke (Hyprland ho tam postaví, latte/windows.lua)
    local W, H = tonumber(fact.sw) or 1920, tonumber(fact.sh) or 1080
    local w, h = math.min(q.w, W - 32), math.min(q.h, H - 32)
    local x = math.max(16, math.min(W - 16 - w, d:px() - w / 2))
    local y = math.max(16, H - d.y - 70 - h)
    local args = { app }
    if app == "aplikacie" and updates > 0 then args[2] = "aktualizacie" end
    if app == "zariadenia" and offline then args[2] = "siete" end
    -- pravidlo 14: kráľovná ostane na mieste a vypľuje bublinu, tá preletí na miesto okna a nafúkne sa naň; program
    -- sa spustí o 650 ms neskôr a Hyprland okno postaví presne na bublinu (latte-kvapky okno), bez vlastnej animácie
    E.bubble(d, x + w / 2, y + h / 2, w, h)
    born[q.title] = { x = x + w / 2, y = y + h / 2, r = math.min(w, h) * 0.42, seen = false, t = os.clock() }
    after(650, function()
        run("latte-kvapky", { "okno", q.title, tostring(math.floor(x)), tostring(math.floor(y)), tostring(w), tostring(h) }, function()
            run("latte-app", args)
        end)
    end)
end
-- okná, ktoré sa zrodili z bubliny: keď naskočia, bublina zmizne; keď ich niekto zavrie, bublina praskne
local function watch_born()
    for title, b in pairs(born) do
        local present = false
        for _, w in ipairs(goobar.wins()) do if w.title == title then present = true end end
        if present and not b.seen then b.seen = true E.bubbleDone()
        elseif not present and b.seen then E.pop(b.x, b.y, b.r) born[title] = nil
        elseif not b.seen and os.clock() - b.t > 8 then E.bubbleDone() born[title] = nil end      -- okno neprišlo
    end
end

return {
    id = "queengoo", nazov = "QueenGoo", koruna = "crown", ikona = "apps", povaha = "pokojna", velkost = 26, vyska = 18,
    poloha = { x = 0.86, y = 18 }, gravitacia = 0.25,
    start = function(d)
        local function devices()
            run("latte-devices", { "list" }, function(out)
                local ok, t = pcall(json.decode, out or "")
                if ok and type(t) == "table" then faults = type(t.faults) == "table" and #t.faults or 0 paint(d) end
            end)
        end
        local function upd()
            run("latte-apps", { "updates" }, function(out)
                local ok, t = pcall(json.decode, out or "")
                if ok and type(t) == "table" then updates = #t paint(d) end
            end)
        end
        devices() upd()
        every(250, watch_born)
        every(60000, devices)
        every(30 * 60000, upd)
    end,
    klik = function(d) open(d, "aplikacie") end,
    pravy = function(d) open(d, "zariadenia") end,
    popis = function(d)
        local t = {}
        if faults > 0 then t[#t + 1] = faults .. " " .. tr("devices need attention") end
        if offline then t[#t + 1] = tr("offline") end
        if updates > 0 then t[#t + 1] = updates .. " " .. tr("updates") end
        return #t > 0 and table.concat(t, " · ") or tr("left: App Manager · right: Device Manager")
    end,
}
