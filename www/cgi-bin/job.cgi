#!/bin/sh
APP="/opt/etc/keenetic-appstore"
JOBS="/opt/var/lib/keenetic-appstore/jobs"
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
JOB="${QUERY_STRING#id=}"
case "$JOB" in ''|*[!a-f0-9]*) printf '{"error":"invalid_job"}\n'; exit 0;; esac
[ "${#JOB}" -eq 16 ] || { printf '{"error":"invalid_job"}\n'; exit 0; }
DIR="$JOBS/$JOB"
[ -d "$DIR" ] || { printf '{"error":"job_not_found"}\n'; exit 0; }
STATE="$(cat "$DIR/status" 2>/dev/null || echo queued)"
LOG="$(tail -c 12000 "$DIR/log" 2>/dev/null | /opt/bin/jq -Rs .)"
printf '{"status":"%s","log":%s}\n' "$STATE" "${LOG:-\"\"}"