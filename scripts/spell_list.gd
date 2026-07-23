extends Node2D
## Top-left spellbook panel: name, level, and the input pattern drawn in the
## same visual language as the rhythm diamond — one small diamond per eighth
## slot. Blue diamond = charge key (arrow inside), gold = SPACE (release),
## hollow = rest.

const ROW_H := 38.0
const DIA := 9.0     # diamond half-diagonal
const SLOT_W := 24.0
const PATTERN_X := 168.0
const GLYPHS := { "L": "←", "R": "→", "U": "↑", "D": "↓" }

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y := 0.0
	for spell in SpellBook.SPELLS:
		if not GameState.known_spells.has(spell["name"]):
			continue  # unlearned spells stay hidden
		draw_string(font, Vector2(0, y + 6), spell["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		draw_string(font, Vector2(96, y + 6), "Lv%d" % GameState.get_spell_level(spell["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.75, 0.8))
		var x := PATTERN_X
		for i in spell["pattern"].length():
			var ch: String = spell["pattern"][i]
			var center := Vector2(x, y)
			var pts := PackedVector2Array([
				center + Vector2(0, -DIA), center + Vector2(DIA, 0),
				center + Vector2(0, DIA), center + Vector2(-DIA, 0),
			])
			match ch:
				"_":
					draw_polyline(pts + PackedVector2Array([pts[0]]),
						Color(1, 1, 1, 0.25), 1.5)
				"S":
					draw_colored_polygon(pts, Color(1.0, 0.85, 0.2))
				_:
					draw_colored_polygon(pts, Color(0.4, 0.75, 1.0))
					draw_string(font, center + Vector2(-6, 4), GLYPHS.get(ch, "?"),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.05, 0.1, 0.2))
			x += SLOT_W
		y += ROW_H
