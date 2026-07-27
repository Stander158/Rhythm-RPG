extends Node2D
## Main menu — same cursor-driven SelectMenu as everything else.

@onready var select_menu: CanvasLayer = $SelectMenu
@onready var fader: ColorRect = $FaderLayer/Rect

func _ready() -> void:
	MusicLibrary.rescan()  # pick up freshly dropped tracks
	select_menu.chosen.connect(_on_chosen)
	fader.color.a = 1.0
	create_tween().tween_property(fader, "color:a", 0.0, 0.4)
	_open()

func _open(start := 0) -> void:
	select_menu.open("RHYTHM  RPG", [
		{ "label": "New Run  —  Life Hearts",
		  "desc": "3 hearts. A hit at 0 HP burns one and restores you to full." },
		{ "label": "New Run  —  Willpower",
		  "desc": "A ticking clock gauge. Hits at 0 HP burn it double. When it cracks, no more readings…" },
		{ "label": "Calibration Mode",
		  "desc": "No enemy. All spells unlocked. Tune input offset and each track's BPM / delay." },
		{ "label": "Music Folder",
		  "desc": "%d track(s) in the library. Drop mp3 / ogg / wav here — battles shuffle them." % MusicLibrary.tracks.size() },
		{ "label": "Quit", "desc": "Close the game." },
	], start)

func _on_chosen(i: int) -> void:
	match i:
		0, 1:
			GameState.calibration = false
			GameState.reset_run()
			GameState.set_life_mode("hearts" if i == 0 else "willpower")
			_fade_to_battle()
		2:
			GameState.calibration = true
			_fade_to_battle()
		3:
			OS.shell_open(ProjectSettings.globalize_path(MusicLibrary.MUSIC_DIR))
			_open(3)
		4:
			get_tree().quit()

func _fade_to_battle() -> void:
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
