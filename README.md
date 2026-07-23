# Rhythm RPG

A rhythm-roguelite built in **Godot 4.7**, inspired by the *Beatspell* mode
from Rhythm Heaven Groove: fight monsters by casting spells **on the beat**.

Charge spells with arrow keys in time with the music, release with SPACE —
every press must land on the rhythm grid, and timing accuracy decides the
spell's power. All-perfect casts **crit**.

## Features

- **Data-driven spellbook** — every spell is a rhythm pattern on an
  eighth-note grid (`C_S`, `CCS`, `C_CCC_S`…); adding a spell is one line of data
- **Suffix-matched casting** — fumbled early presses are forgiven; the spell
  is whatever your input *ends* with. Off-grid presses fizzle.
- **Roguelite run structure** — start with Flame + Cure at Lv1 and walk a
  generated, fully visible 7-round map (fight / elite / well / learn / chest
  nodes with branching paths); every 7th round is a double-HP **boss**
- **Rings & parry** — pick a run-start ring: Flip Ring unlocks a dedicated
  parry key (perfect parries stun and cancel attack chains), Strong Ring
  trades it for raw stats
- **30+ items** — chests and elites offer 3-choose-1 loot with round-scaled
  rarity odds; boss relics bend the rules (crit-tripling gems, a ring that
  pins your HP at 0…). Items never repeat within a run.
- **User music library** — drop your own mp3/ogg/wav into a folder, tune each
  track's BPM and phase offset in-game; battles shuffle your playlist
- **Two lifelines** — Life Hearts (3 hearts, a hit at 0 HP burns one) or
  **Willpower**: a clock-face gauge that drains every beat, takes double
  damage at 0 HP, and *cracks* below 25% so you can't read it anymore
- **Scripted enemy attack patterns** on the same rhythm grid (slime, clown,
  hammer man), telegraphed by sound and color — parry support planned
- **Real BGM** beat-synced at 118 BPM, with live-tunable phase offset
- **Calibration mode** — no enemy, all spells unlocked, per-press timing
  readout in ms, auto-calibration of input latency from your own taps
- All sound effects synthesized from scratch (Python-generated WAVs)

## Controls

| Key | Action |
|---|---|
| ← | Charge (all current spells) |
| SPACE | Cast — the final note of every pattern |
| 1–5 | Menu / map choices |
| ESC | Pause (then M = main menu) |
| R | New run after game over |

**Debug:** `-`/`=` BPM ±1 · `<`/`>` input offset ±1 ms · `[`/`]` music offset
±1 ms · `0` auto-calibrate · `M` metronome · `D` ring · `B` cursor ·
`T` timing readout · `;`/`'` crit window (calibration)

## Run it

Open the project folder in [Godot 4.7+](https://godotengine.org) and press F5.

**Music:** the repo ships without a BGM track (copyright). Drop any ~118 BPM
track at `audio/bgm_keycard.mp3` and the game picks it up automatically —
without one it runs on the beat clock (enable the metronome with `M`).
