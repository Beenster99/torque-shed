class_name DynoRoom
extends Node3D
## The tuning room behind the shed's back wall, through a doorway between bays 2 and 3: a
## rolling-road dyno set into the floor (a drum under the rear wheel, a clamp for the front,
## strap-down posts and a cooling fan), the dyno desk where bikes are tuned and run, and a big
## screen on the far wall showing the latest run. Wheel a bike in and let go of it near the
## drum and it's strapped down (Shed._park). A run is the same for everyone: the host stores
## the result on the bike and each player plays the run back from it.

const CENTER := Vector3(0.0, 0.0, 55.6)
const HALF := Vector2(4.5, 3.6)           # interior: x -4.5..4.5, z 52.0..59.2 (the shed's back wall)
const HEIGHT := 3.6
## The doorway through the shed's back wall, centred on x = 0.
const DOOR_HALF := 1.1
const DOOR_HEIGHT := 2.5
const DRUM_RADIUS := 0.32
const DRUM_Z := 0.71                      # the drum's axle behind the rig's centre, under the rear tyre
const DESK := Vector3(2.9, 0.0, 53.9)
## Phases of a run, seconds: a blip at idle, up through the lower gears, settle, the measured
## sweep in the gear nearest 1:1, then coast down.
const IDLE_T := 0.8
const QUICK_T := 0.6
const SETTLE_T := 0.5
const SWEEP_T := 4.0
const COAST_T := 1.2

var workshop: Workshop
var screen: DynoGraph
var _screen_view: SubViewport
var _drum: Node3D
var _fan: Node3D
var _straps: Node3D
var _probe: ReflectionProbe
var _audio: EngineAudio
var _mats := {}
var _seen := {}              # bike id -> the dyno run count we've seen, so a new run plays once
var _run_bike := 0
var _run_start := -1.0       # seconds (local clock) the playing run started
var _run_build: BikeBuild
var _drum_angle := 0.0
var _wheel_angle := 0.0
var _fan_speed := 0.0
var _screen_sig := ""


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
	_build_decor()
	_build_lights()


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
	if not Shed.active:
		return
	var bike := Shed.dyno_bike()
	_straps.visible = bike != 0
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
	_fan_speed = move_toward(_fan_speed, 25.0 if running else 0.0, delta * 12.0)
	_fan.rotation.z += _fan_speed * delta
	if running and workshop and workshop.bike_views.has(_run_bike):
		workshop.bike_model(_run_bike).update_pose_from(0.0, 0.0, _wheel_angle, 0.0, 0.0, 0.0, 0.0)
	_update_screen(bike)
	if _probe:
		_probe.ambient_color_energy = 0.4 if Shed.lights_on else 0.06


func _start_run(bike: int) -> void:
	_run_bike = bike
	_run_build = Shed.build_of(bike)
	_run_start = _now()
	_wheel_angle = 0.0
	if _audio == null:
		_audio = EngineAudio.new()
		_audio.position = CENTER + Vector3(0.12, 0.45, 0.6)
		add_child(_audio)
	_audio.cylinders = _run_build.cylinders
	_audio.layout = _run_build.layout
	_audio.displacement = _run_build.displacement
	_audio.loudness = _run_build.exhaust_loudness
	_audio.whine = _run_build.gear_whine


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
	l.text = text
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
		_deco(self, c + Vector3(side * (DOOR_HALF + 0.06), DOOR_HEIGHT * 0.5, hz + 0.15), Vector3(0.12, DOOR_HEIGHT, 0.36), _mats["yellow"])
	_deco(self, c + Vector3(0.0, DOOR_HEIGHT + 0.06, hz + 0.15), Vector3(DOOR_HALF * 2.0 + 0.24, 0.12, 0.36), _mats["yellow"])
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
	# Strap-down posts, and the straps themselves while a bike is on.
	_straps = Node3D.new()
	rig.add_child(_straps)
	for post in [Vector3(-0.95, 0.0, -0.6), Vector3(0.95, 0.0, -0.6), Vector3(-0.95, 0.0, 0.8), Vector3(0.95, 0.0, 0.8)]:
		_cylinder(rig, post + Vector3(0.0, 0.22, 0.0), 0.045, 0.44, _mats["yellow"])
		_cylinder(rig, post + Vector3(0.0, 0.46, 0.0), 0.06, 0.05, _mats["dark"])
		var to := Vector3(signf(post.x) * 0.14, 0.78 if post.z < 0.0 else 0.62, -0.5 if post.z < 0.0 else 0.55)
		_strap(post + Vector3(0.0, 0.46, 0.0), to)
	_straps.visible = false


func _strap(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.006, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = _mats["strap"]
	mi.position = (a + b) * 0.5
	mi.basis = Basis.looking_at(b - a, Vector3.UP)
	_straps.add_child(mi)


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


func _build_decor() -> void:
	var c := CENTER
	var hz := HALF.y
	# Hazard lines on the floor round the rig, and a walkway mat by the desk.
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * 1.45, 0.01, -0.3), Vector3(0.06, 0.004, 4.2), _mats["yellow"])
	_deco(self, c + Vector3(0.0, 0.01, -2.4), Vector3(2.9, 0.004, 0.06), _mats["yellow"])
	_deco(self, DESK + Vector3(0.0, 0.006, 0.85), Vector3(1.6, 0.012, 0.9), _mats["rubber"])
	# Exhaust extraction: a hose dropping from the ceiling to a funnel behind the rig.
	var hose_at := c + Vector3(1.75, 0.0, 0.9)
	_cylinder(self, hose_at + Vector3(0.0, (HEIGHT + 0.85) * 0.5, 0.0), 0.09, HEIGHT - 0.85, _mats["rubber"])
	var funnel := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.07
	cone.bottom_radius = 0.15
	cone.height = 0.25
	funnel.mesh = cone
	funnel.material_override = _mats["red"]
	funnel.position = hose_at + Vector3(-0.1, 0.78, 0.0)
	funnel.rotation.z = -0.9
	add_child(funnel)
	# A tool chest and a tyre rack along the west wall.
	_solid(c + Vector3(-HALF.x + 0.4, 0.5, -1.4), Vector3(0.6, 1.0, 1.1), _mats["red"])
	for i in 4:
		_deco(self, c + Vector3(-HALF.x + 0.71, 0.18 + i * 0.22, -1.4), Vector3(0.02, 0.03, 0.9), _mats["steel"])
	for i in 3:
		var tyre := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.32
		tyre.mesh = torus
		tyre.material_override = _mats["rubber"]
		tyre.position = c + Vector3(-HALF.x + 0.25, 0.33, 0.6 + i * 0.45)
		tyre.rotation.z = PI * 0.5
		add_child(tyre)
	_blocker(c + Vector3(-HALF.x + 0.25, 0.33, 1.05), Vector3(0.4, 0.66, 1.4))
	# Signs.
	_poster("DYNO ROOM", c + Vector3(0.0, DOOR_HEIGHT + 0.45, hz + 0.32), 0.0, Vector2(1.0, 0.26), 64)
	_poster("STRAP IT DOWN. EARS ON.", c + Vector3(-2.6, 1.6, -hz + 0.025), 0.0, Vector2(1.2, 0.22), 40)
	_poster("PULL IN, LET GO NEAR THE DRUM", c + Vector3(-HALF.x + 0.025, 1.6, 0.4), PI * 0.5, Vector2(1.4, 0.22), 40)
	_poster("TUNE AT THE DESK (F)", DESK + Vector3(0.0, 1.75, -0.33), 0.0, Vector2(0.9, 0.2), 40)


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
		workshop._shed_lights.append(omni)
	var spot := SpotLight3D.new()
	spot.position = CENTER + Vector3(0.0, HEIGHT - 0.2, 0.2)
	spot.rotation.x = -PI * 0.5
	spot.spot_angle = 40.0
	spot.spot_range = 5.0
	spot.light_energy = 2.2
	spot.light_color = Color(1.0, 0.96, 0.9)
	spot.shadow_enabled = true
	add_child(spot)
	workshop._shed_lights.append(spot)
	workshop._fixture_mats.append(fixture)
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
