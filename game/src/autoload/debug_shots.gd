extends Node
## Command-line helpers for automated visual checks (arguments after "--"):
##   --shots=<dir>        save a screenshot every --shot-every seconds
##   --shot-every=<s>     interval (default 2)
##   --quit-after-s=<s>   quit after this many seconds of game time
##   --menu-page=<name>   open a main-menu page (practice, rules, settings, history, help)
##   --perf               print frame / physics time, draw calls and memory every 2 s
## Inactive unless one of them is given.

var shot_dir := ""
var every := 2.0
var quit_after := -1.0
var menu_page := ""
var perf := false
var _perf_t := 0.0
var _frames := 0
var _t := 0.0
var _shot_t := 0.0
var _n := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shot_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(shot_dir)
		elif arg.begins_with("--shot-every="):
			every = float(arg.substr(13))
		elif arg.begins_with("--quit-after-s="):
			quit_after = float(arg.substr(15))
		elif arg.begins_with("--menu-page="):
			menu_page = arg.substr(12)
		elif arg == "--perf":
			perf = true
			# Uncapped: the frame rate then shows how much work a frame is.
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
	set_process(shot_dir != "" or quit_after > 0.0 or perf)


func _process(delta: float) -> void:
	_t += delta
	if perf:
		_frames += 1
		_perf_t += delta
		if _perf_t >= 2.0:
			var P := Performance
			print("PERF fps=%.0f frame=%.1fms process=%.2fms physics=%.2fms draws=%d prims=%dk objs=%d tex=%dMB vmem=%dMB" % [
				_frames / _perf_t, _perf_t / _frames * 1000.0,
				P.get_monitor(P.TIME_PROCESS) * 1000.0, P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0,
				P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				P.get_monitor(P.RENDER_TOTAL_OBJECTS_IN_FRAME), P.get_monitor(P.RENDER_TEXTURE_MEM_USED) / 1048576,
				P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576])
			_perf_t = 0.0
			_frames = 0
	if shot_dir != "":
		_shot_t += delta
		if _shot_t >= every:
			_shot_t = 0.0
			_n += 1
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join("shot_%03d.png" % _n))
	if quit_after > 0.0 and _t > quit_after:
		get_tree().quit()
