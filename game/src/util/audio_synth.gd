class_name AudioSynth
extends RefCounted
## Small procedural sound effects (no audio files needed): relay clicks for
## the indicators, the seat-belt chime, the emergency beeper, tyre squeal and
## scrub, and impact thumps. Generated once and cached.

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


## Tyre squeal loop: white noise rung through three narrow, inharmonic
## resonances whose pitch and strength wander slowly, like a tread block
## stick-slipping on asphalt. (A plain sine sounds like a whistle.)
static func squeal() -> AudioStreamWAV:
	if _cache.has("squeal"):
		return _cache["squeal"]
	var xf := int(RATE * 0.15)
	var n := int(RATE * 1.5) + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var r := _rng()
	var freqs := [780.0, 1180.0, 1590.0]
	var gains := [1.0, 0.7, 0.45]
	var bq: Array[_Biquad] = []
	var drift := []
	for k in 3:
		bq.append(_Biquad.new())
		drift.append(0.0)
	var hiss := _Biquad.new()
	hiss.bandpass(3200.0, 0.8, RATE)
	var chatter := 0.0
	var chatter_target := 0.0
	for i in n:
		if i % 32 == 0:
			for k in 3:
				# Slow random walk of each resonance, about ±4 %.
				drift[k] = clampf(drift[k] + r.randf_range(-1.0, 1.0) * 0.004, -0.04, 0.04)
				bq[k].bandpass(freqs[k] * (1.0 + drift[k]), 28.0, RATE)
			if i % 640 == 0:
				chatter_target = r.randf()
		chatter += (chatter_target - chatter) * 0.0015
		var x := r.randf_range(-1.0, 1.0)
		var y := 0.0
		for k in 3:
			y += bq[k].tick(x) * gains[k]
		s[i] = y * (0.6 + 0.4 * chatter) + hiss.tick(x) * 0.05
	_cache["squeal"] = _wav(_seamless(_normalize(s, 0.8), xf), true)
	return _cache["squeal"]


## Rubber scrub loop: the dull, gritty rasp of a locked or sliding tyre at
## low speed (handbrake turns, parking-speed skids).
static func scrub() -> AudioStreamWAV:
	if _cache.has("scrub"):
		return _cache["scrub"]
	var xf := int(RATE * 0.1)
	var n := int(RATE * 1.5) + xf
	var s := PackedFloat32Array()
	s.resize(n)
	var r := _rng()
	var body := _Biquad.new()
	body.bandpass(360.0, 1.1, RATE)
	var grit := _Biquad.new()
	grit.bandpass(1100.0, 2.0, RATE)
	var grain := 0.0
	for i in n:
		var x := r.randf_range(-1.0, 1.0)
		# Sparse grains (~80/s) give the texture of rubber tearing over grit.
		if r.randf() < 80.0 / RATE:
			grain = r.randf_range(0.5, 1.0)
		grain *= 0.994
		s[i] = body.tick(x) * (0.7 + grain) + grit.tick(x * grain) * 0.5
	_cache["scrub"] = _wav(_seamless(_normalize(s, 0.8), xf), true)
	return _cache["scrub"]


## Scales a buffer so its peak is `peak`.
static func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0:
		for i in s.size():
			s[i] *= peak / m
	return s


## Turns a buffer into a click-free loop: the last `xf` samples are
## cross-faded (equal power) into the first `xf` and then dropped.
static func _seamless(s: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := s.size() - xf
	var out := s.slice(0, n)
	for i in xf:
		var a := float(i) / xf
		out[i] = s[i] * sqrt(a) + s[n + i] * sqrt(1.0 - a)
	return out


## RBJ band-pass biquad (constant 0 dB peak gain).
class _Biquad:
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func bandpass(freq: float, q: float, rate: float) -> void:
		var w := TAU * freq / rate
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func tick(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


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
