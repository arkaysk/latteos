-- engine Goo — logika scény plochy LatteOS GOO. Celé správanie je v lib/engine.luau; tu sa iba spustí: moduly
-- programátorov (kvapky/zoznam.luau) a kvapky používateľa (+ príklady z priklady/).
-- Na VEDĽAJŠOM monitore (latte-kvapky: LATTE_GOO_VEDLAJSI=1) beží druhá inštancia iba s GooBarom: lišta s oknami
-- toho monitora, ako panel úloh Windows na druhej obrazovke; ostatné kvapky sú iba na hlavnom.
local engine = require("lib/engine")
local moduly = require("kvapky/zoznam")
local function env(n) local ok, v = pcall(sys.ask, "env", n) return ok and type(v) == "string" and v or "" end
local vedlajsi = env("LATTE_GOO_VEDLAJSI") == "1"

engine.start({
    moduly = vedlajsi and { "goobar" } or moduly,
    vedlajsi = vedlajsi,
    monitor_id = tonumber(env("LATTE_GOO_MONITOR_ID")),   -- okná iba z tohto monitora (číslo monitora v Hyprlande)
    pouzivatel = not vedlajsi,
    priklady = not vedlajsi,   -- test: aj JSON z priklady/ (používateľove sú v ~/.config/latteos/goo/kvapky/)
    ladenie = not vedlajsi,    -- vľavo hore posledná udalosť (klik, koliesko, pustenie…), na overovanie vstupov
    prva = 0.02,          -- test: skúšobné kvapky vľavo na lište (od 2 % šírky, rozostup 3 %), vpravo Goobar s oknami,
    prva_koniec = 0.33,   -- DaNoGoo a QueenGoo ako v Kvapkách
})
