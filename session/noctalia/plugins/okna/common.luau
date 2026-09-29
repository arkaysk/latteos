--!nonstrict
-- spoločné pre ovál a ponuku okna
local M = {}
local home = noctalia.getenv("HOME") or ""
M.stateDir = (noctalia.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/latteos"
M.hoverFile = M.stateDir .. "/nahlad"                 -- adresa okna pod myšou (pre živý náhľad)
M.targetFile = noctalia.pluginDataDir() .. "/ciel"    -- okno, pre ktoré je otvorená ponuka

function M.eval(code) noctalia.runAsync({ "hyprctl", "eval", code }) end
function M.isMin(w) return type(w.workspace) == "table" and tostring(w.workspace.name or ""):find("^special:minimized") ~= nil end
-- aplikácie LatteOS majú všetky triedu org.quickshell: podľa titulku dostanú glyf LatteOS
local latte = { ["Aplikácie"] = "apps", ["Monitor"] = "activity", ["Nastavenia"] = "settings", ["Správca zariadení"] = "devices",
                ["Súbory"] = "folder", ["Inštalátor"] = "package", ["Barista"] = "coffee" }
function M.glyph(w)
  if (w.class or "") ~= "org.quickshell" then return nil end
  local t = w.title or ""
  if string.find(t, "Heidelberg") then return "file-text" end
  return latte[string.match(t, "^(.-) — LatteOS$") or ""] or "app-window"
end
function M.icon(w)
  if M.glyph(w) then return nil end
  return noctalia.appIconPath(w.class or "", 48)
end
function M.name(w)
  local t = w.title or ""
  if t == "" then t = w.class or "okno" end
  t = string.gsub(t, " — LatteOS$", "")
  return t
end
return M
