extends Node2D
## Rhythm diamond: a square rotated 45°. The cursor travels the edges
## clockwise starting from the TOP corner, hitting one corner per full beat
## (4 beats = one lap). Player inputs are stamped where the cursor was when
## the key went down, colored by accuracy, and fade out.

const R := 80.0
const CORNERS := [Vector2(0, -R), Vector2(R, 0), Vector2(0, R), Vector2(-R, 0)]
const STAMP_LIFE := 1.6  # seconds an input stamp stays visible

var stamps: Array = []   # { "pos": Vector2, "text": String, "color": Color, "age": float }
var flash_color := Color(1, 1, 1, 0)  # center flash on every press

@onready var conductor: AudioStreamPlayer = $"../Conductor"

## Called by the battle on every press: gold = Perfect, blue = close, grey = off.
func flash(c: Color) -> void:
	flash_color = Color(c.r, c.g, c.b, 0.7)

## Stamp the pressed key at the cursor's current spot.
func stamp(text: String, color: Color) -> void:
	stamps.append({ "pos": _cursor_pos(), "text": text, "color": color, "age": 0.0 })

## Where the cursor is right now: corner index = beat within the bar,
## progress along the edge = how far into the beat we are.
func _cursor_pos() -> Vector2:
	var idx: int = posmod(conductor.last_beat, 4)
	return CORNERS[idx].lerp(CORNERS[(idx + 1) % 4], conductor.beat_progress())

func _process(delta: float) -> void:
	flash_color.a = maxf(flash_color.a - delta * 4.0, 0.0)
	for s in stamps:
		s["age"] += delta
	stamps = stamps.filter(func(s): return s["age"] < STAMP_LIFE)
	queue_redraw()

func _draw() -> void:
	if flash_color.a > 0.0:
		draw_circle(Vector2.ZERO, 34.0, flash_color)
	# the diamond itself
	draw_polyline([CORNERS[0], CORNERS[1], CORNERS[2], CORNERS[3], CORNERS[0]],
		Color(1, 1, 1, 0.5), 2.0)
	# corner dots — the corner we just hit pops on the beat, then settles
	var progress: float = conductor.beat_progress()
	var current: int = posmod(conductor.last_beat, 4)
	for i in 4:
		var size := 5.0
		if i == current:
			size = lerpf(10.0, 5.0, progress)
		draw_circle(CORNERS[i], size, Color.WHITE)
	# the travelling cursor
	if conductor.running:
		draw_circle(_cursor_pos(), 7.0, Color(0.4, 0.75, 1.0))
	# player input stamps, fading with age
	var font := ThemeDB.fallback_font
	for s in stamps:
		var c: Color = s["color"]
		c.a = 1.0 - s["age"] / STAMP_LIFE
		draw_string(font, s["pos"] + Vector2(-7, -10), s["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)
