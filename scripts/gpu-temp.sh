#!/usr/bin/env bash

set -u

NVIDIA_MISMATCH_SESSION="${TMPDIR:-/tmp}/waybar-gpu-temp-nvidia-mismatch"

current_boot_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown'
}

nvidia_mismatch_disabled() {
  local cached_boot_id

  [ -r "$NVIDIA_MISMATCH_SESSION" ] || return 1
  read -r cached_boot_id <"$NVIDIA_MISMATCH_SESSION" || return 1
  [ "$cached_boot_id" = "$(current_boot_id)" ]
}

disable_nvidia_for_session() {
  current_boot_id >"$NVIDIA_MISMATCH_SESSION"
}

output_has_version_mismatch() {
  printf '%s' "$1" | grep -Eiq "version mismatch|api mismatch|driver/library version mismatch|couldn't communicate with the nvidia driver"
}

read_nvidia_temp() {
  local output

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 1
  fi

  # if we detected an NVIDIA mismatch this boot, don't even try to run nvidia-smi again
  if nvidia_mismatch_disabled; then
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 2 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>&1 | head -n 1)"
  else
    output="$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>&1 | head -n 1)"
  fi

  if output_has_version_mismatch "$output"; then
    disable_nvidia_for_session
    return 1
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

# show reboot hint if read_nvidia_temp detected an NVIDIA mismatch this boot. Mismatches usually occur after a 'yay' or 'pacman -Syu' update
if nvidia_mismatch_disabled; then
  printf '{"text":"","tooltip":"NVIDIA driver version mismatch; reboot to reload driver"}\n'
elif [ -n "$temp" ]; then
  printf '{"text":" %s°C","tooltip":"GPU temp"}\n' "$temp"
else
  printf '{"text":" n/a","tooltip":"GPU temp"}\n'
fi
