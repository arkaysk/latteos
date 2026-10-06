-- ChatGoo (doplnok pre Beeper, LATTEOS-GOO.md §4.6 — voliteľná): nie je to messenger, iba kvapka pre pôvodný Beeper.
-- Je na ploche, iba keď je Beeper nainštalovaný alebo beží. Okno Beepera nemá ikru v lište GooBar — patrí tejto
-- kvapke: ľavý klik ho ukáže, alebo schová do kvapky (minimalizácia), jadro svieti, kým je okno v kvapke.
-- Kvapka nesie pôvodnú ikonu Beepera (zo spúšťača aplikácií), nie vlastný znak.
-- Upozornenia Beepera idú sem namiesto ClockGoo: guľky = počet, pravý klik = karta správ (klik otvorí rozhovor,
-- pravý klik na správu = jej akcie). Pomocník: latte-chatgoo (stav, ukaz, skry, prepni).
local E = require("lib/engine")
local goobar = require("lib/goobar")
local installed, notes, seen = false, {}, {}
local icon, shown = "", nil          -- pôvodná ikona Beepera (zo spúšťača aplikácií alebo z pomocníka)
local was_min = false

local function state() return goobar.chat() end
local function paint(d)
    local c = state()
    d:pritomna(installed or c.running)
    -- kvapka nesie pôvodnú ikonu Beepera (používateľ 6. 10.); znak bubliny iba keď sa ikona nenájde
    local a = goobar.find_app("beeper")
    local want = (a and a.icon and a.icon ~= "") and a.icon or icon
    if want ~= shown then shown = want d:obrazok(want) end
    d:gulky(#notes, "softver")
    if c.running and c.minimized then d:jadro("softver", 0.8, false) else d:jadro() end
    if c.minimized and not was_min then d:vlnka(4) end              -- okno práve vtieklo do kvapky
    was_min = c.minimized
end
local function toggle() run("latte-chatgoo", { "prepni" }, function() if E.onWinMin then after(250, E.onWinMin) end end, { output = false }) end

local card
card = function(d, keep)
    local c = state()
    local items = { { hd = true, label = tr("MESSAGES"), hint = #notes > 0 and tostring(#notes) or "" } }
    if #notes == 0 then items[#items + 1] = { info = true, glyph = "message-circle", label = tr("No new messages") } end
    for i, x in ipairs(notes) do                                    -- služba ich dáva od najnovšej
        if i > 8 then
            items[#items + 1] = { info = true, glyph = "dots", label = "+" .. (#notes - 8) .. " " .. tr("more") }
            break
        end
        local acts = type(x.actions) == "table" and x.actions or {}
        items[#items + 1] = {
            img = (x.icon or "") ~= "" and x.icon or nil, glyph = "message-circle",
            label = (x.title or "") ~= "" and x.title or "Beeper", t2 = (tostring(x.body or ""):gsub("%s+", " ")),
            run = function()                                        -- klik = otvorí rozhovor (predvolená akcia upozornenia)
                pcall(sys.call, "notifications.invoke", x.id, "default")
                pcall(sys.call, "notifications.dismiss", x.id)
                run("latte-chatgoo", { "ukaz" }, nil, { output = false })
            end,
            right = function()
                local kids = { { label = tr("Back"), glyph = "chevron-left", keep = true, run = function() card(d, true) end } }
                for _, a in ipairs(acts) do
                    kids[#kids + 1] = { label = a.label or a.key or "", glyph = "chevron-right", sep = #kids == 1, run = function()
                        pcall(sys.call, "notifications.invoke", x.id, a.key)
                        pcall(sys.call, "notifications.dismiss", x.id)
                    end }
                end
                kids[#kids + 1] = { label = tr("Dismiss"), glyph = "x", sep = true, run = function() pcall(sys.call, "notifications.dismiss", x.id) end }
                E.menu(kids, 340, { id = "chat", owner = d })
            end }
    end
    local pills = { { glyph = "message-circle", run = toggle,
                      label = not c.running and tr("Open Beeper") or (c.minimized and tr("Show Beeper") or tr("Hide into the drop")) } }
    if #notes > 0 then
        pills[#pills + 1] = { glyph = "trash", label = tr("Clear all"), danger = true, keep = true, run = function()
            for _, x in ipairs(notes) do pcall(sys.call, "notifications.dismiss", x.id) end
        end }
    end
    items[#items + 1] = { sep = true, pills = pills }
    E.menu(items, 340, { id = "chat", owner = d, keep = keep })
end

return {
    id = "chatgoo", nazov = "ChatGoo", ikona = "message-circle", povaha = "pokojna", velkost = 24, vyska = 18,
    poloha = { x = 0.8, y = 18 }, gravitacia = 0.25,
    start = function(d)
        d:pritomna(false)                                           -- kým sa nevie, či Beeper je
        local function check()
            run("latte-chatgoo", { "stav" }, function(out)
                local ok, t = pcall(json.decode, out or "")
                installed = ok and type(t) == "table" and t.installed == true
                icon = ok and type(t) == "table" and type(t.icon) == "string" and t.icon or ""
                paint(d)
            end)
        end
        check()
        every(60000, check)                                         -- nainštalovaný / odinštalovaný
        every(1000, function() paint(d) end)                        -- beží, schovaný (z okien lišty GooBar)
        E.onNotes(function(list)
            notes = {}
            local fresh = false
            for _, x in ipairs(list) do
                if E.isChat(x) then
                    notes[#notes + 1] = x
                    if not seen[x.id] then seen[x.id] = true fresh = true end
                end
            end
            if fresh and not d.hidden then d:vlnka(5) end
            paint(d)
            if E.menuId() == "chat" then card(d, true) end
        end)
    end,
    klik = function(d) if E.menuId() == "chat" then fact.ctx_open = false end toggle() end,
    pravy = function(d) if E.menuId() == "chat" then fact.ctx_open = false else card(d) end end,
    popis = function(d)
        local c = state()
        local s = c.running and (c.minimized and tr("Beeper is in the drop") or tr("Beeper is open")) or tr("Beeper is not running")
        return (#notes > 0 and (#notes .. " " .. tr("messages") .. " · ") or "") .. s .. " · " .. tr("left: show or hide · right: messages")
    end,
}
