extends Node2D
## Main menu: pick a lifeline to start a new run, or enter calibration mode
## (no enemy — just the beat, for tuning BPM and offsets in peace).

@onready var options: Label = $UI/Options

func _ready() -> void:
	options.text = (
		"1.   New Run  —  LIFE HEARTS\n\n"
		+ "2.   New Run  —  WILLPOWER\n\n"
		+ "3.   Calibration Mode   (no enemy; tune BPM / offsets)\n\n\n"
		+ "input offset %.0f ms   ·   music offset %.0f ms" % [
			GameState.input_offset * 1000.0, GameState.music_offset * 1000.0]
	)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_start_run("hearts")
		KEY_2:
			_start_run("willpower")
		KEY_3:
			GameState.calibration = true
			get_tree().change_scene_to_file("res://scenes/main.tscn")

func _start_run(mode: String) -> void:
	GameState.calibration = false
	GameState.reset_run()
	GameState.set_life_mode(mode)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
