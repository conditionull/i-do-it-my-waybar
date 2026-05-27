#!/usr/bin/env bash

set -u

read_nvidia_temp() {
  local output

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 2 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1)"
  else
    output="$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1)"
  fi

  output="$(printf '%s' "$output" | tr -d '[:space:]')"
  [ -n "$output" ] || return 1
  [ "$output" != "[NotSupported]" ] || return 1

  case "$output" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  printf '%s\n' "$output"
}

read_hwmon_temp() {
  local hwmon name temp_file raw temp

  for hwmon in /sys/class/hwmon/hwmon*; do
    [ -d "$hwmon" ] || continue
    [ -r "$hwmon/name" ] || continue

    name="$(cat "$hwmon/name" 2>/dev/null)"
    case "$name" in
      amdgpu|i915|nouveau)
        for temp_file in "$hwmon"/temp*_input; do
          [ -r "$temp_file" ] || continue
          raw="$(cat "$temp_file" 2>/dev/null)"
          case "$raw" in
            ''|*[!0-9]*)
              continue
              ;;
          esac

          temp=$((raw / 1000))
          printf '%s\n' "$temp"
          return 0
        done
        ;;
    esac
  done

  return 1
}

temp="$(read_nvidia_temp || read_hwmon_temp || true)"

if [ -n "$temp" ]; then
  printf '{"text":" %s°C","tooltip":"GPU temp"}\n' "$temp"
else
  printf '{"text":" n/a","tooltip":"GPU temp"}\n'
fi
