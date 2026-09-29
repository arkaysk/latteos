--!nonstrict
-- spoločné pre widget a panel: položky z cliphist („id<TAB>náhľad“)
local M = {}

function M.parse(out)
  local items = {}
  for line in string.gmatch(out or "", "[^\n]+") do
    local id, prev = string.match(line, "^(%d+)\t(.*)$")
    if id then
      local fmt, dim = string.match(prev, "^%[%[ binary data .- (%a+) (%d+x%d+) %]%]$")   -- obrázok v cliphist
      table.insert(items, { id = id, text = prev, image = fmt ~= nil, fmt = fmt, dim = dim })
    end
  end
  return items
end

function M.label(it, n)
  if it.image then return "Obrázok " .. (it.dim or "") end
  local t = string.gsub(it.text, "%s+", " ")
  if #t > n then t = string.sub(t, 1, n) .. "…" end
  return t
end

return M
