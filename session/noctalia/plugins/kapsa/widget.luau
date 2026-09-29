--!nonstrict
-- Kapsa na lište (náčrt 24. 9.): široký kontajner, vľavo výrez pre jednu odloženú vec (súbor pretiahnutý
-- myšou; ikonu, ktorá čiastočne zapadne do výrezu a presahuje nad lištu, kreslí latte-app kapsavyrez),
-- vpravo sloty schránky: plný slot = položka histórie, prázdny = voľné miesto. Počet slotov:
-- ~/.config/latteos/kapsa-sloty (predvolene 8). Klik na slot = vytiahnuť navrch (skopírovať), pravý klik =
-- podržanie myši = náhľad (vyhodiť sa dá v paneli). Klik na kontajner = panel Kapsy.
-- Poloha: Noctalia pluginu nepovie, kde na lište je; pri prechode myšou nad výrezom (graph je jediný prvok
-- s onPointerMove) sa zistí z kurzora (hyprctl) a normalizovanej polohy a zapíše do
-- ~/.local/state/latteos/kapsa-poloha pre vrstvu výrezu (ľavý horný roh výrezu, šírka, výška).
local C = require("./common.luau")
local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local stateDir = (noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/latteos"
local posFile = stateDir .. "/kapsa-poloha"
local items = {}
local slots = 8
local calibrated = false

local NOTCH_W, NOTCH_H, SLOT_W, SLOT_H, GAP, PAD, H = 44, 26, 12, 20, 4, 10, 36
local function width() return PAD + NOTCH_W + 8 + slots * SLOT_W + (slots - 1) * GAP + PAD end

-- offset = vzdialenosť ľavého okraja prvku od ľavého okraja výrezu (výrez 44 + medzera 4 + 4 + 4 → prvý slot o 56 px)
local function calibrateAt(offset, w, h)
  return function(nx, ny)
    if calibrated then return end
    calibrated = true
    local x, y = tonumber(nx) or 0, tonumber(ny) or 0
    noctalia.runAsync({ "hyprctl", "cursorpos" }, function(r)
      local cx, cy = string.match(r.stdout or "", "(%-?%d+),%s*(%-?%d+)")
      if not cx then return end
      local left = math.floor(tonumber(cx) - x * w - offset + 0.5)
      local top = math.floor(tonumber(cy) - y * h - (h == NOTCH_H and 0 or (NOTCH_H - h) / 2) + 0.5)
      noctalia.mkdirAll(stateDir)
      noctalia.writeFile(posFile, string.format("%d %d %d %d\n", left, top, NOTCH_W, NOTCH_H))
    end)
  end
end

local function pick(it) noctalia.runAsync({ "sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", it.id }) end

local function render()
  local kids = {
    -- výrez: prehĺbená jamka, do ktorej zapadne ikona odloženého súboru
    ui.row({ width = NOTCH_W, height = NOTCH_H, radius = 10, fill = "on_surface/0.22", border = "outline", borderWidth = 1,
             tooltip = "Výrez: pretiahni sem súbor" }, {
      ui.graph({ width = NOTCH_W, height = NOTCH_H, values = { 0, 0 }, lineWidth = 0, fillOpacity = 0, onPointerMove = calibrateAt(0, NOTCH_W, NOTCH_H) }),
    }),
    ui.spacer({ width = 8 - GAP }),
  }
  for i = 1, slots do
    local it = items[i]
    table.insert(kids, ui.row({
      width = SLOT_W, height = SLOT_H, radius = 4,
      fill = it and "primary" or "on_surface/0.14",
      border = it and "primary" or "outline", borderWidth = 1,
      tooltip = it and (i .. ". " .. C.label(it, 80) .. " · klik: navrch") or (i .. ". voľný slot"),
      onClick = it and function() pick(it) end or nil,
    }, { ui.graph({ width = SLOT_W, height = SLOT_H, values = { 0, 0 }, lineWidth = 0, fillOpacity = 0,
                    onPointerMove = calibrateAt(56 + (i - 1) * (SLOT_W + GAP), SLOT_W, SLOT_H) }) }))
  end
  barWidget.render(ui.row({
    -- ostrov kreslí lišta (skupina „kapsa“ v config.toml), widget už nemá vlastný rámik
    width = width(), height = H, gap = GAP, align = "center", paddingH = PAD, radius = 14,
    onHover = function(state) if state == "true" then calibrated = false end end,
  }, kids))
end

function refresh()
  local n = tonumber(string.match(noctalia.readFile(cfgHome .. "/latteos/kapsa-sloty") or "", "%d+") or "") or 8
  slots = math.max(4, math.min(12, n))
  noctalia.runAsync({ "sh", "-c", "cliphist list 2>/dev/null | head -" .. slots }, function(r)
    items = C.parse(r.stdout)
    render()
    barWidget.setTooltip({ { "Kapsa", #items .. " / " .. slots .. " slotov" }, { "Výrez", "pretiahni sem súbor" }, { "Klik", "otvoriť Kapsu" } })
  end)
end

local watching = false
function update()
  noctalia.setUpdateInterval(60000)
  if not watching then
    watching = true
    -- po štarte shellu môže byť rozloženie lišty iné: stará poloha výrezu by blokovala kliky inde,
    -- preto sa zahodí a zistí znova pri prvom prechode myšou nad Kapsou
    noctalia.removeFile(posFile)
    -- každá zmena schránky vypíše riadok → obnoviť (cliphist store beží zvlášť v relácii)
    noctalia.runStream("wl-paste --watch echo zmena", function(_line) refresh() end)
  end
  refresh()
end

function onClick() noctalia.togglePanel("latteos/kapsa:panel") end
-- pravý klik na ostrov Kapsy: otvorí Kapsu (ponuky položiek sú v nej); predtým nereagoval vôbec
function onRightClick() noctalia.togglePanel("latteos/kapsa:panel") end
