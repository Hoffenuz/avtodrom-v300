class_name WebEngineSound
extends Node
## The engine's sound in a browser. The web build has no threads, so the
## engine mixes sound on the game's own thread, and with EngineSound (a
## generator refilled each frame) every slow frame was a gap in it. The page
## (shell.html, window.avtodromEngine) runs the same synthesis on the
## browser's audio thread; this only passes the values on, with the same
## setters as EngineSound so Car drives either one.

var volume_db := 0.0
var _rpm := 0.0
var _load := 0.0
var _running := false
var _cranking := false
var _interior := 1.0
var _voice: JavaScriptObject


## Whether the page offers it (an AudioWorklet: every current browser).
static func available() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.avtodromEngine && window.avtodromEngine.ok)", true))


func set_rpm(v: float) -> void:
	_rpm = v


func set_load(v: float) -> void:
	_load = v


func set_running(v: bool) -> void:
	_running = v


func set_cranking(v: bool) -> void:
	_cranking = v


func set_interior(v: float) -> void:
	_interior = v


func _ready() -> void:
	var api := JavaScriptBridge.get_interface("avtodromEngine")
	if api:
		_voice = api.create()


func _process(_delta: float) -> void:
	_send(false)


func _send(hold: bool) -> void:
	if _voice:
		_voice.update(_rpm, _load, _running, _cranking, _interior, db_to_linear(volume_db), hold)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED: # quiet like the game's other players while paused
			_send(true)
		NOTIFICATION_UNPAUSED:
			_send(false)
		NOTIFICATION_EXIT_TREE:
			if _voice:
				_voice.release()
				_voice = null
		NOTIFICATION_ENTER_TREE:
			if _voice == null and is_node_ready():
				_ready()
