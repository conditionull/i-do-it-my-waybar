#!/usr/bin/env bash

set -u

STATE_FILE="/tmp/waybar-weather-hidden"

if [ -f "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
else
  touch "$STATE_FILE"
fi

pkill -RTMIN+9 waybar >/dev/null 2>&1 || true
