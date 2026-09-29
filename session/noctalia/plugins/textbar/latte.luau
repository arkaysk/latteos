--!nonstrict
-- Režim Lokálne: nastavenia a akcie LatteOS, hľadané aj bez prefixu (spolu s aplikáciami Noctalie).
local home = noctalia.getenv("HOME") or ""
local cfgHome = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")

local function hypr(code) return { "hyprctl", "eval", code } end
local function tier(name)
  return { "sh", "-c", "mkdir -p '" .. cfgHome .. "/latteos' && printf '%s\\n' " .. name .. " > '" .. cfgHome .. "/latteos/tier' && hyprctl reload" }
end

-- { title, subtitle, glyph, kľúčové slová, príkaz }
local items = {
  { "Systémové menu LatteOS", "Relácia, systém, režim, napájanie", "coffee", "system menu latte napajanie", { "noctalia", "msg", "panel-toggle", "latteos/system:menu" } },
  { "Režim okien: nekonečná páska", "Super+W prepína", "layout-columns", "okna paska scrolling rezim", hypr('require("latte.windows").apply("paska", true)') },
  { "Režim okien: dlaždice", "Super+W prepína", "layout-grid", "okna dlazdice tiling rezim", hypr('require("latte.windows").apply("dlazdice", true)') },
  { "Režim okien: plávajúce", "Super+W prepína", "app-window", "okna plavajuce floating rezim", hypr('require("latte.windows").apply("plavajuce", true)') },
  { "Stupeň výkonu: Plný", "Sklo, blur, žiara, animácie", "bolt", "stupen vykon plny efekty blur", tier("plny") },
  { "Stupeň výkonu: Štandard", "Menší blur, animácie", "bolt", "stupen vykon standard", tier("standard") },
  { "Stupeň výkonu: Úsporný", "Bez blur a tieňov, krátke animácie", "leaf", "stupen vykon usporny", tier("usporny") },
  { "Stupeň výkonu: Softvér", "Bez efektov (VM, slabé PC)", "cpu", "stupen vykon softver vm", tier("softver") },
  { "Stupeň výkonu: automaticky", "Podľa hardvéru (latte-boot)", "wand", "stupen vykon auto automaticky", { "sh", "-c", "rm -f '" .. cfgHome .. "/latteos/tier' && hyprctl reload" } },
  { "Nabudúce naštartovať SAFE", "Núdzový režim pri ďalšom štarte", "shield", "safe nudzovy rezim start", { "latte-boot", "force-safe" } },
  { "Nastavenia", "Softvér, dáta, hardvér, účet, prostredie, systém", "settings", "nastavenia settings vzhlad vykon", { "latte-app", "nastavenia" } },
  { "Nastavenia shellu", "Lišta, panely, widgety (Noctalia)", "adjustments", "nastavenia shell lista panely widgety", { "noctalia", "msg", "settings-open" } },
  { "Tapeta", "Vybrať tapetu LatteOS", "photo", "tapeta wallpaper pozadie", { "noctalia", "msg", "panel-toggle", "wallpaper" } },
  { "Riadiace centrum", "Wi-Fi, Bluetooth, zvuk, jas", "adjustments", "riadiace centrum wifi bluetooth zvuk device", { "noctalia", "msg", "panel-toggle", "control-center" } },
  { "Sieť", "Pripojenia (nmtui)", "wifi", "siet wifi internet network", { "foot", "-e", "nmtui" } },
  { "Monitor (správca procesov)", "Ctrl+Shift+Esc · procesy, po štarte, telemetria", "activity", "monitor procesy task manager aktivita autorun", { "latte-app", "monitor" } },
  { "Aplikácie (App Manager)", "Objavovať, aktualizácie, nainštalované, NET", "apps", "aplikacie app manager instalovat obchod flathub aktualizacie", { "latte-app", "aplikacie" } },
  { "Aktualizovať systém a aplikácie", "App Manager › Aktualizácie", "refresh", "aktualizacie update upgrade", { "latte-app", "aplikacie", "aktualizacie" } },
  { "Správca zariadení", "Obrazovky, grafika, zvuk, sieť, disky, vstup", "cpu", "zariadenia device manager hardver obrazovka rozlisenie", { "latte-app", "zariadenia" } },
  { "Rozlíšenie obrazovky", "Správca zariadení › Obrazovky", "device-desktop", "obrazovka rozlisenie mierka monitor display", { "latte-app", "zariadenia", "obrazovky" } },
  { "Heidelberg (nový dokument)", "Editor dokumentov LatteOS: Markdown, HTML, text", "file-text", "heidelberg editor dokument text poznamka markdown", { "latte-app", "heidelberg" } },
  { "Barista (sprievodca)", "Vzhľad, okná, lišta, AI a aplikácie krok za krokom", "coffee", "barista sprievodca uvod zaciatok nastavenie welcome", { "latte-app", "barista" } },
  { "Herňa", "Hry zo Steamu a Heroicu · Super+G", "device-gamepad-2", "hry herna games steam heroic epic gog hrat", { "noctalia", "msg", "panel-open", "latteos/games:panel" } },
  { "Po štarte", "Čo sa spúšťa pri prihlásení (Monitor)", "player-play", "autorun autostart po starte sluzby", { "latte-app", "monitor", "autorun" } },
  { "AI", "Lokálne, domáci server, cloud (Nastavenia)", "sparkles", "ai llm lm studio ollama claude chatgpt", { "latte-app", "nastavenia", "ai" } },
  { "Kalendár", "Panel Čas · plánovač udalostí", "calendar", "kalendar udalosti planovac todo", { "noctalia", "msg", "panel-open", "latteos/time:panel" } },
  { "Súbory", "Data Manager: Tento počítač, dva panely", "folder", "subory files data manager disky", { "latte-app", "subory" } },
  { "Terminál", "predvolený terminál", "terminal-2", "terminal konzola shell", { "latte-terminal" } },
  { "Zamknúť obrazovku", "Super+L", "lock", "zamknut lock", { "noctalia", "msg", "session", "lock" } },
}

-- témy LatteOS: „Téma: Rubín“ … (latte-theme set <id>)
for _, f in ipairs(noctalia.listDir("/usr/share/latteos/themes") or {}) do
  local id = string.match(f, "^([%w_-]+)%.theme$")
  if id then
    local body = noctalia.readFile("/usr/share/latteos/themes/" .. f) or ""
    local name = string.match(body, "\nname = ([^\n]+)") or id
    local desc = string.match(body, "\ndesc = ([^\n]+)") or ""
    table.insert(items, { "Téma: " .. name, desc, "palette", "tema theme vzhlad farby " .. id, { "latte-theme", "set", id } })
  end
end

function onQuery(text)
  local q = string.lower(text or "")
  local results = {}
  if q == "" then
    launcher.setResults(text, results)
    return
  end
  for i, it in ipairs(items) do
    local hay = string.lower(it[1] .. " " .. it[4])
    local score = noctalia.fuzzyScore(q, hay)
    if score then
      -- presná zhoda so slovom (napr. „tema“, „stupen“) má prednosť pred fuzzy zhodou aplikácií
      if string.find(" " .. it[4] .. " ", " " .. q, 1, true) then score = score + 1000 end
      table.insert(results, { id = tostring(i), title = it[1], subtitle = it[2], glyph = it[3], score = score })
    end
  end
  launcher.setResults(text, results)
end

function onActivate(id)
  local it = items[tonumber(id) or 0]
  if it then noctalia.runAsync(it[5]) end
end
