extends Node
## Main menu over a slowly orbiting view of the avtodrom.

var _world: Node3D
var _cam: Camera3D
var _orbit := 0.0
var _ui: Control
var _content: Control
var _panel_stack: Array[Control] = []
var _stats: Label
var _car_buttons := {}
var _menu_car: Car
var _on_home := true
var _settings_panel: SettingsPanel


func _ready() -> void:
	_build_world()
	_build_ui()
	Loc.language_changed.connect(_rebuild_ui)
	Session.history_changed.connect(_update_stats)
	match DebugShots.menu_page:
		"practice": _show_practice()
		"rules": _show_rules()
		"settings": _show_settings()
		"history": _show_history()
		"help": _show_help()


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
	var centre := Vector3(12.0, 0.0, -12.0)
	var r := 78.0
	_cam.global_position = centre + Vector3(cos(_orbit) * r, 34.0, sin(_orbit) * r)
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
	_panel_stack.clear()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var safe := UITheme.safe_margins(_ui.get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48 + int(safe["left"]))
	margin.add_theme_constant_override("margin_right", 48 + int(safe["right"]))
	margin.add_theme_constant_override("margin_top", 32 + int(safe["top"]))
	margin.add_theme_constant_override("margin_bottom", 32 + int(safe["bottom"]))
	_ui.add_child(margin)
	_content = margin
	_show_home()


func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()


func _show_home() -> void:
	_clear_content()
	_on_home = true
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	_content.add_child(h)

	# Left column: title + actions.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	var title := UITheme.label(Loc.t("app.title"), 56, UITheme.TEXT, true)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("outline_size", 6)
	left.add_child(title)
	var sub := UITheme.label(Loc.t("app.subtitle"), 20, UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(sub)
	var exam_row := HBoxContainer.new()
	exam_row.add_theme_constant_override("separation", 8)
	left.add_child(exam_row)
	var exam_btn := _menu_button("menu.exam", "menu.exam_desc", true, func() -> void: _start(Session.Mode.EXAM))
	exam_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exam_row.add_child(exam_btn)
	var demo_btn := UITheme.button("▶", 24, 84)
	demo_btn.custom_minimum_size.x = 84
	demo_btn.tooltip_text = Loc.t("menu.demo_exam")
	demo_btn.pressed.connect(func() -> void: _start(Session.Mode.EXAM, "", true))
	exam_row.add_child(demo_btn)
	left.add_child(_menu_button("menu.practice", "menu.practice_desc", false, _show_practice))
	left.add_child(_menu_button("menu.free", "menu.free_desc", false, func() -> void: _start(Session.Mode.FREE)))
	var grid := GridContainer.new()
	grid.columns = 3 if not OS.has_feature("mobile") else 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	var items := [["menu.rules", _show_rules], ["menu.history", _show_history], ["menu.settings", _show_settings],
			["menu.help", _show_help]]
	if not OS.has_feature("mobile"):
		items.append(["menu.quit", func() -> void: get_tree().quit()])
	for pair in items:
		var b := UITheme.button(Loc.t(pair[0]), 20, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		grid.add_child(b)

	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(filler)

	# Right column: language, car, stats.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 6)
	langs.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(langs)
	for code in Loc.LANGUAGES:
		var b := UITheme.button(Loc.LANGUAGE_NAMES[code], 18, 56)
		b.toggle_mode = true
		b.button_pressed = Loc.language == code
		var lc: String = code
		b.pressed.connect(func() -> void: Settings.set_value("language", lc))
		langs.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var car_panel := PanelContainer.new()
	right.add_child(car_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	car_panel.add_child(cv)
	cv.add_child(UITheme.label(Loc.t("menu.car"), 22, UITheme.CAUTION, true))
	_car_buttons.clear()
	for id in ["nexia2", "cobalt_at"]:
		var b := UITheme.button("", 20, 70)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = Loc.t("car." + id) + "\n" + Loc.t("car." + id + "_desc")
		b.add_theme_font_size_override("font_size", 19)
		b.button_pressed = str(Settings.get_value("car")) == id
		var cid: String = id
		b.pressed.connect(func() -> void:
			Settings.set_value("car", cid)
			if _menu_car:
				_menu_car.configure(cid)
			for k in _car_buttons:
				_car_buttons[k].button_pressed = k == cid)
		_car_buttons[id] = b
		cv.add_child(b)
	_stats = UITheme.label("", 19, UITheme.TEXT_DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_stats)
	_update_stats()


func _menu_button(title_key: String, desc_key: String, primary: bool, action: Callable) -> Button:
	var b := UITheme.primary_button("") if primary else UITheme.button("")
	b.custom_minimum_size = Vector2(0, 84)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = Loc.t(title_key) + "\n" + Loc.t(desc_key)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(action)
	return b


func _update_stats() -> void:
	if _stats == null or not is_instance_valid(_stats):
		return
	if Session.history.is_empty():
		_stats.text = Loc.t("menu.no_history")
		return
	var best := Session.best_exam_score()
	var lines := [Loc.t("menu.passes", [Session.pass_count()])]
	if best >= 0:
		lines.append(Loc.t("menu.best", [best]))
	_stats.text = "\n".join(lines)


func _start(mode: Session.Mode, exercise := "", demo := false) -> void:
	_clear_content()
	var c := CenterContainer.new()
	_content.add_child(c)
	c.add_child(UITheme.label(Loc.t("menu.loading"), 36, UITheme.TEXT, true))
	await get_tree().process_frame
	await get_tree().process_frame
	Session.start(mode, exercise, demo)


# ------------------------------------------------------------------ sub-screens
func _screen(title_key: String) -> VBoxContainer:
	_clear_content()
	_on_home = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var back := UITheme.button("‹  " + Loc.t("menu.back"), 24, 70)
	back.custom_minimum_size.x = 200
	back.pressed.connect(_show_home)
	head.add_child(back)
	var t := UITheme.label(Loc.t(title_key), 34, UITheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(200, 0)
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
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return list


func _show_practice() -> void:
	var v := _screen("menu.choose_exercise")
	var bg := PanelContainer.new()
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
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
		var b := UITheme.button("%d.  %s" % [n, Loc.pick(e["name"])], 20, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ex_id := id
		b.pressed.connect(func() -> void: _start(Session.Mode.PRACTICE, ex_id))
		cell.add_child(b)
		# Watch the instructor (autopilot) do it first.
		var demo := UITheme.button("▶", 22, 84)
		demo.custom_minimum_size.x = 76
		demo.tooltip_text = Loc.t("menu.demo")
		demo.pressed.connect(func() -> void: _start(Session.Mode.PRACTICE, ex_id, true))
		cell.add_child(demo)
		grid.add_child(cell)
	var note := UITheme.label("▶  " + Loc.t("menu.demo_hint"), 18, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)


func _show_rules() -> void:
	var v := _screen("menu.rules")
	var list := _scroll_list(v)
	var colors := {"kichik": UITheme.CAUTION, "orta": Color(1.0, 0.55, 0.2), "qopol": UITheme.STOP}
	for g in PenaltyTable.groups():
		var gt := UITheme.label(Loc.pick(g["title"]), 24, colors.get(g["level"], UITheme.TEXT), true)
		list.add_child(gt)
		for it in g["items"]:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.045), 12, 0, UITheme.LINE, 14))
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 14)
			p.add_child(h)
			var num := UITheme.label(str(int(it["no"])), 20, UITheme.TEXT_FAINT, true)
			num.custom_minimum_size = Vector2(36, 0)
			h.add_child(num)
			var txt := UITheme.label(Loc.pick(it["text"]), 19, UITheme.TEXT)
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(txt)
			var pts := "%d %s" % [int(it["points"]), Loc.t("hud.points")]
			if it.has("note"):
				pts += "\n" + Loc.pick(it["note"])
			var pl := UITheme.label(pts, 19, colors.get(g["level"], UITheme.TEXT), true)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pl.custom_minimum_size = Vector2(150, 0)
			pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_child(pl)
			list.add_child(p)
	var note := UITheme.label(Loc.t("res.rule"), 18, UITheme.TEXT_DIM)
	list.add_child(note)


func _show_history() -> void:
	var v := _screen("menu.history")
	var list := _scroll_list(v)
	if Session.history.is_empty():
		list.add_child(UITheme.label(Loc.t("menu.no_history"), 22, UITheme.TEXT_DIM))
		return
	for r in Session.history:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.045), 12, 0, UITheme.LINE, 16))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		p.add_child(h)
		var passed: bool = r.get("passed", false)
		var badge := UITheme.label("✓" if passed else "✗", 28, UITheme.GO if passed else UITheme.STOP, true)
		h.add_child(badge)
		var info := UITheme.label("%s   ·   %s   ·   %s" % [str(r.get("date", "")).replace("T", " "),
				Loc.t("res.total", [int(r.get("penalty", 0))]), UITheme.clock(float(r.get("time", 0)))], 20, UITheme.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		list.add_child(p)


func _show_help() -> void:
	var v := _screen("help.title")
	var list := _scroll_list(v)
	for key in ["help.touch", "help.keyboard", "help.auto"]:
		var l := UITheme.label(Loc.t(key), 21, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)


func _show_settings() -> void:
	_clear_content()
	_on_home = false
	var s := SettingsPanel.new()
	s.closed.connect(func() -> void:
		s.queue_free()
		_settings_panel = null
		_show_home())
	_ui.add_child(s)
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
