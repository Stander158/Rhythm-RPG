class_name SpellBook
extends RefCounted
## The spellbook: every spell is DATA, not code. Adding a spell = adding a row.
##
## Patterns use an eighth-note grid (each symbol = half a beat), wiki-style:
##   "L" = LEFT arrow charge (the wiki's C — all basic spells charge with LEFT)
##   "S" = SPACE, the cast/release note
##   "_" = eighth rest (the wiki's _)
## Future weird-monster spells can use "U"/"D"/"R" for the other arrows.
##
## damage[0..4] = max damage at spell level 1..5 (wiki values).
## Rules: every press judged against the grid; damage scales with accuracy
## down to a 5% floor; ALL presses Perfect = crit (x2 damage).

# Judgment windows are FRACTIONS of an eighth-note slot, so they scale with
# BPM (fixed seconds would make fast tempos trivially easy: once the slot
# shrinks below the window, everything is "Perfect").
const PERFECT_FRACTION := 0.16  # of a slot; ~41 ms @ 118 BPM — crits must be earned
const CLOSE_FRACTION := 0.37    # "blue" feedback tier; ~94 ms @ 118 BPM
const NONPERFECT_CAP := 0.7     # miss the perfect window at all -> at most 70% power
const FALLOFF_POWER := 2.0      # then quality decays quadratically — small errors cost a lot
const HIT_FRACTION := 0.40      # a press farther than this from its slot is NOT a hit —
								# every charge and the release must actually land on the grid
const MAX_SLOTS := 16

const SPELLS := [
	{ "name": "Flame", "pattern": "L_S", "type": "fire",
	  "damage": [30, 38, 45, 53, 60] },
	{ "name": "Cure", "pattern": "LLS", "type": "heal",
	  "damage": [30, 38, 45, 53, 60] },
	{ "name": "Wave", "pattern": "L_L_L_S", "type": "water",
	  "damage": [75, 93, 114, 141, 180] },
	# Bolt is all-or-nothing (like the original): non-crit casts are halved
	{ "name": "Bolt", "pattern": "L_LLL_S", "type": "electric",
	  "damage": [120, 143, 165, 195, 240], "noncrit_mult": 0.5 },
	{ "name": "Needle", "pattern": "L_LS", "type": "normal",
	  "damage": [60, 75, 90, 105, 120], "self_damage": 15 },
	# Buffs: value = % at full strength for this level; actual strength is
	# max * 0.5 (weak) / 0.75 (normal) / 1.0 (crit), lasting buff_beats.
	{ "name": "Attack+", "pattern": "L__L__S", "type": "buff_atk",
	  "buff_pct": [0.50, 0.60, 0.60, 0.75, 1.00], "buff_beats": [32, 32, 48, 48, 48] },
	{ "name": "Defense+", "pattern": "L__LL_S", "type": "buff_def",
	  "buff_pct": [0.70, 0.80, 0.80, 0.90, 1.00], "buff_beats": [32, 32, 48, 48, 48] },
]

static func get_spell(spell_name: String) -> Dictionary:
	for spell in SPELLS:
		if spell["name"] == spell_name:
			return spell
	return {}

## Turn a recorded press sequence into a spell (or a fizzle). Only spells in
## `known` can be cast.
## presses: [{ "time": seconds, "sym": "L"/"S"/... }] — last one is always "S".
## Two separate questions, answered separately:
##   WHICH spell?  -> press spacing relative to the FIRST press (so being
##                    systematically late never mangles the pattern shape)
##   How WELL?     -> each press's distance from the true eighth-note grid
static func resolve(presses: Array, half_beat: float, known: Array) -> Dictionary:
	var t0: float = presses[0]["time"]
	var slots := {}
	var press_slots: Array[int] = []
	for p in presses:
		var slot := int(roundf((p["time"] - t0) / half_beat))
		if slots.has(slot):
			return { "ok": false, "reason": "two inputs in one slot" }
		slots[slot] = p["sym"]
		press_slots.append(slot)
	var last_slot: int = slots.keys().max()
	if last_slot >= MAX_SLOTS:
		return { "ok": false, "reason": "spell too long" }
	var pattern := ""
	for i in last_slot + 1:
		pattern += slots.get(i, "_")
	# Fuzzy fit: the spell is whatever the input ENDS with — stray earlier
	# presses are forgiven (C_C_S casts Flame via its C_S tail). An exact
	# full match is simply the longest possible suffix, so a real C_C_S
	# spell added later automatically wins over Flame.
	var best := {}
	for spell in SPELLS:
		if not known.has(spell["name"]):
			continue
		if pattern.ends_with(spell["pattern"]):
			if best.is_empty() or spell["pattern"].length() > best["pattern"].length():
				best = spell
	if best.is_empty():
		return { "ok": false, "reason": "unknown pattern " + pattern }
	var tail_start: int = pattern.length() - best["pattern"].length()
	# The tail's first press is the spell's true start (patterns begin with a key)
	var t_tail := t0
	for i in presses.size():
		if press_slots[i] == tail_start:
			t_tail = presses[i]["time"]
			break
	# Spells must START on a whole beat — a solid corner of the diamond —
	# unless the spell data carries "free_start": true (none do yet).
	var beat := half_beat * 2.0
	var anchor: float
	if best.get("free_start", false):
		anchor = roundf(t_tail / half_beat) * half_beat
	else:
		anchor = roundf(t_tail / beat) * beat
		if absf(t_tail - anchor) > half_beat * 0.5:
			return { "ok": false, "reason": "start on a whole beat" }
	# Only presses inside the matched tail count toward accuracy (and crits),
	# each judged against the whole-beat-anchored grid. Every one of them must
	# actually LAND on its grid point (within HIT_FRACTION of a slot) — a
	# charge drifting toward the next half-beat is not that slot's command.
	var tail_offsets: Array[float] = []
	var stray := 0
	for i in presses.size():
		if press_slots[i] >= tail_start:
			var rel := press_slots[i] - tail_start
			var off := absf(presses[i]["time"] - (anchor + rel * half_beat))
			if off > half_beat * HIT_FRACTION:
				return { "ok": false, "reason": "charge off the beat" }
			tail_offsets.append(off)
		else:
			stray += 1
	return { "ok": true, "spell": best, "offsets": tail_offsets, "stray": stray }

## Accuracy -> power. A press inside the perfect window is worth 1.0.
## Outside it there's a CLIFF: value drops straight to NONPERFECT_CAP and
## then decays quadratically to 0 at the worst offset (half a slot) — being
## slightly off costs a lot. Average is floored at 5%. All Perfect = crit.
static func quality(offsets: Array, half_beat: float, perfect_fraction: float = PERFECT_FRACTION) -> Dictionary:
	var perfect := half_beat * perfect_fraction
	var worst := half_beat / 2.0
	var total := 0.0
	var all_perfect := true
	for off in offsets:
		if off <= perfect:
			total += 1.0
		else:
			all_perfect = false
			var t := clampf((off - perfect) / (worst - perfect), 0.0, 1.0)
			total += NONPERFECT_CAP * pow(1.0 - t, FALLOFF_POWER)
	return { "avg": maxf(total / offsets.size(), 0.05), "crit": all_perfect }
