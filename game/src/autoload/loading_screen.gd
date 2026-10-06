extends CanvasLayer
## Full-screen loading page over scene changes (app start, menu -> drive,
## drive -> menu, restart), so the player never looks at a black screen
## while the course, the car and the shaders are prepared.
##
##   await Loading.cover("load.drive")   # drawn on screen when this returns
##   ... heavy synchronous work / change_scene ...
##   Loading.finish()                    # the new scene is ready
##
## The building itself is synchronous, so the page is drawn before it starts
## and stays up for a few frames afterwards while the GPU compiles the new
## scene's pipelines (that first frame is the slow one), then fades out.

const BRAND_MARK := preload("res://assets/ui/brand_mark.png")
const BRAND_FONT := preload("res://assets/fonts/Montserrat-ExtraBold.ttf")
## The brand's dark greens (brand/README.md: app background #14532D → #052E1B).
const BG_TOP := Color(0.07, 0.25, 0.15)
const BG_BOTTOM := Color(0.02, 0.12, 0.07)
const TIPS := ["load.tip1", "load.tip2", "load.tip3", "load.tip4"]
## Frames the page stays up after finish(): the scene renders underneath.
const HOLD_FRAMES := 4
const FADE := 0.3
## No new loading step for this long: the load has stalled (a script error
## stopped it, or the device cannot cope). The page then says where it stopped
## and offers a way back instead of hanging on for ever.
const STALL_S := 30.0

var _page: Control
var _status_key := ""
var _warm_text := ""
var _warm_t := 0
var _tip_key := ""
var _shown := 0.0 # progress bar as drawn
var _target := 0.0
var _spin := 0.0
var _hold := -1
var _fade := 0.0
var _uncovered := Callable()
## The loading step now under way (Loading.stage()), for the log and the
## stall message, and the times the load and the step began (ms).
var _stage := ""
var _load_t0 := 0
var _stage_t0 := 0
var _wait := 0.0
var _stall_box: Control
## Hang guard: a file written before heavy work (a scene behind this page, a
## car switch in the menu) and removed once GUARD_FRAMES frames have been drawn
## after it. Still there at the next start = the app froze (a GPU driver stuck
## creating pipelines blocks the whole program, so nothing can report it while
## it happens): the game then falls back to safe graphics by itself.
const GUARD_PATH := "user://hang_guard.cfg"
const OVERRIDE_PATH := "user://graphics_override.cfg"
const GUARD_FRAMES := 30
var _guard_frames := -1
## Watchdog: a thread that sees the frames stop while a guard is up. On Vulkan
## that is a driver stuck building pipelines: it switches to OpenGL and starts
## the game again at once (phones: closes it, the next start is on OpenGL).
const HANG_S := 20.0
var _beat := 0 # ticks of the last frame
var _armed := false # a guard is up
var _suspended := false # app in the background: no frames, no hang
var _on_opengl := false
var _watch: Thread
var _watch_run := false
## Set at start-up when the last run froze: the main menu tells the player.
var safe_mode_notice := ""


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_STOP # nothing underneath is usable yet
	_page.draw.connect(_draw_page)
	add_child(_page)
	visible = false
	_on_opengl = opengl_mode()
	_pick_renderer()
	_check_last_run()
	_start_watchdog()
	# Up from the very first frame: the main menu builds its 3D backdrop next.
	_show("load.world")


func is_covering() -> bool:
	return visible


## Shows the page and returns once it has been drawn, so the caller can start
## blocking work. Safe to call when it is already up.
func cover(status_key: String) -> void:
	_show(status_key)
	await get_tree().process_frame
	await get_tree().process_frame


## The new scene is built: fill the bar, let it render a few frames, fade out.
## `uncovered` runs when the page starts to fade (at once if it is not up).
func finish(uncovered := Callable()) -> void:
	_uncovered = uncovered
	if not visible:
		get_tree().root.disable_3d = false
		_run_uncovered()
		return
	_clear_stall()
	if _load_t0 > 0:
		print("LOAD done %s in %d ms" % [_status_key, Time.get_ticks_msec() - _load_t0])
	if ShaderWarmup.enabled() and get_tree().current_scene:
		var t0 := _load_t0
		await ShaderWarmup.warm(get_tree().current_scene, _warm_progress)
		if _load_t0 != t0:
			return # another load took over meanwhile
	_target = 1.0
	guard_end()
	_hold = HOLD_FRAMES


## One shader step: the bar moves, and once the steps are slow (shaders being
## compiled, not read from the cache) the page says what it is doing.
func _warm_progress(done: int, total: int) -> void:
	var now := Time.get_ticks_msec()
	if done > 0 and now - _warm_t > 120:
		_warm_text = "%s %d/%d" % [Loc.t("load.shaders"), done, total]
	_warm_t = now
	_wait = 0.0
	_target = maxf(_target, 0.5 + 0.5 * float(done) / maxf(total, 1))
	_page.queue_redraw()


func _run_uncovered() -> void:
	var cb := _uncovered
	_uncovered = Callable()
	if cb.is_valid():
		cb.call()


func _show(status_key: String) -> void:
	if not visible or _hold >= 0 or _fade > 0.0:
		_shown = 0.0
		_target = 0.12
		_tip_key = TIPS[randi() % TIPS.size()]
	_status_key = status_key
	_warm_text = ""
	ShaderWarmup.hide_3d(get_tree())
	if OS.has_feature("web") and not Settings.get_value("web_warm"):
		# The browser compiles every shader on the first visit (tens of
		# seconds on Windows, where WebGL runs through Direct3D); it keeps
		# them, so later visits load in a second or two.
		_tip_key = "load.first_web"
	_uncovered = Callable() # its scene is on the way out
	_load_t0 = Time.get_ticks_msec()
	_stage_t0 = _load_t0
	_stage = status_key
	_wait = 0.0
	_clear_stall()
	print("LOAD begin %s" % status_key)
	guard_begin(status_key)
	_hold = -1
	_fade = 0.0
	_page.modulate.a = 1.0
	visible = true
	_page.queue_redraw()


func _process(delta: float) -> void:
	_beat = Time.get_ticks_msec()
	if _guard_frames > 0:
		_guard_frames -= 1
		if _guard_frames == 0:
			_guard_frames = -1
			_armed = false
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD_PATH))
			print("GUARD clear (frames drawn)")
	if not visible:
		return
	_spin += delta
	if _hold < 0 and _fade == 0.0:
		_wait += delta
		if _wait > STALL_S and _stall_box == null:
			_show_stall()
	# While waiting the bar creeps on (the work gives no progress of its own).
	if _target < 0.9:
		_target = minf(0.9, _target + delta * 0.25)
	_shown = move_toward(_shown, _target, delta * 2.5)
	if _hold > 0:
		_hold -= 1
	elif _hold == 0:
		if _fade == 0.0:
			if _load_t0 > 0:
				print("LOAD uncovered %s after %d ms" % [_status_key, Time.get_ticks_msec() - _load_t0])
			if _status_key == "load.drive" and OS.has_feature("web"):
				Settings.set_value("web_warm", true)
			_run_uncovered()
		_fade += delta
		_page.modulate.a = 1.0 - clampf(_fade / FADE, 0.0, 1.0)
		if _fade >= FADE:
			visible = false
			_hold = -1
			_fade = 0.0
	_page.queue_redraw()


## Heavy work starts now: if the app freezes in it, the next start knows.
func guard_begin(tag: String) -> void:
	if not _guard_enabled():
		return
	_guard_frames = -1
	var cfg := ConfigFile.new()
	cfg.set_value("guard", "tag", tag)
	cfg.set_value("guard", "renderer", RenderingServer.get_current_rendering_method())
	cfg.set_value("guard", "time", Time.get_datetime_string_from_system())
	cfg.save(GUARD_PATH)
	print("GUARD begin %s" % tag)
	_beat = Time.get_ticks_msec()
	_armed = true


## The work is done: the guard goes once GUARD_FRAMES frames have been drawn
## (the first frames of a new scene are where the GPU builds its pipelines).
func guard_end() -> void:
	_guard_frames = GUARD_FRAMES


static func opengl_mode() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Writes (or removes) the override that starts the game on OpenGL. Takes
## effect at the next start.
## Always explicit: phones start on OpenGL by default, desktops on Vulkan.
## Safe from any thread (the watchdog calls it).
static func set_opengl_mode(on: bool) -> void:
	var method := "gl_compatibility" if on else "mobile"
	var f := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
	if f:
		f.store_string('[rendering]\n\nrenderer/rendering_method="%s"\n' % method +
				'renderer/rendering_method.mobile="%s"\n' % method)
		f.close()
	print("graphics override: OpenGL %s" % ("on" if on else "off"))


## Restarts the app (desktop); on phones the player reopens it.
func restart_app() -> void:
	if OS.has_feature("mobile"):
		get_tree().quit()
		return
	OS.set_restart_on_exit(true, _start_args())
	get_tree().quit()


## This run's command line, the user arguments after "--" included.
static func _start_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	return args


## Starts again right now, before anything else is built (a quit() would let
## this frame build the menu's world first, on the renderer that froze).
## Phones cannot start themselves: they close. Safe from any thread.
static func relaunch_now() -> void:
	print("RELAUNCH")
	if not OS.has_feature("mobile"):
		OS.create_process(OS.get_executable_path(), _start_args())
	OS.kill(OS.get_process_id())


## First start on a desktop with an integrated GPU (the AMD/Intel laptop
## chips whose Vulkan drivers hang building pipelines): OpenGL from the start.
## Once only: the player may turn Vulkan back on in the settings.
func _pick_renderer() -> void:
	if not _guard_enabled() or OS.has_feature("mobile") or _on_opengl:
		return
	if Settings.get_value("renderer_checked"):
		return
	Settings.set_value("renderer_checked", true)
	if FileAccess.file_exists(OVERRIDE_PATH):
		return
	var kind := RenderingServer.get_video_adapter_type()
	print("GPU %s (type %d)" % [RenderingServer.get_video_adapter_name(), kind])
	if kind != RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return
	set_opengl_mode(true)
	if not "--no-restart" in OS.get_cmdline_user_args():
		relaunch_now()


func _start_watchdog() -> void:
	if not _guard_enabled() or _on_opengl:
		return # nothing safer to fall back to
	_beat = Time.get_ticks_msec()
	_watch_run = true
	_watch = Thread.new()
	_watch.start(_watchdog)


func _watchdog() -> void:
	while _watch_run:
		OS.delay_msec(500)
		if not _armed or _suspended:
			continue
		var still := Time.get_ticks_msec() - _beat
		if still < HANG_S * 1000.0:
			continue
		# The main thread is stuck: nothing there can run any more.
		print("WATCHDOG no frame for %d ms: OpenGL and restart" % still)
		var cfg := ConfigFile.new()
		cfg.load(GUARD_PATH)
		cfg.set_value("guard", "recovered", true)
		cfg.save(GUARD_PATH)
		set_opengl_mode(true)
		relaunch_now()
		return


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_suspended = OS.has_feature("mobile") or what == NOTIFICATION_APPLICATION_PAUSED
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_beat = Time.get_ticks_msec()
			_suspended = false


func _exit_tree() -> void:
	if _watch:
		_watch_run = false
		_watch.wait_to_finish()
		_watch = null


## Exported builds only (and "--guard-test"): runs from the editor and the
## automated checks are cut off mid-load all the time.
static func _guard_enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not OS.is_debug_build() or "--guard-test" in OS.get_cmdline_user_args()


func _check_last_run() -> void:
	if not _guard_enabled() or not FileAccess.file_exists(GUARD_PATH):
		return
	var cfg := ConfigFile.new()
	cfg.load(GUARD_PATH)
	var tag := str(cfg.get_value("guard", "tag", "?"))
	var was := str(cfg.get_value("guard", "renderer", "?"))
	var recovered := bool(cfg.get_value("guard", "recovered", false))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD_PATH))
	push_warning("last run froze in '%s' (renderer %s): safe graphics" % [tag, was])
	# Lightest settings in any case.
	Settings.set_value("quality", 0)
	Settings.set_value("quality_user", false)
	Settings.set_value("shadows", false)
	Settings.set_value("traffic", false)
	if not _on_opengl:
		set_opengl_mode(true)
		safe_mode_notice = Loc.t("safe.opengl")
		if not OS.has_feature("mobile") and not "--no-restart" in OS.get_cmdline_user_args():
			# The next start tells the player (the mark stays for it).
			cfg.set_value("guard", "recovered", true)
			cfg.save(GUARD_PATH)
			relaunch_now()
	elif recovered:
		# The watchdog already switched and restarted: say what happened.
		safe_mode_notice = Loc.t("safe.auto")
	else:
		safe_mode_notice = Loc.t("safe.low")


## Marks the start of a loading step: logged with the time the last one took,
## and shown if the load stalls in it.
func stage(name: String) -> void:
	var now := Time.get_ticks_msec()
	print("LOAD step %s (previous %s took %d ms)" % [name, _stage, now - _stage_t0])
	_stage = name
	_stage_t0 = now
	_wait = 0.0


func _show_stall() -> void:
	push_error("LOAD stalled in step '%s' after %.0f s" % [_stage, _wait])
	_stall_box = PanelContainer.new()
	_stall_box.theme = UITheme.get_theme()
	_stall_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.08, 0.07, 0.95), 18, 2, UITheme.CAUTION, 22))
	_stall_box.set_anchors_preset(Control.PRESET_CENTER)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_stall_box.add_child(v)
	v.add_child(UITheme.label(Loc.t("load.stalled"), 26, UITheme.CAUTION, true))
	var d := UITheme.label(Loc.t("load.stalled_desc", [_stage]), 18, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(520, 0)
	v.add_child(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var copy := UITheme.button(Loc.t("load.copy_log"), 19, 56)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(diagnostics())
		copy.text = Loc.t("load.copied"))
	row.add_child(copy)
	var back := UITheme.button(Loc.t("load.to_menu"), 19, 56)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		_clear_stall()
		Session.back_to_menu())
	row.add_child(back)
	_page.add_child(_stall_box)
	_stall_box.reset_size()
	_stall_box.position = (_page.size - _stall_box.size) * 0.5


func _clear_stall() -> void:
	if _stall_box:
		_stall_box.queue_free()
		_stall_box = null


## The device, the renderer, the settings and the end of the log, as text to
## send to the developer (copied to the clipboard from the stall message and
## from Settings → About).
static func diagnostics(lines := 250) -> String:
	var out := PackedStringArray()
	out.append("AvtoSmart Avtodrom %s" % str(ProjectSettings.get_setting("application/config/version", "?")))
	out.append("OS: %s %s, model: %s, CPUs: %d" % [OS.get_name(), OS.get_version(), OS.get_model_name(),
			OS.get_processor_count()])
	out.append("GPU: %s / %s, API %s, renderer %s" % [RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
			RenderingServer.get_current_rendering_method()])
	out.append("native module: %s" % ("ok" if ClassDB.class_exists("AvtoVehicle") else "NOT LOADED"))
	out.append("settings: quality=%s car=%s traffic=%s mirrors=%s shadows=%s" % [Settings.get_value("quality"),
			Settings.get_value("car"), Settings.get_value("traffic"), Settings.get_value("mirrors"),
			Settings.get_value("shadows")])
	# The previous run first (after a hang the app was restarted), then this one.
	var older := PackedStringArray()
	for f in DirAccess.get_files_at("user://logs"):
		if f.begins_with("godot") and f != "godot.log":
			older.append(f)
	older.sort()
	if not older.is_empty():
		out.append("---- previous run: %s ----" % older[older.size() - 1])
		out.append_array(_tail("user://logs/" + older[older.size() - 1], lines / 2))
	out.append("---- this run ----")
	out.append_array(_tail("user://logs/godot.log", lines))
	return "\n".join(out)


static func _tail(path: String, lines: int) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray(["(no log: %s)" % error_string(FileAccess.get_open_error())])
	var all := f.get_as_text().split("\n")
	return all.slice(maxi(0, all.size() - lines))


func _draw_page() -> void:
	var sz := _page.size
	var vp := _page.get_viewport_rect().size
	if sz.x < 1.0:
		sz = vp
	# Background: the brand's dark green, lighter at the top.
	var bands := 32
	for i in bands:
		var y0 := sz.y * i / bands
		_page.draw_rect(Rect2(0, y0, sz.x, sz.y / bands + 1.0), BG_TOP.lerp(BG_BOTTOM, float(i) / (bands - 1)))
	var cx := sz.x * 0.5
	var unit := minf(sz.y, sz.x * 0.6)
	# The AvtoSmart mark, breathing gently, a soft glow behind it.
	var wd := unit * 0.3 * (1.0 + sin(_spin * 2.2) * 0.025)
	var wc := Vector2(cx, sz.y * 0.34)
	for k in 14:
		_page.draw_circle(wc, wd * (0.52 + k * 0.045), Color(0.29, 0.87, 0.5, 0.016))
	_page.draw_texture_rect(BRAND_MARK, Rect2(wc - Vector2(wd, wd) * 0.5, Vector2(wd, wd)), false)
	# Brand name and tagline.
	var reg := UITheme.regular()
	_centered(BRAND_FONT, "AvtoSmart", wc.y + wd * 0.5 + unit * 0.1, int(unit * 0.07), UITheme.TEXT)
	_centered(BRAND_FONT, Loc.t("app.title").to_upper(), wc.y + wd * 0.5 + unit * 0.155, int(unit * 0.04),
			Color(0.29, 0.87, 0.5))
	_centered(reg, Loc.t("app.tagline"), wc.y + wd * 0.5 + unit * 0.205, int(unit * 0.03), Color(0.73, 0.97, 0.82, 0.85))
	# Progress bar.
	var bw := minf(sz.x * 0.5, unit * 0.9)
	var bh := maxf(6.0, unit * 0.014)
	var by := sz.y * 0.8
	var bar := Rect2(cx - bw * 0.5, by, bw, bh)
	_page.draw_rect(bar, Color(1, 1, 1, 0.1))
	_page.draw_rect(Rect2(bar.position, Vector2(bw * clampf(_shown, 0.0, 1.0), bh)), Color(0.64, 0.9, 0.21))
	_centered(reg, _warm_text if _warm_text != "" else Loc.t(_status_key), by - unit * 0.035, int(unit * 0.036), UITheme.TEXT)
	if _tip_key != "":
		_centered(reg, Loc.t(_tip_key), by + bh + unit * 0.065, int(unit * 0.032), UITheme.TEXT_FAINT)


func _centered(f: Font, text: String, baseline: float, fs: int, color: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_page.draw_string(f, Vector2(_page.size.x * 0.5 - w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			color)
