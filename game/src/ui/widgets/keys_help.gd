class_name KeysHelp
extends RefCounted
## The keyboard's controls, grouped, each key drawn as a keycap: used by the
## settings (Controls) and the in-game F1 sheet. Must match DriverControls.

## [group title, [[keys], text key], ...]; "/" between keys means "or".
const GROUPS := [
	["keys.grp_drive", [
		[["W", "/", "↑"], "keys.gas"],
		[["S", "/", "↓"], "keys.brake"],
		[["A", "D", "/", "←", "→"], "keys.steer"],
		[["Shift", "/", "C"], "keys.clutch"],
		[["Space"], "keys.handbrake"],
	]],
	["keys.grp_gears", [
		[["1", "2", "3", "4", "5"], "keys.gear_n"],
		[["0", "/", "N"], "keys.neutral"],
		[["6", "/", "R"], "keys.reverse"],
		[["PgUp", "PgDn"], "keys.gear_step"],
		[["P", "R", "N", "G"], "keys.auto"],
	]],
	["keys.grp_cabin", [
		[["I"], "keys.ignition"],
		[["B"], "keys.belt"],
		[["Q", "E"], "keys.indicators"],
		[["H"], "keys.hazard"],
		[["L"], "keys.lights"],
	]],
	["keys.grp_view", [
		[["V"], "keys.camera"],
		[["keys.mouse"], "keys.look"],
		[["F1"], "keys.help"],
		[["F11"], "keys.fullscreen"],
		[["Esc"], "keys.pause"],
	]],
]


## The groups in `columns` columns (1 for a narrow panel); `text_w`: the
## descriptions' width (0 = as narrow as the panel allows).
static func build(columns := 1, font := 17, text_w := 0.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	var cols: Array[VBoxContainer] = []
	for c in columns:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		cols.append(v)
	for gi in GROUPS.size():
		var g: Array = GROUPS[gi]
		var col := cols[gi * columns / GROUPS.size()]
		if col.get_child_count() > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			col.add_child(gap)
		col.add_child(UITheme.label(Loc.t(g[0]), font + 3, UITheme.GO, true))
		for item: Array in g[1]:
			col.add_child(_line(item[0], Loc.t(item[1]), font, text_w))
	return row


static func _line(keys: Array, text: String, font: int, text_w: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var caps := HBoxContainer.new()
	caps.add_theme_constant_override("separation", 5)
	caps.custom_minimum_size = Vector2(font * 12.5, 0)
	for k: String in keys:
		if k == "/":
			var sep := UITheme.label("/", font, UITheme.TEXT_DIM)
			caps.add_child(sep)
		else:
			caps.add_child(keycap(Loc.t(k) if k.begins_with("keys.") else k, font))
	h.add_child(caps)
	var l := UITheme.label(text, font, UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(text_w if text_w > 0.0 else font * 14.0, 0)
	h.add_child(l)
	return h


## A key as on the keyboard: a raised cap with its label.
static func keycap(text: String, font := 17) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UITheme.box(Color(0.2, 0.215, 0.235), 7, 1, Color(1, 1, 1, 0.22), 0)
	sb.border_width_bottom = 4
	sb.border_color = Color(0.06, 0.065, 0.075)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UITheme.label(text, font - 1, UITheme.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(font * 0.9, 0)
	p.add_child(l)
	return p
