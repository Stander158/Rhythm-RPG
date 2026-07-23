extends Node2D
## The Cave Slime. Every enemy owns a UNIQUE attack script written on the same
## eighth-note grid as player spells — that's what will make attacks parryable
## later (the attack slots are known in advance).
##
## Design-doc notation (each phrase = 16 beats = 32 eighth slots):
##   ______________CA
##   ____________CACA
##   ____________(CCC- in 2 beats)AA
##   ____________(-C-A in 2 beats)CA
##   ________________                     <- breather bar
##   ____________(Heavy Charge for 3 beats) A
## C = charge cue (red flash + sfx), A = attack (~25 dmg),
## H = heavy charge held until HA = heavy attack (50 dmg).

signal attack_landed(damage: int)

const NORMAL_DAMAGE := 25
const HEAVY_DAMAGE := 50
const PHRASE_SLOTS := 32  # 16 beats x 2 eighths

# [eighth slot within the phrase, event] — the phrases loop in order forever.
const ATTACK_PHRASES := [
	[[28, "C"], [30, "A"]],
	[[24, "C"], [26, "A"], [28, "C"], [30, "A"]],
	[[24, "C"], [25, "C"], [26, "C"], [28, "A"], [30, "A"]],
	[[25, "C"], [27, "A"], [28, "C"], [30, "A"]],
	[],
	[[24, "H"], [30, "HA"]],
]

var events := {}          # global eighth slot within the cycle -> event
var cycle_slots: int
var damage_mult := 1.0    # endless-mode scaling, set by the battle each round
var charge_flash := 0.0   # red pulse from a C cue, fades fast
var heavy_charge := 0.0   # 0..1, swells over the 3-beat heavy charge
var heavy_charging := false
var hit_flash := 0.0
var base_y: float

@onready var charge_sfx: AudioStreamPlayer = $ChargeSfx
@onready var attack_sfx: AudioStreamPlayer = $AttackSfx

func _ready() -> void:
	base_y = position.y
	cycle_slots = ATTACK_PHRASES.size() * PHRASE_SLOTS
	for i in ATTACK_PHRASES.size():
		for ev in ATTACK_PHRASES[i]:
			events[i * PHRASE_SLOTS + ev[0]] = ev[1]

## Driven by the Conductor's eighth signal (via battle.gd).
func on_eighth(n: int) -> void:
	match events.get(n % cycle_slots, ""):
		"C":
			_charge()
		"A":
			_attack(NORMAL_DAMAGE)
		"H":
			_heavy_charge_start()
		"HA":
			_attack(HEAVY_DAMAGE)

## Small vertical bob on every beat — the slime dances to the music.
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
	attack_sfx.pitch_scale = 0.6 if base_damage >= HEAVY_DAMAGE else 1.0
	attack_sfx.play()
	# lunge toward the player
	position.y = base_y + 30.0
	create_tween().tween_property(self, "position:y", base_y, 0.25)
	attack_landed.emit(int(roundf(base_damage * damage_mult)))

func _process(delta: float) -> void:
	hit_flash = maxf(hit_flash - delta * 3.0, 0.0)
	charge_flash = maxf(charge_flash - delta * 2.5, 0.0)
	if heavy_charging:
		heavy_charge = minf(heavy_charge + delta / 1.8, 1.0)  # 3 beats at 100 BPM
	queue_redraw()

func _draw() -> void:
	var danger := maxf(charge_flash, heavy_charge)
	var body := Color(0.35, 0.7, 0.45).lerp(Color(0.85, 0.25, 0.25), danger)
	body = body.lerp(Color.WHITE, hit_flash)
	var radius := 70.0 + heavy_charge * 14.0  # swells while heavy-charging
	draw_circle(Vector2.ZERO, radius, body)
	# Eyes
	draw_circle(Vector2(-25, -15), 10.0, Color.WHITE)
	draw_circle(Vector2(25, -15), 10.0, Color.WHITE)
	draw_circle(Vector2(-25, -15), 4.0, Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(25, -15), 4.0, Color(0.1, 0.1, 0.1))
