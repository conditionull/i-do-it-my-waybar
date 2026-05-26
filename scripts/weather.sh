#!/usr/bin/env bash

set -u

STATE_FILE="/tmp/waybar-weather-hidden"

clean_value() {
  local value="$1"
  value="$(printf '%s' "$value" | tr -d '\r\n')"
  value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  value="$(printf '%s' "$value" | sed -E 's/(^|[[:space:]])\+([0-9])/\1\2/g')"
  printf '%s' "$value"
}

fetch_value() {
  curl -fsS "$1" 2>/dev/null || true
}

if [ -f "$STATE_FILE" ]; then
  printf '{"text":"󰖐","tooltip":"Click to show weather","class":"hidden"}\n'
  exit 0
fi

weather="$(clean_value "$(fetch_value 'https://wttr.is/?u&format=%c%20%t')")"
weather="$(printf '%s' "$weather" | sed -E 's/^([^[:space:]]+)[[:space:]]+/\1 /')"
c_temp="$(clean_value "$(fetch_value 'https://wttr.is/?m&format=%t')")"

if [ -z "$weather" ]; then
  weather="󰖐 N/A"
fi

if [ -n "$c_temp" ]; then
  printf '{"text":"%s","tooltip":"Click to hide ~ %s","class":"shown"}\n' "$weather" "$c_temp"
else
  printf '{"text":"%s","tooltip":"Click to hide","class":"shown"}\n' "$weather"
fi
