---
name: run-rhythm-rpg
description: Launch, verify and drive this Godot rhythm-RPG — headless parse check, opening the game window, and reaching a given screen with the keyboard. Use when asked to run the game, start it, check that a change works in the real app, or reproduce something in-game.
---

# Running Rhythm RPG

Godot 4.7 project, GDScript, no build step — the engine runs the source
directly. Start scene is `scenes/menu.tscn`.

## Where Godot lives

The binary is installed per-machine, so the invocation differs:

| Machine | Invocation |
|---|---|
| macOS (Homebrew cask) | `godot` — on `PATH`, symlinked from `/Applications/Godot.app` |
| Windows dev box (winget) | `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.1-stable_win64.exe` |

Check `godot --version` first. If it's missing on macOS:

```bash
brew install --cask godot
```

Match the project's engine version (`config/features` in `project.godot`) —
4.7.x today.

## Always verify headless before opening a window

A GDScript parse error doesn't crash the game, it renders a **silently blank
screen**. So never launch the window as the first step:

```bash
godot --headless --import --quit    # after adding or changing any asset
godot --headless --quit-after 300   # parse + ~300 frames of runtime
```

Exit code 0 with no `SCRIPT ERROR` lines means the build is good. Grep for it
rather than eyeballing — the import log is long and noisy:

```bash
godot --headless --quit-after 300 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"
```

**What headless does not prove.** `--headless` implies `--audio-driver Dummy`
and the start scene is the menu, so a headless run never reaches a battle.
Beat timing, latency calibration, the metronome, spell SFX and anything about
what the game *sounds* like are all untested by it. Those need the window.

## Opening the window

```bash
godot --path .
```

Launch it as a **tracked background command** (the Bash tool's
`run_in_background`). A `nohup … &` from an ordinary Bash call is reaped the
moment that call returns — the engine prints its two startup lines, then the
process is gone with no error, which reads exactly like a crash. If the log
ends after `Metal … Using Device #0` and the process is missing, that's this,
not a bug in the game.

The process staying alive is the launch check. Exit code 0 later means the
player quit normally; 143 means it was killed (usually by you, to relaunch
with new code).

## Seeing it

The game is a GUI window and everything in it is drawn with `_draw()`
primitives — there is no DOM, no accessibility tree, no log of what's on
screen. Reading its visual state means capturing the screen, which is the
user's call: **ask before capturing, and prefer capturing only the Godot
window over the whole desktop.** If that isn't available, say plainly that
visual/audio behaviour is unverified rather than implying you checked it, and
ask the user what they see — the window is already on their screen.

## Driving it

Every menu — main, pause, character pick, chests, upgrades, game over — is
the same full-screen cursor menu (`select_menu.gd`): **↑↓←→** move, **SPACE**
confirms. No mouse, no number keys.

Main menu order: `New Run — Life Hearts` · `New Run — Willpower` ·
`Calibration Mode` · `Music Folder` · `Quit`.

In battle: **←** charges, **SPACE** casts, **↓** parries (Virtuosa only),
**ESC** pauses, **R** starts a new run after a game over.

**Calibration Mode is the fastest way to test anything rhythm-related** — no
enemy, no stakes, all spells unlocked, a 4-beat count-in instead of 16, and
every debug aid already on (metronome, rhythm diamond, cursor ball, per-press
timing in ms). Reach it from the main menu with **↓↓ SPACE**.

In a normal battle, **F1** toggles the same debug readout and tuning keys, and
**F4** deletes the enemy — the quick way to walk the map to a specific node
type or reward screen without playing the fights.

## Machine-local state

Saves and the music library live in `user://`, outside the repo:

| Platform | Path |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/First Game/` |
| Windows | `%APPDATA%\Godot\app_userdata\First Game\` |

("First Game" is `config/name` in `project.godot`. Renaming it moves this
directory and orphans existing saves.)

**No music ships with the repo** — `audio/bgm_keycard.mp3` is gitignored for
copyright, and `user://music/` starts empty. An empty library is the normal
state on a fresh clone: battles fall back to the bare beat clock at 118 BPM,
and the metronome auto-enables so there's still an audible beat. So "no music
plays" is expected, not a bug to chase. To test with real music, drop an
mp3/ogg/wav into `user://music/` (main menu → `Music Folder` opens it) and
tune its BPM and offset in Calibration Mode (`N` cycles tracks). `.gitignore`
excludes `*.mp3`, so anything you drop in stays local either way.

Delete `user://save.json` to test a fresh-install run; calibration values and
per-character records survive save-version bumps, run state does not.

## Editing gotcha

Never bulk-edit `.gd` / `.tscn` with PowerShell `-replace` — `Get-Content`
reads them as ANSI and destroys every non-ASCII character (`←`, `—`, `♥`,
`☠`), which the files are full of. Use an editor, or Python with explicit
UTF-8. On any platform, `Edit` on these files can fail on indentation:
they're **tab**-indented, and `match` arms sit one level shallower than they
look.
