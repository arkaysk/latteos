--!nonstrict
-- Režim AI (/ai): cez latte-ai — lokálne (Ollama), domáci server (LM Studio a pod., aj cez SSH)
-- alebo veľké cloudové AI. Voľba je v Nastaveniach › Softvér › AI (~/.config/latteos/ai.toml).
-- Odpoveď sa zobrazí po riadkoch; Enter ju otvorí vo vyskakovacom paneli AI (s pripínačikom → okno),
-- „Skopírovať“ ju vloží do schránky. Pri prihlásení v prehliadači (web) sa otázka otvorí na stránke AI až po
-- Enteri, pri „Bez AI“ tu nie je nič. Rozhovor je spoločný s panelom a oknom: ~/.local/share/latteos/ai-rozhovor.json
local st = nil        -- { ok, model, target, error, web, disabled }
local busy = false
local lastQ, lastA = "", ""
local home = noctalia.getenv("HOME") or ""
local dataDir = (noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/latteos"
local chatFile = dataDir .. "/ai-rozhovor.json"

local function toPanel()
  local raw = noctalia.readFile(chatFile)
  local ok, msgs = pcall(function() return raw and noctalia.json.decode(raw) or {} end)
  if not ok or type(msgs) ~= "table" then msgs = {} end
  table.insert(msgs, { role = "user", content = lastQ })
  table.insert(msgs, { role = "assistant", content = lastA })
  while #msgs > 40 do table.remove(msgs, 1) end
  noctalia.mkdirAll(dataDir)
  noctalia.writeFile(chatFile, noctalia.json.encode(msgs))
  noctalia.runAsync({ "noctalia", "msg", "panel-open", "latteos/ai:chat" })
end

local function parse(out)
  local s = {}
  for k, v in string.gmatch(out or "", "(%w+)=([^\n]*)") do s[k] = v end
  return s
end

local function check(after)
  noctalia.runAsync({ "latte-ai", "status" }, function(r)
    st = parse(r.stdout)
    if after then after() end
  end)
end

local function settingsItem()
  return { id = "::settings", title = "Nastaviť AI", subtitle = "Nastavenia › Softvér › AI", glyph = "settings" }
end
local function chatItem()
  return { id = "::chat", title = "Rozhovor s AI", subtitle = "panel s pamäťou (Super+I)", glyph = "message" }
end

function onQuery(text)
  local q = text or ""
  if q == "" then st = nil end       -- nový dotaz: zistiť poskytovateľa znova (mohol sa zmeniť v Nastaveniach)
  if not st then
    launcher.setResults(text, { { id = "", title = "Zisťujem AI…", glyph = "sparkles" } })
    check(function() onQuery(text) end)
    return
  end
  if st.disabled == "1" then
    launcher.setResults(text, { { id = "::settings", title = "AI je vypnutá (Bez AI)", subtitle = "zapnúť: Nastavenia › Softvér › AI", glyph = "robot-off" } })
    st = nil
    return
  end
  if st.web == "1" then
    launcher.setResults(text, { { id = "::web:" .. q, title = q ~= "" and ("Opýtať sa " .. (st.model or "AI") .. ": " .. string.sub(q, 1, 80)) or ("Otvoriť " .. (st.model or "AI")),
                                  subtitle = "v prehliadači s tvojím prihlásením · Enter", glyph = "world" }, settingsItem() })
    return
  end
  if st.ok ~= "1" then
    launcher.setResults(text, { { id = "", title = "AI nie je dostupné", subtitle = (st.target or "") .. " — " .. (st.error or ""), glyph = "robot-off" }, settingsItem() })
    st = nil          -- nabudúce skúsiť znova
    return
  end
  local who = (st.model ~= "" and st.model) or "model vyberie server"
  if q == "" then
    launcher.setResults(text, { { id = "", title = "Opýtaj sa AI", subtitle = who .. " · " .. (st.target or ""), glyph = "sparkles" }, chatItem(), settingsItem() })
    return
  end
  if busy then return end
  busy = true
  launcher.setResults(text, { { id = "", title = "Premýšľam…", subtitle = who, glyph = "loader" } })
  noctalia.runAsync({ "latte-ai", "ask", q }, function(r)   -- limit 60 s (tretí argument), predvolený je iba 5 s
    busy = false
    if r.exitCode ~= 0 then
      launcher.setResults(text, { { id = "", title = "AI neodpovedalo", subtitle = string.sub(r.stderr or "", 1, 160), glyph = "robot-off" }, settingsItem() })
      return
    end
    local all = r.stdout or ""
    lastQ, lastA = q, all
    local items = {}
    for line in string.gmatch(all, "[^\n]+") do
      if #items >= 8 then break end
      table.insert(items, { id = "::okno", title = string.sub(line, 1, 140), subtitle = (#items == 0) and ("Enter: odpoveď v okne · " .. who) or nil, glyph = (#items == 0) and "sparkles" or "point" })
    end
    if #items > 0 then table.insert(items, 2, { id = "::kopia", title = "Skopírovať odpoveď", glyph = "copy" }) end
    if #items == 0 then items = { { id = "", title = "(prázdna odpoveď)", glyph = "sparkles" } } end
    launcher.setResults(text, items)
  end, 60000)
end

function onActivate(id)
  if id == "::okno" then toPanel(); return end
  if id == "::kopia" then noctalia.copyToClipboard(lastA, "text/plain"); return end
  if id and string.sub(id, 1, 6) == "::web:" then noctalia.runAsync({ "latte-ai", "open", string.sub(id, 7) }); return end
  if id == "::settings" then noctalia.runAsync({ "latte-app", "nastavenia", "ai" }); return end
  if id == "::chat" then noctalia.runAsync({ "noctalia", "msg", "panel-open", "latteos/ai:chat" }); return end
  if id and id ~= "" then noctalia.copyToClipboard(id, "text/plain") end
end
