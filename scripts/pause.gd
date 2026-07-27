extends Node
## ESC opens a full-screen pause menu (tree pause freezes everything else).
## This node runs in PROCESS_MODE_ALWAYS, so it — and its child menu —
## keep working while the game is frozen.

@onready var menu: CanvasLayer = $PauseMenu

func _ready() -> void:
	menu.chosen.connect(_on_chosen)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):  # ESC
		return
	get_viewport().set_input_as_handled()
	# Practice has nothing to pause — ESC simply ends it and the run goes on.
	var host := get_parent()
	if host.has_method("is_training") and host.is_training():
		host.end_training()
		return
	var tree := get_tree()
	if tree.paused:
		tree.paused = false
		menu.close()
	else:
		tree.paused = true
		menu.open("PAUSED", [
			{ "label": "Resume", "desc": "Back to the fight." },
			{ "label": "Return to Menu", "desc": "Leave the battle. Run progress is kept." },
		])

func _on_chosen(i: int) -> void:
	get_tree().paused = false
	if i == 1:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
