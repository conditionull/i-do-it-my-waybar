#!/bin/sh

TMP_SELECTION=$(mktemp)

kitty --class waybar-selector -e bash -c "
printf 'Dock\nFull Bar' | fzf --no-input --layout=reverse --border \
  --border-label 'Waybar Layout' > '$TMP_SELECTION'
"

if [ -s "$TMP_SELECTION" ]; then
    choice=$(cat "$TMP_SELECTION")
    rm "$TMP_SELECTION"

    case "$choice" in
        'Dock')
            pkill -x waybar
            setsid waybar -c ~/.config/waybar/config_dock -s ~/.config/waybar/dock.css >/dev/null 2>&1 &
            ;;
        'Full Bar')
            pkill -x waybar
            setsid waybar -c ~/.config/waybar/config -s ~/.config/waybar/style.css >/dev/null 2>&1 &
            ;;
    esac
fi
