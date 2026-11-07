#!/bin/sh
set -eu
APP="/opt/etc/keenetic-appstore"
LIB="/opt/libexec/keenetic-appstore"

json_error() {
  printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
  /opt/bin/jq -n --arg error "$1" '{error:$error}'
  exit 0
}
json_ok() {
  printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
  printf '%s\n' "$1"
  exit 0
}

[ "${REQUEST_METHOD:-}" = POST ] || json_error "Метод запроса не поддерживается."
LAN_IP="$(cat "$APP/lan-ip" 2>/dev/null || true)"
APP_PORT="$(cat "$APP/port" 2>/dev/null || true)"
EXPECTED_ORIGIN="http://$LAN_IP:$APP_PORT"
REQUEST_HOST="${HTTP_HOST:-}"
case "$REQUEST_HOST" in
  ''|*[!a-zA-Z0-9.:-]*) REQUEST_HOST="";;
esac
ORIGIN_OK=false
if [ -n "$REQUEST_HOST" ] && [ "${HTTP_ORIGIN:-}" = "http://$REQUEST_HOST" ]; then
  ORIGIN_OK=true
elif [ "${HTTP_ORIGIN:-}" = "$EXPECTED_ORIGIN" ]; then
  ORIGIN_OK=true
elif [ -n "$REQUEST_HOST" ] && [ -n "${HTTP_REFERER:-}" ]; then
  case "$HTTP_REFERER" in
    "http://$REQUEST_HOST/"*) ORIGIN_OK=true;;
  esac
fi
[ "$ORIGIN_OK" = true ] || json_error "Запрос должен быть отправлен со страницы AppStore роутера."

LENGTH="${CONTENT_LENGTH:-0}"
case "$LENGTH" in *[!0-9]*|'') json_error "Некорректный запрос.";; esac
[ "$LENGTH" -gt 0 ] && [ "$LENGTH" -le 256 ] || json_error "Некорректный запрос."
BODY=""
IFS= read -r BODY || true
ACTION="$(printf '%s' "$BODY" | /opt/bin/jq -r '.action // empty' 2>/dev/null || true)"

case "$ACTION" in
  start)
    "$LIB/service.sh" restart-terminal >/dev/null 2>&1 || json_error "Не удалось запустить новую SSH-сессию."
    json_ok '{"ok":true,"started":true}'
    ;;
  stop)
    "$LIB/service.sh" stop-terminal >/dev/null 2>&1 || json_error "Не удалось завершить SSH-сессию."
    json_ok '{"ok":true,"stopped":true}'
    ;;
  *)
    json_error "Неизвестная операция."
    ;;
esac
