--!nonstrict
-- Režim Linux príkaz (/cmd): náhľad príkazu, beh v termináli. Deštruktívne príkazy vyžadujú potvrdenie
-- (druhý výber), sudo sa nikdy nespúšťa potichu — heslo zadáva používateľ v termináli.
local CONFIRM = "  #potvrdit"

-- príkazy nebezpečné samy osebe (kontroluje sa prvé slovo každej časti za ; && || | $( `)
local dangerWords = {
  sudo = true, pkexec = true, su = true, doas = true,                                  -- práva správcu
  rm = true, rmdir = true, shred = true, truncate = true, srm = true, unlink = true,     -- mazanie
  dd = true, wipefs = true, fdisk = true, sfdisk = true, parted = true, blkdiscard = true, -- disky
  kill = true, killall = true, pkill = true, poweroff = true, reboot = true, shutdown = true, halt = true,
}
-- vzory kdekoľvek v príkaze
local dangerous = {
  "mkfs", "%-delete", "chmod%s+%-[%a]*R", "chown%s+%-[%a]*R",
  ">%s*/dev/[sn]", ">%s*/etc/", ">%s*/boot/", ">%s*/usr/",
  "%f[%w]mv%s.-%s/[%a]*%s*$",                                                         -- presun do koreňa
  "dnf%s+remove", "dnf%s+erase", "dnf%s+autoremove", "rpm%s+%-e", "flatpak%s+uninstall", "flatpak%s+remove",
  "systemctl%s+stop", "systemctl%s+disable", "systemctl%s+mask", "systemctl%s+poweroff", "systemctl%s+reboot",
  "git%s+reset%s+%-%-hard", "git%s+clean%s", "git%s+push%s.-%-%-force", "git%s+push%s.-%-f%f[%W]",
  "|%s*s?h%f[%W]", "|%s*bash", "|%s*zsh",                                              -- skript z internetu do shellu
  ":%(%)%s*{",
}

local function isDangerous(cmd)
  for seg in string.gmatch(cmd .. ";", "(.-)[;&|`(\n]") do
    local w = string.match(seg, "^[%s$]*([%w%._/%-]+)")
    if w then
      w = string.match(w, "([^/]+)$")                                                  -- /usr/bin/rm → rm
      if dangerWords[w] or string.find(w, "^mkfs") then return true end
    end
  end
  for _, p in ipairs(dangerous) do
    if string.find(cmd, p) then return true end
  end
  return false
end

function onQuery(text)
  local raw = text or ""
  local confirmed = string.sub(raw, -#CONFIRM) == CONFIRM
  local cmd = confirmed and string.sub(raw, 1, #raw - #CONFIRM) or raw
  cmd = string.gsub(cmd, "^%s+", "")
  if cmd == "" then
    launcher.setResults(text, { { id = "", title = "Napíš Linux príkaz", subtitle = "spustí sa v termináli; nebezpečné príkazy treba potvrdiť", glyph = "terminal-2" } })
    return
  end
  if isDangerous(cmd) and not confirmed then
    launcher.setResults(text, {
      { id = "", title = "⚠ Pozor: " .. cmd, subtitle = "Príkaz môže mazať alebo meniť systém. Vyber znova na potvrdenie.",
        glyph = "alert-triangle", query = "/cmd " .. cmd .. CONFIRM },
    })
    return
  end
  launcher.setResults(text, {
    { id = cmd, title = cmd, subtitle = confirmed and "Potvrdené — spustiť v termináli" or "Spustiť v termináli", glyph = "player-play" },
  })
end

function onActivate(id)
  if id == nil or id == "" then return end
  -- terminál ostane otvorený, kým ho používateľ nezavrie Enterom
  noctalia.runInTerminal(id .. "; echo; read -r -p '[LatteOS] Enter zatvorí terminál… ' _")
end
