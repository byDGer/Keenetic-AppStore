#!/bin/sh
APP="/opt/etc/keenetic-appstore"
JOBS="/opt/var/lib/keenetic-appstore/jobs"
EXPECTED="$(cat "$APP/token" 2>/dev/null || true)"
HEADER_TOKEN="${HTTP_X_APPSTORE_TOKEN:-${HTTP_X_APP_STORE_TOKEN:-}}"
BODY_TOKEN=""
if [ "${REQUEST_METHOD:-GET}" = POST ]; then
  LENGTH="${CONTENT_LENGTH:-0}"
  case "$LENGTH" in *[!0-9]*|'') printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\n\r\n{"error":"invalid_request"}\n'; exit 0;; esac
  [ "$LENGTH" -gt 0 ] && [ "$LENGTH" -le 2048 ] || { printf 'Status: 400 Bad Request\r\nContent-Type: application/json; charset=utf-8\r\n\r\n{"error":"invalid_request"}\n'; exit 0; }
  BODY="$(dd bs=1 count="$LENGTH" 2>/dev/null)"
  BODY_TOKEN="$(printf '%s' "$BODY" | /opt/bin/jq -r '.token // empty' 2>/dev/null | tr -d '\r\n' || true)"
fi
if [ -z "$EXPECTED" ] || { [ "$HEADER_TOKEN" != "$EXPECTED" ] && [ "$BODY_TOKEN" != "$EXPECTED" ]; }; then
  printf 'Status: 401 Unauthorized\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n{"error":"unauthorized"}\n'
  exit 0
fi
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
JOB="${QUERY_STRING#id=}"
case "$JOB" in ''|*[!a-f0-9]*) printf '{"error":"invalid_job"}\n'; exit 0;; esac
[ "${#JOB}" -eq 16 ] || { printf '{"error":"invalid_job"}\n'; exit 0; }
DIR="$JOBS/$JOB"
[ -d "$DIR" ] || { printf '{"error":"job_not_found"}\n'; exit 0; }
STATE="$(cat "$DIR/status" 2>/dev/null || echo queued)"
LOG="$(tail -c 12000 "$DIR/log" 2>/dev/null | /opt/bin/jq -Rs .)"
printf '{"status":"%s","log":%s}\n' "$STATE" "${LOG:-\"\"}"