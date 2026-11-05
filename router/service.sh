#!/bin/sh
CONF="/opt/etc/keenetic-appstore/lighttpd.conf"
PID="/opt/var/run/keenetic-appstore.pid"
case "${1:-}" in
  start)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "Keenetic AppStore уже запущен."; exit 0; fi
    /opt/sbin/lighttpd -f "$CONF" || exit $?
    echo "Keenetic AppStore запущен." ;;
  stop)
    if [ -s "$PID" ]; then kill "$(cat "$PID")" 2>/dev/null || true; rm -f "$PID"; fi
    echo "Keenetic AppStore остановлен." ;;
  status)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "Keenetic AppStore работает (PID $(cat "$PID"))."; else echo "Keenetic AppStore остановлен."; exit 1; fi ;;
  *) echo "Usage: $0 {start|stop|status}"; exit 1 ;;
esac

