extends Node2D
## Willpower gauge: a clock face whose purple pie empties clockwise from
## 12 o'clock as willpower drains. Below 25% the glass CRACKS — the reading
## is gone, you only know it's nearly spent.

const RADIUS := 26.0
const CRACK_THRESHOLD := 0.25
const FACE := Color(0.16, 0.14, 0.2)
const RIM := Color(0.75, 0.65, 0.9)
const FILL := Color(0.62, 0.45, 0.95, 0.9)

# Jagged crack lines drawn across the dead face
const CRACKS := [
	[Vector2(-4, -25), Vector2(-1, -9), Vector2(-10, 3), Vector2(-5, 17)],
	[Vector2(12, -18), Vector2(5, -3), Vector2(13, 9), Vector2(8, 20)],
	[Vector2(-19, -10), Vector2(-7, -1), Vector2(-15, 11)],
	[Vector2(2, -6), Vector2(18, 2)],
]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var frac := float(GameState.willpower) / float(GameState.WILLPOWER_MAX)
	draw_circle(Vector2.ZERO, RADIUS + 3.0, FACE)
	draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 64, RIM, 2.0)
	if frac >= CRACK_THRESHOLD:
		# The gap eats CLOCKWISE from 12 o'clock, like a hand sweeping the
		# face clean — the remaining pie's leading edge marches clockwise.
		var start := -PI / 2.0 + TAU * (1.0 - frac)
		var pts := PackedVector2Array([Vector2.ZERO])
		var steps := maxi(int(frac * 48.0), 2)
		for i in steps + 1:
			var a := start + TAU * frac * (float(i) / float(steps))
			pts.append(Vector2(cos(a), sin(a)) * RADIUS)
		draw_colored_polygon(pts, FILL)
		draw_line(Vector2(0, -RADIUS - 3.0), Vector2(0, -RADIUS + 3.0), RIM, 2.0)
	else:
		# The glass has cracked — no more readings, only dread
		for crack in CRACKS:
			draw_polyline(PackedVector2Array(crack), Color(0.85, 0.3, 0.3, 0.9), 2.0)
