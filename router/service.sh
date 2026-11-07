#!/bin/sh
APP="/opt/etc/keenetic-appstore"
LIB="/opt/libexec/keenetic-appstore"
CONF="$APP/lighttpd.conf"
PID="/opt/var/run/keenetic-appstore.pid"
TTY_PID="/opt/var/run/keenetic-appstore-ttyd.pid"
SSH_PID_FILE="$APP/ssh-session.pid"

terminal_running() {
  [ -s "$TTY_PID" ] || return 1
  TERMINAL_PID="$(cat "$TTY_PID" 2>/dev/null || true)"
  case "$TERMINAL_PID" in ''|*[!0-9]*) return 1;; esac
  [ -r "/proc/$TERMINAL_PID/cmdline" ] || return 1
  tr '\\000' ' ' < "/proc/$TERMINAL_PID/cmdline" 2>/dev/null | grep -q '/opt/bin/ttyd'
}

ssh_session_matches() {
  [ -n "$SSH_SESSION_TARGET" ] || return 1
  case "$SSH_SESSION_PID" in ''|*[!0-9]*) return 1;; esac
  [ -r "/proc/$SSH_SESSION_PID/cmdline" ] || return 1
  SESSION_CMDLINE="$(tr '\\000' ' ' < "/proc/$SSH_SESSION_PID/cmdline" 2>/dev/null || true)"
  case "$SESSION_CMDLINE" in
    *"/opt/libexec/keenetic-appstore/ssh-session.sh"*|*"/opt/bin/ssh "*"$SSH_SESSION_TARGET"*) return 0;;
    *) return 1;;
  esac
}

stop_ssh_session() {
  [ -s "$SSH_PID_FILE" ] || return 0
  SSH_SESSION_PID=""
  SSH_SESSION_TARGET=""
  IFS=' ' read -r SSH_SESSION_PID SSH_SESSION_TARGET < "$SSH_PID_FILE" || true
  if ssh_session_matches; then
    kill "$SSH_SESSION_PID" 2>/dev/null || true
    ATTEMPT=0
    while [ "$ATTEMPT" -lt 5 ] && ssh_session_matches; do
      ATTEMPT=$((ATTEMPT + 1))
      sleep 1
    done
    if ssh_session_matches; then kill -9 "$SSH_SESSION_PID" 2>/dev/null || true; fi
  fi
  rm -f "$SSH_PID_FILE"
}

start_terminal() {
  [ -r "$APP/terminal.conf" ] && [ -x /opt/bin/ttyd ] || return 0
  if terminal_running; then
    echo "Веб-терминал уже запущен."
    return 0
  fi
  rm -f "$TTY_PID"
  . "$APP/terminal.conf"
  TTY_LOG="/opt/var/log/keenetic-appstore-terminal.log"
  : > "$TTY_LOG"
  /opt/bin/ttyd -o -t disableReconnect=true -i "$TTY_IFACE" -p "$TTY_PORT" -W "$LIB/ssh-session.sh" >> "$TTY_LOG" 2>&1 </dev/null &
  echo $! > "$TTY_PID"
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 5 ]; do
    if terminal_running; then break; fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
  done
  if ! terminal_running; then
    rm -f "$TTY_PID"
    echo "Не удалось запустить веб-терминал. Вывод ttyd:" >&2
    if [ -s "$TTY_LOG" ]; then tail -n 15 "$TTY_LOG" >&2; else echo "(журнал пуст)" >&2; fi
    return 1
  fi
  echo "Веб-терминал запущен на порту $TTY_PORT."
}

stop_terminal() {
  stop_ssh_session
  if terminal_running; then
    TERMINAL_PID="$(cat "$TTY_PID" 2>/dev/null || true)"
    kill "$TERMINAL_PID" 2>/dev/null || true
    ATTEMPT=0
    while [ "$ATTEMPT" -lt 5 ] && terminal_running; do
      ATTEMPT=$((ATTEMPT + 1))
      sleep 1
    done
    if terminal_running; then kill -9 "$TERMINAL_PID" 2>/dev/null || true; fi
  fi
  rm -f "$TTY_PID"
}

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
  start-terminal) start_terminal ;;
  stop-terminal) stop_terminal ;;
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
    if terminal_running; then
      echo "Веб-терминал работает (PID $(cat "$TTY_PID"))."
    else
      echo "Веб-терминал остановлен."
    fi ;;
  *) echo "Usage: $0 {start|stop|restart-terminal|start-terminal|stop-terminal|status}"; exit 1 ;;
esac
