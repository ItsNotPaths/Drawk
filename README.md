# Drawk

wayluigi-backed dmenu replacement, designed for Sway.

Reads newline-separated items from stdin, opens a centered floating window
with a search field and a filtered list, prints the selected item to stdout
on Enter, exits 1 on Escape or empty stdin.

## Build

```
./download-deps.sh
nimble build -d:wayland -d:release
```

## Use

```
printf 'alpha\nbeta\ngamma\n' | ./Drawk
```

## Keys

| Key                   | Action                                  |
| --------------------- | --------------------------------------- |
| printable characters  | append to the filter query              |
| Backspace             | delete one byte from the query (ASCII)  |
| Up / Down             | move selection                          |
| Ctrl+P / Ctrl+N       | move selection                          |
| Enter                 | print selection to stdout, exit 0       |
| Escape                | exit 1 without printing anything        |

## Sway integration

Drawk sets its xdg `app_id` to `Drawk`, so a single `for_window` rule pins
size and position. Add to `~/.config/sway/config`:

```
for_window [app_id="Drawk"] {
    floating enable
    resize set 480 360
    move position center
    border none
}

# launch any executable on $PATH
bindsym $mod+d exec --no-startup-id sh -c \
  'find $(echo $PATH | tr : " ") -maxdepth 1 -type f -executable -printf "%f\n" \
   | sort -u | Drawk | xargs -r swaymsg exec --'
```

The `resize set` is needed because Wayland compositors negotiate window
size via `xdg_toplevel.configure` and may override the size Drawk requests
at creation.

## Theming

Drawk follows the rawk family palette convention. Default is gruvbox
material dark, baked in at `src/theme.nim`. Override per-user by dropping a
`.theme` file in `~/.config/Drawk/themes/` — same format as Edrawk's
`themes/default.theme`. To switch the active theme, edit
`src/theme.nim`'s `activeTheme` (no runtime config file yet).

Font follows `fc-match monospace:mono` by default; override with the
`RAWK_FONT` environment variable pointing at a TTF path.

## License

GPL-3.0-only.
