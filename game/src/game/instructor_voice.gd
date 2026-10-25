class_name InstructorVoice
extends Node
## The instructor's voice: recorded lines for the exam's moments (the
## director's cue signal). A line is res://audio/voice/<uz|ru>/<key>.ogg (or
## .wav); a key with no recording is skipped, the HUD still shows its text.
## The list of lines to record is docs/VOICE_LINES.md.

const DIR := "res://audio/voice/%s/%s.%s"
## A line still waiting this long after its moment is stale: dropped.
const STALE_S := 3.0
const QUEUE_MAX := 3

var _player: AudioStreamPlayer
var _queue: Array = [] # [stream, time queued, penalty]
var _lang := "uz"
var _cache := {}


func _ready() -> void:
	_lang = "ru" if Settings.get_value("language") == "ru" else "uz"
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_next)


func listen(director: ExamDirector) -> void:
	director.cue.connect(say)
	# Read now, behind the loading page, not from the pack mid-drive.
	var keys := ["start", "emergency", "end_passed", "end_failed", "end_finished", "end_practice",
			"done_hold", "done_box_parked", "done_parallel_parked", "done_exercise"]
	for ex in director.exercises:
		keys.append("ex_" + ex.id.rstrip("0123456789"))
	for no in range(1, 33):
		keys.append("pen_%d" % no)
	for k in keys:
		_stream(k)


func say(key: String) -> void:
	if not Settings.get_value("voice"):
		return
	var stream := _stream(key)
	if stream == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var penalty := key.begins_with("pen_")
	if penalty:
		# A penalty matters more than the line about to be said.
		_queue = _queue.filter(func(q: Array) -> bool: return q[2])
	if _queue.size() >= QUEUE_MAX:
		return
	_queue.append([stream, now, penalty])
	if not _player.playing:
		_next()


func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = null
	for ext in ["ogg", "wav"]:
		var path := DIR % [_lang, key, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	_cache[key] = stream
	return stream


func _next() -> void:
	var now := Time.get_ticks_msec() * 0.001
	while not _queue.is_empty():
		var q: Array = _queue.pop_front()
		if now - float(q[1]) > STALE_S:
			continue
		_player.stream = q[0]
		_player.volume_db = linear_to_db(maxf(0.001, float(Settings.get_value("vol_master")) * float(Settings.get_value("vol_effects")))) + 2.0
		_player.play()
		return
