-- engine Goo — kvapky používateľa: JSON v ~/.config/latteos/goo/kvapky/*.json (latte-goo zoznam ich overí a vráti
-- naraz). Pridať, zmeniť alebo zmazať sa dajú kedykoľvek: zmena súborov sa prejaví do pár sekúnd, bez reštartu.
-- Akcie (príkazy, aplikácie, odkazy) vykoná latte-goo podľa id a mena akcie — logika nikdy neposiela príkaz sama.
--
-- {
--   "id": "kalkulacka", "nazov": "Kalkulačka", "ikona": "calculator", "povaha": "zvedava",
--   "popis": "Klik otvorí kalkulačku", "velkost": 26, "poloha": { "x": 0.3, "y": 0 },
--   "text": { "prikaz": "date +%H:%M", "kazdych": 30 },
--   "akcie": { "klik": { "aplikacia": "org.gnome.Calculator" }, "pravy": { "vystup": "uptime -p" },
--              "stredny": "domov", "podrz": { "otvor": "https://latteos.sk" }, "koliesko": "velkost" }
-- }
-- Akcia: { "spusti": "príkaz" } · { "aplikacia": "id.desktop" } · { "otvor": "súbor alebo adresa" }
--        · { "vystup": "príkaz" } (výstup v bubline) · "domov" · "velkost" · "poskoc" · "vlnka" · "vibracia" · "nic"
-- Jadro: "jadro": "siet" (stále) alebo "upozornenie": { "prikaz": "…", "kazdych": s } — výstup príkazu je farba
--   (hardver, siet, softver, vystraha, svetlo, ine), prázdny = zhasne; nové upozornenie zvlní hladinu
local M = {}
local known = {}          -- id → podpis definície (zmena = nová registrácia)

local ACTIONS = { klik = "klik", pravy = "pravy", stredny = "stredny", podrz = "podrz" }

local function action(E, d, key)
    local a = d.def.akcie and d.def.akcie[key]
    if a == nil then return false end
    if a == "domov" then d:domov() return true end
    if a == "velkost" then return false end              -- koliesko: predvolené správanie enginu
    if a == "poskoc" then d:poskoc() return true end
    if a == "vlnka" then d:vlnka() return true end
    if a == "vibracia" then d:vibruj() return true end
    if a == "nic" then return true end
    run("latte-goo", { "akcia", d.id, key }, function(out, code)
        if out and out ~= "" then d:bublina(out:gsub("%s+$", "")) end
        if code ~= 0 then log("goo: akcia " .. d.id .. "." .. key .. " skončila s " .. tostring(code)) end
    end)
    return true
end

local function refreshText(d)
    run("latte-goo", { "text", d.id }, function(out)
        if out then d:text((out:gsub("%s+$", ""))) end
    end)
end

local function checkNotice(d)
    run("latte-goo", { "upozornenie", d.id }, function(out)
        local f = (out or ""):match("[%w]+")
        if f and not d.notice then d:vlnka(5) end
        d.notice = f
        if f then d:jadro(f, 1, true) else d:jadro(d.def.jadro) end
    end)
end

local function build(E, j)
    local def = {}
    for k, v in pairs(j) do def[k] = v end
    def.text = type(j.text) == "string" and j.text or ""
    for key in pairs(ACTIONS) do
        if j.akcie and j.akcie[key] ~= nil then def[key] = function(d) action(E, d, key) end end
    end
    local wheel = j.akcie and j.akcie.koliesko
    def.zoom = wheel == "velkost"                         -- veľkosť kolieskom iba keď ju kvapka chce (pravidlo 8)
    if type(wheel) == "table" then
        def.koliesko = function(d, dir) action(E, d, dir > 0 and "hore" or "dole") end
    end
    if type(j.text) == "table" and j.text.prikaz then
        def.kazdych = math.max(2, tonumber(j.text.kazdych) or 60) * 1000
        def.tik = refreshText
    end
    if type(j.jadro) == "string" then def.start = function(d) d:jadro(j.jadro, 0.8, false) end end
    if type(j.upozornenie) == "table" and j.upozornenie.prikaz then
        local textTik = def.tik
        local every_ = math.max(2, tonumber(j.upozornenie.kazdych) or 30) * 1000
        local base = def.start
        def.start = function(d)
            if base then base(d) end
            checkNotice(d)
            d.noticeTimer = every(every_, function() checkNotice(d) end)
        end
        def.tik = textTik
    end
    return def
end

local function load(E, opts)
    local args = { "zoznam" }
    if opts.priklady then table.insert(args, "--priklady") end
    run("latte-goo", args, function(out)
        local ok, list = pcall(json.decode, out or "")
        if not ok or type(list) ~= "table" then return end
        local seen = {}
        for _, j in ipairs(list) do
            if type(j) == "table" and type(j.id) == "string" then
                if j.chyba then
                    log("goo: " .. tostring(j.zdroj) .. ": " .. j.chyba)
                else
                    seen[j.id] = true
                    local sig = json.encode(j)
                    if known[j.id] ~= sig then
                        known[j.id] = sig
                        E.define(build(E, j), "json")
                    end
                end
            end
        end
        for id in pairs(known) do
            if not seen[id] then known[id] = nil E.remove(id) end
        end
    end)
end

function M.start(E, opts)
    load(E, opts)
    every(4000, function() load(E, opts) end)
end

return M
