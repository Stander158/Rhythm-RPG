extends Node2D
## The cycle map: 7 columns (rounds) of nodes with connecting edges.
## Completed rows dim out, the player's current node gets a white ring,
## and selectable next nodes get numbered gold rings.

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
const TYPE_LETTERS := {
	"fight": "F", "elite": "E", "well": "W",
	"learn": "L", "chest": "C", "boss": "B",
}

var current_row := 0
var selectable: Array = []  # node indices in current_row the player may pick

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
			draw_string(font, p + Vector2(-5, 6), TYPE_LETTERS.get(t, "?"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.08, 0.08, 0.12, col.a))
			# where you stand
			if i == current_row - 1 and j == GameState.map_pos:
				draw_arc(p, NODE_R + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)
			# where you can go (numbered)
			if i == current_row and selectable.has(j):
				draw_arc(p, NODE_R + 4.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.2), 3.0)
				draw_string(font, p + Vector2(-4, -26), str(selectable.find(j) + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.2))
