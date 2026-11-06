#!/bin/sh
APP="/opt/etc/keenetic-appstore"
ARCH=""
if [ -r "$APP/architecture" ]; then
  IFS= read -r ARCH < "$APP/architecture" || true
fi
case "$ARCH" in
  ""|unknown)
    PATH="/opt/bin:/opt/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH
    ARCH="$(uname -m 2>/dev/null || true)"
    ;;
esac
case "$ARCH" in
  ""|unknown)
    for BB in /bin/busybox /opt/bin/busybox; do
      if [ -x "$BB" ]; then
        ARCH="$("$BB" uname -m 2>/dev/null || true)"
        [ -n "$ARCH" ] && break
      fi
    done
    ;;
esac
[ -n "$ARCH" ] || ARCH="unknown"
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
printf '{"architecture":"%s"}\n' "$ARCH"
