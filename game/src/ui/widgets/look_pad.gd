class_name LookPad
extends Control
## Transparent layer under all HUD controls. One finger (or the mouse, which
## the project turns into touches) drags the camera round; two fingers pinch
## to zoom; the mouse wheel zooms too.

signal dragged(delta: Vector2)
signal released
signal zoomed(factor: float)

var _touches := {} # finger index -> last position
## Fingers that landed while a driving control was held: they never turn the
## camera (see hold_check), whatever they do afterwards.
var _ignored := {}
## Returns true while the player holds the wheel, a pedal or a steering
## button. A second finger then (the palm, a finger that missed a pedal, a
## thumb resting on the glass) must not swing the view round mid-drive -
## the old behaviour, and the most common complaint about the touch controls.
var hold_check: Callable


func _held() -> bool:
	return hold_check.is_valid() and bool(hold_check.call())


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _held():
				_ignored[event.index] = true
		elif _touches.has(event.index):
			_touches.erase(event.index)
			_ignored.erase(event.index)
			if _touches.is_empty():
				released.emit()
		accept_event()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		if _ignored.has(event.index) or _held():
			_touches[event.index] = event.position
			accept_event()
			return
		if _touches.size() >= 2:
			var other: int = -1
			for k in _touches:
				if k != event.index:
					other = k
					break
			var before: float = (_touches[event.index] as Vector2).distance_to(_touches[other])
			var after: float = event.position.distance_to(_touches[other])
			if before > 20.0 and after > 20.0:
				zoomed.emit(before / after) # fingers apart -> closer
		else:
			dragged.emit(event.relative)
		_touches[event.index] = event.position
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomed.emit(0.9)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomed.emit(1.1)
			accept_event()


func _notification(what: int) -> void:
	# A finger lifted outside the window must not leave a stuck drag behind.
	if what == NOTIFICATION_MOUSE_EXIT_SELF or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not _touches.is_empty() and not is_visible_in_tree():
			_touches.clear()
			_ignored.clear()
			released.emit()
