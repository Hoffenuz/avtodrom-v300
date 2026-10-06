class_name Exercise
extends RefCounted
## One exam exercise. The director activates it when the car reaches the
## exercise's stretch of route (def.s0) and keeps ticking it until it reports
## done. Penalty numbers are those of the official table (data/penalties.json).

enum State { WAITING, ACTIVE, DONE }

var id := ""
var type := ""
var def: Dictionary
var director: ExamDirector
var state: State = State.WAITING
var s0 := 0.0
var s1 := 0.0
var elapsed := 0.0
## Localisation key of what the driver should do now (shown on the HUD).
var hint_key := ""
var hint_args: Array = []
## Lines to highlight for the learner (practice mode), as course line dicts.
var highlight: Array = []
var performed := false # the manoeuvre itself was carried out
var penalties_here := 0
var _milestones := {}
## A different hint must be asked for this long before it replaces the shown
## one: the exercises pick the hint from live thresholds every tick (a car
## coming to rest flips "reversing" on and off), and without the hold the
## HUD card flickered between two texts.
const HINT_HOLD := 0.4
var _pending_key := ""
var _pending_args: Array = []
var _pending_t := 0.0


func _init(p_def: Dictionary, p_director: ExamDirector) -> void:
	def = p_def
	director = p_director
	id = str(def["id"])
	type = str(def["type"])
	s0 = float(def["s0"])
	s1 = float(def["s1"])


func title() -> String:
	return Loc.pick(def.get("name", {}))


func begin() -> void:
	state = State.ACTIVE
	elapsed = 0.0
	_on_begin()


func tick(dt: float, p: CarProbe) -> void:
	elapsed += dt
	if _pending_key != "":
		_pending_t += dt
	_tick(dt, p)


func finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	_on_finish()
	# Clean and carried out: tell the learner (not for the start, whose
	# "exercise" is only pulling away, nor each intersection pass).
	if performed and penalties_here == 0 and type not in ["start", "intersection"]:
		milestone("done.exercise", [title()])


## Tells the learner a step went right (HUD banner + chime), once per key.
func milestone(key: String, args: Array = []) -> void:
	if _milestones.has(key):
		return
	_milestones[key] = true
	director.milestone.emit(Loc.t(key, args))


## Called when the car has moved past s1 without the exercise finishing
## itself. Default: finish (subclasses decide whether that means "skipped").
func passed_without_finish() -> void:
	finish()


func penalize(no: int, detail := "") -> void:
	penalties_here += 1
	director.add_penalty(no, id, detail)


func set_hint(key: String, args: Array = []) -> void:
	if key == hint_key:
		_pending_key = ""
		if args != hint_args: # a countdown ticking: show at once
			_show_hint(key, args)
		return
	# The first hint, anything once the exercise is over, and the traffic
	# light's (it changes cleanly, and late would be wrong) show at once.
	if hint_key == "" or state != State.ACTIVE or key.begins_with("hint.light_"):
		_pending_key = ""
		_show_hint(key, args)
		return
	if key != _pending_key:
		_pending_key = key
		_pending_t = 0.0
	_pending_args = args
	if _pending_t >= HINT_HOLD:
		_pending_key = ""
		_show_hint(key, args)


func _show_hint(key: String, args: Array) -> void:
	hint_key = key
	hint_args = args
	director.hint_changed.emit()


## Rules the director should relax while this exercise is active.
func allows_reverse() -> bool:
	return false


func suspends_speed_limit() -> bool:
	return false


## Free manoeuvring area (route deviation is not "leaving the route" here).
func free_area() -> Array:
	return def.get("zone", [])


func _on_begin() -> void:
	pass


func _tick(_dt: float, _p: CarProbe) -> void:
	pass


func _on_finish() -> void:
	pass
