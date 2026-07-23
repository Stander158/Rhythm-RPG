extends Node
## ESC pauses/unpauses the whole battle (tree pause freezes music, timers,
## tweens and input everywhere else). This node's process_mode is ALWAYS,
## so it keeps listening while everything else is frozen.

@onready var label: Label = $"../UI/PauseLabel"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		var tree := get_tree()
		tree.paused = not tree.paused
		label.visible = tree.paused
