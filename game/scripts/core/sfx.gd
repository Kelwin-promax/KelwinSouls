# Autoload "Sfx": efeitos sonoros 2D/3D, ambiência e música com crossfade.
extends Node

const LOOPS := ["fire_loop", "wind_loop", "music_explore", "music_boss"]

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _current_music := ""
var music_volume_db := -8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dir := DirAccess.open("res://assets/audio")
	if dir:
		for f in dir.get_files():
			var base := f.get_basename()
			if f.ends_with(".wav") or f.ends_with(".wav.import"):
				base = f.replace(".wav.import", "").replace(".wav", "")
				if not _streams.has(base):
					var s = load("res://assets/audio/%s.wav" % base)
					if s:
						_streams[base] = s
						if base in LOOPS and s is AudioStreamWAV:
							s.loop_mode = AudioStreamWAV.LOOP_FORWARD
							s.loop_begin = 0
							s.loop_end = int(s.get_length() * s.mix_rate)
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new(); add_child(_music_a)
	_music_b = AudioStreamPlayer.new(); add_child(_music_b)
	_ambience = AudioStreamPlayer.new(); add_child(_ambience)


func stream(sound: String) -> AudioStream:
	return _streams.get(sound)


func play(sound: String, volume_db := 0.0, pitch_var := 0.08) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08, max_dist := 60.0) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = max_dist / 6.0
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func play_music(track: String, fade := 2.0) -> void:
	if track == _current_music:
		return
	_current_music = track
	var old := _music_a if _music_a.playing else _music_b
	var nxt := _music_b if old == _music_a else _music_a
	var tw := create_tween().set_parallel(true)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.chain().tween_callback(old.stop)
	if track != "" and _streams.has(track):
		nxt.stream = _streams[track]
		nxt.volume_db = -60.0
		nxt.play()
		var tw2 := create_tween()
		tw2.tween_property(nxt, "volume_db", music_volume_db, fade)


func play_ambience(track: String, volume_db := -14.0) -> void:
	if _streams.has(track):
		_ambience.stream = _streams[track]
		_ambience.volume_db = volume_db
		_ambience.play()
