#!/bin/sh
set -eu

REPO="byDGer/Keenetic-AppStore"
BRANCH="main"
BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
ROOT="/opt"
APP="/opt/etc/keenetic-appstore"
WWW="/opt/share/keenetic-appstore/www"
LIB="/opt/libexec/keenetic-appstore"
JOBS="/opt/var/lib/keenetic-appstore/jobs"

say() { printf '[Keenetic AppStore] %s\n' "$*"; }
die() { say "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "Запустите установщик из Entware под root."
[ -x /opt/bin/opkg ] || die "Entware/opkg не найден (ожидался /opt/bin/opkg)."

ARCH="$(uname -m 2>/dev/null || echo unknown)"
say "Архитектура роутера: $ARCH"

PORT="${1:-}"
if [ -z "$PORT" ]; then
  LAN_IP=""
  if [ -r /dev/tty ]; then
    printf 'LAN-IP роутера [192.168.1.1]: ' > /dev/tty
    read -r LAN_IP < /dev/tty || true
  fi
  LAN_IP="${LAN_IP:-192.168.1.1}"
  if [ -r /dev/tty ]; then
    printf 'Порт AppStore [8088]: ' > /dev/tty
    read -r PORT < /dev/tty || true
  fi
  PORT="${PORT:-8088}"
else
  LAN_IP="${2:-192.168.1.1}"
fi
case "$PORT" in *[!0-9]*|'') die "Порт должен быть числом.";; esac
[ "$PORT" -ge 1024 ] && [ "$PORT" -le 65535 ] || die "Выберите порт от 1024 до 65535."
case "$LAN_IP" in
  *[!0-9.]*|'') die "Укажите IPv4-адрес LAN-интерфейса роутера.";;
esac
[ "$(printf '%s' "$LAN_IP" | awk -F. 'NF==4 && $1<256 && $2<256 && $3<256 && $4<256 {print 1}')" = 1 ] || die "Некорректный IPv4-адрес: $LAN_IP"

say "Обновляю список пакетов Entware и устанавливаю веб-сервер..."
opkg update
opkg install lighttpd lighttpd-mod-cgi jq curl ca-certificates

mkdir -p "$APP" "$WWW/cgi-bin" "$LIB" "$JOBS" /opt/var/run
for f in index.html app.css app.js; do
  curl -fsSL --connect-timeout 15 --max-time 60 "$BASE/www/$f" -o "$WWW/$f" || die "Не удалось скачать www/$f"
done
for f in device.cgi catalog.cgi install.cgi job.cgi; do
  curl -fsSL --connect-timeout 15 --max-time 60 "$BASE/www/cgi-bin/$f" -o "$WWW/cgi-bin/$f" || die "Не удалось скачать www/cgi-bin/$f"
  chmod 755 "$WWW/cgi-bin/$f"
done
for f in worker.sh lighttpd.conf service.sh; do
  curl -fsSL --connect-timeout 15 --max-time 60 "$BASE/router/$f" -o "$LIB/$f" || die "Не удалось скачать router/$f"
  chmod 755 "$LIB/$f"
done

TOKEN="$(head -c 32 /dev/urandom | od -v -t x1 | awk '{ for (i=2; i<=NF; i++) printf "%s", $i }')"
[ "${#TOKEN}" -ge 48 ] || die "Не удалось создать ключ API."
printf '%s\n' "$PORT" > "$APP/port"
printf '%s\n' "$LAN_IP" > "$APP/lan-ip"
printf '%s\n' "$TOKEN" > "$APP/token"
chmod 600 "$APP/token"
cat > "$APP/config" <<EOF
server.bind = "$LAN_IP"
server.port = $PORT
server.document-root = "$WWW"
server.pid-file = "/opt/var/run/keenetic-appstore.pid"
server.errorlog = "/opt/var/log/keenetic-appstore.log"
server.username = "root"
server.groupname = "root"
server.modules = ( "mod_access", "mod_cgi", "mod_accesslog" )
server.indexfiles = ( "index.html" )
cgi.assign = ( ".cgi" => "" )
accesslog.filename = "/opt/var/log/keenetic-appstore-access.log"
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
/opt/etc/init.d/S80keenetic-appstore start

say "Готово."
say "Адрес: http://$LAN_IP:$PORT/"
say "Ключ AppStore (введите в окне установки сайта): $TOKEN"
say "Сохраните ключ: повторно он не выводится. Сервис доступен только на $LAN_IP."

