class_name IconButton
extends Control
## Round cabin switch with a vector icon. Reports press / release (the
## ignition key needs "hold"), lights up in `lit_color` when `lit`.

signal pressed_down
signal released
signal tapped

@export var icon := "left"
@export var caption := ""
var lit := false:
	set(v):
		if lit != v:
			lit = v
			queue_redraw()
var lit_color := UITheme.GO
var icon_color := UITheme.TEXT
var flash := 0.0
var _down := false
var _touch := -1


func _init(p_icon := "left", size_px := 88.0, p_caption := "") -> void:
	icon = p_icon
	caption = p_caption
	custom_minimum_size = Vector2(size_px, size_px + (22.0 if caption != "" else 0.0))
	mouse_filter = Control.MOUSE_FILTER_STOP


## Touch only: the project emulates touch from the mouse on desktop, and
## handling both would fire every click twice.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_touch = event.index
			_press()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_release(Rect2(Vector2.ZERO, size).has_point(event.position))
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()


## The app lost focus mid-touch: forget the finger without firing the button.
func release_touch() -> void:
	_touch = -1
	_down = false
	queue_redraw()


func _press() -> void:
	_down = true
	pressed_down.emit()
	queue_redraw()


func _release(inside: bool) -> void:
	if not _down:
		return
	_down = false
	released.emit()
	if inside:
		tapped.emit()
	queue_redraw()


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		queue_redraw()


func _draw() -> void:
	var d := minf(size.x, size.y - (22.0 if caption != "" else 0.0))
	var c := Vector2(size.x * 0.5, d * 0.5)
	var r := d * 0.5 - 2.0
	var bg := UITheme.SURFACE_HI
	if lit:
		bg = lit_color.darkened(0.45)
	if _down:
		bg = bg.lightened(0.15)
	if flash > 0.0:
		bg = bg.lerp(UITheme.STOP, flash)
	draw_circle(c, r, bg)
	draw_arc(c, r, 0, TAU, 40, lit_color if lit else Color(1, 1, 1, 0.16), 2.5, true)
	Icons.draw(self, icon, c, r * 0.5, lit_color.lightened(0.2) if lit else icon_color)
	if caption != "":
		var f := UITheme.regular()
		var fs := 15
		var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(size.x * 0.5 - w * 0.5, d + 17), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				UITheme.TEXT_DIM)
