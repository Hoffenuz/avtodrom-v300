extends Node
## Main menu: the chosen car on a turntable in an open showroom (sky and a
## floor fading into the haze, no avtodrom behind it: lighter and calmer), the
## camera slowly circling it, with the menu over the left half of the screen.
##   Home      — three modes (exam, exercises, free drive), the car, and
##               results / penalties / settings;
##   Exam      — what the exam is in four lines, then start (or watch it);
##   Exercises — every exercise on its own, each with a demonstration;
##   Results, Penalties, Settings.

var _world: Node3D
var _cam: Camera3D
var _orbit := 0.0
var _ui: Control
var _content: Control
var _stats: Label
var _menu_car: Car
var _car_name: Label
var _car_type: Label
## Under the car switch: opens the colour (and the Onix's gearbox) choice.
var _car_options: Button
var _car_focus := Vector3.ZERO
var _on_home := true
var _settings_panel: SettingsPanel
## The player spins the showroom by dragging over the car; the slow orbit
## takes over again a moment after the finger lifts.
var _drag_idle := 99.0
var _orbit_speed := 0.12
const BRAND_MARK := preload("res://assets/ui/brand_mark.png")
const BRAND_FONT := preload("res://assets/fonts/Montserrat-ExtraBold.ttf")


func _ready() -> void:
	# The 3D backdrop takes a moment to build: the loading page goes up first.
	set_process(false)
	await Loading.cover("load.world")
	_build_world()
	_build_ui()
	set_process(true)
	if Loading.safe_mode_notice != "":
		_safe_mode_dialog.call_deferred(Loading.safe_mode_notice)
	Loading.finish()
	Loc.language_changed.connect(_rebuild_ui)
	Session.history_changed.connect(_update_stats)
	Settings.changed.connect(_on_setting_changed)
	match DebugShots.menu_page:
		"exam": _show_exam()
		"practice": _show_practice()
		"rules": _show_rules()
		"settings": _show_settings()
		"history": _show_history()
		"car_options": _car_options_dialog()
	# Checks of an exported build (no scene path on its command line): leave
	# the menu as a tap would, "--start=exam|free|<exercise id>".
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="):
			var what := arg.substr(8)
			if what == "exam":
				_start(Session.Mode.EXAM)
			elif what == "free":
				_start(Session.Mode.FREE)
			else:
				_start(Session.Mode.PRACTICE, what)


const DISC_TOP := 0.05 # turntable deck height (m)


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var q := mini(int(Settings.get_value("quality")), 1)
	EnvironmentSetup.create(_world, q)
	_world.add_child(_floor())
	_world.add_child(_turntable(Vector3.ZERO))
	var car := Car.new()
	car.rest_pose = true
	_world.add_child(car)
	car.configure(Session.car_id())
	_menu_car = car
	car.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)), Vector3(0.0, DISC_TOP, 0.0)), false)
	car.freeze = true
	_car_focus = Vector3(0.0, DISC_TOP + 0.75, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 1200.0
	_world.add_child(_cam)
	_cam.current = true
	EnvironmentSetup.apply_viewport(get_viewport(), q)
	# The menu background is a slow orbit: 30 fps is plenty and keeps the phone
	# cool (the drive scene sets its own limit from the settings).
	if not DebugShots.perf:
		Engine.max_fps = 30


## The showroom floor: one big quad, fading into the sky at the horizon.
func _floor() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/showroom_floor.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A low dark platform with a lit rim under the menu car.
func _turntable(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Turntable"
	root.position = at
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.25
	cyl.bottom_radius = 3.4
	cyl.height = DISC_TOP
	cyl.radial_segments = 64
	cyl.rings = 1
	disc.mesh = cyl
	disc.position.y = DISC_TOP * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.07, 0.085)
	m.metallic = 0.4
	m.roughness = 0.32
	disc.material_override = m
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.23
	torus.outer_radius = 3.29
	torus.rings = 64
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = DISC_TOP - 0.004
	ring.scale = Vector3(1.0, 0.25, 1.0)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = UITheme.GO.lerp(Color.WHITE, 0.15)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return root


func _input(event: InputEvent) -> void:
	# On the home page a drag over the car (the right part of the screen,
	# clear of the menu column) turns the showroom. The full-screen UI layer
	# stops pointer events, so this listens before it.
	if not _on_home or _settings_panel != null or Loading.is_covering():
		return
	# (The project emulates touch from the mouse, so this covers both.)
	var drag := event as InputEventScreenDrag
	if drag and drag.position.x > _vw() * 0.45:
		_orbit -= drag.relative.x * 0.006
		_drag_idle = 0.0
		_orbit_speed = 0.0


func _process(delta: float) -> void:
	_drag_idle += delta
	# The slow orbit eases back in after a drag.
	_orbit_speed = move_toward(_orbit_speed, 0.12 if _drag_idle > 2.5 else 0.0, delta * 0.08)
	_orbit += delta * _orbit_speed
	# Farther back for a longer vehicle (the van is 6 m, the cars 4.5 m).
	var length := 4.5
	if _menu_car:
		length = _menu_car.body_front + _menu_car.body_rear
	var r := 8.2 * clampf(length / 4.5, 1.0, 1.5)
	_cam.global_position = _car_focus + Vector3(cos(_orbit) * r, 1.55 * r / 8.2, sin(_orbit) * r)
	_cam.look_at(_car_focus, Vector3.UP)
	# The car sits in the right half of the screen, clear of the menu.
	_cam.h_offset = -r * tan(deg_to_rad(_cam.fov * 0.5)) * _aspect() * 0.42


func _vw() -> float:
	return get_viewport().get_visible_rect().size.x


func _aspect() -> float:
	var s := get_viewport().get_visible_rect().size
	return s.x / maxf(s.y, 1.0)


# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	layer.add_child(_ui)
	_rebuild_ui()


func _rebuild_ui() -> void:
	for c in _ui.get_children():
		c.queue_free()
	# Dark on the menu side, clear over the car.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.05, 0.82))
	grad.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	grad.add_point(0.45, Color(0.02, 0.03, 0.05, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var safe := UITheme.safe_margins(_ui.get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44 + int(safe["left"]))
	margin.add_theme_constant_override("margin_right", 44 + int(safe["right"]))
	margin.add_theme_constant_override("margin_top", 28 + int(safe["top"]))
	margin.add_theme_constant_override("margin_bottom", 28 + int(safe["bottom"]))
	_ui.add_child(margin)
	_content = margin
	_show_home()


func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	_animate_in(_content)


## Pages slide in and fade up, as in a mobile game, instead of popping.
func _animate_in(c: Control, from_x := 36.0) -> void:
	# Full-rect pages rest at x = 0 (also when a previous slide was cut short).
	var x0 := 0.0
	c.modulate.a = 0.0
	c.position.x = x0 + from_x
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.24)
	tw.tween_property(c, "position:x", x0, 0.3)


func _show_home() -> void:
	_clear_content()
	_on_home = true
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	_content.add_child(h)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(minf(520.0, _vw() * 0.42), 0)
	left.add_theme_constant_override("separation", 14)
	h.add_child(left)
	left.add_child(_logo())
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gap)
	var stats := ""
	if not Session.history.is_empty():
		stats = Loc.t("menu.stats", [Session.history.size(), Session.pass_count()])
	var exam := MenuCard.new(Loc.t("menu.exam"), "flag", UITheme.GO, true, stats)
	exam.custom_minimum_size.y = 104
	exam.pressed.connect(_show_exam)
	left.add_child(exam)
	var practice := MenuCard.new(Loc.t("menu.practice"), "cone", Color(1.0, 0.6, 0.2))
	practice.pressed.connect(_show_practice)
	left.add_child(practice)
	var free := MenuCard.new(Loc.t("menu.free"), "wheel", UITheme.INFO)
	free.pressed.connect(func() -> void: _start(Session.Mode.FREE))
	left.add_child(free)
	left.add_child(_traffic_switch())
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	left.add_child(gap2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	left.add_child(row)
	var items := [["menu.history", "list", _show_history], ["menu.rules", "warn", _show_rules],
			["menu.settings", "gear", _show_settings]]
	if OS.has_feature("web"):
		# A browser tab cannot close itself: back to the site instead, and
		# the app for this device (smoother than the browser).
		items.append(["menu.site", "home", WebLinks.open_site])
		if WebLinks.app_url() != "":
			items.append(["menu.app", "download", _app_dialog])
	elif not OS.has_feature("mobile"):
		items.append(["menu.quit", "exit", func() -> void: get_tree().quit()])
	for it in items:
		var b := MenuCard.RoundAction.new(Loc.t(it[0]), it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(it[2])
		row.add_child(b)

	# Right: the car (3D, behind) and its switch at the bottom.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var car_row := HBoxContainer.new()
	car_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(car_row)
	car_row.add_child(_car_carousel())
	var opt_row := HBoxContainer.new()
	opt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(opt_row)
	_car_options = _options_button()
	opt_row.add_child(_car_options)
	_show_car_name()
	var foot := UITheme.label("avtotestu.uz  ·  v%s" % str(ProjectSettings.get_setting("application/config/version", "1.0")),
			15, Color(1, 1, 1, 0.55))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(foot)
	_stats = null


func _logo() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var mark := TextureRect.new()
	mark.texture = BRAND_MARK
	mark.custom_minimum_size = Vector2(78, 78)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(mark)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := _brand_label("AvtoSmart", 40, Color.WHITE, 0)
	v.add_child(t)
	var sub := _brand_label(Loc.t("app.title").to_upper(), 22, Color(0.29, 0.87, 0.5), 5)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	var tag := UITheme.label(Loc.t("app.tagline"), 17, Color(1, 1, 1, 0.8))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	tag.add_theme_constant_override("outline_size", 4)
	v.add_child(tag)
	box.add_child(v)
	return box


## A line in the brand's typeface (Montserrat ExtraBold), `spacing` px
## between the letters.
func _brand_label(text: String, size: int, color: Color, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	var fv := FontVariation.new()
	fv.base_font = BRAND_FONT
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("outline_size", 6)
	return l


## Home-page switch for the other participants (also in Settings → Avtodrom).
func _traffic_switch() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.1, 0.13, 0.82), 20, 1, UITheme.LINE, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(40, 40)
	ic.draw.connect(func() -> void: Icons.draw(ic, "cars", ic.size * 0.5, 15.0, Color(1.0, 0.6, 0.2)))
	h.add_child(ic)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", -2)
	lv.add_child(UITheme.label(Loc.t("set.traffic"), 19, UITheme.TEXT, true))
	var state := UITheme.label("", 15, UITheme.TEXT_DIM)
	lv.add_child(state)
	h.add_child(lv)
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.get_value("traffic"))
	var show_state := func() -> void:
		state.text = Loc.t("menu.traffic_on", [int(Settings.get_value("traffic_count"))]) 				if bool(Settings.get_value("traffic")) else Loc.t("menu.traffic_off")
	show_state.call()
	c.toggled.connect(func(on: bool) -> void:
		Settings.set_value("traffic", on)
		show_state.call())
	h.add_child(c)
	return p


## ‹ Nexia 2 · mexanika › — switches the car (and the model on screen).
func _car_carousel() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.1, 0.13, 0.86), 26, 1, UITheme.LINE, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var prev := _chevron("chev_left")
	h.add_child(prev)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(190, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	_car_name = UITheme.label("", 26, UITheme.TEXT, true)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_type = UITheme.label("", 16, UITheme.TEXT_DIM)
	_car_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_car_name)
	v.add_child(_car_type)
	h.add_child(v)
	var next := _chevron("chev_right")
	h.add_child(next)
	prev.pressed.connect(func() -> void: _switch_car(-1))
	next.pressed.connect(func() -> void: _switch_car(1))
	_show_car_name()
	return p


func _chevron(icon: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56, 56)
	b.draw.connect(func() -> void:
		var hov := b.is_hovered()
		b.draw_circle(b.size * 0.5, 24.0, Color(1, 1, 1, 0.14 if hov else 0.07))
		Icons.draw(b, icon, b.size * 0.5, 11.0, UITheme.TEXT))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	return b


## The last run froze: say what was changed (on phones, ask to reopen).
func _safe_mode_dialog(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.08, 0.07, 0.96), 18, 2, UITheme.CAUTION, 22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.label(Loc.t("safe.title"), 26, UITheme.CAUTION, true))
	var d := UITheme.label(text, 18, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(560, 0)
	v.add_child(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var copy := UITheme.button(Loc.t("load.copy_log"), 19, 56)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Loading.diagnostics())
		copy.text = Loc.t("load.copied"))
	row.add_child(copy)
	var ok := UITheme.button(Loc.t("safe.reopen") if OS.has_feature("mobile") and not Loading.opengl_mode() \
			else "OK", 19, 56)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func() -> void:
		if OS.has_feature("mobile") and not Loading.opengl_mode():
			get_tree().quit()
		p.queue_free())
	row.add_child(ok)
	_ui.add_child(p)
	p.reset_size()
	p.position = (_ui.size - p.size) * 0.5


## Web: why the app is better, with its download for this device.
func _app_dialog() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(shade)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.08, 0.07, 0.97), 18, 2, UITheme.GO, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var android := OS.has_feature("web_android")
	v.add_child(UITheme.label(Loc.t("app.android_title" if android else "app.windows_title"), 26, UITheme.GO, true))
	var d := UITheme.label(Loc.t("app.why"), 18, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(minf(560.0, _vw() * 0.8), 0)
	v.add_child(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var close := func() -> void:
		shade.queue_free()
		p.queue_free()
	var later := UITheme.button(Loc.t("app.later"), 19, 56)
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	later.pressed.connect(close)
	row.add_child(later)
	var get_it := UITheme.button(Loc.t("app.download"), 19, 56)
	get_it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	get_it.pressed.connect(func() -> void:
		OS.shell_open(WebLinks.app_url())
		close.call())
	row.add_child(get_it)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close.call())
	_ui.add_child(p)
	p.reset_size()
	p.position = (_ui.size - p.size) * 0.5


## A small pill under the car switch, with the body colour as a dot.
func _options_button() -> Button:
	var b := UITheme.button("", 17, 46)
	b.custom_minimum_size.x = 250
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0.08, 0.1, 0.13, 0.86), 23, 1, UITheme.LINE, 12))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(0.12, 0.15, 0.19, 0.92), 23, 1, UITheme.LINE, 12))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(0.05, 0.07, 0.09, 0.92), 23, 1, UITheme.LINE, 12))
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.draw.connect(func() -> void:
		var e := CarPaint.entry(CarPaint.key_for(Session.car_id()))
		if e.is_empty():
			return
		var c := Vector2(24.0, b.size.y * 0.5)
		b.draw_circle(c, 11.0, e[2])
		b.draw_arc(c, 11.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 1.5, true))
	b.pressed.connect(_car_options_dialog)
	return b


## Colour swatches for the shown car, and for the Onix its gearbox.
func _car_options_dialog() -> void:
	var cid := str(Settings.get_value("car"))
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(shade)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.07, 0.09, 0.97), 20, 1, UITheme.LINE, 22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(UITheme.label(Loc.t("car.paint_title") + " · " + Loc.t("car." + cid), 24, UITheme.TEXT, true))
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	v.add_child(swatches)
	for row in CarPaint.COLORS:
		var key: String = row[0]
		var sw := Button.new()
		sw.flat = true
		sw.focus_mode = Control.FOCUS_NONE
		sw.custom_minimum_size = Vector2(92, 96)
		sw.draw.connect(func() -> void:
			var chosen := CarPaint.key_for(cid) == key
			var c := Vector2(sw.size.x * 0.5, 34.0)
			if chosen:
				sw.draw_circle(c, 31.0, UITheme.GO)
			sw.draw_circle(c, 26.0, Color(0, 0, 0, 0.5))
			sw.draw_circle(c, 24.0, row[2])
			# A highlight, as on a paint sample.
			sw.draw_circle(c + Vector2(-8, -9), 7.0, Color(1, 1, 1, 0.16 + 0.2 * float(row[3])))
			var f := UITheme.regular()
			var caption := Loc.t("paint." + key)
			var fs := 15
			var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			sw.draw_string(f, Vector2(sw.size.x * 0.5 - w * 0.5, 86.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					UITheme.TEXT if chosen else UITheme.TEXT_DIM))
		sw.pressed.connect(func() -> void:
			Settings.set_value(CarPaint.setting_key(cid), key)
			for s in swatches.get_children():
				(s as Control).queue_redraw())
		swatches.add_child(sw)
	if cid == "onix":
		var gb := HBoxContainer.new()
		gb.add_theme_constant_override("separation", 10)
		v.add_child(gb)
		var gl := UITheme.label(Loc.t("car.gearbox"), 19, UITheme.TEXT)
		gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.add_child(gl)
		var buttons: Array[Button] = []
		for opt in [["manual", "car.manual"], ["auto", "car.auto"]]:
			var ob := UITheme.button(Loc.t(opt[1]), 18, 48)
			ob.custom_minimum_size.x = 150
			ob.toggle_mode = true
			ob.button_pressed = str(Settings.get_value("onix_gearbox")) == opt[0]
			ob.add_theme_stylebox_override("pressed", UITheme.box(UITheme.GO.darkened(0.15), 14, 0, UITheme.LINE, 12))
			buttons.append(ob)
			gb.add_child(ob)
			ob.pressed.connect(func() -> void:
				for o in buttons:
					o.set_pressed_no_signal(o == ob)
				if str(Settings.get_value("onix_gearbox")) == opt[0]:
					return
				Settings.set_value("onix_gearbox", opt[0]))
	var close := func() -> void:
		shade.queue_free()
		p.queue_free()
	var done := UITheme.primary_button(Loc.t("car.done"), 20, 52)
	done.pressed.connect(close)
	v.add_child(done)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close.call())
	_ui.add_child(p)
	p.reset_size()
	p.position = ((_ui.size - p.size) * 0.5).max(Vector2.ZERO)


func _switch_car(step: int) -> void:
	var i := Car.IDS.find(str(Settings.get_value("car")))
	Settings.set_value("car", Car.IDS[posmod(i + step, Car.IDS.size())]) # -> _on_setting_changed


## The car on the turntable follows the settings, whichever page changed them.
func _on_setting_changed(key: String) -> void:
	if key == "car" or key == "onix_gearbox":
		if _menu_car:
			var preset := Session.car_id()
			# A new car model means new GPU pipelines: guarded like a load.
			Loading.guard_begin("menu car " + preset)
			print("CAR switch %s" % preset)
			_menu_car.configure(preset)
			Loading.guard_end()
		_show_car_name()
	elif key.begins_with("paint_"):
		if _menu_car:
			_menu_car.refresh_paint()
		if _car_options and is_instance_valid(_car_options):
			_car_options.queue_redraw()


func _show_car_name() -> void:
	var cid := str(Settings.get_value("car"))
	if _car_name:
		_car_name.text = Loc.t("car." + cid)
		_car_type.text = Loc.t("car." + Session.car_id() + "_desc")
	if _car_options and is_instance_valid(_car_options):
		_car_options.visible = CarPaint.paintable(cid)
		_car_options.text = "     " + Loc.t("car.options" if cid == "onix" else "car.paint")
		_car_options.queue_redraw()


func _update_stats() -> void:
	if _stats == null or not is_instance_valid(_stats):
		return
	if Session.history.is_empty():
		_stats.text = Loc.t("menu.no_history")
	else:
		_stats.text = Loc.t("menu.stats", [Session.history.size(), Session.pass_count()])


func _start(mode: Session.Mode, exercise := "", demo := false) -> void:
	Session.start(mode, exercise, demo) # behind the loading page


# ------------------------------------------------------------------ sub-screens
func _screen(title_key: String) -> VBoxContainer:
	_clear_content()
	_on_home = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_theme_constant_override("separation", 14)
	var back := _chevron("back")
	back.custom_minimum_size = Vector2(64, 64)
	back.pressed.connect(_show_home)
	head.add_child(back)
	var t := UITheme.label(Loc.t(title_key), 34, UITheme.TEXT, true)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	t.add_theme_constant_override("outline_size", 6)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	return v


func _scroll_list(parent: Control) -> VBoxContainer:
	var bg := PanelContainer.new()
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _show_exam() -> void:
	var v := _screen("exam.title")
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(split)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(minf(600.0, _vw() * 0.45), 0)
	body.add_theme_constant_override("separation", 12)
	split.add_child(body)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(rest)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.1, 0.13, 0.88), 22, 1, UITheme.LINE, 22))
	body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var minutes := int(Settings.get_value("exam_time_limit_min"))
	var rows := [["flag", Loc.t("exam.rule_route")], ["warn", Loc.t("exam.rule_pass")],
			["list", Loc.t("exam.rule_time", [minutes])], ["cone", Loc.t("exam.rule_hints")]]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(30, 30)
		var icon_name: String = r[0]
		ic.draw.connect(func() -> void: Icons.draw(ic, icon_name, ic.size * 0.5, 11.0, UITheme.CAUTION))
		h.add_child(ic)
		var l := UITheme.label(r[1], 21, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		box.add_child(h)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(fill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var go := MenuCard.new(Loc.t("menu.start"), "flag", UITheme.GO, true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func() -> void: _start(Session.Mode.EXAM))
	row.add_child(go)
	var demo := MenuCard.RoundAction.new(Loc.t("menu.demo"), "play")
	demo.pressed.connect(func() -> void: _start(Session.Mode.EXAM, "", true))
	row.add_child(demo)


func _show_practice() -> void:
	var v := _screen("menu.practice")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3 if _vw() >= 1500.0 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var data := CourseData.get_default()
	var n := 0
	var seen := {}
	var accents := [UITheme.GO, Color(1.0, 0.6, 0.2), UITheme.INFO, UITheme.CAUTION]
	for e in data.exercises:
		var id := str(e["id"])
		var key := "intersection" if id.begins_with("intersection") else id
		if seen.has(key):
			continue
		seen[key] = true
		n += 1
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 4)
		var b := MenuCard.new(Loc.pick(e["name"]), str(n), accents[(n - 1) % accents.size()])
		b.custom_minimum_size = Vector2(0, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ex_id := id
		b.pressed.connect(func() -> void: _start(Session.Mode.PRACTICE, ex_id))
		cell.add_child(b)
		# Watch the instructor (autopilot) do it first.
		var demo := MenuCard.RoundAction.new(Loc.t("menu.demo"), "play")
		demo.pressed.connect(func() -> void: _start(Session.Mode.PRACTICE, ex_id, true))
		cell.add_child(demo)
		grid.add_child(cell)


func _show_rules() -> void:
	var v := _screen("menu.rules")
	var list := _scroll_list(v)
	var colors := {"kichik": UITheme.CAUTION, "orta": Color(1.0, 0.55, 0.2), "qopol": UITheme.STOP}
	for g in PenaltyTable.groups():
		var gt := UITheme.label(Loc.pick(g["title"]), 21, colors.get(g["level"], UITheme.TEXT), true)
		list.add_child(gt)
		for it in g["items"]:
			list.add_child(_rule_row(it, colors.get(g["level"], UITheme.TEXT)))
	var note := UITheme.label(Loc.t("res.rule"), 17, UITheme.TEXT_DIM)
	list.add_child(note)


## One penalty: number, short name, points; a tap shows the official wording.
func _rule_row(it: Dictionary, col: Color) -> Control:
	var no := int(it["no"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var num := UITheme.label(str(no), 18, UITheme.TEXT_FAINT, true)
	num.custom_minimum_size = Vector2(34, 0)
	var txt := UITheme.label(PenaltyTable.short_text(no), 19, UITheme.TEXT)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pts := "%d %s" % [int(it["points"]), Loc.t("hud.points")]
	if it.has("note"):
		pts += " *"
	var pl := UITheme.label(pts, 19, col, true)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.custom_minimum_size = Vector2(96, 0)
	for c in [num, txt, pl]:
		h.add_child(c)
	var full := Loc.pick(it["text"])
	if it.has("note"):
		full += " (" + Loc.pick(it["note"]) + ")"
	var detail := UITheme.label(full, 17, UITheme.TEXT_DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _expandable(h, detail)


## A list row that shows `detail` under `summary` when tapped. Drags pass
## through to the scrolling list.
func _expandable(summary: Control, detail: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.045), 12, 0, UITheme.LINE, 14))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	summary.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(summary)
	detail.visible = false
	box.add_child(detail)
	p.add_child(box)
	var down := [Vector2.INF]
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			if e.pressed:
				down[0] = e.position
			elif down[0] != Vector2.INF:
				if e.position.distance_to(down[0]) < 14.0:
					detail.visible = not detail.visible
				down[0] = Vector2.INF)
	return p


func _show_history() -> void:
	var v := _screen("menu.history")
	var list := _scroll_list(v)
	if Session.history.is_empty():
		list.add_child(UITheme.label(Loc.t("menu.no_history"), 21, UITheme.TEXT_DIM))
		return
	for r in Session.history:
		list.add_child(_history_row(r))


## One exam attempt; a tap lists its errors.
func _history_row(r: Dictionary) -> Control:
	var passed: bool = r.get("passed", false)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var badge := UITheme.label("✓" if passed else "✗", 24, UITheme.GO if passed else UITheme.STOP, true)
	var date := str(r.get("date", "")).replace("T", " ").substr(0, 16)
	var info := UITheme.label(date, 19, UITheme.TEXT)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var car_id := str(r.get("car", ""))
	var car_l := UITheme.label(Loc.t("car." + car_id) if car_id != "" else "", 17, UITheme.TEXT_DIM)
	var pts := UITheme.label(Loc.t("res.total", [int(r.get("penalty", 0))]), 19,
			UITheme.GO if passed else UITheme.STOP, true)
	var tm := UITheme.label(UITheme.clock(float(r.get("time", 0))), 17, UITheme.TEXT_DIM)
	for c in [badge, info, car_l, pts, tm]:
		h.add_child(c)
	var errs := []
	for e in r.get("entries", []):
		errs.append("+%d   %s" % [int(e["points"]), PenaltyTable.short_text(int(e["no"]))])
	var detail := UITheme.label("\n".join(errs) if not errs.is_empty() else Loc.t("res.no_errors"), 17,
			UITheme.TEXT_DIM)
	return _expandable(h, detail)


func _show_settings() -> void:
	_clear_content()
	_on_home = false
	var s := SettingsPanel.new()
	s.closed.connect(func() -> void:
		s.queue_free()
		_settings_panel = null
		_show_home())
	_ui.add_child(s)
	_animate_in(s, 0.0)
	_settings_panel = s


## Android "back": a sub-page goes back to the home page; on the home page the
## app closes, as Android users expect (the project turns off Godot's own
## quit-on-back so a drive in progress is never closed by it).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _content == null:
		return
	if _settings_panel:
		_settings_panel.closed.emit()
	elif not _on_home:
		_show_home()
	else:
		get_tree().quit()
