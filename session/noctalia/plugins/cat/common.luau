--!nonstrict
-- Maskot LatteOS — spoločné pre widget (lišta), panel (pravý klik) a maskot.qml (útek z ostrova).
-- Potreby ako tamagoči: káva, nálada, energia (0–100); stav ~/.local/state/latteos/maskot.json
--   { kava, nalada, energia, narodeny, posledne, dni, den, spanokDo }
-- Postava: ~/.config/latteos/mascot (homebrew … cdrak | ziadny; staré macka/zrnko/void sa prevedú); režim: ~/.config/latteos/mascot-mode
--   off (bez maskota) · slot (iba v ostrove) · world (občas vybehne po lište a oknách) · chaos (voľne po ploche)
-- Útek riadi maskot.qml cez $XDG_RUNTIME_DIR/latteos/maskot-von: vychadza | von | prichadza | domov (žiadosť) | prázdne.
local M = {}

local home = noctalia.getenv("HOME") or ""
M.cfg = (noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/latteos"
M.stateDir = (noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/latteos"
M.stateFile = M.stateDir .. "/maskot.json"
M.runFile = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/latteos/maskot-von"
M.dir = "/usr/share/latteos/noctalia/plugins/cat/mascots/"
M.packs = "/usr/share/latteos/maskoti/"          -- plné snímky pre výbehy (maskot.qml)
-- vlastné a komunitné balíčky (latte-maskoti pridaj): index ~/.local/share/latteos/maskoti/index.json, lišta v maskoti-lista/
local data = noctalia.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
M.userIndex = data .. "/latteos/maskoti/index.json"
M.userBar = data .. "/latteos/maskoti-lista/"
M.user = {}
-- hlavní maskoti (zadanie 25. 9.) a ďalší
M.order = { "homebrew", "drak", "ktulu", "robot", "maid", "kapybara", "latte", "mokka", "tien", "liska", "myval", "svetluska", "cdrak" }
M.names = { homebrew = "Homebrew", drak = "Kávový drak", ktulu = "Ktulu", robot = "Robot turista", maid = "Foxy Maid", kapybara = "Kapybara",
            latte = "Latte mačka", mokka = "Mokka", tien = "Tieň", liska = "Líška", myval = "Mýval", svetluska = "Svetluška", cdrak = "Dráčik" }
M.about = { homebrew = "kávový sliz: naťahuje sa, prilepí a pritiahne", drak = "vzlietne, sadne si na okno a stráži svoju šálku",
            ktulu = "Ph'nglui… mňau — chápadielka a krídelká", robot = "lieta s vrtuľkou, všetko naskenuje a odfotí",
            maid = "líščia slúžka: zametá, leští okná, kávička, selfie ♥", kapybara = "najpokojnejšia: bazénik a gumová kačička",
            latte = "skáče, plíži sa, uhýba kurzoru", mokka = "čierna mačka, v noci ju nevidno", tien = "teleportuje sa, občas niečo vezme a vráti",
            liska = "behá po ploche a hrá sa s kurzorom", myval = "zbiera drobnosti a ukrýva sa", svetluska = "v noci svieti", cdrak = "skáče, lieta, chrlí oheň" }
M.legacy = { macka = "latte", zrnko = "latte", void = "cdrak" }
M.flyers = { drak = true, svetluska = true, cdrak = true, robot = true }
M.modes = { "off", "slot", "world", "chaos" }
M.modeNames = { off = "Vypnutý", slot = "Ostrov", world = "Výbehy", chaos = "Chaos" }

function M.trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
-- vlastné postavy do zoznamu (za vstavané); volá sa pri otvorení panela a pri štarte widgetu
function M.loadUser()
  local ok, list = pcall(noctalia.json.decode, noctalia.readFile(M.userIndex) or "[]")
  for id in pairs(M.user) do
    for i = #M.order, 1, -1 do if M.order[i] == id then table.remove(M.order, i) end end
    M.names[id] = nil; M.about[id] = nil; M.flyers[id] = nil
  end
  M.user = {}
  if not ok or type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.id) == "string" and not M.names[e.id] then
      M.user[e.id] = true
      table.insert(M.order, e.id)
      M.names[e.id] = tostring(e.name or e.id); M.about[e.id] = tostring(e.about or "vlastný maskot")
      if e.flyer then M.flyers[e.id] = true end
    end
  end
end
-- obrázok lišty pre postavu (vlastné majú snímky v ~/.local/share)
function M.bar(k, frame) return (M.user[k] and M.userBar or M.dir) .. k .. "-" .. frame .. ".png" end
function M.kind()
  local k = M.trim(noctalia.readFile(M.cfg .. "/mascot") or "")
  k = M.legacy[k] or k
  return M.names[k] and k or (k == "ziadny" and "ziadny" or "homebrew")
end
function M.setKind(k) noctalia.mkdirAll(M.cfg); noctalia.writeFile(M.cfg .. "/mascot", k .. "\n") end
function M.mode()
  if M.kind() == "ziadny" then return "off" end
  local m = M.trim(noctalia.readFile(M.cfg .. "/mascot-mode") or "")
  if m == "" then m = (M.trim(noctalia.readFile(M.cfg .. "/mascot-escape") or "") == "off") and "slot" or "world" end
  return m
end
function M.setMode(m) noctalia.mkdirAll(M.cfg); noctalia.writeFile(M.cfg .. "/mascot-mode", m .. "\n") end
function M.run() return M.trim(noctalia.readFile(M.runFile) or "") end
function M.setRun(v) noctalia.writeFile(M.runFile, v) end

local function clamp(v) return math.max(0, math.min(100, v)) end

function M.load()
  local raw = noctalia.readFile(M.stateFile)
  local st
  if raw and raw ~= "" then
    local ok, v = pcall(noctalia.json.decode, raw)
    if ok and type(v) == "table" then st = v end
  end
  local now = os.time()
  st = st or { kava = 80, nalada = 80, energia = 80, narodeny = now, posledne = now, dni = 0, den = "" }
  st.kava = st.kava or 80; st.nalada = st.nalada or 80; st.energia = st.energia or 80
  st.narodeny = st.narodeny or now; st.posledne = st.posledne or now; st.dni = st.dni or 0; st.den = st.den or ""
  return st
end
function M.save(st) noctalia.mkdirAll(M.stateDir); noctalia.writeFile(M.stateFile, noctalia.json.encode(st)) end

-- plynutie času: bdie → ubúda káva a energia; spí (noc, Nerušiť, uložený spať) → energia pribúda
function M.decay(st, asleep)
  local now = os.time()
  local h = math.min(12, math.max(0, (now - (st.posledne or now)) / 3600))
  st.posledne = now
  if asleep then
    st.energia = clamp(st.energia + 25 * h); st.kava = clamp(st.kava - 2 * h)
  else
    st.kava = clamp(st.kava - 8 * h); st.energia = clamp(st.energia - 6 * h)
    st.nalada = clamp(st.nalada - (st.kava < 30 and 10 or 4) * h)
  end
  return st
end
-- starostlivosť (káva, pohladkanie, hra) → počíta dni spolu
function M.care(st)
  local d = os.date("%Y-%m-%d")
  if st.den ~= d then st.den = d; st.dni = (st.dni or 0) + 1 end
end
function M.feed(st) st.kava = clamp(st.kava + 35); st.energia = clamp(st.energia + 10); st.nalada = clamp(st.nalada + 5); M.care(st) end
function M.pet(st) st.nalada = clamp(st.nalada + 12); M.care(st) end
function M.play(st) st.nalada = clamp(st.nalada + 20); st.energia = clamp(st.energia - 10); st.kava = clamp(st.kava - 5); M.care(st) end
function M.nap(st) st.spanokDo = os.time() + 30 * 60 end

function M.mood(st)
  if st.kava < 20 then return "smutny", "chce kávu ☕" end
  if st.energia < 15 then return "spi", "je strašne unavený" end
  if st.nalada < 25 then return "smutny", "cíti sa osamelo — pohladkaj ho" end
  if st.nalada > 85 and st.kava > 50 then return "stastny", "je v pohode" end
  return "", ""
end

M.loadUser()
return M
