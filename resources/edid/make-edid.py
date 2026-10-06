#!/usr/bin/env python3
# EDID 1.4 virtuálneho monitora LatteOS: 1920×1080 @ 60 Hz (CEA timing 148,5 MHz), názov „LATTE-VIRT“.
# Jadro ho dá voľnému výstupu grafickej karty (drm.edid_firmware=DP-1:edid/latte-virt-1080p.bin video=DP-1:e),
# takže karta má „monitor“ aj bez monitora: Sunshine ho sníma cez KMS od prihlasovacej obrazovky po každú reláciu.
import sys
e = bytearray(128)
e[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
mid = (ord('L') - 64) << 10 | (ord('A') - 64) << 5 | (ord('T') - 64)       # výrobca „LAT“
e[8:10] = mid.to_bytes(2, "big")
e[10:12] = (0x0001).to_bytes(2, "little")                                   # produkt
e[12:16] = (1).to_bytes(4, "little")                                        # sériové číslo
e[16], e[17] = 1, 2026 - 1990                                               # týždeň, rok
e[18], e[19] = 1, 4                                                         # EDID 1.4
e[20] = 0xA5                                  # digitálny vstup, 8 bitov na farbu, DisplayPort
e[21], e[22] = 53, 30                         # 53 × 30 cm (24")
e[23] = 120                                   # gama 2,2
e[24] = 0x06                                  # sRGB, prvé časovanie je natívne
e[25:35] = bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])   # farby sRGB
e[35:38] = bytes([0x00, 0x00, 0x00])
std = [0xD1, 0xC0] + [0x01, 0x01] * 7        # 1920×1080 @ 60 (16:9), ostatné nepoužité
e[38:54] = bytes(std)
# 1. deskriptor: presné časovanie 1920×1080 @ 60 Hz
e[54:72] = bytes([0x02, 0x3A, 0x80, 0x18, 0x71, 0x38, 0x2D, 0x40, 0x58, 0x2C, 0x45, 0x00, 0x0F, 0x28, 0x21, 0x00, 0x00, 0x1E])
# 2. rozsah: 56–76 Hz, 30–83 kHz, najviac 170 MHz
e[72:90] = bytes([0x00, 0x00, 0x00, 0xFD, 0x00, 0x38, 0x4C, 0x1E, 0x53, 0x11, 0x00, 0x0A] + [0x20] * 6)
# 3. názov
name = b"LATTE-VIRT\n".ljust(13, b" ")
e[90:108] = bytes([0x00, 0x00, 0x00, 0xFC, 0x00]) + name
# 4. prázdny
e[108:126] = bytes([0x00, 0x00, 0x00, 0x10, 0x00] + [0x00] * 13)
e[126] = 0                                    # bez rozšírení
e[127] = (-sum(e[:127])) & 0xFF
open(sys.argv[1] if len(sys.argv) > 1 else "latte-virt-1080p.bin", "wb").write(e)
