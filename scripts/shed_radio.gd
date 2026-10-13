class_name ShedRadio
extends Node3D
## The workshop radio on its shelf. Its on/off switch and station live in the Shed state, so
## everyone in the session hears the same station; each player's game streams it itself.

var _speaker: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _stream: RadioStream
var _display: Label3D
var _dial_light: MeshInstance3D
var _sig := ""


func _ready() -> void:
	var body := _box(Vector3(0.0, 0.13, 0.0), Vector3(0.46, 0.26, 0.16), _mat(Color(0.42, 0.12, 0.08), 0.1, 0.45))
	body.name = "Cabinet"
	_box(Vector3(-0.1, 0.13, 0.081), Vector3(0.2, 0.18, 0.01), _mat(Color(0.75, 0.68, 0.52), 0.0, 0.9))  # grille cloth
	for i in 5:
		_box(Vector3(-0.1, 0.06 + i * 0.035, 0.087), Vector3(0.2, 0.006, 0.004), _mat(Color(0.8, 0.78, 0.72), 1.0, 0.25))
	var dial := _box(Vector3(0.12, 0.17, 0.082), Vector3(0.17, 0.07, 0.006), _mat(Color(0.95, 0.85, 0.55), 0.0, 0.4))
	dial.name = "Dial"
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.6, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.15)
	glow.emission_energy_multiplier = 3.0
	_dial_light = _box(Vector3(0.12, 0.17, 0.086), Vector3(0.005, 0.06, 0.004), glow)
	for x in [0.07, 0.17]:
		var knob := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.022
		c.bottom_radius = 0.025
		c.height = 0.025
		knob.mesh = c
		knob.material_override = _mat(Color(0.1, 0.08, 0.07), 0.2, 0.4)
		knob.position = Vector3(x, 0.08, 0.09)
		knob.rotation.x = PI * 0.5
		add_child(knob)
	var aerial := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.003
	rod.bottom_radius = 0.004
	rod.height = 0.45
	aerial.mesh = rod
	aerial.material_override = _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15)
	aerial.position = Vector3(0.18, 0.45, -0.04)
	aerial.rotation.z = -0.35
	add_child(aerial)
	_display = Label3D.new()
	_display.font_size = 28
	_display.pixel_size = 0.0022
	_display.outline_size = 6
	_display.modulate = Color(1.0, 0.85, 0.55)
	_display.position = Vector3(0.0, 0.36, 0.05)
	_display.width = 420.0
	_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_display)
	# Something to aim at.
	var target := StaticBody3D.new()
	target.collision_layer = Workshop.INTERACT_LAYER
	target.collision_mask = 0
	target.set_meta("radio", true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.32, 0.22)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.14, 0.0)
	target.add_child(cs)
	add_child(target)

	_speaker = AudioStreamPlayer3D.new()
	_speaker.bus = "Radio"
	_speaker.unit_size = 7.0
	_speaker.max_distance = 70.0
	_speaker.position = Vector3(-0.1, 0.13, 0.1)
	add_child(_speaker)
	_hiss = Sfx.make_loop_player(self)
	_hiss.bus = "Radio"
	_hiss.volume_db = -18.0
	_stream = RadioStream.new()
	_stream.player = _speaker
	add_child(_stream)
	_stream.status_changed.connect(func(_t): _refresh_display())
	sync()


## Matches the Shed's radio: switches on or off and retunes when the station changes.
func sync() -> void:
	var on: bool = Shed.active and Shed.radio["on"] and not Shed.stations.is_empty()
	var station: int = Shed.radio["station"]
	var sig := "%s|%d" % [on, station]
	if sig == _sig:
		return
	if _sig != "":
		Sfx.play_at("switch", global_position, -6.0, self)
	_sig = sig
	if on:
		_stream.tune(str(Shed.stations[station]["url"]))
	else:
		_stream.stop()
	_refresh_display()


func is_on() -> bool:
	return Shed.radio["on"]


## "Groove Salad · Ambient and downtempo", plus what's playing.
func now_playing() -> String:
	if not is_on():
		return "Off"
	var st: Dictionary = Shed.stations[Shed.radio["station"]]
	var line := "%s  ·  %s" % [st["name"], st["genre"]]
	if _stream.title != "":
		line += "\n" + _stream.title
	elif _stream.status != "" and _stream.status != "On air":
		line += "\n" + _stream.status
	return line


func _refresh_display() -> void:
	_display.text = "" if not is_on() else now_playing()
	_dial_light.visible = is_on()
	_dial_light.position.x = 0.05 + 0.14 * (float(Shed.radio["station"]) / maxf(1.0, Shed.stations.size() - 1.0))
	# No signal: let the static through instead of silence.
	Sfx.set_loop(_hiss, "static" if is_on() and not _stream.is_live() else "")


func _process(_delta: float) -> void:
	if is_on() and _hiss.playing == _stream.is_live():
		_refresh_display()


func _box(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m
