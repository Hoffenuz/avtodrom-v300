class_name Hud
extends CanvasLayer
## Everything drawn over the road while driving: exercise card with the
## current instruction, penalty/time status, penalty toasts, big centre
## messages (START, emergency signal), the instrument cluster, and the
## touch controls (wheel, pedals, gear lever, cabin switches).
##
## Layout is recomputed on every resize from the visible rect and the
## display's safe area, so it works from 16:9 tablets to 21:9 phones.

signal pause_requested
signal camera_requested
signal ready_pressed

var car: Car
var controls: DriverControls
var director: ExamDirector
var data: CourseData
var touch_mode := true

var root: Control
var card: PanelContainer
var card_title: Label
var card_hint: Label
var card_turn: Label
var status: PanelContainer
var status_penalty: Label
var status_time: Label
var toasts: VBoxContainer
var center_msg: Label
var emergency_overlay: ColorRect
var prepare_panel: PanelContainer
var prep_items := {}
var ready_btn: Button
var cluster: GaugeCluster
var minimap: Minimap
var wheel: SteeringWheelWidget
var btn_steer_left: IconButton
var btn_steer_right: IconButton
var gas: Pedal
var brake_pedal: Pedal
var clutch_pedal: Pedal
var gears: GearSelector
var b_ind_left: IconButton
var b_ind_right: IconButton
var b_hazard: IconButton
var b_key: IconButton
var b_belt: IconButton
var b_handbrake: IconButton
var b_lights: IconButton
var b_camera: IconButton
var b_map: IconButton
var b_pause: IconButton

var _center_t := 0.0
var _emergency := false
var _emergency_t := 0.0
var _map_forced := false
## Demonstration: the autopilot drives, the driving controls are hidden.
var demo := false
var demo_badge: PanelContainer


func _init() -> void:
	layer = 5


func setup(p_car: Car, p_controls: DriverControls, p_director: ExamDirector, p_data: CourseData) -> void:
	car = p_car
	controls = p_controls
	director = p_director
	data = p_data
	touch_mode = Settings.is_mobile() or DisplayServer.is_touchscreen_available()
	_build()
	if director:
		director.penalty_added.connect(_on_penalty)
		director.hint_changed.connect(_refresh_card)
		director.exercise_changed.connect(_refresh_card)
		director.state_changed.connect(_on_state)
		director.start_signal.connect(func() -> void: show_center(Loc.t("hud.start_signal"), UITheme.GO, 2.5))
		director.emergency_signal.connect(_on_emergency)
	car.engine_stalled.connect(func() -> void: show_center(Loc.t("hud.stalled"), UITheme.CAUTION, 2.0))
	Loc.language_changed.connect(_relabel)
	get_viewport().size_changed.connect(_layout)
	_relabel()
	_layout()
	_refresh_card()


# ------------------------------------------------------------------ construction
func _build() -> void:
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	emergency_overlay = ColorRect.new()
	emergency_overlay.color = Color(0.9, 0.1, 0.1, 0.0)
	emergency_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emergency_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(emergency_overlay)

	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	card_title = UITheme.label("", 22, UITheme.CAUTION, true)
	card_hint = UITheme.label("", 20, UITheme.TEXT)
	card_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_turn = UITheme.label("", 18, UITheme.INFO, true)
	cv.add_child(card_title)
	cv.add_child(card_hint)
	cv.add_child(card_turn)
	root.add_child(card)

	status = PanelContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 22)
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_child(sh)
	status_penalty = UITheme.label("0", 26, UITheme.TEXT, true)
	status_time = UITheme.label("0:00", 26, UITheme.TEXT_DIM, true)
	sh.add_child(status_penalty)
	sh.add_child(status_time)
	root.add_child(status)

	demo_badge = PanelContainer.new()
	demo_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	demo_badge.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.12, 0.22, 0.88), 14, 2, UITheme.INFO, 12))
	var db := UITheme.label("", 20, UITheme.INFO, true)
	db.name = "Text"
	db.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	demo_badge.add_child(db)
	demo_badge.visible = false
	root.add_child(demo_badge)

	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 8)
	root.add_child(toasts)

	center_msg = UITheme.label("", 54, UITheme.GO, true)
	center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	center_msg.add_theme_constant_override("outline_size", 10)
	center_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_msg.visible = false
	root.add_child(center_msg)

	_build_prepare()

	cluster = GaugeCluster.new()
	cluster.car = car
	root.add_child(cluster)

	minimap = Minimap.new()
	minimap.setup(data, car, director)
	root.add_child(minimap)

	_build_touch()


func _build_prepare() -> void:
	prepare_panel = PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	prepare_panel.add_child(v)
	var title := UITheme.label(Loc.t("hud.prepare"), 26, UITheme.CAUTION, true)
	title.name = "Title"
	v.add_child(title)
	for key in ["prep.belt", "prep.engine", "prep.handbrake", "prep.signal"]:
		var l := UITheme.label("", 21, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prep_items[key] = l
		v.add_child(l)
	ready_btn = UITheme.primary_button(Loc.t("hud.ready"))
	ready_btn.pressed.connect(func() -> void:
		ready_pressed.emit()
		if director:
			director.request_start())
	v.add_child(ready_btn)
	prepare_panel.visible = director != null and director.state == ExamDirector.State.PREPARE
	root.add_child(prepare_panel)


func _build_touch() -> void:
	wheel = SteeringWheelWidget.new()
	wheel.lock_deg = car.get_steering_lock()
	wheel.steered.connect(func(d: float) -> void:
		controls.touch_steer_deg = d
		controls.touch_steer_active = true)
	root.add_child(wheel)

	btn_steer_left = IconButton.new("left", 120)
	btn_steer_right = IconButton.new("right", 120)
	root.add_child(btn_steer_left)
	root.add_child(btn_steer_right)

	gas = Pedal.new(Loc.t("hud.gas"), UITheme.GO, 1.35)
	gas.changed.connect(func(v: float) -> void: controls.touch_throttle = v)
	brake_pedal = Pedal.new(Loc.t("hud.brake"), UITheme.STOP, 1.1)
	brake_pedal.changed.connect(func(v: float) -> void: controls.touch_brake = v)
	clutch_pedal = Pedal.new(Loc.t("hud.clutch"), UITheme.INFO, 1.0)
	clutch_pedal.changed.connect(func(v: float) -> void: controls.touch_clutch = v)
	root.add_child(gas)
	root.add_child(brake_pedal)
	root.add_child(clutch_pedal)

	gears = GearSelector.new()
	gears.automatic = car.is_automatic()
	gears.gear_requested.connect(func(g: int) -> void: controls.gear_requested.emit(g))
	root.add_child(gears)

	b_ind_left = IconButton.new("left", 96)
	b_ind_left.lit_color = UITheme.INDICATOR
	b_ind_left.tapped.connect(func() -> void: controls.indicator_pressed.emit(Car.Indicator.LEFT))
	b_ind_right = IconButton.new("right", 96)
	b_ind_right.lit_color = UITheme.INDICATOR
	b_ind_right.tapped.connect(func() -> void: controls.indicator_pressed.emit(Car.Indicator.RIGHT))
	b_hazard = IconButton.new("hazard", 84)
	b_hazard.lit_color = UITheme.STOP
	b_hazard.icon_color = Color(1.0, 0.45, 0.45)
	b_hazard.tapped.connect(func() -> void: controls.hazard_pressed.emit())
	b_key = IconButton.new("key", 84)
	b_key.lit_color = UITheme.CAUTION
	b_key.pressed_down.connect(func() -> void: controls.key_down())
	b_key.released.connect(func() -> void: controls.key_up())
	b_belt = IconButton.new("belt", 84)
	b_belt.lit_color = UITheme.GO
	b_belt.tapped.connect(func() -> void: controls.seatbelt_pressed.emit())
	b_handbrake = IconButton.new("handbrake", 84)
	b_handbrake.lit_color = UITheme.STOP
	b_handbrake.tapped.connect(func() -> void: controls.handbrake_pressed.emit())
	b_lights = IconButton.new("lights", 72)
	b_lights.lit_color = UITheme.INFO
	b_lights.tapped.connect(func() -> void: controls.headlights_pressed.emit())
	b_camera = IconButton.new("camera", 72)
	b_camera.tapped.connect(func() -> void: camera_requested.emit())
	b_map = IconButton.new("map", 72)
	b_map.tapped.connect(func() -> void:
		_map_forced = not _map_forced
		_layout())
	b_pause = IconButton.new("pause", 72)
	b_pause.tapped.connect(func() -> void: pause_requested.emit())
	for b in [b_ind_left, b_ind_right, b_hazard, b_key, b_belt, b_handbrake, b_lights, b_camera, b_map, b_pause]:
		root.add_child(b)
	btn_steer_left.pressed_down.connect(func() -> void: _steer_button(-1))
	btn_steer_left.released.connect(func() -> void: _steer_button(0))
	btn_steer_right.pressed_down.connect(func() -> void: _steer_button(1))
	btn_steer_right.released.connect(func() -> void: _steer_button(0))


var _steer_dir := 0


func _steer_button(d: int) -> void:
	_steer_dir = d


# ------------------------------------------------------------------ layout
func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz


func _layout() -> void:
	if root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var safe := UITheme.safe_margins(get_viewport())
	var m := 16.0
	var L := m + float(safe["left"])
	var R := vp.x - m - float(safe["right"])
	var T := m + float(safe["top"])
	var B := vp.y - m - float(safe["bottom"])
	var W := R - L
	var steer_mode := str(Settings.get_value("steering_mode"))
	var manual_clutch := not car.is_automatic() and not car.auto_clutch
	var left_handed := bool(Settings.get_value("left_handed"))

	# Top row, right: lights, camera, map, pause.
	var bx := R - 72
	for b in [b_pause, b_map, b_camera, b_lights]:
		_place(b, Vector2(bx, T), b.custom_minimum_size)
		bx -= 82

	# Exercise card (top-left) and status (top-centre).
	var card_w := minf(520.0, W * 0.36)
	card.position = Vector2(L, T)
	card.custom_minimum_size = Vector2(card_w, 0)
	card_hint.custom_minimum_size = Vector2(card_w - 48.0, 0)
	card.reset_size()
	status.custom_minimum_size = Vector2(240, 0)
	status.position = Vector2(L + W * 0.5 - 120 + (W * 0.1 if W < 1300 else 0.0), T)
	demo_badge.reset_size()
	demo_badge.position = Vector2(status.position.x + 120 - demo_badge.size.x * 0.5, T + 64)
	toasts.position = Vector2(L + W * 0.5 - 260, T + 78)
	toasts.size = Vector2(520, 300)
	center_msg.position = Vector2(L, vp.y * 0.3)
	center_msg.size = Vector2(W, 80)
	prepare_panel.custom_minimum_size = Vector2(minf(560.0, W * 0.5), 0)
	prepare_panel.position = Vector2(L + W * 0.5 - prepare_panel.custom_minimum_size.x * 0.5, vp.y * 0.2)

	# Pedals and gear lever on the right (mirrored for left-handed drivers).
	var gas_sz := Vector2(140, 270)
	var brake_sz := Vector2(170, 220)
	var clutch_sz := Vector2(150, 220)
	var gear_sz := Vector2(170, 170) if not car.is_automatic() else Vector2(96, 220)
	var gas_pos := Vector2(R - gas_sz.x, B - gas_sz.y)
	var brake_pos := Vector2(gas_pos.x - 16 - brake_sz.x, B - brake_sz.y)
	var clutch_pos := Vector2(brake_pos.x - 16 - clutch_sz.x, B - clutch_sz.y)
	var gear_pos := Vector2(brake_pos.x + brake_sz.x - gear_sz.x, brake_pos.y - 16 - gear_sz.y)
	# Cabin column (key, belt, handbrake) at the right edge above the gas pedal.
	var col_x := R - 84
	var col_y := gas_pos.y - 16 - 84 * 3 - 20
	var wheel_d := minf(300.0, vp.y * 0.42)
	var wheel_pos := Vector2(L, B - wheel_d)
	if left_handed:
		var mirror := func(p: Vector2, s: Vector2) -> Vector2: return Vector2(L + R - p.x - s.x, p.y)
		gas_pos = mirror.call(gas_pos, gas_sz)
		brake_pos = mirror.call(brake_pos, brake_sz)
		clutch_pos = mirror.call(clutch_pos, clutch_sz)
		gear_pos = mirror.call(gear_pos, gear_sz)
		wheel_pos = Vector2(R - wheel_d, B - wheel_d)
		col_x = L
	_place(gas, gas_pos, gas_sz)
	_place(brake_pedal, brake_pos, brake_sz)
	_place(clutch_pedal, clutch_pos, clutch_sz)
	clutch_pedal.visible = touch_mode and manual_clutch
	_place(gears, gear_pos, gear_sz)
	for i in 3:
		var b: IconButton = [b_key, b_belt, b_handbrake][i]
		_place(b, Vector2(col_x, col_y + i * 92), b.custom_minimum_size)
	# Steering (left): wheel or buttons; indicators and hazards above it.
	_place(wheel, wheel_pos, Vector2(wheel_d, wheel_d))
	wheel.visible = touch_mode and steer_mode == "wheel"
	_place(btn_steer_left, Vector2(wheel_pos.x, B - 130), Vector2(120, 120))
	_place(btn_steer_right, Vector2(wheel_pos.x + 140, B - 130), Vector2(120, 120))
	btn_steer_left.visible = touch_mode and steer_mode == "buttons"
	btn_steer_right.visible = btn_steer_left.visible
	var ind_y := wheel_pos.y - 104
	_place(b_ind_left, Vector2(wheel_pos.x, ind_y), b_ind_left.custom_minimum_size)
	_place(b_hazard, Vector2(wheel_pos.x + wheel_d * 0.5 - 42, ind_y + 6), b_hazard.custom_minimum_size)
	_place(b_ind_right, Vector2(wheel_pos.x + wheel_d - 96, ind_y), b_ind_right.custom_minimum_size)
	for c in [gas, brake_pedal, gears, b_key, b_belt, b_handbrake]:
		c.visible = touch_mode
	if demo:
		for c in [gas, brake_pedal, clutch_pedal, gears, b_key, b_belt, b_handbrake, wheel, btn_steer_left,
				btn_steer_right, b_ind_left, b_ind_right, b_hazard, b_lights]:
			c.visible = false
	# Cluster centred between the wheel and the pedal group.
	var left_edge := wheel_pos.x + wheel_d + 12 if not left_handed else (clutch_pos.x + clutch_sz.x if manual_clutch else brake_pos.x + brake_sz.x) + 12
	var right_edge := (clutch_pos.x if manual_clutch else brake_pos.x) - 12 if not left_handed else wheel_pos.x - 12
	if not touch_mode:
		left_edge = L
		right_edge = R
	var cw := clampf(right_edge - left_edge, 300.0, 430.0)
	_place(cluster, Vector2((left_edge + right_edge) * 0.5 - cw * 0.5, B - 190), Vector2(cw, 190))
	# Minimap: shown by default on wide screens, on demand otherwise.
	var wide := vp.x / vp.y >= 2.0 or not touch_mode
	minimap.visible = (wide or _map_forced) and data != null
	var mm := 220.0
	if touch_mode and not left_handed:
		# On 720-px-tall layouts a full-size map would reach down over the gear lever.
		mm = clampf(gear_pos.y - 12.0 - (T + 90), 150.0, 220.0)
	# Left of the cabin-switch column, below the top button row.
	_place(minimap, Vector2(R - 84 - 16 - mm, T + 90), Vector2(mm, mm))
	if not touch_mode:
		_place(minimap, Vector2(R - mm, T + 90), Vector2(mm, mm))
	elif not wide:
		_place(minimap, Vector2(L + W * 0.5 - mm * 0.5, T + 90), Vector2(mm, mm))


# ------------------------------------------------------------------ updates
func _process(delta: float) -> void:
	if car == null:
		return
	if _steer_dir != 0:
		var rate := 360.0 * float(Settings.get_value("steering_sensitivity"))
		controls.touch_steer_deg = clampf(controls.touch_steer_deg + _steer_dir * rate * delta,
				-car.get_steering_lock(), car.get_steering_lock())
		controls.touch_steer_active = true
	elif btn_steer_left.visible:
		controls.touch_steer_deg = move_toward(controls.touch_steer_deg, 0.0, 480.0 * delta)
		controls.touch_steer_active = true
	wheel.car_speed = car.get_forward_speed()
	wheel.autocenter = bool(Settings.get_value("steering_autocenter"))
	wheel.sensitivity = float(Settings.get_value("steering_sensitivity"))
	if not wheel.is_held():
		# Keep the drawn wheel in step with keyboard / pad steering too.
		if not controls.touch_steer_active or not wheel.visible:
			wheel.set_angle(car.steering_wheel)
	b_ind_left.lit = car.left_lit()
	b_ind_right.lit = car.right_lit()
	b_hazard.lit = car.hazard
	b_key.lit = car.ignition
	b_belt.lit = car.seatbelt
	b_handbrake.lit = car.handbrake > 0.5
	b_lights.lit = car.headlights
	gears.automatic = car.is_automatic()
	gears.set_current(car.get_selector() if car.is_automatic() else car.get_gear())
	# Status.
	if director:
		status_penalty.text = "%s: %d" % [Loc.t("hud.penalty"), director.total]
		_font_color(status_penalty,
				UITheme.GO if director.total == 0 else (UITheme.CAUTION if director.total < 50 else UITheme.STOP))
		status_time.text = UITheme.clock(director.exam_time)
		_update_prepare()
		_update_turn()
	# A wrapped label can report a tall minimum while its width is still being
	# laid out; shrink the card back once the layout has settled.
	if card.visible and card.size.y > card.get_combined_minimum_size().y + 0.5:
		card.reset_size()
	# Centre message fade.
	if _center_t > 0.0:
		_center_t -= delta
		center_msg.modulate.a = clampf(_center_t / 0.4, 0.0, 1.0)
		if _center_t <= 0.0:
			center_msg.visible = false
	if _emergency:
		_emergency_t += delta
		var pulse := 0.5 + 0.5 * sin(_emergency_t * TAU * 2.0)
		emergency_overlay.color.a = 0.12 + 0.18 * pulse
		center_msg.visible = true
		center_msg.text = Loc.t("hud.emergency")
		center_msg.add_theme_color_override("font_color", UITheme.STOP.lerp(Color.WHITE, pulse * 0.4))
		center_msg.modulate.a = 1.0
	# Toast life.
	for t in toasts.get_children():
		var life: float = t.get_meta("life", 4.0) - delta
		t.set_meta("life", life)
		t.modulate.a = clampf(life / 0.6, 0.0, 1.0)
		if life <= 0.0:
			t.queue_free()


## Re-setting an override, even to the same colour, makes the label and its
## containers recompute their layout, so the per-frame updates only touch it
## when the colour really changes.
func _font_color(l: Label, color: Color) -> void:
	if not l.has_theme_color_override("font_color") or l.get_theme_color("font_color") != color:
		l.add_theme_color_override("font_color", color)


func _update_prepare() -> void:
	var preparing := director.state == ExamDirector.State.PREPARE
	prepare_panel.visible = preparing
	if not preparing:
		return
	var checks := {
		"prep.belt": car.seatbelt,
		"prep.engine": car.is_engine_running(),
		"prep.handbrake": car.handbrake > 0.5,
		"prep.signal": car.signalling_left(),
	}
	for key in prep_items:
		var ok: bool = checks[key]
		var l: Label = prep_items[key]
		l.text = ("✓  " if ok else "•  ") + Loc.t(key)
		_font_color(l, UITheme.GO if ok else UITheme.TEXT)
	ready_btn.disabled = not car.is_engine_running()


func _update_turn() -> void:
	if not Settings.get_value("show_hints") or director.state != ExamDirector.State.RUNNING:
		card_turn.text = ""
		return
	var t := director.next_turn()
	if t.is_empty() or float(t["distance"]) > 60.0:
		card_turn.text = ""
		return
	var dir_txt := Loc.t("hud.turn_left") if t["dir"] == "left" else Loc.t("hud.turn_right")
	var arrow := "⟵ " if t["dir"] == "left" else "⟶ "
	card_turn.text = arrow + dir_txt + " · " + Loc.t("hud.in_m", [maxi(int(t["distance"]), 0)])


func _refresh_card() -> void:
	if director == null:
		card_title.text = Loc.t("hud.free_mode")
		card_hint.text = ""
		return
	var ex := director.current_exercise()
	# The preparation checklist has its own panel; the card stays out of the way.
	card.visible = director.state != ExamDirector.State.PREPARE
	if ex:
		card_title.text = ex.title()
		card_hint.text = Loc.t(ex.hint_key, ex.hint_args) if ex.hint_key != "" else ""
	else:
		var nxt := director.upcoming_exercise()
		card_title.text = (Loc.t("hud.next") + ": " + nxt.title()) if nxt else ""
		card_hint.text = Loc.t("hint.go")
	card_hint.visible = bool(Settings.get_value("show_hints")) and card_hint.text != ""
	card.reset_size()


func _on_state() -> void:
	_refresh_card()


func _on_penalty(entry: Dictionary) -> void:
	var p := PanelContainer.new()
	var col := UITheme.CAUTION if int(entry["points"]) < 50 else UITheme.STOP
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.05, 0.05, 0.9), 16, 2, col, 16))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var pts := UITheme.label("+%d" % int(entry["points"]), 26, col, true)
	var txt := UITheme.label(PenaltyTable.text(int(entry["no"])), 18, UITheme.TEXT)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(400, 0)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pts)
	h.add_child(txt)
	p.set_meta("life", 5.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(p)
	toasts.move_child(p, 0)
	while toasts.get_child_count() > 3:
		toasts.get_child(toasts.get_child_count() - 1).queue_free()


func _on_emergency(on: bool) -> void:
	_emergency = on
	_emergency_t = 0.0
	if not on:
		emergency_overlay.color.a = 0.0
		center_msg.visible = false


func set_demo(on: bool) -> void:
	demo = on
	demo_badge.visible = on
	ready_btn.visible = not on
	_relabel()
	_layout()


func show_center(text: String, color: Color, seconds: float) -> void:
	if _emergency:
		return
	center_msg.text = text
	center_msg.add_theme_color_override("font_color", color)
	center_msg.visible = true
	center_msg.modulate.a = 1.0
	_center_t = seconds


func _relabel() -> void:
	if gas:
		gas.caption = Loc.t("hud.gas")
		brake_pedal.caption = Loc.t("hud.brake")
		clutch_pedal.caption = Loc.t("hud.clutch")
		gas.queue_redraw()
		brake_pedal.queue_redraw()
		clutch_pedal.queue_redraw()
	if ready_btn:
		ready_btn.text = Loc.t("hud.ready")
	if demo_badge:
		(demo_badge.get_node("Text") as Label).text = "▶  " + Loc.t("hud.demo")
	var title := prepare_panel.find_child("Title", true, false) as Label if prepare_panel else null
	if title:
		title.text = Loc.t("hud.prepare")
	_refresh_card()
