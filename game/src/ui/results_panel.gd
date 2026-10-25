class_name ResultsPanel
extends CanvasLayer
## The exam protocol: pass / fail, total penalty against the 100-point
## limit, each error with its official wording and time, and which
## exercises were performed.

signal retry
signal menu

var _box: VBoxContainer
var _rows: Array[Control] = []
var _map: ExamMap
var _note: Label
var _scroll: ScrollContainer
var _entries: Array = []


func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## [param course]: the course driven, for the map (none: no map).
func show_result(r: Dictionary, course: CourseData = null) -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_entries = r.get("entries", [])
	var with_map: bool = course != null and r.get("track", PackedVector2Array()).size() > 1
	visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.theme = UITheme.get_theme()
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180 if with_map else 640, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var practice: bool = r.get("practice", false)
	var passed: bool = r.get("passed", false)
	var total := int(r.get("penalty", 0))
	var head: String
	var col: Color
	if Session.demo:
		head = Loc.t("res.demo")
		col = UITheme.INFO
	elif practice:
		head = Loc.t("res.practice")
		col = UITheme.GO if total == 0 else UITheme.CAUTION
	elif r.get("no_fail", false):
		# "Yiqitish" was off: the points, no verdict.
		head = Loc.t("res.finished")
		col = UITheme.INFO
	else:
		head = Loc.t("res.passed") if passed else Loc.t("res.failed")
		col = UITheme.GO if passed else UITheme.STOP
	var title := UITheme.label(head, 36, col, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	var tot := UITheme.label("%s   ·   %s" % [Loc.t("res.total", [total]),
			Loc.t("res.time", [UITheme.clock(float(r.get("time", 0)))])], 22, UITheme.TEXT, true)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(tot)
	if not practice and not Session.demo:
		var rule := UITheme.label(Loc.t("res.no_fail_note" if r.get("no_fail", false) else "res.rule"), 16,
				UITheme.TEXT_DIM)
		rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	if with_map:
		# The map on the left, the list beside it; a mark tapped is explained
		# under the map, a row tapped lights its mark.
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 14)
		outer.add_child(body)
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 6)
		body.add_child(left)
		_map = ExamMap.new()
		_map.setup(r, course)
		_map.picked.connect(_pick)
		left.add_child(_map)
		_note = UITheme.label(Loc.t("res.map_hint") if not _entries.is_empty() else Loc.t("res.map_legend"),
				16, UITheme.TEXT_DIM)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.custom_minimum_size = Vector2(_map.custom_minimum_size.x, 46)
		left.add_child(_note)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(0, 0)
		body.add_child(scroll)
	else:
		outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	if _entries.is_empty():
		_box.add_child(UITheme.label(Loc.t("res.no_errors"), 22, UITheme.GO, true))
	else:
		_box.add_child(UITheme.label(Loc.t("res.errors"), 18, UITheme.TEXT_DIM, true))
		for i in _entries.size():
			var row := _entry_row(_entries[i], i if with_map else -1)
			_rows.append(row)
			_box.add_child(row)
	if not practice:
		# Exercises not performed (the exam lists only what went wrong).
		var missed := []
		for ex in r.get("exercises", []):
			if not ex.get("performed", false):
				missed.append("✗  " + Loc.pick(ex["name"]))
		if not missed.is_empty():
			_box.add_child(UITheme.label(Loc.t("res.exercises"), 18, UITheme.TEXT_DIM, true))
			var l := UITheme.label("\n".join(missed), 18, UITheme.STOP)
			_box.add_child(l)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	var b_retry := UITheme.primary_button(Loc.t("res.retry_practice") if practice or Session.demo
			else Loc.t("res.retry"), 22, 64)
	b_retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_retry.pressed.connect(func() -> void: retry.emit())
	var b_menu := UITheme.button(Loc.t("res.menu"), 22, 64)
	b_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_menu.pressed.connect(func() -> void: menu.emit())
	buttons.add_child(b_retry)
	buttons.add_child(b_menu)
	# Slide up and fade in over the dimmed drive.
	panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	margin.position.y = 40.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "modulate:a", 1.0, 0.3).set_delay(0.08)
	tw.tween_property(margin, "position:y", 0.0, 0.38).set_delay(0.08)


## A mark on the map or its row picked: the row lit and in view, the rule's
## full wording under the map.
func _pick(i: int) -> void:
	if _map:
		_map.select(i)
	for k in _rows.size():
		_rows[k].add_theme_stylebox_override("panel", _row_box(k == i))
	if i < 0 or i >= _entries.size():
		return
	_scroll.ensure_control_visible(_rows[i])
	var e: Dictionary = _entries[i]
	if _note:
		_note.text = "%d.  №%d  (+%d):  %s" % [i + 1, int(e["no"]), int(e["points"]), PenaltyTable.text(int(e["no"]))]
		_note.add_theme_color_override("font_color", UITheme.TEXT)


func _row_box(lit: bool) -> StyleBoxFlat:
	return UITheme.box(Color(1, 1, 1, 0.12 if lit else 0.04), 10, 2 if lit else 0, UITheme.INFO, 12)


## [param index]: its number on the map (-1: no map).
func _entry_row(e: Dictionary, index := -1) -> Control:
	var p := PanelContainer.new()
	var pts := int(e["points"])
	var col := UITheme.CAUTION if pts < 20 else (UITheme.STOP if pts >= 50 else Color(1.0, 0.55, 0.2))
	p.add_theme_stylebox_override("panel", _row_box(false))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	if index >= 0 and e.has("pos"):
		var num := UITheme.label(str(index + 1), 16, Color(0.06, 0.06, 0.07), true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.custom_minimum_size = Vector2(26, 26)
		var dot := StyleBoxFlat.new()
		dot.bg_color = col
		dot.set_corner_radius_all(13)
		num.add_theme_stylebox_override("normal", dot)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(num)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
				_pick(index))
	var badge := UITheme.label("+%d" % pts, 20, col, true)
	badge.custom_minimum_size = Vector2(56, 0)
	h.add_child(badge)
	var txt := UITheme.label(PenaltyTable.short_text(int(e["no"])), 18, UITheme.TEXT)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	var t := UITheme.label("№%d · %s" % [int(e["no"]), UITheme.clock(float(e.get("time", 0)))], 16, UITheme.TEXT_FAINT)
	h.add_child(t)
	return p
