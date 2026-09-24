extends Node
## Persistent user settings (user://settings.cfg).
##
## Every value has a default here; the file only stores what the user changed.
## Graphics settings are applied immediately to the viewport/environment by
## whoever listens to `changed` (see src/game/graphics.gd).

signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULTS := {
	"language": "uz_latn", # uz_latn | uz_cyrl | ru
	"car": "nexia2", # nexia2 (mexanika) | cobalt_at (avtomat)
	"auto_clutch": true, # manual gearbox: the simulation works the clutch
	"abs": true,
	"steering_mode": "wheel", # wheel | tilt | buttons
	"steering_sensitivity": 1.0,
	"steering_autocenter": true,
	"camera": "cockpit", # cockpit | chase | top
	"quality": -1, # -1 = auto, 0 low, 1 medium, 2 high
	"render_scale": 1.0,
	"fps_limit": 60,
	"shadows": true,
	"mirrors": true,
	"show_hints": true,
	"show_route": true,
	"vol_master": 0.9,
	"vol_engine": 0.8,
	"vol_effects": 0.8,
	"vol_voice": 1.0,
	"haptics": true,
	"left_handed": false,
	"ui_scale": 1.0,
	"exam_time_limit_min": 25,
}

var _values: Dictionary = {}


func _ready() -> void:
	_values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in cfg.get_section_keys(SECTION):
			if DEFAULTS.has(key):
				var v: Variant = cfg.get_value(SECTION, key)
				if typeof(v) == typeof(DEFAULTS[key]) or (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
					_values[key] = v
	if int(_values["quality"]) < 0:
		_values["quality"] = detect_quality()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown setting: %s" % key)
		return
	if _values.get(key) == value:
		return
	_values[key] = value
	save()
	changed.emit(key)


func save() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		if _values[key] != DEFAULTS[key]:
			cfg.set_value(SECTION, key, _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings could not be saved (%s)" % error_string(err))


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	_values["quality"] = detect_quality()
	save()
	for key in _values:
		changed.emit(key)


## Picks a starting quality level from the hardware: phones with few cores or
## the OpenGL fallback start on Low; desktops on High.
func detect_quality() -> int:
	if not OS.has_feature("mobile"):
		return 2
	var cores := OS.get_processor_count()
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or method == "gl_compatibility":
		return 0
	if cores >= 8:
		return 1
	return 0


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
