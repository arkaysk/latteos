--!nonstrict
-- Maskot: snímky /usr/share/latteos/noctalia/plugins/cat/mascots/<maskot>-<snímka>.png (12 postáv, make-mascots.py)
-- Pohyb iba keď hrá hudba (4 obr/s, výmena malého obrázka), inak raz za 2 s — lacné aj pri softvérovom kreslení.
-- Ktulu (Cthulhu mačka): občas jej z hrany lišty vyrastú chápadlá.
-- Potreby ako tamagoči (common.luau): káva, nálada, energia — smutný, keď chce kávu; unavený spí.
-- Režimy (panel na pravý klik): off · slot (ostrov; pri nečinnosti alebo z nudy odíde z ostrova a vráti sa) ·
--   world / chaos — výbehy mimo ostrova riadi maskot.qml (súbor $XDG_RUNTIME_DIR/latteos/maskot-von).
-- Klik = pohladkať / zavolať späť · pravý klik = panel maskota (postava, potreby, režim).
local C = require("./common.luau")

local kind = "homebrew"
local playing, dnd = false, false
local tick, petUntil, blink = 0, 0, false
local lastPoll = -100
-- útek v režime slot: tu | odchadza | prec | prichadza
local away, step = "tu", 0
local lastActive, lastPet, lastSeen = os.time(), os.time(), ""
local boredUntil = 0
local tentacles = 0          -- zostávajúce snímky chápadiel (Ktulu)
local st = C.load()
local lastSave = os.time()

local function show(frame)
  barWidget.setImage(C.bar(kind, frame), false, 44, 36)
end

-- Optimalizácia 26. 9.: predtým každé 3 s sh + playerctl + noctalia msg + 2× hyprctl + grep (6 procesov).
-- Teraz: hudba a aktivita okien z trvalých streamov (zmena príde hneď), kurzor raz za 10 s, Nerušiť raz za 30 s.
local streams, pollN = false, 0
local function startStreams()
  if streams then return end
  streams = true
  noctalia.runStream("playerctl --follow status", function(line)
    playing = string.match(line or "", "^%s*(%a+)") == "Playing"
    if playing then lastActive = os.time() end
  end)
  noctalia.runStream("latte-hypr-udalosti activewindowv2 openwindow closewindow workspacev2 windowtitlev2",
                     function(_line) lastActive = os.time() end)
end
local function poll()
  startStreams()
  pollN = pollN + 1
  local dndToo = pollN % 3 == 1
  noctalia.runAsync({ "sh", "-c", (dndToo and "echo \"dnd=$(noctalia msg notification-dnd-status 2>/dev/null)\"; " or "")
                      .. "echo \"kurzor=$(hyprctl cursorpos 2>/dev/null)\"" }, function(r)
    local out = r.stdout or ""
    if dndToo then dnd = string.match(out, "dnd=(%a*)") == "on" end
    local seen = string.match(out, "kurzor=([^\n]*)") or ""
    if seen ~= lastSeen then lastSeen = seen; lastActive = os.time() end
    if playing then lastActive = os.time() end       -- pri hudbe ťuká, neodchádza
  end)
end

local function asleepNow()
  local h = os.date("*t").hour
  return ((h >= 23 or h < 6 or dnd) and not playing) or (st.spanokDo or 0) > os.time() or st.energia < 10
end

local function stats()
  return string.format("☕ %d · ♥ %d · ⚡ %d · deň %d s tebou", math.floor(st.kava), math.floor(st.nalada), math.floor(st.energia), st.dni or 0)
end

function update()
  kind = C.kind()
  local mode = C.mode()
  if kind == "ziadny" or mode == "off" then barWidget.setVisible(false); noctalia.setUpdateInterval(30000); return end
  barWidget.setVisible(true)
  tick = tick + 1
  local now = os.time()
  if now - lastPoll >= 10 then lastPoll = now; poll() end
  -- potreby: plynutie času, uloženie raz za minútu (panel a maskot.qml čítajú ten istý súbor)
  local fresh = C.load()
  if (fresh.posledne or 0) > (st.posledne or 0) then st = fresh end
  C.decay(st, asleepNow())
  if now - lastSave >= 60 then C.save(st); lastSave = now end
  local moodFrame, moodText = C.mood(st)

  -- výbehy mimo ostrova (world/chaos): maskot.qml zapisuje stav, widget ukazuje odchod / prázdny ostrov / príchod
  if mode == "world" or mode == "chaos" then
    local run = C.run()
    if run == "vychadza" then
      if away ~= "odchadza" and away ~= "prec" then away, step = "odchadza", 0 end
    elseif run == "von" then
      away = "prec"
    elseif run == "prichadza" then
      if away == "prec" or away == "odchadza" then away, step = "prichadza", 3 end
    end
  else
    -- režim slot: útek z nečinnosti alebo z nudy, návrat pri aktivite
    local idle = now - lastActive
    if away == "tu" and (idle > 300 or (now - lastPet > 1800 and math.random(1, 400) == 1)) then
      away, step = "odchadza", 0
      if idle <= 300 then boredUntil = now + math.random(60, 150) end
    elseif away == "prec" and ((boredUntil > 0 and now > boredUntil and idle < 60) or (boredUntil == 0 and idle < 5)) then
      away, step, boredUntil = "prichadza", 3, 0
    end
  end
  if away == "odchadza" then
    step = step + 1
    if step > 3 then away = "prec"; show("prazdny") else show("odchod-" .. step) end
    noctalia.setUpdateInterval(450)
    barWidget.setTooltip({ { C.names[kind], "odchádza na prechádzku…" } })
    return
  elseif away == "prichadza" then
    if step < 1 then
      away = "tu"; lastPet = now; show("sedi")
      if C.run() == "prichadza" then C.setRun("") end
    else show("odchod-" .. step); step = step - 1 end
    noctalia.setUpdateInterval(450)
    return
  elseif away == "prec" then
    show("prazdny"); noctalia.setUpdateInterval(mode == "slot" and 3000 or 700)
    barWidget.setTooltip({ { C.names[kind], mode ~= "slot" and "je na výbehu po ploche (klik = zavolať domov)"
                             or (boredUntil > 0 and "nudil sa, šiel na prechádzku (klik = zavolať)" or "odišiel, kým si preč — vráti sa s tebou") } })
    return
  end

  local asleep = asleepNow()
  local frame
  if now < petUntil then
    frame = "hlad"; noctalia.setUpdateInterval(500)
  elseif playing then
    frame = (tick % 2 == 0) and "lapka-l" or "lapka-p"; noctalia.setUpdateInterval(250)
  elseif asleep then
    frame = "spi"; noctalia.setUpdateInterval(5000)
  elseif tentacles > 0 then
    tentacles = tentacles - 1
    frame = (tentacles % 2 == 0) and "chapadla-1" or "chapadla-2"; noctalia.setUpdateInterval(350)
  elseif blink then
    blink = false; frame = "zmurk"; noctalia.setUpdateInterval(2000)
  elseif moodFrame == "smutny" then
    frame = "smutny"; noctalia.setUpdateInterval(3000)
  else
    frame = "sedi"
    if kind == "ktulu" and math.random(1, 10) == 1 then tentacles = 8; noctalia.setUpdateInterval(350)     -- chápadlá z lišty
    elseif math.random(1, 5) == 1 then blink = true; noctalia.setUpdateInterval(180) else noctalia.setUpdateInterval(2000) end
  end
  show(frame)
  local line = playing and "ťuká do rytmu ♪" or (asleep and "spí… zZ" or (moodText ~= "" and moodText or C.about[kind]))
  barWidget.setTooltip({ { C.names[kind], line }, { "Potreby", stats() }, { "Klik", "pohladkať" }, { "Pravý klik", "panel maskota" } })
end

function onClick()
  lastPet = os.time(); lastActive = os.time()
  if away ~= "tu" then
    if C.mode() == "world" or C.mode() == "chaos" then C.setRun("domov") end     -- maskot.qml ho privedie domov
    away, step, boredUntil = "prichadza", 3, 0; noctalia.setUpdateInterval(100); return
  end
  C.pet(st); C.save(st)
  petUntil = os.time() + 2
  show("hlad")
  noctalia.setUpdateInterval(500)
end

function onRightClick()
  C.save(st)
  noctalia.togglePanel("latteos/cat:panel")
end
