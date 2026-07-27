# Rhythm RPG — design & handoff notes

A rhythm-roguelite in **Godot 4.7** (GDScript), inspired by *Beatspell* from
Rhythm Heaven Groove. You cast spells by pressing keys on the beat; accuracy
decides power. Runs are a 21-round campaign over generated maps.

This document is the handoff: how it's built, how to work on it, and what's
left. Read `README.md` first for the player-facing view.

---

## Running & verifying

Godot is installed per-user via winget, so the binary path differs per
machine. On the dev box:

```
%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.1-stable_win64.exe
```

Workflow used throughout development — **always verify headless before
launching the window**, because a GDScript parse error otherwise shows up as
a silently blank game:

```
godot --headless --path <project> --import --quit     # after adding assets
godot --headless --path <project> --quit-after 300    # parse + runtime check
godot --path <project>                                # play it
```

Exit code 0 with no `SCRIPT ERROR` lines means the build is good.

**Gotcha:** never bulk-edit `.gd`/`.tscn` files with PowerShell `-replace`.
`Get-Content` reads them as ANSI, so every non-ASCII character (`←`, `—`, `♥`)
is destroyed on write. Use an editor/IDE or Python with explicit UTF-8.

---

## Architecture

```
scenes/
  menu.tscn         main menu (start scene)
  main.tscn         everything else: battle, map, rewards, pause
  select_menu.tscn  reusable full-screen cursor menu (CanvasLayer)
scripts/
  game_state.gd     autoload GameState — run state + save file + map gen
  music_library.gd  autoload MusicLibrary — user://music scanning, per-track bpm/offset
  conductor.gd      the beat clock (AudioStreamPlayer + beat/eighth signals)
  battle.gd         the big one: input, casting, rewards, map flow, phases
  spellbook.gd      SpellBook — spell data + press-sequence resolution
  item_db.gd        ItemDB — all items as data + rarity rolls
  enemy.gd          enemy data (stats + attack phrases) and presentation
  beat_ring.gd      the rhythm diamond
  map_view.gd       the cycle map drawing + hover tooltip
  spell_fx.gd       per-spell impact effects
  will_clock.gd     the Willpower clock gauge
  select_menu.gd    cursor menu logic (emits `chosen`)
  menu.gd           main menu
  pause.gd          ESC pause (process_mode = ALWAYS)
tools/
  make_audio.py     regenerates every .wav in audio/ (no recorded assets)
```

`battle.gd` is a state machine on `phase`:
`prelude_map` → `character` → `choice` (map) → a node → `battle` → `won` →
`chest`/`upgrade`/`learn`/`replace` → back to `choice`; plus `over`.
Every menu goes through `SelectMenu.open(title, options)` and comes back via
`_on_menu_chosen(i)`, keyed by `phase`, with `menu_payload` holding the
per-option data.

---

## Core systems

### The grid
`conductor.gd` counts time itself (`song_time`) and emits `beat` and `eighth`.
Everything — spell patterns, enemy attacks, telegraphs — lives on the
**eighth-note grid** (`half_beat` seconds per slot). Count-in is 16 beats
(4 in calibration); `song_time` is negative during it.

### Casting (`spellbook.gd`)
Spells are data: `"pattern": "L_S"` where `L` = ← charge, `S` = SPACE release,
`_` = eighth rest. `resolve(presses, half_beat, known)`:

1. Quantize press times to slots **relative to the first press** (so being
   systematically late never mangles the shape).
2. Rebuild a pattern string, match it as a **suffix** of a known spell —
   stray early presses are forgiven and reported as `stray`.
3. The spell must start on a **whole beat** (unless `free_start`), and every
   press in the matched tail must land within `HIT_FRACTION` (40%) of its
   slot, or the cast fizzles.
4. `quality()` returns average accuracy (cliff to 70% outside the perfect
   window, then quadratic falloff, floor 5%) and `crit` = all presses perfect.

Damage: **only a crit reaches a spell's listed max**; non-crits are capped
(`NONCRIT_DAMAGE_CAP` 60%, Bolt 30% via `noncrit_cap`). Heals floor at 50%.
The crit window is `GameState.perfect_fraction` (16% of a slot, tunable in
calibration and saved).

### Enemies (`enemy.gd`)
Each enemy is an entry in `ENEMY_TYPES`: stats, colour, radius, `phrase_slots`
and `phrases` — event lists on the grid (`C` charge, `A` attack, `H`/`HA`
heavy). `setup()` flattens phrases into a global slot→event map **and injects
telegraph ticks**: two `d` events on the off-beats before each *group* of
charges (a group = a burst; nothing else within the previous 2 beats).

Stun (perfect parry) freezes events but not the cycle position, and disarms:
after waking, attacks are skipped until a fresh charge re-arms the enemy — so
a chain whose opening charge was stunned is cancelled entirely.

### Same-beat resolution
Enemy hits are queued (`pending_attacks`) and only land after the beat's
judgment window closes, so a kill, a Cure or a Defense+ on the same beat
resolves **first**. This is deliberate: the player wins ties.

### The map (`GameState.generate_map`)
Each 7-round cycle generates 6 rows of 1–4 nodes plus a boss row. Edges use a
**non-crossing sweep**: each node owns a contiguous, only-rightward span of
the next row. Node odds come from `MAP_NODE_POOL`; in the first cycle a
Willpower Well can't appear before a fight has. Round 0 is the Prelude node
drawn at column −1.

Campaign: bosses at 7/14/21, clear after 21 — except **Harmonia**, who
continues to a forced well (22), an all-UR relic vault (23) and a final boss
(24) for the true clear.

### Characters, lifelines, items
- Characters: `virtuosa` (parry via ↓), `domina` (+10 atk / −10 taken / +10
  heal), `harmonia` (nothing, and no rhythm diamond; true-ending route).
- Lifelines: Life Hearts or the Willpower clock (drains per beat, double
  damage at 0 HP, cracks below 25% so the reading is hidden).
- `item_db.gd`: additive fields (`max_hp`, `atk_flat`, `heal_flat`,
  `def_flat`, `type_flat`) are summed generically; unique behaviours are
  matched by id in `battle.gd`. Items never repeat within a run.

### Persistence
`user://save.json` (`%APPDATA%\Godot\app_userdata\<config/name>\`). Run state
is gated behind `SAVE_VERSION`; calibration (bpm, offsets, crit window) and
per-character `records` load regardless of version.

### Audio
Every SFX is synthesized by `tools/make_audio.py` — edit a function, re-run,
Godot re-imports. Music is user-supplied: `user://music/` with per-track bpm
and offset in `library.json`, tuned in Calibration Mode (`N` cycles tracks).
No copyrighted audio is committed.

---

## Balance snapshot

| Thing | Value |
|---|---|
| Player HP | 100 base (+ cake items), refilled each round |
| Enemy scaling | linear, +25% of base per round; bosses ×2 HP |
| Slime / Clown / Hammer | 1200/25/50 · 1000/18/42 · 1400/33/66 |
| Enemy damage variance | 80–100% |
| Perfect window | 16% of an eighth slot (tunable, saved) |
| Hit window | 40% of a slot, else fizzle |
| Non-crit damage cap | 60% (Bolt 30%) |
| Willpower | 600 beats, −1/beat, ×2 damage at 0 HP |
| Stun | 8 beats (12 with Flashy Nail), +50% damage taken |

---

## Open work

**Next up**
- Score system (`records[*].best_score` is already persisted, nothing writes it)
- Items that need missing systems: Clarity Lens (weird monsters), Rainbow
  Stone / Evil Eye (elemental effectiveness), Evil Seed (poison) — these are
  in `item_db.gd` comments but excluded from the drop pool
- Per-enemy music/BPM (the hook exists: each battle already picks a track)
- Final-boss balance: at round 24 the linear scaling is ×6.75 before the
  boss ×2, which is likely too much

**Later**
- Weird-monster encounters: monster-specific spell sets using ↑ ↓ → (the
  input path already supports those keys)
- Real sprites/art; the game is entirely `_draw()` primitives today
- `config/name` in project.godot is still "First Game" — renaming it moves
  the `user://` save directory, so migrate the save if you change it
