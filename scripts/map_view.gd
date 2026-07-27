extends Node2D
## The cycle map: 7 columns (rounds) of nodes with connecting edges.
## Navigation is cursor-based: the hovered node glows and shows a tooltip
## explaining what it is — no legend to cross-reference.

const COL_W := 92.0
const ROW_SPREAD := 64.0
const NODE_R := 16.0
const TYPE_COLORS := {
	"fight": Color(0.75, 0.55, 0.4),
	"elite": Color(0.9, 0.35, 0.35),
	"well": Color(0.5, 0.75, 1.0),
	"learn": Color(0.6, 0.9, 0.5),
	"chest": Color(1.0, 0.85, 0.3),
	"boss": Color(0.95, 0.3, 0.55),
}
const TYPE_TOOLTIPS := {
	"fight": "Fight",
	"elite": "Strong Enemy",
	"well": "Willpower Well",
	"learn": "Learn a Spell",
	"chest": "Treasure Chest",
	"boss": "BOSS",
}

var current_row := 0
var selectable: Array = []  # node indices in current_row the player may pick
var hover := -1             # the selectable node the cursor is on
var show_ring_node := false # first cycle: draw the PRELUDE node at column -1
var hover_ring := false     # cursor is on the prelude node

func _process(_delta: float) -> void:
	queue_redraw()

func _node_pos(row: int, idx: int, count: int) -> Vector2:
	return Vector2(row * COL_W, (float(idx) - (count - 1) * 0.5) * ROW_SPREAD)

func _draw() -> void:
	var rounds: Array = GameState.map_rounds
	if rounds.is_empty():
		return
	var font := ThemeDB.fallback_font
	# edges first, nodes on top
	for i in rounds.size() - 1:
		var a: Array = rounds[i]
		for j in a.size():
			for k in a[j]["edges"]:
				var col := Color(1, 1, 1, 0.10 if i < current_row else 0.28)
				draw_line(_node_pos(i, j, a.size()),
					_node_pos(i + 1, k, rounds[i + 1].size()), col, 2.0)
	for i in rounds.size():
		var row: Array = rounds[i]
		for j in row.size():
			var p := _node_pos(i, j, row.size())
			var t: String = row[j]["type"]
			var col: Color = TYPE_COLORS.get(t, Color.WHITE)
			if i < current_row:
				col.a = 0.25  # already behind you
			draw_circle(p, NODE_R, col)
			_draw_icon(t, p, col.a)
			# where you stand
			if i == current_row - 1 and j == GameState.map_pos:
				draw_arc(p, NODE_R + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)
			# reachable this round: gold ring; the hovered one pulses bigger
			if i == current_row and selectable.has(j):
				if j == hover:
					draw_arc(p, NODE_R + 6.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.2), 4.0)
				else:
					draw_arc(p, NODE_R + 3.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.2, 0.5), 2.0)
	# The PRELUDE node at column -1, wired into every entry node
	if show_ring_node:
		var rp := _node_pos(-1, 0, 1)
		var visited: bool = GameState.character != ""
		var a := 0.25 if visited else 1.0
		for k in rounds[0].size():
			draw_line(rp, _node_pos(0, k, rounds[0].size()),
				Color(1, 1, 1, 0.10 if visited else 0.28), 2.0)
		var ccol: Color = TYPE_COLORS["chest"]
		ccol.a = a
		draw_circle(rp, NODE_R, ccol)
		_draw_icon("chest", rp, a)
		if not visited:
			draw_arc(rp, NODE_R + 6.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.2), 4.0)
	# hovered node's name — fixed box at the bottom-right, above the version tag
	if hover_ring:
		_draw_tooltip(font, "Prelude")
	elif hover >= 0 and current_row < rounds.size():
		var row: Array = rounds[current_row]
		if hover < row.size():
			_draw_tooltip(font, TYPE_TOOLTIPS.get(row[hover]["type"], ""))

func _draw_tooltip(font: Font, tip: String) -> void:
	var box_pos := Vector2(500, 266)  # screen ~ (870, 566), above the version tag
	draw_rect(Rect2(box_pos, Vector2(240, 38)), Color(0.07, 0.07, 0.12, 0.92))
	draw_rect(Rect2(box_pos, Vector2(240, 38)), Color(1.0, 0.85, 0.2, 0.6), false, 1.5)
	draw_string(font, box_pos + Vector2(0, 26), tip,
		HORIZONTAL_ALIGNMENT_CENTER, 240, 17, Color.WHITE)

## Tiny vector icons — readable at a glance, no legend needed.
func _draw_icon(t: String, p: Vector2, alpha: float) -> void:
	var ink := Color(0.08, 0.08, 0.12, alpha)
	match t:
		"fight":  # single sword
			draw_line(p + Vector2(-6, 7), p + Vector2(6, -7), ink, 2.5)
			draw_line(p + Vector2(-1, -5), p + Vector2(-6, -1), ink, 2.5)
			draw_circle(p + Vector2(-7, 8), 2.0, ink)
		"elite":  # crossed swords
			draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), ink, 2.5)
			draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), ink, 2.5)
		"well":  # water droplet
			draw_circle(p + Vector2(0, 3), 5.5, ink)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -9), p + Vector2(-5, 2), p + Vector2(5, 2)]), ink)
		"learn":  # open book
			draw_rect(Rect2(p + Vector2(-8, -5), Vector2(7, 11)), ink)
			draw_rect(Rect2(p + Vector2(1, -5), Vector2(7, 11)), ink)
			draw_line(p + Vector2(0, -7), p + Vector2(0, 7), ink, 1.5)
		"chest":  # treasure box with a lid seam and lock
			draw_rect(Rect2(p + Vector2(-8, -6), Vector2(16, 12)), ink)
			draw_line(p + Vector2(-8, -1), p + Vector2(8, -1), Color(1, 1, 1, alpha * 0.7), 1.5)
			draw_circle(p + Vector2(0, 2), 2.0, Color(1, 1, 1, alpha * 0.7))
		"boss":  # skull
			draw_circle(p + Vector2(0, -2), 7.0, ink)
			draw_rect(Rect2(p + Vector2(-4, 3), Vector2(8, 5)), ink)
			draw_circle(p + Vector2(-3, -3), 1.8, Color(1, 1, 1, alpha))
			draw_circle(p + Vector2(3, -3), 1.8, Color(1, 1, 1, alpha))
