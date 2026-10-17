class_name Car
extends RigidBody3D
## The garage's recovery truck: a double-cab pickup with a tow ball, driven like the bikes are
## ridden. One rigid body on four ray-cast wheels (RayWheel: spring and damper suspension and
## the bikes' Magic Formula tyres), a 2.4 litre turbo diesel with its torque curve, a six-speed
## gearbox (automatic, or manual with the auto-shift setting off) and reverse, rack steering with
## Ackermann geometry that tightens up with speed, ABS brakes biased to the front, a handbrake on
## the back wheels, and rear-wheel drive through an open differential. You get in with the engine
## off and start it on the key (I, as on the bikes); the headlamps switch through off, dipped and
## main beam (L), and light the road ahead at night.
##
## Local axes: forward is -Z, up is +Y, right is +X. The body's origin is on the ground under the
## middle of the truck when it sits on its springs. Frozen, it's a parked truck (or another
## player's, moved by their network state); unfrozen, the local driver's.

signal gear_changed(gear: int)
signal engine_changed(running: bool)

const G := 9.81
const MASS := 1950.0
const FRONT_Z := -1.55
const REAR_Z := 1.65
const WHEELBASE := REAR_Z - FRONT_Z
const HALF_TRACK := 0.81
const RADIUS := 0.39
const TRAVEL := 0.22
const SPRING_F := 52000.0
const SPRING_R := 58000.0
const BUMP := 3800.0
const REBOUND := 5600.0
const WHEEL_INERTIA := 2.4
const MOUNT_Y := RADIUS + TRAVEL - 0.1   # the top of the travel, with the truck sat on its springs
## The tow ball, behind the back bumper.
const HITCH := Vector3(0.0, 0.5, 2.95)
## The engine: idle, red line, and the torque curve [rpm, N m].
const IDLE_RPM := 800.0
const REDLINE := 4600.0
const TORQUE_CURVE := [[600.0, 150.0], [1000.0, 230.0], [1500.0, 320.0], [1800.0, 350.0], [2800.0, 350.0],
	[3500.0, 320.0], [4200.0, 270.0], [4700.0, 200.0]]
const GEARS := [4.17, 2.34, 1.52, 1.14, 0.87, 0.69]
const REVERSE := 3.75
const REVERSE_LIMIT := 2400.0   # rpm: backing up is kept to a walk or a jog
const FINAL_DRIVE := 3.55
const EFFICIENCY := 0.88
const SHIFT_TIME := 0.35
const BRAKE_FRONT := 3200.0     # N m at each front wheel, pedal flat
const BRAKE_REAR := 1600.0
const HANDBRAKE := 4800.0     # enough to lock the back wheels against the road
const MAX_STEER := deg_to_rad(34.0)
const STEER_RATE := 1.4         # rad/s at the road wheels
const CDA := 1.4                # drag area, m^2: a pickup is a brick
const EYE := Vector3(0.4, 1.58, -0.2)   # the driver's eyes (right-hand drive)
const STEER_RATIO := 16.0       # steering wheel turns to road wheel angle
const START_TIME := 0.9         # seconds on the starter before the diesel catches
## The headlamp switch's stops, as on the bikes (but no fog stop: the fog lamps ride with dipped).
const BEAM_NAMES := ["off", "dipped beam", "main beam"]

var throttle := 0.0
var brake := 0.0
var handbrake := 0.0
var steer_input := 0.0          # -1 left .. 1 right
var auto_shift := true
var controls_enabled := true
var engine_on := true            # tests drive it running; you get in with it off (RecoveryView)
var horn := false
var beam := 1                    # headlamp switch: 0 off, 1 dipped, 2 main beam
## Reverse picked with the gear lever (shift down at a standstill): the pedals stay where they
## are, the throttle backing it up. Reverse the automatic finds itself, holding the brake at a
## standstill, swaps them instead, so the brake pedal backs you up.
var reverse_selected := false
var braking := false             # the brake lamps' switch, worked out each tick (sent to the crew)

var speed := 0.0                # forward speed, m/s
var rpm := IDLE_RPM
var gear := 1                   # -1 reverse, 0 neutral, 1..6
var steer := 0.0                # road wheel angle, rad, + right
var wheels: Array = []          # front left, front right, rear left, rear right
var model: Node3D
var _shift_timer := 0.0
var _since_shift := 0.0
var _rev_hold := 0.0
var _starting := 0.0
var _wheel_nodes: Array = []
var _steering_wheel: Node3D
var _head_lights: Array = []
var _brake_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D      # headlamps and fog lamps, lit with the engine
var _reverse_mat: StandardMaterial3D   # the reversing lamps
var _dash_mat: StandardMaterial3D      # the instruments and screen
var _paint := Color(0.12, 0.27, 0.2)


func _init() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.66, 0.05)
	inertia = Vector3(4900.0, 5300.0, 1150.0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.15
	can_sleep = false
	continuous_cd = true
	collision_layer = 2
	collision_mask = 1 | 2
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var tyre := RayWheel.car_tyre(245.0)
	for z in [FRONT_Z, REAR_Z]:
		for x in [-HALF_TRACK, HALF_TRACK]:
			var front: bool = z == FRONT_Z
			var w := RayWheel.make(Vector3(x, MOUNT_Y, z), RADIUS, TRAVEL, SPRING_F if front else SPRING_R, BUMP, REBOUND,
				WHEEL_INERTIA, tyre)
			w["abs"] = true
			w["front"] = front
			wheels.append(w)
	# The body: the chassis and load bed low down, the cab and bonnet over it.
	_box_shape(Vector3(1.86, 0.62, 5.3), Vector3(0.0, 0.78, 0.15))
	_box_shape(Vector3(1.8, 0.75, 2.4), Vector3(0.0, 1.45, -0.55))
	_build_model()


func _box_shape(size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	add_child(cs)


## Puts the truck down at `xf` (its origin on the ground), still.
func place(xf: Transform3D) -> void:
	global_transform = xf
	if is_inside_tree():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer = 0.0
	gear = 1
	reverse_selected = false
	for w in wheels:
		w["omega"] = 0.0
		w["sy"] = 0.0


## Where the driver's eyes are, for the in-cab camera.
func eye_transform() -> Transform3D:
	return Transform3D(Basis(), EYE)


## The world point the trailer's coupler sits on.
func hitch_point() -> Vector3:
	return global_transform * HITCH


## The engine's torque at `at_rpm`, N m, wide open.
static func engine_torque(at_rpm: float) -> float:
	var c: Array = TORQUE_CURVE
	if at_rpm <= float(c[0][0]):
		return float(c[0][1])
	for i in range(1, c.size()):
		if at_rpm <= float(c[i][0]):
			var f := (at_rpm - float(c[i - 1][0])) / (float(c[i][0]) - float(c[i - 1][0]))
			return lerpf(float(c[i - 1][1]), float(c[i][1]), f)
	return float(c[-1][1])


## The gearing from the engine to the back wheels in `g` (negative in reverse, 0 in neutral).
static func ratio_of(g: int) -> float:
	if g == 0:
		return 0.0
	if g < 0:
		return -REVERSE * FINAL_DRIVE
	return float(GEARS[clampi(g, 1, GEARS.size()) - 1]) * FINAL_DRIVE


## The most the front wheels turn at this speed: full lock in the yard, a few degrees at speed.
func max_steer() -> float:
	return lerpf(MAX_STEER, deg_to_rad(5.0), clampf(absf(speed) / 32.0, 0.0, 1.0))


func shift_up() -> void:
	if gear < GEARS.size():
		if gear < 0 and absf(speed) > 1.0:
			return
		# The automatic goes from reverse straight to drive (there's no neutral to stop in).
		gear = 1 if gear < 0 and auto_shift else gear + 1
		_shifted()


## Down a gear; at a standstill, down from first (through neutral on the manual box) into
## reverse. The automatic's lever goes from drive straight to reverse.
func shift_down() -> void:
	if auto_shift and gear == 1 and absf(speed) < 1.0:
		gear = -1
		reverse_selected = true
		_shifted()
	elif gear > (-1 if absf(speed) < 1.0 else 1):
		gear -= 1
		reverse_selected = gear < 0
		_shifted()


## In the automatic's own reverse (found by holding the brake at a standstill): the pedals swap
## round, the brake pedal backing it up and the throttle stopping it.
func pedals_swapped() -> bool:
	return gear < 0 and auto_shift and not reverse_selected


## Turns the key: the starter turns it over for a moment, then it catches.
func start_engine() -> void:
	if engine_on or _starting > 0.0:
		return
	_starting = START_TIME


func stop_engine() -> void:
	_starting = 0.0
	if not engine_on:
		return
	engine_on = false
	engine_changed.emit(false)


func is_starting() -> bool:
	return _starting > 0.0


## The headlamp switch: off, dipped, main beam and round to off. Returns the new stop's name.
func cycle_beam() -> String:
	beam = (beam + 1) % BEAM_NAMES.size()
	Sfx.play_at("switch", global_position + global_basis * EYE, -10.0)
	return BEAM_NAMES[beam]


func _shifted() -> void:
	if gear >= 0:
		reverse_selected = false
	_shift_timer = SHIFT_TIME
	_since_shift = 0.0
	gear_changed.emit(gear)


func _physics_process(delta: float) -> void:
	var b := global_basis
	speed = linear_velocity.dot(-b.z)
	if freeze:
		_update_model(delta)
		return
	if not controls_enabled:
		throttle = 0.0
		brake = 0.0
		handbrake = 1.0
	if _starting > 0.0:
		_starting -= delta
		if _starting <= 0.0:
			_starting = 0.0
			engine_on = true
			rpm = IDLE_RPM * 1.3
			engine_changed.emit(true)
	_update_gear_choice(delta)
	_update_steering(delta)
	var drive := _update_engine(delta)
	# Going forwards the pedal on the right is the throttle and the left the brake; in the
	# automatic's own reverse they swap round, so S backs you up and W stops you.
	var pedal_brake := throttle if pedals_swapped() else brake
	braking = pedal_brake > 0.1
	for w in wheels:
		var front: bool = w["front"]
		w["brake_torque"] = pedal_brake * (BRAKE_FRONT if front else BRAKE_REAR)
		if not front:
			w["brake_torque"] = maxf(float(w["brake_torque"]), handbrake * HANDBRAKE)
			# An open differential: the same torque to each back wheel.
			w["drive_torque"] = drive * 0.5
			w["abs"] = handbrake < 0.1
		else:
			w["drive_torque"] = 0.0
	var space := get_world_3d().direct_space_state
	var share := mass * 0.25
	for w in wheels:
		RayWheel.step(self, w, delta, space, share, MASS * G * 0.25)
	var v := linear_velocity
	apply_central_force(-0.5 * 1.225 * CDA * v.length() * v)
	# Stood still on the brakes: hold it (a tyre at rest has its own static grip).
	if absf(speed) < 0.3 and (pedal_brake > 0.3 or handbrake > 0.3) and wheels.any(func(w): return w["contact"]):
		var flat := linear_velocity - b.y * linear_velocity.dot(b.y)
		apply_central_force(-flat * mass * 8.0)
	_update_model(delta)


## The automatic's choice of drive or reverse: hold the brake at a standstill and it goes into
## reverse; touch the throttle stopped in reverse and it's back in first.
func _update_gear_choice(delta: float) -> void:
	_shift_timer -= delta
	_since_shift += delta
	if not auto_shift:
		return
	if gear >= 1 and absf(speed) < 0.6 and brake > 0.5 and throttle < 0.1:
		_rev_hold += delta
		if _rev_hold > 0.35:
			gear = -1
			_rev_hold = 0.0
			_shifted()
	elif pedals_swapped() and absf(speed) < 0.6 and throttle > 0.3 and brake < 0.1:
		_rev_hold += delta
		if _rev_hold > 0.2:
			gear = 1
			_rev_hold = 0.0
			_shifted()
	else:
		_rev_hold = 0.0
	if gear == 0:
		gear = 1


func _update_steering(delta: float) -> void:
	var want := clampf(steer_input, -1.0, 1.0) * max_steer()
	# Let go and the castor brings the wheel back to the middle, quicker the faster you go.
	var rate := STEER_RATE * (1.0 if absf(steer_input) > 0.01 else 1.0 + absf(speed) * 0.05)
	steer = move_toward(steer, want, rate * delta)
	# Ackermann: the inside wheel turns tighter, round the same middle as the outside one.
	if absf(steer) < 1e-4:
		wheels[0]["steer"] = 0.0
		wheels[1]["steer"] = 0.0
		return
	var r := WHEELBASE / tan(absf(steer))
	var inner := atan(WHEELBASE / maxf(r - HALF_TRACK, 0.5))
	var outer := atan(WHEELBASE / (r + HALF_TRACK))
	var s := signf(steer)
	wheels[0]["steer"] = s * (outer if s > 0.0 else inner)   # front left: outside in a right turn
	wheels[1]["steer"] = s * (inner if s > 0.0 else outer)


## The engine and gearbox: the revs from the back wheels through the gears (the clutch slips at
## a standstill, holding launch revs), the torque off the curve, the rev limiter, engine braking,
## and the automatic's shifts. Returns the drive torque at the axle.
func _update_engine(delta: float) -> float:
	var ratio := ratio_of(gear)
	var wheel_omega := (float(wheels[2]["omega"]) + float(wheels[3]["omega"])) * 0.5
	var wheel_rpm := wheel_omega * ratio * 60.0 / TAU
	var engaged := ratio != 0.0 and wheel_rpm >= IDLE_RPM + 350.0
	var accel := brake if pedals_swapped() else throttle
	if not engine_on:
		accel = 0.0
	if _shift_timer > 0.0:
		rpm = lerpf(rpm, maxf(wheel_rpm, IDLE_RPM), 0.25)
	elif engaged:
		rpm = wheel_rpm
	else:
		var launch := lerpf(IDLE_RPM, 2100.0, accel)
		rpm = lerpf(rpm, maxf(launch, wheel_rpm), 1.0 - exp(-8.0 * delta))
	if _starting > 0.0:
		rpm = lerpf(rpm, IDLE_RPM * 0.3, 0.2)   # the starter turning it over
	elif not engine_on:
		rpm = move_toward(rpm, 0.0, 2500.0 * delta)
	var torque := engine_torque(rpm) * accel
	if rpm >= REDLINE or (gear < 0 and rpm >= REVERSE_LIMIT):
		torque = 0.0
	if engaged and accel < 0.05:
		torque -= 45.0 * clampf(rpm / REDLINE, 0.2, 1.0)   # engine braking
	if _shift_timer > 0.0 or ratio == 0.0:
		torque = 0.0
	rpm = clampf(rpm, IDLE_RPM * 0.9 if engine_on else 0.0, REDLINE * 1.02)
	if auto_shift and gear >= 1 and _since_shift > 0.9 and _shift_timer <= 0.0:
		var road_rpm := absf(speed) / RADIUS * ratio * 60.0 / TAU
		var up_at := lerpf(2000.0, 4100.0, clampf(accel, 0.0, 1.0))
		if road_rpm > up_at and gear < GEARS.size():
			gear += 1
			_shifted()
		elif gear > 1:
			var lower := road_rpm * ratio_of(gear - 1) / ratio
			if (road_rpm < 1250.0 or (accel > 0.9 and road_rpm < 2200.0)) and lower < 3900.0:
				gear -= 1
				_shifted()
	return torque * ratio * EFFICIENCY


## How much revs the engine note should carry.
func sound_load() -> float:
	if _shift_timer > 0.0:
		return 0.1
	return brake if pedals_swapped() else throttle


## The engine note's recipe: a four-cylinder turbo diesel on a quiet standard pipe.
static func engine_spec() -> Dictionary:
	return EngineSynth.make_spec("inline", 4, 2400.0, {"idle": IDLE_RPM, "redline": REDLINE, "peak": 1800.0,
		"exhaust": "stock", "loud": 0.45, "intake": "airbox", "shift": "clunk"})


# ---------------------------------------------------------------------------- network

## Snapshot for the network: where it is, its wheels, revs and gear, then its lamps and starter.
func get_net_state() -> PackedFloat32Array:
	var q := global_basis.get_rotation_quaternion()
	var p := global_position
	var v := linear_velocity
	var s := PackedFloat32Array([p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, steer, rpm, sound_load(), float(gear),
		1.0 if engine_on else 0.0, 1.0 if braking else 0.0])
	for w in wheels:
		s.append(float(w["spin"]))
		s.append(float(w["compression"]))
	s.append(float(beam))
	s.append(1.0 if is_starting() else 0.0)
	return s


const NET_SIZE := 26


## Shows another player's truck as their snapshot has it (frozen, kinematic).
func set_net_state(s: PackedFloat32Array, at := 0) -> void:
	if s.size() < at + NET_SIZE:
		return
	var xf := Transform3D(Basis(Quaternion(s[at + 3], s[at + 4], s[at + 5], s[at + 6]).normalized()), Vector3(s[at], s[at + 1], s[at + 2]))
	global_transform = xf
	steer = s[at + 10]
	rpm = s[at + 11]
	gear = int(s[at + 13])
	engine_on = s[at + 14] > 0.5
	braking = s[at + 15] > 0.5
	for i in 4:
		wheels[i]["spin"] = s[at + 16 + i * 2]
		wheels[i]["compression"] = s[at + 17 + i * 2]
	beam = int(s[at + 24])
	_starting = START_TIME if s[at + 25] > 0.5 else 0.0
	wheels[0]["steer"] = steer
	wheels[1]["steer"] = steer


# ---------------------------------------------------------------------------- model

## The truck's looks: see CarModel.
func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	CarModel.new(self).build()
	_update_model(0.0)


func _update_model(_delta: float) -> void:
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var holder: Node3D = _wheel_nodes[i][0]
		var spin: Node3D = _wheel_nodes[i][1]
		var m: Vector3 = w["mount"]
		holder.position = Vector3(m.x, m.y - (TRAVEL - float(w["compression"])), m.z)
		holder.rotation = Vector3(0.0, -float(w["steer"]), 0.0)
		spin.rotation.x = -float(w["spin"])
	if _steering_wheel:
		_steering_wheel.rotation.y = -steer * STEER_RATIO
	# Every lamp runs off the ignition, as on the bikes: a truck that isn't running is dark. The
	# tail lamps are on with the headlamps, brighter on the brakes.
	var lamps := engine_on and beam > 0
	if _brake_mat:
		_brake_mat.emission_energy_multiplier = 3.0 if braking and engine_on else (0.6 if lamps else 0.0)
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = (3.5 if beam >= 2 else 2.5) if lamps else (0.3 if engine_on else 0.0)
	if _reverse_mat:
		_reverse_mat.emission_energy_multiplier = 2.0 if engine_on and gear < 0 else 0.0
	if _dash_mat:
		_dash_mat.emission_energy_multiplier = 0.8 if engine_on else 0.0
	_update_beams(lamps)


## The headlamp beams: dipped, a wide pool down on the road just ahead; main beam, a long narrow
## reach up the road. The eye adjusts at night, so the same lamps throw a brighter pool then
## (and light the night air a little, as the bikes' do).
func _update_beams(on: bool) -> void:
	var night := World.darkness()
	var high := beam >= 2
	for l: SpotLight3D in _head_lights:
		l.visible = on
		if not on:
			continue
		l.light_energy = (1.0 + 3.0 * night) * (2.6 if high else 1.4)
		l.spot_angle = 20.0 if high else lerpf(30.0, 36.0, night)
		l.spot_range = 95.0 if high else 42.0
		l.rotation.x = deg_to_rad(-1.0 if high else -5.5)
		l.light_volumetric_fog_energy = night * (0.5 if high else 0.3)
