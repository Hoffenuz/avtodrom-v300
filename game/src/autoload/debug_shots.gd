extends Node
## Command-line helpers for automated visual checks (arguments after "--"):
##   --shots=<dir>        save a screenshot every --shot-every seconds
##   --shot-every=<s>     interval (default 2)
##   --quit-after-s=<s>   quit after this many seconds of game time
##   --menu-page=<name>   open a main-menu page (practice, rules, settings, history, help)
## Inactive unless one of them is given.

var shot_dir := ""
var every := 2.0
var quit_after := -1.0
var menu_page := ""
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
	set_process(shot_dir != "" or quit_after > 0.0)


func _process(delta: float) -> void:
	_t += delta
	if shot_dir != "":
		_shot_t += delta
		if _shot_t >= every:
			_shot_t = 0.0
			_n += 1
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join("shot_%03d.png" % _n))
	if quit_after > 0.0 and _t > quit_after:
		get_tree().quit()
