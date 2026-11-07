#!/bin/sh
set -eu
umask 077
APP="/opt/etc/keenetic-appstore"
LIB="/opt/libexec/keenetic-appstore"

handle_unexpected_exit() {
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -ne 0 ]; then
    trap - EXIT
    printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
    /opt/bin/jq -n --arg code "$EXIT_CODE" '{error:("Внутренняя ошибка CGI, код " + $code + ".")}' 2>/dev/null || printf '{"error":"Внутренняя ошибка CGI."}\n'
    exit 0
  fi
}
trap 'handle_unexpected_exit' EXIT

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

normalize_port() {
  PORT_VALUE="$1"
  case "$PORT_VALUE" in ''|*[!0-9]*) return 1;; esac
  while [ "${PORT_VALUE#0}" != "$PORT_VALUE" ]; do PORT_VALUE="${PORT_VALUE#0}"; done
  [ -n "$PORT_VALUE" ] || PORT_VALUE=0
  [ "${#PORT_VALUE}" -le 5 ] || return 1
  [ "$PORT_VALUE" -ge 1 ] && [ "$PORT_VALUE" -le 65535 ] || return 1
  printf '%s\n' "$PORT_VALUE"
}

if [ "${REQUEST_METHOD:-}" = GET ]; then
  CONFIGURED=false
  USERNAME=""
  SSH_PORT=222
  if [ -s "$APP/ssh-credentials.json" ]; then
    USERNAME="$(/opt/bin/jq -r '.username // empty' "$APP/ssh-credentials.json" 2>/dev/null || true)"
    STORED_PASSWORD="$(/opt/bin/jq -r '.password // empty' "$APP/ssh-credentials.json" 2>/dev/null || true)"
    STORED_PORT="$(/opt/bin/jq -r '.port // 222 | tostring' "$APP/ssh-credentials.json" 2>/dev/null || echo 222)"
    SSH_PORT="$(normalize_port "$STORED_PORT" 2>/dev/null || echo 222)"
    if [ -n "$USERNAME" ] && [ -n "$STORED_PASSWORD" ]; then CONFIGURED=true; fi
  fi
  RESULT="$(/opt/bin/jq -n --arg username "$USERNAME" --arg port "$SSH_PORT" --argjson configured "$CONFIGURED" '{configured:$configured,username:$username,port:($port|tonumber)}')"
  json_ok "$RESULT"
fi

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
[ "$LENGTH" -gt 0 ] && [ "$LENGTH" -le 4096 ] || json_error "Некорректный запрос."
BODY=""
IFS= read -r BODY || true
[ -n "$BODY" ] || json_error "Тело запроса не получено."
ACTION="$(printf '%s' "$BODY" | /opt/bin/jq -r '.action // empty' 2>/dev/null || true)"

case "$ACTION" in
  save)
    USERNAME="$(printf '%s' "$BODY" | /opt/bin/jq -r '.username // empty' 2>/dev/null || true)"
    PASSWORD="$(printf '%s' "$BODY" | /opt/bin/jq -r '.password // empty' 2>/dev/null || true)"
    RAW_PORT="$(printf '%s' "$BODY" | /opt/bin/jq -r '.port // 222 | tostring' 2>/dev/null || true)"
    SSH_PORT="$(normalize_port "$RAW_PORT" 2>/dev/null || true)"
    [ -n "$SSH_PORT" ] || json_error "Укажите порт SSH от 1 до 65535."
    case "$USERNAME" in ''|*[!a-zA-Z0-9._-]*) json_error "Логин: используйте латинские буквы, цифры, точку, дефис или подчёркивание.";; esac
    [ "${#USERNAME}" -le 64 ] || json_error "Слишком длинный SSH-логин."
    if [ -z "$PASSWORD" ] && [ -s "$APP/ssh-credentials.json" ]; then
      PASSWORD="$(/opt/bin/jq -r '.password // empty' "$APP/ssh-credentials.json" 2>/dev/null || true)"
    fi
    [ -n "$PASSWORD" ] || json_error "Введите пароль SSH."
    [ "${#PASSWORD}" -le 512 ] || json_error "Пароль SSH слишком длинный."
    TEMP_FILE="$APP/ssh-credentials.json.tmp"
    : > "$TEMP_FILE" || json_error "Не удалось подготовить временный файл SSH-данных."
    if [ -z "$(printf '%s' "$BODY" | /opt/bin/jq -r '.password // empty' 2>/dev/null || true)" ] && [ -s "$APP/ssh-credentials.json" ]; then
      /opt/bin/jq --arg username "$USERNAME" --arg port "$SSH_PORT" '.username=$username | .port=($port|tonumber)' "$APP/ssh-credentials.json" > "$TEMP_FILE" || json_error "Не удалось подготовить данные SSH."
    else
      /opt/bin/jq -n --arg username "$USERNAME" --arg password "$PASSWORD" --arg port "$SSH_PORT" '{username:$username,password:$password,port:($port|tonumber)}' > "$TEMP_FILE" || json_error "Не удалось подготовить данные SSH."
    fi
    MOVE_BIN=""
    for CANDIDATE in /bin/mv /opt/bin/mv /usr/bin/mv; do
      if [ -x "$CANDIDATE" ]; then MOVE_BIN="$CANDIDATE"; break; fi
    done
    [ -n "$MOVE_BIN" ] || json_error "Не найдена системная команда mv."
    "$MOVE_BIN" "$TEMP_FILE" "$APP/ssh-credentials.json" || json_error "Не удалось сохранить SSH-данные."
    "$LIB/service.sh" restart-terminal >/dev/null 2>&1 || json_error "Данные сохранены, но веб-терминал не удалось перезапустить."
    json_ok '{"ok":true,"configured":true}'
    ;;
  delete)
    : > "$APP/ssh-credentials.json" || json_error "Не удалось удалить SSH-данные."
    : > "$APP/ssh-credentials.json.tmp" 2>/dev/null || true
    "$LIB/service.sh" restart-terminal >/dev/null 2>&1 || json_error "Данные удалены, но веб-терминал не удалось перезапустить."
    json_ok '{"ok":true,"configured":false}'
    ;;
  *)
    json_error "Неизвестная операция."
    ;;
esac
