# Beatspell-like — Plan

A tiny rhythm-RPG in Godot 4.7, inspired by Beatspell (Rhythm Heaven Groove):
battle monsters by pressing keys in time with the beat. Timing quality
(Perfect / Good / Miss) determines spell power.

## Core loop

```
Conductor (beat clock) ──beat──▶ visuals pulse, enemy acts on a schedule
        ▲
        │ "how far off the beat was that press?"
Player input (SPACE) ──▶ judgment ──▶ charge spell ──▶ damage enemy
```

## Phases

### Phase 0 — Bootstrap ✅ (done)
Empty project, git, verified import.

### Phase 1 — Beat engine + one battle ✅ (this build)
- `Conductor`: fixed-BPM clock (100 BPM), emits a `beat` signal, plays a click
- Beat ring UI: shrinking ring shows when the next beat lands
- Judgment windows: Perfect ≤ 70 ms, Good ≤ 150 ms, else Miss
- One spell: **Firebolt** — 4 on-beat presses charge it, Perfect charges more
- One enemy: Cave Slime (60 HP), attacks every 8 beats for 8 damage,
  telegraphs 2 beats ahead by turning red
- Win / lose states, R to retry

### Phase 1.5 — SpellBook system ✅ (this build)
Wiki-accurate spell notation on an eighth-note grid: `C` charge / `S` cast /
`_` eighth rest. All basic spells charge with ←, SPACE releases.
The press sequence + rhythm is quantized to the grid and matched against the
spellbook (`scripts/spellbook.gd`); unknown patterns fizzle harmlessly.

| Spell | Pattern | Lv1–5 | Type / notes |
|---|---|---|---|
| Flame | `C_S` | 30–60 | fire |
| Cure | `CCS` | 30–60 | heal; floor 50%, Perfect = full, no crit ×2 |
| Wave | `C_C_C_S` | 75–180 | water |
| Bolt | `C_CCC_S` | 120–240 | electric |
| Needle | `C_CS` | 60–120 | normal; 15 recoil to self (ignores Defense+) |
| Attack+ | `C__C__S` | 50/60/60/75/100% | dmg buff, 32/32/48/48/48 beats; tier weak 50% / normal 75% / crit 100% of max |
| Defense+ | `C__CC_S` | 70/80/80/90/100% | dmg reduction buff, same tier/duration structure |

- Damage scales continuously with press accuracy, floored at **5%**
- Every press Perfect → **crit ×2**
- Spell level currently fixed at 1
- Walk away mid-charge for 2 beats → spell dissipates

### Phase 1.6 — Enemy attack patterns ✅ (this build)
Every enemy owns a unique scripted attack pattern on the same eighth-note
grid (`C` charge cue / `A` attack ~25 / `H`+`A` heavy charge → 50 dmg /
`_` beat rest / `-` eighth rest). The slime loops six 16-beat phrases that
escalate, with one breather bar. Because attack slots are known in advance,
**parry** becomes possible later (press a key exactly on the attack slot).
- Charge = red flash + rising tone; heavy charge = slime swells for 3 beats
- Attack = lunge + thud sfx; slime bobs vertically on every beat
- Casts/fizzles log to the bottom-left; enemy shows only damage numbers + CRIT

### Phase 1.7 — Endless mode, persistence, UX ✅ (this build)
- **GameState autoload** + `user://save.json`: bpm, input offset, items
  (placeholder), known spells, spell levels, Life Hearts, round number
- **Endless loop**: win → pick one spell to level up (keys 1–7) → next round,
  enemy ×1.10 hp & damage. Player HP refills each round.
- **Life Hearts**: start with 3; hits taken at 0 HP cost one; 0 hearts =
  game over → new run (Round 1, hearts refilled, spell levels KEPT)
- Death protection + Cure-rhythm alarm every 2 beats at 0 HP (red flash
  synced to the ticks)
- Input latency calibration: `<`/`>` nudge ±5 ms, `0` auto-calibrates from
  recent taps; judgment windows scale with BPM (25% of a slot = Perfect)
- Fuzzy casting: input tail is matched (stray early presses forgiven)
- Debug: `-`/`=` BPM ±10; pause on ESC
- Spellbook panel: name + level + pattern drawn as diamond glyphs

### Phase 2 — Make it a real rhythm game (next, hands-on)
- Sync beats to an actual music track (AudioStreamPlayer playback position
  + latency compensation) instead of a bare timer
- Combo counter & score, better hit/miss feedback (particles, screen shake)

### Phase 3 — Make it an RPG
- **Parry**: press a key exactly on an enemy attack slot to negate/reduce it
- Weird-monster spells using ↑ ↓ → (interface reserved)
- Elemental weaknesses per enemy, spell leveling (tables already in data)
- Enemy variety: new enemy = new attack-phrase list + sprite

### Phase 4 — Structure & polish
- Chapter map: several battles in a row, boss at the end
- Real art/sprites, menus, save progress
- Stretch: randomized cave (the roguelike mode Beatspell unlocks)

## Balance (current)
| Thing | Value |
|---|---|
| BPM | 100 default (0.6 s/beat); debug-adjustable, persisted |
| Player HP | 100, refilled each round; 3 Life Hearts per run |
| Slime | 1200 HP, hits 25 / heavy 50 — all ×1.10 per round |
| Perfect window | 25% of an eighth slot (scales with BPM; 75 ms @ 100 BPM) |

## Controls
- **←** — charge (all basic spells) · **↑ ↓ →** reserved for weird-monster spells
- **SPACE** — release/cast · **R** — restart run after game over
- **1–7** — pick level-up after a win · **ESC** — pause
- Debug: **-/=** BPM ±10 · **< / >** input offset ±5 ms · **0** auto-calibrate
