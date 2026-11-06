#!/bin/sh
APP="/opt/etc/keenetic-appstore"
CONF="$APP/lighttpd.conf"
PID="/opt/var/run/keenetic-appstore.pid"
TTY_PID="/opt/var/run/keenetic-appstore-ttyd.pid"
case "$1" in
  start)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "Keenetic AppStore уже запущен."; exit 0; fi
    /opt/sbin/lighttpd -f "$CONF" || exit $?
    echo "Keenetic AppStore запущен."
    if [ -r "$APP/terminal.conf" ] && [ -x /opt/bin/ttyd ]; then
      . "$APP/terminal.conf"
      /opt/bin/ttyd -i "$TTY_IFACE" -p "$TTY_PORT" -c "$TTY_USER:$TTY_PASSWORD" -W /bin/sh -l >> /opt/var/log/keenetic-appstore-terminal.log 2>&1 &
      echo $! > "$TTY_PID"
      sleep 1
      if ! kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then
        rm -f "$TTY_PID"
        echo "Не удалось запустить веб-терминал." >&2
        exit 1
      fi
      echo "Веб-терминал запущен на порту $TTY_PORT."
    fi ;;
  stop)
    if [ -s "$TTY_PID" ]; then kill "$(cat "$TTY_PID")" 2>/dev/null || true; rm -f "$TTY_PID"; fi
    if [ -s "$PID" ]; then kill "$(cat "$PID")" 2>/dev/null || true; rm -f "$PID"; fi
    echo "Keenetic AppStore остановлен." ;;
  status)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "Keenetic AppStore работает (PID $(cat "$PID"))."
    else
      echo "Keenetic AppStore остановлен."
      exit 1
    fi
    if [ -s "$TTY_PID" ] && kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then echo "Веб-терминал работает (PID $(cat "$TTY_PID"))."; else echo "Веб-терминал остановлен."; fi ;;
  *) echo "Usage: $0 {start|stop|status}"; exit 1 ;;
esac
