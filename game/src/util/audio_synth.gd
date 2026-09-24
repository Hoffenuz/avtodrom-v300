class_name AudioSynth
extends RefCounted
## Small procedural sound effects (no audio files needed): relay clicks for
## the indicators, the seat-belt chime, the emergency beeper, tyre squeal and
## impact thumps. Generated once and cached.

const RATE := 32000

static var _cache := {}


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	return r


## Indicator relay: a sharp click with a short resonant body.
static func relay_click(pitch := 1.0) -> AudioStreamWAV:
	var key := "click%.2f" % pitch
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * 0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	var r := _rng()
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 380.0)
		s[i] = (r.randf_range(-1, 1) * 0.6 + sin(TAU * 1900.0 * pitch * t) * 0.5) * env * 0.8
	_cache[key] = _wav(s)
	return _cache[key]


## Two-tone chime (seat-belt reminder, exercise start).
static func chime(f1 := 880.0, f2 := 660.0) -> AudioStreamWAV:
	var key := "chime%d_%d" % [f1, f2]
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := f1 if t < 0.25 else f2
		var tt := t if t < 0.25 else t - 0.25
		var env := exp(-tt * 7.0) * minf(1.0, tt * 400.0)
		s[i] = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.15) * env * 0.5
	_cache[key] = _wav(s)
	return _cache[key]


## Continuous beeper for the emergency-stop signal (looping, 2.5 Hz pulses).
static func beeper() -> AudioStreamWAV:
	if _cache.has("beeper"):
		return _cache["beeper"]
	var n := int(RATE * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gate := 1.0 if t < 0.22 else 0.0
		s[i] = sin(TAU * 1250.0 * t) * 0.45 * gate * minf(1.0, t * 300.0)
	_cache["beeper"] = _wav(s, true)
	return _cache["beeper"]


## Band-limited noise loop for tyre squeal / scrub.
static func squeal() -> AudioStreamWAV:
	if _cache.has("squeal"):
		return _cache["squeal"]
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var r := _rng()
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := r.randf_range(-1, 1)
		lp += (x - lp) * 0.25
		hp = lp - hp * 0.2
		var tone := sin(TAU * 1150.0 * t + sin(TAU * 7.0 * t) * 2.0) * 0.35
		s[i] = (hp * 0.5 + tone) * 0.5
	_cache["squeal"] = _wav(s, true)
	return _cache["squeal"]


## Dull impact.
static func thump() -> AudioStreamWAV:
	if _cache.has("thump"):
		return _cache["thump"]
	var n := int(RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var r := _rng()
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (r.randf_range(-1, 1) - lp) * 0.05
		s[i] = (sin(TAU * 70.0 * t) * 0.8 + lp * 2.0) * exp(-t * 14.0)
	_cache["thump"] = _wav(s)
	return _cache["thump"]


## UI tick.
static func tick() -> AudioStreamWAV:
	if _cache.has("tick"):
		return _cache["tick"]
	var n := int(RATE * 0.04)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * 2600.0 * t) * exp(-t * 160.0) * 0.4
	_cache["tick"] = _wav(s)
	return _cache["tick"]
