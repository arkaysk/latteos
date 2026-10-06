-- Hodiny: čas v kvapke, prstenec = minúty v hodine; každých 10 s príkaz `date` (scéna ho má v povoleniach)
return {
    id = "hodiny", nazov = "Hodiny", druh = "ukazovatel", povaha = "pokojna", velkost = 32,
    kazdych = 10000,
    tik = function(d)
        run("date", { "+%H:%M %M" }, function(out)
            local hm, m = (out or ""):match("(%d+:%d+) (%d+)")
            if hm then d:text(hm) d:hodnota(tonumber(m) / 60) end
        end)
    end,
    popis = function(d)
        return "čas · prstenec = minúty v hodine"
    end,
}
