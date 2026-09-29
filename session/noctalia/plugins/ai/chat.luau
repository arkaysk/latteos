--!nonstrict
-- AI rozhovor (vyskakovací panel, Super+I alebo Enter na odpovedi v Text Bare): história v
-- ~/.local/share/latteos/ai-rozhovor.json (spoločná s oknom latte-app aichat, najviac 40 správ), odpoveď cez
-- `latte-ai chat`. Pripínačik 📌 otvorí rozhovor ako samostatné okno.
local home = noctalia.getenv("HOME") or ""
local dataDir = (noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/latteos"
local file = dataDir .. "/ai-rozhovor.json"
local disabled = false
local msgs, draft, busy, target = {}, "", false, ""

local function save()
  noctalia.mkdirAll(dataDir)
  while #msgs > 40 do table.remove(msgs, 1) end
  noctalia.writeFile(file, noctalia.json.encode(msgs))
end
local function load()
  local raw = noctalia.readFile(file)
  local ok, t = pcall(function() return raw and noctalia.json.decode(raw) or {} end)
  msgs = (ok and type(t) == "table") and t or {}
end

local function bubble(m)
  local mine = m.role == "user"
  return ui.row({ justify = mine and "end" or "start" }, {
    ui.column({ fill = mine and "primary" or "surface_variant", radius = 14, padding = 12, gap = 4, width = 440 }, {
      ui.label({ text = mine and "Ty" or "AI", fontSize = 11, fontWeight = "bold", color = mine and "on_primary" or "primary" }),
      mine and ui.label({ text = m.content, fontSize = 13, color = "on_primary", maxWidth = 410, maxLines = 30 })
            or ui.markdown({ text = m.content }),
    }),
  })
end

function render()
  local body = {}
  if disabled then
    table.insert(body, ui.label({ text = "AI je vypnutá (Bez AI). Zapneš ju v Nastaveniach › Softvér › AI.", fontSize = 13, color = "on_surface_variant", maxWidth = 500, maxLines = 3 }))
  elseif #msgs == 0 then
    table.insert(body, ui.label({ text = "Opýtaj sa čokoľvek. Rozhovor si pamätá predošlé správy.", fontSize = 13, color = "on_surface_variant", maxWidth = 500, maxLines = 3 }))
  end
  for _, m in ipairs(msgs) do table.insert(body, bubble(m)) end
  if busy then table.insert(body, ui.label({ text = "AI premýšľa…", fontSize = 12, color = "primary" })) end
  panel.render(ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "sparkles", size = 20, color = "primary" }),
      ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = "AI", fontSize = 17, fontWeight = "bold" }),
        ui.label({ text = target ~= "" and target or "latte-ai", fontSize = 11, color = "on_surface_variant", maxWidth = 360, maxLines = 1 }),
      }),
      ui.button({ glyph = "pin", variant = "ghost", tooltip = "Pripnúť ako okno",
                  onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "aichat" }) end }),
      ui.button({ glyph = "settings", variant = "ghost", tooltip = "Nastavenia AI", onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "nastavenia", "ai" }) end }),
      ui.button({ text = "Nový", glyph = "plus", variant = "ghost", onClick = function() msgs = {}; save(); render() end }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.scroll({ flexGrow = 1, gap = 10, align = "stretch", stickToBottom = true }, body),
    ui.row({ gap = 8, align = "center" }, {
      ui.input({ key = "draft-" .. #msgs, placeholder = busy and "čakám na odpoveď…" or "Napíš správu, Enter pošle", flexGrow = 1, focus = true,
                 enabled = not busy, onChange = "onDraft", onSubmit = "onSend" }),
      ui.button({ glyph = "send", enabled = not busy, onClick = function() onSend(draft) end }),
    }),
  }))
end

function onDraft(t) draft = t or "" end
function onSend(_t)
  local text = string.gsub(draft or "", "^%s*(.-)%s*$", "%1")
  if text == "" or busy then return end
  table.insert(msgs, { role = "user", content = text })
  draft = ""
  busy = true
  save(); render()
  -- runStream nemá časový limit (runAsync má 5 s, najviac 60 s; premýšľajúce modely potrebujú viac).
  -- Príkaz obsahuje iba cestu k vlastnému súboru, text používateľa ide cez súbor, nie cez shell.
  local lines = {}
  noctalia.runStream("latte-ai chat '" .. file .. "' 2>&1; echo \"__LATTE_KONIEC__ $?\"", function(line)
    local rc = string.match(line, "^__LATTE_KONIEC__ (%d+)$")
    if not rc then table.insert(lines, line); return end
    busy = false
    local out = string.gsub(table.concat(lines, "\n"), "%s+$", "")
    if rc ~= "0" or out == "" then
      table.insert(msgs, { role = "assistant", content = "⚠ AI neodpovedalo: " .. string.sub(out ~= "" and out or "?", 1, 300) })
    else
      table.insert(msgs, { role = "assistant", content = out })
    end
    save(); render()
  end)
end

function onOpen(_ctx)
  load(); render()
  noctalia.runAsync({ "latte-ai", "status" }, function(r)
    local model = string.match(r.stdout or "", "model=([^\n]*)") or ""
    local tgt = string.match(r.stdout or "", "target=([^\n]*)") or ""
    target = (model ~= "" and (model .. " · ") or "") .. tgt
    disabled = string.find(r.stdout or "", "disabled=1") ~= nil
    render()
  end)
end
