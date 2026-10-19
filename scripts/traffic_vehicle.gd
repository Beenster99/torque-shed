class_name TrafficVehicle
extends AnimatableBody3D
## One car, van, lorry or coach out in the traffic: VehicleModel's shared meshes in its own paint,
## solid for a bike to hit, and moved by whoever drives it (RoadTraffic on the town's roads, or a
## TrafficStream along any road) through drive() each frame. Nothing about it is simulated: it's
## put where its driver says, its wheels turned and steered to match, and its lamps lit (dipped
## beams, tail lamps and markers after dusk, brake lamps as it slows, indicators blinking before
## it turns off).
##
## Close to (LOD_NEAR) it's the full model with its cabin and turning wheels; further off one
## merged mesh with the wheels baked in; past DRAW_RANGE nothing is drawn (it's still solid).

## Each kind's driving: its pace (a share of the road's speed), how hard it corners (sideways
## m/s^2), brakes and pulls away (m/s^2), and how often it turns up in town and out of it.
const TRAITS := {
	"hatchback": {"pace": 1.0, "grip": 3.2, "brake": 3.2, "accel": 2.2, "town": 26, "open": 18},
	"saloon": {"pace": 1.03, "grip": 3.2, "brake": 3.2, "accel": 2.2, "town": 18, "open": 20},
	"estate": {"pace": 1.0, "grip": 3.1, "brake": 3.1, "accel": 2.0, "town": 13, "open": 15},
	"suv": {"pace": 1.0, "grip": 2.9, "brake": 3.1, "accel": 2.0, "town": 15, "open": 15},
	"van": {"pace": 0.95, "grip": 2.7, "brake": 2.8, "accel": 1.7, "town": 12, "open": 14},
	"lorry": {"pace": 0.78, "grip": 2.0, "brake": 2.2, "accel": 0.9, "town": 5, "open": 11},
	"coach": {"pace": 0.8, "grip": 2.0, "brake": 2.2, "accel": 1.0, "town": 11, "open": 7},
	# Only ever put on the road on purpose (see AdventurePolice), never in the mix.
	"police": {"pace": 1.0, "grip": 4.5, "brake": 6.0, "accel": 4.5, "town": 0, "open": 0},
}
## Near model within this (m, times the draw distance setting); far mesh out to DRAW_RANGE.
const LOD_NEAR := 45.0
const DRAW_RANGE := 450.0
## Headlamp beams are real lights only this close to the camera.
const BEAM_RANGE := 70.0
## How brightly the lenses glow: daytime running lamps, dipped beams at night, tail lamps,
## brake lamps, indicators and markers.
const DRL := 1.2
const HEAD_NIGHT := 6.0
const TAIL_NIGHT := 2.5
const BRAKE_ON := 6.0
const INDICATOR_ON := 5.0
const BLINK := 0.7              # seconds an indicator's flash cycle takes
## A police car's blue lamps at full flash (bright enough to see by day), and its beacon light's
## reach and strength at night (a real light, so the road and hedges flash blue round it).
const BLUE_ON := 16.0
const BEACON_RANGE := 120.0
const BEACON_ENERGY := 3.0

var kind := ""
var look := {}
var length := 4.0
var half_width := 0.9
var height := 1.5
## 0 the near model, 1 the far mesh, 2 not drawn.
var lod := -1
## What the lamps were last set to: (head, tail, brake, marker) and (left, right).
var lamps := Vector4.ZERO
var indicators := Vector2.ZERO
## A police car's blue lamps: how bright the left and right banks are now (0 off).
var blues := Vector2.ZERO
var _model: Node3D
var _near: Node3D
var _body: MeshInstance3D
var _far: MeshInstance3D
var _steered: Array[Node3D] = []    # the front wheels' holders, turned to steer
var _spinning: Array[Node3D] = []   # every wheel node that turns as it rolls
var _beam: SpotLight3D
var _beacon: OmniLight3D           # a police car's blue light thrown round it at night
var _roll := 0.0
var _blink := 0.0


## The kind of vehicle a driver turns up in, by how often each is seen in town or out of it.
static func pick_kind(rng: RandomNumberGenerator, town: bool) -> String:
	var total := 0
	for k in TRAITS:
		total += int(TRAITS[k]["town" if town else "open"])
	var roll := rng.randi() % total
	for k in TRAITS:
		roll -= int(TRAITS[k]["town" if town else "open"])
		if roll < 0:
			return k
	return "hatchback"


## How a driver takes the road, as a share of its speed limit: most near it, some dawdling,
## a few pressing on; lorries and coaches slower.
static func pick_pace(rng: RandomNumberGenerator, kind_name: String) -> float:
	var driver := clampf(1.0 + rng.randfn(0.0, 0.11), 0.72, 1.18)
	return driver * float(TRAITS[kind_name]["pace"])


## Builds it as `kind_name` in the look its seed gives (the same on every machine).
func setup(kind_name: String, seed_value: int) -> void:
	kind = kind_name
	look = VehicleModel.look_of(kind, seed_value)
	var spec: Dictionary = VehicleModel.SPECS[kind]
	length = float(spec["len"])
	half_width = float(spec["w"])
	height = float(spec["h"])
	sync_to_physics = false
	collision_layer = 2            # with the bikes, so yours runs into it
	collision_mask = 0
	add_to_group("road_traffic")
	set_meta("mover_radius", half_width + 0.5)   # how wide a berth the townsfolk give it
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_width * 2.0, height - 0.25, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.25 + (height - 0.25) * 0.5, 0.0)
	add_child(cs)
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var parts := VehicleModel.parts(kind, int(look["trim"]))
	var paint := VehicleModel.paint_material(look["paint"])
	var paint2 := VehicleModel.paint_material(look["paint2"])
	_near = Node3D.new()
	_near.name = "Near"
	_model.add_child(_near)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = parts["near"]
	_paint_over(_body, parts["keys_near"], paint, paint2)
	_near.add_child(_body)
	var r := float(spec["r"])
	var vm := VehicleModel.new()
	vm.s = spec
	var axle_done := false
	for spot in vm.wheel_spots():
		if spot[2]:
			var holder := Node3D.new()
			holder.position = Vector3(spot[0], r, spot[1])
			_near.add_child(holder)
			var spin := MeshInstance3D.new()
			spin.mesh = parts["wheel"]
			if spot[0] < 0.0:
				spin.basis = Basis(Vector3.UP, PI)
			holder.add_child(spin)
			_steered.append(holder)
			_spinning.append(spin)
		elif not axle_done:
			axle_done = true
			var axle := MeshInstance3D.new()
			axle.mesh = parts["axle"]
			axle.position = Vector3(0.0, r, spot[1])
			_near.add_child(axle)
			_spinning.append(axle)
	_far = MeshInstance3D.new()
	_far.name = "Far"
	_far.mesh = parts["far"]
	_paint_over(_far, parts["keys_far"], paint, paint2)
	_model.add_child(_far)
	_beam = SpotLight3D.new()
	_beam.name = "Headlamps"
	_beam.position = Vector3(0.0, 0.9 if height < 2.0 else 1.1, -length * 0.5 - 0.1)
	_beam.rotation.x = deg_to_rad(-6.0)
	_beam.spot_range = 40.0
	_beam.spot_angle = 38.0
	_beam.light_energy = 1.6
	_beam.light_color = Color(1.0, 0.96, 0.88)
	_beam.shadow_enabled = false
	_beam.spot_angle_attenuation = BikeEffects.CORE_FALLOFF
	_beam.light_projector = BikeEffects.soft_spot_texture()
	_beam.light_specular = 0.3
	_beam.set_meta("lighting_skip", true)
	_beam.visible = false
	_model.add_child(_beam)
	if kind == "police":
		_beacon = OmniLight3D.new()
		_beacon.name = "Beacon"
		_beacon.position = Vector3(0.0, height + 0.3, -0.6)
		_beacon.omni_range = 16.0
		_beacon.light_color = Color(0.2, 0.35, 1.0)
		_beacon.shadow_enabled = false
		_beacon.light_specular = 0.2
		_beacon.set_meta("lighting_skip", true)
		_beacon.visible = false
		_model.add_child(_beacon)
	_set_lod(1)


func _paint_over(mi: MeshInstance3D, keys: Array, paint: Material, paint2: Material) -> void:
	for i in keys.size():
		if keys[i] == "paint":
			mi.set_surface_override_material(i, paint)
		elif keys[i] == "paint2":
			mi.set_surface_override_material(i, paint2)


## Puts it at `xf` (origin on the road under its middle, facing -Z), going `v` m/s with its
## front wheels at `steer` (rad, + right), braking or not, an indicator going (-1 left, 1 right,
## 0 none), seen from `cam` (for which model to draw, and whether its beams light the road).
func drive(xf: Transform3D, v: float, steer: float, braking: bool, indicator: int, delta: float, cam: Vector3) -> void:
	global_transform = xf
	var scale := clampf(Settings.gfx_draw_distance, 0.5, 2.0)
	var dist := cam.distance_to(xf.origin)
	var near := LOD_NEAR * scale + (3.0 if lod == 0 else 0.0)
	_set_lod(0 if dist < near else (1 if dist < DRAW_RANGE * scale else 2))
	if lod == 0:
		_roll = wrapf(_roll + v * delta / float(VehicleModel.SPECS[kind]["r"]), 0.0, TAU)
		for n in _spinning:
			n.rotation.x = -_roll
		for h in _steered:
			h.rotation.y = -steer
	var night := Daylight.current.lamps if Daylight.current else 0.0
	_blink = fmod(_blink + delta, BLINK) if indicator != 0 else 0.0
	var flash := INDICATOR_ON if _blink < BLINK * 0.5 else 0.0
	set_lamps(Vector4(lerpf(DRL, HEAD_NIGHT, night), TAIL_NIGHT * night, BRAKE_ON if braking else 0.0, lerpf(0.4, 3.0, night)),
		Vector2(flash if indicator < 0 else 0.0, flash if indicator > 0 else 0.0))
	_beam.visible = night > 0.3 and lod == 0 and dist < BEAM_RANGE
	if _beam.visible:
		_beam.light_energy = 1.6 * night
	if _beacon:
		var flash_now := maxf(blues.x, blues.y) / BLUE_ON
		_beacon.visible = night > 0.15 and flash_now > 0.05 and dist < BEACON_RANGE * scale
		if _beacon.visible:
			_beacon.light_energy = BEACON_ENERGY * night * flash_now
			_beacon.position.x = 0.5 if blues.y > blues.x else -0.5


## A police car's blue lamps: the left and right banks' glow (0 off, BLUE_ON flashing full).
func set_blues(b: Vector2) -> void:
	if b == blues:
		return
	blues = b
	for mi in [_body, _far]:
		(mi as MeshInstance3D).set_instance_shader_parameter("lamp_blue", b)


## Lights its lenses: (head, tail, brake, marker) and the (left, right) indicators' glow.
func set_lamps(a: Vector4, ind: Vector2) -> void:
	if a == lamps and ind == indicators:
		return
	lamps = a
	indicators = ind
	for mi in [_body, _far]:
		(mi as MeshInstance3D).set_instance_shader_parameter("lamp_a", a)
		(mi as MeshInstance3D).set_instance_shader_parameter("lamp_ind", ind)


func _set_lod(l: int) -> void:
	if l == lod:
		return
	lod = l
	_near.visible = l == 0
	_far.visible = l == 1
