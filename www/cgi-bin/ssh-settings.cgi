#!/bin/sh
set -eu
umask 077
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

if [ "${REQUEST_METHOD:-}" = GET ]; then
  CONFIGURED=false
  USERNAME=""
  if [ -s "$APP/ssh-credentials.json" ]; then
    CONFIGURED=true
    USERNAME="$(/opt/bin/jq -r '.username // empty' "$APP/ssh-credentials.json" 2>/dev/null || true)"
  fi
  RESULT="$(/opt/bin/jq -n --arg username "$USERNAME" --argjson configured "$CONFIGURED" '{configured:$configured,username:$username}')"
  json_ok "$RESULT"
fi

[ "${REQUEST_METHOD:-}" = POST ] || json_error "Метод запроса не поддерживается."
LAN_IP="$(cat "$APP/lan-ip" 2>/dev/null || true)"
APP_PORT="$(cat "$APP/port" 2>/dev/null || true)"
EXPECTED_ORIGIN="http://$LAN_IP:$APP_PORT"
[ "${HTTP_ORIGIN:-}" = "$EXPECTED_ORIGIN" ] || json_error "Запрос должен быть отправлен со страницы AppStore роутера."

LENGTH="${CONTENT_LENGTH:-0}"
case "$LENGTH" in *[!0-9]*|'') json_error "Некорректный запрос.";; esac
[ "$LENGTH" -gt 0 ] && [ "$LENGTH" -le 4096 ] || json_error "Некорректный запрос."
BODY="$(dd bs=1 count="$LENGTH" 2>/dev/null)" || json_error "Не удалось прочитать запрос."
ACTION="$(printf '%s' "$BODY" | /opt/bin/jq -r '.action // empty' 2>/dev/null || true)"

case "$ACTION" in
  save)
    USERNAME="$(printf '%s' "$BODY" | /opt/bin/jq -r '.username // empty' 2>/dev/null || true)"
    PASSWORD="$(printf '%s' "$BODY" | /opt/bin/jq -r '.password // empty' 2>/dev/null || true)"
    case "$USERNAME" in ''|*[!a-zA-Z0-9._-]*) json_error "Логин: используйте латинские буквы, цифры, точку, дефис или подчёркивание.";; esac
    [ "${#USERNAME}" -le 64 ] || json_error "Слишком длинный SSH-логин."
    if [ -z "$PASSWORD" ] && [ -s "$APP/ssh-credentials.json" ]; then
      PASSWORD="$(/opt/bin/jq -r '.password // empty' "$APP/ssh-credentials.json" 2>/dev/null || true)"
    fi
    [ -n "$PASSWORD" ] || json_error "Введите пароль SSH."
    [ "${#PASSWORD}" -le 512 ] || json_error "Пароль SSH слишком длинный."
    if [ -z "$(printf '%s' "$BODY" | /opt/bin/jq -r '.password // empty' 2>/dev/null || true)" ] && [ -s "$APP/ssh-credentials.json" ]; then
      /opt/bin/jq --arg username "$USERNAME" '.username=$username' "$APP/ssh-credentials.json" > "$APP/ssh-credentials.json.tmp" || json_error "Не удалось подготовить данные SSH."
    else
      printf '%s' "$BODY" | /opt/bin/jq '{username:.username,password:.password}' > "$APP/ssh-credentials.json.tmp" || json_error "Не удалось подготовить данные SSH."
    fi
    chmod 600 "$APP/ssh-credentials.json.tmp"
    mv "$APP/ssh-credentials.json.tmp" "$APP/ssh-credentials.json"
    "$LIB/service.sh" restart-terminal >/dev/null 2>&1 || json_error "Данные сохранены, но веб-терминал не удалось перезапустить."
    json_ok '{"ok":true,"configured":true}'
    ;;
  delete)
    rm -f "$APP/ssh-credentials.json" "$APP/ssh-credentials.json.tmp"
    "$LIB/service.sh" restart-terminal >/dev/null 2>&1 || json_error "Данные удалены, но веб-терминал не удалось перезапустить."
    json_ok '{"ok":true,"configured":false}'
    ;;
  *)
    json_error "Неизвестная операция."
    ;;
esac
