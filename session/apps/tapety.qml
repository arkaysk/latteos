// SPDX-License-Identifier: GPL-3.0-or-later
// LatteOS — Tapety sú od 25. 9. 2026 súčasťou Nastavení (zadanie: „tapety integrované ako súčasť nastavení“):
//   Nastavenia › Prostredie › Pozadie        obrázok, plná farba, prezentácia, živá tapeta, obrazovky, prispôsobenie
//   Nastavenia › Prostredie › Tapety online  katalógy MotionBGS, Wallhaven, Bing, minimalistické (z projektu Aura)
// Tento súbor iba presmeruje staré odkazy (latte-app tapety [kniznica|objavovat|obrazovky|nastavenia]).
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Process {
        command: ["latte-app", "nastavenia", (Quickshell.env("LATTE_APP_ARGS") || "").trim() === "objavovat" ? "tapetyonline" : "pozadie"]
        Component.onCompleted: { startDetached(); Qt.quit(); }
    }
}
