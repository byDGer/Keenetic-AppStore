#!/bin/sh
set -eu

SCRIPT_REVISION="2026-11-07-ssh-port-222"
REPO="byDGer/Keenetic-AppStore"
SOURCE_REVISION="36e136eb6d38779552bdf0b380e0f9ef777ecc71"
BASE="https://raw.githubusercontent.com/$REPO/$SOURCE_REVISION"
ROOT="/opt"
APP="/opt/etc/keenetic-appstore"
WWW="/opt/share/keenetic-appstore/www"
LIB="/opt/libexec/keenetic-appstore"
JOBS="/opt/var/lib/keenetic-appstore/jobs"

say() { printf '[Keenetic AppStore] %s\n' "$*"; }
die() { say "ОШИБКА: $*" >&2; exit 1; }
say "Версия установщика: $SCRIPT_REVISION"

probe_download() {
  PROBE_URL="$1"
  PROBE_LABEL="$2"
  say "Проверяю доступность $PROBE_LABEL..."
  if ! wget -q -T 10 -t 1 -O /dev/null "$PROBE_URL"; then
    die "Нет доступа к $PROBE_LABEL ($PROBE_URL). Загрузка остановлена."
  fi
}

check_download_sources() {
  command -v wget >/dev/null 2>&1 || die "Не найден wget Entware, необходимый для проверки источников загрузки."
  probe_download "$BASE/www/index.html" "GitHub Raw"
  [ -r /opt/etc/opkg.conf ] || die "Не найден файл источников Entware: /opt/etc/opkg.conf"
  FEED_URLS="$(awk '($1 == "src" || $1 == "src/gz") && $3 ~ /^https?:\/\// {print $3}' /opt/etc/opkg.conf)"
  [ -n "$FEED_URLS" ] || die "В /opt/etc/opkg.conf не найдены HTTP-источники Entware."
  for FEED_URL in $FEED_URLS; do
    FEED_URL="${FEED_URL%/}"
    probe_download "$FEED_URL/Packages.gz" "Entware ($FEED_URL)"
  done
}

port_in_use() {
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk -v p="$PORT" 'NR>1 {n=split($4,a,":"); if (a[n]==p) found=1} END {exit !found}'
  elif command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk -v p="$PORT" 'NR>1 {n=split($4,a,":"); if (a[n]==p) found=1} END {exit !found}'
  else
    return 1
  fi
}

interface_ip() {
  IFACE="$1"
  ADDR=""
  if command -v ip >/dev/null 2>&1; then
    ADDR="$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '$1=="inet" {split($2,a,"/"); if (a[1] !~ /^127\./ && a[1] !~ /^169\.254\./) {print a[1]; exit}}')"
  fi
  if [ -z "$ADDR" ] && command -v ifconfig >/dev/null 2>&1; then
    ADDR="$(ifconfig "$IFACE" 2>/dev/null | awk '/inet addr:/ {for(i=1;i<=NF;i++) if($i ~ /^addr:/){sub(/^addr:/,"",$i); print $i; exit}} /inet / && !/inet6/ {for(i=1;i<NF;i++) if($i=="inet"){print $(i+1); exit}}')"
  fi
  case "$ADDR" in
    ''|127.*|169.254.*) return 1 ;;
    *[!0-9.]*) return 1 ;;
    *) printf '%s\n' "$ADDR"; return 0 ;;
  esac
}

detect_lan_ip() {
  # Keenetic's main LAN bridge is normally br0. Try common bridge names first.
  for IFACE in br0 br-lan lan; do
    if ADDR="$(interface_ip "$IFACE")"; then printf '%s\n' "$ADDR"; return 0; fi
  done
  # Fallback: choose an addressed interface other than the default-route WAN.
  DEFAULT_IF=""
  if command -v ip >/dev/null 2>&1; then
    DEFAULT_IF="$(ip route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  fi
  for IF_PATH in /sys/class/net/*; do
    [ -e "$IF_PATH" ] || continue
    IFACE="${IF_PATH##*/}"
    [ "$IFACE" = lo ] && continue
    [ -n "$DEFAULT_IF" ] && [ "$IFACE" = "$DEFAULT_IF" ] && continue
    case "$IFACE" in ppp*|wwan*|lte*|tun*|wg*|brwan*|br-wan*) continue;; esac
    if ADDR="$(interface_ip "$IFACE")"; then printf '%s\n' "$ADDR"; return 0; fi
  done
  return 1
}

[ "$(id -u)" = 0 ] || die "Запустите установщик из Entware под root."
[ -x /opt/bin/opkg ] || die "Entware/opkg не найден (ожидался /opt/bin/opkg)."

ARCH="$(uname -m 2>/dev/null || echo unknown)"
say "Архитектура роутера: $ARCH"

LAN_IP="$(detect_lan_ip)" || die "Не удалось автоматически определить LAN-IP. Проверьте, что у LAN-моста (обычно br0) назначен IPv4-адрес."
say "LAN-IP роутера: $LAN_IP"
LAN_IFACE=""
for IFACE in br0 br-lan lan; do
  IF_ADDR="$(interface_ip "$IFACE" 2>/dev/null || true)"
  if [ "$IF_ADDR" = "$LAN_IP" ]; then LAN_IFACE="$IFACE"; break; fi
done
if [ -z "$LAN_IFACE" ]; then
  for IF_PATH in /sys/class/net/*; do
    [ -e "$IF_PATH" ] || continue
    IFACE="${IF_PATH##*/}"
    [ "$IFACE" = lo ] && continue
    IF_ADDR="$(interface_ip "$IFACE" 2>/dev/null || true)"
    if [ "$IF_ADDR" = "$LAN_IP" ]; then LAN_IFACE="$IFACE"; break; fi
  done
fi
[ -n "$LAN_IFACE" ] || die "Не удалось определить LAN-интерфейс для веб-терминала."

check_download_sources


# Stop the previous AppStore instance before checking whether its port is available.
/opt/etc/init.d/S80keenetic-appstore stop >/dev/null 2>&1 || true

PORT="${1:-}"
if [ -z "$PORT" ]; then
  if [ -r /dev/tty ]; then
    printf 'Порт AppStore [8088]: ' > /dev/tty
    read -r PORT < /dev/tty || true
  fi
  PORT="${PORT:-8088}"
fi
case "$PORT" in *[!0-9]*|'') die "Порт должен быть числом.";; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || die "Выберите порт от 1024 до 65535."
if port_in_use; then
  if [ -n "${1:-}" ]; then die "Порт $PORT уже занят. Укажите другой порт, например 8089."; fi
  say "Порт $PORT занят. Ищу следующий свободный порт..."
  while [ "$PORT" -lt 65535 ]; do
    PORT=$((PORT + 1))
    if ! port_in_use; then break; fi
  done
  port_in_use && die "Не найден свободный порт. Укажите его аргументом, например: sh install.sh 8089"
  say "Выбран свободный порт: $PORT"
fi
case "$LAN_IP" in
  *[!0-9.]*|'') die "Укажите IPv4-адрес LAN-интерфейса роутера.";;
esac
[ "$(printf '%s' "$LAN_IP" | awk -F. 'NF==4 && $1<256 && $2<256 && $3<256 && $4<256 {print 1}')" = 1 ] || die "Некорректный IPv4-адрес: $LAN_IP"

APP_PORT="$PORT"
TTY_PORT="$(cat "$APP/terminal-port" 2>/dev/null || echo 7681)"
case "$TTY_PORT" in *[!0-9]*|'') TTY_PORT=7681;; esac
PORT="$TTY_PORT"
if [ "$PORT" = "$APP_PORT" ] || port_in_use; then
  while [ "$PORT" -lt 65535 ]; do
    PORT=$((PORT + 1))
    [ "$PORT" = "$APP_PORT" ] && continue
    if ! port_in_use; then break; fi
  done
  if [ "$PORT" = "$APP_PORT" ] || port_in_use; then die "Не найден свободный порт для веб-терминала."; fi
  TTY_PORT="$PORT"
fi
PORT="$APP_PORT"

say "Обновляю список пакетов Entware и устанавливаю веб-сервер..."
mkdir -p "$APP" /opt/var/run
OPKG_CONF="/opt/var/run/keenetic-appstore-opkg.conf"
cp /opt/etc/opkg.conf "$OPKG_CONF" || die "Не удалось подготовить временную конфигурацию opkg."
printf '\noption http_timeout 30\n' >> "$OPKG_CONF"
trap 'rm -f "$OPKG_CONF"' EXIT
/opt/bin/opkg -f "$OPKG_CONF" update || die "Не удалось обновить списки Entware за отведённое время. Проверьте доступ роутера к bin.entware.net."
/opt/bin/opkg -f "$OPKG_CONF" install lighttpd lighttpd-mod-cgi jq curl ca-certificates ttyd openssh-client || die "Не удалось установить необходимые пакеты Entware."
rm -f "$OPKG_CONF"
trap - EXIT

mkdir -p "$APP" "$WWW/cgi-bin" "$LIB" "$JOBS" /opt/var/run
rm -f "$APP/ssh-credentials.json.tmp" "$APP/ssh-credentials.json.$"
printf '%s\n' "$ARCH" > "$APP/architecture"
CACHE_BUST="$(date +%s 2>/dev/null || echo 0)-${RANDOM:-0}"
for f in index.html app.css app.js; do
  curl -fsSL --connect-timeout 15 --max-time 60 "$BASE/www/$f?update=$CACHE_BUST" -o "$WWW/$f" || die "Не удалось скачать www/$f"
done
for f in device.cgi catalog.cgi install.cgi job.cgi ssh-settings.cgi; do
  curl -fsSL --connect-timeout 15 --max-time 60 "$BASE/www/cgi-bin/$f?update=$CACHE_BUST" -o "$WWW/cgi-bin/$f" || die "Не удалось скачать www/cgi-bin/$f"
  tr -d '\r' < "$WWW/cgi-bin/$f" > "$WWW/cgi-bin/$f.tmp" && mv "$WWW/cgi-bin/$f.tmp" "$WWW/cgi-bin/$f"
  chmod 755 "$WWW/cgi-bin/$f"
done
for f in worker.sh lighttpd.conf service.sh ssh-session.sh ssh-askpass.sh; do
  curl -fsSL --connect-timeout 15 --max-time 60 -H 'Cache-Control: no-cache, no-store' -H 'Pragma: no-cache' "$BASE/router/$f?update=$CACHE_BUST" -o "$LIB/$f" || die "Не удалось скачать router/$f"
  tr -d '\r' < "$LIB/$f" > "$LIB/$f.tmp" && mv "$LIB/$f.tmp" "$LIB/$f"
  chmod 755 "$LIB/$f"
done
SERVICE_CONTENT="$(cat "$LIB/service.sh")" || die "Не удалось проверить router/service.sh."
case "$SERVICE_CONTENT" in
  *nohup*) die "GitHub вернул устаревший service.sh с nohup. Загрузка остановлена.";;
esac
unset SERVICE_CONTENT

rm -f "$APP/token"
printf '%s\n' "$PORT" > "$APP/port"
printf '%s\n' "$LAN_IP" > "$APP/lan-ip"
printf '%s\n' "$TTY_PORT" > "$APP/terminal-port"
rm -f "$APP/terminal-password"
cat > "$APP/terminal.conf" <<EOF
TTY_PORT="$TTY_PORT"
TTY_IFACE="$LAN_IFACE"
EOF
chmod 600 "$APP/terminal.conf"
cat > "$APP/config" <<EOF
server.bind = "$LAN_IP"
server.port = $PORT
server.document-root = "$WWW"
server.pid-file = "/opt/var/run/keenetic-appstore.pid"
server.errorlog = "/opt/var/log/keenetic-appstore.log"
server.modules = ( "mod_access", "mod_cgi" )
server.indexfiles = ( "index.html" )
cgi.assign = ( ".cgi" => "" )
url.access-deny = ( "~", ".inc", ".sh", ".conf", ".json" )
EOF

cat > "$APP/lighttpd.conf" <<EOF
include "$APP/config"
EOF
cat > "/opt/etc/init.d/S80keenetic-appstore" <<EOF
#!/bin/sh
APP_LIB="$LIB"
case "\$1" in
  start) "\$APP_LIB/service.sh" start ;;
  stop) "\$APP_LIB/service.sh" stop ;;
  restart) "\$APP_LIB/service.sh" stop; sleep 1; "\$APP_LIB/service.sh" start ;;
  status) "\$APP_LIB/service.sh" status ;;
  *) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
EOF
chmod 755 /opt/etc/init.d/S80keenetic-appstore

say "Проверяю конфигурацию Lighttpd..."
/opt/sbin/lighttpd -tt -f "$APP/lighttpd.conf" || die "Конфигурация Lighttpd не прошла проверку."
/opt/etc/init.d/S80keenetic-appstore stop >/dev/null 2>&1 || true
/opt/etc/init.d/S80keenetic-appstore start

HTTP_CODE="$(/opt/bin/curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 8 "http://$LAN_IP:$PORT/" 2>/dev/null || true)"
if [ "$HTTP_CODE" = 401 ]; then
  /opt/etc/init.d/S80keenetic-appstore stop >/dev/null 2>&1 || true
  die "На порту $PORT отвечает сервер с HTTP-авторизацией. Выберите другой порт и повторите установку."
fi
[ "$HTTP_CODE" = 200 ] || say "Не удалось проверить главную страницу (HTTP $HTTP_CODE); проверьте адрес вручную."

say "Готово."
say "Адрес: http://$LAN_IP:$PORT/"
say "Проверить из терминала: curl -I http://$LAN_IP:$PORT/"
printf '\033]8;;http://%s:%s/\033\\Открыть AppStore в браузере\033]8;;\033\\\n' "$LAN_IP" "$PORT"
say "Если терминал не поддерживает кликабельные ссылки, откройте http://$LAN_IP:$PORT/ на компьютере."
say "Сайт доступен на LAN-IP $LAN_IP."
say "Веб-терминал: http://$LAN_IP:$TTY_PORT/ (кнопка SSH в шапке сайта)."