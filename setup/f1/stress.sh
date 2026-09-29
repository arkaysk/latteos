#!/usr/bin/env bash
# F1 — záťažový test stability: v bežiacej relácii rýchlo otvára a zatvára okná (foot) a meria, či
# Hyprland prežije. Použitie: setup/f1/stress.sh <počet_cyklov>   (relácia musí bežať, napr. session-test.sh)
n="${1:-60}"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
sig=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1); export HYPRLAND_INSTANCE_SIGNATURE=$sig
for i in $(seq 1 "$n"); do
    pgrep -x Hyprland >/dev/null || { echo "Hyprland PADOL v cykle $i"; exit 1; }
    hyprctl eval 'hl.exec_cmd("foot -e sh -c \"sleep 0.8\"")' >/dev/null 2>&1
    hyprctl eval 'hl.exec_cmd("foot -e sh -c \"sleep 1.3\"")' >/dev/null 2>&1
    sleep 0.6
done
sleep 2
pgrep -x Hyprland >/dev/null && echo "Hyprland prežil $n cyklov" || echo "Hyprland PADOL na konci"
