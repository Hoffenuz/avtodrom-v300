class_name ResultsPanel
extends CanvasLayer
## The exam protocol: pass / fail, total penalty against the 100-point
## limit, each error with its official wording and time, and which
## exercises were performed.

signal retry
signal menu

var _box: VBoxContainer


func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func show_result(r: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.theme = UITheme.get_theme()
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var practice: bool = r.get("practice", false)
	var passed: bool = r.get("passed", false)
	var total := int(r.get("penalty", 0))
	var head: String
	var col: Color
	if practice:
		head = Loc.t("res.practice")
		col = UITheme.GO if total == 0 else UITheme.CAUTION
	elif not r.get("completed", false) and not passed:
		head = Loc.t("res.failed")
		col = UITheme.STOP
	else:
		head = Loc.t("res.passed") if passed else Loc.t("res.failed")
		col = UITheme.GO if passed else UITheme.STOP
	var title := UITheme.label(head, 38, col, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	var tot := UITheme.label(Loc.t("res.total", [total]), 26, UITheme.TEXT, true)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(tot)
	if not practice:
		var rule := UITheme.label(Loc.t("res.rule"), 17, UITheme.TEXT_DIM)
		rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(rule)
	var meta := UITheme.label("%s    %s" % [Loc.t("res.time", [UITheme.clock(float(r.get("time", 0)))]),
			Loc.t("res.distance", [int(r.get("distance", 0))])], 18, UITheme.TEXT_DIM)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(meta)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	var entries: Array = r.get("entries", [])
	if entries.is_empty():
		_box.add_child(UITheme.label(Loc.t("res.no_errors"), 22, UITheme.GO, true))
	else:
		_box.add_child(UITheme.label(Loc.t("res.errors"), 20, UITheme.TEXT_DIM, true))
		for e in entries:
			_box.add_child(_entry_row(e))
	if not practice:
		_box.add_child(UITheme.label(Loc.t("res.exercises"), 20, UITheme.TEXT_DIM, true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		for ex in r.get("exercises", []):
			if str(ex["id"]).begins_with("intersection") and str(ex["id"]) != "intersection1":
				continue
			var ok: bool = ex.get("performed", false)
			var l := UITheme.label("%s  %s" % ["✓" if ok else "✗", Loc.pick(ex["name"])], 18,
					UITheme.TEXT if ok else UITheme.STOP)
			grid.add_child(l)
		_box.add_child(grid)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	outer.add_child(buttons)
	var b_retry := UITheme.primary_button(Loc.t("res.retry_practice") if practice else Loc.t("res.retry"))
	b_retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_retry.pressed.connect(func() -> void: retry.emit())
	var b_menu := UITheme.button(Loc.t("res.menu"))
	b_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_menu.pressed.connect(func() -> void: menu.emit())
	buttons.add_child(b_retry)
	buttons.add_child(b_menu)


func _entry_row(e: Dictionary) -> Control:
	var p := PanelContainer.new()
	var pts := int(e["points"])
	var col := UITheme.CAUTION if pts < 20 else (UITheme.STOP if pts >= 50 else Color(1.0, 0.55, 0.2))
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.04), 12, 0, UITheme.LINE, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var badge := UITheme.label("+%d" % pts, 22, col, true)
	badge.custom_minimum_size = Vector2(64, 0)
	h.add_child(badge)
	var txt := UITheme.label("№%d  %s" % [int(e["no"]), PenaltyTable.text(int(e["no"]))], 18, UITheme.TEXT)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	var t := UITheme.label(UITheme.clock(float(e.get("time", 0))), 18, UITheme.TEXT_FAINT)
	h.add_child(t)
	return p
