--!nonstrict
-- Dlaždica Zariadení (pravý roh lišty): zrkadlo dlaždice aplikácií (zadanie 25. 9.) — rovnaká pokojná textúra
-- (vlastná pre pravé L: bar-scene-vpravo, inak bar-scene). Klik = Správca zariadení v tvare L (latte-rychle).
-- Zadanie 26. 9.: žiadna statická ikona. Ako App Manager je dlaždica bez ikony, kým nie je čo ukázať; inak ukazuje
-- iba významové ukazovatele (neklikateľné, ovládanie je až v okne), zľava podľa dôležitosti:
--   prehrievanie (teplota blízko kritickej) · kamera používaná · mikrofón používaný · sila Wi-Fi · batéria.
-- Wi-Fi iba pri pripojení cez Wi-Fi, batéria iba ak ju počítač má.
-- Pravidlá starej verzie:
--   - pasívny pohyb (cyklus ~8 s), najviac 10 obr/s; nič sa nemení podľa stavu systému,
--   - statický snímok je vždy čitateľný (ikona), navigácia sa na pohyb nespolieha,
--   - pri softvérovom kreslení (VM, stupeň Softvér/Minimálny) alebo v hernom režime sa hýbe iba pod kurzorom.
local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local stateHome = noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")

local W0, H = 88, 34             -- dlaždica ≈ 2,5 : 1 (ostrov lišty má výšku ~40); s ukazovateľmi širšia
local wifi, bat, charging = nil, nil, false      -- sila Wi-Fi 0–100 (nil = nie je Wi-Fi), batéria % (nil = bez batérie)
local hot = nil                  -- najteplejší senzor blízko kritickej teploty: { c = °C, name = "…" }
local mic, cam = {}, {}          -- aplikácie, ktoré práve používajú mikrofón / kameru
local polled, privT = -100, 0
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
  scene = readPref("bar-scene-vpravo", readPref("bar-scene", "para"))
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

local function tip()
  local t = { "Správca zariadení" }
  if hot then table.insert(t, "⚠ prehrieva sa: " .. hot.name .. " " .. hot.c .. " °C") end
  if #cam > 0 then table.insert(t, "kamera: " .. table.concat(cam, ", ")) end
  if #mic > 0 then table.insert(t, "mikrofón: " .. table.concat(mic, ", ")) end
  if wifi then table.insert(t, "Wi-Fi " .. wifi .. " %") end
  if bat then table.insert(t, "batéria " .. bat .. " %" .. (charging and " (nabíja sa)" or "")) end
  return table.concat(t, " · ")
end

-- textúry okien v tvare L (apps/common/Scena.qml): matrix a para kreslí dlaždica sama; jedna farba a pomalé svetlo
-- menia výplň; ozubené kolesá a obrázok/GIF dlaždica nevie, ukáže paru (v okne L sa kreslia celé)
local function render()
  local kind, arg = string.match(scene, "^(%a+):?(.*)$")
  kind = kind or "para"
  local tex = kind == "matrix" and matrix or para
  local row = {}
  local plain = kind == "solid" or kind == "glow"
  if not plain then for _, n in ipairs(tex("r")) do table.insert(row, n) end end
  -- ukazovatele podľa dôležitosti; bez nich je dlaždica iba textúra (ako App Manager)
  local ind, extra = {}, 0
  local function add(node, w) table.insert(ind, node); extra = extra + w end
  if hot then add(ui.glyph({ name = "flame", size = 16, color = "error" }), 20) end
  if #cam > 0 then add(ui.glyph({ name = "camera", size = 16, color = "error" }), 20) end
  if #mic > 0 then add(ui.glyph({ name = "microphone", size = 16, color = "error" }), 20) end
  if wifi then
    local g = wifi >= 70 and "wifi" or (wifi >= 45 and "wifi-2" or (wifi >= 20 and "wifi-1" or "wifi-0"))
    add(ui.glyph({ name = g, size = 16, color = "on_surface" }), 20)
  end
  if bat then
    local g = charging and "battery-charging" or (bat >= 85 and "battery-4" or (bat >= 60 and "battery-3" or (bat >= 35 and "battery-2" or "battery-1")))
    add(ui.glyph({ name = g, size = 16, color = (bat < 15 and not charging) and "error" or "on_surface" }), 20)
    add(ui.label({ text = tostring(bat), fontSize = 10, color = "on_surface" }), 18)
  end
  if #ind > 0 then table.insert(row, ui.row({ gap = 3, align = "center" }, ind)) end
  if not plain then for _, n in ipairs(tex("l")) do table.insert(row, n) end end
  local fill = hovered and "primary/0.14" or "primary/0.06"
  if kind == "solid" and string.match(arg or "", "^#%x%x%x%x%x%x$") then fill = arg
  elseif kind == "glow" then fill = string.format("primary/%.2f", 0.08 + 0.14 * (0.5 + 0.5 * math.sin(t0 * 2 * math.pi / 8)) + (hovered and 0.06 or 0)) end
  local W = W0 + extra
  barWidget.render(ui.row({ width = W, height = H, gap = 2, align = "center", justify = "center", radius = 12,
                            fill = fill,
                            onHover = function(state) hovered = state == "true"; noctalia.setUpdateInterval(moving() and (cheapTier and 200 or 100) or 3000); render() end,
                            tooltip = tip() }, row))
end

-- test bez hardvéru: LATTE_TEST_INDIK="wifi:batéria:nabíja:mikrofón:kamera:teplota", napr. "70:45:1:1:0:96"
local function testIndik()
  local test = noctalia.getenv("LATTE_TEST_INDIK")
  if not test or test == "" then return false end
  local w, b, c, m, k, h = string.match(test, "^(%d*):(%d*):(%d?):?(%d?):?(%d?):?(%d*)$")
  wifi = tonumber(w or ""); bat = tonumber(b or ""); charging = c == "1"
  mic = m == "1" and { "test" } or {}; cam = k == "1" and { "test" } or {}
  hot = tonumber(h or "") and { c = tonumber(h), name = "CPU" } or nil
  return true
end

-- súkromie (mikrofón, kamera) každé 3 s: latte-sysmon sukromie (otvorené /dev zariadenia a streamy PipeWire)
local function pollPrivacy()
  noctalia.runAsync({ "latte-sukromie" }, function(r)
    mic, cam = {}, {}
    for kind, who in string.gmatch(r.stdout or "", "(%a+)\t([^\n]+)") do
      table.insert(kind == "camera" and cam or mic, who)
    end
    render()
  end)
end

-- Wi-Fi, batéria a teplota raz za 30 s, bez skenovania siete. Prehrievanie: senzor hwmon nad (kritická − 5 °C),
-- bez kritickej hodnoty nad 90 °C.
local function poll()
  noctalia.runAsync({ "sh", "-c", 'nmcli -t -f ACTIVE,SIGNAL dev wifi list --rescan no 2>/dev/null | sed -n "s/^yes://p" | head -1; echo @; '
                        .. 'for b in /sys/class/power_supply/BAT*; do [ -r "$b/capacity" ] && { cat "$b/capacity"; cat "$b/status"; break; }; done; echo @; '
                        .. 'for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null) || continue; '
                        .. 'c=$(cat "${f%_input}_crit" 2>/dev/null || echo 95000); [ "$c" -gt 20000 ] 2>/dev/null || c=95000; '
                        .. '[ "$v" -ge $((c - 5000)) ] 2>/dev/null && echo "$((v / 1000)) $(cat "${f%/*}/name")"; done | sort -rn | head -1' }, function(r)
    local w, b, h = string.match(r.stdout or "", "^(.-)@(.-)@(.*)$")
    wifi = tonumber(trim(w or ""))
    local cap, st = string.match(b or "", "(%d+)%s+(%a+)")
    bat = tonumber(cap or ""); charging = st == "Charging" or st == "Full"
    local c, name = string.match(h or "", "(%d+)%s+(%S+)")
    hot = c and { c = tonumber(c), name = ({ coretemp = "procesor", k10temp = "procesor", amdgpu = "grafika", nouveau = "grafika", nvme = "disk", acpitz = "doska" })[name] or name } or nil
    render()
  end)
end

function update()
  loadPrefs()
  if testIndik() then
    noctalia.setUpdateInterval(moving() and 100 or 30000)
    if moving() then t0 = t0 + 0.1 end
    render(); return
  end
  -- súkromie každé 3 s (bez pohybu interval 3 s, pri pohybe 100 ms → každý 30. krok)
  privT = privT + 1
  if not moving() or privT >= (cheapTier and 15 or 30) then privT = 0; pollPrivacy() end   -- každé ~3 s
  polled = polled + 1
  if polled >= (moving() and (cheapTier and 150 or 300) or 10) or polled < 0 then polled = 0; poll() end   -- každých ~30 s
  if moving() then
    t0 = t0 + (cheapTier and 0.2 or 0.1)
    noctalia.setUpdateInterval(cheapTier and 200 or 100)   -- 5 obr/s bez GPU, 10 obr/s s GPU
  else
    noctalia.setUpdateInterval(3000)         -- statický snímok; súkromie každé 3 s, ostatné každých 30 s
  end
  render()
end

-- klik = Správca zariadení v tvare L (ukazovatele samy nie sú tlačidlá)
function onClick() noctalia.runAsync({ "latte-rychle" }) end
