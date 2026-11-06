#!/bin/sh
APP="/opt/etc/keenetic-appstore"
LIB="/opt/libexec/keenetic-appstore"
CONF="$APP/lighttpd.conf"
PID="/opt/var/run/keenetic-appstore.pid"
TTY_PID="/opt/var/run/keenetic-appstore-ttyd.pid"

start_terminal() {
  [ -r "$APP/terminal.conf" ] && [ -x /opt/bin/ttyd ] || return 0
  if [ -s "$TTY_PID" ] && kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then
    echo "Веб-терминал уже запущен."
    return 0
  fi
  . "$APP/terminal.conf"
  TTY_LOG="/opt/var/log/keenetic-appstore-terminal.log"
  : > "$TTY_LOG"
  /opt/bin/ttyd -i "$TTY_IFACE" -p "$TTY_PORT" -W "$LIB/ssh-session.sh" >> "$TTY_LOG" 2>&1 </dev/null &
  echo $! > "$TTY_PID"
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 5 ]; do
    if kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then break; fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
  done
  if ! kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then
    rm -f "$TTY_PID"
    echo "Не удалось запустить веб-терминал. Вывод ttyd:" >&2
    if [ -s "$TTY_LOG" ]; then tail -n 15 "$TTY_LOG" >&2; else echo "(журнал пуст)" >&2; fi
    return 1
  fi
  echo "Веб-терминал запущен на порту $TTY_PORT."
}

stop_terminal() {
  if [ -s "$TTY_PID" ]; then
    kill "$(cat "$TTY_PID")" 2>/dev/null || true
    rm -f "$TTY_PID"
  fi
}

case "$1" in
  start)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "Keenetic AppStore уже запущен."
    else
      /opt/sbin/lighttpd -f "$CONF" || exit $?
      echo "Keenetic AppStore запущен."
    fi
    start_terminal ;;
  restart-terminal)
    stop_terminal
    sleep 1
    start_terminal ;;
  stop)
    stop_terminal
    if [ -s "$PID" ]; then kill "$(cat "$PID")" 2>/dev/null || true; rm -f "$PID"; fi
    echo "Keenetic AppStore остановлен." ;;
  status)
    if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "Keenetic AppStore работает (PID $(cat "$PID"))."
    else
      echo "Keenetic AppStore остановлен."
      exit 1
    fi
    if [ -s "$TTY_PID" ] && kill -0 "$(cat "$TTY_PID")" 2>/dev/null; then
      echo "Веб-терминал работает (PID $(cat "$TTY_PID"))."
    else
      echo "Веб-терминал остановлен."
    fi ;;
  *) echo "Usage: $0 {start|stop|restart-terminal|status}"; exit 1 ;;
esac
