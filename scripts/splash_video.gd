class_name SplashVideo
extends CanvasLayer
## The opening film (video/splash.ogv) played over the title screen when the game starts, then
## faded away to show the main menu. Any key, mouse click or pad button skips it. A headless
## run (the tests, the multiplayer pairs) never plays it.

signal finished

const PATH := "res://video/splash.ogv"
## How long the last frame (the Torque Shed title) holds before fading.
const HOLD := 0.4
const FADE := 0.6

var player: VideoStreamPlayer
var _cover: ColorRect
var _done := false


## Starts the film over `parent` (above its UI); null when there's nothing to play.
static func play_over(parent: Node) -> SplashVideo:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(PATH):
		return null
	var s := SplashVideo.new()
	parent.add_child(s)
	return s


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = ColorRect.new()
	_cover.color = Color.BLACK
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	# Kept at 16:9 on a wider or taller window, with black either side.
	var fit := AspectRatioContainer.new()
	fit.ratio = 16.0 / 9.0
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(fit)
	player = VideoStreamPlayer.new()
	player.stream = load(PATH)
	player.expand = true
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(player)
	player.finished.connect(func(): get_tree().create_timer(HOLD).timeout.connect(skip))
	player.play()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


## Ends the film: fades it out and frees it.
func skip() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, FADE)
	tw.tween_callback(func():
		player.stop()
		finished.emit()
		queue_free())
