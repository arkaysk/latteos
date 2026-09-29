--!nonstrict
-- LatteOS — systémové menu šálky (zadanie 24. 9., bod 4): navrchu účet a jeho typ s Odhlásiť hneď vedľa,
-- potom Nastavenia a Monitor, rýchly stupeň výkonu a režim okien (v Nastaveniach › Lišta sa dajú skryť:
-- ~/.config/latteos/cup-quick = off) a napájanie. App Manager a Správca zariadení majú vlastné ostrovy,
-- témy, informácie o systéme a Nastavenia shellu sú v Nastaveniach.

local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local stateHome = noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local tierFile = cfgHome .. "/latteos/tier"
local windowFile = stateHome .. "/latteos/window-mode"

local tiers = { "auto", "plny", "standard", "usporny", "minimalny", "softver" }
local tierNames = { "Automaticky (podľa HW)", "Plný", "Štandard", "Úsporný", "Minimálny", "Softvér (VM)" }
local windowModes = { "paska", "dlazdice", "plavajuce" }
local windowNames = { "Nekonečná páska", "Dlaždice", "Plávajúce okná" }

local st = {}
local confirm = nil       -- akcia napájania čakajúca na potvrdenie

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function indexOf(list, v) for i, x in ipairs(list) do if x == v then return i - 1 end end return 0 end

local function load()
  local toml = noctalia.readFile("/run/latteos/mode.toml") or ""
  st.mode = string.match(toml, 'mode = "(%a+)"') or "safe"
  st.renderer = string.match(toml, 'renderer = "([%w%-]+)"') or "?"
  st.tier = string.match(toml, 'tier = "(%a+)"') or "?"
  st.reason = string.match(toml, 'reason = "([^"]*)"') or ""
  local forced = noctalia.fileExists(tierFile) and trim(noctalia.readFile(tierFile)) or ""
  st.tierChoice = (forced ~= "" and forced) or "auto"
  st.window = noctalia.fileExists(windowFile) and trim(noctalia.readFile(windowFile)) or "paska"
  st.forceSafe = noctalia.fileExists("/var/lib/latteos/force-safe")
  st.user = noctalia.getenv("USER") or "používateľ"
  st.quick = trim(noctalia.readFile(cfgHome .. "/latteos/cup-quick") or "") ~= "off"
  st.face = nil
  for _, f in ipairs({ home .. "/.face", "/var/lib/AccountsService/icons/" .. st.user }) do
    if noctalia.fileExists(f) then st.face = f; break end
  end
  noctalia.runAsync({ "sh", "-c", 'getent passwd "$USER" | cut -d: -f5 | cut -d, -f1; id -nG' }, function(r)
    local name, groups = string.match(r.stdout or "", "^([^\n]*)\n([^\n]*)")
    st.fullName = trim(name or "")
    st.admin = groups ~= nil and (" " .. groups .. " "):find(" wheel ") ~= nil
    render()
  end)
end

local function section(title, children)
  local rows = { ui.label({ text = title, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }) }
  for _, c in ipairs(children) do table.insert(rows, c) end
  return ui.column({ gap = 6, align = "stretch" }, rows)
end

local function action(label, hint, handler, danger)
  local row = { ui.button({ text = label, onClick = handler, flexGrow = 1, contentAlign = "start",
                            variant = danger and "destructive" or "ghost" }) }
  if hint then table.insert(row, ui.label({ text = hint, fontSize = 11, color = "on_surface_variant" })) end
  return ui.row({ align = "center", gap = 8 }, row)
end

local function latteRows(safe, modeText)
  local rows = { ui.label({ text = modeText, fontSize = 12, color = safe and "primary" or "on_surface" }) }
  if st.reason ~= "" then
    table.insert(rows, ui.label({ text = st.reason, fontSize = 11, color = "on_surface_variant", maxWidth = 330, maxLines = 3 }))
  end
  table.insert(rows, ui.label({ text = "Stupeň výkonu", fontSize = 12, color = "on_surface_variant" }))
  table.insert(rows, ui.select({ options = tierNames, selectedIndex = indexOf(tiers, st.tierChoice), onChange = "onTier", enabled = not safe }))
  table.insert(rows, ui.label({ text = "Režim okien (Super+W)", fontSize = 12, color = "on_surface_variant" }))
  table.insert(rows, ui.select({ options = windowNames, selectedIndex = indexOf(windowModes, st.window), onChange = "onWindow", enabled = not safe }))
  if safe then
    table.insert(rows, action("Skúsiť NORMAL znova", "odhlási", function()
      run({ "latte-boot", "reset" })
      run({ "noctalia", "msg", "session", "logout" })
    end))
  end
  return rows
end

function render()
  local safe = st.mode == "safe"
  local tierShown = (st.tierChoice ~= "auto") and (st.tierChoice .. " (vynútený)") or st.tier
  local modeText = (safe and "SAFE" or "NORMAL") .. " · " .. st.renderer .. " · stupeň " .. tierShown
  local power = {}
  for _, p in ipairs({ { "suspend", "Uspať" }, { "reboot", "Reštartovať" }, { "shutdown", "Vypnúť" } }) do
    local id, label = p[1], p[2]
    table.insert(power, ui.button({
      text = (confirm == id) and ("Naozaj? " .. label) or label,
      variant = (confirm == id) and "destructive" or nil,
      flexGrow = 1,
      onClick = function() onPower(id) end,
    }))
  end

  local who = (st.fullName and st.fullName ~= "") and st.fullName or st.user
  local kind = st.admin == nil and "…" or (st.admin and "Správca (môže inštalovať a meniť systém)" or "Štandardný účet")
  local body = {
    -- účet: meno, typ účtu; Odhlásiť a Zamknúť hneď vedľa
    ui.row({ align = "center", gap = 10 }, {
      st.face and ui.image({ path = st.face, width = 44, height = 44, radius = 22, fit = "cover" })
        or ui.row({ width = 44, height = 44, radius = 22, fill = "primary/0.18", align = "center", justify = "center" },
                  { ui.label({ text = string.upper(string.sub(who, 1, 1)), fontSize = 20, fontWeight = "bold", color = "primary" }) }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = who, fontSize = 16, fontWeight = "bold", color = "on_surface", maxWidth = 170, maxLines = 1 }),
        ui.label({ text = kind, fontSize = 11, color = "on_surface_variant", maxWidth = 170, maxLines = 2 }),
      }),
      ui.button({ glyph = "lock", variant = "ghost", tooltip = "Zamknúť (Super+L)", onClick = function() panel.close(); run({ "noctalia", "msg", "session", "lock" }) end }),
      ui.button({ text = "Odhlásiť", glyph = "logout", variant = "outline", onClick = function() run({ "noctalia", "msg", "session", "logout" }) end }),
    }),
    ui.row({ gap = 8 }, {
      ui.button({ text = "Nastavenia", glyph = "settings", variant = "primary", flexGrow = 1,
                  onClick = function() panel.close(); run({ "latte-app", "nastavenia" }) end }),
      ui.button({ text = "Monitor", glyph = "activity", variant = "outline", flexGrow = 1, tooltip = "Ctrl+Shift+Esc",
                  onClick = function() panel.close(); run({ "latte-app", "monitor" }) end }),
    }),
  }
  if st.quick or safe then
    table.insert(body, ui.separator({}))
    table.insert(body, section("Rýchlo", latteRows(safe, modeText)))
  end
  table.insert(body, ui.separator({}))
  table.insert(body, section("Napájanie", { ui.row({ gap = 8 }, power) }))
  table.insert(body, ui.button({ text = "Upraviť túto ponuku", glyph = "adjustments", variant = "ghost", contentAlign = "start",
                                 onClick = function() panel.close(); run({ "latte-app", "nastavenia", "lista" }) end }))

  panel.render(ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, body))
end

function run(argv)
  if not noctalia.runAsync(argv) then
    noctalia.notifyError("LatteOS", "Nepodarilo sa spustiť: " .. table.concat(argv, " "))
  end
end

-- hyprctl eval funguje iba v relácii NORMAL (Hyprland); v SAFE (labwc) sú voľby vypnuté
local function hyprEval(code) run({ "hyprctl", "eval", code }) end

function onTier(index, _text)
  local choice = tiers[(tonumber(index) or 0) + 1]
  if choice == "auto" then
    if noctalia.fileExists(tierFile) then noctalia.removeFile(tierFile) end
  else
    noctalia.mkdirAll(cfgHome .. "/latteos")
    noctalia.writeFile(tierFile, choice .. "\n")
  end
  run({ "hyprctl", "reload" })          -- Lua modul prečíta stupeň znova
  noctalia.notify("Stupeň výkonu", tierNames[(tonumber(index) or 0) + 1])
  load(); render()
end

function onWindow(index, _text)
  local m = windowModes[(tonumber(index) or 0) + 1]
  hyprEval('require("latte.windows").apply("' .. m .. '", true)')
  st.window = m
  render()
end

function onForceSafe(value)
  run({ "latte-boot", value == "true" and "force-safe" or "reset" })
  st.forceSafe = value == "true"
  render()
end

function onPower(id)
  if confirm ~= id then
    confirm = id           -- prvé kliknutie iba pripraví, druhé vykoná (nič nevypne priamo)
    render()
    return
  end
  confirm = nil
  panel.close()
  run({ "noctalia", "msg", "session", id })
end

function onOpen(_context)
  confirm = nil
  load()
  render()
end
