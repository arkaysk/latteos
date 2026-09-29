-- latte/snap.lua — rozloženia okna ako vo Windows 11: polovice, štvrtiny, tretiny, stred, celá.
-- Aktívne okno sa uvoľní (pláva) a presunie do zvolenej časti obrazovky bez lišty (reserved area).
-- Volá ho panel „Rozloženie okna“ (Win+Z), Win+←→ a prichytenie ťahaním k okraju (latte/prichytenie.lua).
-- Pôvodnú polohu a veľkosť si pamätá: Win+↓ alebo odtiahnutie prichyteného okna ho vráti (ako Windows).
local S = {}

local GAP = 10
-- časti obrazovky ako zlomky pracovnej plochy: { x, y, šírka, výška }
S.layouts = {
    lava   = { 0, 0, 1/2, 1 },     prava = { 1/2, 0, 1/2, 1 },
    hore   = { 0, 0, 1, 1/2 },     dole  = { 0, 1/2, 1, 1/2 },
    lh     = { 0, 0, 1/2, 1/2 },   ph    = { 1/2, 0, 1/2, 1/2 },
    ld     = { 0, 1/2, 1/2, 1/2 }, pd    = { 1/2, 1/2, 1/2, 1/2 },
    l23    = { 0, 0, 2/3, 1 },     p13   = { 2/3, 0, 1/3, 1 },
    l13    = { 0, 0, 1/3, 1 },     p23   = { 1/3, 0, 2/3, 1 },
    stred  = { 0.15, 0.1, 0.7, 0.8 },
    cela   = { 0, 0, 1, 1 },
}
S.saved = {}          -- adresa okna → { x, y, w, h, zone } pred prichytením

local function xy(v) if type(v) == "table" then return (v.x or v[1] or 0), (v.y or v[2] or 0) end return 0, 0 end
S.xy = xy

--- pracovná plocha monitora (bez lišty) v logických súradniciach
function S.area(m)
    local scale = m.scale or 1
    local r = m.reserved or { top = 0, right = 0, bottom = 0, left = 0 }
    return { x = m.x + r.left, y = m.y + r.top, w = m.width / scale - r.left - r.right, h = m.height / scale - r.top - r.bottom }
end

--- obdĺžnik rozloženia na monitore (s medzerami ako maximalizované okno)
function S.rect(name, m)
    local l = S.layouts[name]
    if not l or not m then return nil end
    local a = S.area(m)
    local ax, ay, aw, ah = a.x + GAP, a.y + GAP, a.w - 2 * GAP, a.h - 2 * GAP
    return {
        x = math.floor(ax + l[1] * aw + (l[1] > 0 and GAP / 2 or 0)),
        y = math.floor(ay + l[2] * ah + (l[2] > 0 and GAP / 2 or 0)),
        w = math.floor(l[3] * aw - ((l[1] > 0 or l[1] + l[3] < 1) and GAP / 2 or 0)),
        h = math.floor(l[4] * ah - ((l[2] > 0 or l[2] + l[4] < 1) and GAP / 2 or 0)),
    }
end

local function place(w, r)
    local sel = "address:" .. w.address
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = sel })) end
    hl.dispatch(hl.dsp.window.resize({ x = r.w, y = r.h, window = sel }))
    hl.dispatch(hl.dsp.window.move({ x = r.x, y = r.y, window = sel }))
end

function S.apply(name, w, m)
    w = w or hl.get_active_window()
    if not w or not S.layouts[name] then return end
    m = m or w.monitor or hl.get_active_monitor()
    local r = S.rect(name, m)
    if not r then return end
    if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = "address:" .. w.address })) end
    if not S.saved[w.address] then
        local x, y = xy(w.at)
        local ww, wh = xy(w.size)
        S.saved[w.address] = { x = x, y = y, w = ww, h = wh }
    end
    S.saved[w.address].zone = name
    place(w, r)
end

function S.is_snapped(w) return w and S.saved[w.address] ~= nil and S.saved[w.address].zone ~= nil end

--- vráti okno na pôvodnú veľkosť; s cursor (x, y) ho položí pod kurzor v rovnakom pomere ako Windows pri odtiahnutí
function S.restore(w, cx, cy)
    local s = w and S.saved[w.address]
    if not s then return end
    S.saved[w.address] = nil
    local r = { x = s.x, y = s.y, w = s.w, h = s.h }
    if cx then
        local x, _ = xy(w.at)
        local ww, _ = xy(w.size)
        local ratio = ww > 0 and (cx - x) / ww or 0.5
        r.x = math.floor(cx - r.w * math.max(0, math.min(1, ratio)))
        r.y = math.floor(cy - 15)               -- kurzor ostane v titulku
    end
    place(w, r)
end

hl.on("window.close", function(w) if w then S.saved[w.address] = nil end end)

return S
