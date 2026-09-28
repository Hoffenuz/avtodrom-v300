class_name PauseMenu
extends CanvasLayer
## Pause overlay: resume, restart, quick settings, back to the menu (with a
## warning that leaving a running exam costs 100 points — rule №26).

signal resume
signal restart
signal quit_to_menu
signal edit_layout

var _panel: PanelContainer
var _warn: Label
var _restart: Button
var _layout_btn: Button
var _settings: SettingsPanel


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = UITheme.get_theme()
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(_panel)
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.07, 0.09, 0.12, 0.94), 26, 1, UITheme.LINE, 22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var title := UITheme.label(Loc.t("pause.title"), 34, UITheme.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var b_resume := _tile(Loc.t("pause.resume"), "play", UITheme.GO, true)
	b_resume.pressed.connect(func() -> void: resume.emit())
	v.add_child(b_resume)
	_restart = _tile(Loc.t("pause.restart"), "restart", Color(1.0, 0.6, 0.2))
	_restart.pressed.connect(func() -> void: restart.emit())
	v.add_child(_restart)
	var b_settings := _tile(Loc.t("menu.settings"), "gear", UITheme.INFO)
	b_settings.pressed.connect(_open_settings)
	v.add_child(b_settings)
	_layout_btn = _tile(Loc.t("pause.layout"), "wheel", UITheme.CAUTION)
	_layout_btn.pressed.connect(func() -> void: edit_layout.emit())
	v.add_child(_layout_btn)
	var b_menu := _tile(Loc.t("pause.menu"), "exit", UITheme.STOP)
	b_menu.pressed.connect(func() -> void: quit_to_menu.emit())
	v.add_child(b_menu)
	_warn = UITheme.label(Loc.t("pause.warn_exam"), 18, UITheme.STOP)
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_warn)


## During a real exam there is no "start again": leaving counts as a failed
## attempt (№26), like walking away from the examiner.
func open(exam_running: bool, touch_controls := false) -> void:
	visible = true
	_warn.visible = exam_running
	_restart.visible = not exam_running
	_layout_btn.visible = touch_controls
	_panel.visible = true
	# A quick pop-in, as mobile games do.
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	var tw := _panel.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.16)


func _tile(title: String, icon: String, accent: Color, primary := false) -> MenuCard:
	var b := MenuCard.new(title, icon, accent, primary)
	b.custom_minimum_size = Vector2(0, 66)
	return b


func close() -> void:
	visible = false
	if _settings:
		_settings.queue_free()
		_settings = null


## Android "back" while the menu is open: closes the settings page if it is
## showing and returns true; false means the caller should resume.
func back() -> bool:
	if _settings:
		_settings.queue_free()
		_settings = null
		_panel.visible = true
		return true
	return false


func _open_settings() -> void:
	_panel.visible = false
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
		_panel.visible = true)
	add_child(_settings)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		resume.emit()
