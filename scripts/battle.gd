extends Node2D
## Endless-mode battle. Charge spells with arrow keys ON THE BEAT, release
## with SPACE. Win -> pick a spell to level up -> next round, enemy +10%
## hp/damage. At 0 HP hits cost Life Hearts; out of hearts = run over.
## Phases: "battle" -> "upgrade" (victory menu) / "over" (game over).

const CHARGE_LIFETIME_BEATS := 4.0  # buffer auto-fizzles 4 beats after the first press
const ARROWS := { "L": "←", "R": "→", "U": "↑", "D": "↓" }
const LOG_LINES := 4
const NORMAL_TIER := 0.65  # accuracy below this sounds/acts "weak"
const ROUND_SCALING := 0.25  # each round adds a flat +25% of base (linear, not compounding)
const CYCLE_LEN := 7         # rounds per cycle; the last round of each cycle is a BOSS
const BOSS_HP_MULT := 2.0

# Map nodes: what a round can be. Each round you draw 1–3 of these and pick.
const NODE_TYPES := ["fight", "elite", "well", "learn", "chest"]
const NODE_INFO := {
	"fight": "Fight — Cave Slime   (win: level up a spell)",
	"elite": "Strong Enemy — ???   (win: level up + item)",
	"well": "Willpower Well   (+25% willpower / +1 heart)",
	"learn": "Learn a spell   (3 random choices)",
	"chest": "Treasure Chest   (???)",
}
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
var phase := "battle"    # "battle" | "select" | "ring" | "choice" | "chest" | "upgrade" | "learn" | "replace" | "over"
var pending_upgrades := 0      # upgrade menus owed (battle win, grimoires…)
var last_parry := -999.0       # judged time of the last parry attempt (Flip Ring)
var current_node := ""         # the map node being played ("fight"/"elite"/"boss"/…)
var current_track: Dictionary = {}  # this battle's music (from MusicLibrary)
var choice_options: Array = [] # node types offered on the choice screen
var chest_choices: Array = []  # item ids offered by an opened chest
var learn_choices: Array = []  # spell names offered on the learn screen
var pending_learn := ""        # picked spell waiting for a replacement slot
var buffs := {}          # "atk"/"def" -> { "pct": float, "until": beat number }
var pending_attacks: Array = []  # enemy hits waiting for the beat's window to close
var flash_tween: Tween           # single owner of the red-flash animation
var show_timing := false         # calibration debug: show each press's signed error in ms
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
@onready var will_clock: Node2D = $UI/WillClock
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
@onready var parry_sfx: AudioStreamPlayer = $ParrySfx
@onready var items_label: Label = $UI/ItemsLabel
@onready var map_view: Node2D = $UI/MapView
@onready var bgm: AudioStreamPlayer = $BGM

const MUSIC_BPM := 118.0  # the BGM track's tempo — overrides the saved BPM

func _ready() -> void:
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
	upgrade_label.visible = false
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
		round_label.text = "CALIBRATION MODE   (ESC then M returns to menu · N next track)"
		if not MusicLibrary.tracks.is_empty():
			current_track = MusicLibrary.tracks[0]
		_apply_track()
		conductor.start_beats()
		_start_music()
	elif GameState.life_mode == "":
		_enter_mode_select()  # fallback: shouldn't happen via the menu flow
	elif GameState.ring == "":
		_enter_ring_select()  # a fresh run starts by choosing a ring
	else:
		_next_round_flow()

func _unhandled_input(event: InputEvent) -> void:
	if phase == "over":
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			GameState.reset_run()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	if phase != "battle":
		_handle_menu_key(event)
		return
	# Debug: - / = BPM ±1; < / > input offset ±1 ms; [ / ] music offset ±1 ms;
	# 0 auto-calibrates; M toggles the metronome click. Held keys repeat.
	if event is InputEventKey and event.pressed:
		match event.keycode:
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
				if not event.echo and GameState.calibration:
					show_timing = not show_timing
					_update_debug_label()
				return
			KEY_N:  # next track (calibration): restart the count-in on it
				if not event.echo and GameState.calibration and not MusicLibrary.tracks.is_empty():
					var i: int = MusicLibrary.tracks.find(current_track)
					current_track = MusicLibrary.tracks[(i + 1) % MusicLibrary.tracks.size()]
					_apply_track()
					conductor.start_beats()
					_start_music()
				return
			KEY_SEMICOLON:  # ;  narrower crit window (calibration only)
				if GameState.calibration:
					GameState.set_perfect_fraction(GameState.perfect_fraction - 0.01)
					_update_debug_label()
				return
			KEY_APOSTROPHE:  # '  wider crit window (calibration only)
				if GameState.calibration:
					GameState.set_perfect_fraction(GameState.perfect_fraction + 0.01)
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
	if sym == "D" and GameState.ring == "flip":
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
		var tcolor := Color(1.0, 0.85, 0.2) if absf(err) <= half_beat * GameState.perfect_fraction else Color(0.6, 0.7, 0.85)
		_float_number("%+.0f ms" % ms, false, ring.position + Vector2(105, -40), tcolor)
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
	if off <= half_beat * GameState.perfect_fraction:
		color = Color(1.0, 0.85, 0.2)
	elif off <= half_beat * SpellBook.CLOSE_FRACTION:
		color = Color(0.4, 0.65, 1.0)
	else:
		color = Color(0.5, 0.5, 0.55)
	ring.flash(color)
	ring.stamp(ARROWS.get(sym, "•"), color)

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
	var pf := GameState.perfect_fraction * (1.5 if ItemDB.has(GameState.items, "x_matter") else 1.0)
	var q: Dictionary = SpellBook.quality(res["offsets"], half_beat, pf)
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
			if GameState.ring == "strong":
				heal += 10
			var restored := mini(player_hp + heal, player_max_hp) - player_hp
			player_hp += restored
			_log("Cure +%d%s%s" % [restored, "  PERFECT" if q["crit"] else "", stray_tag])
			_float_number("+%d" % restored, false, Vector2(500, 555), Color(0.45, 0.9, 0.55))
			# Magical Crystal: restored health strikes the enemy at 200%
			if ItemDB.has(GameState.items, "magical_crystal") and restored > 0:
				var mc := restored * 2
				enemy_hp = maxi(enemy_hp - mc, 0)
				enemy.hit()
				_float_number("-%d" % mc, false, enemy.position + Vector2(-30, -130), Color(0.8, 0.6, 1.0))
				if enemy_hp <= 0 and not GameState.calibration:
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
		_:
			# Damage spells (fire / water / electric / normal)
			var base: int = spell["damage"][lv - 1]
			var amount: int
			if q["crit"]:
				amount = base * 2
				if ItemDB.has(GameState.items, "thunderous_gem"):
					amount *= 3
				if ItemDB.has(GameState.items, "suit"):
					GameState.suit_crits += 1
					GameState.save()
			else:
				# Some spells (Bolt) are all-or-nothing: non-crits are penalized
				amount = int(roundf(base * q["avg"] * spell.get("noncrit_mult", 1.0)))
			# Flat item bonuses
			amount += ItemDB.sum_field(GameState.items, "atk_flat")
			amount += ItemDB.type_flat(GameState.items, spell["type"])
			if GameState.ring == "strong":
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
			_float_number("-%d" % amount, q["crit"], enemy.position + Vector2(-30, -130), color)
			if spell.has("self_damage"):
				# Needle's price: ignores Defense+, can knock you to 0 HP,
				# but never costs a Life Heart
				_damage_player(spell["self_damage"], true, false)
				_log("Needle recoil -%d" % spell["self_damage"])
			if enemy_hp <= 0:
				if GameState.calibration:
					enemy_hp = int(enemy_bar.max_value)  # target dummy respawns
				else:
					_win_battle()
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
	if not GameState.calibration:
		enemy.bob()
	if n < 0:
		info_label.text = "Get ready…  %d" % -n  # count-in: 8, 7, 6…
		return
	if n == 0:
		_refresh_ui()  # count-in over, restore the normal hint
	# Willpower mode: the clock is always ticking (Dimensional Ring stops it)
	if GameState.life_mode == "willpower" and not GameState.calibration:
		if not ItemDB.has(GameState.items, "dimensional_ring"):
			GameState.willpower -= 1
		if _willpower_depleted():
			_refresh_ui()
			_game_over()
			return
		_refresh_ui()
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

## Same-beat resolution favors the PLAYER: an enemy hit doesn't land until
## this beat's judgment window has closed, so a cast released "late but still
## on the beat" resolves first — a kill cancels the hit, a Cure heals before
## the damage, a Defense+ starts reducing it.
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
			# Parry (Flip Ring): ↓ pressed on the attack's beat deflects.
			# Tiers: crit = negate + stun · normal = -50% · weak = -25%
			if GameState.ring == "flip":
				var diff := absf(last_parry - pa["grid"])
				if diff <= half_beat * GameState.perfect_fraction:
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
	_log("PERFECT PARRY!  stunned %d beats" % beats)
	if ItemDB.has(GameState.items, "spiky_nail"):
		enemy_hp = maxi(enemy_hp - 100, 0)
		enemy.hit()
		_float_number("-100", false, enemy.position + Vector2(-30, -130), Color(0.9, 0.9, 0.95))
		if enemy_hp <= 0 and not GameState.calibration:
			_win_battle()

## All player damage funnels through here: Defense+ reduction, death
## protection, and Life Hearts. can_cost_heart=false (Needle recoil) can
## knock you to 0 HP but never takes a heart.
func _damage_player(damage: int, ignore_defense: bool, can_cost_heart: bool) -> void:
	if not ignore_defense:
		# Flat reductions (shields, Strong Ring) first, then Defense+ percentage
		var flat := ItemDB.sum_field(GameState.items, "def_flat")
		if GameState.ring == "strong":
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
	var cycle := (GameState.round_num - 1) / CYCLE_LEN
	if GameState.map_cycle != cycle:
		GameState.generate_map(cycle)
	_enter_choice()

func _enter_choice() -> void:
	phase = "choice"
	conductor.stop_beats()
	bgm.stop()
	enemy.visible = false
	enemy_bar.visible = false
	upgrade_label.visible = false
	map_view.visible = true
	var row := (GameState.round_num - 1) % CYCLE_LEN
	map_view.current_row = row
	choice_options = []
	if row == 0 or GameState.map_pos < 0:
		for j in GameState.map_rounds[row].size():
			choice_options.append(j)  # cycle start: any entry node
	else:
		choice_options = GameState.map_rounds[row - 1][GameState.map_pos]["edges"].duplicate()
		choice_options.sort()
	map_view.selectable = choice_options
	round_label.text = "ROUND %d" % GameState.round_num
	info_label.text = "Choose your path (1-%d)    F fight · E elite · W well · L learn · C chest · B boss" % choice_options.size()

func _enter_node(node_type: String) -> void:
	current_node = node_type
	upgrade_label.visible = false
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
	player_hp = player_max_hp
	presses.clear()
	buffs.clear()
	pending_attacks.clear()
	last_parry = -999.0  # song_time restarts each battle — stale values would jam the cooldown
	round_label.text = "ROUND %d   —   %s%s" % [
		GameState.round_num, enemy.type["display"], "   ☠ BOSS" if node_type == "boss" else ""]
	_refresh_ui()
	conductor.start_beats()
	_start_music()

## The fight is over: stop the music, hand out loot, then upgrade menu(s).
func _win_battle() -> void:
	pending_attacks.clear()  # a dead enemy's swing never lands
	conductor.stop_beats()
	bgm.stop()
	_refresh_ui()
	pending_upgrades += 1  # every won battle levels a spell of your choice
	match current_node:
		"elite":
			_enter_chest()  # elite loot: same 3-choose-1 as a chest
			return          # rewards continue after the pick
		"boss":
			# Boss relic (UR) + a breather
			_grant_item(ItemDB.roll(["UR"], GameState.life_mode, GameState.ring, GameState.items))
			if GameState.life_mode == "willpower":
				GameState.add_willpower(GameState.WILLPOWER_MAX / 4)
				_log("Boss bonus: +25% willpower")
			else:
				GameState.add_heart()
				_log("Boss bonus: +1 heart")
	_open_rewards()

## Work through owed upgrade menus, then move to the next round.
func _open_rewards() -> void:
	if pending_upgrades > 0:
		_enter_upgrade()
	else:
		_finish_node()

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
	var id := ItemDB.roll([rarity], GameState.life_mode, GameState.ring, owned)
	if id == "":
		id = ItemDB.roll(["C", "R", "SR"], GameState.life_mode, GameState.ring, owned)
	return id

## Open a chest: roll 3 distinct offers, player picks one.
func _enter_chest() -> void:
	chest_choices.clear()
	var taken: Array = GameState.items.duplicate()
	for i in 3:
		var id := _roll_chest_item(taken)
		if id == "":
			break
		chest_choices.append(id)
		taken.append(id)
	if chest_choices.is_empty():
		_log("The chest is empty — you own everything it could hold")
		_open_rewards()
		return
	phase = "chest"
	upgrade_label.visible = true
	info_label.text = ""
	var lines := ["Treasure chest!  Pick one:", ""]
	for i in chest_choices.size():
		var it: Dictionary = ItemDB.ITEMS[chest_choices[i]]
		lines.append("%d.  [%s] %s — %s" % [i + 1, it["rarity"], it["name"], it["desc"]])
	upgrade_label.text = "\n".join(lines)

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

func _finish_node() -> void:
	GameState.next_round()
	_next_round_flow()

## A fresh run's first decision: which ring?
func _enter_ring_select() -> void:
	phase = "ring"
	upgrade_label.visible = true
	info_label.text = ""
	round_label.text = ""
	upgrade_label.text = (
		"Choose your ring:\n\n"
		+ "1.  FLIP RING\n     enables PARRY — press an arrow on the enemy's\n     attack beat (perfect parry stuns!)\n\n"
		+ "2.  STRONG RING\n     attack +10 · damage taken -10 · healing +10\n\n"
		+ "3.  NO RING"
	)

## Fresh run: pick Life Hearts or Willpower before the music starts.
func _enter_mode_select() -> void:
	phase = "select"
	upgrade_label.visible = true
	info_label.text = ""
	upgrade_label.text = (
		"Choose your lifeline for this run:\n\n"
		+ "1.  LIFE HEARTS\n     3 hearts — a hit at 0 HP burns one\n     and restores you to full HP\n\n"
		+ "2.  WILLPOWER\n     a ticking clock — drains every beat,\n     hits at 0 HP burn it by the damage, HP stays 0.\n     When it cracks, you won't know how much is left…"
	)

## Victory reward 1: level up one known spell.
func _enter_upgrade() -> void:
	phase = "upgrade"
	conductor.stop_beats()
	bgm.stop()
	upgrade_label.visible = true
	info_label.text = ""
	var all_maxed := true
	var lines := ["VICTORY!  Choose a spell to level up:", ""]
	for i in GameState.known_spells.size():
		var spell_name: String = GameState.known_spells[i]
		var lv := GameState.get_spell_level(spell_name)
		if lv >= 5:
			lines.append("%d.  %s   Lv%d  (MAX)" % [i + 1, spell_name, lv])
		else:
			all_maxed = false
			lines.append("%d.  %s   Lv%d → %d" % [i + 1, spell_name, lv, lv + 1])
	if all_maxed:
		pending_upgrades = 0  # nothing left to level — move on
		_finish_node()
		return
	upgrade_label.text = "\n".join(lines)

## The learn node: learn a new spell (3 random picks) or take the skip bonus.
func _enter_learn() -> void:
	phase = "learn"
	upgrade_label.visible = true
	info_label.text = ""
	learn_choices.clear()
	var unknown: Array = []
	for spell in SpellBook.SPELLS:
		if not GameState.known_spells.has(spell["name"]):
			unknown.append(spell["name"])
	unknown.shuffle()
	for i in mini(3, unknown.size()):
		learn_choices.append(unknown[i])
	var lines := ["Learn a new spell?", ""]
	for i in learn_choices.size():
		var sp := SpellBook.get_spell(learn_choices[i])
		lines.append("%d.  %s   %s" % [i + 1, sp["name"], _pattern_text(sp["pattern"])])
	var skip_reward := "+60 Willpower" if GameState.life_mode == "willpower" else "+1 Life Heart"
	lines.append("%d.  Skip  →  %s" % [learn_choices.size() + 1, skip_reward])
	if GameState.known_spells.size() >= GameState.MAX_SPELLS and not learn_choices.is_empty():
		lines.append("")
		lines.append("(spellbook full — learning replaces a spell, keeping its level)")
	upgrade_label.text = "\n".join(lines)

## Spellbook full: pick which spell the newcomer replaces (it inherits the level).
func _enter_replace() -> void:
	phase = "replace"
	var lines := ["Replace which spell with %s?" % pending_learn, "(the new spell inherits its level)", ""]
	for i in GameState.known_spells.size():
		var spell_name: String = GameState.known_spells[i]
		lines.append("%d.  %s   Lv%d" % [i + 1, spell_name, GameState.get_spell_level(spell_name)])
	upgrade_label.text = "\n".join(lines)

func _handle_menu_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var idx: int = event.keycode - KEY_1
	match phase:
		"select":
			if idx == 0 or idx == 1:
				GameState.set_life_mode("hearts" if idx == 0 else "willpower")
				upgrade_label.visible = false
				_refresh_ui()
				_enter_ring_select()
		"ring":
			if idx >= 0 and idx <= 2:
				GameState.set_ring(["flip", "strong", "none"][idx])
				upgrade_label.visible = false
				_refresh_ui()
				_next_round_flow()
		"choice":
			if idx >= 0 and idx < choice_options.size():
				var target: int = choice_options[idx]
				GameState.set_map_pos(target)
				map_view.visible = false
				var row := (GameState.round_num - 1) % CYCLE_LEN
				_enter_node(GameState.map_rounds[row][target]["type"])
		"chest":
			if idx >= 0 and idx < chest_choices.size():
				_grant_item(chest_choices[idx])
				upgrade_label.visible = false
				_open_rewards()
		"upgrade":
			if idx < 0 or idx >= GameState.known_spells.size():
				return
			var spell_name: String = GameState.known_spells[idx]
			if GameState.get_spell_level(spell_name) >= 5:
				return  # maxed — pick another
			GameState.upgrade_spell(spell_name)
			pending_upgrades -= 1
			_open_rewards()
		"learn":
			if idx == learn_choices.size():
				if GameState.life_mode == "willpower":
					GameState.add_willpower(60)
				else:
					GameState.add_heart()
				_finish_node()
			elif idx >= 0 and idx < learn_choices.size():
				pending_learn = learn_choices[idx]
				if GameState.known_spells.size() >= GameState.MAX_SPELLS:
					_enter_replace()
				else:
					GameState.learn_spell(pending_learn)
					_finish_node()
		"replace":
			if idx < 0 or idx >= GameState.known_spells.size():
				return
			GameState.replace_spell(GameState.known_spells[idx], pending_learn)
			_finish_node()

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
	var why := "your willpower is spent." if GameState.life_mode == "willpower" else "out of Life Hearts."
	info_label.text = "GAME OVER — %s  R = new run" % why

func _flash_screen_red() -> void:
	_flash_rect_pulse(0.5, 0.7)

## All red flashes go through here — killing the previous tween first, so a
## long damage flash can never smother the rhythmic hint pulses.
func _flash_rect_pulse(alpha: float, duration: float) -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	flash_rect.color = Color(0.9, 0.1, 0.1, alpha)
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

## Load the current track's stream and match the clock to its tempo.
func _apply_track() -> void:
	if current_track.is_empty():
		bgm.stream = null
		conductor.set_bpm(MUSIC_BPM)
	else:
		bgm.stream = MusicLibrary.load_stream(current_track)
		conductor.set_bpm(float(current_track["bpm"]))
	half_beat = conductor.seconds_per_beat / 2.0
	_update_debug_label()

## The music starts WITH the count-in, skipping the track's offset seconds
## so its downbeats line up with the conductor's.
func _start_music() -> void:
	if bgm.stream:
		bgm.play(float(current_track.get("offset", GameState.music_offset)))

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

func _update_debug_label() -> void:
	var moffset: float = float(current_track.get("offset", GameState.music_offset))
	debug_label.text = "%s\nBPM %.0f   [-/=]\noffset %.0f ms   [</> · 0 auto]\nmusic %.0f ms   [ [ / ] ]\nmetronome %s   [M]\nring %s [D] · ball %s [B]" % [
		current_track.get("name", "(no track)"),
		conductor.bpm, input_offset * 1000.0, moffset * 1000.0,
		"ON" if conductor.metronome else "off",
		"ON" if ring.visible else "off", "ON" if ring.show_cursor else "off"]
	if GameState.calibration:
		debug_label.text += "\ntiming %s   [T]\ncrit ±%.0f ms   [ ; / ' ]" % [
			"ON" if show_timing else "off", half_beat * GameState.perfect_fraction * 1000.0]

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
	if GameState.life_mode == "willpower":
		will_clock.visible = true
		hp_text.text = "HP  %d / %d" % [player_hp, player_max_hp]
	else:
		will_clock.visible = false
		hp_text.text = "HP  %d / %d      %s" % [player_hp, player_max_hp, "♥ ".repeat(GameState.hearts).strip_edges()]
	# Bottom-left inventory
	var inames := PackedStringArray()
	if GameState.ring != "" and GameState.ring != "none":
		inames.append("RING: %s" % ("Flip" if GameState.ring == "flip" else "Strong"))
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
