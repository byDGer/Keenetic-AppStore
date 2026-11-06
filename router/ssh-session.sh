#!/bin/sh
APP="/opt/etc/keenetic-appstore"
LIB="/opt/libexec/keenetic-appstore"
CREDENTIALS="$APP/ssh-credentials.json"
if [ ! -s "$CREDENTIALS" ]; then
  printf 'SSH-данные не сохранены. Укажите логин и пароль через значок пользователя в AppStore.\r\n'
  exit 1
fi
SSH_USER="$(/opt/bin/jq -r '.username // empty' "$CREDENTIALS" 2>/dev/null || true)"
SSH_PASSWORD="$(/opt/bin/jq -r '.password // empty' "$CREDENTIALS" 2>/dev/null || true)"
SSH_HOST="$(cat "$APP/lan-ip" 2>/dev/null || true)"
if [ -z "$SSH_USER" ] || [ -z "$SSH_PASSWORD" ] || [ -z "$SSH_HOST" ]; then
  printf 'Не удалось прочитать сохранённые SSH-данные.\r\n'
  exit 1
fi
export KEENETIC_SSH_PASSWORD="$SSH_PASSWORD"
export SSH_ASKPASS="$LIB/ssh-askpass.sh"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY=:0
exec /opt/bin/ssh -tt -p 22 \
  -o PreferredAuthentications=password,keyboard-interactive \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -o StrictHostKeyChecking=accept-new \
  -o "UserKnownHostsFile=$APP/ssh_known_hosts" \
  "$SSH_USER@$SSH_HOST"
