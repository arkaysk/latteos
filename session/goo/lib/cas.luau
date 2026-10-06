-- lib/cas.luau — čas pre kartu ClockGoo: stopky, minútka a budíky, digitálna pohoda, svetové hodiny.
-- Prevzaté z časového menu plochy Kvapky (kvapka.luau): tie isté údaje a ten istý súbor
-- ~/.local/share/latteos/casovace.json (zápis `latte-kvapky uloz casovace`), takže stopky pustené v jednej ploche
-- bežia aj v druhej. Čítanie a zvonenie robí `latte-goo` (logika nevie súbory ani zvuk).
-- Minútku a budíky STRÁŽI táto logika (M.guard, každú sekundu) — aj keď je karta zatvorená.
local M = { alh = 7, alm = 0, pohoda = { spolu = 0, aplikacie = {} }, pasma = {} }
local data, epoch, c0 = nil, nil, 0

function M.now()
    if epoch then return epoch + math.floor((os.clock() - c0) * 1000) end
    return os.time() * 1000
end
function M.fmt(ms, tenths)
    ms = math.max(0, math.floor(ms))
    local s = ms // 1000
    local h, m, sec = s // 3600, (s // 60) % 60, s % 60
    local out = h > 0 and string.format("%d:%02d:%02d", h, m, sec) or string.format("%02d:%02d", m, sec)
    if tenths then out = out .. "," .. tostring((ms // 100) % 10) end
    return out
end
function M.dur(s)
    s = math.floor(s or 0)
    local h, m = s // 3600, (s % 3600) // 60
    if h > 0 then return string.format("%d h %02d min", h, m) end
    return string.format("%d min", m)
end
function M.timers()
    local t = data or {}
    t.sw = t.sw or { running = false, start = 0, acc = 0, laps = {} }
    t.sw.laps = t.sw.laps or {}
    t.timer = t.timer or { endMs = 0, durMs = 5 * 60000, left = 0 }
    t.alarms = t.alarms or {}
    data = t
    return t
end
function M.save() run("latte-kvapky", { "uloz", "casovace", json.encode(M.timers()) }, nil, { output = false }) end
function M.load(done)
    run("latte-goo", { "cas" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then
            if tonumber(t.teraz) then epoch, c0 = tonumber(t.teraz), os.clock() end
            data = type(t.casovace) == "table" and t.casovace or {}
            if type(t.pohoda) == "table" then M.pohoda = t.pohoda end
            if type(t.pasma) == "table" then M.pasma = t.pasma end
        end
        M.timers()
        if done then done() end
    end)
end

-- stopky
function M.elapsed()
    local sw = M.timers().sw
    return (sw.acc or 0) + ((sw.running and (sw.start or 0) > 0) and (M.now() - sw.start) or 0)
end
function M.sw_toggle()
    local sw = M.timers().sw
    if sw.running then sw.acc = M.elapsed() sw.running = false else sw.start = M.now() sw.running = true end
    M.save()
end
function M.sw_lap()
    local sw = M.timers().sw
    if sw.running then table.insert(sw.laps, 1, M.elapsed()) M.save() end
end
function M.sw_reset() M.timers().sw = { running = false, start = 0, acc = 0, laps = {} } M.save() end

-- minútka: beží (endMs), stojí (left), alebo čaká s dĺžkou durMs
function M.timer_state()
    local tim = M.timers().timer
    local running = (tim.endMs or 0) > 0
    local left = running and (tim.endMs - M.now()) or (tim.left or 0)
    local active = running or (tim.left or 0) > 0
    return running, active, math.max(0, left), tim.durMs or 300000
end
function M.timer_toggle()
    local tim = M.timers().timer
    if (tim.endMs or 0) > 0 then tim.left = tim.endMs - M.now() tim.endMs = 0
    elseif (tim.left or 0) > 0 then tim.endMs = M.now() + tim.left tim.left = 0
    else tim.endMs = M.now() + (tim.durMs or 300000) tim.left = 0 end
    M.save()
end
function M.timer_cancel() local tim = M.timers().timer tim.endMs, tim.left = 0, 0 M.save() end
function M.timer_start(minutes)
    local tim = M.timers().timer
    tim.durMs = minutes * 60000
    tim.endMs, tim.left = M.now() + tim.durMs, 0
    M.save()
end
function M.timer_adjust(dir)                                -- koliesko: iba keď nebeží ani nestojí
    local tim = M.timers().timer
    if (tim.endMs or 0) > 0 or (tim.left or 0) > 0 then return end
    local m = math.floor((tim.durMs or 300000) / 60000 + 0.5) + dir
    tim.durMs = math.max(1, math.min(180, m)) * 60000
    M.save()
end

-- budíky
function M.alarm_add()
    local al = M.timers().alarms
    if #al >= 10 then return end
    table.insert(al, { time = string.format("%02d:%02d", M.alh, M.alm), label = "", on = true, last = "" })
    table.sort(al, function(a, b) return a.time < b.time end)
    M.save()
end
function M.alarm_toggle(i)
    local a = M.timers().alarms[i]
    if a then a.on = not a.on a.last = "" M.save() end
end
function M.alarm_prune()                                    -- odstráni vypnuté
    local t = M.timers()
    local keep = {}
    for _, a in ipairs(t.alarms) do if a.on then keep[#keep + 1] = a end end
    t.alarms = keep
    M.save()
end
function M.next_alarm()
    local hm, nxt = os.date("%H:%M"), nil
    for _, a in ipairs(M.timers().alarms) do
        if a.on and (not nxt or ((a.time > hm) and (nxt.time <= hm or a.time < nxt.time))) then nxt = a end
    end
    return nxt
end

-- stráženie: minútka a budíky zvonia, aj keď je karta zatvorená; `changed()` po zmene (prekreslenie)
function M.guard(changed)
    every(1000, function()
        if not data then return end
        local tm, ch = M.timers(), false
        if (tm.timer.endMs or 0) > 0 and tm.timer.endMs - M.now() <= 0 then
            tm.timer.endMs = 0
            ch = true
            run("latte-goo", { "zvon", tr("Timer"), tr("Time is up") .. " (" .. M.fmt(tm.timer.durMs) .. ")" }, nil, { output = false })
        end
        local hm, today = os.date("%H:%M"), os.date("%Y-%m-%d")
        for _, a in ipairs(tm.alarms) do
            if a.on and a.time == hm and a.last ~= today then
                a.last = today
                ch = true
                run("latte-goo", { "zvon", tr("Alarm") .. " " .. hm, (a.label or "") ~= "" and a.label or tr("LatteOS alarm") }, nil, { output = false })
                if a.once then a.on = false end
            end
        end
        if ch then M.save() if changed then changed() end end
    end)
    -- súbor môže zmeniť aj iná plocha (Kvapky): raz za minútu znova
    every(60000, function() M.load() end)
end

return M
