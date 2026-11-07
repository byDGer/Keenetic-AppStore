#!/bin/sh
APP="/opt/etc/keenetic-appstore"
umask 077
LIB="/opt/libexec/keenetic-appstore"
CREDENTIALS="$APP/ssh-credentials.json"
if [ ! -s "$CREDENTIALS" ]; then
  printf 'SSH-данные не сохранены. Укажите логин и пароль через значок пользователя в AppStore.\r\n'
  exit 1
fi
SSH_USER="$(/opt/bin/jq -r '.username // empty' "$CREDENTIALS" 2>/dev/null || true)"
SSH_PASSWORD="$(/opt/bin/jq -r '.password // empty' "$CREDENTIALS" 2>/dev/null || true)"
SSH_PORT="$(/opt/bin/jq -r '.port // 222 | tostring' "$CREDENTIALS" 2>/dev/null || echo 222)"
SSH_HOST="$(cat "$APP/lan-ip" 2>/dev/null || true)"
if [ -z "$SSH_USER" ] || [ -z "$SSH_PASSWORD" ] || [ -z "$SSH_HOST" ]; then
  printf 'Не удалось прочитать сохранённые SSH-данные.\r\n'
  exit 1
fi
case "$SSH_PORT" in ''|*[!0-9]*)
  printf 'Некорректный порт SSH в сохранённых данных.\r\n'
  exit 1
  ;;
esac
while [ "${SSH_PORT#0}" != "$SSH_PORT" ]; do SSH_PORT="${SSH_PORT#0}"; done
[ -n "$SSH_PORT" ] || SSH_PORT=0
if [ "${#SSH_PORT}" -gt 5 ] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  printf 'Порт SSH должен быть от 1 до 65535.\r\n'
  exit 1
fi
SSH_PID_FILE="$APP/ssh-session.pid"
printf '%s %s\n' "$" "$SSH_USER@$SSH_HOST" > "$SSH_PID_FILE" || {
  printf 'Не удалось сохранить PID SSH-сессии.\r\n'
  exit 1
}
export KEENETIC_SSH_PASSWORD="$SSH_PASSWORD"
export SSH_ASKPASS="$LIB/ssh-askpass.sh"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY=:0
printf 'Подключение SSH к %s:%s под пользователем %s...\r\n' "$SSH_HOST" "$SSH_PORT" "$SSH_USER"
exec /opt/bin/ssh -v -tt -p "$SSH_PORT" \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  -o PreferredAuthentications=password,keyboard-interactive \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -o StrictHostKeyChecking=accept-new \
  -o "UserKnownHostsFile=$APP/ssh_known_hosts" \
  "$SSH_USER@$SSH_HOST"
