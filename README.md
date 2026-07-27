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
- **Three characters** — Virtuosa parries with a dedicated key (a perfect
  parry stuns and cancels the whole attack chain), Domina trades that for raw
  stats, and Harmonia plays with no aids at all — no bonuses, no rhythm
  diamond — as the only route to the true ending. Best round, clears and true
  clears are recorded per character.
- **30+ items** — chests and elites offer 3-choose-1 loot with round-scaled
  rarity odds; boss relics bend the rules (crit-tripling gems, a ring that
  pins your HP at 0…). Items never repeat within a run.
- **User music library** — drop your own mp3/ogg/wav into a folder, tune each
  track's BPM and phase offset in-game; battles shuffle your playlist
- **Two lifelines** — Life Hearts (3 hearts, a hit at 0 HP burns one) or
  **Willpower**: a clock-face gauge that drains every beat, takes double
  damage at 0 HP, and *cracks* below 25% so you can't read it anymore
- **Scripted enemy attack patterns** on the same rhythm grid (slime, clown,
  hammer man). Every attack burst is telegraphed two beats out by off-beat
  ticks while the enemy slides into its charge colour; heavy blows wind up
  with an aura, a tremble and a rising drone.
- **Per-spell impact effects** at three intensities — fire tongues, water
  ripples, lightning forks, needle spikes, healing pluses, buff chevrons and
  shields, all drawn in code and gone within the beat
- **Calibration mode** — no enemy, all spells unlocked, per-press timing
  readout in ms, auto-calibration of input latency from your own taps
- All sound effects synthesized from scratch (Python-generated WAVs)

## Controls

| Key | Action |
|---|---|
| ← | Charge (all current spells) |
| ↓ | Parry (Virtuosa only) |
| SPACE | Cast — the final note of every pattern |
| ↑ ↓ ← → + SPACE | Every menu and the run map |
| ESC | Pause |

**Debug:** `F1` toggles debug mode in battle, `F4` insta-kills. Then (or in
calibration mode): `-`/`=` BPM ±1 · `<`/`>` input offset ±1 ms · `[`/`]` music
offset ±1 ms · `0` auto-calibrate · `M` metronome · `D` diamond · `B` cursor ·
`T` timing readout · `;`/`'` crit window · `N` next track

## Run it

Open the project folder in [Godot 4.7+](https://godotengine.org) and press F5.

**Music:** the repo ships without any BGM (copyright). Pick *Music Folder* in
the main menu and drop mp3 / ogg / wav files in — then tune each track's BPM
and phase offset in Calibration Mode. Without a track the game runs on its own
beat clock (turn the metronome on with `M`).
