# Patche nad upstreamom

## vmwgfx dmabuf — patch proti čiernej obrazovke vo VM

| Súbor | Cieľ | Overené |
|---|---|---|
| `hyprland-0.56.2-vmwgfx-dmabuf.patch` | Hyprland `src/protocols/LinuxDMABUF.cpp` | `git apply --check` na tagu **v0.56.2**, teda na verzii balíka v COPR `lionheartp/Hyprland` |
| `hyprland-main-vmwgfx-dmabuf.patch` | to isté, vetva `main` | `git apply --check` na `23118f9f7f24` (= `hyprland-git` v COPR); `LOGM` → `LOG` |
| `wlroots-vmwgfx-dmabuf.patch` | wlroots `types/wlr_linux_dmabuf_v1.c` (labwc, SAFE režim) | `git apply --check` na 0.21-dev (`297e01d2d4a7`) |

**Autor:** Pascal-0x90, [hyprwm/Hyprland diskusia #12966](https://github.com/hyprwm/Hyprland/discussions/12966) (31. 8. 2026).
Do upstreamu zatiaľ nie je začlenený. Pôvodný balík opráv
`ClaireDuSoleil/hyprland-vmware-fix` už neexistuje (404).

**Príznak:** Hyprland štartuje, ale ukáže čiernu plochu, prípadne len kurzor. GPU klienti (kitty,
alacritty, Quickshell, tapeta) padnú na prvom snímku s chybou
`invalid arguments for wl_surface.attach`.

**Príčina:** kernelový ovládač `vmwgfx` pri importe dmabuf-u (`vmw_prime_fd_to_handle`) vráti
**TTM** handle namiesto GEM handle. Kompozitor ho potom nevie zavrieť cez `drmCloseBufferHandle`
(EINVAL) a klienta odpojí.

**Oprava:** ak `drmCloseBufferHandle` zlyhá a zariadenie je `vmwgfx`, handle sa uvoľní cez
`DRM_VMW_UNREF_SURFACE`. Na iných ovládačoch sa správanie nemení.

**Týka sa aj VirtualBoxu:** grafický adaptér VMSVGA sa v hosťovi hlási ako `VMware SVGA II
[15ad:0405]` a používa rovnaký ovládač `vmwgfx`. Overené na `latteOSdev`.
Chyba sa prejaví iba pri **zapnutej 3D akcelerácii**. Bez nej Mesa nepoužije ovládač `svga`
a klienti kreslia cez llvmpipe a zdieľanú pamäť.

Doplnkové nastavenia pre VM (nie sú súčasťou patchu, pozri ROADMAP F1):
`cursor { no_hardware_cursors = true }` a pri problémoch `LIBGL_ALWAYS_SOFTWARE=1` pre klientov.
