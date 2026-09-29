--!nonstrict
-- Dlaždica aplikácií: ikona v strede, okolo pokojná textúra. Pravidlá starej verzie:
--   - pasívny pohyb (cyklus ~8 s), najviac 10 obr/s; nič sa nemení podľa stavu systému,
--   - statický snímok je vždy čitateľný (ikona), navigácia sa na pohyb nespolieha,
--   - pri softvérovom kreslení (VM, stupeň Softvér/Minimálny) alebo v hernom režime sa hýbe iba pod kurzorom.
local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local stateHome = noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")

local W, H = 88, 34              -- dlaždica ≈ 2,5 : 1 (ostrov lišty má výšku ~40)
local BARS = 7                   -- stĺpce textúry na každej strane ikony
local t0 = 0                     -- čas animácie v s
local hovered = false
local anim, scene, still = "kurzor", "para", false
local pokoj = false               -- $XDG_RUNTIME_DIR/latteos/pokoj (zamknutá obrazovka)
local runDir = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"
local cheapTier = true           -- bez GPU: 5 obr/s namiesto 10 (každá snímka stojí kompozitor celé prekreslenie)

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function readPref(name, default)
  local v = trim(noctalia.readFile(cfgHome .. "/latteos/" .. name) or "")
  return v ~= "" and v or default
end

local function loadPrefs()
  local tier = string.match(noctalia.readFile("/run/latteos/mode.toml") or "", 'tier = "(%a+)"') or "softver"
  local forced = trim(noctalia.readFile(cfgHome .. "/latteos/tier") or "")
  if forced ~= "" then tier = forced end
  local game = trim(noctalia.readFile(stateHome .. "/latteos/game-mode") or "0") == "1"
  local cheap = tier == "softver" or tier == "minimalny" or tier == "safe" or game
  cheapTier = tier == "softver" or tier == "minimalny" or tier == "safe"
  pokoj = noctalia.readFile(runDir .. "/latteos/pokoj") ~= nil
  anim = readPref("bar-anim", cheap and "kurzor" or "vzdy")
  scene = readPref("bar-scene", "para")
end

-- GIF / obrázok kreslí nad dlaždicou vrstva TileOverlay (Quickshell) — dlaždica pod ním sa nemusí hýbať
local function moving()
  if string.sub(scene, 1, 5) == "file:" then return false end
  if pokoj then return false end            -- obrazovka zamknutá (hook session_locked): pod zámkom sa nič nehýbe
  return anim == "vzdy" or (anim == "kurzor" and hovered)
end

-- para: stĺpce ako para nad šálkou, pomaly dýchajú (fáza posunutá po stĺpcoch)
local function para(side)
  local out = {}
  for i = 1, BARS do
    local k = side == "l" and (BARS - i + 1) or i          -- vzdialenosť od ikony
    local phase = t0 * (2 * math.pi / 8) + k * 0.7 + (side == "l" and 0 or 1.9)
    local h = 6 + (H - 14) * (0.5 + 0.5 * math.sin(phase)) * (1 - k / (BARS + 3))
    local a = 0.22 + 0.30 * (1 - k / (BARS + 1))
    table.insert(out, ui.box({ width = 3, height = math.floor(h), radius = 2, fill = string.format("primary/%.2f", a) }))
  end
  return out
end

-- matrix: stekajúce číslice v akcente témy (stĺpec = jeden znak, jas podľa „kvapky“)
local glyphs = { "0", "1", "L", "7", "A", "3", "T", "9", "E", "5" }   -- iba znaky, ktoré má každé písmo
local function matrix(side)
  local out = {}
  for i = 1, BARS do
    local seed = (side == "l" and i or i + 11)
    local drop = (t0 * 1.2 + seed * 0.37) % 1
    local ch = glyphs[(math.floor(t0 * 2 + seed * 3) % #glyphs) + 1]
    table.insert(out, ui.label({ text = ch, fontSize = 9, color = string.format("primary/%.2f", 0.15 + 0.6 * drop), width = 5, textAlign = "center" }))
  end
  return out
end

-- textúry okien v tvare L (apps/common/Scena.qml): matrix a para kreslí dlaždica sama; jedna farba a pomalé svetlo
-- menia výplň; ozubené kolesá a obrázok/GIF dlaždica nevie, ukáže paru (v okne L sa kreslia celé)
local function render()
  local kind, arg = string.match(scene, "^(%a+):?(.*)$")
  kind = kind or "para"
  local tex = kind == "matrix" and matrix or para
  local row = {}
  local plain = kind == "solid" or kind == "glow"
  if not plain then for _, n in ipairs(tex("l")) do table.insert(row, n) end end
  table.insert(row, ui.glyph({ name = "apps", size = 18, color = "on_surface" }))
  if not plain then for _, n in ipairs(tex("r")) do table.insert(row, n) end end
  local fill = hovered and "primary/0.14" or "primary/0.06"
  if kind == "solid" and string.match(arg or "", "^#%x%x%x%x%x%x$") then fill = arg
  elseif kind == "glow" then fill = string.format("primary/%.2f", 0.08 + 0.14 * (0.5 + 0.5 * math.sin(t0 * 2 * math.pi / 8)) + (hovered and 0.06 or 0)) end
  barWidget.render(ui.row({ width = W, height = H, gap = 2, align = "center", justify = "center", radius = 12,
                            fill = fill,
                            onHover = function(state) hovered = state == "true"; noctalia.setUpdateInterval(moving() and (cheapTier and 200 or 100) or 30000); render() end,
                            tooltip = "Aplikácie · klik: rýchle spustenie, 📌 plný App Manager" }, row))
end

function update()
  loadPrefs()
  if moving() then
    t0 = t0 + (cheapTier and 0.2 or 0.1)
    noctalia.setUpdateInterval(cheapTier and 200 or 100)   -- 5 obr/s bez GPU, 10 obr/s s GPU
  else
    noctalia.setUpdateInterval(pokoj and 2000 or 30000)   -- statický snímok; pri zámku kontrola každé 2 s (rýchly návrat)
  end
  render()
end

-- klik = App Manager: rýchle spustenie (vyskakovacie okno); ak je plný App Manager otvorený, iba ho vytiahne dopredu
function onClick() noctalia.runAsync({ "latte-spustac" }) end
-- pravý klik ako na tlačidlo Štart vo Windows: ponuka Win+X (Nainštalované aplikácie, Správca zariadení, Terminál…)
function onRightClick() noctalia.runAsync({ "latte-ponuka", "win-x" }) end
