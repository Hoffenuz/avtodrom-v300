extends Node
## Main menu over a slowly orbiting view of the avtodrom.
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
var _car_buttons := {}
var _menu_car: Car


func _ready() -> void:
	_build_world()
	_build_ui()
	Loc.language_changed.connect(_rebuild_ui)
	Session.history_changed.connect(_update_stats)
	match DebugShots.menu_page:
		"exam": _show_exam()
		"practice": _show_practice()
		"rules": _show_rules()
		"settings": _show_settings()
		"history": _show_history()


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var q := mini(int(Settings.get_value("quality")), 1)
	EnvironmentSetup.create(_world, q)
	var data := CourseData.get_default()
	var course := CourseBuilder.load_or_build(data, q)
	_world.add_child(course)
	var car := Car.new()
	_world.add_child(car)
	car.configure(Session.car_id())
	_menu_car = car
	var sp: Dictionary = data.exercise("start")["spawn"]
	car.teleport(course.spawn_transform(CourseData.v2(sp["pos"]), float(sp["yaw"])), false)
	car.freeze = true
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 1200.0
	_world.add_child(_cam)
	_cam.current = true
	get_viewport().msaa_3d = Viewport.MSAA_2X


func _process(delta: float) -> void:
	_orbit += delta * 0.045
	var centre := Vector3(11.0, 0.0, -11.0)
	var r := 70.0
	_cam.global_position = centre + Vector3(cos(_orbit) * r, 31.0, sin(_orbit) * r)
	_cam.look_at(centre + Vector3(0, -6, 0), Vector3.UP)


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
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.4)
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


func _show_home() -> void:
	_clear_content()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_content.add_child(v)

	# Title (left) and the car (right).
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := UITheme.label(Loc.t("app.title"), 54, UITheme.TEXT, true)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("outline_size", 6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_car_picker())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	# The three modes.
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 16)
	v.add_child(modes)
	modes.add_child(_mode_card("menu.exam", true, _show_exam))
	modes.add_child(_mode_card("menu.practice", false, _show_practice))
	modes.add_child(_mode_card("menu.free", false, func() -> void: _start(Session.Mode.FREE)))

	# Secondary actions.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var items := [["menu.history", _show_history], ["menu.rules", _show_rules], ["menu.settings", _show_settings]]
	if not OS.has_feature("mobile"):
		items.append(["menu.quit", func() -> void: get_tree().quit()])
	for pair in items:
		var b := UITheme.button(Loc.t(pair[0]), 20, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		row.add_child(b)
	_stats = UITheme.label("", 17, UITheme.TEXT_DIM)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stats)
	_update_stats()


func _mode_card(key: String, primary: bool, action: Callable) -> Button:
	var b := UITheme.primary_button(Loc.t(key), 30, 132) if primary else UITheme.button(Loc.t(key), 28, 132)
	if not primary:
		b.add_theme_font_override("font", UITheme.bold())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


## Two-way switch: Nexia 2 (manual) / Cobalt (automatic).
func _car_picker() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_car_buttons.clear()
	for id in ["nexia2", "cobalt_at"]:
		var b := UITheme.button("", 19, 60)
		b.toggle_mode = true
		b.custom_minimum_size.x = 170
		b.text = Loc.t("car." + id) + "\n" + Loc.t("car." + id + "_desc")
		b.add_theme_font_size_override("font_size", 18)
		b.button_pressed = str(Settings.get_value("car")) == id
		var cid: String = id
		b.pressed.connect(func() -> void:
			Settings.set_value("car", cid)
			if _menu_car:
				_menu_car.configure(cid)
			for k in _car_buttons:
				_car_buttons[k].button_pressed = k == cid)
		_car_buttons[id] = b
		box.add_child(b)
	return box


func _update_stats() -> void:
	if _stats == null or not is_instance_valid(_stats):
		return
	if Session.history.is_empty():
		_stats.text = Loc.t("menu.no_history")
	else:
		_stats.text = Loc.t("menu.stats", [Session.history.size(), Session.pass_count()])


func _start(mode: Session.Mode, exercise := "", demo := false) -> void:
	_clear_content()
	var c := CenterContainer.new()
	_content.add_child(c)
	c.add_child(UITheme.label(Loc.t("menu.loading"), 34, UITheme.TEXT, true))
	await get_tree().process_frame
	await get_tree().process_frame
	Session.start(mode, exercise, demo)


# ------------------------------------------------------------------ sub-screens
func _screen(title_key: String) -> VBoxContainer:
	_clear_content()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var back := UITheme.button("‹  " + Loc.t("menu.back"), 21, 60)
	back.custom_minimum_size.x = 170
	back.pressed.connect(_show_home)
	head.add_child(back)
	var t := UITheme.label(Loc.t(title_key), 32, UITheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(170, 0)
	head.add_child(spacer)
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
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(620.0, _ui.size.x - 120.0), 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var minutes := int(Settings.get_value("exam_time_limit_min"))
	for line in [Loc.t("exam.rule_route"), Loc.t("exam.rule_pass"), Loc.t("exam.rule_time", [minutes]),
			Loc.t("exam.rule_hints")]:
		var l := UITheme.label("•  " + line, 21, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	var car_id := str(Settings.get_value("car"))
	box.add_child(UITheme.label("%s: %s (%s)" % [Loc.t("menu.car"), Loc.t("car." + car_id),
			Loc.t("car." + car_id + "_desc")], 19, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var go := UITheme.primary_button(Loc.t("menu.start"), 26, 76)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.size_flags_stretch_ratio = 2.0
	go.pressed.connect(func() -> void: _start(Session.Mode.EXAM))
	row.add_child(go)
	var demo := UITheme.button("▶  " + Loc.t("menu.demo"), 21, 76)
	demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo.pressed.connect(func() -> void: _start(Session.Mode.EXAM, "", true))
	row.add_child(demo)


func _show_practice() -> void:
	var v := _screen("menu.practice")
	var bg := PanelContainer.new()
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3 if _ui.size.x >= 1150.0 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var data := CourseData.get_default()
	var n := 0
	var seen := {}
	for e in data.exercises:
		var id := str(e["id"])
		var key := "intersection" if id.begins_with("intersection") else id
		if seen.has(key):
			continue
		seen[key] = true
		n += 1
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 6)
		var b := UITheme.button("%d.  %s" % [n, Loc.pick(e["name"])], 20, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ex_id := id
		b.pressed.connect(func() -> void: _start(Session.Mode.PRACTICE, ex_id))
		cell.add_child(b)
		# Watch the instructor (autopilot) do it first.
		var demo := UITheme.button("▶ " + Loc.t("menu.demo"), 17, 72)
		demo.custom_minimum_size.x = 118
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
	var date := str(r.get("date", "")).replace("T", "  ").substr(0, 17)
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
	var s := SettingsPanel.new()
	s.closed.connect(func() -> void:
		s.queue_free()
		_show_home())
	_ui.add_child(s)
