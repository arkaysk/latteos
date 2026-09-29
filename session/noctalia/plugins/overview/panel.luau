--!nonstrict
-- Prehľad pásky: plochy pod sebou, okná každej plochy v rade zľava doprava (poradie pásky podľa x).
-- Písanie filtruje (názov aplikácie aj titulok), Enter zameria prvé nájdené okno, klik zameria okno.
local wins, filter, active = {}, "", ""
local glyphs = { foot = "terminal-2", kitty = "terminal-2", firefox = "world", ["org.mozilla.firefox"] = "world", chromium = "world",
                 code = "code", ["code-oss"] = "code", steam = "device-gamepad-2", ["org.videolan.VLC"] = "movie", vlc = "movie",
                 ["org.quickshell"] = "coffee", discord = "message", ["com.discordapp.Discord"] = "message" }

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function lower(s) return string.lower(s or "") end

local function focus(addr)
  panel.close()
  noctalia.runAsync({ "hyprctl", "eval", 'hl.dispatch(hl.dsp.focus({ window = "address:' .. addr .. '" }))' })
end

local function matches(w)
  if filter == "" then return true end
  local f = lower(filter)
  return string.find(lower(w.class), f, 1, true) ~= nil or string.find(lower(w.title), f, 1, true) ~= nil
end

local function load()
  noctalia.runAsync({ "sh", "-c", "hyprctl clients -j; echo '#AKTIVNE#'; hyprctl activewindow -j" }, function(r)
    local out = r.stdout or ""
    local a, b = string.find(out, "#AKTIVNE#", 1, true)
    local clients = a and string.sub(out, 1, a - 1) or out
    local act = a and string.sub(out, b + 1) or ""
    local ok, list = pcall(noctalia.json.decode, clients)
    local ok2, aw = pcall(noctalia.json.decode, act)
    active = (ok2 and type(aw) == "table" and aw.address) or ""
    wins = {}
    if ok and type(list) == "table" then
      for _, c in ipairs(list) do
        if c.mapped ~= false and (c.workspace and c.workspace.id or 0) > 0 then
          table.insert(wins, { addr = c.address, class = c.class or "", title = c.title or "", ws = c.workspace.id, wsName = c.workspace.name or tostring(c.workspace.id),
                               x = (c.at and c.at[1]) or 0, w = (c.size and c.size[1]) or 0, floating = c.floating })
        end
      end
    end
    table.sort(wins, function(p, q) if p.ws ~= q.ws then return p.ws < q.ws end return p.x < q.x end)
    render()
  end)
end

local function card(w)
  local isActive = w.addr == active
  return ui.column({ width = 210, height = 118, padding = 12, gap = 6, radius = 14,
                     fill = isActive and "primary/0.22" or "surface_variant", border = isActive and "primary" or "outline", borderWidth = 1,
                     onClick = function() focus(w.addr) end, tooltip = w.title }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = glyphs[w.class] or glyphs[lower(w.class)] or "app-window", size = 22, color = isActive and "primary" or "on_surface" }),
      ui.label({ text = w.class ~= "" and w.class or "okno", fontSize = 13, fontWeight = "bold", maxWidth = 150, maxLines = 1 }),
    }),
    ui.label({ text = w.title, fontSize = 12, color = "on_surface_variant", maxWidth = 186, maxLines = 3 }),
    ui.label({ text = w.floating and "plávajúce" or (w.w .. " px"), fontSize = 10, color = "on_surface_variant" }),
  })
end

function render()
  local body = {}
  local shown, curWs, row = 0, nil, nil
  local function flush()
    if row and #row > 0 then table.insert(body, ui.row({ gap = 10 }, row)) end
  end
  for _, w in ipairs(wins) do
    if matches(w) then
      if w.ws ~= curWs then
        flush()
        curWs = w.ws
        table.insert(body, ui.label({ text = "PLOCHA " .. w.wsName, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }))
        row = {}
      end
      if #row == 4 then flush(); row = {} end        -- dlhá páska: ďalší rad (panel nemá vodorovný posun)
      table.insert(row, card(w))
      shown = shown + 1
    end
  end
  flush()
  if shown == 0 then
    table.insert(body, ui.label({ text = filter ~= "" and ("Nič pre „" .. filter .. "“") or "Žiadne otvorené okná.", fontSize = 14, color = "on_surface_variant" }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = "layout-columns", size = 20, color = "primary" }),
      ui.label({ text = "Prehľad pásky", fontSize = 17, fontWeight = "bold" }),
      ui.label({ text = #wins .. " okien · píš pre filter, Enter zameria prvé", fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.input({ placeholder = "Hľadať okno…", focus = true, onChange = "onFilter", onSubmit = "onEnter" }),
    ui.scroll({ flexGrow = 1, gap = 10, align = "stretch" }, body),
  }))
end

function onFilter(t) filter = trim(t); render() end
function onEnter(_t)
  for _, w in ipairs(wins) do if matches(w) then focus(w.addr); return end end
end

function onOpen(_ctx)
  filter = ""
  render()
  load()
end
