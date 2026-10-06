-- lib/spustac.luau — okno spúšťača LensGoo (LATTEOS-GOO.md §4.3): hľadanie, spúšťač a AI v karte Goo.
-- Režimy (záložky hore; koliesko nad nimi alebo Tab prepína; pamätá sa v spustac.json — spoločné s plochou Kvapky):
--   Aplikácie  bez textu obľúbené a nedávne, s textom hľadanie aplikácií, kalkulačka a prevody, stránky Nastavení
--              a rýchle prepnutie do iných režimov; pravý klik = akcie aplikácie (Nové okno…)
--   Súbory     bez textu domovské priečinky, s textom latte-hladaj (index + čerstvé súbory, filtre v texte);
--              klik otvorí súbor, pravý klik priečinok so súborom
--   Web        adresa, vyhľadávače (predvolený prvý), návrhy počas písania
--   Terminál   príkaz v latte-terminal; nebezpečný príkaz chce druhý Enter; história a dopĺňanie
--   AI         rozhovor priamo v karte v goo bublinách cez latte-ai (nikdy neotvára prehliadač), odpoveď po riadkoch
-- Enter = prvý riadok. Myš prvá: všetko sa dá klikom; klávesnica je na písanie.
-- Prevzaté zo spúšťača plochy Kvapky (kvapka.luau); pomocníci latte-riadok, latte-hladaj, latte-ai sú tie isté.
local E = require("lib/engine")
local M = {}

local W = 540
local apps, byId = {}, {}
local cfg = {}
local mode = 1                        -- 0 AI, 1 aplikácie, 2 súbory, 3 web, 4 príkaz (poradie ako v Kvapkách: kľúč mode)
local q = ""
local gen = 0                         -- poradové číslo dotazu: staršie odpovede pomocníkov sa zahodia
local extra = {}                      -- doplnky riadkov z pomocníkov (kalkulačka, nastavenia, súbory, návrhy, dopĺňanie)
local chat, busy, job, status = {}, false, nil, ""
local confirm = nil                   -- nebezpečný príkaz čaká na druhý Enter
local lastItems, lastOpts = nil, nil
local render

local ORDER = { 1, 2, 3, 4, 0 }       -- záložky v poradí architektúry: Aplikácie, Súbory, Web, Terminál, AI
local MODES = {
    [0] = { glyph = "sparkles", name = "AI", hint = "Ask AI anything…" },
    [1] = { glyph = "search", name = "Applications", hint = "Search apps…" },
    [2] = { glyph = "folder", name = "Files", hint = "Search files…" },
    [3] = { glyph = "world", name = "Web", hint = "Search the web…" },
    [4] = { glyph = "terminal-2", name = "Terminal", hint = "Run a command…" },
}
local ENGINES = {
    { id = "google", name = "Google", url = "https://www.google.com/search?q=%s" },
    { id = "bing", name = "Bing", url = "https://www.bing.com/search?q=%s" },
    { id = "duckduckgo", name = "DuckDuckGo", url = "https://duckduckgo.com/?q=%s" },
    { id = "startpage", name = "Startpage", url = "https://www.startpage.com/do/search?q=%s" },
    { id = "ecosia", name = "Ecosia", url = "https://www.ecosia.org/search?q=%s" },
    { id = "brave", name = "Brave Search", url = "https://search.brave.com/search?q=%s" },
}

-- ── pomôcky ──────────────────────────────────────────────────────────────────────────────────────────────────
local BEZ = { ["á"] = "a", ["ä"] = "a", ["č"] = "c", ["ď"] = "d", ["é"] = "e", ["ě"] = "e", ["í"] = "i", ["ĺ"] = "l", ["ľ"] = "l",
              ["ň"] = "n", ["ó"] = "o", ["ô"] = "o", ["ö"] = "o", ["ŕ"] = "r", ["ř"] = "r", ["š"] = "s", ["ť"] = "t", ["ú"] = "u",
              ["ů"] = "u", ["ü"] = "u", ["ý"] = "y", ["ž"] = "z",
              ["Á"] = "a", ["Ä"] = "a", ["Č"] = "c", ["Ď"] = "d", ["É"] = "e", ["Ě"] = "e", ["Í"] = "i", ["Ĺ"] = "l", ["Ľ"] = "l",
              ["Ň"] = "n", ["Ó"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Ŕ"] = "r", ["Ř"] = "r", ["Š"] = "s", ["Ť"] = "t", ["Ú"] = "u",
              ["Ů"] = "u", ["Ü"] = "u", ["Ý"] = "y", ["Ž"] = "z" }
local function fold(s) return (tostring(s or ""):gsub("[\xC3-\xC5][\x80-\xBF]", BEZ):lower()) end
local function urlencode(s) return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end)) end
local function lines(out) local t = {} for l in (out or ""):gmatch("[^\n]+") do t[#t + 1] = l end return t end
local function close() fact.ctx_open = false end

-- nebezpečné príkazy chcú druhý Enter (zoznam z Text Baru klasického LatteOS, ako v Kvapkách)
local DANGER_WORDS = {
    sudo = true, pkexec = true, su = true, doas = true,
    rm = true, rmdir = true, shred = true, truncate = true, srm = true, unlink = true,
    dd = true, wipefs = true, fdisk = true, sfdisk = true, parted = true, blkdiscard = true,
    kill = true, killall = true, pkill = true, poweroff = true, reboot = true, shutdown = true, halt = true,
}
local DANGER = {
    "mkfs", "%-delete", "chmod%s+%-[%a]*R", "chown%s+%-[%a]*R",
    ">%s*/dev/[sn]", ">%s*/etc/", ">%s*/boot/", ">%s*/usr/",
    "%f[%w]mv%s.-%s/[%a]*%s*$",
    "dnf%s+remove", "dnf%s+erase", "dnf%s+autoremove", "rpm%s+%-e", "flatpak%s+uninstall", "flatpak%s+remove",
    "systemctl%s+stop", "systemctl%s+disable", "systemctl%s+mask", "systemctl%s+poweroff", "systemctl%s+reboot",
    "git%s+reset%s+%-%-hard", "git%s+clean%s", "git%s+push%s.-%-%-force", "git%s+push%s.-%-f%f[%W]",
    "|%s*s?h%f[%W]", "|%s*bash", "|%s*zsh", ":%(%)%s*{",
}
local function dangerous(cmd)
    for seg in string.gmatch(cmd .. ";", "(.-)[;&|`(\n]") do
        local w = string.match(seg, "^[%s$]*([%w%._/%-]+)")
        if w then
            w = string.match(w, "([^/]+)$")
            if DANGER_WORDS[w] or string.find(w, "^mkfs") then return true end
        end
    end
    for _, p in ipairs(DANGER) do if string.find(cmd, p) then return true end end
    return false
end

-- ── akcie ────────────────────────────────────────────────────────────────────────────────────────────────────
local function launch(a)
    if not a then return end
    if a.exec then pcall(sys.call, "apps.launch", a.exec) end
    if a.id then
        run("latte-riadok", { "zaznam", a.id }, nil, { output = false })       -- časté aplikácie podľa dennej doby
        local rec = { a.id }
        for _, id in ipairs(cfg.recent or {}) do if id ~= a.id and #rec < 8 then rec[#rec + 1] = id end end
        cfg.recent = rec
        run("latte-goo", { "spustac-uloz", "recent", json.encode(rec) }, nil, { output = false })
    end
    close()
end
local function open_url(url) run("xdg-open", { url }, nil, { output = false }) close() end
local function search_web(e, text) open_url(string.format(e.url, urlencode(text))) end
local function engine()
    for _, e in ipairs(ENGINES) do if e.id == cfg.engine then return e end end
    return ENGINES[1]
end
local function run_cmd(cmd)
    local hist = { cmd }
    for _, c in ipairs(cfg.cmds or {}) do if c ~= cmd and #hist < 12 then hist[#hist + 1] = c end end
    cfg.cmds = hist
    run("latte-goo", { "spustac-uloz", "cmds", json.encode(hist) }, nil, { output = false })
    -- terminál po príkaze OSTANE otvorený (používateľ 5. 10.): za príkazom beží bežný shell, dá sa pokračovať
    run("latte-terminal", { "sh", "-c", cmd .. '; exec "${SHELL:-/bin/bash}"' }, nil, { output = false })
    close()
end
local function set_mode(m, keep_text)
    if mode == m then return end
    mode, confirm, extra = m, nil, {}
    if not keep_text then q = "" E.menuText("") end
    run("latte-goo", { "spustac-uloz", "mode", tostring(m) }, nil, { output = false })
    M.query()
end
local function ask_ai(text)
    if busy then return end
    chat[#chat + 1] = { role = "user", content = text }
    local msgs = {}
    for _, m in ipairs(chat) do msgs[#msgs + 1] = { role = m.role, content = m.content } end
    local answer = { role = "assistant", content = "…" }
    chat[#chat + 1] = answer
    busy = true
    render(true)
    local got, last = {}, 0
    job = spawn("latte-ai", { "chat", json.encode(msgs) }, function(line)
        got[#got + 1] = line
        answer.content = table.concat(got, "\n")
        local now = os.clock()
        if now - last > 0.25 and E.menuId() == "lens" and mode == 0 then last = now render(true) end      -- odpoveď po riadkoch
    end, function()
        busy, job = false, nil
        if #got == 0 then answer.content = tr("No answer (check Settings › AI)") end
        if E.menuId() == "lens" and mode == 0 then render(true) end
    end)
end

-- ── riadky podľa režimu ──────────────────────────────────────────────────────────────────────────────────────
local function app_row(a, hint)
    return { img = a.icon, glyph = "apps", label = a.name or a.id, hint = hint, run = function() launch(a) end,
             right = function()
                 run("latte-riadok", { "akcie", a.id }, function(out)
                     if E.menuId() ~= "lens" then return end
                     local kids = { { label = tr("Back"), glyph = "chevron-left", back = lastItems },
                                    { sep = true, img = a.icon, glyph = "apps", label = tr("Open") .. " " .. (a.name or ""), run = function() launch(a) end } }
                     for _, l in ipairs(lines(out)) do
                         local name, cmd = l:match("^([^\t]+)\t(.+)$")
                         if name then kids[#kids + 1] = { glyph = "chevron-right", label = name, run = function() pcall(sys.call, "apps.launch", cmd) close() end } end
                     end
                     local o = {} for k, v in pairs(lastOpts or {}) do o[k] = v end
                     o.id, o.keep, o.parent = nil, nil, lastOpts
                     E.menu(kids, W, o)
                 end)
             end }
end
local function rows_apps()
    local items = {}
    if q == "" then
        -- MRIEŽKA (bez textu): obľúbené a naposledy spustené ako dlaždice, 6 v rade; pravý klik = akcie aplikácie.
        -- Karta má najviac 24 prvkov (model ctx): pole + 2 nadpisy + 21 dlaždíc.
        local seen = {}
        local function tiles(ids, max)
            local t = {}
            for _, id in ipairs(ids) do
                local a = byId[id]
                if a and not seen[id] and #t < max then seen[id] = true t[#t + 1] = app_row(a) end
            end
            return t
        end
        local fav = tiles(((cfg.tabs or {})[1] or {}).apps or {}, 12)
        local room = #fav > 6 and 6 or 12
        local rec = tiles(cfg.recent or {}, room)
        for _, t in ipairs(tiles(extra.caste or {}, room - #rec)) do rec[#rec + 1] = t end   -- doplnok: časté v túto dennú dobu
        if #fav > 0 then
            items[#items + 1] = { hd = true, label = tr("FAVOURITES") }
            items[#items + 1] = { tiles = fav, per = 6 }
        end
        if #rec > 0 then
            items[#items + 1] = { hd = true, sep = #fav > 0, label = tr("RECENTLY USED") }
            items[#items + 1] = { tiles = rec, per = 6 }
        end
        if #items == 0 then
            local first = {}
            for i = 1, math.min(18, #apps) do first[#first + 1] = apps[i].id end
            items[#items + 1] = { hd = true, label = tr("APPLICATIONS") }
            items[#items + 1] = { tiles = tiles(first, 18), per = 6 }
        end
        return items
    end
    if extra.calc then
        items[#items + 1] = { glyph = "calculator", label = extra.calc.value, hint = extra.calc.desc .. "  ·  " .. tr("click copies"),
                              run = function() pcall(sys.call, "clipboard.set", (extra.calc.value:gsub("%s[%a°]+$", ""):gsub(" ", ""))) close() end }
    end
    local fq, scored = fold(q), {}
    for _, a in ipairs(apps) do
        local name = fold(a.name)
        local at = name:find(fq, 1, true)
        local s = at == 1 and 3 or (at and name:sub(at - 1, at - 1):match("[%s%-_]") and 2) or (at and 1) or (fold(a.id):find(fq, 1, true) and 0.5) or 0
        if s > 0 then scored[#scored + 1] = { a = a, s = s } end
    end
    table.sort(scored, function(x, y) if x.s ~= y.s then return x.s > y.s end return (x.a.name or "") < (y.a.name or "") end)
    -- ZDROJ VÝSLEDKU: značka vpravo hovorí, odkiaľ riadok je (Aplikácia / Nastavenia / Súbor / Priečinok / Web)
    for i = 1, math.min(7, #scored) do items[#items + 1] = app_row(scored[i].a, tr("App")) end
    for i, st in ipairs(extra.settings or {}) do
        if i > 3 then break end
        items[#items + 1] = { glyph = "settings", label = st.name, hint = tr("Settings"), run = function() run("latte-app", { "nastavenia", st.page }, nil, { output = false }) close() end }
    end
    for i, r in ipairs(extra.afiles or {}) do                       -- pár súborov rovno medzi výsledkami (viac v režime Súbory)
        if i > 3 then break end
        local name = r.path:match("([^/]+)/?$") or r.path
        items[#items + 1] = { glyph = r.dir and "folder" or "file", label = name, hint = r.dir and tr("Folder") or tr("File"),
                              run = function()
                                  run("xdg-open", { r.path }, nil, { output = false })
                                  run("latte-hladaj", { "--otvorene", r.path }, nil, { output = false })
                                  close()
                              end,
                              right = function() run("latte-app", { "subory", r.path }, nil, { output = false }) close() end }
    end
    -- rýchle prepnutie do iných režimov s tým istým textom
    local text = q
    items[#items + 1] = { sep = true, keep = true, glyph = "folder", label = tr("Search files") .. ": " .. text, run = function() set_mode(2, true) end }
    items[#items + 1] = { glyph = "world", label = tr("Search the web") .. ": " .. text, hint = tr("Web"), run = function() search_web(engine(), text) end }
    items[#items + 1] = { keep = true, glyph = "sparkles", label = tr("Ask AI") .. ": " .. text, run = function() set_mode(0) ask_ai(text) end }
    return items
end
local function rows_files()
    local items = {}
    if q == "" then
        for _, f in ipairs(cfg._priecinky or {}) do
            items[#items + 1] = { glyph = f.glyph or "folder", label = tr(f.name), hint = f.kratko or "", run = function() run("latte-app", { "subory", f.path }, nil, { output = false }) close() end }
        end
        return items
    end
    for i, r in ipairs(extra.files or {}) do
        if i > 10 then break end
        local name = r.path:match("([^/]+)/?$") or r.path
        local dir = (r.path:gsub("/[^/]*/?$", ""))
        items[#items + 1] = { glyph = r.dir and "folder" or "file", label = name, hint = (dir:gsub("^" .. (cfg._domov or "~"):gsub("%p", "%%%0"), "~")),
                              run = function()
                                  run("xdg-open", { r.path }, nil, { output = false })
                                  run("latte-hladaj", { "--otvorene", r.path }, nil, { output = false })
                                  close()
                              end,
                              right = function() run("latte-app", { "subory", r.path }, nil, { output = false }) close() end }
    end
    if #items == 0 then items[1] = { info = true, glyph = "folder-search", label = extra.files and tr("Nothing found") or tr("Searching…") } end
    return items
end
local function rows_web()
    local items = {}
    if q == "" then
        for _, e in ipairs(ENGINES) do items[#items + 1] = { info = true, glyph = "world", label = e.name, hint = e.id == engine().id and tr("default") or "" } end
        return items
    end
    local text = q
    if text:match("^[%w%-]+%.[%w%-%.]+[/%S]*$") and not text:find("%s") then
        local url = text:match("^%a+://") and text or ("https://" .. text)
        items[#items + 1] = { glyph = "external-link", label = tr("Open") .. " " .. text, run = function() open_url(url) end }
    end
    local def = engine()
    items[#items + 1] = { glyph = "world", label = def.name .. ": " .. text, run = function() search_web(def, text) end }
    for i, sug in ipairs(extra.suggest or {}) do
        if i > 4 then break end
        items[#items + 1] = { sep = i == 1, glyph = "search", label = sug, run = function() search_web(def, sug) end }
    end
    local first = true
    for _, e in ipairs(ENGINES) do
        if e.id ~= def.id and #items < 12 then
            items[#items + 1] = { sep = first, glyph = "world", label = e.name .. ": " .. text, run = function() search_web(e, text) end }
            first = false
        end
    end
    return items
end
local function rows_cmd()
    local items = {}
    if q == "" then
        for i, c in ipairs(cfg.cmds or {}) do
            if i > 9 then break end
            items[#items + 1] = { keep = true, glyph = "history", label = c, run = function() q = c E.menuText(c) M.query() end }
        end
        items[#items + 1] = { sep = #items > 0, glyph = "terminal-2", label = tr("Open terminal"), run = function() run("latte-terminal", {}, nil, { output = false }) close() end }
        return items
    end
    local cmd, bad = q, dangerous(q)
    if confirm == cmd then
        items[#items + 1] = { danger = true, glyph = "alert-triangle", label = tr("Dangerous command — Enter or click again runs it"), run = function() run_cmd(cmd) end }
    else
        items[#items + 1] = { danger = bad, keep = bad, glyph = "player-play", label = tr("Run in terminal") .. ": " .. cmd,
                              run = function() if bad then confirm = cmd render(true) else run_cmd(cmd) end end }
    end
    for i, c in ipairs(extra.compl or {}) do
        if i > 8 then break end
        items[#items + 1] = { keep = true, sep = i == 1, glyph = "corner-down-right", label = c, run = function() q = c E.menuText(c) M.query() end }
    end
    return items
end
local function rows_ai()
    local items = {}
    local from = math.max(1, #chat - 3)                                   -- posledné dve otázky a odpovede
    for i = from, #chat do
        local m = chat[i]
        if m.role == "user" then items[#items + 1] = { info = true, sep = i > from, glyph = "user", label = m.content }
        else items[#items + 1] = { para = true, glyph = "sparkles", label = m.content } end
    end
    if #chat == 0 then items[1] = { info = true, glyph = "sparkles", label = tr("The answer appears here, in the launcher") } end
    items[#items + 1] = { info = true, sep = true, glyph = "cpu", label = status ~= "" and status or tr("AI not set up"), hint = busy and tr("answering…") or "" }
    if busy then
        items[#items + 1] = { keep = true, glyph = "player-stop", label = tr("Stop"), run = function() if job then pcall(cancel, job) end busy, job = false, nil render(true) end }
    elseif #chat > 0 then
        items[#items + 1] = { keep = true, glyph = "refresh", label = tr("New conversation"), run = function() chat = {} render(true) end }
    end
    items[#items + 1] = { glyph = "settings", label = tr("AI settings"), run = function() run("latte-app", { "nastavenia", "ai" }, nil, { output = false }) close() end }
    return items
end

-- ── karta ────────────────────────────────────────────────────────────────────────────────────────────────────
local function first_action(items)
    for i = 2, #items do
        local it = items[i]
        if it.run and not it.info and not it.off then return it end
    end
end
local function build(keep)
    local chips = {}
    for _, m in ipairs(ORDER) do
        chips[#chips + 1] = { glyph = MODES[m].glyph, label = tr(MODES[m].name), on = mode == m, run = function() set_mode(m) end }
    end
    local rows = (mode == 0 and rows_ai or mode == 2 and rows_files or mode == 3 and rows_web or mode == 4 and rows_cmd or rows_apps)()
    local items = { { input = true, glyph = MODES[mode].glyph, label = tr(MODES[mode].hint),
        change = function(v)
            v = (v:gsub("^%s+", ""))
            if v == q then return end
            q, confirm = v, nil
            M.query()
        end,
        submit = function(v)
            if mode == 0 then ask_ai(v) return false end
            local it = first_action(lastItems or {})
            if it then it.run() return it.keep == true end               -- nebezpečný príkaz: text ostáva na druhý Enter
            return true
        end } }
    for i, r in ipairs(rows) do
        if i == 1 then r.sep = true end
        items[#items + 1] = r
    end
    -- okno má pevnú výšku (horná hrana pri prepínaní režimov neskáče) a ucho = kvapka LensGoo v jeho rohu
    lastItems, lastOpts = items, { id = "lens", chips = chips, owner = M.drop, height = 600 }
    E.menu(items, W, { id = "lens", chips = chips, keep = keep, owner = M.drop, height = 600 })
end
render = function(keep)
    local ok, err = pcall(build, keep)
    if not ok then log("goo: spúšťač: " .. tostring(err)) text.hud = "spúšťač: " .. tostring(err) end
end

-- doplnky z pomocníkov podľa režimu a textu (asynchrónne; staršia odpoveď sa zahodí)
function M.query()
    gen = gen + 1
    local g, text = gen, q
    extra = { caste = extra.caste }
    render(true)
    local function mine() return g == gen and E.menuId() == "lens" end
    if mode == 1 and text ~= "" then
        run("latte-riadok", { "pocitaj", text }, function(out)
            local v, d = (out or ""):match("^([^\t\n]+)\t([^\n]*)")
            if mine() and v then extra.calc = { value = v, desc = d } render(true) end
        end)
        run("latte-riadok", { "nastavenia", text }, function(out)
            if not mine() then return end
            local t = {}
            for _, l in ipairs(lines(out)) do
                local name, _, page = l:match("^([^\t]+)\t([^\t]*)\t(.+)$")
                if name then t[#t + 1] = { name = name, page = page } end
            end
            if #t > 0 then extra.settings = t render(true) end
        end)
        if utf8.len(text) and utf8.len(text) >= 3 then
            run("latte-hladaj", { "--json", "--max", "3", text }, function(out)
                if not mine() then return end
                local t = {}
                for _, l in ipairs(lines(out)) do
                    local ok, r = pcall(json.decode, l)
                    if ok and type(r) == "table" and r.path then t[#t + 1] = r end
                end
                if #t > 0 then extra.afiles = t render(true) end
            end)
        end
    elseif mode == 2 and text ~= "" then
        run("latte-hladaj", { "--json", "--max", "10", text }, function(out)
            if not mine() then return end
            local t = {}
            for _, l in ipairs(lines(out)) do
                local ok, r = pcall(json.decode, l)
                if ok and type(r) == "table" and r.path then t[#t + 1] = r end
            end
            extra.files = t
            render(true)
        end)
    elseif mode == 3 and text ~= "" then
        run("latte-riadok", { "navrhy", engine().id, text }, function(out)
            if mine() then extra.suggest = lines(out) render(true) end
        end)
    elseif mode == 4 and text ~= "" then
        run("latte-riadok", { "dopln", text }, function(out)
            if mine() then extra.compl = lines(out) render(true) end
        end)
    end
end

-- otvorí okno spúšťača pri kvapke (klik na LensGoo alebo kláves Windows — aj bez myši); znova = zavrie
function M.open(d)
    if E.menuId() == "lens" then close() return end
    M.drop = d or M.drop
    q, confirm, extra = "", nil, { caste = extra.caste }
    E.menuText("")
    render(false)
    run("latte-goo", { "spustac" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then
            cfg = t
            local m = tonumber(t.mode)
            if m and MODES[m] and #chat == 0 and q == "" then mode = m end
        end
        if E.menuId() == "lens" then render(true) end
    end)
    run("latte-riadok", { "caste", "8" }, function(out) extra.caste = lines(out) if E.menuId() == "lens" and q == "" then render(true) end end)
    run("latte-ai", { "status" }, function(out)
        local target, model, prov = (out or ""):match("target=([^\n]*)"), (out or ""):match("model=([^\n]*)"), (out or ""):match("provider=([^\n]*)")
        local where = (prov == "lokalne" and tr("on this PC")) or (prov == "domaci" and tr("home server")) or (prov == "ziadna" and "") or tr("cloud")
        status = (target or model or "") .. (where ~= "" and "  ·  " .. where or "")
        if prov == "ziadna" then status = "" end
        if E.menuId() == "lens" and mode == 0 then render(true) end
    end)
end

-- RÝCHLY ZOZNAM (pravý klik na LensGoo, používateľ 6. 10.): jednoduché okno s ikonami aplikácií — naposledy spustené
-- a obľúbené ako dlaždice (ikona nad názvom), klik spustí; pod nimi hľadanie (otvorí spúšťač). Bez písania.
local function quick_items(d)
    local items, seen = {}, {}
    local function tiles(ids, max)
        local t = {}
        for _, id in ipairs(ids) do
            local a = byId[id]
            if a and not seen[id] and #t < max then
                seen[id] = true
                t[#t + 1] = { img = a.icon, glyph = "apps", label = a.name or a.id, run = function() launch(a) end }
            end
        end
        return t
    end
    local rec = tiles(cfg.recent or {}, 8)
    local more = tiles(extra.caste or {}, 8 - #rec)                  -- doplnok: časté v túto dennú dobu
    for _, t in ipairs(more) do rec[#rec + 1] = t end
    if #rec > 0 then
        items[#items + 1] = { hd = true, label = tr("RECENTLY USED") }
        items[#items + 1] = { tiles = rec, per = 4 }
    end
    local fav = tiles(((cfg.tabs or {})[1] or {}).apps or {}, 8)
    if #fav > 0 then
        items[#items + 1] = { hd = true, sep = #rec > 0, label = tr("FAVOURITES") }
        items[#items + 1] = { tiles = fav, per = 4 }
    end
    if #items == 0 then
        local first = {}
        for i = 1, math.min(8, #apps) do first[#first + 1] = apps[i].id end
        items[#items + 1] = { hd = true, label = tr("APPLICATIONS") }
        items[#items + 1] = { tiles = tiles(first, 8), per = 4 }
    end
    items[#items + 1] = { sep = true, pills = {
        { glyph = "search", label = tr("Search…"), run = function() after(60, function() M.open(d) end) end },
        { glyph = "apps", label = tr("App Manager"), run = function() run("latte-app", { "aplikacie" }, nil, { output = false }) end } } }
    return items
end
function M.quick(d)
    if E.menuId() == "quick" then close() return end
    local function show(keep) E.menu(quick_items(d), 380, { id = "quick", keep = keep, owner = d }) end
    show(false)
    run("latte-goo", { "spustac" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then cfg = t end
        if E.menuId() == "quick" then show(true) end
    end)
    run("latte-riadok", { "caste", "8" }, function(out) extra.caste = lines(out) if E.menuId() == "quick" then show(true) end end)
end

function M.start(d)
    M.drop = d
    -- kláves Windows (latte-spustac → pleamar --say goo "emit lens_toggle"): spúšťač sa dá otvoriť aj bez myši
    on("lens_toggle", function() M.open(d) end)
    sys.watch("apps", function(list)
        apps, byId = list or {}, {}
        for _, a in ipairs(apps) do if a.id then byId[a.id] = a end end
    end)
end

return M
