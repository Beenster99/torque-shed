class_name DynoRoom
extends Node3D
## The tuning room behind the shed's back wall, through a doorway between bays 2 and 3: a
## rolling-road dyno set into the floor (a drum under the rear wheel, a clamp for the front,
## strap-down posts and a cooling fan), the dyno desk where bikes are tuned and run, a big
## screen on the far wall showing the latest run, and a wall-sized TV on the west wall for the crew
## to plan rides on (its home channel is the Route planner, see RouteTv). Wheel a bike in and let go of it near the
## drum and it squares up on the rig (Shed._park); strap it down at the four posts before a run.
## The room has its own lights, a wall switch for the cooling fan, an exhaust extraction hose on
## a hook and ear defenders hanging by the door (Shed.dyno holds their state). A run is the
## same for everyone: the host stores the result on the bike and each player plays it back.

const CENTER := Vector3(0.0, 0.0, 55.6)
const HALF := Vector2(4.5, 3.6)           # interior: x -4.5..4.5, z 52.0..59.2 (the shed's back wall)
const HEIGHT := 3.6
## The doorway through the shed's back wall, centred on x = 0: 1.7 m clear, wide enough to
## wheel a bike through, and narrow enough for full-size bay screens either side of it.
const DOOR_HALF := 0.85
const DOOR_HEIGHT := 2.5
const DRUM_RADIUS := 0.32
const DRUM_Z := 0.71                      # the drum's axle behind the rig's centre, under the rear tyre
const DESK := Vector3(2.9, 0.0, 53.9)
## The cooling fan's level (dB) at rest; it gets louder as a run pushes it.
const FAN_DB := -6.0
## Phases of a run, seconds: a blip at idle, up through the lower gears, settle, the measured
## sweep in the gear nearest 1:1, then coast down.
const IDLE_T := 0.8
const QUICK_T := 0.6
const SETTLE_T := 0.5
const SWEEP_T := 4.0
const COAST_T := 1.2
## The four strap posts round the rig (front left, front right, rear left, rear right), in rig
## space, and where on the bike each strap pulls to.
const STRAP_POSTS := [Vector3(-0.95, 0.0, -0.6), Vector3(0.95, 0.0, -0.6), Vector3(-0.95, 0.0, 0.8), Vector3(0.95, 0.0, 0.8)]
## The extraction hose: where it drops from the ceiling, its hook on the east wall, and how far
## it reaches from the drop.
const HOSE_DROP := Vector3(3.7, 3.45, 56.9)
const HOSE_HOOK := Vector3(4.42, 1.45, 56.9)
const HOSE_REACH := 5.6
## Switches by the door (lights, fan) and the ear defenders' hook, on the shed side wall.
const SWITCHES := Vector3(-1.3, 1.35, 59.17)
const PHONES_HOOK := Vector3(-2.1, 1.62, 59.15)
## The planning TV on the west wall: metres across (most of the wall), and its middle.
const PLAN_TV_WIDTH := 5.0
const PLAN_TV := Vector3(-HALF.x + 0.08, 1.95, 55.6)

var workshop: Workshop
var screen: DynoGraph
## The wall-sized planning TV (screen key "dyno", see TvChannels).
var plan_tv: Dashboard
var _screen_view: SubViewport
var _drum: Node3D
var _fan: Node3D
var _straps: Node3D
var _probe: ReflectionProbe
var _audio: EngineSound
var _mats := {}
var _seen := {}              # bike id -> the dyno run count we've seen, so a new run plays once
var _run_bike := 0
var _run_start := -1.0       # seconds (local clock) the playing run started
var _run_build: BikeBuild
var _drum_angle := 0.0
var _wheel_angle := 0.0
var _fan_speed := 0.0
var _roller_sound: AudioStreamPlayer3D   # the drum whining as it turns
var _screen_sig := ""
var _lights: Array[Light3D] = []
var _fixture: StandardMaterial3D
var _lights_shown := true
var _strap_nodes: Array[Node3D] = []
var _hose_parts: Array[MeshInstance3D] = []
var _hose_end: Node3D
var _hose_end_target: StaticBody3D
var _hose_sig := ""
var _phones: Node3D
var _fan_sound: AudioStreamPlayer3D
var _fan_push := 0.0          # 0..1: how hard the fan's pushed as a run builds
var _rocker_lights: Node3D
var _rocker_fan: Node3D
var _haze: CPUParticles3D
var _fumes: CPUParticles3D
var _haze_level := 0.0


## Where a bike sits on the rig: facing the fan and the far wall (-Z), rear tyre on the drum.
static func rig_transform() -> Transform3D:
	return Transform3D(Basis(), CENTER)


## How long a dyno run takes for this bike.
static func run_time(build: BikeBuild) -> float:
	return IDLE_T + QUICK_T * _quick_gears(build) + SETTLE_T + SWEEP_T + COAST_T


static func _measure_gear(build: BikeBuild) -> int:
	return clampi(build.gear_count() - 1, 1, maxi(build.gear_count(), 1))


static func _quick_gears(build: BikeBuild) -> int:
	return _measure_gear(build) - 1


## What the engine is doing `t` seconds into a run: {rpm, gear (0 neutral), throttle, progress},
## where progress is how far through the measured sweep it is (-1 before it starts).
static func sweep_state(build: BikeBuild, t: float) -> Dictionary:
	var lo := maxf(build.idle_rpm * 1.5, build.redline * 0.2)
	if t < IDLE_T:
		return {"rpm": build.idle_rpm * (1.0 + 0.8 * sin(t / IDLE_T * PI)), "gear": 0, "throttle": 0.35, "progress": -1.0}
	t -= IDLE_T
	var quick := _quick_gears(build)
	if t < quick * QUICK_T:
		var g := int(t / QUICK_T)
		var f := fmod(t, QUICK_T) / QUICK_T
		var from := build.redline * 0.55 if g > 0 else build.idle_rpm * 1.5
		return {"rpm": lerpf(from, build.redline * 0.95, f), "gear": g + 1, "throttle": 1.0, "progress": -1.0}
	t -= quick * QUICK_T
	var gear := _measure_gear(build)
	if t < SETTLE_T:
		return {"rpm": lerpf(build.redline * (0.6 if quick > 0 else 0.3), lo, t / SETTLE_T), "gear": gear, "throttle": 0.15, "progress": 0.0}
	t -= SETTLE_T
	if t < SWEEP_T:
		var f := t / SWEEP_T
		return {"rpm": lerpf(lo, build.redline, f), "gear": gear, "throttle": 1.0, "progress": f}
	t -= SWEEP_T
	var f := clampf(t / COAST_T, 0.0, 1.0)
	return {"rpm": lerpf(build.redline, build.idle_rpm, f), "gear": gear, "throttle": 0.0, "progress": 1.0}


func build(shop: Workshop) -> void:
	workshop = shop
	name = "DynoRoom"
	add_to_group("dyno_room")
	_make_materials()
	_build_shell()
	_build_rig()
	_build_fan()
	_build_desk()
	_build_screen()
	_build_plan_tv()
	_build_decor()
	_build_lights()
	_build_switches()
	_build_hose()
	_build_phones()
	_build_haze()


## How far through its measured sweep the run on a bike is, for the dyno desk: -1 before it
## starts, 1 when done (or when nothing is playing).
func progress_for(bike_id: int) -> float:
	if bike_id != _run_bike or _run_start < 0.0 or _run_build == null:
		return 1.0
	return float(sweep_state(_run_build, _now() - _run_start)["progress"])


## The engine's rpm and gear mid-run, or {}.
func live_for(bike_id: int) -> Dictionary:
	if bike_id != _run_bike or _run_start < 0.0 or _run_build == null:
		return {}
	var st := sweep_state(_run_build, _now() - _run_start)
	return {"rpm": st["rpm"], "gear": st["gear"]}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------------------- running

func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("rooms", pt)


func _process_body(delta: float) -> void:
	if not Shed.active:
		return
	var bike := Shed.dyno_bike()
	var straps: Array = Shed.dyno.get("straps", [])
	for i in _strap_nodes.size():
		_strap_nodes[i].visible = bike != 0 and i < straps.size() and bool(straps[i])
	if bike != 0:
		var n := int(Shed.bikes[bike].get("dyno", {}).get("n", 0))
		if not _seen.has(bike):
			_seen[bike] = n    # runs from before we arrived don't replay
		elif n > int(_seen[bike]):
			_seen[bike] = n
			_start_run(bike)
	var t := _now() - _run_start
	var running := _run_start >= 0.0 and _run_build != null and Shed.bikes.has(_run_bike) and Shed.on_dyno(_run_bike) \
		and t < run_time(_run_build)
	var wheel_omega := 0.0
	if running:
		var st := sweep_state(_run_build, t)
		var gear := int(st["gear"])
		if gear > 0:
			wheel_omega = float(st["rpm"]) * TAU / 60.0 / _run_build.overall_ratio(gear)
		if _audio:
			_audio.rpm = float(st["rpm"])
			_audio.gear = maxi(gear, 1)
			_audio.throttle = float(st["throttle"])
			_audio.running = true
	elif _run_start >= 0.0:
		_run_start = -1.0
		if _audio:
			_audio.running = false
			var gone := _audio
			_audio = null
			get_tree().create_timer(1.5).timeout.connect(gone.queue_free)
	# The drum turns with the tyre on it; the fan blows while the engine's running.
	var rear_r := _run_build.rear_radius if running else 0.3
	_wheel_angle += wheel_omega * delta
	_drum_angle += wheel_omega * rear_r / DRUM_RADIUS * delta
	_drum.rotation.x = -_drum_angle
	_update_roller(wheel_omega * rear_r)
	var fan_on := bool(Shed.dyno.get("fan", false))
	if fan_on and _fan_speed <= 0.0:
		fan_build()
	_fan_speed = move_toward(_fan_speed, 25.0 if fan_on else 0.0, delta * (12.0 if fan_on else 5.0))
	# As a run builds the fan is pushed harder, following the roller's speed.
	_fan_push = move_toward(_fan_push, clampf(absf(wheel_omega * rear_r) / 45.0, 0.0, 1.0) if fan_on else 0.0, delta * 0.6)
	_fan.rotation.z += _fan_speed * (1.0 + 0.5 * _fan_push) * delta
	if _fan_sound:
		Sfx.set_loop(_fan_sound, "fan" if _fan_speed > 2.0 else "")
		_fan_sound.pitch_scale = clampf(_fan_speed / 25.0, 0.4, 1.0) * (1.0 + 0.15 * _fan_push)
		_fan_sound.set_meta("base_db", FAN_DB + 5.0 * _fan_push)
	_update_kit(delta, running)
	if running and workshop and workshop.bike_views.has(_run_bike):
		workshop.bike_model(_run_bike).update_pose_from(0.0, 0.0, _wheel_angle, 0.0, 0.0, 0.0, 0.0)
	_update_screen(bike)
	if _lights_shown != bool(Shed.dyno.get("lights", true)):
		set_lights(bool(Shed.dyno.get("lights", true)))


func _start_run(bike: int) -> void:
	_run_bike = bike
	_run_build = Shed.build_of(bike)
	_run_start = _now()
	_wheel_angle = 0.0
	if _audio == null:
		_audio = EngineSound.new()
		_audio.position = CENTER
		_audio.view = "room"
		add_child(_audio)
	var model: BikeModel = workshop.bike_model(bike) if workshop and workshop.bike_views.has(bike) else null
	_audio.setup(_run_build, model)
	if bool(Shed.dyno.get("fan", false)):
		fan_build()


## The cooling fan winding up: switched on, or pushed harder as a run starts.
func fan_build() -> void:
	if _fan_sound and _fan_sound.is_inside_tree():
		Sfx.play_at("fan_build", _fan_sound.global_position, FAN_DB)


func _update_screen(bike: int) -> void:
	var title := "DYNO"
	var runs: Array = []
	var msg := "Wheel a bike onto the rig and run it from the dyno desk."
	if bike != 0:
		title = "DYNO: %s" % Shed.bikes[bike]["name"]
		runs = Shed.bikes[bike].get("dyno", {}).get("runs", [])
		msg = "Strapped down. Run it from the dyno desk." if runs.is_empty() else ""
	var p := progress_for(bike)
	var live := live_for(bike)
	var sig := "%s|%d|%d|%.3f|%s|%s" % [title, runs.size(), int(runs[-1].get("n", 0)) if not runs.is_empty() else 0, p,
		str(live.get("gear", "")), Units.imperial()]
	if not live.is_empty():
		sig += str(roundi(float(live["rpm"]) / 50.0))
	if sig == _screen_sig:
		return
	_screen_sig = sig
	screen.show_runs(title, runs, p, live, msg)


# ---------------------------------------------------------------------------- building

func _make_materials() -> void:
	_mats["floor"] = _material(Color(0.2, 0.21, 0.22), 0.0, 0.55)
	_mats["wall_in"] = _material(Color(0.62, 0.66, 0.68), 0.0, 0.85)
	_mats["wall_low"] = _material(Color(0.14, 0.16, 0.18), 0.0, 0.6)
	_mats["plate"] = _material(Color(0.32, 0.33, 0.35), 0.8, 0.45)
	_mats["dark"] = _material(Color(0.05, 0.05, 0.06), 0.3, 0.5)
	_mats["steel"] = _material(Color(0.55, 0.57, 0.6), 0.85, 0.3)
	_mats["drum"] = _material(Color(0.42, 0.43, 0.45), 0.9, 0.35)
	_mats["yellow"] = _material(Color(0.95, 0.75, 0.05), 0.0, 0.5)
	_mats["blue"] = _material(Color(0.1, 0.3, 0.65), 0.5, 0.4)
	_mats["red"] = _material(Color(0.7, 0.08, 0.06), 0.5, 0.35)
	_mats["strap"] = _material(Color(0.95, 0.55, 0.05), 0.0, 0.8)
	_mats["wood"] = _material(Color(0.5, 0.36, 0.22), 0.0, 0.7)
	_mats["rubber"] = _material(Color(0.08, 0.08, 0.08), 0.0, 0.9)
	_mats["roof"] = workshop._mats.get("roof", _mats["dark"])
	_mats["cladding"] = workshop._mats.get("cladding", _mats["dark"])


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _solid(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	return body


func _deco(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, center: Vector3, radius: float, height: float, mat: Material, axis := Vector3.UP) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = center
	if axis == Vector3.RIGHT:
		mi.rotation.z = PI * 0.5
	elif axis == Vector3.BACK:
		mi.rotation.x = PI * 0.5
	parent.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, rot_y: float, font_size: int, color: Color, parent: Node3D = self) -> Label3D:
	var l := Label3D.new()
	Controls.bind_text(l, text)
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	parent.add_child(l)
	return l


func _build_shell() -> void:
	var c := CENTER
	var hx := HALF.x
	var hz := HALF.y
	var t := 0.3
	# The room sits off the back of the yard slab, so it has its own floor slab.
	_solid(c + Vector3(0.0, -0.25, -0.15), Vector3(hx * 2.0 + t * 2.0, 0.5, hz * 2.0 + t), _mats["floor"]).name = "DynoFloor"
	var floor_mi := _deco(self, c + Vector3(0.0, 0.004, 0.0), Vector3(hx * 2.0, 0.008, hz * 2.0), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far wall and the two sides; the shed's back wall closes it off.
	_solid(c + Vector3(0.0, HEIGHT * 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, HEIGHT, t), _mats["cladding"])
	for side in [-1.0, 1.0]:
		_solid(c + Vector3(side * (hx + t * 0.5), HEIGHT * 0.5, 0.0), Vector3(t, HEIGHT, hz * 2.0), _mats["cladding"])
	_solid(c + Vector3(0.0, HEIGHT + 0.12, 0.0), Vector3(hx * 2.0 + 0.8, 0.24, hz * 2.0 + 0.6), _mats["roof"])
	# Inside faces: grey-blue plaster over a dark band, like the shed.
	_deco(self, c + Vector3(0.0, HEIGHT * 0.5 + 0.6, -hz + 0.01), Vector3(hx * 2.0, HEIGHT - 1.2, 0.02), _mats["wall_in"])
	_deco(self, c + Vector3(0.0, 0.6, -hz + 0.01), Vector3(hx * 2.0, 1.2, 0.02), _mats["wall_low"])
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * (hx - 0.01), HEIGHT * 0.5 + 0.6, 0.0), Vector3(0.02, HEIGHT - 1.2, hz * 2.0), _mats["wall_in"])
		_deco(self, c + Vector3(side * (hx - 0.01), 0.6, 0.0), Vector3(0.02, 1.2, hz * 2.0), _mats["wall_low"])
		# This side of the shed wall, either side of the doorway.
		var w := hx - DOOR_HALF
		var x: float = side * (DOOR_HALF + w * 0.5)
		_deco(self, c + Vector3(x, HEIGHT * 0.5 + 0.6, hz - 0.01), Vector3(w, HEIGHT - 1.2, 0.02), _mats["wall_in"])
		_deco(self, c + Vector3(x, 0.6, hz - 0.01), Vector3(w, 1.2, 0.02), _mats["wall_low"])
		# The yellow door frame stands a centimetre proud into the opening, so its faces
		# don't sit in the same plane as the wall's edges and flicker against them.
		_deco(self, c + Vector3(side * (DOOR_HALF + 0.055), (DOOR_HEIGHT - 0.01) * 0.5, hz + 0.15), Vector3(0.13, DOOR_HEIGHT - 0.01, 0.36), _mats["yellow"])
	_deco(self, c + Vector3(0.0, DOOR_HEIGHT + 0.055, hz + 0.15), Vector3(DOOR_HALF * 2.0 + 0.24, 0.13, 0.36), _mats["yellow"])
	_deco(self, c + Vector3(0.0, (HEIGHT + DOOR_HEIGHT) * 0.5 + 0.06, hz - 0.01), Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_HEIGHT - 0.12, 0.02), _mats["wall_in"])
	for i in 3:
		_deco(self, c + Vector3(0.0, HEIGHT - 0.15, -hz + 1.2 + i * (hz * 2.0 - 2.4) / 2.0), Vector3(hx * 2.0, 0.14, 0.1), _mats["steel"])


## The rolling road: a steel plate flush with the floor, the drum showing through a slot under
## the rear tyre, a wheel clamp for the front and four posts to strap it down to.
func _build_rig() -> void:
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.transform = rig_transform()
	add_child(rig)
	_deco(rig, Vector3(0.0, 0.007, -0.05), Vector3(1.3, 0.014, 3.3), _mats["plate"])
	# Hazard edging round the plate.
	for side in [-1.0, 1.0]:
		_deco(rig, Vector3(side * 0.7, 0.009, -0.05), Vector3(0.08, 0.018, 3.4), _mats["yellow"])
	_deco(rig, Vector3(0.0, 0.016, DRUM_Z), Vector3(0.6, 0.004, 0.62), _mats["dark"])   # the slot
	_roller_sound = Sfx.make_loop_player(rig)
	_roller_sound.position = Vector3(0.0, 0.1, DRUM_Z)
	_roller_sound.volume_db = -6.0
	_drum = Node3D.new()
	_drum.position = Vector3(0.0, -DRUM_RADIUS + 0.025, DRUM_Z)
	rig.add_child(_drum)
	_cylinder(_drum, Vector3.ZERO, DRUM_RADIUS, 0.54, _mats["drum"], Vector3.RIGHT)
	# Knurled bars across the drum, so you can see it turn.
	for i in 12:
		var a := TAU * i / 12.0
		var bar := _deco(_drum, Vector3(0.0, sin(a), cos(a)) * DRUM_RADIUS, Vector3(0.55, 0.02, 0.03), _mats["dark"])
		bar.rotation.x = a
	# The front wheel clamp: a cradle the tyre rolls into.
	var cz := -0.72
	for side in [-1.0, 1.0]:
		_deco(rig, Vector3(side * 0.1, 0.2, cz - 0.08), Vector3(0.03, 0.36, 0.6), _mats["blue"])
	_deco(rig, Vector3(0.0, 0.03, cz - 0.08), Vector3(0.26, 0.04, 0.62), _mats["blue"])
	var stop := _deco(rig, Vector3(0.0, 0.2, cz - 0.42), Vector3(0.26, 0.4, 0.04), _mats["blue"])
	stop.rotation.x = -0.35
	# Strap-down posts, each with its ratchet strap, drawn once it's done up. Hold the work
	# button at a post to do its strap up (or undo it).
	_straps = Node3D.new()
	rig.add_child(_straps)
	for i in STRAP_POSTS.size():
		var post: Vector3 = STRAP_POSTS[i]
		_cylinder(rig, post + Vector3(0.0, 0.22, 0.0), 0.045, 0.44, _mats["yellow"])
		_cylinder(rig, post + Vector3(0.0, 0.46, 0.0), 0.06, 0.05, _mats["dark"])
		var strap := Node3D.new()
		strap.name = "Strap%d" % i
		_straps.add_child(strap)
		var to := Vector3(signf(post.x) * 0.14, 0.78 if post.z < 0.0 else 0.62, -0.5 if post.z < 0.0 else 0.55)
		_strap(strap, post + Vector3(0.0, 0.46, 0.0), to)
		strap.visible = false
		_strap_nodes.append(strap)
		var t := workshop._target(post + Vector3(0.0, 0.35, 0.0), Vector3(0.34, 0.7, 0.34), {"dyno_kit": "strap", "point": i}, rig)
		t.name = "StrapPost%d" % i


func _strap(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.006, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = _mats["strap"]
	mi.position = (a + b) * 0.5
	mi.basis = Basis.looking_at(b - a, Vector3.UP)
	parent.add_child(mi)
	# The ratchet buckle a third of the way up.
	var buckle := _deco(parent, a.lerp(b, 0.3), Vector3(0.07, 0.04, 0.09), _mats["steel"])
	buckle.basis = mi.basis


## A big cooling fan in front of the bike, as a rolling road needs.
func _build_fan() -> void:
	var at := CENTER + Vector3(0.0, 0.0, -1.95)
	_solid(at + Vector3(0.0, 0.18, 0.0), Vector3(0.7, 0.36, 0.45), _mats["dark"])
	_deco(self, at + Vector3(0.0, 0.55, 0.0), Vector3(0.12, 0.4, 0.12), _mats["steel"])
	var housing := _cylinder(self, at + Vector3(0.0, 0.95, 0.0), 0.48, 0.3, _mats["blue"], Vector3.BACK)
	housing.name = "FanHousing"
	_cylinder(self, at + Vector3(0.0, 0.95, 0.0), 0.44, 0.32, _mats["dark"], Vector3.BACK)
	_fan = Node3D.new()
	_fan.position = at + Vector3(0.0, 0.95, 0.12)
	add_child(_fan)
	for i in 5:
		var blade := _deco(_fan, Vector3.ZERO, Vector3(0.12, 0.4, 0.015), _mats["steel"])
		blade.rotation = Vector3(0.0, 0.3, TAU * i / 5.0)
		blade.position = Vector3(0.0, 0.2, 0.0).rotated(Vector3.BACK, TAU * i / 5.0)
	_cylinder(_fan, Vector3.ZERO, 0.07, 0.08, _mats["steel"], Vector3.BACK)
	_fan_sound = Sfx.make_loop_player(self)
	_fan_sound.position = at + Vector3(0.0, 0.95, 0.0)
	_fan_sound.volume_db = FAN_DB
	# The grille: rings and a cross on the front.
	for r in [0.2, 0.33, 0.46]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r - 0.008
		torus.outer_radius = r + 0.008
		ring.mesh = torus
		ring.material_override = _mats["steel"]
		ring.position = at + Vector3(0.0, 0.95, 0.17)
		ring.rotation.x = PI * 0.5
		add_child(ring)
	_deco(self, at + Vector3(0.0, 0.95, 0.17), Vector3(0.92, 0.015, 0.015), _mats["steel"])
	_deco(self, at + Vector3(0.0, 0.95, 0.17), Vector3(0.015, 0.92, 0.015), _mats["steel"])


## The dyno desk: a console with a monitor, where the tuning computer opens (F).
func _build_desk() -> void:
	var p := DESK
	_solid(p + Vector3(0.0, 0.4, 0.0), Vector3(1.5, 0.8, 0.7), _mats["dark"])
	_deco(self, p + Vector3(0.0, 0.82, 0.0), Vector3(1.55, 0.04, 0.75), _mats["wood"])
	_deco(self, p + Vector3(0.0, 1.17, -0.18), Vector3(0.9, 0.52, 0.05), _mats["dark"])
	var glow := _material(Color(0.1, 0.25, 0.35), 0.0, 0.3)
	glow.emission_enabled = true
	glow.emission = Color(0.9, 0.55, 0.2)
	glow.emission_energy_multiplier = 1.2
	_deco(self, p + Vector3(0.0, 1.17, -0.15), Vector3(0.84, 0.46, 0.01), glow)
	_deco(self, p + Vector3(0.0, 0.88, -0.2), Vector3(0.08, 0.1, 0.08), _mats["dark"])
	_deco(self, p + Vector3(-0.1, 0.85, 0.12), Vector3(0.5, 0.02, 0.16), _mats["dark"])   # keyboard
	_deco(self, p + Vector3(0.45, 0.86, 0.12), Vector3(0.18, 0.06, 0.12), _mats["red"])   # the big run button
	_label("DYNO & TUNING", p + Vector3(0.0, 1.27, -0.14), 0.0, 18, Color(0.08, 0.06, 0.05))
	_label("Tune  ·  Run  ·  Compare", p + Vector3(0.0, 1.17, -0.14), 0.0, 11, Color(0.08, 0.06, 0.05))
	workshop._target(p + Vector3(0.0, 1.0, 0.0), Vector3(1.5, 0.7, 0.8), {"dyno": true}, self)


## The big screen on the far wall, showing the run on the rig.
func _build_screen() -> void:
	_screen_view = SubViewport.new()
	_screen_view.size = Vector2i(1280, 720)
	_screen_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_screen_view)
	screen = DynoGraph.new()
	screen.size = Vector2(1280, 720)
	_screen_view.add_child(screen)
	var width := 3.2
	var height := width * 9.0 / 16.0
	var holder := Node3D.new()
	holder.position = CENTER + Vector3(0.0, 2.25, -HALF.y + 0.06)
	add_child(holder)
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _screen_view.get_texture()
	var mi := MeshInstance3D.new()
	mi.name = "DynoScreen"
	mi.mesh = quad
	mi.material_override = mat
	mi.position.z = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	_deco(holder, Vector3.ZERO, Vector3(width + 0.1, height + 0.1, 0.05), _mats["dark"])
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.7, 1.0)
	light.light_energy = 0.3
	light.omni_range = 3.0
	light.position = Vector3(0.0, 0.0, 0.8)
	holder.add_child(light)
	screen.show_runs("DYNO", [], 1.0, {}, "Wheel a bike onto the rig and run it from the dyno desk.")


## The crew's planning TV, filling most of the west wall: a shed screen like any other (its channel
## changes the same way), which comes on at the Route planner.
func _build_plan_tv() -> void:
	plan_tv = Dashboard.new("route", PLAN_TV_WIDTH)
	plan_tv.name = "PlanTv"
	plan_tv.position = PLAN_TV
	plan_tv.rotation.y = PI * 0.5
	add_child(plan_tv)
	workshop._screen_target(plan_tv, "dyno")


func _build_decor() -> void:
	var c := CENTER
	var hz := HALF.y
	# Hazard lines on the floor round the rig, and a walkway mat by the desk.
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * 1.45, 0.01, -0.3), Vector3(0.06, 0.004, 4.2), _mats["yellow"])
	_deco(self, c + Vector3(0.0, 0.01, -2.4), Vector3(2.9, 0.004, 0.06), _mats["yellow"])
	_deco(self, DESK + Vector3(0.0, 0.006, 0.85), Vector3(1.6, 0.012, 0.9), _mats["rubber"])
	# Signs.
	_poster("DYNO ROOM", c + Vector3(0.0, DOOR_HEIGHT + 0.45, hz + 0.32), 0.0, Vector2(1.0, 0.26), 64)
	_poster("STRAP IT DOWN. EARS ON.", c + Vector3(-2.6, 1.6, -hz + 0.025), 0.0, Vector2(1.2, 0.22), 40)
	_poster("PULL IN, LET GO NEAR THE DRUM", c + Vector3(2.6, 2.3, -hz + 0.025), 0.0, Vector2(1.4, 0.22), 40)
	_poster("HOSE ON THE EXHAUST", HOSE_HOOK + Vector3(-0.025, 0.45, 0.0), -PI * 0.5, Vector2(0.8, 0.16), 34)
	_poster("TUNE AT THE DESK ({interact})", DESK + Vector3(0.0, 1.75, -0.33), 0.0, Vector2(0.9, 0.2), 40)


func _blocker(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _poster(text: String, pos: Vector3, rot_y: float, size: Vector2, font_size: int) -> void:
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	paper.mesh = quad
	paper.material_override = _material(Color(0.86, 0.82, 0.7), 0.0, 0.9)
	paper.position = pos
	paper.rotation.y = rot_y
	add_child(paper)
	_label(text, Vector3(0.0, 0.0, 0.004), 0.0, font_size, Color(0.15, 0.12, 0.1), paper).pixel_size = 0.0018


func _build_lights() -> void:
	var fixture := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	for x in [-1.8, 1.8]:
		_deco(self, CENTER + Vector3(x, HEIGHT - 0.06, 0.0), Vector3(0.2, 0.05, 1.6), fixture)
		var omni := OmniLight3D.new()
		omni.position = CENTER + Vector3(x, HEIGHT - 0.4, 0.0)
		omni.omni_range = 6.5
		omni.light_energy = 1.1
		omni.light_color = Color(1.0, 0.94, 0.85)
		add_child(omni)
		_lights.append(omni)
	var spot := SpotLight3D.new()
	spot.position = CENTER + Vector3(0.0, HEIGHT - 0.2, 0.2)
	spot.rotation.x = -PI * 0.5
	spot.spot_angle = 40.0
	spot.spot_range = 5.0
	spot.light_energy = 2.2
	spot.light_color = Color(1.0, 0.96, 0.9)
	spot.shadow_enabled = true
	add_child(spot)
	_lights.append(spot)
	_fixture = fixture
	_probe = ReflectionProbe.new()
	_probe.position = CENTER + Vector3(0.0, HEIGHT * 0.5, 0.0)
	_probe.size = Vector3(HALF.x * 2.0 + 0.2, HEIGHT, HALF.y * 2.0 + 0.2)
	_probe.interior = true
	_probe.box_projection = true
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color(0.5, 0.5, 0.52)
	_probe.ambient_color_energy = 0.4
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)


# ---------------------------------------------------------------------------- the room's kit

## The dyno room's lights on or off (its own switch by the door, not the shed's).
func set_lights(on: bool) -> void:
	_lights_shown = on
	for l in _lights:
		l.visible = on
	if _fixture:
		_fixture.emission_energy_multiplier = 4.0 if on else 0.0
	if _probe:
		_probe.ambient_color_energy = 0.4 if on else 0.04
		_probe.intensity = 1.0 if on else 0.15
	if _rocker_lights:
		_rocker_lights.rotation.x = 0.0 if on else 0.5


func lights_shown() -> bool:
	return _lights_shown


## Two switches on the wall by the door, inside: the room's lights and the cooling fan.
func _build_switches() -> void:
	var at := SWITCHES
	_deco(self, at + Vector3(-0.17, 0.0, 0.0), Vector3(0.52, 0.26, 0.03), _mats["yellow"])
	var white := _material(Color(0.92, 0.92, 0.9), 0.0, 0.5)
	for i in 2:
		var x := -0.05 - i * 0.24
		_deco(self, at + Vector3(x, 0.0, -0.02), Vector3(0.12, 0.16, 0.02), white)
		var rocker := _deco(self, at + Vector3(x, 0.0, -0.035), Vector3(0.05, 0.08, 0.015), _mats["red"] if i == 1 else white)
		_poster("LIGHTS" if i == 0 else "FAN", at + Vector3(x, 0.17, -0.02), PI, Vector2(0.16, 0.06), 34)
		var t := workshop._target(at + Vector3(x, 0.0, -0.04), Vector3(0.2, 0.26, 0.12), {"dyno_kit": "lights" if i == 0 else "fan"}, self)
		t.name = "LightSwitch" if i == 0 else "FanSwitch"
		if i == 0:
			_rocker_lights = rocker
		else:
			_rocker_fan = rocker


## The exhaust extraction hose: a flexible duct dropping from the ceiling to a hook on the east
## wall. Take it off the hook, carry it to the bike and push it over the exhaust; it's drawn
## sagging from the drop to wherever its end is.
func _build_hose() -> void:
	_cylinder(self, HOSE_DROP + Vector3(0.0, 0.1, 0.0), 0.13, 0.12, _mats["steel"])
	# The hook.
	_deco(self, HOSE_HOOK + Vector3(0.03, 0.0, 0.0), Vector3(0.04, 0.2, 0.2), _mats["steel"])
	_deco(self, HOSE_HOOK + Vector3(-0.06, -0.06, 0.0), Vector3(0.14, 0.03, 0.04), _mats["steel"])
	var t := workshop._target(HOSE_HOOK + Vector3(-0.15, -0.3, 0.0), Vector3(0.36, 0.8, 0.5), {"dyno_kit": "hose"}, self)
	t.name = "HoseHook"
	var duct := _material(Color(0.12, 0.12, 0.13), 0.2, 0.7)
	var rib := _material(Color(0.3, 0.3, 0.32), 0.6, 0.4)
	for i in 18:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.065
		cm.height = 1.0
		cm.radial_segments = 10
		cm.rings = 1
		seg.mesh = cm
		seg.material_override = duct
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.06
		torus.outer_radius = 0.078
		torus.rings = 10
		torus.ring_segments = 4
		ring.mesh = torus
		ring.material_override = rib
		seg.add_child(ring)
		add_child(seg)
		_hose_parts.append(seg)
	# The end: a red rubber boot that goes over the tailpipe.
	_hose_end = Node3D.new()
	_hose_end.name = "HoseEnd"
	add_child(_hose_end)
	var boot := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.07
	cone.bottom_radius = 0.11
	cone.height = 0.24
	boot.mesh = cone
	boot.material_override = _mats["red"]
	boot.rotation.x = PI * 0.5      # its wide mouth faces -Z, onto the pipe
	boot.position.z = -0.08
	_hose_end.add_child(boot)
	_hose_end_target = workshop._target(Vector3.ZERO, Vector3(0.3, 0.3, 0.4), {"dyno_kit": "hose_end"}, self)
	_hose_end_target.name = "HoseOnExhaust"


## Where the hose's end is and which way its mouth faces (-Z of the returned transform).
func hose_end_transform() -> Transform3D:
	var state := str(Shed.dyno.get("hose", "hook"))
	if state == "bike":
		var tip = exhaust_tip()
		if tip is Transform3D:
			return tip
	elif state == "held" and is_inside_tree():
		var holder := Shed.hose_holder()
		if holder == Shed.me():
			var w: Node = get_tree().get_first_node_in_group("local_walker")
			if w is Walker:
				var cam: Camera3D = (w as Walker).camera
				var at: Vector3 = cam.global_transform * Vector3(0.22, -0.32, -0.55)
				return Transform3D(Basis.looking_at(-cam.global_transform.basis.z, Vector3.UP), at)
		else:
			for rp in get_tree().get_nodes_in_group("remote_players"):
				if int(rp.get("peer")) == holder:
					var xf: Transform3D = rp.world_transform()
					return Transform3D(xf.basis, xf.origin + Vector3.UP * 1.05 - xf.basis.z * 0.4)
	return Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), HOSE_HOOK + Vector3(-0.14, -0.12, 0.0))


## The bike on the rig's tailpipe, facing out of the pipe (-Z of the transform), or null.
func exhaust_tip():
	var bike := Shed.dyno_bike()
	if bike == 0 or workshop == null or not workshop.bike_views.has(bike) or Shed.item_on(bike, "exhaust") == 0:
		return null
	var model := workshop.bike_model(bike)
	if model == null or not model.is_inside_tree():
		return null
	var out := model.global_transform.basis.z.normalized()   # the bike faces -Z: the pipe points back
	return Transform3D(Basis.looking_at(-out, Vector3.UP), model.global_transform * model.exhaust_tip() + out * 0.05)


func _draw_hose(end: Transform3D) -> void:
	var a := HOSE_DROP
	var b := end.origin + end.basis.z * 0.12
	var dist := a.distance_to(b)
	var sag := clampf(HOSE_REACH - dist, 0.15, 2.2) * 0.55
	var c := (a + b) * 0.5 + Vector3.DOWN * sag
	c.y = maxf(c.y, 0.08)
	var n := _hose_parts.size()
	var prev := a
	for i in n:
		var t := float(i + 1) / n
		var p := a.lerp(c, t).lerp(c.lerp(b, t), t)
		var seg := _hose_parts[i]
		var d := p - prev
		var length := maxf(d.length(), 0.01)
		var up := d / length
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		# Each segment's own tube is sized to its length (only redrawn when the hose moves), so
		# the rib round its middle stays a ring.
		var cm := seg.mesh as CylinderMesh
		if absf(cm.height - length * 1.05) > 0.005:
			cm.height = length * 1.05
		seg.transform = Transform3D(Basis(side, up, side.cross(up)), (prev + p) * 0.5)
		prev = p
	_hose_end.global_transform = end


## The ear defenders, on a hook by the door when nobody's wearing them.
func _build_phones() -> void:
	_deco(self, PHONES_HOOK + Vector3(0.0, 0.08, 0.0), Vector3(0.04, 0.04, 0.12), _mats["steel"])
	_phones = headphones_model()
	_phones.position = PHONES_HOOK + Vector3(0.0, -0.02, -0.08)
	add_child(_phones)
	_poster("EAR DEFENDERS", PHONES_HOOK + Vector3(0.0, 0.3, 0.02), PI, Vector2(0.42, 0.08), 32)
	var t := workshop._target(PHONES_HOOK + Vector3(0.0, -0.06, -0.1), Vector3(0.34, 0.36, 0.24), {"dyno_kit": "phones"}, self)
	t.name = "PhonesHook"


## A pair of ear defenders: a headband over two big cups, ear to ear along x. Sits on a head
## with its band on top.
static func headphones_model() -> Node3D:
	var root := Node3D.new()
	root.name = "EarDefenders"
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.95, 0.72, 0.05)
	shell.roughness = 0.45
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.06, 0.06)
	black.roughness = 0.8
	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.135
	torus.outer_radius = 0.155
	band.mesh = torus
	band.material_override = black
	band.rotation.x = PI * 0.5    # a hoop standing up, ear to ear
	root.add_child(band)
	for side in [-1.0, 1.0]:
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.055
		cm.bottom_radius = 0.06
		cm.height = 0.05
		cup.mesh = cm
		cup.material_override = shell
		cup.rotation.z = PI * 0.5
		cup.position = Vector3(side * 0.15, -0.06, 0.0)
		root.add_child(cup)
		var pad := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.05
		pm.height = 0.02
		pad.mesh = pm
		pad.material_override = black
		pad.rotation.z = PI * 0.5
		pad.position = Vector3(side * 0.12, -0.06, 0.0)
		root.add_child(pad)
	return root


## Exhaust haze that fills the room after a run without the extraction hose, and the fumes
## out of the tailpipe while it runs. Soft grey puffs drifting slowly (and, with volumetric
## fog, a fog volume as thick as the haze).
func _build_haze() -> void:
	_haze = _smoke_particles(46, 9.0, Vector2(1.4, 2.2))
	_haze.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_haze.emission_box_extents = Vector3(HALF.x - 0.4, 0.9, HALF.y - 0.4)
	_haze.position = CENTER + Vector3(0.0, 1.5, 0.0)
	_haze.initial_velocity_max = 0.08
	_haze.gravity = Vector3(0.0, 0.01, 0.0)
	add_child(_haze)
	_fumes = _smoke_particles(40, 2.6, Vector2(0.15, 0.7))
	_fumes.direction = Vector3(0.0, 0.3, -1.0)
	_fumes.spread = 14.0
	_fumes.initial_velocity_min = 1.0
	_fumes.initial_velocity_max = 1.8
	_fumes.damping_min = 0.8
	_fumes.damping_max = 1.4
	_fumes.gravity = Vector3(0.0, 0.25, 0.0)
	add_child(_fumes)
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return   # fog volumes need Forward+; the haze particles carry it on the simpler renderer
	var fog := FogVolume.new()
	fog.name = "HazeFog"
	fog.size = Vector3(HALF.x * 2.0, HEIGHT, HALF.y * 2.0)
	fog.position = CENTER + Vector3(0.0, HEIGHT * 0.5, 0.0)
	var fm := FogMaterial.new()
	fm.density = 0.0
	fm.albedo = Color(0.7, 0.7, 0.72)
	fog.material = fm
	fog.visible = false
	add_child(fog)


func _smoke_particles(amount: int, life: float, scale: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.randomness = 0.6
	p.lifetime_randomness = 0.4
	p.scale_amount_min = scale.x
	p.scale_amount_max = scale.y
	p.anim_offset_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 2
	m.particles_anim_v_frames = 2
	m.particles_anim_loop = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.62, 0.63, 0.66, 0.0)
	m.albedo_texture = BikeEffects.puff_texture()
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## How thick the exhaust haze in the room looks right now, 0..1.
func haze_shown() -> float:
	return _haze_level if _haze and _haze.emitting else 0.0


func fumes_showing() -> bool:
	return _fumes != null and _fumes.emitting


func phones_on_hook() -> bool:
	return _phones != null and _phones.visible


## The hose, ear defenders, haze and fumes, every frame.
func _update_kit(delta: float, running: bool) -> void:
	var end := hose_end_transform()
	var sig := "%s|%s" % [Shed.dyno.get("hose", ""), str(end.origin.snapped(Vector3.ONE * 0.01))]
	if sig != _hose_sig:
		_hose_sig = sig
		_draw_hose(end)
	var on_bike: bool = Shed.dyno.get("hose", "") == "bike"
	_hose_end_target.global_position = end.origin if on_bike else Vector3(0.0, -50.0, 0.0)
	# Carried too far from the drop, the hose pulls out of your hands back to its hook.
	if Shed.hose_holder() == Shed.me():
		var w: Node = get_tree().get_first_node_in_group("local_walker")
		if w is Node3D and Vector2((w as Node3D).global_position.x - HOSE_DROP.x, (w as Node3D).global_position.z - HOSE_DROP.z).length() > HOSE_REACH + 0.6:
			if not has_meta("hose_pulled"):
				set_meta("hose_pulled", true)
				Shed.request({"a": "dyno_hose", "to": "hook"})
				Shed.feedback.emit("The hose won't reach that far: it's back on its hook.", false)
		elif has_meta("hose_pulled"):
			remove_meta("hose_pulled")
	_phones.visible = int(Shed.dyno.get("headphones", 0)) == 0
	Sfx.set_muffled(Shed.wearing_headphones(Shed.me()))
	if _rocker_fan:
		_rocker_fan.rotation.x = 0.5 if bool(Shed.dyno.get("fan", false)) else 0.0
	# Exhaust haze: thickens after a run with no hose on, clears slowly (faster with the fan
	# blowing and the extraction on).
	var want := float(Shed.dyno.get("haze", 0.0))
	_haze_level = move_toward(_haze_level, want, delta * 0.25)
	_haze.emitting = _haze_level > 0.02
	var hm := (_haze.mesh as QuadMesh).material as StandardMaterial3D
	hm.albedo_color.a = clampf(_haze_level * 0.32, 0.0, 0.4)
	var fog: FogVolume = get_node_or_null("HazeFog")
	if fog:
		fog.visible = _haze_level > 0.02
		(fog.material as FogMaterial).density = _haze_level * 0.08
	var tip = exhaust_tip() if running else null
	_fumes.emitting = running and not on_bike and tip != null
	if _fumes.emitting:
		_fumes.global_transform = tip
		var fm := (_fumes.mesh as QuadMesh).material as StandardMaterial3D
		fm.albedo_color.a = 0.3


# ---------------------------------------------------------------------------- for the player

## What the work button does at a piece of the dyno room's kit (or anywhere while carrying the
## hose): {action, time, verb}, or {}. `target` is the walker's.
static func plan_for(target: Dictionary, peer: int) -> Dictionary:
	var kind := str(target.get("kind", ""))
	var kit := str(target.get("kit", ""))
	if Shed.hose_holder() == peer:
		var on_rig := Shed.dyno_bike()
		if kind == "part" and on_rig != 0 and int(target.get("bike", 0)) == on_rig:
			return {"action": {"a": "dyno_hose", "to": "bike"}, "time": 1.0, "verb": "push the extraction hose over the exhaust"}
		if kit == "hose":
			return {"action": {"a": "dyno_hose", "to": "hook"}, "time": 0.3, "verb": "hang the hose back on its hook"}
		return {}
	match kit:
		"strap":
			var i := clampi(int(target.get("point", 0)), 0, 3)
			var done := bool(Shed.dyno["straps"][i])
			return {"action": {"a": "dyno_strap", "point": i}, "time": 0.8 if done else 1.4,
				"verb": "undo this strap" if done else "hook the strap on and ratchet it down tight"}
		"hose_end":
			return {"action": {"a": "dyno_hose", "to": "held"}, "time": 0.6, "verb": "pull the hose off the exhaust"}
		"hose":
			if Shed.dyno.get("hose", "") == "hook":
				return {"action": {"a": "dyno_hose", "to": "held"}, "time": 0.3, "verb": "take the extraction hose off its hook"}
	return {}


## What F does at the dyno room's switches and the ear defenders' hook, or {}.
static func f_action(target: Dictionary) -> Dictionary:
	match str(target.get("kit", "")):
		"lights":
			return {"a": "dyno_lights", "on": not bool(Shed.dyno.get("lights", true))}
		"fan":
			return {"a": "dyno_fan", "on": not bool(Shed.dyno.get("fan", false))}
		"phones":
			return {"a": "dyno_headphones"}
	return {}


## The info panel's lines for the dyno room's kit.
static func describe(target: Dictionary, peer: int) -> Array:
	var lines := []
	match str(target.get("kit", "")):
		"lights":
			lines = ["Dyno room lights", "{interact}: switch them %s" % ("off" if bool(Shed.dyno.get("lights", true)) else "on")]
		"fan":
			var hot := Shed.dyno_temp(float(Shed.dyno.get("heat", 0.0)))
			lines = ["Cooling fan", "{interact}: switch it %s" % ("off" if bool(Shed.dyno.get("fan", false)) else "on"),
				"Blows air over the engine on the rig so it doesn't heat soak and lose power. Engine at %d °C." % roundi(hot)]
		"phones":
			var wearer := int(Shed.dyno.get("headphones", 0))
			if wearer == peer:
				lines = ["Ear defenders (you're wearing them)", "{interact}: hang them back up"]
			elif wearer != 0:
				lines = ["Ear defenders", "%s is wearing them." % str(Shed.crew.get(wearer, {}).get("name", "Someone"))]
			else:
				lines = ["Ear defenders", "{interact}: put them on. The dyno's roar (and everything else) is muffled while you wear them."]
		"strap":
			var i := clampi(int(target.get("point", 0)), 0, 3)
			lines = ["Strap post (%s)" % ["front left", "front right", "rear left", "rear right"][i],
				"Strapped: %d of 4" % Shed.straps_done()]
			if Shed.dyno_bike() == 0:
				lines.append("Wheel a bike onto the rig to strap it down.")
		"hose", "hose_end":
			var state := str(Shed.dyno.get("hose", "hook"))
			lines = ["Exhaust extraction hose", str({"hook": "On its hook. Take it to the bike on the rig and fit it over the exhaust.",
				"bike": "On the exhaust: the fumes go outside.", "held": "Being carried."}.get(state, ""))]
	if Shed.hose_holder() == peer:
		lines.append("Carrying the extraction hose: hold the work button on the bike on the rig to fit it, or hang it back on its hook.")
	return lines


## The drum's whine, pitched with its surface speed (`speed` m/s; the sound is made at 60 km/h).
func _update_roller(speed: float) -> void:
	if _roller_sound == null:
		return
	var turning := absf(speed) > 1.0
	Sfx.set_loop(_roller_sound, "dyno_roller" if turning else "")
	if turning:
		_roller_sound.pitch_scale = clampf(absf(speed) / 16.7, 0.3, 3.0)
