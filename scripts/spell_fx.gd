extends Node2D
## Spell impact effects, drawn in code — one distinct animation per spell,
## scaled by how well the cast went (weak / normal / crit). Everything is
## short and snappy: bursts clear out well inside a beat.

const LIFE := { "weak": 0.16, "normal": 0.24, "crit": 0.34 }
const SCALE := { "weak": 0.6, "normal": 1.0, "crit": 1.5 }

var bursts: Array = []  # { pos, color, tier, kind, age, seed }

func play(pos: Vector2, color: Color, tier: String, kind: String) -> void:
	bursts.append({
		"pos": pos, "color": color, "tier": tier, "kind": kind,
		"age": 0.0, "seed": randf() * TAU,
	})

func _process(delta: float) -> void:
	if bursts.is_empty():
		return
	for b in bursts:
		b["age"] += delta
	bursts = bursts.filter(func(b): return b["age"] < LIFE[b["tier"]])
	queue_redraw()

func _draw() -> void:
	for b in bursts:
		var t: float = b["age"] / LIFE[b["tier"]]  # 0 → 1
		var fade := 1.0 - t
		var s: float = SCALE[b["tier"]]
		var col: Color = b["color"]
		col.a = fade
		var pos: Vector2 = b["pos"]
		var seed: float = b["seed"]
		var hot := Color(1, 1, 1, fade * (0.7 if b["tier"] == "crit" else 0.35))
		match b["kind"]:
			"Flame":
				# tongues of fire licking outward and up
				var n := int(5 * s) + 3
				for i in n:
					var a := seed + TAU * float(i) / float(n)
					var dir := Vector2(cos(a), sin(a) - 0.5).normalized()
					var d := 70.0 * s * (1.0 - pow(1.0 - t, 2.0))
					for k in 3:
						var p := pos + dir * (d * (0.4 + 0.3 * k))
						draw_circle(p, (13.0 - 3.5 * k) * s * fade, col)
				draw_circle(pos, 20.0 * s * fade, hot)
			"Wave":
				# ripples racing outward
				for k in 3:
					var rt := clampf(t * 1.5 - k * 0.18, 0.0, 1.0)
					if rt <= 0.0:
						continue
					var c := col
					c.a = fade * (1.0 - rt) * 0.9
					draw_arc(pos, 100.0 * s * rt, 0.0, TAU, 40, c, 4.0 * s * (1.0 - rt * 0.5))
			"Bolt":
				# jagged lightning forks
				var n := int(3 * s) + 2
				for i in n:
					var a := seed + TAU * float(i) / float(n)
					var pts := PackedVector2Array([pos])
					var reach := 110.0 * s * minf(t * 2.2, 1.0)
					for k in range(1, 5):
						var f := float(k) / 4.0
						var perp := Vector2(-sin(a), cos(a)) * sin(f * 9.0 + seed) * 16.0 * s
						pts.append(pos + Vector2(cos(a), sin(a)) * reach * f + perp)
					draw_polyline(pts, col, 3.0 * s)
				draw_circle(pos, 16.0 * s * fade, hot)
			"Needle":
				# thin spikes stabbing through
				var n := int(2 * s) + 2
				for i in n:
					var a := seed + PI * float(i) / float(n)
					var dir := Vector2(cos(a), sin(a))
					var d := 120.0 * s * (0.5 + 0.5 * t)
					draw_line(pos - dir * d * 0.5, pos + dir * d, col, 2.5)
				draw_circle(pos, 8.0 * s * fade, hot)
			"Cure":
				# little plus signs floating up
				var n := int(4 * s) + 3
				for i in n:
					var a := seed + TAU * float(i) / float(n)
					var p := pos + Vector2(cos(a) * 46.0 * s, sin(a) * 20.0 - 60.0 * t) * (0.4 + t)
					var r := 9.0 * s * fade
					draw_line(p - Vector2(r, 0), p + Vector2(r, 0), col, 3.0)
					draw_line(p - Vector2(0, r), p + Vector2(0, r), col, 3.0)
			"Attack+":
				# chevrons surging upward
				for k in 3:
					var y := 30.0 - 70.0 * t - k * 26.0 * s
					var w := 34.0 * s
					var c := col
					c.a = fade * (1.0 - k * 0.25)
					draw_polyline(PackedVector2Array([
						pos + Vector2(-w, y + 16), pos + Vector2(0, y), pos + Vector2(w, y + 16),
					]), c, 4.0)
			"Defense+":
				# a hexagonal shield snapping shut
				var r := 90.0 * s * (1.0 - 0.55 * t)
				var pts := PackedVector2Array()
				for i in 7:
					var a := -PI / 2.0 + TAU * float(i) / 6.0
					pts.append(pos + Vector2(cos(a), sin(a)) * r)
				draw_polyline(pts, col, 4.0 * s)
			_:
				# generic burst (parries, unknown spells)
				var n := int(8 * s) + 4
				var d := 90.0 * s * (1.0 - pow(1.0 - t, 2.0))
				for i in n:
					var a := seed + TAU * float(i) / float(n)
					var dir := Vector2(cos(a), sin(a))
					draw_line(pos + dir * d * 0.45, pos + dir * d, col, 3.0)
				draw_circle(pos, 18.0 * s * fade, hot)
