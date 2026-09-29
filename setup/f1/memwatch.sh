#!/usr/bin/env bash
# F1 — strážca pamäte počas testov: každých 5 s zapíše obsadenú pamäť a SUnreclaim (jadro).
# Pri prekročení limitu spustí zadaný príkaz (napr. zastavenie testu), aby VM nezamrzla.
# Použitie: setup/f1/memwatch.sh <log> [limit_MB=6000] [príkaz pri prekročení]
log="${1:?log}"; limit="${2:-6000}"; action="${3:-}"
while true; do
    read -r used sun <<<"$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}/SUnreclaim/{s=$2}END{print int((t-a)/1024), int(s/1024)}' /proc/meminfo)"
    top=$(ps -eo rss,comm --sort=-rss | awk 'NR==2{printf "%s %dMB", $2, $1/1024}')
    echo "$(date +%T) obsadené=${used}MB SUnreclaim=${sun}MB top=[$top]" >> "$log"
    if [ "$used" -gt "$limit" ]; then
        echo "$(date +%T) !!! nad ${limit} MB → $action" >> "$log"
        [ -n "$action" ] && sh -c "$action"
        exit 1
    fi
    sleep 5
done
