class_name SettingsPanel
extends Control
## Settings screen (used from the main menu and from pause): sections down
## the left (General, Avtodrom, Controls, Graphics, Sound, About), the chosen
## one's rows on the right. Every change is saved immediately through the
## Settings autoload.

signal closed

const TABS := [
	["general", "set.general", "gear"],
	["avtodrom", "set.avtodrom", "flag"],
	["controls", "set.controls", "wheel"],
	["graphics", "set.graphics", "lights"],
	["sound", "set.sound", "sound"],
	["about", "set.about", "info"],
]
## The section shown when the screen opens again.
static var _last_tab := "general"

var _list: VBoxContainer
var _tabs: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	# Already in the tree here: the offsets must be reset too, otherwise the
	# panel keeps its 0×0 rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-tab="): # screenshots of one section
			_last_tab = arg.substr(15)
	_rebuild()
	Loc.language_changed.connect(func() -> void:
		for c in get_children():
			c.queue_free()
		_rebuild.call_deferred())


func _rebuild() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var safe := UITheme.safe_margins(get_viewport())
	margin.add_theme_constant_override("margin_left", 36 + int(safe["left"]))
	margin.add_theme_constant_override("margin_right", 36 + int(safe["right"]))
	margin.add_theme_constant_override("margin_top", 22 + int(safe["top"]))
	margin.add_theme_constant_override("margin_bottom", 22 + int(safe["bottom"]))
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var back := _round_button("back")
	back.pressed.connect(func() -> void: closed.emit())
	head.add_child(back)
	var title := UITheme.label(Loc.t("set.title"), 32, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var brand := UITheme.label("AvtoSmart Avtodrom", 17, UITheme.TEXT_FAINT)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(brand)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	v.add_child(body)
	var tab_panel := PanelContainer.new()
	tab_panel.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.04), 22, 1, UITheme.LINE, 10))
	tab_panel.custom_minimum_size = Vector2(minf(290.0, _vw() * 0.24), 0)
	body.add_child(tab_panel)
	_tabs = VBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tab_panel.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	_build_tabs()
	_build()


func _vw() -> float:
	return get_viewport().get_visible_rect().size.x


func _round_button(icon: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(60, 60)
	b.draw.connect(func() -> void:
		b.draw_circle(b.size * 0.5, 27.0, Color(1, 1, 1, 0.16 if b.is_hovered() else 0.08))
		Icons.draw(b, icon, b.size * 0.5, 12.0, UITheme.TEXT))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	return b


func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for t in TABS:
		var id: String = t[0]
		var on := id == _last_tab
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 62)
		b.clip_text = true
		var label: String = Loc.t(t[1])
		var icon: String = t[2]
		b.draw.connect(func() -> void:
			var r := Rect2(Vector2.ZERO, b.size)
			if on:
				var sb := UITheme.box(Color(UITheme.GO.r, UITheme.GO.g, UITheme.GO.b, 0.2), 16, 0)
				b.draw_style_box(sb, r)
				b.draw_rect(Rect2(4, 14, 4, b.size.y - 28), UITheme.GO)
			elif b.is_hovered():
				b.draw_style_box(UITheme.box(Color(1, 1, 1, 0.06), 16, 0), r)
			var col := UITheme.TEXT if on else UITheme.TEXT_DIM
			Icons.draw(b, icon, Vector2(34, b.size.y * 0.5), 11.0, UITheme.GO if on else UITheme.TEXT_DIM)
			var f := UITheme.bold() if on else UITheme.regular()
			b.draw_string(f, Vector2(62, b.size.y * 0.5 + 7), label, HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 70, 20, col))
		b.mouse_entered.connect(b.queue_redraw)
		b.mouse_exited.connect(b.queue_redraw)
		b.pressed.connect(func() -> void:
			_last_tab = id
			_build_tabs()
			_refill())
		_tabs.add_child(b)


func _refill() -> void:
	for c in _list.get_children():
		c.queue_free()
	_scroll.scroll_vertical = 0
	_build.call_deferred()


func _section(key: String) -> void:
	var l := UITheme.label(Loc.t(key), 20, UITheme.CAUTION, true)
	l.custom_minimum_size = Vector2(0, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


func _row(label_key: String, control: Control, desc_key := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.045), 16, 0, UITheme.LINE, 20))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := UITheme.label(Loc.t(label_key), 21, UITheme.TEXT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(name_l)
	if desc_key != "":
		var d := UITheme.label(Loc.t(desc_key), 16, UITheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(d)
	h.add_child(lv)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	_list.add_child(p)
	return p


func _segmented(key: String, options: Array, rebuild := false) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var current: Variant = Settings.get_value(key)
	for opt in options:
		var b := UITheme.button(str(opt[1]), 19, 56)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 104
		b.button_pressed = current == opt[0]
		var value: Variant = opt[0]
		b.pressed.connect(func() -> void:
			Settings.set_value(key, value)
			if key == "quality":
				Settings.set_value("quality_user", true)
			if rebuild:
				_refill())
		h.add_child(b)
	return h


## Like _segmented, but the shown choice is given (for "automatic" values).
func _segmented_int(key: String, options: Array, current: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for opt in options:
		var b := UITheme.button(str(opt[1]), 19, 56)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 104
		b.button_pressed = current == int(opt[0])
		var value: int = opt[0]
		b.pressed.connect(func() -> void:
			Settings.set_value(key, value)
			_refill()) # the control rows below depend on it
		h.add_child(b)
	return h


func _toggle(key: String, rebuild := false) -> Control:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(90, 50)
	c.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		if rebuild:
			_refill())
	return c


func _slider(key: String, lo: float, hi: float, step: float, fmt := "%.0f%%", mul := 100.0) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(280, 50)
	s.focus_mode = Control.FOCUS_NONE
	var val := UITheme.label(fmt % (s.value * mul), 19, UITheme.TEXT_DIM)
	val.custom_minimum_size = Vector2(72, 0)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * mul)
		Settings.set_value(key, int(v) if typeof(Settings.DEFAULTS[key]) == TYPE_INT else v))
	h.add_child(s)
	h.add_child(val)
	return h


func _build() -> void:
	match _last_tab:
		"avtodrom": _build_avtodrom()
		"controls": _build_controls()
		"graphics": _build_graphics()
		"sound": _build_sound()
		"about": _build_about()
		_: _build_general()


func _build_general() -> void:
	_row("set.language", _segmented("language", [["uz_latn", "O‘zbekcha"], ["uz_cyrl", "Ўзбекча"], ["ru", "Русский"]]))
	var cars := []
	for cid in Car.IDS:
		cars.append([cid, Loc.t("car." + cid)])
	_row("menu.car", _segmented("car", cars), "set.car_desc")
	var reset := UITheme.button(Loc.t("set.reset"), 19, 56)
	reset.custom_minimum_size.x = 220
	reset.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		_refill())
	_row("set.reset_title", reset, "set.reset_desc")


func _build_avtodrom() -> void:
	var on := bool(Settings.get_value("traffic"))
	var head := _row("set.traffic", _toggle("traffic", true), "set.traffic_desc")
	head.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.GO.r, UITheme.GO.g, UITheme.GO.b,
			0.1 if on else 0.045), 16, 1 if on else 0, UITheme.GO, 20))
	if on:
		_row("set.traffic_count", _segmented("traffic_count", [[1, "1"], [2, "2"], [3, "3"], [4, "4"]]),
				"set.traffic_count_desc")
	_row("set.route", _toggle("show_route"), "set.route_desc")
	_row("set.hints", _toggle("show_hints"))


func _build_controls() -> void:
	var touch := Settings.screen_controls_on()
	if not Settings.is_mobile():
		_row("set.screen_controls", _segmented_int("screen_controls", [[0, Loc.t("set.off")], [1, Loc.t("set.on")]],
				1 if touch else 0))
	_row("set.auto_clutch", _toggle("auto_clutch"), "set.auto_clutch_desc")
	if touch:
		var modes := [["wheel", Loc.t("set.steer_wheel")], ["buttons", Loc.t("set.steer_buttons")]]
		if Settings.is_mobile():
			modes.append(["tilt", Loc.t("set.steer_tilt")])
		_row("set.steering", _segmented("steering_mode", modes))
		_row("set.sensitivity", _slider("steering_sensitivity", 0.75, 3.0, 0.05, "%.2f", 1.0))
		_row("set.autocenter", _toggle("steering_autocenter"))
		_row("set.left_handed", _toggle("left_handed"))
		_section("set.wheel_group")
		_row("set.wheel_scale", _slider("wheel_scale", 0.7, 1.35, 0.05), "set.wheel_group_desc")
		_row("set.wheel_shift_x", _slider("wheel_shift_x", 0.0, 0.2, 0.01))
		_row("set.wheel_shift_y", _slider("wheel_shift_y", 0.0, 0.2, 0.01))
	if not Settings.is_mobile():
		_section("set.keys")
		var sheet := KeysHelp.build(1, 17)
		_list.add_child(sheet)


func _build_graphics() -> void:
	if not OS.has_feature("web"): # browsers only have WebGL
		_build_renderer_row()
	if not Settings.is_mobile() and not OS.has_feature("web"):
		_row("set.fullscreen", _toggle("fullscreen"), "set.fullscreen_desc")
	_build_quality_rows()


func _build_renderer_row() -> void:
	var gl := CheckButton.new()
	gl.button_pressed = Loading.opengl_mode()
	gl.focus_mode = Control.FOCUS_NONE
	gl.custom_minimum_size = Vector2(90, 50)
	gl.toggled.connect(func(on: bool) -> void:
		Loading.set_opengl_mode(on)
		Loading.restart_app())
	_row("set.opengl", gl, "set.opengl_desc")


func _build_quality_rows() -> void:
	_row("set.quality", _segmented("quality", [[0, Loc.t("set.q0")], [1, Loc.t("set.q1")], [2, Loc.t("set.q2")]]),
			"set.quality_desc")
	_row("set.render_scale", _segmented("render_scale", [[-1.0, Loc.t("set.auto")], [0.6, "60%"], [0.75, "75%"],
			[1.0, "100%"]]))
	_row("set.fps", _segmented("fps_limit", [[30, "30"], [60, "60"]]))
	_row("set.shadows", _toggle("shadows"))
	_row("set.lite", _toggle("lite_scenery"), "set.lite_desc")
	_row("set.mirrors", _toggle("mirrors"))


func _build_sound() -> void:
	_row("set.vol_master", _slider("vol_master", 0.0, 1.0, 0.05))
	_row("set.vol_engine", _slider("vol_engine", 0.0, 1.0, 0.05))
	_row("set.vol_effects", _slider("vol_effects", 0.0, 1.0, 0.05))


func _build_about() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.2, 0.12, 0.6), 22, 1, UITheme.GO, 24))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	card.add_child(h)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/brand_mark.png")
	mark.custom_minimum_size = Vector2(96, 96)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(mark)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 2)
	h.add_child(tv)
	var name_l := Label.new()
	name_l.text = "AvtoSmart Avtodrom"
	name_l.add_theme_font_override("font", load("res://assets/fonts/Montserrat-ExtraBold.ttf"))
	name_l.add_theme_font_size_override("font_size", 30)
	name_l.add_theme_color_override("font_color", UITheme.TEXT)
	tv.add_child(name_l)
	tv.add_child(UITheme.label(Loc.t("app.tagline"), 18, Color(0.73, 0.97, 0.82)))
	var ver := str(ProjectSettings.get_setting("application/config/version", "1.0"))
	tv.add_child(UITheme.label(Loc.t("set.version", [ver]) + "  ·  avtotestu.uz", 16, UITheme.TEXT_DIM))
	_list.add_child(card)
	var copy := UITheme.button(Loc.t("load.copy_log"), 19, 56)
	copy.custom_minimum_size.x = 260
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Loading.diagnostics())
		copy.text = Loc.t("load.copied"))
	_row("set.diagnostics", copy, "set.diagnostics_desc")
	_section("set.credits")
	var credits := UITheme.label(Loc.t("set.credits_text"), 16, UITheme.TEXT_DIM)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size = Vector2(200, 0)
	_list.add_child(credits)
