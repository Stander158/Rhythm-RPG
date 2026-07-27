extends Node2D
## Enemies talking — for story, and for teaching.
##
## Two kinds of line, and they live in different places on purpose:
##
##   WAITING (pre-battle)   The clock isn't running: no music, no metronome,
##                          no fight. The player presses SPACE to turn each
##                          line. Story happens in silence, at reading speed,
##                          and nothing is ticking away while you read.
##
##   AMBIENT (mid-battle)   Auto-expires after N beats while play continues.
##                          Never takes input — the fight is live, and SPACE
##                          belongs to the player.
##
## Each kind gets the presentation it can afford. Before the fight there is no
## HUD to protect, so a wide box along the bottom reads best. Mid-fight the
## screen is busy and every element earns its place, so an ambient line
## becomes a small bubble tucked into the empty space at the enemy's shoulder
## — clear of the rhythm diamond, the bars and the charge readout.

signal finished

const MIN_BEATS := 8            # nobody reads a line mid-fight in less than this
const MAX_WIDTH := 400.0        # text column; the bubble sizes itself to fit
const PAD := Vector2(18, 14)
const ANCHOR := Vector2(672, 186)   # bubble's bottom-left, clear of every HUD element
const TAIL_TIP := Vector2(636, 214) # where the tail points: the enemy's shoulder
# Pre-battle box. Wedged into the one genuinely empty band: right of the item
# list and cast log (both end at x 400), above the HP readout (starts y 570),
# below the buff column (ends y 380). The rhythm diamond is hidden while this
# is up — there's no clock running for it to track anyway.
const BOX_RECT := Rect2(420, 424, 648, 134)
const FONT_SIZE := 19
const SPEAKER_SIZE := 15

var queue: Array = []
var beats_left := 0
var active := false
var waiting := false     # true = this line turns on SPACE, not on the beat
var speaker := ""
var body := ""

func _ready() -> void:
	visible = false

## lines: [{ "text": String, "speaker": String, "beats": int }]
## wait_for_input: story mode — the player turns each line themselves.
func play(lines: Array, wait_for_input: bool) -> void:
	queue = lines.duplicate()
	waiting = wait_for_input
	active = true
	_next()

func is_active() -> bool:
	return active

## True only while a line is waiting to be turned — the battle uses this to
## know that SPACE means "next line", not "cast".
func wants_input() -> bool:
	return active and waiting

## Player turned the page.
func advance() -> void:
	if active and waiting:
		_next()

## Ambient lines expire on beats. Waiting lines ignore this entirely.
func on_beat() -> void:
	if not active or waiting:
		return
	beats_left -= 1
	if beats_left <= 0:
		_next()

func stop() -> void:
	queue.clear()
	active = false
	waiting = false
	visible = false
	queue_redraw()

func _next() -> void:
	if queue.is_empty():
		var was_active := active
		stop()
		if was_active:
			finished.emit()
		return
	var line: Dictionary = queue.pop_front()
	speaker = str(line.get("speaker", ""))
	body = str(line.get("text", ""))
	# A line the player has to read while also playing gets a floor, whatever
	# the data asked for — the fight doesn't pause for it, so it has to linger.
	beats_left = maxi(int(line.get("beats", 0)), MIN_BEATS)
	visible = true
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	if waiting:
		_draw_box()
	else:
		_draw_bubble()

## Pre-battle: nothing else is on screen, so take the room and be readable.
func _draw_box() -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(BOX_RECT.position, BOX_RECT.size)
	draw_rect(box, Color(0.06, 0.06, 0.11, 0.94), true)
	draw_rect(Rect2(box.position, Vector2(5, box.size.y)), Color(0.85, 0.8, 0.55, 0.85), true)
	var cursor := box.position + Vector2(26, 26)
	if speaker != "":
		draw_string(font, cursor + Vector2(0, font.get_ascent(SPEAKER_SIZE + 3)),
			speaker, HORIZONTAL_ALIGNMENT_LEFT, -1,
			SPEAKER_SIZE + 3, Color(0.95, 0.88, 0.55))
		cursor.y += 28
	draw_multiline_string(font, cursor + Vector2(0, font.get_ascent(FONT_SIZE + 1)), body,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, FONT_SIZE + 1, -1,
		Color(0.92, 0.92, 0.96))
	# The only affordance that matters while the world is stopped
	var prompt := "SPACE  ▶" if queue.size() > 0 else "SPACE  begin"
	draw_string(font, Vector2(box.end.x - 118, box.end.y - 18), prompt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.55))

## Mid-fight: a small bubble at the enemy's shoulder, sized to its own text.
## Both the measuring and the drawing must agree on width, size AND baseline —
## text is drawn from its BASELINE, so offsetting by the font size instead of
## its real ascent let descenders on the last line hang out of the border.
func _draw_bubble() -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_multiline_string_size(
		body, HORIZONTAL_ALIGNMENT_LEFT, MAX_WIDTH, FONT_SIZE)
	var head := (SPEAKER_SIZE + 10.0) if speaker != "" else 0.0
	var size := Vector2(
		maxf(text_size.x, 120.0) + PAD.x * 2.0,
		text_size.y + head + PAD.y * 2.0)
	# Grow upward from the anchor, but never climb into the enemy's HP bar
	var top := maxf(ANCHOR.y - size.y, 76.0)
	var box := Rect2(Vector2(ANCHOR.x, top), Vector2(size.x, ANCHOR.y - top))
	# Tail first, so the bubble's fill covers the seam where they meet
	draw_colored_polygon(PackedVector2Array([
		box.position + Vector2(24, box.size.y - 2),
		box.position + Vector2(64, box.size.y - 2),
		TAIL_TIP,
	]), Color(0.07, 0.07, 0.12, 0.94))
	draw_rect(box, Color(0.07, 0.07, 0.12, 0.94), true)
	draw_rect(box, Color(0.85, 0.8, 0.55, 0.5), false, 2.0)
	var cursor := box.position + PAD
	if speaker != "":
		draw_string(font, cursor + Vector2(0, font.get_ascent(SPEAKER_SIZE)), speaker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, SPEAKER_SIZE, Color(0.95, 0.88, 0.55))
		cursor.y += head
	draw_multiline_string(font, cursor + Vector2(0, font.get_ascent(FONT_SIZE)), body,
		HORIZONTAL_ALIGNMENT_LEFT, MAX_WIDTH, FONT_SIZE, -1, Color(0.92, 0.92, 0.96))
