#!/usr/bin/env bash

set -u

if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -w "${XDG_RUNTIME_DIR}" ]; then
  RUNTIME_DIR="$XDG_RUNTIME_DIR"
else
  RUNTIME_DIR="/tmp"
fi

HIDDEN_STATE_FILE="$RUNTIME_DIR/waybar-weather-hidden"

# flip the state file so a click toggles the module visibility
[ -f "$HIDDEN_STATE_FILE" ] && rm -f "$HIDDEN_STATE_FILE" || touch "$HIDDEN_STATE_FILE"

pkill -RTMIN+9 waybar 2>/dev/null || true
