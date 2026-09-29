--!nonstrict
-- Rýchle nastavenia Text Baru (pravý klik na lište): režim, kde beží AI (aj prihlásenie v prehliadači
-- bez API kľúča, alebo Bez AI), ktorá webová AI. Podrobnosti sú v Nastaveniach › Softvér › AI.
local home = noctalia.getenv("HOME") or ""
local cfg = (noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/latteos"
local modeFile = noctalia.pluginDataDir() .. "/mode"
local st = { mode = "local", provider = "domaci", web = "claude" }

local function load()
  st.mode = string.match(noctalia.readFile(modeFile) or "", "%a+") or "local"
  local t = noctalia.readFile(cfg .. "/ai.toml") or ""
  st.provider = string.match(t, 'provider%s*=%s*"([%a]+)"') or "domaci"
  st.web = string.match(t, 'web%s*=%s*"([%a]+)"') or "claude"
end

local function set(k, v) noctalia.runAsync({ "latte-ai", "set", k, v }, function() load(); render() end) end
local function choice(text, sub, on, onClick)
  return ui.button({ text = text .. (sub and ("  ·  " .. sub) or ""), variant = on and "primary" or "ghost", contentAlign = "start", onClick = onClick })
end
local function heading(t) return ui.label({ text = t, fontSize = 11, fontWeight = "bold", color = "on_surface_variant" }) end

function render()
  local modes = { { "local", "Lokálne" }, { "web", "Web" }, { "ai", "AI" }, { "cmd", "Príkaz" } }
  local mrow = {}
  for _, m in ipairs(modes) do
    if not (m[1] == "ai" and st.provider == "ziadna") then
      table.insert(mrow, ui.button({ text = m[2], variant = st.mode == m[1] and "primary" or "outline", controlSize = "sm", flexGrow = 1,
                                     onClick = function() noctalia.writeFile(modeFile, m[1]); st.mode = m[1]; render() end }))
    end
  end
  local body = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "search", size = 18, color = "primary" }),
      ui.label({ text = "Text Bar", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
    }),
    heading("REŽIM PO KLIKNUTÍ"),
    ui.row({ gap = 6 }, mrow),
    heading("AI"),
    choice("Domáci server", "LM Studio, Ollama v sieti", st.provider == "domaci", function() set("provider", "domaci") end),
    choice("Tento počítač", "Ollama, bez internetu", st.provider == "lokalne", function() set("provider", "lokalne") end),
    choice("Prihlásenie v prehliadači", "bez API kľúča", st.provider == "web", function() set("provider", "web") end),
  }
  if st.provider == "web" then
    local wrow = {}
    for _, w in ipairs({ { "claude", "Claude" }, { "chatgpt", "ChatGPT" }, { "perplexity", "Perplexity" }, { "copilot", "Copilot" } }) do
      table.insert(wrow, ui.button({ text = w[2], variant = st.web == w[1] and "primary" or "outline", controlSize = "sm", flexGrow = 1,
                                     onClick = function() set("web", w[1]) end }))
    end
    table.insert(body, ui.row({ gap = 6 }, wrow))
  end
  table.insert(body, choice("Veľké AI cez API kľúč", "Claude, ChatGPT, Gemini", st.provider == "cloud", function() set("provider", "cloud") end))
  table.insert(body, choice("Bez AI", "LatteOS AI nikde neponúka", st.provider == "ziadna", function() set("provider", "ziadna") end))
  table.insert(body, ui.separator({}))
  table.insert(body, ui.button({ text = "Všetky nastavenia AI", glyph = "settings", variant = "ghost", contentAlign = "start",
                                 onClick = function() panel.close(); noctalia.runAsync({ "latte-app", "nastavenia", "ai" }) end }))
  panel.render(ui.scroll({ flexGrow = 1, gap = 8, align = "stretch" }, body))
end

function onOpen(_ctx) load(); render() end
