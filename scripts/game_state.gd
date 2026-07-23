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
var perfect_fraction := 0.16   # crit window as a fraction of an eighth slot (tunable in calibration)
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
var calibration := false  # transient: battle runs with no enemy (menu option 3)

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
		"perfect_fraction": perfect_fraction,
		"items": items,
		"known_spells": known_spells,
		"spell_levels": spell_levels,
		"hearts": hearts,
		"round_num": round_num,
		"life_mode": life_mode,
		"willpower": willpower,
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

func set_perfect_fraction(v: float) -> void:
	perfect_fraction = clampf(v, 0.05, 0.45)
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
		perfect_fraction = data.get("perfect_fraction", perfect_fraction)
		items = data.get("items", [])
		# Run state only loads from saves of the current structure —
		# older saves fall back to a fresh run
		if int(data.get("save_version", 1)) >= SAVE_VERSION:
			known_spells = data.get("known_spells", known_spells)
			spell_levels = data.get("spell_levels", spell_levels)
			hearts = int(data.get("hearts", hearts))
			round_num = int(data.get("round_num", round_num))
			life_mode = data.get("life_mode", "")
			willpower = int(data.get("willpower", WILLPOWER_MAX))
