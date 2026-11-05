#!/bin/sh
REPO="byDGer/Keenetic-AppStore"
URL="https://raw.githubusercontent.com/$REPO/main/catalog/apps.json"
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store, no-cache, must-revalidate\r\n\r\n'
/opt/bin/curl -fsSL --connect-timeout 15 --max-time 45 "$URL" 2>/dev/null || printf '{"apps":[],"groups":[],"categories":[],"error":"github_unavailable"}'