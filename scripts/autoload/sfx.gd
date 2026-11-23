extends Node
## Plays sound effects and music if the files exist (see asset_requests/). Silent otherwise.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

var _players: Array[AudioStreamPlayer] = []
var _music := AudioStreamPlayer.new()
var _cache: Dictionary = {}
var _current_music: String = ""


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(_music)


func _stream(dir: String, sound_name: String) -> AudioStream:
	var key := dir + sound_name
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	for ext in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(key + ext):
			s = load(key + ext)
			break
	_cache[key] = s
	return s


func play(sound_name: String) -> void:
	var s := _stream(SFX_DIR, sound_name)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = linear_to_db(maxf(0.001, float(Profile.setting("sfx"))))
			p.play()
			return


func music(track: String) -> void:
	if track == _current_music:
		return
	_current_music = track
	var s := _stream(MUSIC_DIR, track)
	_music.stop()
	if s:
		_music.stream = s
		_music.volume_db = linear_to_db(maxf(0.001, float(Profile.setting("music"))))
		_music.play()
