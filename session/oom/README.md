# OOM politika LatteOS (F5)

Prevzaté z nápadu Ubuntu 26.10 (`resources/upstream/ubuntu-settings/oom`, GPL-2+), prispôsobené LatteOS.
Pri nedostatku pamäte má jadro (a systemd-oomd) ukončiť najprv **aplikáciu**, nie reláciu.

| Čo | Hodnota | Kde |
|---|---|---|
| správca používateľa `user@.service` | `OOMScoreAdjust=-500`, `ManagedOOMMemoryPressure=auto` | `user@.service.d/` |
| služby spustené správcom používateľa (predvolene) | `DefaultOOMScoreAdjust=100` | `user.conf.d/` |
| dôležité služby relácie (dbus, pipewire, portály, gvfs…) | `OOMScoreAdjust=-500` | `user/<služba>.service.d/` |
| okná aplikácií v Hyprlande | `oom_score_adj +300` pri otvorení okna | `hypr/hyprland.lua` (`window.open` → `choom`) |

Kompozitor Hyprland a shell Noctalia bežia v rozsahu relácie greetd (`session-N.scope`), nie pod
`user@`, takže majú 0; aplikácie z okien +300. Pri OOM teda padne najprv prehliadač, nie lišta ani celá plocha.

Overenie: `systemctl show user@$(id -u) -p OOMScoreAdjust`, `cat /proc/$(pidof foot)/oom_score_adj`.
