--!nonstrict
-- Zariadenia — rýchle nastavenia. Stav sa číta príkazmi (nmcli, noctalia msg, wpctl, brightnessctl,
-- powerprofilesctl) asynchrónne; zmeny sa posielajú tými istými nástrojmi.
local home = noctalia.getenv("HOME") or ""
local stateHome = noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")

local st = { wifi = nil, ssid = "", bt = nil, dnd = nil, volume = nil, brightness = nil,
             profile = "balanced", profiles = { "power-saver", "balanced", "performance" }, game = false, tier = "?", tierForced = false }
local profileNames = { ["power-saver"] = "Úsporný", balanced = "Vyvážený", performance = "Výkon" }

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function refresh()
  local toml = noctalia.readFile("/run/latteos/mode.toml") or ""
  st.tier = string.match(toml, 'tier = "(%a+)"') or "?"
  local forced = noctalia.fileExists(cfgHome .. "/latteos/tier") and trim(noctalia.readFile(cfgHome .. "/latteos/tier")) or ""
  st.tierForced = forced ~= ""
  if st.tierForced then st.tier = forced end
  st.game = trim(noctalia.readFile(stateHome .. "/latteos/game-mode") or "0") == "1"

  noctalia.runAsync({ "nmcli", "-t", "-f", "WIFI", "radio" }, function(r) st.wifi = trim(r.stdout) == "enabled"; render() end)
  noctalia.runAsync({ "sh", "-c", "nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -1; nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | grep ':connected:' | head -1" },
    function(r)
      local lines = {}
      for l in string.gmatch(r.stdout or "", "[^\n]+") do table.insert(lines, l) end
      st.ssid = lines[1] or ""
      if st.ssid == "" and lines[1] then st.ssid = "" end
      st.wired = r.stdout and string.match(r.stdout, "ethernet:connected:([^\n]+)") or nil
      render()
    end)
  noctalia.runAsync({ "noctalia", "msg", "bluetooth-status" }, function(r) st.bt = string.find(string.lower(r.stdout or ""), "on") ~= nil and r.exitCode == 0; st.btAvail = r.exitCode == 0; render() end)
  noctalia.runAsync({ "noctalia", "msg", "notification-dnd-status" }, function(r) st.dnd = string.find(string.lower(r.stdout or ""), "on") ~= nil or string.find(string.lower(r.stdout or ""), "true") ~= nil; render() end)
  noctalia.runAsync({ "wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@" }, function(r)
    local v = string.match(r.stdout or "", "Volume: ([%d%.]+)")
    st.volume = v and math.floor(tonumber(v) * 100 + 0.5) or nil; render()
  end)
  noctalia.runAsync({ "brightnessctl", "-m", "-c", "backlight" }, function(r)
    local p = string.match(r.stdout or "", ",(%d+)%%,")
    st.brightness = (r.exitCode == 0 and p) and tonumber(p) or nil; render()
  end)
  noctalia.runAsync({ "powerprofilesctl", "get" }, function(r) st.profile = trim(r.stdout) ~= "" and trim(r.stdout) or st.profile; render() end)
end

local function run(argv) noctalia.runAsync(argv, function() refresh() end) end

local function tile(glyph, title, sub, on, handler, enabled)
  return ui.column({ fill = on and "primary" or "surface_variant", radius = 14, padding = 12, gap = 4, flexGrow = 1,
                     onClick = (enabled ~= false) and handler or nil }, {
    ui.glyph({ name = glyph, size = 20, color = on and "on_primary" or "on_surface" }),
    ui.label({ text = title, fontSize = 13, fontWeight = "bold", color = on and "on_primary" or "on_surface" }),
    ui.label({ text = sub, fontSize = 11, color = on and "on_primary" or "on_surface_variant", maxLines = 1, maxWidth = 150 }),
  })
end

local function heading(t) return ui.label({ text = t, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }) end

function render()
  local tierName = ({ plny = "Plný", standard = "Štandard", usporny = "Úsporný", minimalny = "Minimálny", softver = "Softvér" })[st.tier] or st.tier
  local net = st.wired and ("Kábel · " .. st.wired) or (st.ssid ~= "" and st.ssid or "nepripojené")
  local profIdx = 0
  for i, p in ipairs(st.profiles) do if p == st.profile then profIdx = i - 1 end end
  local profOptions = {}
  for _, p in ipairs(st.profiles) do table.insert(profOptions, profileNames[p] or p) end

  local body = {
    ui.row({ align = "center", justify = "space_between" }, {
      ui.column({ gap = 2 }, {
        ui.label({ text = "Zariadenia", fontSize = 17, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = "Stupeň: " .. tierName .. (st.tierForced and " (vynútený)" or " (auto)"), fontSize = 12, color = "on_surface_variant" }),
      }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    ui.row({ gap = 10 }, {
      st.wired and tile("network", "Sieť", "Kábel · " .. st.wired, true, function() run({ "foot", "-e", "nmtui" }) end)
               or tile("wifi", "Wi-Fi", st.wifi == nil and "…" or (st.wifi and net or "vypnuté"), st.wifi == true, function() run({ "noctalia", "msg", "wifi-toggle" }) end),
      tile("bluetooth", "Bluetooth", st.btAvail == false and "nedostupné" or (st.bt and "zapnuté" or "vypnuté"), st.bt == true,
           function() run({ "noctalia", "msg", "bluetooth-toggle" }) end, st.btAvail ~= false),
    }),
    ui.row({ gap = 10 }, {
      tile("bell-off", "Nerušiť", st.dnd and "zapnuté" or "vypnuté", st.dnd == true, function() run({ "noctalia", "msg", "notification-dnd-toggle" }) end),
      tile("moon", "Nočné svetlo", "podľa rozvrhu", false, function() run({ "noctalia", "msg", "nightlight-toggle" }) end),
    }),
    heading("HLASITOSŤ" .. (st.volume and ("  " .. st.volume .. " %") or "  (bez zvukového zariadenia)")),
    ui.slider({ min = 0, max = 100, step = 5, value = st.volume or 0, enabled = st.volume ~= nil, onDragEnd = "onVolume" }),
    heading("JAS" .. (st.brightness and ("  " .. st.brightness .. " %") or "  (monitor bez ovládania jasu)")),
    ui.slider({ min = 5, max = 100, step = 5, value = st.brightness or 100, enabled = st.brightness ~= nil, onDragEnd = "onBrightness" }),
    heading("HERNÝ REŽIM"),
    ui.row({ gap = 10, align = "center" }, {
      ui.toggle({ checked = st.game, onChange = "onGame" }),
      ui.label({ text = st.game and "Zapnutý: bez efektov, medzier a animácií" or "Vypnutý", flexGrow = 1 }),
    }),
    ui.label({ text = "Profil výkonu", fontSize = 12, color = "on_surface_variant" }),
    ui.select({ options = profOptions, selectedIndex = profIdx, onChange = "onProfile" }),
    ui.row({ gap = 8 }, {
      ui.button({ text = "Limit FPS", enabled = false, flexGrow = 1, tooltip = "na reálnom HW (gamescope)" }),
      ui.button({ text = "HDR", enabled = false, flexGrow = 1, tooltip = "na reálnom HW" }),
      ui.button({ text = "VRR", enabled = false, flexGrow = 1, tooltip = "na reálnom HW" }),
    }),
    heading("INTERNET PODĽA APLIKÁCIÍ (NET)"),
    ui.label({ text = "Internet pre každú aplikáciu zapneš a vypneš v App Manageri › Oprávnenia a NET (Flatpak aj bežné aplikácie).",
               fontSize = 12, color = "on_surface_variant", maxWidth = 360, maxLines = 3 }),
    ui.row({ gap = 8 }, {
      ui.button({ text = "Správca zariadení", glyph = "cpu", flexGrow = 1, onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "zariadenia" }) end }),
      ui.button({ text = "NET", glyph = "world", variant = "ghost", onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "aplikacie", "opravnenia" }) end }),
    }),
  }
  panel.render(ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, body))
end

function onVolume(v) run({ "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", tostring(math.floor(tonumber(v) or 0)) .. "%" }) end
function onBrightness(v) run({ "brightnessctl", "-c", "backlight", "set", tostring(math.floor(tonumber(v) or 100)) .. "%" }) end
function onProfile(index, _t)
  local p = st.profiles[(tonumber(index) or 0) + 1]
  if p then st.profile = p; run({ "powerprofilesctl", "set", p }) end
end
function onGame(value)
  st.game = value == "true"
  run({ "hyprctl", "eval", "latte.game(" .. (st.game and "true" or "false") .. ")" })
  render()
end

function onOpen(_ctx)
  render()
  refresh()
end
