extends Node

const MUSIC_PATH: String = "res://music.mp3"

var _player: AudioStreamPlayer

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.process_mode = PROCESS_MODE_ALWAYS
	add_child(_player)

	if ResourceLoader.exists(MUSIC_PATH):
		_player.stream = load(MUSIC_PATH) as AudioStream

	_player.finished.connect(_on_music_finished)
	_ensure_playing()

func _ensure_playing() -> void:
	if _player == null or _player.stream == null:
		return
	if not _player.playing:
		_player.play()

func _on_music_finished() -> void:
	# Some stream types don't support looping; restarting on finish is reliable.
	_ensure_playing()
