# Rhythm RPG

A rhythm-RPG prototype built in **Godot 4.7**, inspired by the *Beatspell* mode
from Rhythm Heaven Groove: fight monsters by casting spells **on the beat**.

Charge spells with arrow keys in time with the music, release with SPACE —
your timing accuracy decides the spell's power. All-perfect casts **crit**.

## Features

- **Data-driven spellbook** — every spell is a rhythm pattern on an
  eighth-note grid (`C_S`, `CCS`, `C_CCC_S`…); adding a spell is one line of data
- **Suffix-matched casting** — fumbled early presses are forgiven; the spell
  is whatever your input *ends* with
- **Scripted enemy attack patterns** on the same rhythm grid, telegraphed by
  sound and color (parry support planned)
- **Endless mode** — win, pick a spell to level up, fight a +10% stronger foe
- **Death protection & Life Hearts** — lethal hits leave you at 0 HP with the
  game drumming Cure's rhythm at you; hits at 0 HP burn hearts
- **Latency calibration** — auto-calibrates from your own tap timing (`0`),
  BPM adjustable live (`-`/`=`), judgment windows scale with tempo
- All sound effects synthesized from scratch (Python-generated WAVs)

## Controls

| Key | Action |
|---|---|
| ← | Charge (basic spells) |
| SPACE | Cast — the final note of every pattern |
| 1–7 | Choose level-up after a victory |
| ESC | Pause |
| R | New run after game over |
| `-` / `=` | BPM ±10 (debug) |
| `<` / `>` / `0` | Input offset ±5 ms / auto-calibrate (debug) |

## Run it

Open the project folder in [Godot 4.7+](https://godotengine.org) and press F5.
