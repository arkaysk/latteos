--!nonstrict
-- Režim Web (/web): hľadanie na webe iba na výslovnú žiadosť (radar: lokálne výsledky bez webu).
local function urlencode(s)
  return (string.gsub(s, "[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local engines = {
  { "DuckDuckGo", "https://duckduckgo.com/?q=", "world-search" },
  { "Wikipédia (sk)", "https://sk.wikipedia.org/w/index.php?search=", "book" },
  { "ProtonDB (hry na Linuxe)", "https://www.protondb.com/search?q=", "device-gamepad-2" },
}

function onQuery(text)
  local q = text or ""
  local results = {}
  if q ~= "" then
    for i, e in ipairs(engines) do
      table.insert(results, { id = e[2] .. urlencode(q), title = e[1] .. ": " .. q, subtitle = "otvorí prehliadač", glyph = e[3], score = 10 - i })
    end
  end
  launcher.setResults(text, results)
end

function onActivate(id)
  if id and id ~= "" then noctalia.runAsync({ "xdg-open", id }) end
end
