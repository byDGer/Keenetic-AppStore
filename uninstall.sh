#!/bin/sh
set -eu

say() { printf '[Keenetic AppStore] %s\n' "$*"; }
INIT="/opt/etc/init.d/S80keenetic-appstore"

if [ -x "$INIT" ]; then
  "$INIT" stop || true
fi
rm -f "$INIT" /opt/var/run/keenetic-appstore.pid /opt/var/run/keenetic-appstore-ttyd.pid
rm -rf /opt/etc/keenetic-appstore /opt/share/keenetic-appstore /opt/libexec/keenetic-appstore /opt/var/lib/keenetic-appstore
rm -f /opt/var/log/keenetic-appstore.log /opt/var/log/keenetic-appstore-access.log /opt/var/log/keenetic-appstore-terminal.log

say "AppStore удалён. Пакеты Lighttpd, ttyd, jq, curl и сертификаты оставлены: они могут использоваться другими программами."
