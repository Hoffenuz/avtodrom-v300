class_name SettingsPanel
extends Control
## Settings screen (used from the main menu and from pause). Every change is
## saved immediately through the Settings autoload.

signal closed

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rebuild()
	Loc.language_changed.connect(func() -> void:
		for c in get_children():
			c.queue_free()
		_rebuild.call_deferred())


func _rebuild() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var safe := UITheme.safe_margins(get_viewport())
	margin.add_theme_constant_override("margin_left", 40 + int(safe["left"]))
	margin.add_theme_constant_override("margin_right", 40 + int(safe["right"]))
	margin.add_theme_constant_override("margin_top", 24 + int(safe["top"]))
	margin.add_theme_constant_override("margin_bottom", 24 + int(safe["bottom"]))
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var back := UITheme.button("‹  " + Loc.t("menu.back"), 24, 70)
	back.custom_minimum_size.x = 200
	back.pressed.connect(func() -> void: closed.emit())
	head.add_child(back)
	var title := UITheme.label(Loc.t("set.title"), 34, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(200, 0)
	head.add_child(spacer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(minf(860.0, get_viewport().get_visible_rect().size.x - 120.0), 0)
	_list.add_theme_constant_override("separation", 10)
	center.add_child(_list)
	_build()


func _section(key: String) -> void:
	var l := UITheme.label(Loc.t(key), 22, UITheme.CAUTION, true)
	l.custom_minimum_size = Vector2(0, 44)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _row(label_key: String, control: Control, desc_key := "") -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.045), 16, 0, UITheme.LINE, 20))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(UITheme.label(Loc.t(label_key), 22, UITheme.TEXT))
	if desc_key != "":
		var d := UITheme.label(Loc.t(desc_key), 16, UITheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(d)
	h.add_child(lv)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	h.add_child(control)
	_list.add_child(p)


func _segmented(key: String, options: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var current: Variant = Settings.get_value(key)
	for opt in options:
		var b := UITheme.button(str(opt[1]), 20, 60)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 120
		b.button_pressed = current == opt[0]
		var value: Variant = opt[0]
		b.pressed.connect(func() -> void: Settings.set_value(key, value))
		h.add_child(b)
	return h


func _toggle(key: String) -> Control:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.focus_mode = Control.FOCUS_NONE
	c.scale = Vector2(1.4, 1.4)
	c.custom_minimum_size = Vector2(80, 50)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	return c


func _slider(key: String, lo: float, hi: float, step: float, fmt := "%.0f%%", mul := 100.0) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(300, 50)
	s.focus_mode = Control.FOCUS_NONE
	var val := UITheme.label(fmt % (s.value * mul), 20, UITheme.TEXT_DIM)
	val.custom_minimum_size = Vector2(80, 0)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * mul)
		Settings.set_value(key, int(v) if typeof(Settings.DEFAULTS[key]) == TYPE_INT else v))
	h.add_child(s)
	h.add_child(val)
	return h


func _build() -> void:
	_section("set.language")
	_row("set.language", _segmented("language", [["uz_latn", "O‘zbekcha"], ["uz_cyrl", "Ўзбекча"], ["ru", "Русский"]]))
	_row("menu.car", _segmented("car", [["nexia2", "Nexia 2"], ["cobalt_at", "Cobalt AT"]]))

	_section("set.controls")
	_row("set.steering", _segmented("steering_mode", [["wheel", Loc.t("set.steer_wheel")],
			["tilt", Loc.t("set.steer_tilt")], ["buttons", Loc.t("set.steer_buttons")]]))
	_row("set.sensitivity", _slider("steering_sensitivity", 0.5, 2.0, 0.05, "%.2f", 1.0))
	_row("set.autocenter", _toggle("steering_autocenter"))
	_row("set.auto_clutch", _toggle("auto_clutch"), "set.auto_clutch_desc")
	_row("set.left_handed", _toggle("left_handed"))

	_section("set.learning")
	_row("set.hints", _toggle("show_hints"))
	_row("set.route", _toggle("show_route"))
	_row("set.time_limit", _slider("exam_time_limit_min", 15, 40, 1, "%d", 1.0))

	_section("set.graphics")
	_row("set.quality", _segmented("quality", [[0, Loc.t("set.q0")], [1, Loc.t("set.q1")], [2, Loc.t("set.q2")]]),
			"set.quality_desc")
	_row("set.render_scale", _slider("render_scale", 0.5, 1.0, 0.05))
	_row("set.fps", _segmented("fps_limit", [[30, "30"], [60, "60"]]))
	_row("set.shadows", _toggle("shadows"))
	_row("set.mirrors", _toggle("mirrors"))

	_section("set.sound")
	_row("set.vol_master", _slider("vol_master", 0.0, 1.0, 0.05))
	_row("set.vol_engine", _slider("vol_engine", 0.0, 1.0, 0.05))
	_row("set.vol_effects", _slider("vol_effects", 0.0, 1.0, 0.05))

	var reset := UITheme.button(Loc.t("set.reset"), 22, 70)
	reset.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		for c in _list.get_children():
			c.queue_free()
		_build.call_deferred())
	_list.add_child(reset)
