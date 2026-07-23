extends Node
## ESC pauses/unpauses the whole battle (tree pause freezes music, timers,
## tweens and input everywhere else). This node's process_mode is ALWAYS,
## so it keeps listening while everything else is frozen.
## While paused, M returns to the main menu.

@onready var label: Label = $"../UI/PauseLabel"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		var tree := get_tree()
		tree.paused = not tree.paused
		label.visible = tree.paused
	elif get_tree().paused and event is InputEventKey and event.pressed and event.keycode == KEY_M:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
