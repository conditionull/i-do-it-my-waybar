#!/usr/bin/env bash

set -u

if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR}" ]; then
  RUNTIME_DIR="$XDG_RUNTIME_DIR"
else
  # fall back to /tmp when the session runtime dir is missing
  RUNTIME_DIR="/tmp"
fi

if [ -n "${XDG_CACHE_HOME:-}" ]; then
  CACHE_DIR="$XDG_CACHE_HOME"
else
  CACHE_DIR="$HOME/.cache"
fi

HIDDEN_STATE_FILE="$RUNTIME_DIR/waybar-weather-hidden"
CACHE_FILE="$CACHE_DIR/waybar-weather-cache"
REFRESH_LOCK_FILE="$RUNTIME_DIR/waybar-weather-refresh.lock"
SESSION_STATE_FILE="$RUNTIME_DIR/waybar-weather-session"
CACHE_MAX_AGE_SECONDS=600
INITIAL_RETRY_DELAY_SECONDS=2
INITIAL_RETRY_ATTEMPTS=10
RETRY_INTERVAL_SECONDS=2

fetch_value() {
  curl -fsS --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true
}

clean_value() {
  printf '%s' "$1" | tr -d '\r\n' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/(^| )\+([0-9])/\1\2/g'
}

read_cache() {
  [ -f "$CACHE_FILE" ] || return 1

  cached_weather="$(clean_value "$(sed -n '1p' "$CACHE_FILE" 2>/dev/null)")"
  cached_c_temp="$(clean_value "$(sed -n '2p' "$CACHE_FILE" 2>/dev/null)")"
  [ -n "$cached_weather" ]
}

cache_is_stale() {
  local now modified

  [ -f "$CACHE_FILE" ] || return 0

  now="$(date +%s)"
  modified="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || printf '0')"
  [ $((now - modified)) -ge "$CACHE_MAX_AGE_SECONDS" ]
}

fetch_weather() {
  local live_weather live_c_temp

  mkdir -p "$CACHE_DIR" 2>/dev/null || true

  live_weather="$(clean_value "$(fetch_value 'https://wttr.is/?u&format=%c%20%t')")"
  live_c_temp="$(clean_value "$(fetch_value 'https://wttr.is/?m&format=%t')")"

  [ -n "$live_weather" ] || return 1

  weather="$live_weather"
  c_temp="$live_c_temp"
  printf '%s\n%s\n' "$weather" "$c_temp" > "$CACHE_FILE"
}

schedule_refresh() {
  local delay attempts

  delay="${1:-0}"
  attempts="${2:-1}"

  [ -f "$REFRESH_LOCK_FILE" ] && return

  : > "$REFRESH_LOCK_FILE"
  (
    trap 'rm -f "$REFRESH_LOCK_FILE"' EXIT

    [ "$delay" -gt 0 ] && sleep "$delay"

    while [ "$attempts" -gt 0 ]; do
      if fetch_weather; then
        pkill -RTMIN+9 waybar >/dev/null 2>&1 || true
        exit 0
      fi

      attempts=$((attempts - 1))
      [ "$attempts" -gt 0 ] || break
      sleep "$RETRY_INTERVAL_SECONDS"
    done
  ) >/dev/null 2>&1 &
}

if [ -f "$HIDDEN_STATE_FILE" ]; then
  printf '{"text":"󰖐","tooltip":"Click to show weather","class":"hidden"}\n'
  exit 0
fi

weather=""
c_temp=""
cached_weather=""
cached_c_temp=""

if read_cache; then
  weather="$cached_weather"
  c_temp="$cached_c_temp"

  # use cached data first and refresh in the background to avoid empty value on startup
  if [ ! -f "$SESSION_STATE_FILE" ]; then
    : > "$SESSION_STATE_FILE"
    schedule_refresh 0 "$INITIAL_RETRY_ATTEMPTS"
  else
    cache_is_stale && schedule_refresh
  fi
else
  schedule_refresh 0 "$INITIAL_RETRY_ATTEMPTS"
fi

if [ -z "$weather" ]; then
  printf '{"text":"󰖐 ...","tooltip":"Refreshing weather...","class":"shown"}\n'
  exit 0
fi

if [ -n "$c_temp" ]; then
  printf '{"text":"%s","tooltip":"Click to hide ~ %s","class":"shown"}\n' "$weather" "$c_temp"
else
  printf '{"text":"%s","tooltip":"Click to hide","class":"shown"}\n' "$weather"
fi
