extends CanvasLayer
## Reusable full-screen selection menu. ↑/↓ (or ←/→) moves the cursor,
## SPACE confirms. Every menu in the game goes through this — one control
## scheme everywhere. The hovered option's description shows below the list.

signal chosen(index: int)

var options: Array = []  # [{ "label": String, "desc": String }]
var cursor := 0
var active := false

@onready var title_label: Label = $Title
@onready var list_label: Label = $List
@onready var desc_label: Label = $Desc
@onready var hint_label: Label = $Hint

func open(title: String, opts: Array, start := 0) -> void:
	options = opts
	cursor = clampi(start, 0, maxi(opts.size() - 1, 0))
	title_label.text = title
	hint_label.text = "↑ ↓  choose      SPACE  confirm"
	active = true
	visible = true
	_refresh()

func close() -> void:
	active = false
	visible = false

func _refresh() -> void:
	var lines := PackedStringArray()
	for i in options.size():
		lines.append(("▶   " if i == cursor else "      ") + str(options[i]["label"]))
	list_label.text = "\n\n".join(lines)
	desc_label.text = str(options[cursor].get("desc", "")) if not options.is_empty() else ""

func _unhandled_input(event: InputEvent) -> void:
	if not active or options.is_empty():
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		cursor = (cursor + 1) % options.size()
		_refresh()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		cursor = (cursor - 1 + options.size()) % options.size()
		_refresh()
	elif event.is_action_pressed("ui_accept"):
		# Swallow the event — otherwise the same SPACE leaks into whatever
		# screen this menu resolves into and picks something instantly
		get_viewport().set_input_as_handled()
		close()
		chosen.emit(cursor)
