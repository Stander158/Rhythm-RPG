extends Node
## User music library (autoload). Drop tracks (mp3/ogg/wav) into
## user://music/ — on Windows that's %APPDATA%\Godot\app_userdata\First Game\music\.
## Each track carries its own bpm + phase offset, stored in library.json and
## tuned in calibration mode. Battles pick a random track.

const MUSIC_DIR := "user://music"
const CONFIG_PATH := "user://music/library.json"
const BUILTIN := "res://audio/bgm_keycard.mp3"  # present locally, not in the repo
const BUILTIN_KEY := "__builtin__"

var tracks: Array = []  # { "name": display, "path": file path, "bpm": float, "offset": float }

func _ready() -> void:
	rescan()

## Re-read the folder; new files get default settings (bpm 120, offset 0).
func rescan() -> void:
	DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
	var config := {}
	if FileAccess.file_exists(CONFIG_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary:
			config = data
	tracks.clear()
	if ResourceLoader.exists(BUILTIN):
		var c: Dictionary = config.get(BUILTIN_KEY, {})
		tracks.append({ "name": "Keycard (built-in)", "path": BUILTIN,
			"bpm": float(c.get("bpm", 118.0)), "offset": float(c.get("offset", 0.09)) })
	for f in DirAccess.get_files_at(MUSIC_DIR):
		if f.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			var c2: Dictionary = config.get(f, {})
			tracks.append({ "name": f, "path": MUSIC_DIR + "/" + f,
				"bpm": float(c2.get("bpm", 120.0)), "offset": float(c2.get("offset", 0.0)) })
	save_config()

func save_config() -> void:
	var config := {}
	for t in tracks:
		var key: String = BUILTIN_KEY if t["path"] == BUILTIN else t["name"]
		config[key] = { "bpm": t["bpm"], "offset": t["offset"] }
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(config, "\t"))

func random_track() -> Dictionary:
	return tracks.pick_random() if not tracks.is_empty() else {}

## Build a playable stream from a track entry (runtime-loaded, so user files
## outside the project just work).
func load_stream(track: Dictionary) -> AudioStream:
	if track.is_empty():
		return null
	var path: String = track["path"]
	if path.begins_with("res://"):
		var s = load(path)
		if s:
			s.loop = true
		return s
	match path.get_extension().to_lower():
		"mp3":
			var s := AudioStreamMP3.load_from_file(path)
			if s:
				s.loop = true
			return s
		"ogg":
			var s := AudioStreamOggVorbis.load_from_file(path)
			if s:
				s.loop = true
			return s
		"wav":
			return AudioStreamWAV.load_from_file(path)  # wav: no loop for now
	return null
