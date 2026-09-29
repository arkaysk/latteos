#!/usr/bin/env bash
# Stiahne plytké (depth 1) kópie projektov z inspo/LatteOS – technologický radar 2026.md,
# ktoré sa dajú priamo prebrať / integrovať. Kópie idú do upstream/ (netrackované v gite).
# Opätovné spustenie preskočí existujúce; na refresh zmaž priečinok projektu.
# Použitie: ./fetch.sh            – všetko
#           ./fetch.sh hyprland   – len vybrané názvy
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p upstream docs

only=("$@")
want() { [ ${#only[@]} -eq 0 ] && return 0; local n; for n in "${only[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

clone() {
    local name="$1" url="$2" ref="${3:-}"
    want "$name" || return 0
    if [ -d "upstream/$name/.git" ]; then echo "== $name: už je, preskakujem"; return; fi
    echo "== $name"
    git -c advice.detachedHead=false clone --quiet --depth 1 ${ref:+--branch "$ref"} "$url" "upstream/$name" \
        || { echo "!! $name: zlyhalo"; return 0; }
    printf '%s %s %s\n' "$name" "$(git -C "upstream/$name" rev-parse --short=12 HEAD)" "$url" >> upstream/COMMITS.txt
}

page() {   # uloží web stránku (článok z radaru) ako referenciu; $3 = prípona (html)
    local name="$1" url="$2" ext="${3:-html}"
    want "$name" || return 0
    [ -s "docs/$name.$ext" ] && return 0
    echo "== doc $name"
    curl -fsSL --max-time 60 -A 'Mozilla/5.0' "$url" -o "docs/$name.$ext" \
        || { rm -f "docs/$name.$ext"; echo "!! doc $name: zlyhalo"; }
}

# --- Kompozitor (Základ, bez forku; patch v patches/) -----------------------
clone hyprland            https://github.com/hyprwm/Hyprland.git
clone aquamarine          https://github.com/hyprwm/aquamarine.git
clone xdg-desktop-portal-hyprland https://github.com/hyprwm/xdg-desktop-portal-hyprland.git
clone hyprland-plugins    https://github.com/hyprwm/hyprland-plugins.git   # hyprbars: okenné tlačidlá
clone hyprlock            https://github.com/hyprwm/hyprlock.git
clone hypr-darkwindow     https://github.com/micha4w/Hypr-DarkWindow.git
clone hyprwindowshade     https://github.com/ManofJELLO/HyprWindowShade.git

# --- SAFE režim (núdzový kompozitor, wlroots) ------------------------------
clone labwc               https://github.com/labwc/labwc.git
clone wlroots             https://gitlab.freedesktop.org/wlroots/wlroots.git

# --- Shell (Prebrať / forknúť) ---------------------------------------------
clone dankmaterialshell   https://github.com/AvengeMedia/DankMaterialShell.git
clone quickshell          https://github.com/quickshell-mirror/quickshell.git
clone caelestia-shell     https://github.com/caelestia-dots/shell.git
# Caelestia: zdroj prvkov pre silnejšie PC (stupeň Plný) — animácie, dashboard, pluginy
clone caelestia-dotfiles  https://github.com/caelestia-dots/caelestia.git
clone caelestia-cli       https://github.com/caelestia-dots/cli.git
clone matugen             https://github.com/InioX/matugen.git
# referencie pre UI prvky (Prebrať z …)
clone noctalia-shell      https://github.com/noctalia-dev/noctalia-shell.git
clone noctalia-greeter    https://github.com/noctalia-dev/noctalia-greeter.git
clone noctalia-plugins    https://github.com/noctalia-dev/noctalia-plugins.git
clone noctalia-official-plugins https://github.com/noctalia-dev/official-plugins.git
clone end4-dots-hyprland  https://github.com/end-4/dots-hyprland.git
clone ml4w-dotfiles       https://github.com/mylinuxforwork/dotfiles.git

# --- Hry --------------------------------------------------------------------
clone proton              https://github.com/ValveSoftware/Proton.git proton-11.0-1
clone umu-launcher        https://github.com/Open-Wine-Components/umu-launcher.git
clone gamescope           https://github.com/ValveSoftware/gamescope.git
clone mangohud            https://github.com/flightlessmango/MangoHud.git
clone lepton              https://gitlab.steamos.cloud/frame-public/lepton.git
clone waydroid            https://github.com/waydroid/waydroid.git

# --- Pamäť a stabilita (OOM politika Ubuntu 26.10 → Fedora) ----------------
clone ubuntu-settings     https://git.launchpad.net/~ubuntu-desktop/ubuntu/+source/ubuntu-settings 26.10.1

# --- Manageri (vzory) -------------------------------------------------------
clone cosmic-files        https://github.com/pop-os/cosmic-files.git
clone mission-center      https://gitlab.com/mission-center-devs/mission-center.git

# --- AI ---------------------------------------------------------------------
clone ollama              https://github.com/ollama/ollama.git
# Qwen3-14B-sk: len karta modelu; váhy (~29 GB, GGUF Q6_K ~12 GB) sa sťahujú až na cieľovom stroji
page  qwen3-14b-sk-card   https://huggingface.co/slovak-nlp/Qwen3-14B-sk/raw/main/README.md md

# --- NVIDIA / základ OS (neskoršie fázy) -------------------------------------
clone nvidia-fedora-guide https://github.com/fady-saied/Nvidia-Fedora-Guide.git
clone bazzite             https://github.com/ublue-os/bazzite.git

# --- Články z radaru s verdiktom Prebrať / Základ ----------------------------
page  ubuntu-2610-oom     https://itsfoss.com/news/ubuntu-26-10-oom-policy/
page  valve-lepton        https://itsfoss.com/news/valve-lepton/
page  hyprland-0.56       https://hypr.land/news/update56/
page  hyprland-0.55-0.56  https://alternativeto.net/news/2026/7/hyprland-0-56-adds-new-layout-options-and-expands-lua-api-features/
page  proton-11-release   https://github.com/ValveSoftware/Proton/releases/tag/proton-11.0-1
page  nvidia-595          https://ubuntuhandbook.org/index.php/2026/03/nvidia-595-58-03-released-with-better-wayland-linux-gaming-support/
page  nvidia-580-last     https://www.phoronix.com/news/NVIDIA-580-Linux-Driver-Last-HW
page  nvk-maxwell         https://www.phoronix.com/news/NVK-Vulkan-1.4-Maxwell
page  fedora-nvidia       https://linuxcapable.com/how-to-install-nvidia-drivers-on-fedora-linux/
page  qwen3-14b-sk        https://www.veda.sk/slovensky-jazykovy-model-qwen3-14b-sk-slovencina-ai/
page  hyprland-vmwgfx-12966 https://github.com/hyprwm/Hyprland/discussions/12966
page  omarchy-virtualbox  https://github.com/omacom/omarchy/discussions/7758

echo "Hotovo. Commity: upstream/COMMITS.txt, popis: MANIFEST.md"
