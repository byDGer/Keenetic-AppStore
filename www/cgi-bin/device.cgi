#!/bin/sh
ARCH="$(uname -m 2>/dev/null || echo unknown)"
printf 'Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
printf '{"architecture":"%s"}\n' "$ARCH"

