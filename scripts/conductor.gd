extends AudioStreamPlayer
## The Conductor keeps time. It counts beats at a fixed BPM, emits a `beat`
## signal every beat, and plays a click sound (higher pitch on the downbeat).
## Everything rhythm-related in the game asks the Conductor what time it is.

signal beat(beat_number: int)
signal eighth(eighth_number: int)  # twice per beat — enemy patterns use this grid

@export var bpm := 100.0
@export var count_in_beats := 8  # "get ready" beats before the battle proper

var seconds_per_beat: float
var song_time := 0.0  # seconds since the battle started
var last_beat := -1
var last_eighth := -1
var running := false

func _ready() -> void:
	seconds_per_beat = 60.0 / bpm

## Change tempo live (debug). Keeps the current position in the bar so the
## beat count doesn't jump when the seconds-per-beat mapping changes.
func set_bpm(new_bpm: float) -> void:
	new_bpm = clampf(new_bpm, 40.0, 240.0)
	var beats_elapsed := song_time / seconds_per_beat
	bpm = new_bpm
	seconds_per_beat = 60.0 / bpm
	song_time = beats_elapsed * seconds_per_beat

## Beats -8..-1 are the count-in; beat 0 is the battle's first real downbeat.
func start_beats() -> void:
	song_time = -count_in_beats * seconds_per_beat
	last_beat = -999
	last_eighth = -999
	running = true

func stop_beats() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	song_time += delta
	var current := floori(song_time / seconds_per_beat)
	if current != last_beat:
		last_beat = current
		pitch_scale = 1.5 if posmod(current, 4) == 0 else 1.0  # accent beat 1 of each bar
		play()  # the click
		beat.emit(current)
	var current_e := floori(song_time / (seconds_per_beat * 0.5))
	if current_e != last_eighth:
		last_eighth = current_e
		eighth.emit(current_e)

## How many seconds the current moment is from the NEAREST beat (before or after).
## The battle uses this to judge how accurate a key press was.
func time_to_nearest_beat() -> float:
	var into := fposmod(song_time, seconds_per_beat)  # fposmod: safe for count-in (negative time)
	return minf(into, seconds_per_beat - into)

## 0.0 exactly on a beat -> 1.0 just before the next one. Drives the beat ring.
func beat_progress() -> float:
	return fposmod(song_time, seconds_per_beat) / seconds_per_beat
