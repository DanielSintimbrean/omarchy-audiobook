# Audiobook — Omarchy shell plugin

An audiobook player that lives in the Omarchy bar. Pick a book from a folder,
see its chapters and how far along you are, and it resumes exactly where you
paused — across shell restarts and reboots.

Deliberately small: no notes, no bookmarks, no history. One library folder,
one book at a time, one position per book.

## Install

```bash
omarchy plugin add https://github.com/DanielSintimbrean/omarchy-audiobook.git --enable
```

Requires `mpv` (already part of Omarchy). Nothing else.

## Use

Drop books into `~/Audiobooks`:

- a single audio file with embedded chapters (`.m4b`, `.m4a`, `.mp3`, `.opus`, `.ogg`, `.flac`, …), or
- one folder per book containing numbered audio files — each file becomes a chapter.

Bar icon (`󰋋`):

| Action        | Effect                    |
|---------------|---------------------------|
| Left click    | open the panel            |
| Middle/right  | play / pause              |
| Scroll        | seek ±30 s                |
| Hover         | title · chapter · percent |

Panel: seek bar, elapsed / percent / total, previous chapter · −30 s ·
play/pause · +30 s · next chapter, playback speed (0.75×–2×), chapter list
(click to jump) and a Library view to switch books. `Esc` closes, `Tab`
moves to the next bar panel, `Space` toggles play, `←`/`→` seek, `↑`/`↓`
change speed.

Open the panel from a keybinding:

```lua
o.bind("SUPER + CTRL + ALT + A", "Audiobook", "omarchy-shell shell toggle io.github.danielsintimbrean.audiobook")
```

## Settings

Inline on the widget's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.danielsintimbrean.audiobook", "library": "~/Audiobooks" }
```

## IPC

```
omarchy-shell audiobook status        # JSON: book, position, duration, percent, chapter, speed
omarchy-shell audiobook playPause
omarchy-shell audiobook play | pause
omarchy-shell audiobook next | previous   # chapter
omarchy-shell audiobook seek 30       # seconds, negative to rewind
omarchy-shell audiobook speed 1.25
omarchy-shell audiobook load /path/to/book   # a path from the library
omarchy-shell audiobook rescan
```

## How it works

- `Service.qml` runs one `mpv` process (`--no-config --load-scripts=no`, so no
  MPRIS and no interference with the stock media widget) and talks to it over
  its JSON IPC socket at `$XDG_RUNTIME_DIR/omarchy-audiobook.sock`.
- Folder books are loaded as a single mpv EDL, so chapters, total duration and
  percent work the same as for a single file.
- State is written to `~/.local/share/omarchy-audiobook/state.json` on pause,
  seek, chapter/book switch, shell exit, and every 10 s while playing.
- The bar widget and panel only read from the service; the service is the one
  instance shared across monitors.

## Privilege boundary

Runs unsandboxed inside `omarchy-shell` like every plugin. It spawns `mpv` and
`bash` (to list the library folder), reads audio files under the configured
library, and writes only `~/.local/share/omarchy-audiobook/state.json`. No
network access, no sudo.

## License

MIT
