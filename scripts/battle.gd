extends Node2D
## The battle scene: rhythm combat plus the run's map & reward flow.
## One control scheme everywhere: arrows move, SPACE confirms (SelectMenu);
## the map screen is cursor-driven with hover tooltips.
## Phases: "battle" | "won" (death animation interlude) | "choice" (map) |
## "prelude_map"/"select"/"character" (run setup) |
## "chest"/"upgrade"/"learn"/"replace" | "over".

const CHARGE_LIFETIME_BEATS := 4.0  # buffer auto-fizzles 4 beats after the first press
const ARROWS := { "L": "←", "R": "→", "U": "↑", "D": "↓" }
const LOG_LINES := 4
const NORMAL_TIER := 0.65  # accuracy below this sounds/acts "weak"
const NONCRIT_DAMAGE_CAP := 0.6  # no crit -> at most 60% of a spell's max damage
const ROUND_SCALING := 0.25  # each round adds a flat +25% of base (linear, not compounding)
const CYCLE_LEN := 7         # rounds per cycle; the last round of each cycle is a BOSS
const BOSS_HP_MULT := 2.0
const MUSIC_BPM := 118.0  # fallback tempo when no track is available
const HEAL_FLOOR := 0.5   # heal spells never fall below 50% of listed value
const TRAINING_HEAL_BEATS := 4  # the dummy refills this often — practice never stalls
const TRAINING_COUNT_IN := 4    # short count-in: you came here to repeat a pattern

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

const PARRY_SFX := {
	"swing": preload("res://audio/parry_swing.wav"),
	"weak": preload("res://audio/parry_weak.wav"),
	"normal": preload("res://audio/parry_normal.wav"),
	"crit": preload("res://audio/parry_crit.wav"),
}

const SPELL_COLORS := {
	"fire": Color(1.0, 0.55, 0.15),
	"water": Color(0.35, 0.7, 1.0),
	"electric": Color(1.0, 0.95, 0.3),
	"normal": Color(0.85, 0.85, 0.9),
}

var player_max_hp := 100
var player_hp := 100
var enemy_hp := 1
var presses: Array = []  # the spell being charged: [{ "time": .., "sym": .. }]
var half_beat: float
var phase := "battle"
var current_node := ""         # the map node being played ("fight"/"elite"/"boss"/…)
var current_track: Dictionary = {}  # this battle's music (from MusicLibrary)
var pending_upgrades := 0      # upgrade menus owed (battle win, grimoires…)
var last_parry := -999.0       # judged time of the last parry attempt (Virtuosa)
var choice_options: Array = [] # selectable node indices on the map screen
var map_cursor := 0            # cursor within choice_options
var menu_payload: Array = []   # per-option payload behind the active SelectMenu
var learn_choices: Array = []  # spell names offered on the learn screen
var pending_learn := ""        # picked spell waiting for a replacement slot
var buffs := {}          # "atk"/"def" -> { "pct": float, "until": beat number }
var pending_attacks: Array = []  # enemy hits waiting for the beat's window to close
var flash_tween: Tween           # single owner of the red-flash animation
var show_timing := false         # calibration debug: show each press's signed error in ms
var metronome_auto := false      # the metronome is on as a failsafe, not by choice
# Training is a no-stakes practice interlude that reuses the whole combat
# machinery — same phase, same casting path — so patterns feel identical to
# the real thing. Only death, attacks and the exit differ.
var training := false
var training_next := Callable()  # where the run continues once practice ends
var dialogue_next := Callable()  # where a page-turned conversation leads
var demo_pattern := ""   # a spell's rhythm, ticking under a training session
var demo_period := 0     # eighth-slots per call-and-response cycle
var during_lines := {}   # this fight's drawn set of mid-battle taunts
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
@onready var debug_label: Label = $UI/DebugLabel
@onready var version_label: Label = $UI/VersionLabel
@onready var flash_rect: ColorRect = $UI/FlashRect
@onready var items_label: Label = $UI/ItemsLabel
@onready var map_view: Node2D = $UI/MapView
@onready var will_clock: Node2D = $UI/WillClock
@onready var select_menu: CanvasLayer = $SelectMenu
@onready var dialogue: Node2D = $UI/DialogueBox
@onready var fader: ColorRect = $FaderLayer/Rect
@onready var hint_sfx: AudioStreamPlayer = $HintSfx
@onready var cast_sfx: AudioStreamPlayer = $CastSfx
@onready var press_sfx: AudioStreamPlayer = $PressSfx
@onready var parry_sfx: AudioStreamPlayer = $ParrySfx
@onready var spell_fx: Node2D = $SpellFx
@onready var explosion_sfx: AudioStreamPlayer = $ExplosionSfx
@onready var victory_sfx: AudioStreamPlayer = $VictorySfx
@onready var bgm: AudioStreamPlayer = $BGM

func _ready() -> void:
	select_menu.chosen.connect(_on_menu_chosen)
	dialogue.finished.connect(_on_dialogue_finished)
	explosion_sfx.stream = preload("res://audio/explosion.wav")
	victory_sfx.stream = preload("res://audio/victory.wav")
	# Debug readout & toggles exist ONLY in calibration mode
	debug_label.visible = GameState.calibration
	fader.color.a = 1.0
	create_tween().tween_property(fader, "color:a", 0.0, 0.4)
	# Baseline clock; each battle re-tunes it to its randomly drawn track
	conductor.set_bpm(MUSIC_BPM)
	half_beat = conductor.seconds_per_beat / 2.0
	if GameState.has_input_offset:
		input_offset = GameState.input_offset
	else:
		input_offset = AudioServer.get_output_latency()
		GameState.set_input_offset(input_offset)
	conductor.beat.connect(_on_beat)
	conductor.eighth.connect(_on_eighth)
	enemy.attack_landed.connect(_on_enemy_attack)
	_recalc_max_hp()
	player_hp = player_max_hp
	enemy_bar.max_value = enemy_hp
	_update_debug_label()
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_refresh_ui()
	if GameState.calibration:
		# Calibration mode: no enemy, no stakes — just you and the beat.
		# Every debug aid starts ON here (metronome, ring, cursor ball).
		enemy.visible = false
		enemy_bar.visible = false
		conductor.metronome = true
		ring.visible = true
		ring.show_cursor = true
		show_timing = true
		conductor.count_in_beats = 4  # short count-in — get practicing quickly
		round_label.text = "CALIBRATION MODE   (ESC to leave · N next track)"
		if not MusicLibrary.tracks.is_empty():
			current_track = MusicLibrary.tracks[0]
		_apply_track()
		conductor.start_beats()
		_start_music()
	elif GameState.life_mode == "":
		_enter_mode_select()  # fallback: shouldn't happen via the menu flow
	else:
		_next_round_flow()  # a fresh run starts at the Prelude (character pick)

## ── Input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if phase == "choice":
		_map_input(event)
		return
	if phase == "dialogue":
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			dialogue.advance()
		return
	if phase == "prelude_map":
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			map_view.hover_ring = false
			# Warm up on the dummy before the run's first real decision — the
			# characters differ by how they handle the rhythm, so you should
			# have felt it once before being asked to choose.
			# The phase changes NOW, not when the fade lands: input is live
			# for those 0.25s and a second SPACE would queue a second bout.
			phase = "interlude"
			_fade_to(func(): _enter_training(
				"WARM  UP  —  the dummy has notes",
				func(): _fade_to(_enter_character_select)))
		return
	if phase != "battle":
		return  # menus (SelectMenu) and interludes own the input now
	# F1 unlocks the debug toggles mid-game
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		GameState.debug_mode = not GameState.debug_mode
		debug_label.visible = GameState.calibration or GameState.debug_mode
		_update_debug_label()
		_log("debug mode %s" % ("ON" if GameState.debug_mode else "off"))
		return
	# Debug tuning: calibration mode, or F1-enabled debug mode. Held keys repeat.
	if (GameState.calibration or GameState.debug_mode) and event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F4:  # debug: delete the enemy
				if not event.echo and not GameState.calibration:
					enemy_hp = 0
					_refresh_ui()
					_win_battle()
				return
			KEY_MINUS:
				_set_bpm(conductor.bpm - 1.0)
				return
			KEY_EQUAL:
				_set_bpm(conductor.bpm + 1.0)
				return
			KEY_COMMA:  # <  judge earlier
				input_offset -= 0.001
				GameState.set_input_offset(input_offset)
				_update_debug_label()
				return
			KEY_PERIOD:  # >  judge later
				input_offset += 0.001
				GameState.set_input_offset(input_offset)
				_update_debug_label()
				return
			KEY_BRACKETLEFT:   # [  music earlier relative to the beats
				_adjust_music_offset(-0.001)
				return
			KEY_BRACKETRIGHT:  # ]  music later relative to the beats
				_adjust_music_offset(0.001)
				return
			KEY_0:
				if not event.echo:
					_auto_calibrate()
				return
			KEY_M:
				if not event.echo:
					conductor.metronome = not conductor.metronome
					metronome_auto = false  # from here on it's the player's call
					_update_debug_label()
				return
			KEY_D:
				if not event.echo:
					ring.visible = not ring.visible
					_update_debug_label()
				return
			KEY_B:
				if not event.echo:
					ring.show_cursor = not ring.show_cursor
					_update_debug_label()
				return
			KEY_T:
				if not event.echo:
					show_timing = not show_timing
					_update_debug_label()
				return
			KEY_N:  # next track: restart the count-in on it
				if not event.echo and not MusicLibrary.tracks.is_empty():
					var i: int = MusicLibrary.tracks.find(current_track)
					current_track = MusicLibrary.tracks[(i + 1) % MusicLibrary.tracks.size()]
					_apply_track()
					conductor.start_beats()
					_start_music()
				return
			KEY_SEMICOLON:  # ;  narrower crit window
				GameState.set_perfect_ms(GameState.perfect_ms - 1.0)
				_update_debug_label()
				return
			KEY_APOSTROPHE:  # '  wider crit window
				GameState.set_perfect_ms(GameState.perfect_ms + 1.0)
				_update_debug_label()
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
	# Flip Ring: ↓ is the dedicated PARRY key — it never charges, it wipes
	# any half-charged spell, and it alone has a 1/4-beat cooldown.
	if sym == "D" and GameState.character == "virtuosa":
		if t - last_parry >= conductor.seconds_per_beat * 0.25:
			last_parry = t
			presses.clear()
			_parry_sound("swing")  # the swing; an impact sound follows if it connects
			ring.stamp("↓", Color(0.85, 0.85, 0.9))
			_refresh_ui()
		return
	presses.append({ "time": t, "sym": sym })
	# Remember this press's signed error (late = positive) for auto-calibration
	var err := fposmod(t, half_beat)
	if err > half_beat / 2.0:
		err -= half_beat
	recent_errors.append(err)
	if recent_errors.size() > 16:
		recent_errors.pop_front()
	if show_timing:
		# Signed press error: + = late, - = early
		var ms := err * 1000.0
		var tcolor := Color(1.0, 0.85, 0.2) if absf(err) <= GameState.perfect_window() else Color(0.6, 0.7, 0.85)
		_float_number("%+.0f ms" % ms, false, ring.position + Vector2(105, -40), tcolor)
	_flash_press_feedback(t, sym)
	if sym == "S":
		_resolve_cast()
	else:
		# Short blip per charge key, pitched slightly per direction
		press_sfx.pitch_scale = { "L": 1.0, "R": 1.06, "U": 1.12, "D": 0.94 }[sym]
		press_sfx.play()
	_refresh_ui()

## Map screen: arrows walk the highlighted options, SPACE commits.
func _map_input(event: InputEvent) -> void:
	if choice_options.is_empty():
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		map_cursor = (map_cursor + 1) % choice_options.size()
		map_view.hover = choice_options[map_cursor]
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		map_cursor = (map_cursor - 1 + choice_options.size()) % choice_options.size()
		map_view.hover = choice_options[map_cursor]
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		var target: int = choice_options[map_cursor]
		GameState.set_map_pos(target)
		var row := (GameState.round_num - 1) % CYCLE_LEN
		var node_type: String = GameState.map_rounds[row][target]["type"]
		map_view.visible = false
		_fade_to(func(): _enter_node(node_type))

## Instant feedback on every press: gold = Perfect, blue = close, grey = off.
func _flash_press_feedback(t: float, sym: String) -> void:
	var off := fposmod(t, half_beat)
	off = minf(off, half_beat - off)
	var color: Color
	if off <= GameState.perfect_window():
		color = Color(1.0, 0.85, 0.2)
	elif off <= SpellBook.CLOSE_MS / 1000.0:
		color = Color(0.4, 0.65, 1.0)
	else:
		color = Color(0.5, 0.5, 0.55)
	ring.flash(color)
	ring.stamp(ARROWS.get(sym, "•"), color)

## ── Casting ──────────────────────────────────────────────────────────────

## SPACE was pressed: try to turn the recorded sequence into a spell.
func _resolve_cast() -> void:
	var known: Array = GameState.known_spells
	if GameState.calibration:
		known = []  # calibration: the whole book is castable
		for spell in SpellBook.SPELLS:
			known.append(spell["name"])
	var res: Dictionary = SpellBook.resolve(presses, half_beat, known)
	presses.clear()
	if not res["ok"]:
		ring.fizzle_mark()
		_log("Fizzle… (%s)" % res["reason"])
		return
	var spell: Dictionary = res["spell"]
	# X-Matter widens the crit window
	var pw := GameState.perfect_window() * (1.5 if ItemDB.has(GameState.items, "x_matter") else 1.0)
	var q: Dictionary = SpellBook.quality(res["offsets"], half_beat, pw)
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
			heal += ItemDB.sum_field(GameState.items, "heal_flat")
			if GameState.character == "domina":
				heal += 10
			var restored := mini(player_hp + heal, player_max_hp) - player_hp
			player_hp += restored
			_log("Cure +%d%s%s" % [restored, "  PERFECT" if q["crit"] else "", stray_tag])
			_float_number("+%d" % restored, false, Vector2(500, 555), Color(0.45, 0.9, 0.55))
			spell_fx.play(Vector2(576, 505), Color(0.45, 0.95, 0.6), tier, spell["name"])
			# Magical Crystal: restored health strikes the enemy at 200%
			if ItemDB.has(GameState.items, "magical_crystal") and restored > 0:
				var mc := restored * 2
				enemy_hp = maxi(enemy_hp - mc, 0)
				enemy.hit()
				_float_number("-%d" % mc, false, enemy.position + Vector2(-30, -130), Color(0.8, 0.6, 1.0))
				if enemy_hp <= 0 and not _target_is_a_dummy():
					_win_battle()
					return
		"buff_atk", "buff_def":
			# Strength = level max * tier (weak 50% / normal 75% / crit 100%)
			var tier_factor := 1.0 if q["crit"] else (0.75 if q["avg"] >= NORMAL_TIER else 0.5)
			var pct: float = spell["buff_pct"][lv - 1] * tier_factor
			var beats: int = spell["buff_beats"][lv - 1]
			var kind := "atk" if spell["type"] == "buff_atk" else "def"
			buffs[kind] = { "pct": pct, "until": conductor.last_beat + beats }
			_log("%s %d%% for %d beats%s%s" % [spell["name"], roundf(pct * 100.0), beats, crit_tag, stray_tag])
			spell_fx.play(Vector2(576, 505),
				Color(1.0, 0.6, 0.35) if kind == "atk" else Color(0.5, 0.7, 1.0),
				tier, spell["name"])
		_:
			# Damage spells: only a CRIT reaches max damage. Anything less is
			# capped — 60% for most spells, 30% for all-or-nothing Bolt.
			var base: int = spell["damage"][lv - 1]
			var amount: int
			if q["crit"]:
				amount = base
				if ItemDB.has(GameState.items, "thunderous_gem"):
					amount *= 3
				if ItemDB.has(GameState.items, "suit"):
					GameState.suit_crits += 1
					GameState.save()
			else:
				var cap: float = spell.get("noncrit_cap", NONCRIT_DAMAGE_CAP)
				amount = int(roundf(base * q["avg"] * cap))
			# Flat item bonuses
			amount += ItemDB.sum_field(GameState.items, "atk_flat")
			amount += ItemDB.type_flat(GameState.items, spell["type"])
			if GameState.character == "domina":
				amount += 10
			# Multiplicative item effects
			var mult := 1.0
			if ItemDB.has(GameState.items, "power_glove") and player_max_hp > 0 and player_hp >= player_max_hp:
				mult *= 1.2
			if ItemDB.has(GameState.items, "berserker_headgear") and player_hp <= 0:
				mult *= 1.5
			if ItemDB.has(GameState.items, "thunderous_gem"):
				mult *= 0.5
			if ItemDB.has(GameState.items, "x_matter"):
				mult *= 0.8
			if ItemDB.has(GameState.items, "suit"):
				mult *= minf(0.2 + 0.05 * GameState.suit_crits, 3.0)
			amount = int(roundf(amount * mult * (1.0 + _buff_pct("atk"))))
			if enemy.is_stunned():
				amount = int(roundf(amount * 1.5))  # stunned enemies take +50%
			enemy_hp = maxi(enemy_hp - amount, 0)
			enemy.hit()
			_log("%s!%s%s" % [spell["name"], crit_tag, stray_tag])
			var color: Color = SPELL_COLORS.get(spell["type"], Color.WHITE)
			spell_fx.play(enemy.position, color, tier, spell["name"])
			_float_number("-%d" % amount, q["crit"], enemy.position + Vector2(-30, -130), color)
			if spell.has("self_damage"):
				# Needle's price: ignores Defense+, can knock you to 0 HP,
				# but never costs a Life Heart
				_damage_player(spell["self_damage"], true, false)
				_log("Needle recoil -%d" % spell["self_damage"])
			if enemy_hp <= 0:
				if _target_is_a_dummy():
					enemy_hp = int(enemy_bar.max_value)  # target dummy respawns
				else:
					_win_battle()
					return
	_refresh_ui()

## ── Enemy speech ─────────────────────────────────────────────────────────

## Fire this fight's line for beat `n`, if it has one.
func _speak_scheduled(n: int) -> void:
	if not during_lines.has(n):
		return
	var line: Dictionary = (during_lines[n] as Dictionary).duplicate()
	line["speaker"] = line.get("speaker", enemy.type["display"])
	_speak([line])

## Enemies carry several versions of everything they say; one set is drawn per
## encounter, so meeting the same monster twice isn't the same scene twice.
func _draw_during() -> void:
	var variants: Array = enemy.type.get("dialogue", {}).get("during", [])
	during_lines = variants.pick_random() if not variants.is_empty() else {}

## A conversation ended. A page-turned one hands control to whatever queued
## it; an ambient one just gives the hint strip back.
func _on_dialogue_finished() -> void:
	var next := dialogue_next
	dialogue_next = Callable()
	if next.is_valid():
		next.call()
	else:
		_refresh_ui()

## Ambient chatter over live play: it never takes input and never touches
## a charge in progress — the player is mid-bar and owes it nothing.
func _speak(lines: Array) -> void:
	if lines.is_empty():
		return
	dialogue.play(lines, false)

## One of the enemy's intro conversations, stamped with its speaker.
func _intro_lines() -> Array:
	var variants: Array = enemy.type.get("dialogue", {}).get("intro", [])
	if variants.is_empty():
		return []
	var out: Array = []
	for line in variants.pick_random():
		var l: Dictionary = (line as Dictionary).duplicate()
		l["speaker"] = l.get("speaker", enemy.type["display"])
		out.append(l)
	return out

## Calibration and training both fight an immortal target: reaching 0 refills
## it instead of ending the bout.
func _target_is_a_dummy() -> bool:
	return GameState.calibration or training

func _buff_pct(kind: String) -> float:
	if buffs.has(kind) and conductor.last_beat < buffs[kind]["until"]:
		return buffs[kind]["pct"]
	return 0.0

## ── Beat & enemy flow ────────────────────────────────────────────────────

## Runs once per beat — enemy bobs to the music, buffs tick, stale charges fade.
func _on_beat(n: int) -> void:
	if phase != "battle":
		return
	_sync_metronome()
	if not GameState.calibration:
		enemy.bob()
	# Speech advances on beats, during the count-in as much as mid-fight
	if dialogue.is_active():
		dialogue.on_beat()
	elif n >= 0:
		_speak_scheduled(n)
	if n < 0:
		# A talking enemy owns the count-in; the countdown would just be noise
		info_label.text = "Get ready…  %d" % -n  # count-in: 16, 15, 14…
		return
	if n == 0:
		_refresh_ui()  # count-in over, restore the normal hint
	if training and posmod(n, TRAINING_HEAL_BEATS) == 0:
		_training_refill()
	# Willpower mode: the clock is always ticking (Dimensional Ring stops it)
	# — but never in practice, which has no stakes to spend.
	if GameState.life_mode == "willpower" and not GameState.calibration and not training:
		if not ItemDB.has(GameState.items, "dimensional_ring"):
			GameState.willpower -= 1
		if _willpower_depleted():
			_refresh_ui()
			_game_over()
			return
		_refresh_ui()
	# Buffs expire on their beat
	var buff_expired := false
	for kind in buffs.keys():
		if n >= buffs[kind]["until"]:
			_log(("Attack+" if kind == "atk" else "Defense+") + " fades")
			buffs.erase(kind)
			buff_expired = true
	# The buff readout counts down in beats, so it has to be redrawn on every
	# one — and once more on the beat the last one expires, or the final
	# number would stay burned on screen. It used to ride along with the
	# willpower tick, which left it frozen in Life Hearts runs and in training.
	if buff_expired or not buffs.is_empty():
		_refresh_ui()
	# On death's door: replay Cure's rhythm every 2 beats, starting on a beat
	# so the demo is honest — press along with it and you're cured.
	# The Dimensional Ring pins HP at 0 permanently, so for that build this
	# isn't a warning, it's the normal state — the alarm would never stop.
	if player_hp <= 0 and posmod(n, 2) == 0 \
			and not ItemDB.has(GameState.items, "dimensional_ring"):
		_play_cure_hint()
	# The charge buffer only lives 4 beats from its FIRST press, then it
	# auto-fizzles — so a charge can never grow into "spell too long"
	if not presses.is_empty() and (conductor.song_time - input_offset) - presses[0]["time"] > CHARGE_LIFETIME_BEATS * conductor.seconds_per_beat:
		presses.clear()
		ring.fizzle_mark()
		_log("Fizzle… (charge faded)")
		_refresh_ui()

## Twice per beat — feeds the enemy's scripted attack pattern.
func _on_eighth(n: int) -> void:
	if phase == "battle" and n >= 0 and not GameState.calibration:
		enemy.on_eighth(n)
	if training and demo_period > 0 and n >= 0:
		_demo_eighth(n % demo_period)

func _on_enemy_attack(damage: int) -> void:
	pending_attacks.append({
		"amount": damage,
		"at": conductor.song_time + half_beat * 0.5 + input_offset + 0.01,
		"grid": roundf(conductor.song_time / half_beat) * half_beat,  # the attack's beat
	})

func _process(_delta: float) -> void:
	if phase != "battle" or pending_attacks.is_empty():
		return
	var now: float = conductor.song_time
	var remaining: Array = []
	for pa in pending_attacks:
		if now >= pa["at"]:
			var dmg: int = pa["amount"]
			# Parry (Virtuosa's Flip): ↓ pressed on the attack's beat deflects.
			# Tiers: crit = negate + stun · normal = -50% · weak = -25%
			if GameState.character == "virtuosa":
				var diff := absf(last_parry - pa["grid"])
				if diff <= GameState.perfect_window():
					dmg = 0
					_parry_sound("crit")
					_perfect_parry()
				elif diff <= half_beat * 0.28:
					dmg = int(roundf(dmg * 0.5))
					_parry_sound("normal")
					_log("Parry!  -50%")
				elif diff <= half_beat * SpellBook.HIT_FRACTION:
					dmg = int(roundf(dmg * 0.75))
					_parry_sound("weak")
					_log("weak parry  -25%")
			if dmg > 0:
				_float_number("-%d" % dmg, false, Vector2(560, 550), Color(0.95, 0.35, 0.35))
				_damage_player(dmg, false, true)
			_refresh_ui()
			if phase != "battle":
				return  # parry kill / game over ended the fight mid-loop
		else:
			remaining.append(pa)
	pending_attacks = remaining

func _parry_sound(tier: String) -> void:
	parry_sfx.stream = PARRY_SFX[tier]
	parry_sfx.play()

func _perfect_parry() -> void:
	var beats := 12 if ItemDB.has(GameState.items, "flashy_nail") else 8
	enemy.stun(beats * 2)
	# A soft screen bloom + a burst on the enemy: the parry reads instantly
	_flash_screen(Color(0.85, 0.95, 1.0), 0.22, 0.3)
	spell_fx.play(enemy.position, Color(1, 1, 1), "crit", "parry")
	_float_number("PERFECT PARRY!", false, Vector2(430, 300), Color(1.0, 0.9, 0.4))
	_log("PERFECT PARRY!  stunned %d beats" % beats)
	if ItemDB.has(GameState.items, "spiky_nail"):
		enemy_hp = maxi(enemy_hp - 100, 0)
		enemy.hit()
		_float_number("-100", false, enemy.position + Vector2(-30, -130), Color(0.9, 0.9, 0.95))
		if enemy_hp <= 0 and not _target_is_a_dummy():
			_win_battle()

## All player damage funnels through here: Defense+ reduction, death
## protection, and Life Hearts. can_cost_heart=false (Needle recoil) can
## knock you to 0 HP but never takes a heart.
func _damage_player(damage: int, ignore_defense: bool, can_cost_heart: bool) -> void:
	if not ignore_defense:
		# Flat reductions (shields, Domina) first, then Defense+ percentage
		var flat := ItemDB.sum_field(GameState.items, "def_flat")
		if GameState.character == "domina":
			flat += 10
		damage = maxi(damage - flat, 0)
		damage = int(roundf(damage * (1.0 - _buff_pct("def"))))
	if damage <= 0:
		return
	if player_hp <= 0:
		if not can_cost_heart:
			return
		_flash_screen_red()
		if GameState.life_mode == "willpower":
			# Hits at 0 HP burn willpower at DOUBLE the damage; HP stays at 0
			GameState.damage_willpower(damage * 2)
			_log("-%d WILLPOWER" % (damage * 2))
			if _willpower_depleted():
				_refresh_ui()
				_game_over()
			return
		# Hit while on death's door: a Life Heart burns, HP restored to full
		GameState.lose_heart()
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

## ── The map loop ─────────────────────────────────────────────────────────
## Each 7-round cycle gets a generated map the player can see in full and
## walk along its edges. Row 6 (rounds 7/14/21…) is always the boss.
func _next_round_flow() -> void:
	# The campaign ends after round 21 — except Harmonia's true finale
	if GameState.round_num > 21:
		if GameState.character != "harmonia":
			_game_clear(false)
			return
		match GameState.round_num:
			22:
				current_node = "well"
				_enter_node("well")   # forced breather before the end
			23:
				_enter_ur_chest()     # every offer is a boss relic
			24:
				current_node = "boss"
				_enter_node("boss")   # FINAL BOSS
			_:
				_game_clear(true)
		return
	var cycle := (GameState.round_num - 1) / CYCLE_LEN
	if GameState.map_cycle != cycle:
		GameState.generate_map(cycle)
	if GameState.character == "":
		_enter_prelude_node()  # the Prelude: step in and choose your character
	else:
		_enter_choice()

## Three Ultra Rare relics, pick one. Shared by the boss reward and by
## Harmonia's round-23 vault. Returns false when the player already owns every
## relic, so callers can decide what to do with an empty vault.
func _offer_ur_relics(title: String) -> bool:
	var taken: Array = GameState.items.duplicate()
	menu_payload = []
	var opts: Array = []
	for i in 3:
		var id := ItemDB.roll(["UR"], GameState.life_mode, GameState.character, taken)
		if id == "":
			break
		var it: Dictionary = ItemDB.ITEMS[id]
		menu_payload.append(id)
		opts.append({ "label": "[UR]  %s" % it["name"], "desc": it["desc"] })
		taken.append(id)
	if menu_payload.is_empty():
		return false
	phase = "chest"  # resolves through the "chest" branch, which owes rewards
	select_menu.open(title, opts)
	return true

## Harmonia's round 23: a vault where everything is Ultra Rare.
func _enter_ur_chest() -> void:
	current_node = "chest"
	if not _offer_ur_relics("RELIC  VAULT  —  pick one"):
		_log("The relic vault is empty — you own every relic")
		_finish_node()

## The run is won. Hard mode's post-round-24 clear gets the bigger banner.
func _game_clear(true_clear: bool) -> void:
	phase = "over"
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	victory_sfx.play()
	GameState.note_run_end(GameState.round_num - 1, true, true_clear)
	var title := "TRUE  CLEAR  —  THE  SONG  IS  COMPLETE" if true_clear else "VICTORY  —  RUN  CLEAR"
	select_menu.open(title, [
		{ "label": "Return to Menu", "desc": "A new run awaits." },
	])

## The PRELUDE: the map opens with a lone node — step in to pick a character.
func _enter_prelude_node() -> void:
	phase = "prelude_map"
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	enemy.visible = false
	enemy_bar.visible = false
	ring.visible = false  # no rhythm diamond outside of combat
	map_view.visible = true
	map_view.current_row = 0
	map_view.selectable = []
	map_view.hover = -1
	map_view.show_ring_node = true
	map_view.hover_ring = true
	round_label.text = "PRELUDE"
	info_label.text = "SPACE  begin"

func _enter_choice() -> void:
	phase = "choice"
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	enemy.visible = false
	enemy_bar.visible = false
	ring.visible = false  # no rhythm diamond outside of combat
	map_view.visible = true
	# The prelude node stays on the first cycle's map, dimmed once passed
	map_view.show_ring_node = GameState.round_num <= CYCLE_LEN
	map_view.hover_ring = false
	var row := (GameState.round_num - 1) % CYCLE_LEN
	map_view.current_row = row
	choice_options = []
	if row == 0 or GameState.map_pos < 0:
		for j in GameState.map_rounds[row].size():
			choice_options.append(j)  # cycle start: any entry node
	else:
		choice_options = GameState.map_rounds[row - 1][GameState.map_pos]["edges"].duplicate()
		choice_options.sort()
	map_cursor = 0
	map_view.hover = choice_options[0]
	map_view.selectable = choice_options
	round_label.text = "ROUND %d" % GameState.round_num
	info_label.text = "← →  choose your path      SPACE  go"

func _enter_node(node_type: String) -> void:
	current_node = node_type
	match node_type:
		"fight", "elite", "boss":
			_start_battle(node_type)
		"well":
			if GameState.life_mode == "willpower":
				GameState.add_willpower(GameState.WILLPOWER_MAX / 4)
				_log("Willpower Well:  +25% willpower")
			else:
				GameState.add_heart()
				_log("Willpower Well:  +1 heart")
			_refresh_ui()
			_finish_node()
		"learn":
			_enter_learn()
		"chest":
			_enter_chest()

func _start_battle(node_type: String) -> void:
	phase = "battle"
	var enemy_id: String
	match node_type:
		"fight":
			enemy_id = "slime"
		"elite":
			enemy_id = ["clown", "hammer"].pick_random()
		_:
			enemy_id = enemy.ENEMY_TYPES.keys().pick_random()  # boss: anyone, beefed up
	enemy.setup(enemy_id)
	_draw_during()
	# Each battle draws a random track from the user's music library
	current_track = MusicLibrary.random_track()
	_apply_track()
	var scale_factor := 1.0 + ROUND_SCALING * (GameState.round_num - 1)
	var hp_mult := BOSS_HP_MULT if node_type == "boss" else 1.0
	enemy_hp = int(roundf(enemy.type["hp"] * scale_factor * hp_mult))
	enemy.damage_mult = scale_factor
	enemy.visible = true
	enemy_bar.visible = true
	enemy_bar.max_value = enemy_hp
	# Harmonia hears the song unaided: no rhythm diamond to lean on
	ring.visible = GameState.character != "harmonia"
	player_hp = player_max_hp
	presses.clear()
	buffs.clear()
	pending_attacks.clear()
	last_parry = -999.0  # song_time restarts each battle — stale values would jam the cooldown
	var boss_tag := ""
	if node_type == "boss":
		boss_tag = "   ☠ FINAL BOSS" if GameState.round_num >= 24 else "   ☠ BOSS"
	round_label.text = "ROUND %d   —   %s%s" % [
		GameState.round_num, enemy.type["display"], boss_tag]
	_refresh_ui()
	# Anything the enemy has to say happens BEFORE the fight exists: the clock
	# is still stopped, so there is no music, no metronome and no pressure
	# while the player reads. Combat begins when the talking does.
	_say_then(_intro_lines(), _begin_combat)

## Start the clock. Everything before this point was staging.
func _begin_combat() -> void:
	phase = "battle"
	# Harmonia still hears the song unaided
	ring.visible = GameState.character != "harmonia"
	conductor.count_in_beats = 16
	conductor.start_beats()
	_start_music()

## Run a page-turned conversation, then continue. With nothing to say, the
## continuation happens immediately — callers don't special-case silence.
func _say_then(lines: Array, next: Callable) -> void:
	if lines.is_empty():
		next.call()
		return
	phase = "dialogue"
	dialogue_next = next
	ring.visible = false  # no clock is running for the diamond to track
	dialogue.play(lines, true)
	info_label.text = ""

## ── Training ─────────────────────────────────────────────────────────────
## A practice bout against a dummy that can't hit back and can't be killed.
## It runs as a normal "battle" phase rather than a phase of its own, so every
## casting rule — the grid, the fizzle gate, crits, item effects — is byte for
## byte what you'll meet in a real fight. Practising against a different code
## path would teach the wrong timing.
func _enter_training(headline: String, next: Callable, lines: Array = [],
		demo := "") -> void:
	phase = "battle"
	training = true
	training_next = next
	enemy.setup("dummy")
	enemy.damage_mult = 0.0
	_draw_during()
	_set_demo(demo)
	current_track = MusicLibrary.random_track()
	_apply_track()
	enemy_hp = int(enemy.type["hp"])
	enemy.visible = true
	enemy_bar.visible = true
	enemy_bar.max_value = enemy_hp
	map_view.visible = false
	ring.visible = true  # even Harmonia gets the diamond while learning
	player_hp = player_max_hp
	presses.clear()
	buffs.clear()
	pending_attacks.clear()
	last_parry = -999.0
	round_label.text = headline
	_refresh_ui()
	if lines.is_empty():
		lines = _intro_lines()
	# Coaching is read in silence too, then the beat starts
	_say_then(lines, _begin_training_clock)

func _begin_training_clock() -> void:
	phase = "battle"
	ring.visible = true  # even Harmonia gets the diamond while learning
	conductor.count_in_beats = TRAINING_COUNT_IN
	conductor.start_beats()
	_start_music()

func is_training() -> bool:
	return training

## A rhythm can't be taught in words — it has to be heard. During a new-spell
## session the pattern ticks itself out on the grid, then leaves an equal
## silence for you to answer into: call, then response. The gap is the lesson;
## a pattern looping without one is just noise to play over.
func _set_demo(pattern: String) -> void:
	demo_pattern = pattern
	if pattern.is_empty():
		demo_period = 0
		return
	var bar := int(ceilf(pattern.length() / 8.0)) * 8  # whole bars of eighths
	demo_period = bar * 2  # the second bar is yours

## One slot of the loop. Charges tick low, the release rings higher — the two
## are distinguishable with your eyes shut, which is the whole point.
func _demo_eighth(slot: int) -> void:
	if slot >= demo_pattern.length():
		return  # the answering bar: silence, so you can hear yourself
	var sym := demo_pattern[slot]
	if sym == "_":
		return
	hint_sfx.pitch_scale = 2.4 if sym == "S" else 1.6
	hint_sfx.play()
	ring.stamp(ARROWS.get(sym, "◆"), Color(0.85, 0.8, 0.55, 0.9))

## A spell you've never played is just a rhythm you haven't heard yet, so the
## run pauses on the dummy the moment one is learned — including when it
## replaces another, since the pattern is equally new either way.
func _train_new_spell(spell_name: String) -> void:
	phase = "interlude"  # nothing is interactive until the dummy is up
	var sp := SpellBook.get_spell(spell_name)
	# Several ways to say the same three things; one set per spell learned
	var lines: Array = [
		[
			{ "speaker": "Training Dummy",
			  "text": "%s. It goes %s. I'll tap it out for you — then shut up for a bar so you can try." % [
				spell_name.to_upper(), _pattern_text(sp["pattern"])] },
			{ "speaker": "Training Dummy",
			  "text": "Nail every note and it crits. Miss one and it still works, just sadly. Miss by a lot and nothing happens at all, which is its own kind of feedback." },
			{ "speaker": "Training Dummy",
			  "text": "I heal every four beats. I have no other hobbies. ESC when you've got it." },
		],
		[
			{ "speaker": "Training Dummy",
			  "text": "New one: %s. The shape is %s. Listen first — I'll play it, then leave you a bar." % [
				spell_name.to_upper(), _pattern_text(sp["pattern"])] },
			{ "speaker": "Training Dummy",
			  "text": "Don't rush the last note. Everyone rushes the last note." },
			{ "speaker": "Training Dummy",
			  "text": "Stay as long as you like. I'm a sack of straw with excellent time. ESC to move on." },
		],
	].pick_random()
	_fade_to(func(): _enter_training(
		"NEW  SPELL  —  %s" % spell_name.to_upper(), _finish_node, lines,
		sp["pattern"]))

## Leave practice and hand control back to whatever queued it.
func end_training() -> void:
	if not training:
		return
	training = false
	_set_demo("")
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	conductor.count_in_beats = 16  # restore the real battle count-in
	enemy.visible = false
	enemy_bar.visible = false
	presses.clear()
	var next := training_next
	training_next = Callable()
	# Called straight, not through _fade_to: some destinations (_finish_node)
	# run their own fade, and two tweens on `fader` would fight each other.
	# Whoever queued the practice owns the transition out of it.
	if next.is_valid():
		next.call()

## The dummy tops itself up on a fixed cadence so a half-learned pattern can
## be repeated forever. Refilling on the beat (rather than on death) keeps the
## bar meaningful: what you see is the damage of your last few casts.
func _training_refill() -> void:
	if enemy_hp >= int(enemy_bar.max_value):
		return
	enemy_hp = int(enemy_bar.max_value)
	enemy.modulate = Color(1.3, 1.3, 1.3)
	create_tween().tween_property(enemy, "modulate", Color.WHITE, 0.25)
	_refresh_ui()

## The fight is over: the enemy explodes, victory fanfare, then rewards.
func _win_battle() -> void:
	phase = "won"
	pending_attacks.clear()
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	_refresh_ui()
	enemy.explode()
	explosion_sfx.play()
	get_tree().create_timer(0.9, false).timeout.connect(victory_sfx.play)
	get_tree().create_timer(1.7, false).timeout.connect(_after_victory)

func _after_victory() -> void:
	pending_upgrades += 1  # every won battle levels a spell of your choice
	match current_node:
		"elite":
			_enter_chest()  # elite loot: same 3-choose-1 as a chest
			return          # rewards continue after the pick
		"boss":
			# Breather first, then the relic — bosses offer a CHOICE of three,
			# same as an elite. They used to just hand over a random one.
			if GameState.life_mode == "willpower":
				GameState.add_willpower(GameState.WILLPOWER_MAX / 4)
				_log("Boss bonus: +25% willpower")
			else:
				GameState.add_heart()
				_log("Boss bonus: +1 heart")
			if _offer_ur_relics("BOSS  RELIC  —  pick one"):
				return  # rewards continue once it's picked
			_log("No relics left to claim")
	_open_rewards()

## Work through owed upgrade menus, then move to the next round.
func _open_rewards() -> void:
	if pending_upgrades > 0:
		_enter_upgrade()
	else:
		_finish_node()

func _finish_node() -> void:
	GameState.next_round()
	_fade_to(_next_round_flow)

## ── Items ────────────────────────────────────────────────────────────────

## Chest odds improve with the round: SR starts ~2% and reaches ~30% by
## round 15 (capped 40%); R creeps from 25% toward 45%; C takes the rest.
func _roll_chest_item(owned: Array) -> String:
	var rnd := GameState.round_num
	var sr_chance := clampf(0.05 + (rnd - 4) * 0.023, 0.02, 0.40)
	var r_chance := clampf(0.25 + (rnd - 1) * 0.01, 0.25, 0.45)
	var r := randf()
	var rarity: String
	if r < sr_chance:
		rarity = "SR"
	elif r < sr_chance + r_chance:
		rarity = "R"
	else:
		rarity = "C"
	var id := ItemDB.roll([rarity], GameState.life_mode, GameState.character, owned)
	if id == "":
		id = ItemDB.roll(["C", "R", "SR"], GameState.life_mode, GameState.character, owned)
	return id

## Open a chest: roll 3 distinct offers, player picks one.
func _enter_chest() -> void:
	var taken: Array = GameState.items.duplicate()
	menu_payload = []
	var opts: Array = []
	for i in 3:
		var id := _roll_chest_item(taken)
		if id == "":
			break
		var it: Dictionary = ItemDB.ITEMS[id]
		menu_payload.append(id)
		opts.append({ "label": "[%s]  %s" % [it["rarity"], it["name"]], "desc": it["desc"] })
		taken.append(id)
	if menu_payload.is_empty():
		_log("The chest is empty — you own everything it could hold")
		_open_rewards()
		return
	phase = "chest"
	select_menu.open("TREASURE  —  pick one", opts)

## Add an item to the run: log it, apply instant effects, recalc stats.
func _grant_item(id: String) -> void:
	if id == "":
		return
	var it: Dictionary = ItemDB.ITEMS[id]
	GameState.items.append(id)
	GameState.save()
	_log("[%s] %s — %s" % [it["rarity"], it["name"], it["desc"]])
	match it.get("instant", ""):
		"heart":
			GameState.add_heart()
		"level_random":
			var pick: String = GameState.known_spells.pick_random()
			GameState.upgrade_spell(pick)
			_log("Spellbook: %s leveled up!" % pick)
		"level_choice":
			pending_upgrades += 1
		"level_choice2":
			pending_upgrades += 2
	_recalc_max_hp()
	_refresh_ui()

## Max HP = 100 + cake bonuses; the Dimensional Ring pins it (and you) at 0.
func _recalc_max_hp() -> void:
	var old_max := player_max_hp
	if ItemDB.has(GameState.items, "dimensional_ring"):
		player_max_hp = 0
	else:
		player_max_hp = 100 + ItemDB.sum_field(GameState.items, "max_hp")
	if player_max_hp > old_max:
		player_hp += player_max_hp - old_max  # growing max heals the difference
	player_hp = mini(player_hp, player_max_hp)
	player_bar.max_value = maxi(player_max_hp, 1)

## ── Menus (all SelectMenu-driven) ────────────────────────────────────────

## The Prelude — the run's first decision: who plays this song?
func _enter_character_select() -> void:
	phase = "character"
	round_label.text = "PRELUDE"
	menu_payload = []
	var opts: Array = []
	for id in GameState.CHARACTERS:
		var ch: Dictionary = GameState.CHARACTERS[id]
		var rec := GameState.get_record(id)
		var badge := ""
		if bool(rec["true_clear"]):
			badge = "   ★ TRUE CLEAR"
		elif bool(rec["cleared"]):
			badge = "   ✦ CLEARED"
		elif int(rec["best_round"]) > 0:
			badge = "   best: round %d" % int(rec["best_round"])
		menu_payload.append(id)
		opts.append({ "label": ch["name"] + badge, "desc": ch["desc"] })
	select_menu.open("PRELUDE  —  CHOOSE  YOUR  CHARACTER", opts)

## Fallback lifeline select (normally chosen in the main menu).
func _enter_mode_select() -> void:
	phase = "select"
	select_menu.open("CHOOSE  YOUR  LIFELINE", [
		{ "label": "Life Hearts", "desc": "3 hearts — a hit at 0 HP burns one and restores full HP." },
		{ "label": "Willpower", "desc": "A ticking clock. Hits at 0 HP burn it double. HP stays at 0." },
	])

## Victory reward: level up one known spell.
func _enter_upgrade() -> void:
	phase = "upgrade"
	menu_payload = []
	var opts: Array = []
	for spell_name in GameState.known_spells:
		var lv := GameState.get_spell_level(spell_name)
		if lv >= 5:
			continue  # maxed spells aren't offered
		var sp := SpellBook.get_spell(spell_name)
		menu_payload.append(spell_name)
		opts.append({
			"label": "%s   Lv%d → %d" % [spell_name, lv, lv + 1],
			"desc": _pattern_text(sp["pattern"]),
		})
	if opts.is_empty():
		pending_upgrades = 0  # nothing left to level — move on
		_finish_node()
		return
	select_menu.open("LEVEL  UP  A  SPELL", opts)

## The learn node: learn a new spell (3 random picks) or take the skip bonus.
func _enter_learn() -> void:
	phase = "learn"
	learn_choices.clear()
	var unknown: Array = []
	for spell in SpellBook.SPELLS:
		if not GameState.known_spells.has(spell["name"]):
			unknown.append(spell["name"])
	unknown.shuffle()
	for i in mini(3, unknown.size()):
		learn_choices.append(unknown[i])
	menu_payload = []
	var opts: Array = []
	for spell_name in learn_choices:
		var sp := SpellBook.get_spell(spell_name)
		menu_payload.append(spell_name)
		var full_note := ""
		if GameState.known_spells.size() >= GameState.MAX_SPELLS:
			full_note = "  (spellbook full — replaces a spell, keeping its level)"
		opts.append({
			"label": spell_name,
			"desc": _pattern_text(sp["pattern"]) + full_note,
		})
	menu_payload.append("")  # skip
	opts.append({
		"label": "Skip",
		"desc": "+60 Willpower" if GameState.life_mode == "willpower" else "+1 Life Heart",
	})
	select_menu.open("LEARN  A  NEW  SPELL?", opts)

## Spellbook full: pick which spell the newcomer replaces (it inherits the level).
func _enter_replace() -> void:
	phase = "replace"
	menu_payload = []
	var opts: Array = []
	for spell_name in GameState.known_spells:
		menu_payload.append(spell_name)
		opts.append({
			"label": "%s   Lv%d" % [spell_name, GameState.get_spell_level(spell_name)],
			"desc": "%s takes this slot and inherits Lv%d." % [pending_learn, GameState.get_spell_level(spell_name)],
		})
	select_menu.open("REPLACE  WHICH  SPELL  WITH  %s?" % pending_learn.to_upper(), opts)

## Every SelectMenu resolution routes through here, keyed by phase.
func _on_menu_chosen(i: int) -> void:
	match phase:
		"select":
			GameState.set_life_mode("hearts" if i == 0 else "willpower")
			_enter_character_select()
		"character":
			GameState.set_character(menu_payload[i])
			_refresh_ui()
			_next_round_flow()
		"chest":
			_grant_item(menu_payload[i])
			_open_rewards()
		"upgrade":
			GameState.upgrade_spell(menu_payload[i])
			pending_upgrades -= 1
			_open_rewards()
		"learn":
			if menu_payload[i] == "":
				if GameState.life_mode == "willpower":
					GameState.add_willpower(60)
				else:
					GameState.add_heart()
				_finish_node()
			else:
				pending_learn = menu_payload[i]
				if GameState.known_spells.size() >= GameState.MAX_SPELLS:
					_enter_replace()
				else:
					GameState.learn_spell(pending_learn)
					_train_new_spell(pending_learn)
		"replace":
			GameState.replace_spell(menu_payload[i], pending_learn)
			_train_new_spell(pending_learn)
		"over":
			GameState.reset_run()
			var tw := create_tween()
			tw.tween_property(fader, "color:a", 1.0, 0.35)
			tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

## ── Lifelines & endings ──────────────────────────────────────────────────

## Willpower hit zero? The Band-aid saves you exactly once.
func _willpower_depleted() -> bool:
	if GameState.willpower > 0:
		return false
	if ItemDB.has(GameState.items, "band_aid") and not GameState.band_aid_used:
		GameState.band_aid_used = true
		GameState.willpower = GameState.WILLPOWER_MAX / 4
		GameState.save()
		_log("Band-aid!  willpower restored to 25%")
		return false
	GameState.willpower = 0
	return true

func _game_over() -> void:
	phase = "over"
	conductor.stop_beats()
	bgm.stop()
	dialogue.stop()
	GameState.note_run_end(GameState.round_num)
	var why := "Your willpower is spent." if GameState.life_mode == "willpower" else "Out of Life Hearts."
	select_menu.open("GAME  OVER  —  round %d.  %s" % [GameState.round_num, why], [
		{ "label": "Return to Menu",
		  "desc": "The run ends. Calibration settings are kept." },
	])

func _flash_screen_red() -> void:
	_flash_rect_pulse(0.5, 0.7)

func _flash_rect_pulse(alpha: float, duration: float) -> void:
	_flash_screen(Color(0.9, 0.1, 0.1), alpha, duration)

## All screen flashes go through here — killing the previous tween first, so
## a long damage flash can never smother the rhythmic hint pulses.
func _flash_screen(color: Color, alpha: float, duration: float) -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	flash_rect.color = Color(color.r, color.g, color.b, alpha)
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "color:a", 0.0, duration)

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
	# The screen breathes red exactly with each tick of Cure's rhythm
	_flash_rect_pulse(0.32, half_beat * 0.8)

## ── Music & debug tuning ─────────────────────────────────────────────────

## Failsafe: you can only play to a beat you can hear. Whenever the music
## isn't actually running — no track in the library, a file that failed to
## load, or a non-looping wav that ran out mid-fight — the metronome takes
## over so there's still something to play to, and steps back down as soon as
## music returns. A metronome the player switched on themselves (M) is left
## alone: `metronome_auto` marks only the clicks this failsafe owns.
func _sync_metronome() -> void:
	if bgm.playing:
		if metronome_auto:
			metronome_auto = false
			conductor.metronome = false
			_update_debug_label()
	elif not conductor.metronome:
		metronome_auto = true
		conductor.metronome = true
		_update_debug_label()

## Load the current track's stream and match the clock to its tempo.
func _apply_track() -> void:
	if current_track.is_empty():
		bgm.stream = null
		conductor.set_bpm(MUSIC_BPM)
	else:
		bgm.stream = MusicLibrary.load_stream(current_track)
		conductor.set_bpm(float(current_track["bpm"]))
	half_beat = conductor.seconds_per_beat / 2.0
	enemy.eighth_dur = half_beat  # the telegraph ramp follows the tempo
	_update_debug_label()

## The music starts WITH the count-in, skipping the track's offset seconds
## so its downbeats line up with the conductor's.
func _start_music() -> void:
	if bgm.stream:
		bgm.play(float(current_track.get("offset", GameState.music_offset)))
	# Decide before the count-in's first beat — the conductor picks whether to
	# click at the top of the beat, so waiting for _on_beat would drop one.
	_sync_metronome()

## Debug: live BPM change — edits the CURRENT TRACK's bpm (saved per track).
## Half-charged spells are cleared: their timings belong to the old tempo.
func _set_bpm(new_bpm: float) -> void:
	conductor.set_bpm(new_bpm)
	if current_track.is_empty():
		GameState.set_bpm(conductor.bpm)
	else:
		current_track["bpm"] = conductor.bpm
		MusicLibrary.save_config()
	half_beat = conductor.seconds_per_beat / 2.0
	presses.clear()
	recent_errors.clear()
	_update_debug_label()

## Live phase tuning: seek the playing track so you can align it BY EAR —
## press [ or ] until the music's beat sits on the click. Saved per track.
func _adjust_music_offset(step: float) -> void:
	if current_track.is_empty():
		GameState.set_music_offset(GameState.music_offset + step)
	else:
		current_track["offset"] = maxf(float(current_track["offset"]) + step, 0.0)
		MusicLibrary.save_config()
	if bgm.playing:
		bgm.seek(maxf(bgm.get_playback_position() + step, 0.0))
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
	if not (GameState.calibration or GameState.debug_mode):
		return
	var moffset: float = float(current_track.get("offset", GameState.music_offset))
	debug_label.text = "%s\nBPM %.0f   [-/=]\noffset %.0f ms   [</> · 0 auto]\nmusic %.0f ms   [ [ / ] ]\nmetronome %s   [M]\nring %s [D] · ball %s [B]\ntiming %s   [T]\ncrit ±%.0f ms   [ ; / ' ]" % [
		current_track.get("name", "(no track)"),
		conductor.bpm, input_offset * 1000.0, moffset * 1000.0,
		"ON" if conductor.metronome else "off",
		"ON" if ring.visible else "off", "ON" if ring.show_cursor else "off",
		"ON" if show_timing else "off",
		GameState.perfect_ms]

## ── Shared UI helpers ────────────────────────────────────────────────────

## Fade to black, run the callback, fade back in.
func _fade_to(callback: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 0.25)
	tw.tween_callback(callback)
	tw.tween_property(fader, "color:a", 0.0, 0.25)

## "L_S" -> "← · SPC" for menu display.
func _pattern_text(pattern: String) -> String:
	var out := PackedStringArray()
	for i in pattern.length():
		var ch := pattern[i]
		if ch == "_":
			out.append("·")
		elif ch == "S":
			out.append("SPC")
		else:
			out.append(ARROWS.get(ch, "?"))
	return " ".join(out)

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

## Left-side running log of casts and fizzles.
func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > LOG_LINES:
		log_lines.remove_at(0)
	cast_log.text = "\n".join(log_lines)

func _refresh_ui() -> void:
	player_bar.value = player_hp
	enemy_bar.value = enemy_hp
	if GameState.life_mode == "willpower":
		will_clock.visible = true
		hp_text.text = "HP  %d / %d" % [player_hp, player_max_hp]
	else:
		will_clock.visible = false
		hp_text.text = "HP  %d / %d      %s" % [player_hp, player_max_hp, "♥ ".repeat(GameState.hearts).strip_edges()]
	# Bottom-left inventory
	var inames := PackedStringArray()
	if GameState.character != "":
		inames.append(GameState.CHARACTERS[GameState.character]["name"])
	for id in GameState.items:
		var it: Dictionary = ItemDB.ITEMS.get(id, {})
		if not it.is_empty():
			inames.append("[%s] %s" % [it["rarity"], it["name"]])
	items_label.text = "\n".join(inames)
	var parts := PackedStringArray()
	if _buff_pct("atk") > 0.0:
		parts.append("ATK +%d%%  (%d)" % [roundf(_buff_pct("atk") * 100.0), buffs["atk"]["until"] - conductor.last_beat])
	if _buff_pct("def") > 0.0:
		parts.append("DEF -%d%%  (%d)" % [roundf(_buff_pct("def") * 100.0), buffs["def"]["until"] - conductor.last_beat])
	buff_label.text = "\n".join(parts)  # stacked in the right margin
	if phase != "battle":
		return
	if dialogue.is_active():
		info_label.text = ""  # the dialogue box owns this strip while it speaks
	elif presses.is_empty():
		info_label.text = "whack the dummy · ESC  when you're done" if training \
			else "Charge with ← on the beat, release with SPACE"
	else:
		var seq := ""
		for p in presses:
			seq += ARROWS.get(p["sym"], "?") + " "
		info_label.text = "Charging:  " + seq
