extends CanvasLayer
## Full-screen loading page over scene changes (app start, menu -> drive,
## drive -> menu, restart), so the player never looks at a black screen
## while the course, the car and the shaders are prepared.
##
##   await Loading.cover("load.drive")   # drawn on screen when this returns
##   ... heavy synchronous work / change_scene ...
##   Loading.finish()                    # the new scene is ready
##
## The building itself is synchronous, so the page is drawn before it starts
## and stays up for a few frames afterwards while the GPU compiles the new
## scene's pipelines (that first frame is the slow one), then fades out.

const WHEEL_ART := preload("res://assets/ui/steering_wheel.png")
const TIPS := ["load.tip1", "load.tip2", "load.tip3", "load.tip4"]
## Frames the page stays up after finish(): the scene renders underneath.
const HOLD_FRAMES := 4
const FADE := 0.3

var _page: Control
var _status_key := ""
var _tip_key := ""
var _shown := 0.0 # progress bar as drawn
var _target := 0.0
var _spin := 0.0
var _hold := -1
var _fade := 0.0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_STOP # nothing underneath is usable yet
	_page.draw.connect(_draw_page)
	add_child(_page)
	visible = false
	# Up from the very first frame: the main menu builds its 3D backdrop next.
	_show("load.world")


func is_covering() -> bool:
	return visible


## Shows the page and returns once it has been drawn, so the caller can start
## blocking work. Safe to call when it is already up.
func cover(status_key: String) -> void:
	_show(status_key)
	await get_tree().process_frame
	await get_tree().process_frame


## The new scene is built: fill the bar, let it render a few frames, fade out.
func finish() -> void:
	if not visible:
		return
	_target = 1.0
	_hold = HOLD_FRAMES


func _show(status_key: String) -> void:
	if not visible or _hold >= 0 or _fade > 0.0:
		_shown = 0.0
		_target = 0.12
		_tip_key = TIPS[randi() % TIPS.size()]
	_status_key = status_key
	_hold = -1
	_fade = 0.0
	_page.modulate.a = 1.0
	visible = true
	_page.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_spin += delta
	# While waiting the bar creeps on (the work gives no progress of its own).
	if _target < 0.9:
		_target = minf(0.9, _target + delta * 0.25)
	_shown = move_toward(_shown, _target, delta * 2.5)
	if _hold > 0:
		_hold -= 1
	elif _hold == 0:
		_fade += delta
		_page.modulate.a = 1.0 - clampf(_fade / FADE, 0.0, 1.0)
		if _fade >= FADE:
			visible = false
			_hold = -1
			_fade = 0.0
	_page.queue_redraw()


func _draw_page() -> void:
	var sz := _page.size
	var vp := _page.get_viewport_rect().size
	if sz.x < 1.0:
		sz = vp
	# Background: the app's dark blue-grey, a little lighter at the top.
	var top := Color(0.1, 0.13, 0.17)
	var bottom := UITheme.BG
	var bands := 24
	for i in bands:
		var y0 := sz.y * i / bands
		_page.draw_rect(Rect2(0, y0, sz.x, sz.y / bands + 1.0), top.lerp(bottom, float(i) / (bands - 1)))
	var cx := sz.x * 0.5
	var unit := minf(sz.y, sz.x * 0.6)
	# Steering wheel, turning gently left and right.
	var wd := unit * 0.3
	var wc := Vector2(cx, sz.y * 0.36)
	_page.draw_set_transform(wc, sin(_spin * 1.6) * 0.5, Vector2.ONE)
	_page.draw_texture_rect(WHEEL_ART, Rect2(-wd * 0.5, -wd * 0.5, wd, wd), false)
	_page.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Title and status.
	var bold := UITheme.bold()
	var reg := UITheme.regular()
	_centered(bold, Loc.t("app.title").to_upper(), wc.y + wd * 0.5 + unit * 0.12, int(unit * 0.075), UITheme.TEXT)
	_centered(reg, Loc.t("app.tagline"), wc.y + wd * 0.5 + unit * 0.18, int(unit * 0.035), UITheme.TEXT_DIM)
	# Progress bar.
	var bw := minf(sz.x * 0.5, unit * 0.9)
	var bh := maxf(6.0, unit * 0.014)
	var by := sz.y * 0.8
	var bar := Rect2(cx - bw * 0.5, by, bw, bh)
	_page.draw_rect(bar, Color(1, 1, 1, 0.1))
	_page.draw_rect(Rect2(bar.position, Vector2(bw * clampf(_shown, 0.0, 1.0), bh)), UITheme.GO)
	_centered(reg, Loc.t(_status_key), by - unit * 0.035, int(unit * 0.036), UITheme.TEXT)
	if _tip_key != "":
		_centered(reg, Loc.t(_tip_key), by + bh + unit * 0.065, int(unit * 0.032), UITheme.TEXT_FAINT)


func _centered(f: Font, text: String, baseline: float, fs: int, color: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_page.draw_string(f, Vector2(_page.size.x * 0.5 - w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			color)
