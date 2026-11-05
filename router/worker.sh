#!/bin/sh
set -u
JOB="${1:-}"
case "$JOB" in *[!a-f0-9]*|'') exit 2;; esac
[ "${#JOB}" -eq 16 ] || exit 2
DIR="/opt/var/lib/keenetic-appstore/jobs/$JOB"
TASK="$DIR/task.json"
LOG="$DIR/log"
URL="$(/opt/bin/jq -r '.url' "$TASK" 2>/dev/null || true)"
ARG="$(/opt/bin/jq -r '.arg' "$TASK" 2>/dev/null || true)"
case "$URL" in https://raw.githubusercontent.com/byDGer/*) ;; *) printf 'Источник установщика запрещён.\n' >> "$LOG"; echo failed > "$DIR/status"; exit 1;; esac
case "$ARG" in ''|auto) ;; *) printf 'Аргумент установщика запрещён.\n' >> "$LOG"; echo failed > "$DIR/status"; exit 1;; esac
echo running > "$DIR/status"
printf '[AppStore] Скачиваю установщик из GitHub…\n' >> "$LOG"
SCRIPT="$DIR/installer.sh"
if ! /opt/bin/curl -fsSL --connect-timeout 15 --max-time 120 "$URL" -o "$SCRIPT" >> "$LOG" 2>&1; then
  printf '\nНе удалось скачать установщик.\n' >> "$LOG"; echo failed > "$DIR/status"; exit 1
fi
chmod 700 "$SCRIPT"
printf '[AppStore] Запускаю установщик…\n' >> "$LOG"
if [ -n "$ARG" ]; then /opt/bin/sh "$SCRIPT" "$ARG" >> "$LOG" 2>&1; RESULT=$?; else /opt/bin/sh "$SCRIPT" >> "$LOG" 2>&1; RESULT=$?; fi
rm -f "$SCRIPT"
if [ "$RESULT" -eq 0 ]; then echo done > "$DIR/status"; else printf '\nУстановщик завершился с кодом %s.\n' "$RESULT" >> "$LOG"; echo failed > "$DIR/status"; fi