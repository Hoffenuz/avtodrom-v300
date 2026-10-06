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
	"car": "nexia2", # nexia2, gentra (mexanika) | cobalt_at (avtomat) — Car.IDS
	"auto_clutch": true, # manual gearbox: the simulation works the clutch
	"abs": true,
	"steering_mode": "wheel", # wheel | tilt | buttons (on-screen controls)
	# On-screen wheel, pedals and switches: -1 = automatic (phones and
	# tablets yes, computers no), 0 = off, 1 = on.
	"screen_controls": -1,
	# On-screen wheel: 1.5 = one full turn of the finger gives the car's full
	# lock (1.5 steering-wheel turns on the Nexia).
	"steering_sensitivity": 1.5,
	"steering_autocenter": true,
	"camera": "chase", # cockpit | chase | top (the last one used)
	"quality": -1, # -1 = auto, 0 low, 1 medium, 2 high
	"render_scale": -1.0, # 3D resolution; -1 = by quality (phones render below screen resolution)
	"fps_limit": 60,
	"shadows": true,
	"mirrors": true,
	"show_hints": true,
	"show_route": true,
	"vol_master": 0.9,
	"vol_engine": 0.8,
	"vol_effects": 0.8,
	"left_handed": false,
	# On-screen wheel with the indicator buttons above it, as one group:
	# size (1 = standard) and how far it sits from the screen corner, as a
	# share of the safe area's width / height.
	"wheel_scale": 1.1,
	"wheel_shift_x": 0.03,
	"wheel_shift_y": 0.05,
	# Touch controls moved / resized by the player (HudLayoutEditor):
	# control id -> {"x", "y": centre as a share of the safe area, "s": scale}.
	"hud_layout": {},
	"exam_time_limit_min": 25,
	# Other participants: learner cars driving the route with the player.
	"traffic": false,
	"traffic_count": 2,
	# Computers: full screen without a window frame (F11 / Alt+Enter toggle it).
	"fullscreen": true,
	# The player picked the quality in Settings: it is then never lowered
	# automatically.
	"quality_user": false,
	"renderer_checked": false,
	"web_warm": false, # browser: the shaders have been compiled once (the browser keeps them)
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="): # checks: a quality level for this run only
			_values["quality"] = clampi(int(arg.substr(10)), 0, 2)
		if arg.begins_with("--set="): # checks: "--set=key:value" for this run only
			var kv := arg.substr(6).split(":", true, 1)
			if kv.size() == 2 and DEFAULTS.has(kv[0]):
				_values[kv[0]] = str_to_var(kv[1])
		if arg.begins_with("--physics-hz="): # tests: the phones' tick rate on a PC
			Engine.physics_ticks_per_second = int(arg.substr(13))
			Engine.max_physics_steps_per_frame = 3
	_apply_window_mode()
	changed.connect(func(k: String) -> void:
		if k == "fullscreen":
			_apply_window_mode())
	if OS.has_feature("mobile") or OS.has_feature("web"):
		# Phones and browsers: 60 physics ticks (the C++ car model keeps its own 960 Hz
		# substeps) and never more than 3 catch-up ticks in a slow frame.
		Engine.physics_ticks_per_second = 60
		Engine.max_physics_steps_per_frame = 3


## Full screen or a maximised window (computers only; "--windowed" on the
## command line, used by the automated checks, keeps a window).
func _apply_window_mode() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var args := OS.get_cmdline_args()
	if "--windowed" in args or "-w" in args:
		return
	var full := bool(_values.get("fullscreen", true))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_MAXIMIZED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or OS.has_feature("mobile"):
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		set_value("fullscreen", not bool(get_value("fullscreen")))
		get_viewport().set_input_as_handled()


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


## Picks a starting quality level from the hardware. The OpenGL fallback
## (no usable Vulkan) and software GPUs start on Low. Computers: a discrete
## GPU High, an integrated one (most laptops) Medium. Phones start on Low,
## Medium only with a strong GPU (Adreno 640 and up, Mali-G7xx / G610+,
## Immortalis) and 8 cores: a mid-range Mali on High-like settings drew the
## first frames of the avtodrom so slowly that the loading page seemed stuck.
## The drive also steps it down by itself if the frame rate is too low (see
## Drive._watch_frame_rate), as long as the player has not chosen a level.
func detect_quality() -> int:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var kind := RenderingServer.get_video_adapter_type()
	if kind == RenderingDevice.DEVICE_TYPE_CPU or kind == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU \
			or gpu.contains("llvmpipe") or gpu.contains("swiftshader") or gpu.contains("basic render"):
		return 0
	if not OS.has_feature("mobile"):
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			# OpenGL does not say the GPU type: tell a discrete card by its name.
			var discrete := gpu.contains("geforce") or gpu.contains("rtx") or gpu.contains("gtx") \
					or gpu.contains("quadro") or gpu.contains("radeon rx") or gpu.contains("radeon pro") \
					or gpu.contains("arc a") or gpu.contains("arc(tm) a")
			return 1 if discrete else 0
		return 2 if kind == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU else 1
	var strong := false
	var m := RegEx.create_from_string("adreno[^0-9]*([0-9]{3})").search(gpu)
	if m and int(m.get_string(1)) >= 640:
		strong = true
	m = RegEx.create_from_string("mali-g([0-9]{2,3})").search(gpu)
	if m and (int(m.get_string(1)) >= 610 or (int(m.get_string(1)) >= 71 and int(m.get_string(1)) < 100)):
		strong = true
	if gpu.contains("immortalis"):
		strong = true
	return 1 if strong and OS.get_processor_count() >= 8 else 0


## 3D render resolution as a share of the screen: the setting, or by quality
## (phone screens have far more pixels than their GPUs can shade at 60 fps).
func render_scale() -> float:
	var v := float(get_value("render_scale"))
	if v > 0.0:
		return clampf(v, 0.5, 1.0)
	if not is_mobile():
		return 1.0
	return [0.6, 0.72, 0.85][clampi(int(get_value("quality")), 0, 2)]


## Frame cap that divides the display's refresh rate evenly (never below the
## chosen limit): 60 on a 90 Hz phone would show frames for 1, 2, 1, 2
## refreshes, a steady judder; there it runs at 90, on 120 Hz at 60, on
## 144 Hz at 72. 0 = no cap.
func frame_limit() -> int:
	var lim := int(get_value("fps_limit"))
	if lim <= 0:
		return 0
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz < 20.0:
		return lim # unknown refresh rate
	var n := maxi(1, int(floor(hz / float(lim) + 0.05)))
	return int(round(hz / n))


## Whether the on-screen driving controls are shown.
func screen_controls_on() -> bool:
	var v := int(get_value("screen_controls"))
	return is_mobile() if v < 0 else v == 1


func is_mobile() -> bool:
	# "--touch" (after "--") previews the phone layout on a desktop.
	var forced := "--touch" in OS.get_cmdline_user_args()
	return forced or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
