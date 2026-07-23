extends Node2D
## Endless-mode battle. Charge spells with arrow keys ON THE BEAT, release
## with SPACE. Win -> pick a spell to level up -> next round, enemy +10%
## hp/damage. At 0 HP hits cost Life Hearts; out of hearts = run over.
## Phases: "battle" -> "upgrade" (victory menu) / "over" (game over).

const CHARGE_TIMEOUT_BEATS := 2.0  # stop mid-charge for 2 beats -> spell dissipates
const ARROWS := { "L": "←", "R": "→", "U": "↑", "D": "↓" }
const LOG_LINES := 4
const NORMAL_TIER := 0.65  # accuracy below this sounds/acts "weak"
const BASE_ENEMY_HP := 1200
const ROUND_SCALING := 1.10
const HEAL_FLOOR := 0.5    # heal spells never fall below 50% of listed value

# Every spell has three cast sounds: weak / normal / crit, picked by accuracy.
const CAST_SFX := {
	"Flame": {
		"weak": preload("res://audio/flame_weak.wav"),
		"normal": preload("res://audio/flame_normal.wav"),
		"crit": preload("res://audio/flame_crit.wav"),
	},
	"Cure": {
		"weak": preload("res://audio/cure_weak.wav"),
		"normal": preload("res://audio/cure_normal.wav"),
		"crit": preload("res://audio/cure_crit.wav"),
	},
	"Wave": {
		"weak": preload("res://audio/wave_weak.wav"),
		"normal": preload("res://audio/wave_normal.wav"),
		"crit": preload("res://audio/wave_crit.wav"),
	},
	"Bolt": {
		"weak": preload("res://audio/bolt_weak.wav"),
		"normal": preload("res://audio/bolt_normal.wav"),
		"crit": preload("res://audio/bolt_crit.wav"),
	},
	"Needle": {
		"weak": preload("res://audio/needle_weak.wav"),
		"normal": preload("res://audio/needle_normal.wav"),
		"crit": preload("res://audio/needle_crit.wav"),
	},
	"Attack+": {
		"weak": preload("res://audio/atkup_weak.wav"),
		"normal": preload("res://audio/atkup_normal.wav"),
		"crit": preload("res://audio/atkup_crit.wav"),
	},
	"Defense+": {
		"weak": preload("res://audio/defup_weak.wav"),
		"normal": preload("res://audio/defup_normal.wav"),
		"crit": preload("res://audio/defup_crit.wav"),
	},
}

const SPELL_COLORS := {
	"fire": Color(1.0, 0.55, 0.15),
	"water": Color(0.35, 0.7, 1.0),
	"electric": Color(1.0, 0.95, 0.3),
	"normal": Color(0.85, 0.85, 0.9),
}

var player_max_hp := 100
var player_hp := 100
var enemy_hp := BASE_ENEMY_HP
var presses: Array = []  # the spell being charged: [{ "time": .., "sym": .. }]
var half_beat: float
var phase := "battle"    # "battle" | "upgrade" | "over"
var buffs := {}          # "atk"/"def" -> { "pct": float, "until": beat number }
var log_lines: PackedStringArray = []
# Input latency calibration: presses are judged at (song_time - input_offset).
var input_offset := 0.0
var recent_errors: Array[float] = []  # signed per-press error, for auto-calibration

@onready var conductor: AudioStreamPlayer = $Conductor
@onready var enemy: Node2D = $Enemy
@onready var ring: Node2D = $BeatRing
@onready var cast_log: Label = $UI/CastLog
@onready var info_label: Label = $UI/InfoLabel
@onready var player_bar: ProgressBar = $UI/PlayerHP
@onready var enemy_bar: ProgressBar = $UI/EnemyHP
@onready var hp_text: Label = $UI/PlayerHPText
@onready var buff_label: Label = $UI/BuffLabel
@onready var round_label: Label = $UI/RoundLabel
@onready var upgrade_label: Label = $UI/UpgradeLabel
@onready var debug_label: Label = $UI/DebugLabel
@onready var version_label: Label = $UI/VersionLabel
@onready var flash_rect: ColorRect = $UI/FlashRect
@onready var hint_sfx: AudioStreamPlayer = $HintSfx
@onready var cast_sfx: AudioStreamPlayer = $CastSfx
@onready var press_sfx: AudioStreamPlayer = $PressSfx

func _ready() -> void:
	# Restore what survives restarts: tempo, calibration, round scaling
	conductor.set_bpm(GameState.bpm)
	half_beat = conductor.seconds_per_beat / 2.0
	if GameState.has_input_offset:
		input_offset = GameState.input_offset
	else:
		input_offset = AudioServer.get_output_latency()
		GameState.set_input_offset(input_offset)
	var scale_factor := pow(ROUND_SCALING, GameState.round_num - 1)
	enemy_hp = int(roundf(BASE_ENEMY_HP * scale_factor))
	enemy.damage_mult = scale_factor
	round_label.text = "ROUND %d" % GameState.round_num
	conductor.beat.connect(_on_beat)
	conductor.eighth.connect(_on_eighth)
	enemy.attack_landed.connect(_on_enemy_attack)
	player_bar.max_value = player_max_hp
	enemy_bar.max_value = enemy_hp
	upgrade_label.visible = false
	_update_debug_label()
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_refresh_ui()
	conductor.start_beats()

func _unhandled_input(event: InputEvent) -> void:
	if phase == "over":
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			GameState.reset_run()
			get_tree().reload_current_scene()
		return
	if phase == "upgrade":
		_handle_upgrade_key(event)
		return
	# Debug: - / = adjust BPM; < / > nudge input offset; 0 auto-calibrates
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_MINUS:
				_set_bpm(conductor.bpm - 10.0)
				return
			KEY_EQUAL:
				_set_bpm(conductor.bpm + 10.0)
				return
			KEY_COMMA:  # <  judge earlier
				input_offset -= 0.005
				GameState.set_input_offset(input_offset)
				_update_debug_label()
				return
			KEY_PERIOD:  # >  judge later
				input_offset += 0.005
				GameState.set_input_offset(input_offset)
				_update_debug_label()
				return
			KEY_0:
				_auto_calibrate()
				return
	if conductor.song_time < 0.0:
		return  # count-in: listen to the beat, no casting yet
	var sym := ""
	if event.is_action_pressed("ui_left"):
		sym = "L"
	elif event.is_action_pressed("ui_right"):
		sym = "R"
	elif event.is_action_pressed("ui_up"):
		sym = "U"
	elif event.is_action_pressed("ui_down"):
		sym = "D"
	elif event.is_action_pressed("ui_accept"):  # SPACE
		sym = "S"
	if sym.is_empty():
		return
	var t: float = conductor.song_time - input_offset
	presses.append({ "time": t, "sym": sym })
	# Remember this press's signed error (late = positive) for auto-calibration
	var err := fposmod(t, half_beat)
	if err > half_beat / 2.0:
		err -= half_beat
	recent_errors.append(err)
	if recent_errors.size() > 16:
		recent_errors.pop_front()
	_flash_press_feedback(t, sym)
	if sym == "S":
		_resolve_cast()
	else:
		# Short blip per charge key, pitched slightly per direction
		press_sfx.pitch_scale = { "L": 1.0, "R": 1.06, "U": 1.12, "D": 0.94 }[sym]
		press_sfx.play()
	_refresh_ui()

## Instant feedback on every press: gold = Perfect, blue = close, grey = off.
func _flash_press_feedback(t: float, sym: String) -> void:
	var off := fposmod(t, half_beat)
	off = minf(off, half_beat - off)
	var color: Color
	if off <= half_beat * SpellBook.PERFECT_FRACTION:
		color = Color(1.0, 0.85, 0.2)
	elif off <= half_beat * SpellBook.CLOSE_FRACTION:
		color = Color(0.4, 0.65, 1.0)
	else:
		color = Color(0.5, 0.5, 0.55)
	ring.flash(color)
	ring.stamp(ARROWS.get(sym, "•"), color)

## SPACE was pressed: try to turn the recorded sequence into a spell.
func _resolve_cast() -> void:
	var res: Dictionary = SpellBook.resolve(presses, half_beat)
	presses.clear()
	if not res["ok"]:
		_log("Fizzle… (%s)" % res["reason"])
		return
	var spell: Dictionary = res["spell"]
	var q: Dictionary = SpellBook.quality(res["offsets"], half_beat)
	var lv := GameState.get_spell_level(spell["name"])
	var tier := "crit" if q["crit"] else ("normal" if q["avg"] >= NORMAL_TIER else "weak")
	cast_sfx.stream = CAST_SFX[spell["name"]][tier]
	cast_sfx.play()
	var crit_tag: String = "  CRIT!" if q["crit"] else ""
	var stray_tag: String = "  (+%d stray)" % res["stray"] if res["stray"] > 0 else ""
	match spell["type"]:
		"heal":
			# Heals: floored at 50% of listed value; a perfect cast = the full amount
			var base_h: int = spell["damage"][lv - 1]
			var heal := base_h if q["crit"] else int(roundf(base_h * maxf(q["avg"], HEAL_FLOOR)))
			player_hp = mini(player_hp + heal, player_max_hp)
			_log("Cure +%d%s%s" % [heal, "  PERFECT" if q["crit"] else "", stray_tag])
			_float_number("+%d" % heal, false, Vector2(500, 555), Color(0.45, 0.9, 0.55))
		"buff_atk", "buff_def":
			# Strength = level max * tier (weak 50% / normal 75% / crit 100%)
			var tier_factor := 1.0 if q["crit"] else (0.75 if q["avg"] >= NORMAL_TIER else 0.5)
			var pct: float = spell["buff_pct"][lv - 1] * tier_factor
			var beats: int = spell["buff_beats"][lv - 1]
			var kind := "atk" if spell["type"] == "buff_atk" else "def"
			buffs[kind] = { "pct": pct, "until": conductor.last_beat + beats }
			_log("%s %d%% for %d beats%s%s" % [spell["name"], roundf(pct * 100.0), beats, crit_tag, stray_tag])
		_:
			# Damage spells (fire / water / electric / normal)
			var base: int = spell["damage"][lv - 1]
			var amount: int = base * 2 if q["crit"] else int(roundf(base * q["avg"]))
			amount = int(roundf(amount * (1.0 + _buff_pct("atk"))))
			enemy_hp = maxi(enemy_hp - amount, 0)
			enemy.hit()
			_log("%s!%s%s" % [spell["name"], crit_tag, stray_tag])
			var color: Color = SPELL_COLORS.get(spell["type"], Color.WHITE)
			_float_number("-%d" % amount, q["crit"], enemy.position + Vector2(-30, -130), color)
			if spell.has("self_damage"):
				# Needle's price: ignores Defense+, can knock you to 0 HP,
				# but never costs a Life Heart
				_damage_player(spell["self_damage"], true, false)
				_log("Needle recoil -%d" % spell["self_damage"])
			if enemy_hp <= 0:
				_refresh_ui()
				_enter_upgrade()
				return
	_refresh_ui()

func _buff_pct(kind: String) -> float:
	if buffs.has(kind) and conductor.last_beat < buffs[kind]["until"]:
		return buffs[kind]["pct"]
	return 0.0

## Runs once per beat — enemy bobs to the music, buffs tick, stale charges fade.
func _on_beat(n: int) -> void:
	if phase != "battle":
		return
	enemy.bob()
	if n < 0:
		info_label.text = "Get ready…  %d" % -n  # count-in: 8, 7, 6…
		return
	if n == 0:
		_refresh_ui()  # count-in over, restore the normal hint
	# Buffs expire on their beat
	for kind in buffs.keys():
		if n >= buffs[kind]["until"]:
			_log(("Attack+" if kind == "atk" else "Defense+") + " fades")
			buffs.erase(kind)
			_refresh_ui()
	# On death's door: replay Cure's rhythm every 2 beats, starting on a beat
	# so the demo is honest — press along with it and you're cured
	if player_hp <= 0 and posmod(n, 2) == 0:
		_play_cure_hint()
	if not presses.is_empty() and conductor.song_time - presses.back()["time"] > CHARGE_TIMEOUT_BEATS * conductor.seconds_per_beat:
		presses.clear()
		_log("the spell dissipates…")
		_refresh_ui()

## Twice per beat — feeds the enemy's scripted attack pattern.
func _on_eighth(n: int) -> void:
	if phase == "battle" and n >= 0:  # pattern starts after the count-in
		enemy.on_eighth(n)

func _on_enemy_attack(damage: int) -> void:
	_float_number("-%d" % damage, false, Vector2(560, 550), Color(0.95, 0.35, 0.35))
	_damage_player(damage, false, true)
	_refresh_ui()

## All player damage funnels through here: Defense+ reduction, death
## protection, and Life Hearts. can_cost_heart=false (Needle recoil) can
## knock you to 0 HP but never takes a heart.
func _damage_player(damage: int, ignore_defense: bool, can_cost_heart: bool) -> void:
	if not ignore_defense:
		damage = int(roundf(damage * (1.0 - _buff_pct("def"))))
	if damage <= 0:
		return
	if player_hp <= 0:
		if not can_cost_heart:
			return
		# Hit while on death's door: a Life Heart burns, HP restored to full
		GameState.lose_heart()
		_flash_screen_red()
		if GameState.hearts <= 0:
			_refresh_ui()
			_game_over()
		else:
			player_hp = player_max_hp
			_log("-1 LIFE HEART  (%d left) — HP restored" % GameState.hearts)
		return
	if damage >= player_hp:
		# Death protection: a lethal hit leaves you at 0 HP —
		# Cure now, or hits start costing hearts
		player_hp = 0
		_flash_screen_red()
		_log("DEATH PROTECTION — cast Cure!")
	else:
		player_hp -= damage

## Victory: pause the fight, offer one spell level-up (keys 1-7).
func _enter_upgrade() -> void:
	phase = "upgrade"
	conductor.stop_beats()
	var lines := ["VICTORY!  Choose a spell to level up:", ""]
	var i := 1
	for spell in SpellBook.SPELLS:
		if not GameState.known_spells.has(spell["name"]):
			continue
		var lv := GameState.get_spell_level(spell["name"])
		if lv >= 5:
			lines.append("%d.  %s   Lv%d  (MAX)" % [i, spell["name"], lv])
		else:
			lines.append("%d.  %s   Lv%d → %d" % [i, spell["name"], lv, lv + 1])
		i += 1
	upgrade_label.text = "\n".join(lines)
	upgrade_label.visible = true
	info_label.text = ""

func _handle_upgrade_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var idx: int = event.keycode - KEY_1
	var known: Array = []
	for spell in SpellBook.SPELLS:
		if GameState.known_spells.has(spell["name"]):
			known.append(spell["name"])
	if idx < 0 or idx >= known.size():
		return
	if GameState.get_spell_level(known[idx]) >= 5:
		return  # maxed — pick another
	GameState.advance_round(known[idx])
	get_tree().reload_current_scene()

func _game_over() -> void:
	phase = "over"
	conductor.stop_beats()
	info_label.text = "GAME OVER — out of Life Hearts.  R = new run (Round 1, hearts refilled)"

func _flash_screen_red() -> void:
	flash_rect.color = Color(0.9, 0.1, 0.1, 0.5)
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.7)

## Cure's rhythm: three ticks an eighth apart, the last one higher where
## SPACE belongs. The screen pulses red IN TIME with each tick.
func _play_cure_hint() -> void:
	_hint_pulse(1.8)
	get_tree().create_timer(half_beat, false).timeout.connect(_hint_pulse.bind(1.8))
	get_tree().create_timer(half_beat * 2.0, false).timeout.connect(_hint_pulse.bind(2.4))

func _hint_pulse(pitch: float) -> void:
	if phase != "battle" or player_hp > 0:
		return  # cured (or the fight ended) between ticks — stop nagging
	hint_sfx.pitch_scale = pitch
	hint_sfx.play()
	flash_rect.color = Color(0.9, 0.1, 0.1, 0.22)
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.25)

## Debug: live BPM change. Half-charged spells are cleared because their
## recorded timings belong to the old tempo.
func _set_bpm(new_bpm: float) -> void:
	conductor.set_bpm(new_bpm)
	GameState.set_bpm(conductor.bpm)
	half_beat = conductor.seconds_per_beat / 2.0
	presses.clear()
	recent_errors.clear()
	_update_debug_label()

## Press 0 after playing a while: your average error becomes the new offset.
func _auto_calibrate() -> void:
	if recent_errors.size() < 4:
		_log("auto-calibrate: tap along a bit first")
		return
	var mean := 0.0
	for e in recent_errors:
		mean += e
	mean /= recent_errors.size()
	input_offset += mean
	GameState.set_input_offset(input_offset)
	recent_errors.clear()
	_log("input offset -> %.0f ms" % (input_offset * 1000.0))
	_update_debug_label()

func _update_debug_label() -> void:
	debug_label.text = "BPM %.0f   [-/=]\noffset %.0f ms   [</> · 0 auto]" % [
		conductor.bpm, input_offset * 1000.0]

## Floating combat number (damage on the enemy, heal/damage near the player bar).
func _float_number(text: String, crit: bool, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text + ("  CRIT!" if crit else "")
	lbl.add_theme_font_size_override("font_size", 34 if crit else 26)
	lbl.modulate = color
	lbl.position = pos
	lbl.z_index = 10
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", pos.y - 55.0, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

## Bottom-left running log of casts and fizzles.
func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > LOG_LINES:
		log_lines.remove_at(0)
	cast_log.text = "\n".join(log_lines)

func _refresh_ui() -> void:
	player_bar.value = player_hp
	enemy_bar.value = enemy_hp
	hp_text.text = "HP  %d / %d      %s" % [player_hp, player_max_hp, "♥ ".repeat(GameState.hearts).strip_edges()]
	var parts := PackedStringArray()
	if _buff_pct("atk") > 0.0:
		parts.append("ATK +%d%%  (%d)" % [roundf(_buff_pct("atk") * 100.0), buffs["atk"]["until"] - conductor.last_beat])
	if _buff_pct("def") > 0.0:
		parts.append("DEF -%d%%  (%d)" % [roundf(_buff_pct("def") * 100.0), buffs["def"]["until"] - conductor.last_beat])
	buff_label.text = "    ".join(parts)
	if phase != "battle":
		return
	if presses.is_empty():
		info_label.text = "Charge with ← on the beat, release with SPACE"
	else:
		var seq := ""
		for p in presses:
			seq += ARROWS.get(p["sym"], "?") + " "
		info_label.text = "Charging:  " + seq
