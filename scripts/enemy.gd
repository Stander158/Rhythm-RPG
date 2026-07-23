extends Node2D
## Data-driven enemies. Every enemy is an entry in ENEMY_TYPES: stats, look,
## unlock round, and a unique attack script on the eighth-note grid — which is
## what will make attacks parryable later (attack slots are known in advance).
##
## Sheet notation (from the design doc): C = charge cue, A = attack,
## H = heavy charge held until HA = heavy attack, _ = beat rest, - = eighth
## rest. Slime phrases are 16 beats (32 slots); the others are 8 beats (16).

signal attack_landed(damage: int)

const ENEMY_TYPES := {
	# Slime: the tutorial enemy — steady escalation with a breather bar
	"slime": {
		"display": "Cave Slime",
		"hp": 1200, "normal": 25, "heavy": 50,
		"unlock_round": 1,
		"radius": 70.0, "color": Color(0.35, 0.7, 0.45),
		"phrase_slots": 32,
		"phrases": [
			[[28, "C"], [30, "A"]],                                   # ______________CA
			[[24, "C"], [26, "A"], [28, "C"], [30, "A"]],             # ____________CACA
			[[24, "C"], [25, "C"], [26, "C"], [28, "A"], [30, "A"]],  # (CCC- in 2 beats)AA
			[[25, "C"], [27, "A"], [28, "C"], [30, "A"]],             # (-C-A in 2 beats)CA
			[],                                                        # breather
			[[24, "H"], [30, "HA"]],                                   # Heavy Charge 3 beats -> A
		],
	},
	# Mad Clown: relentless — attacks often, hits light
	"clown": {
		"display": "Mad Clown",
		"hp": 1000, "normal": 18, "heavy": 42,
		"unlock_round": 3,
		"radius": 60.0, "color": Color(0.85, 0.4, 0.75),
		"phrase_slots": 16,
		"phrases": [
			[],                                                        # ________
			[[12, "C"], [14, "A"]],                                    # ______CA
			[[12, "C"], [14, "A"]],                                    # ______CA
			[[8, "C"], [10, "A"], [12, "C"], [14, "A"]],               # ____CACA
			[],                                                        # ________
			[[9, "C"], [11, "A"], [12, "C"], [14, "A"]],               # ____(-C-A)CA
			[[8, "C"], [9, "C"], [10, "C"], [12, "A"], [14, "A"]],     # ____(CCC in 2 beats)AA
			[[8, "H"], [14, "HA"]],                                    # ____(Heavy 3 beats)A
			[],                                                        # ________
			[[8, "C"], [10, "A"], [13, "C"], [15, "A"]],               # ____CA(-C-A)
		],
	},
	# Hammer Man: slow and terrifying — rare hits, huge numbers
	"hammer": {
		"display": "Hammer Man",
		"hp": 1400, "normal": 33, "heavy": 66,
		"unlock_round": 5,
		"radius": 82.0, "color": Color(0.55, 0.55, 0.65),
		"phrase_slots": 16,
		"phrases": [
			[],                                                        # ________
			[[12, "C"], [14, "A"]],                                    # ______CA
			[],                                                        # ________
			[[8, "H"], [14, "HA"]],                                    # ____(Heavy 3 beats)A
			[],                                                        # ________
			[[10, "C"], [12, "A"]],                                    # _____CA_
			[],                                                        # ________
			[[8, "H"], [14, "HA"]],                                    # ____(Heavy 3 beats)A
			[],                                                        # ________
			[[8, "C"], [10, "A"], [12, "C"], [14, "A"]],               # ____CACA
			[],                                                        # ________
			[],                                                        # ________
			[[8, "C"], [9, "C"], [10, "C"], [12, "A"], [14, "A"]],     # ____(CCC in 2 beats)AA
			[[8, "H"], [14, "HA"]],                                    # ____(Heavy 3 beats)A
		],
	},
}

var type: Dictionary = ENEMY_TYPES["slime"]
var events := {}          # global eighth slot within the cycle -> event
var cycle_slots: int = 1
var damage_mult := 1.0    # endless-mode scaling, set by the battle each round
var last_eighth := 0
var stun_until := -1      # global eighth when a parry stun wears off
var armed := true         # false after a stun: attacks wait for a fresh charge,
						  # so a chain whose first C fell inside the stun is skipped
var charge_flash := 0.0   # red pulse from a C cue, fades fast
var heavy_charge := 0.0   # 0..1, swells over the 3-beat heavy charge
var heavy_charging := false
var hit_flash := 0.0
var base_y: float

@onready var charge_sfx: AudioStreamPlayer = $ChargeSfx
@onready var attack_sfx: AudioStreamPlayer = $AttackSfx

func _ready() -> void:
	base_y = position.y
	setup("slime")

## Load an enemy type: stats + flattened attack-event table.
func setup(type_id: String) -> void:
	type = ENEMY_TYPES[type_id]
	# Fresh fighter, fresh state — a stun never carries over between enemies
	stun_until = -1
	last_eighth = 0
	armed = true
	heavy_charging = false
	heavy_charge = 0.0
	charge_flash = 0.0
	hit_flash = 0.0
	events.clear()
	var slots: int = type["phrase_slots"]
	cycle_slots = type["phrases"].size() * slots
	for i in type["phrases"].size():
		for ev in type["phrases"][i]:
			events[i * slots + ev[0]] = ev[1]
	queue_redraw()

## Driven by the Conductor's eighth signal (via battle.gd). The cycle position
## always advances — a stun doesn't shift the pattern, it just eats events.
func on_eighth(n: int) -> void:
	last_eighth = n
	if is_stunned():
		return
	match events.get(n % cycle_slots, ""):
		"C":
			armed = true
			_charge()
		"A":
			if armed:
				_attack(type["normal"])
		"H":
			armed = true
			_heavy_charge_start()
		"HA":
			if armed:
				_attack(type["heavy"])

func is_stunned() -> bool:
	return last_eighth < stun_until

## Perfect parry: freeze the attack script for a while. Also disarms —
## attacks only resume once a fresh charge has been performed.
func stun(eighths: int) -> void:
	stun_until = last_eighth + eighths
	armed = false
	heavy_charging = false
	heavy_charge = 0.0
	charge_flash = 0.0

## Small vertical bob on every beat — dancing to the music.
func bob() -> void:
	position.y = base_y - 8.0
	create_tween().tween_property(self, "position:y", base_y, 0.18)

func hit() -> void:
	hit_flash = 1.0
	scale = Vector2(0.8, 1.2)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.3)

func _charge() -> void:
	charge_flash = 1.0
	charge_sfx.pitch_scale = 1.0
	charge_sfx.play()

func _heavy_charge_start() -> void:
	heavy_charging = true
	heavy_charge = 0.0
	charge_sfx.pitch_scale = 0.5  # same sample, ominous octave down
	charge_sfx.play()

func _attack(base_damage: int) -> void:
	heavy_charging = false
	heavy_charge = 0.0
	attack_sfx.pitch_scale = 0.6 if base_damage >= int(type["heavy"]) else 1.0
	attack_sfx.play()
	# lunge toward the player
	position.y = base_y + 30.0
	create_tween().tween_property(self, "position:y", base_y, 0.25)
	# Attacks land with variance: 80%–100% of the scaled value
	attack_landed.emit(int(roundf(base_damage * damage_mult * randf_range(0.8, 1.0))))

func _process(delta: float) -> void:
	hit_flash = maxf(hit_flash - delta * 3.0, 0.0)
	charge_flash = maxf(charge_flash - delta * 2.5, 0.0)
	if heavy_charging:
		heavy_charge = minf(heavy_charge + delta / 1.8, 1.0)  # 3 beats at 100 BPM
	queue_redraw()

func _draw() -> void:
	var danger := maxf(charge_flash, heavy_charge)
	var body: Color = type["color"]
	body = body.lerp(Color(0.85, 0.25, 0.25), danger)
	body = body.lerp(Color.WHITE, hit_flash)
	if is_stunned():
		body = body.lerp(Color(0.5, 0.5, 0.55), 0.6)  # dazed grey
	var radius: float = type["radius"] + heavy_charge * 14.0  # swells while heavy-charging
	draw_circle(Vector2.ZERO, radius, body)
	# Eyes — X-ed out while stunned
	draw_circle(Vector2(-25, -15), 10.0, Color.WHITE)
	draw_circle(Vector2(25, -15), 10.0, Color.WHITE)
	if is_stunned():
		for ex in [-25.0, 25.0]:
			draw_line(Vector2(ex - 5, -20), Vector2(ex + 5, -10), Color(0.1, 0.1, 0.1), 2.0)
			draw_line(Vector2(ex - 5, -10), Vector2(ex + 5, -20), Color(0.1, 0.1, 0.1), 2.0)
	else:
		draw_circle(Vector2(-25, -15), 4.0, Color(0.1, 0.1, 0.1))
		draw_circle(Vector2(25, -15), 4.0, Color(0.1, 0.1, 0.1))
