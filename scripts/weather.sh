#!/usr/bin/env bash

set -u

# -----------------------------------------------
# Runtime and cache directories
# -----------------------------------------------

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

# -----------------------------------------------
# State files
# -----------------------------------------------

HIDDEN_STATE_FILE="$RUNTIME_DIR/waybar-weather-hidden"
CACHE_FILE="$CACHE_DIR/waybar-weather-cache"
REFRESH_LOCK_FILE="$RUNTIME_DIR/waybar-weather-refresh.lock"
SESSION_STATE_FILE="$RUNTIME_DIR/waybar-weather-session"

# -----------------------------------------------
# Refresh behavior
# To test config changes without waiting for the cache to expire, set
# CACHE_MAX_AGE_SECONDS to a low value like 10, then hide/show the widget to trigger a refresh
# -----------------------------------------------

CACHE_MAX_AGE_SECONDS=600
INITIAL_RETRY_DELAY_SECONDS=2
INITIAL_RETRY_ATTEMPTS=10
RETRY_INTERVAL_SECONDS=2

# -----------------------------------------------
# User configuration
# Default behavior uses IP geolocation through ipapi.co.
# Optional overrides:
# - WEATHER_LATITUDE / WEATHER_LONGITUDE for fixed coordinates
# - WEATHER_LOCATION for Open-Meteo geocoding
# - WEATHER_COUNTRY_CODE to narrow geocoding results
# - WEATHER_DISPLAY_UNIT=celsius|fahrenheit
# -----------------------------------------------

DISPLAY_UNIT="${WEATHER_DISPLAY_UNIT:-fahrenheit}"
LOCATION_QUERY="${WEATHER_LOCATION:-}"
LOCATION_COUNTRY_CODE="${WEATHER_COUNTRY_CODE:-}"
LATITUDE="${WEATHER_LATITUDE:-}"
LONGITUDE="${WEATHER_LONGITUDE:-}"

case "$DISPLAY_UNIT" in
  celsius|fahrenheit)
    ;;
  *)
    DISPLAY_UNIT="fahrenheit"
    ;;
esac

# -----------------------------------------------
# Generic helpers
# -----------------------------------------------

fetch_value() {
  curl -fsS --connect-timeout 2 --max-time 4 "$1" 2>/dev/null || true
}

clean_value() {
  printf '%s' "$1" | tr -d '\r\n' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/(^| )\+([0-9])/\1\2/g'
}

urlencode() {
  jq -rn --arg value "$1" '$value|@uri'
}

# -----------------------------------------------
# Location resolution
# -----------------------------------------------

resolve_location() {
  local location_json geocoding_url ip_geo_json

  if [ -z "$LATITUDE" ] && [ -z "$LONGITUDE" ] && [ -z "$LOCATION_QUERY" ]; then
    ip_geo_json="$(fetch_value 'https://ipapi.co/json/')"
    [ -n "$ip_geo_json" ] || return 1

    LATITUDE="$(printf '%s' "$ip_geo_json" | jq -r '.latitude // empty')"
    LONGITUDE="$(printf '%s' "$ip_geo_json" | jq -r '.longitude // empty')"

    [ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ] || return 1
    return 0
  fi

  if [ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ]; then
    return 0
  fi

  [ -n "$LOCATION_QUERY" ] || return 1

  geocoding_url="https://geocoding-api.open-meteo.com/v1/search?name=$(urlencode "$LOCATION_QUERY")&count=1&language=en&format=json"
  if [ -n "$LOCATION_COUNTRY_CODE" ]; then
    geocoding_url="${geocoding_url}&countryCode=$(urlencode "$LOCATION_COUNTRY_CODE")"
  fi

  location_json="$(fetch_value "$geocoding_url")"
  [ -n "$location_json" ] || return 1

  LATITUDE="$(printf '%s' "$location_json" | jq -r '.results[0].latitude // empty')"
  LONGITUDE="$(printf '%s' "$location_json" | jq -r '.results[0].longitude // empty')"

  [ -n "$LATITUDE" ] && [ -n "$LONGITUDE" ]
}

# -----------------------------------------------
# Cache helpers
# -----------------------------------------------

read_cache() {
  [ -f "$CACHE_FILE" ] || return 1

  cached_weather="$(clean_value "$(sed -n '1p' "$CACHE_FILE" 2>/dev/null)")"
  cached_alt_temp="$(clean_value "$(sed -n '2p' "$CACHE_FILE" 2>/dev/null)")"
  cached_feels_like="$(clean_value "$(sed -n '3p' "$CACHE_FILE" 2>/dev/null)")"
  [ -n "$cached_weather" ]
}

cache_is_stale() {
  local now modified

  [ -f "$CACHE_FILE" ] || return 0

  now="$(date +%s)"
  modified="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || printf '0')"
  [ $((now - modified)) -ge "$CACHE_MAX_AGE_SECONDS" ]
}

# -----------------------------------------------
# Formatting helpers
# -----------------------------------------------

format_weather() {
  local icon temp

  icon="$1"
  temp="$2"

  if [ -n "$temp" ]; then
    printf '%s %s' "$icon" "$temp"
  else
    printf '%s' "$icon"
  fi
}

format_temperature_value() {
  awk -v value="$1" -v unit="$2" '
    BEGIN {
      rounded = (value >= 0) ? int(value + 0.5) : int(value - 0.5)
      suffix = (unit == "celsius") ? "°C" : "°F"
      printf "%d%s", rounded, suffix
    }
  '
}

format_feels_like() {
  printf 'Feels like %s' "$(format_temperature_value "$1" "$2")"
}

convert_temperature() {
  awk -v value="$1" -v unit="$2" '
    BEGIN {
      if (unit == "fahrenheit") {
        printf "%.6f", (value * 9 / 5) + 32
      } else {
        printf "%.6f", value
      }
    }
  '
}

weather_icon() {
  local code is_day

  code="$1"
  is_day="$2"

  case "$code" in
    0)
      [ "$is_day" = "1" ] && printf '󰖙' || printf '󰖔'
      ;;
    1|2)
      printf '󰖕'
      ;;
    3)
      printf '󰖐'
      ;;
    45|48)
      printf '󰖑'
      ;;
    51|53|55|56|57)
      printf '󰖗'
      ;;
    61|63|65|66|67|80|81|82)
      printf '󰖖'
      ;;
    71|73|75|77|85|86)
      printf '󰖘'
      ;;
    95|96|99)
      printf '󰖓'
      ;;
    *)
      printf '󰖐'
      ;;
  esac
}

# -----------------------------------------------
# Open-Meteo fetch and cache update
# -----------------------------------------------

fetch_weather() {
  local weather_json weather_url temp_c apparent_temp_c display_temp apparent_display_temp live_icon live_weather weather_code is_day

  mkdir -p "$CACHE_DIR" 2>/dev/null || true

  resolve_location || return 1

  weather_url="https://api.open-meteo.com/v1/forecast?latitude=${LATITUDE}&longitude=${LONGITUDE}&current=temperature_2m,apparent_temperature,weather_code,is_day&temperature_unit=celsius&timezone=auto"
  weather_json="$(fetch_value "$weather_url")"
  [ -n "$weather_json" ] || return 1

  temp_c="$(printf '%s' "$weather_json" | jq -r '.current.temperature_2m // empty')"
  apparent_temp_c="$(printf '%s' "$weather_json" | jq -r '.current.apparent_temperature // empty')"
  weather_code="$(printf '%s' "$weather_json" | jq -r '.current.weather_code // empty')"
  is_day="$(printf '%s' "$weather_json" | jq -r '.current.is_day // empty')"
  [ -n "$temp_c" ] && [ -n "$apparent_temp_c" ] && [ -n "$weather_code" ] && [ -n "$is_day" ] || return 1

  display_temp="$(convert_temperature "$temp_c" "$DISPLAY_UNIT")"
  apparent_display_temp="$(convert_temperature "$apparent_temp_c" "$DISPLAY_UNIT")"

  live_icon="$(weather_icon "$weather_code" "$is_day")"
  live_weather="$(format_weather "$live_icon" "$(format_temperature_value "$display_temp" "$DISPLAY_UNIT")")"
  alt_temp="$(format_temperature_value "$temp_c" "celsius")"
  feels_like="$(format_feels_like "$apparent_display_temp" "$DISPLAY_UNIT")"

  if [ "$DISPLAY_UNIT" = "celsius" ]; then
    alt_temp="$(format_temperature_value "$(convert_temperature "$temp_c" "fahrenheit")" "fahrenheit")"
  fi

  [ -n "$live_weather" ] || return 1

  weather="$live_weather"
  printf '%s\n%s\n%s\n' "$weather" "$alt_temp" "$feels_like" > "$CACHE_FILE"
}

# -----------------------------------------------
# Background refresh coordination
# -----------------------------------------------

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

# -----------------------------------------------
# Main Waybar execution flow
# -----------------------------------------------

if [ -f "$HIDDEN_STATE_FILE" ]; then
  printf '{"text":"󰖐","tooltip":"Click to show weather","class":"hidden"}\n'
  exit 0
fi

weather=""
alt_temp=""
feels_like=""
cached_weather=""
cached_alt_temp=""
cached_feels_like=""

if read_cache; then
  weather="$cached_weather"
  alt_temp="$cached_alt_temp"
  feels_like="$cached_feels_like"

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

# No cache yet or refresh has not completed.
if [ -z "$weather" ]; then
  printf '{"text":"󰖐 ...","tooltip":"Refreshing weather...","class":"shown"}\n'
  exit 0
fi

# Final Waybar payload.
if [ -n "$alt_temp" ] && [ -n "$feels_like" ]; then
  printf '{"text":"%s","tooltip":"Click to hide ~ %s ~ %s","class":"shown"}\n' "$weather" "$alt_temp" "$feels_like"
elif [ -n "$alt_temp" ]; then
  printf '{"text":"%s","tooltip":"Click to hide ~ %s","class":"shown"}\n' "$weather" "$alt_temp"
else
  printf '{"text":"%s","tooltip":"Click to hide","class":"shown"}\n' "$weather"
fi
