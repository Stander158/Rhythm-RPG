extends Node
## Autoload singleton: everything that must survive a restart (R) and a full
## quit. Lives outside the battle scene, so reloading the scene doesn't touch
## it; on top of that every change is saved as JSON to user://save.json.
## (user:// on Windows = %APPDATA%\Godot\app_userdata\First Game\)
##
## Run structure (roguelike): every new run starts with Flame + Cure at Lv1.
## Each victory grants one level-up AND a chance to learn a new spell
## (3 random choices, or skip for +1 Life Heart). Max 5 spells known —
## learning past that replaces one, and the newcomer inherits its level.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const RUN_START_SPELLS := ["Flame", "Cure"]
const MAX_SPELLS := 5
const WILLPOWER_MAX := 600  # beats; drains 1 per battle beat

var bpm := 100.0
var input_offset := 0.0
var has_input_offset := false  # false -> seed from the audio driver's estimate
var music_offset := 0.09       # seconds skipped at the start of the BGM (phase alignment; tuned for the current track)
var perfect_ms := 25.0   # crit window in MILLISECONDS, tempo-independent (tunable in calibration)
var items: Array = []          # inventory (future)
var known_spells: Array = RUN_START_SPELLS.duplicate()
var spell_levels := {}         # missing entries mean Lv1
var hearts := 3     # Life Hearts: lost when hit at 0 HP; 0 hearts = game over
var round_num := 1  # endless mode round; enemy scales linearly per round
# Lifeline system, chosen at the start of each run:
#   "hearts"    — classic: 3 hearts, a hit at 0 HP burns one & restores HP
#   "willpower" — a WILLPOWER_MAX-beat countdown gauge; drains 1 every battle
#                 beat, hits at 0 HP drain it by the damage, HP stays 0.
#   ""          — not chosen yet (battle shows the selection screen)
var life_mode := ""
var willpower := WILLPOWER_MAX
var character := ""       # "virtuosa" (parry) / "domina" (stats) / "harmonia" (hard); "" = unchosen
var records := {}         # character id -> { best_round, cleared, true_clear, best_score }
var suit_crits := 0       # crits landed while holding the Power-Restricting Suit
var band_aid_used := false
# The cycle map: 7 rows of nodes (row 6 = boss). Player sees the whole cycle
# and walks it along random edges, Slay-the-Spire style.
var map_rounds: Array = []
var map_cycle := -1  # which cycle the current map belongs to
var map_pos := -1    # node index reached in the last completed row (-1 = cycle start)

# Node-type weights for map generation (duplicates = higher odds):
# fight 30% · chest 30% · learn 20% · elite 10% · well 10%
const MAP_NODE_POOL := ["fight", "fight", "fight", "elite", "well",
	"learn", "learn", "chest", "chest", "chest"]
var calibration := false  # transient: battle runs with no enemy (menu option 3)
var debug_mode := false   # transient: F1 in battle unlocks the debug toggles

func _ready() -> void:
	load_save()

func get_spell_level(spell_name: String) -> int:
	return int(spell_levels.get(spell_name, 1))

func upgrade_spell(spell_name: String) -> void:
	spell_levels[spell_name] = mini(get_spell_level(spell_name) + 1, 5)
	save()

func learn_spell(new_spell: String) -> void:
	known_spells.append(new_spell)
	save()

## Swap a known spell for a new one — the newcomer inherits its level.
func replace_spell(old_spell: String, new_spell: String) -> void:
	var idx := known_spells.find(old_spell)
	if idx < 0:
		return
	known_spells[idx] = new_spell
	spell_levels[new_spell] = get_spell_level(old_spell)
	save()

func add_heart() -> void:
	hearts += 1
	save()

func lose_heart() -> void:
	hearts -= 1
	save()

func set_life_mode(mode: String) -> void:
	life_mode = mode
	save()

const CHARACTERS := {
	"virtuosa": {
		"name": "Virtuosa",
		"desc": "Cannot sit still. Hits ↓ on the enemy's beat to slap the attack away; time it perfectly and they need a lie down.",
	},
	"domina": {
		"name": "Domina",
		"desc": "Solves problems with numbers. Attack +10 · damage taken -10 · healing +10. No tricks, just better at everything.",
	},
	"harmonia": {
		"name": "Harmonia",
		"desc": "Refuses all assistance, including the rhythm diamond. No bonuses, no training wheels, no sympathy. She says she can hear it fine.",
	},
}

func set_character(c: String) -> void:
	character = c
	save()

func get_record(id: String) -> Dictionary:
	return records.get(id, { "best_round": 0, "cleared": false, "true_clear": false, "best_score": 0 })

## Called when a run ends (death or clear) — keeps the best result per character.
func note_run_end(reached: int, cleared := false, true_clear := false) -> void:
	if character == "":
		return
	var r := get_record(character)
	r["best_round"] = maxi(int(r["best_round"]), reached)
	r["cleared"] = bool(r["cleared"]) or cleared
	r["true_clear"] = bool(r["true_clear"]) or true_clear
	records[character] = r
	save()

## Build one cycle's map: 6 rows of 1-4 random nodes + the boss row.
## Edges connect neighbouring rows; every node is guaranteed reachable.
func generate_map(cycle: int) -> void:
	map_rounds = []
	# In the opening cycle a Willpower Well may only show up once a real
	# fight has come before it — no free refill before the first monster.
	var fight_seen: bool = cycle > 0
	for i in 6:
		var row := []
		for j in randi_range(1, 4):
			var t: String = MAP_NODE_POOL.pick_random()
			if t == "well" and not fight_seen:
				t = "fight"
			row.append({ "type": t, "edges": [] })
		for node in row:
			if node["type"] == "fight" or node["type"] == "elite":
				fight_seen = true  # wells unlock from the next row on
				break
		map_rounds.append(row)
	map_rounds.append([{ "type": "boss", "edges": [] }])
	for i in map_rounds.size() - 1:
		var a: Array = map_rounds[i]
		var b: Array = map_rounds[i + 1]
		# Non-crossing sweep: each node owns a contiguous span of the next
		# row, and spans only ever move right (sharing an endpoint is fine).
		var k := 0
		for j in a.size():
			var edges: Array = [k]
			while k < b.size() - 1 and edges.size() < 3 and randf() < 0.35:
				k += 1
				edges.append(k)
			a[j]["edges"] = edges
			if j < a.size() - 1 and randf() < 0.5:
				k = mini(k + 1, b.size() - 1)
		# the last node sweeps up any unreached tail of the next row
		var last: Array = a[a.size() - 1]["edges"]
		for kk in range(int(last.max()) + 1, b.size()):
			last.append(kk)
	map_cycle = cycle
	map_pos = -1
	save()

func set_map_pos(p: int) -> void:
	map_pos = p
	save()

## Damage-driven willpower loss (saved). The 1-per-beat drain writes memory
## only — it's persisted at round transitions to avoid a disk write per beat.
func damage_willpower(amount: int) -> void:
	willpower = maxi(willpower - amount, 0)
	save()

func add_willpower(amount: int) -> void:
	willpower = mini(willpower + amount, WILLPOWER_MAX)
	save()

func next_round() -> void:
	round_num += 1
	save()

## New run: back to Flame + Cure at Lv1, full hearts, Round 1.
## Only bpm/offset (machine calibration) carry over.
func reset_run() -> void:
	hearts = 3
	round_num = 1
	life_mode = ""  # choose your lifeline again next run
	willpower = WILLPOWER_MAX
	character = ""
	items = []
	suit_crits = 0
	band_aid_used = false
	map_rounds = []
	map_cycle = -1
	map_pos = -1
	known_spells = RUN_START_SPELLS.duplicate()
	spell_levels = {}
	save()

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not write save file")
		return
	f.store_string(JSON.stringify({
		"save_version": SAVE_VERSION,
		"bpm": bpm,
		"input_offset": input_offset,
		"has_input_offset": has_input_offset,
		"music_offset": music_offset,
		"perfect_ms": perfect_ms,
		"items": items,
		"known_spells": known_spells,
		"spell_levels": spell_levels,
		"hearts": hearts,
		"round_num": round_num,
		"life_mode": life_mode,
		"willpower": willpower,
		"character": character,
		"records": records,
		"suit_crits": suit_crits,
		"band_aid_used": band_aid_used,
		"map_rounds": map_rounds,
		"map_cycle": map_cycle,
		"map_pos": map_pos,
	}, "\t"))

func set_bpm(v: float) -> void:
	bpm = v
	save()

func set_input_offset(v: float) -> void:
	input_offset = v
	has_input_offset = true
	save()

func set_music_offset(v: float) -> void:
	music_offset = maxf(v, 0.0)
	save()

## The crit window in seconds — what every judgment site actually compares.
func perfect_window() -> float:
	return perfect_ms / 1000.0

func set_perfect_ms(v: float) -> void:
	perfect_ms = clampf(v, 8.0, 60.0)
	save()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		# Calibration always carries over
		bpm = data.get("bpm", bpm)
		input_offset = data.get("input_offset", input_offset)
		has_input_offset = data.get("has_input_offset", false)
		music_offset = data.get("music_offset", 0.0)
		perfect_ms = data.get("perfect_ms", perfect_ms)
		items = data.get("items", [])
		records = data.get("records", {})  # career records outlive save versions
		# Run state only loads from saves of the current structure —
		# older saves fall back to a fresh run
		if int(data.get("save_version", 1)) >= SAVE_VERSION:
			known_spells = data.get("known_spells", known_spells)
			spell_levels = data.get("spell_levels", spell_levels)
			hearts = int(data.get("hearts", hearts))
			round_num = int(data.get("round_num", round_num))
			life_mode = data.get("life_mode", "")
			willpower = int(data.get("willpower", WILLPOWER_MAX))
			character = data.get("character", "")
			suit_crits = int(data.get("suit_crits", 0))
			band_aid_used = data.get("band_aid_used", false)
			map_rounds = data.get("map_rounds", [])
			for row in map_rounds:  # JSON floats -> ints
				for node in row:
					var ie: Array = []
					for e in node["edges"]:
						ie.append(int(e))
					node["edges"] = ie
			map_cycle = int(data.get("map_cycle", -1))
			map_pos = int(data.get("map_pos", -1))
