class_name ExBox
extends Exercise
## №4 "Boksga kirish" (turn-round using the box). Drive into the dead-end
## pad, reverse into the side bay until the rear wheels reach the fixation
## line, then drive out forwards and leave the way you came. The position is
## judged at the last stop in the bay before the car drives out of it.
##   penalties: 17 (rear wheels not on the fixation line), 27 (not performed)

enum Phase { ENTER, IN_BAY, LEAVING }

const FIX_TOUCH := 0.06 + 0.0925 # line half-width + tyre half-width
const STABLE_STOP := 0.8

var phase: Phase = Phase.ENTER
var bay := PackedVector2Array()
var fix_line: Dictionary
var bay_travel := Vector2.ZERO
var last_ok := false
var judged := false


func _on_begin() -> void:
	bay = CourseData.poly(def["bay"])
	fix_line = def["fixation_line"]
	bay_travel = CourseData.forward2(float(def["bay_heading"]))
	highlight = [fix_line]
	set_hint("hint.box_enter")


func allows_reverse() -> bool:
	return true


func _rear_wheels_at_line(p: CarProbe) -> bool:
	# The car faces out of the bay; its rear wheels must be on or beyond the
	# fixation line behind it.
	for i in [2, 3]:
		var beyond := -Geo.past(fix_line, bay_travel, p.wheels[i])
		if beyond < -FIX_TOUCH:
			return false
	return true


func _in_bay(p: CarProbe) -> bool:
	return Geometry2D.is_point_in_polygon(p.rear, bay) and p.heading_error_deg(float(def["bay_heading"])) < 35.0


func _tick(_dt: float, p: CarProbe) -> void:
	match phase:
		Phase.ENTER:
			if _in_bay(p):
				set_hint("hint.box_fix")
				if p.stopped_time > STABLE_STOP:
					phase = Phase.IN_BAY
					performed = true
			elif p.reversing:
				set_hint("hint.box_reverse")
			else:
				set_hint("hint.box_enter")
		Phase.IN_BAY:
			if _in_bay(p) and p.stopped_time > STABLE_STOP:
				last_ok = _rear_wheels_at_line(p)
				set_hint("hint.box_leave" if last_ok else "hint.box_fix")
			if not Geometry2D.is_point_in_polygon(p.rear, bay) and p.speed > 0.2:
				_judge()
				phase = Phase.LEAVING
		Phase.LEAVING:
			set_hint("hint.box_leave")
			var entry: Dictionary = def["entry_line"]
			if Geo.past(entry, Vector2(0, -1), p.rear) > 0.5:
				finish()


func _judge() -> void:
	if judged:
		return
	judged = true
	if not last_ok:
		penalize(17)


func passed_without_finish() -> void:
	if not performed:
		penalize(27, id)
	else:
		_judge()
	finish()
