extends Node
## Autoload singleton: everything that must survive a restart (R) and a full
## quit. Lives outside the battle scene, so reloading the scene doesn't touch
## it; on top of that every change is saved as JSON to user://save.json.
## (user:// on Windows = %APPDATA%\Godot\app_userdata\First Game\)

const SAVE_PATH := "user://save.json"

var bpm := 100.0
var input_offset := 0.0
var has_input_offset := false  # false -> seed from the audio driver's estimate
var items: Array = []          # inventory (future)
var known_spells: Array = []
var spell_levels := {}
var hearts := 3     # Life Hearts: lost when hit at 0 HP; 0 hearts = game over
var round_num := 1  # endless mode round; enemy scales +10% hp/dmg per round

func _ready() -> void:
	load_save()
	# Migration: until a real learning system exists, every spell in the book
	# is automatically known (also seeds fresh saves).
	for spell in SpellBook.SPELLS:
		if not known_spells.has(spell["name"]):
			known_spells.append(spell["name"])
		if not spell_levels.has(spell["name"]):
			spell_levels[spell["name"]] = 1

func get_spell_level(spell_name: String) -> int:
	return int(spell_levels.get(spell_name, 1))

func lose_heart() -> void:
	hearts -= 1
	save()

## Player picked an upgrade after a win: level the spell, harder next round.
func advance_round(upgraded_spell: String) -> void:
	spell_levels[upgraded_spell] = mini(int(spell_levels[upgraded_spell]) + 1, 5)
	round_num += 1
	save()

## Out of hearts: the run ends. Spell levels persist (permanent progression).
func reset_run() -> void:
	hearts = 3
	round_num = 1
	save()

func set_bpm(v: float) -> void:
	bpm = v
	save()

func set_input_offset(v: float) -> void:
	input_offset = v
	has_input_offset = true
	save()

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not write save file")
		return
	f.store_string(JSON.stringify({
		"bpm": bpm,
		"input_offset": input_offset,
		"has_input_offset": has_input_offset,
		"items": items,
		"known_spells": known_spells,
		"spell_levels": spell_levels,
		"hearts": hearts,
		"round_num": round_num,
	}, "\t"))

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		bpm = data.get("bpm", bpm)
		input_offset = data.get("input_offset", input_offset)
		has_input_offset = data.get("has_input_offset", false)
		items = data.get("items", [])
		known_spells = data.get("known_spells", known_spells)
		spell_levels = data.get("spell_levels", spell_levels)
		hearts = int(data.get("hearts", hearts))
		round_num = int(data.get("round_num", round_num))
