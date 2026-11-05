#!/bin/sh
set -eu
APP="/opt/etc/keenetic-appstore"
JOBS="/opt/var/lib/keenetic-appstore/jobs"
LIB="/opt/libexec/keenetic-appstore"
REPO="byDGer/Keenetic-AppStore"
json_error(){ printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'; printf '{"error":"%s"}\n' "$1"; exit 0; }
unauthorized(){ printf 'Status: 401 Unauthorized\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n{"error":"unauthorized"}\n'; exit 0; }
[ "${REQUEST_METHOD:-}" = POST ] || json_error 'method_not_allowed'
EXPECTED="$(cat "$APP/token" 2>/dev/null || true)"
[ -n "$EXPECTED" ] && [ "${HTTP_X_APPSTORE_TOKEN:-}" = "$EXPECTED" ] || unauthorized
LENGTH="${CONTENT_LENGTH:-0}"
case "$LENGTH" in *[!0-9]*|'') json_error 'invalid_request';; esac
[ "$LENGTH" -gt 0 ] && [ "$LENGTH" -le 2048 ] || json_error 'invalid_request'
BODY="$(dd bs=1 count="$LENGTH" 2>/dev/null)" || json_error 'invalid_request'
ID="$(printf '%s' "$BODY" | /opt/bin/jq -r '.id // empty' 2>/dev/null || true)"
case "$ID" in ''|*[!a-zA-Z0-9_-]*) json_error 'invalid_app_id';; esac
TMP="$(mktemp /tmp/appstore-catalog.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
/opt/bin/curl -fsSL --connect-timeout 15 --max-time 45 "https://raw.githubusercontent.com/$REPO/main/catalog/apps.json" -o "$TMP" 2>/dev/null || json_error 'github_unavailable'
APP_JSON="$(/opt/bin/jq -c --arg id "$ID" '[.apps[] | select(.id==$id)][0] // empty' "$TMP" 2>/dev/null || true)"
[ -n "$APP_JSON" ] || json_error 'app_not_found'
INSTALL_TYPE="$(printf '%s' "$APP_JSON" | /opt/bin/jq -r '.install.type // empty')"
[ "$INSTALL_TYPE" = script ] || json_error 'installer_not_available'
APP_ARCH="$(uname -m 2>/dev/null || echo unknown)"
printf '%s' "$APP_JSON" | /opt/bin/jq -e --arg arch "$APP_ARCH" '.architectures | index($arch)' >/dev/null 2>&1 || json_error 'architecture_not_supported'
URL="$(printf '%s' "$APP_JSON" | /opt/bin/jq -r '.install.url // empty')"
case "$URL" in https://raw.githubusercontent.com/byDGer/*) ;; *) json_error 'installer_source_not_allowed';; esac
ARG="$(printf '%s' "$APP_JSON" | /opt/bin/jq -r '.install.args[0] // empty')"
case "$ARG" in ''|auto) ;; *) json_error 'installer_argument_not_allowed';; esac
JOB="$(head -c 8 /dev/urandom | od -v -t x1 | awk '{ for (i=2; i<=NF; i++) printf "%s", $i }')"
[ "${#JOB}" -eq 16 ] || json_error 'job_id_failed'
mkdir -p "$JOBS/$JOB"
printf '%s\n' queued > "$JOBS/$JOB/status"
/opt/bin/jq -n --arg url "$URL" --arg arg "$ARG" '{url:$url,arg:$arg}' > "$JOBS/$JOB/task.json"
nohup "$LIB/worker.sh" "$JOB" >/dev/null 2>&1 </dev/null &
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
printf '{"job":"%s","status":"queued"}\n' "$JOB"

