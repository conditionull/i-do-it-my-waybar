### Dock Bar:
![dock layout](assets/dock.png)

### Full Bar:
![full bar layout](assets/full.png)

### Preview:<br />
![Preview](assets/preview.gif)

Waybar Layout Selector: << update the paths in scripts/waybar-selector.sh to match your system >>

> [!TIP] 
The hyprland bind + windowrule below are recommended for waybar-selector tool:
```lua
hl.window_rule({ match = { initial_class = "waybar-selector" }, float = true, center = true, size = { 460, 140 } })
```
```lua
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("~/.config/waybar/scripts/waybar-selector.sh"))`
```

### Spotify module:
[left click ~ previous song] &nbsp; • &nbsp;  [middle click - pause/play] &nbsp; • &nbsp;  [right click - next]
<img width="581" height="96" alt="2026-05-05_08-19-01" src="https://github.com/user-attachments/assets/537a929b-8df3-4dd6-942a-a5ed04dce89a" />

