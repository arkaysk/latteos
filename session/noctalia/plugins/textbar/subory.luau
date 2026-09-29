--!nonstrict
-- Režim Lokálne: súbory a priečinky v domovskom priečinku (aj v bežnom hľadaní, od 3 znakov).
-- plocate (index, rýchle) alebo find (hĺbka 5, bez skrytých). Dopyt ide ako argument, nie do shellu.
local home = noctalia.getenv("HOME") or ""
local last = ""

function onQuery(text)
  local q = string.gsub(text or "", "^%s*(.-)%s*$", "%1")
  if #q < 3 then launcher.setResults(text, {}); return end
  last = q
  local script = [[
home="$1"; q="$2"
if command -v plocate >/dev/null 2>&1 && out="$(plocate -i -l 400 -- "$q" 2>/dev/null)"; then
  printf '%s\n' "$out" | grep "^$home/" | grep -v '/\.' | head -8
else
  find "$home" -maxdepth 5 \( -name '.*' -prune \) -o -iname "*$q*" -print 2>/dev/null | head -8
fi]]
  noctalia.runAsync({ "sh", "-c", script, "sh", home, q }, function(r)
    if q ~= last then return end
    local results = {}
    for path in string.gmatch(r.stdout or "", "[^\n]+") do
      local name = string.match(path, "([^/]+)$") or path
      local dir = string.match(path, "^(.*)/[^/]*$") or ""
      local isDir = noctalia.listDir(path) ~= nil
      table.insert(results, { id = path, title = name, subtitle = string.gsub(dir, "^" .. string.gsub(home, "%p", "%%%0"), "~"),
                              glyph = isDir and "folder" or "file", score = 50 - #results })
    end
    launcher.setResults(text, results)
  end, 4000)
end

function onActivate(id)
  if not id or id == "" then return end
  if noctalia.listDir(id) ~= nil then noctalia.runAsync({ "latte-app", "subory", id })
  else noctalia.runAsync({ "xdg-open", id }) end
end
