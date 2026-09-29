--!nonstrict
-- Panel maskota (pravý klik na maskota): postava, potreby (káva, nálada, energia), starostlivosť,
-- režim OFF / Ostrov / Výbehy / Chaos a výber zo všetkých postáv. Bezpečnosť: maskot je iba obrázok,
-- nečíta súbory ani nič nespúšťa (ukazuje sa vo vrstve nad plochou, kliky prechádzajú mimo neho).
local C = require("./common.luau")
local st = C.load()

local function bar(label, glyph, v, color)
  local w = 180
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = glyph, size = 15, color = color }),
    ui.label({ text = label, fontSize = 12, minWidth = 62 }),
    ui.row({ width = w, height = 8, radius = 4, fill = "on_surface/0.1" }, {
      ui.row({ width = math.max(2, math.floor(w * v / 100)), height = 8, radius = 4, fill = color }, {}),
    }),
    ui.label({ text = tostring(math.floor(v)), fontSize = 11, color = "on_surface_variant" }),
  })
end

local function act(fn, msg)
  st = C.load(); C.decay(st, false); fn(st); C.save(st)
  if msg then noctalia.notify(C.names[C.kind()] or "Maskot", msg) end
  render()
end

function render()
  local kind = C.kind()
  if kind == "ziadny" then kind = "homebrew" end
  local mode = C.mode()
  local mf, mt = C.mood(st)
  local modeRow = {}
  for _, m in ipairs(C.modes) do
    table.insert(modeRow, ui.button({ text = C.modeNames[m], variant = (mode == m) and "primary" or "ghost",
      onClick = function()
        C.setMode(m)
        if m == "off" or m == "slot" then C.setRun("domov") end
        render()
      end }))
  end
  local grid, row = {}, {}
  for _, k in ipairs(C.order) do
    table.insert(row, ui.column({ width = 64, gap = 2, align = "center", radius = 10, padding = 4,
                                  fill = (k == kind) and "primary/0.18" or "surface_variant",
                                  tooltip = C.names[k] .. " — " .. C.about[k],
                                  onClick = function() C.setKind(k); if C.mode() == "off" then C.setMode("world") end; render() end }, {
      ui.image({ path = C.bar(k, "sedi"), width = 44, height = 36, fit = "contain" }),
      ui.label({ text = C.names[k], fontSize = 9, maxWidth = 60, maxLines = 1 }),
    }))
    if #row == 5 then table.insert(grid, ui.row({ gap = 6 }, row)); row = {} end
  end
  if #row > 0 then table.insert(grid, ui.row({ gap = 6 }, row)) end

  local descMode = ({ off = "Maskot je skrytý.", slot = "Sedí vo svojom ostrove na lište; pri nečinnosti odíde a vráti sa s tebou.",
                      world = "Občas vybehne z ostrova: chodí po lište, sadá na okná, keď si preč, zdriemne si pri kurzore.",
                      chaos = "Behá voľne po celej ploche a naháňa kurzor." })[mode]
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ gap = 12, align = "center" }, {
      ui.image({ path = C.bar(kind, (mf == "smutny") and "smutny" or "sedi"), width = 88, height = 72, fit = "contain" }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = C.names[kind], fontSize = 18, fontWeight = "bold" }),
        ui.label({ text = (mt ~= "" and mt or C.about[kind]), fontSize = 12, color = "on_surface_variant", maxWidth = 250, maxLines = 2 }),
        ui.label({ text = "deň " .. (st.dni or 0) .. " s tebou", fontSize = 11, color = "primary" }),
      }),
      ui.button({ glyph = "x", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.column({ gap = 6, padding = 10, radius = 12, fill = "surface_variant" }, {
      bar("Káva", "coffee", st.kava, "primary"),
      bar("Nálada", "heart", st.nalada, "error"),
      bar("Energia", "bolt", st.energia, "secondary"),
    }),
    ui.row({ gap = 6 }, {
      ui.button({ text = "Dať kávu", glyph = "coffee", onClick = function() act(C.feed, "Mňam, káva! ☕") end }),
      ui.button({ text = "Pohladkať", glyph = "heart", variant = "ghost", onClick = function() act(C.pet) end }),
      ui.button({ text = "Hrať sa", glyph = "ball-football", variant = "ghost", onClick = function()
        act(C.play, "Hráme sa!")
        if C.mode() == "world" or C.mode() == "chaos" then C.setRun("hrat") end
      end }),
      ui.button({ text = "Spať", glyph = "moon", variant = "ghost", onClick = function() act(C.nap, "Dobrú noc… zZ") end }),
    }),
    ui.label({ text = "REŽIM", fontSize = 10, fontWeight = "bold", color = "on_surface_variant" }),
    ui.row({ gap = 4 }, modeRow),
    ui.label({ text = descMode, fontSize = 11, color = "on_surface_variant", maxWidth = 380, maxLines = 2 }),
    ui.label({ text = "POSTAVA", fontSize = 10, fontWeight = "bold", color = "on_surface_variant" }),
    ui.column({ gap = 6 }, grid),
    ui.row({ gap = 6 }, {
      ui.button({ text = "Pridať balíček…", glyph = "plus", variant = "ghost", tooltip = "Vlastný alebo komunitný maskot (.zip: PNG snímky + pet.json)",
                  onClick = function() noctalia.runAsync({ "latte-maskoti", "pridaj-vyber" }, function(r)
                    local id = C.trim(r.stdout or ""); C.loadUser(); if id ~= "" then C.setKind(id) end; render() end) end }),
      ui.button({ text = "Zdieľať…", glyph = "share", variant = "ghost", tooltip = "Uloží postavu ako .zip do Dokumentov",
                  onClick = function() local k = C.kind(); noctalia.runAsync({ "sh", "-c", 'd="$(xdg-user-dir DOCUMENTS)"; latte-maskoti export "$1" "$d/Maskot $1.zip" && notify-send -a LatteOS "Maskot uložený" "$d/Maskot $1.zip"', "sh", k }) end }),
      (C.user[kind] and ui.button({ text = "Odobrať", glyph = "trash", variant = "ghost",
                  onClick = function() noctalia.runAsync({ "latte-maskoti", "odober", kind }, function() C.setKind("homebrew"); C.loadUser(); render() end) end })) or nil,
    }),
    ui.label({ text = "Maskot je iba obrázok: nemá prístup k súborom ani sieti.", fontSize = 10, color = "on_surface_variant" }),
  }))
end

function onOpen(_ctx) C.loadUser(); st = C.load(); C.decay(st, false); render() end
