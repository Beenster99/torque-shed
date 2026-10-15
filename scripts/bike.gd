class_name Bike
extends RigidBody3D
## The ridden motorbike: one rigid body with ray-cast wheels, a slip-based tyre model,
## an engine, clutch and gearbox model, and a rider who balances it by steering.
##
## Local axes: forward is -Z, up is +Y, right is +X. The body origin sits at axle height
## with the suspension fully extended, midway between the wheels.

signal crashed
signal respawned
signal gear_changed(gear: int)
signal engine_changed(running: bool, reason: String)

const G := 9.81
const MAX_LEAN := deg_to_rad(52.0)
const ROLLING_RESISTANCE := 0.015
const LONG_SLIP_SPEED := 3.0      # m/s: slip ratios are taken against at least this speed, so a crawl stays calm
const LAT_SLIP_SPEED := 2.5       # and slip angles against at least this one
const RELAX_SPEED := 4.0          # grip builds over the relaxation length, timed at no less than this speed
const STEER_LOCK := deg_to_rad(38.0)
const STEER_DAMPING := 2.5        # Nm per rad/s: the bearings, the tyre scrubbing and the rider's arms
const CRASH_LEAN := deg_to_rad(78.0)
const CRASH_PITCH := deg_to_rad(72.0)
const AUTO_RESPAWN_TIME := 3.5
const START_TIME := 0.7           # seconds on the starter motor before it fires
const WHEELIE_PITCH := deg_to_rad(28.0)   # where the rider tries to hold a wheelie (weight back: higher)
const STOPPIE_PITCH := deg_to_rad(14.0)   # and a stoppie, nose down
const AIR_REV_PITCH := 7.0        # pitch acceleration (rad/s^2) from blipping the rear wheel in the air
const SKID_SLIP := 0.2            # tyre slip above which it screeches and marks the road
const BUMP_HEIGHT := {"tarmac": 0.006, "concrete": 0.004, "dirt": 0.035, "grass": 0.025, "gravel": 0.03}
static var _bumps: FastNoiseLite
## How much past the grip that's left for braking (normalised slip) a rider with no help lets the
## front go before they'd ease off: with full care (Riding realism 0.5 and up) none at all.
const CARELESS_SLIP := 0.9
const PADDLE_SPEED := 1.1         # walking pace when the rider paddles backwards with their feet
const PADDLE_HOLD := 0.45         # hold the front brake this long at a standstill to start paddling back
const BURNOUT_SPEED := 2.5        # below this, front brake plus throttle lights up the back tyre
const BEAM_FOG := 3               # the headlight switch's last stop on a bike with fog lights
const DONUT_RATE := 2.2           # rad/s: how fast a full-lock burnout swings the back round the front wheel

var build: BikeBuild

# Rider inputs, set by the player controller or by tests.
var throttle := 0.0
var front_brake := 0.0
var rear_brake := 0.0
var lean_input := 0.0      # -1 lean left .. 1 lean right
var body_shift := 0.0      # -1 weight back (wheelies) .. 1 weight forward
var auto_shift := true
## Riding realism: 0 is the full sim (nothing holds the front, a slide that grips again can
## throw you off), 0.5 and up the rider protects the front tyre and smooths the throttle, 1 also
## balances the bike for you. Kept as "assist" for the settings file and tests.
var assist := 0.5
## Records the ride for the telemetry overlay and the dyno desk; only the local player's bike has one.
var telemetry: RideTelemetry
var controls_enabled := true
var engine_on := true      # a parked bike you get on starts with it off; tests ride with it running
var fuel_litres := 15.0    # petrol left in the tank
var fuel_used := 0.0       # litres burnt since the last time someone read and cleared it
var effects: BikeEffects

# Simulation state, read by the HUD, camera, audio and network.
var gear := 1
var rpm := 1000.0
var steer := 0.0            # radians, + bars turned right
var steer_vel := 0.0        # how fast the bars are turning, rad/s
var speed := 0.0           # forward speed, m/s
var lean_angle := 0.0      # radians, positive = leaning right
var lean_rate := 0.0
var pitch_angle := 0.0     # radians, positive = nose up
var is_crashed := false
var surface := "tarmac"
var wheels: Array = []     # [front, rear] Dictionaries
var model: BikeModel

var _shift_timer := 0.0
var _since_shift := 0.0
var _traction := 1.0
var _crash_timer := 0.0
var _base_com := Vector3.ZERO
var _rider_shape_index := -1
var _ragdoll: RigidBody3D
var _starting := 0.0
var _shift_from_rpm := 0.0
var skid := 0.0            # 0..1, how hard the tyres are squealing on tarmac, set by the effects
var horn := false          # horn button held
var beam := 1              # headlight switch: 0 off, 1 low beam, 2 high beam, 3 high beam and fog lights (BEAM_FOG)
var rider_color := Color(0, 0, 0, 0)   # the rider's own colours; clear uses the bike's paint
var rider_gear := {}                   # the rider's gear, slot -> RiderGear item id (see RiderFigure)
var burnout := 0.0         # 0..1, how hard the back tyre is spinning on the spot
## Seconds of full burnout since the shed last took it (see take_burnout_time): it wears the back tyre.
var burnout_time := 0.0
## How far a burnout has spun the bike round, radians (+ to the left), since it lit up.
var donut_turn := 0.0
var paddling := false      # walking the bike backwards with the rider's feet
var horn_audio: HornAudio
var _stopped_brake := 0.0  # how long the front brake has been held at a standstill
var _throttle_eff := 0.0   # the throttle as the rider's wrist actually turns it (smoothed with realism up)
var _fog: Array = []
## The rider's riding skills (see Progress.rider_skills): balance, throttle_control, airtime, quick_reset.
var skills := {}
## Works out riding XP as the bike is ridden; only the local player's bike has one.
var ride_xp: RideXP


func setup(new_build: BikeBuild, paint := Color(0.78, 0.09, 0.08)) -> void:
	add_to_group("ridden_bike")   # shed TVs follow whoever is out riding
	build = new_build
	mass = build.total_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_base_com = Vector3(0.0, build.com_height - build.rear_radius, 0.06)
	center_of_mass = _base_com
	# Rough rider-plus-bike inertia (pitch, yaw, roll).
	var m := build.total_mass
	var wb := build.wheelbase
	inertia = Vector3(m * wb * wb * 0.16, m * wb * wb * 0.13, m * 0.11)
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.0
	angular_damp = 0.05
	collision_layer = 2
	collision_mask = 1 | 2 | 4   # world, other bikes, parked bikes in the shed

	for child in get_children():
		if child is CollisionShape3D or child is BikeModel:
			child.free()

	wheels = [
		_make_wheel(true, Vector3(0.0, build.front_travel, -wb * 0.5), build.front_radius,
			build.front_travel, build.front_spring, build.front_bump, build.front_rebound, build.front_inertia),
		_make_wheel(false, Vector3(0.0, build.rear_travel, wb * 0.5), build.rear_radius,
			build.rear_travel, build.rear_spring, build.rear_bump, build.rear_rebound, build.rear_inertia),
	]
	gear = 1
	rpm = build.idle_rpm

	# Collision: frame and engine box, rider, and wheel bumpers that only touch walls and ramps edges.
	var frame_shape := BoxShape3D.new()
	frame_shape.size = Vector3(0.34, 0.45, wb * 0.72)
	_add_shape(frame_shape, Vector3(0.0, 0.42, 0.0))
	var rider_shape := CapsuleShape3D.new()
	rider_shape.radius = 0.2
	rider_shape.height = 0.85
	_rider_shape_index = _add_shape(rider_shape, Vector3(0.0, build.seat_height - build.rear_radius + 0.38, 0.05))
	for w in wheels:
		var bumper := SphereShape3D.new()
		bumper.radius = w["radius"] * 0.78
		_add_shape(bumper, w["mount"])

	model = BikeModel.new()
	model.rider_color = rider_color
	model.rider_gear = rider_gear
	add_child(model)
	model.build_from(build, paint)
	for l in _fog:
		l.free()
	_fog = make_fog_lights(self, model, build)
	beam = mini(beam, beam_stops() - 1)
	if horn_audio:
		horn_audio.free()
	horn_audio = HornAudio.new()
	horn_audio.setup_from(build)
	horn_audio.position = model.lamp_position()
	add_child(horn_audio)
	fuel_litres = build.fuel_litres
	if effects:
		effects.free()
	effects = BikeEffects.new()
	add_child(effects)
	effects.setup(model.exhaust_tip(), Vector3(0.0, -build.rear_radius, wb * 0.5), model.lamp_position(), build.headlight_lumens)

	if not body_shape_entered.is_connected(_on_body_shape_entered):
		body_shape_entered.connect(_on_body_shape_entered)


func _make_wheel(is_front: bool, mount: Vector3, radius: float, travel: float, spring: float,
		bump: float, rebound: float, wheel_inertia: float) -> Dictionary:
	return {
		"is_front": is_front, "mount": mount, "radius": radius, "travel": travel,
		"spring": spring, "bump": bump, "rebound": rebound, "inertia": wheel_inertia,
		"omega": 0.0, "spin": 0.0, "compression": 0.0, "contact": false, "load": 0.0,
		"drive_torque": 0.0, "brake_torque": 0.0, "slip": 0.0, "surface": "tarmac",
		# Tyre state for the telemetry and the steering: slip ratio, slip angle (rad), lateral
		# normalised slip after relaxation, camber (+ leaning right), grip used (0..1+), friction,
		# side force along the bike's right (N), rolling radius, and whether the rider eased the brake.
		"kappa": 0.0, "alpha": 0.0, "sy": 0.0, "camber": 0.0, "grip_used": 0.0, "mu": 0.0,
		"f_side": 0.0, "r_eff": radius, "eased": false, "gx": 0.0, "gy": 0.0,
	}


func _add_shape(shape: Shape3D, pos: Vector3) -> int:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	add_child(cs)
	return cs.get_index()


## Places the bike upright on the ground at the given position and heading.
func place(pos: Vector3, heading: float) -> void:
	_clear_ragdoll()
	is_crashed = false
	_crash_timer = 0.0
	var t := Transform3D(Basis(Vector3.UP, heading), pos + Vector3.UP * (build.rear_radius + 0.05))
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer = 0.0
	steer_vel = 0.0
	gear = 1
	rpm = build.idle_rpm
	for w in wheels:
		w["omega"] = 0.0
		w["compression"] = 0.0
		w["sy"] = 0.0
	if model:
		model.set_rider_visible(true)
	respawned.emit()


## Turns the key: the starter cranks for a moment, then it fires, as long as there's petrol.
func start_engine() -> String:
	if engine_on or _starting > 0.0:
		return ""
	if is_crashed:
		return "Pick the bike up first."
	if fuel_litres <= 0.0:
		return "Out of petrol."
	_starting = START_TIME
	return ""


func stop_engine(reason := "") -> void:
	_starting = 0.0
	if not engine_on:
		return
	engine_on = false
	engine_changed.emit(false, reason)


func is_starting() -> bool:
	return _starting > 0.0


func respawn() -> void:
	var fwd := -global_transform.basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	place(global_position + Vector3.UP * 0.3, heading)


func _physics_process(delta: float) -> void:
	if build == null:
		return
	var space := get_world_3d().direct_space_state
	var b := global_transform.basis
	var fwd := -b.z
	speed = linear_velocity.dot(fwd)
	_measure_attitude()

	if _starting > 0.0:
		_starting -= delta
		rpm = lerpf(rpm, build.idle_rpm * 0.3, 0.2)
		if _starting <= 0.0:
			_starting = 0.0
			engine_on = true
			rpm = build.idle_rpm * 1.3
			engine_changed.emit(true, "")

	if horn_audio:
		horn_audio.pressed = horn and controls_enabled and not is_crashed
	# Every lamp, lens and the clocks run off the ignition: a bike that isn't running is dark.
	var fog_on := engine_on and beam >= BEAM_FOG
	for l in _fog:
		l.visible = fog_on
	if model:
		model.set_lights(engine_on, beam > 0, fog_on)
	if effects:
		effects.beam_mode = beam

	if is_crashed:
		throttle = 0.0
		_crash_timer += delta
		if _crash_timer > AUTO_RESPAWN_TIME - float(skills.get("quick_reset", 0)):
			respawn()
		if ride_xp:
			ride_xp.step(self, delta)
		return

	if not controls_enabled:
		throttle = 0.0
		front_brake = 1.0
		rear_brake = 1.0

	var shift := body_shift * 0.13
	center_of_mass = _base_com + Vector3(0.0, 0.0, -shift)

	_update_feet(delta)
	_update_steering(delta)
	_update_engine(delta)
	var rear_grip := rear_brake
	if not wheels[0]["contact"] and wheels[1]["contact"] and pitch_angle > deg_to_rad(4.0):
		# Past the wheelie angle the rider covers the back brake to bring the front down.
		var over := pitch_angle - wheelie_target()
		var rising := angular_velocity.dot(global_transform.basis.x)
		if over > 0.0:
			rear_grip = maxf(rear_grip, clampf(over * 3.0 + rising * 0.6, 0.0, 1.0) * _steadiness())
	var front_grip := front_brake
	if not wheels[1]["contact"] and wheels[0]["contact"] and pitch_angle < -deg_to_rad(3.0):
		# Holding a stoppie: ease the front brake as the back climbs past the balance angle.
		var over := -pitch_angle - STOPPIE_PITCH
		var falling := -angular_velocity.dot(global_transform.basis.x)
		front_grip *= clampf(1.0 - (over * 5.0 + falling * 0.8) * _steadiness(), 0.0, 1.0)
	if paddling:
		front_grip = 0.0
	wheels[0]["brake_torque"] = front_grip * build.front_brake_torque
	wheels[1]["brake_torque"] = 0.0 if burnout > 0.0 else rear_grip * build.rear_brake_torque
	for w in wheels:
		_wheel_forces(w, delta, space)
	surface = wheels[1]["surface"] if wheels[1]["contact"] else wheels[0]["surface"]
	_apply_aero()
	_apply_rider_balance()
	_apply_feet()
	_apply_donut(delta)
	_check_crash()

	if model:
		model.update_pose(self)
	if effects:
		effects.update(delta, speed, throttle, engine_on, build.overall_health(), surface,
			wheels[1]["contact"], wheels[1]["slip"])
		effects.update_skids(self)
		if effects.has_method("set_tyre_smoke"):
			effects.call("set_tyre_smoke", burnout, Vector3(0.0, -build.rear_radius, build.wheelbase * 0.5))
	if ride_xp:
		ride_xp.step(self, delta)
	if telemetry:
		telemetry.step(self, delta)


func _measure_attitude() -> void:
	var b := global_transform.basis
	var up := b.y
	var fwd := -b.z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length() < 0.01:
		fwd_flat = Vector3(b.y.x, 0.0, b.y.z)
	fwd_flat = fwd_flat.normalized()
	var right_flat := fwd_flat.cross(Vector3.UP)
	lean_angle = atan2(up.dot(right_flat), up.dot(Vector3.UP))
	lean_rate = angular_velocity.dot(fwd_flat)
	pitch_angle = asin(clampf(fwd.y, -1.0, 1.0))


func _target_lean() -> float:
	var speed_factor := clampf((absf(speed) - 1.0) / 8.0, 0.15, 1.0)
	var want := lean_input * MAX_LEAN * speed_factor
	# That's the lean of the line from the tyres to the centre of mass, which sets the turn; the
	# bike itself leans a little further, as the contact patch rolls in round the tyre's crown.
	var rc := _crown()
	var arm := maxf(build.com_height - rc, 0.2)
	return want + asin(clampf(rc * sin(want) / arm, -1.0, 1.0))


## The tyres' average crown radius (see TyreModel), m.
func _crown() -> float:
	return (float(build.tyre_front.get("crown", 0.0)) + float(build.tyre_rear.get("crown", 0.0))) * 0.5


## The lean of the line from the contact patches to the centre of mass at a body lean of `lean`:
## a little less than the body's on round tyres.
func _balance_lean(lean: float) -> float:
	var rc := _crown()
	var arm := maxf(build.com_height - rc, 0.2)
	return atan2(arm * sin(lean), rc + arm * cos(lean))


func _max_steer() -> float:
	return lerpf(deg_to_rad(35.0), deg_to_rad(3.5), clampf(absf(speed) / 45.0, 0.0, 1.0))


## The rider steers to reach the lean they want: counter-steer to start the lean,
## then hold the steady-turn steering angle for the current lean and speed.
func _update_steering(delta: float) -> void:
	var v := absf(speed)
	var before := steer
	var target := _target_lean()
	var cmd: float
	if v < 2.0:
		# Feet down at walking pace: the bars just point where the rider steers them.
		cmd = lean_input * _max_steer()
	else:
		var steer_eq := atan(build.wheelbase * G * tan(_balance_lean(lean_angle)) / (v * v))
		var gain := clampf(8.0 / v, 0.25, 2.5)
		var err := target - lean_angle
		cmd = steer_eq - 0.22 * gain * err + 0.06 * gain * lean_rate
	cmd = clampf(cmd, -_max_steer(), _max_steer())
	steer = move_toward(steer, cmd, build.steer_rate * delta)
	steer_vel = (steer - before) / delta


func _update_engine(delta: float) -> void:
	var rear: Dictionary = wheels[1]
	var ratio := build.overall_ratio(gear)
	var wheel_rpm: float = rear["omega"] * ratio * 60.0 / TAU
	var clutch_rpm := build.idle_rpm + 900.0
	var engaged := wheel_rpm >= clutch_rpm
	var shifting := _shift_timer > 0.0
	_shift_timer -= delta

	if shifting and engine_on:
		# The clutch is in: the revs fall (or blip up) to the new gear's speed instead of jumping.
		var f := clampf(1.0 - _shift_timer / maxf(build.shift_time, 0.01), 0.0, 1.0)
		rpm = lerpf(_shift_from_rpm, maxf(wheel_rpm, build.idle_rpm), f * f)
	elif engaged:
		rpm = wheel_rpm
	else:
		# Slipping clutch: the engine holds launch revs while the wheel catches up.
		var launch := lerpf(build.idle_rpm, build.peak_torque_rpm * 0.75, _throttle_eff)
		rpm = lerpf(rpm, maxf(launch, wheel_rpm), 1.0 - exp(-10.0 * delta))

	# Rider throttle control: with assist on, roll off when the rear tyre spins up.
	# The rider's wrist: with realism at 0.5 and up the throttle is rolled on and off smoothly,
	# at 0 it goes exactly where the input is, snap shut included.
	var smooth := clampf(assist * 2.0, 0.0, 1.0)
	var rate := lerpf(1000.0, 5.0 if throttle > _throttle_eff else 8.0, smooth)
	_throttle_eff = move_toward(_throttle_eff, throttle, rate * delta)
	var v_ground := maxf(absf(speed), 1.0)
	var spin_ratio: float = (rear["omega"] * float(rear.get("r_eff", build.rear_radius)) - v_ground) / v_ground
	var tc_target := 1.0
	# Throttle Control (a riding skill) feathers it as if there were more assist.
	var tc := maxf(minf(1.0, assist + 0.15 * float(skills.get("throttle_control", 0))), build.ecu_aid if build.has_aid("traction") else 0.0)
	var tc_from := 0.08 if build.has_aid("traction") else 0.12
	if tc > 0.05 and spin_ratio > tc_from and rear["contact"] and burnout <= 0.0:
		tc_target = clampf(1.0 - (spin_ratio - tc_from) * 4.0 * tc, 0.15, 1.0)
	# In a wheelie the rider feathers the throttle to hold the front up at the balance angle
	# rather than looping it; more assist, steadier hands.
	if not wheels[0]["contact"] and rear["contact"] and pitch_angle > deg_to_rad(4.0):
		var over := pitch_angle - wheelie_target()
		var rising := angular_velocity.dot(global_transform.basis.x)
		var hands := _steadiness()
		tc_target = minf(tc_target, clampf(1.0 - (over * 8.0 + rising * 1.2) * hands, 0.0, 1.0))
	if build.has_aid("anti_wheelie") and pitch_angle > deg_to_rad(2.0):
		# The ECU's anti-wheelie trims the power to keep the front wheel skimming the road.
		var cap := deg_to_rad(lerpf(20.0, 4.0, build.ecu_aid))
		tc_target = minf(tc_target, clampf(1.0 - (pitch_angle - cap) * 12.0, 0.05, 1.0))
	_traction = lerpf(_traction, tc_target, 1.0 - exp(-25.0 * delta))
	var torque := build.engine_torque(rpm) * _throttle_eff * _traction
	if rpm >= build.redline:
		torque = 0.0  # rev limiter
	var made := maxf(torque, 0.0)
	if engaged:
		# Engine braking when the throttle is closed.
		torque -= (1.0 - _throttle_eff) * build.peak_torque * 0.25 * clampf(rpm / build.redline, 0.0, 1.0)
	if shifting:
		torque = 0.0
		made = 0.0
	if not engine_on:
		# Engine off: the bike just rolls. The revs fall away to nothing.
		torque = 0.0
		made = 0.0
		if _starting <= 0.0:
			rpm = wheel_rpm if engaged else move_toward(rpm, 0.0, 3000.0 * delta)
	else:
		var burnt := build.fuel_rate(made * rpm * TAU / 60.0 / 1000.0, rpm) / 3600.0 * delta
		fuel_litres -= burnt
		fuel_used += burnt
		if fuel_litres <= 0.0:
			fuel_litres = 0.0
			stop_engine("Out of petrol! Push it home or bring it a can.")
	rear["drive_torque"] = torque * ratio * build.drivetrain_efficiency
	rpm = clampf(rpm, build.idle_rpm * 0.9 if engine_on else 0.0, build.redline * 1.02)

	_since_shift += delta
	if auto_shift and not shifting and _since_shift > 0.6:
		# Shift on road speed, not engine revs, so wheelspin doesn't confuse the gearbox.
		var road_rpm := absf(speed) / build.rear_radius * ratio * 60.0 / TAU
		if road_rpm > build.redline * 0.9 and gear < build.gear_count():
			shift_up()
		elif gear > 1:
			var lower_rpm := road_rpm * build.overall_ratio(gear - 1) / ratio
			if road_rpm < build.peak_torque_rpm * 0.5 and lower_rpm < build.redline * 0.8:
				shift_down()


func shift_up() -> void:
	if gear < build.gear_count():
		_shift_from_rpm = rpm
		gear += 1
		_shift_timer = build.shift_time
		_since_shift = 0.0
		gear_changed.emit(gear)


func shift_down() -> void:
	if gear > 1:
		_shift_from_rpm = rpm
		gear -= 1
		_shift_timer = build.shift_time
		_since_shift = 0.0
		gear_changed.emit(gear)


## The wheelie angle the rider aims for: with their weight back, the balance angle (higher the
## further back); otherwise they keep the front wheel near the ground.
func wheelie_target() -> float:
	var t := deg_to_rad(6.0)
	if body_shift <= -0.25:
		t = WHEELIE_PITCH + deg_to_rad(10.0) * clampf((-body_shift - 0.25) / 0.75, 0.0, 1.0)
	if build and build.has_aid("anti_wheelie"):
		t = minf(t, deg_to_rad(lerpf(20.0, 4.0, build.ecu_aid)))
	return t


## Burnouts and paddling. Front brake and throttle at a standstill spin the back tyre up in a
## cloud of smoke; holding the front brake at a standstill with the throttle shut lets the
## rider walk the bike backwards with their feet, steering with the bars.
func _update_feet(delta: float) -> void:
	var still := absf(speed) < 0.4
	var on_ground: bool = wheels[0]["contact"] and wheels[1]["contact"]
	if paddling:
		if front_brake < 0.3 or throttle > 0.1 or not on_ground:
			paddling = false
	elif still and on_ground and front_brake > 0.5 and throttle < 0.05:
		_stopped_brake += delta
		if _stopped_brake >= PADDLE_HOLD:
			paddling = true
	else:
		_stopped_brake = 0.0
	if paddling:
		_stopped_brake = 0.0
	var lit := engine_on and on_ground and front_brake > 0.5 and throttle > 0.35 and absf(speed) < BURNOUT_SPEED \
		and pitch_angle < deg_to_rad(8.0)
	var spin_v: float = wheels[1]["omega"] * build.rear_radius - speed
	var target := clampf(spin_v / 12.0, 0.0, 1.0) * throttle if lit else 0.0
	burnout = move_toward(burnout, target, delta * 3.0)
	if lit and burnout < 0.05:
		burnout = 0.05   # it has to start somewhere


## The rider's feet: holding the bike still against a burnout, or walking it backwards.
func _apply_feet() -> void:
	var fwd := -global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if burnout > 0.0:
		# The front brake and the rider's legs hold it on the spot while the back tyre spins.
		var v := linear_velocity.dot(flat)
		apply_central_force(-flat * v * mass * 6.0)
	elif paddling:
		var v := linear_velocity.dot(flat)
		apply_central_force(flat * (-PADDLE_SPEED - v) * mass * 2.5)


## Circle burnouts: lit up with the bars turned, the rider pivots the bike round the braked
## front wheel and the spinning back tyre slides round in a circle of smoke. Lean left or right
## (A / D, left stick) to swing it round; the harder the burnout, the faster it goes.
func _apply_donut(delta: float) -> void:
	if burnout <= 0.0:
		donut_turn = 0.0
		return
	burnout_time += burnout * delta
	var b := global_transform.basis
	var yaw_rate := angular_velocity.dot(b.y)
	donut_turn += yaw_rate * delta
	if not (wheels[0]["contact"] and wheels[1]["contact"]):
		return
	# Lean right swings the bike round to the right: the back slides out to the left.
	var want := -lean_input * DONUT_RATE * clampf(burnout * 1.5, 0.0, 1.0)
	var wb := build.wheelbase
	var i_front := inertia.y + mass * wb * wb * 0.25
	var push := (want - yaw_rate) * i_front * 8.0 / wb
	var grip: float = float(build.grip_rear.get(str(wheels[1]["surface"]), 0.7)) * float(wheels[1]["load"])
	push = clampf(push, -grip, grip)
	var at: Vector3 = wheels[1].get("contact_pos", global_transform * Vector3(0.0, -build.rear_radius, wb * 0.5))
	apply_force(b.x * push, at - global_position)


## Hands over the burnout seconds since the last call, for the shed to wear the back tyre.
func take_burnout_time() -> float:
	var t := burnout_time
	burnout_time = 0.0
	return t


## How much revs the engine note should carry: the throttle, except while the clutch is in for a shift.
func sound_load() -> float:
	return throttle * 0.15 if _shift_timer > 0.0 else throttle


## One wheel's suspension and tyre: finds the ground under the round tyre, works the spring and
## damper, then the tyre's Magic Formula with combined slip (see TyreModel) for the drive, brake
## and side forces, and spins the wheel up or down by what the road gives back.
func _wheel_forces(w: Dictionary, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var b := global_transform.basis
	var up := b.y
	var is_front: bool = w["is_front"]
	var tp: Dictionary = build.tyre_front if is_front else build.tyre_rear
	var radius: float = w["radius"]
	var crown := minf(float(tp.get("crown", 0.0)), radius * 0.6)
	var mount: Vector3 = global_transform * w["mount"]
	var travel: float = w["travel"]
	# Leaned over, a round tyre sits lower than a thin disc would: look a little further.
	var ray_len := travel + radius + crown * 2.0
	var query := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var inertia_w: float = w["inertia"]

	var heading := -b.z
	var axle := b.x
	if is_front:
		heading = heading.rotated(up, -steer)
		axle = axle.rotated(up, -steer)
	var raw_comp := -1.0
	var n := Vector3.UP
	var cos_cam := 1.0
	var hit_surf := "grass"
	if not hit.is_empty():
		n = hit["normal"]
		if hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
			hit_surf = str((hit["collider"] as Object).get_meta("surface"))
		# The contact patch rolls round the tyre's crown as it leans: the wheel centre sits
		# (radius - crown) * cos(camber) + crown above the ground.
		var sin_cam := clampf(axle.dot(n), -0.95, 0.95)
		cos_cam = sqrt(1.0 - sin_cam * sin_cam)
		var h_mount: float = (mount - hit["position"]).dot(n)
		var hang := (h_mount - crown - (radius - crown) * cos_cam) / maxf(up.dot(n), 0.2)
		# The ground isn't a billiard table: ripples, ruts and stones under the tyre work the suspension.
		raw_comp = travel - hang + road_bump(hit["position"], hit_surf)

	if raw_comp < 0.0:
		w["contact"] = false
		w["load"] = 0.0
		w["compression"] = move_toward(w["compression"], 0.0, delta * 2.0)
		var omega_air: float = w["omega"] + w["drive_torque"] * delta / inertia_w
		omega_air = move_toward(omega_air, 0.0, w["brake_torque"] * delta / inertia_w)
		w["omega"] = omega_air * 0.999
		w["spin"] = fmod(w["spin"] + w["omega"] * delta, TAU)
		w["slip"] = 0.0
		w["grip_used"] = 0.0
		w["gx"] = 0.0
		w["gy"] = 0.0
		w["kappa"] = 0.0
		w["alpha"] = 0.0
		w["sy"] = 0.0
		w["f_side"] = 0.0
		w["eased"] = false
		return

	var comp := clampf(raw_comp, 0.0, travel)
	var was_touching: bool = w["contact"]
	# How fast the wheel is being pushed up into the bike. On the first frame of touchdown the
	# wheel was hanging free, so take the bike's own closing speed instead of the jump in travel.
	var closing := -(linear_velocity + angular_velocity.cross(mount - global_position)).dot(up)
	var comp_vel: float = (comp - w["compression"]) / delta if was_touching else closing
	var raw_vel: float = (raw_comp - float(w.get("raw", raw_comp))) / delta if was_touching else closing
	w["raw"] = raw_comp
	w["compression"] = comp
	# Bump damping resists the wheel coming up, rebound damping resists it going back down. Fast
	# hits blow the compression valving open a little, as real dampers do, so a big landing is
	# soaked up rather than kicked back.
	var damp_force: float
	if comp_vel > 0.0:
		var bump: float = w["bump"]
		damp_force = bump * (comp_vel if comp_vel < 1.0 else 1.0 + (comp_vel - 1.0) * 0.45)
	else:
		damp_force = float(w["rebound"]) * comp_vel
	var fz: float = w["spring"] * comp + damp_force
	if raw_comp > travel:
		# Bottomed out: a firm, heavily damped rubber stop that eats the energy it takes, both
		# squashing and coming back off it, so it never kicks the bike back up.
		var over := raw_comp - travel
		fz += over * 160000.0 + raw_vel * (9000.0 if raw_vel > 0.0 else 14000.0)
	fz = clampf(fz, 0.0, mass * G * 6.0)
	w["contact"] = true
	w["load"] = fz
	w["surface"] = hit_surf

	# Where the crown touches: from the wheel centre, down the wheel's plane to the crown's
	# centre, then straight down onto the road.
	var down := -n - axle * (-n).dot(axle)
	down = down.normalized() if down.length() > 0.01 else -up
	var centre := mount - up * (travel - comp)
	var contact := centre + down * (radius - crown) - n * crown
	contact -= n * (contact - hit["position"]).dot(n)
	var r_eff := (radius - crown) + crown * cos_cam    # the rolling radius at this camber
	w["r_eff"] = r_eff
	w["contact_pos"] = contact
	w["normal"] = n
	var arm := contact - global_position
	apply_force(n * fz, arm)

	# Tyre frame on the ground plane. lat_dir points to the wheel's left.
	var long_dir := (heading - n * heading.dot(n)).normalized()
	var lat_dir := n.cross(long_dir)
	var v_contact := linear_velocity + angular_velocity.cross(arm)
	var v_long := v_contact.dot(long_dir)
	var v_lat := v_contact.dot(lat_dir)
	var v_abs := absf(v_long)
	var mu_surf: float = float((build.grip_front if is_front else build.grip_rear).get(hit_surf, 0.7))
	mu_surf *= Weather.grip_mult(hit_surf)   # wet roads after rain grip a little less
	var mu := TyreModel.mu_at(mu_surf, fz, build.total_mass * G * 0.5, tp)
	var f_peak := mu * fz
	var bc := TyreModel.stiffness_at_zero(tp)
	var kp: float = tp["kappa_peak"]
	var ap: float = tp["alpha_peak"]
	w["mu"] = mu

	# Lateral: the slip angle and camber thrust as one normalised slip. A leaned tyre pushes
	# towards the lean (camber thrust) once it's rolling; the force builds over the relaxation
	# length rather than all at once.
	var alpha := atan2(v_lat, maxf(v_abs, LAT_SLIP_SPEED))
	var cam_left := asin(clampf(-down.dot(lat_dir), -1.0, 1.0))   # wheel top leaning towards lat_dir
	w["camber"] = -cam_left
	w["alpha"] = alpha
	var rolling_in := clampf((v_abs - 1.0) / 3.0, 0.0, 1.0)
	var sy_now := -tan(clampf(alpha, -TyreModel.MAX_SLIP_ANGLE, TyreModel.MAX_SLIP_ANGLE)) / tan(ap) \
		+ float(tp["camber"]) * cam_left / (maxf(mu, 0.1) * bc) * rolling_in
	var sy := sy_now
	if was_touching:
		var keep := exp(-maxf(v_abs, RELAX_SPEED) * delta / float(tp["relax"]))
		sy = sy_now + (float(w["sy"]) - sy_now) * keep
	w["sy"] = sy

	# Longitudinal: the wheel's new spin is solved implicitly against the tyre's own curve, so a
	# stiff tyre on a light wheel stays stable at the physics rate and a locked wheel stays locked.
	var vden := maxf(v_abs, LONG_SLIP_SPEED)
	var omega: float = w["omega"] + w["drive_torque"] * delta / inertia_w
	omega = move_toward(omega, 0.0, w["brake_torque"] * delta / inertia_w)
	var react := (1.0 - 0.4 * burnout) if burnout > 0.0 and not is_front else 1.0
	var omega_new := _solve_spin(omega, v_long, vden, r_eff, kp, sy, f_peak * react, inertia_w / delta, tp)
	var eased := false
	var care := _brake_care(is_front)
	if care > 0.0 and v_long > 1.0 and w["brake_torque"] > 0.0:
		# The rider feels the tyre and eases the brake before it goes past the grip it has left
		# with the cornering it's doing (ABS does the same for its wheels): with less care, a
		# little later. With none at all a grabbed front brake locks the wheel and tucks the front.
		var left := maxf(sqrt(maxf(1.0 - sy * sy, 0.0)), 0.25)
		var allowed := left + CARELESS_SLIP * (1.0 - care) / care
		if (omega_new * r_eff - v_long) / vden / kp < -allowed:
			omega_new = maxf((v_long - allowed * kp * vden) / r_eff, 0.0)
			eased = true
	w["eased"] = eased
	var sx := (omega_new * r_eff - v_long) / vden / kp
	var g := TyreModel.combined(sx, sy, tp)
	var fx := f_peak * g.x
	var fy := f_peak * g.y
	w["kappa"] = sx * kp
	w["gx"] = g.x
	w["gy"] = g.y
	var rho := Vector2(sx, sy).length()
	w["grip_used"] = Vector2(g.x, g.y).length() if rho <= 1.0 else rho
	var slip_ratio := clampf(rho - 1.0, 0.0, 1.0)
	# At a crawl the tyre can't push harder sideways than it takes to stop the sideways creep.
	var fy_cap := absf(v_lat) * mass * 0.5 / delta
	fy = clampf(fy, -fy_cap, fy_cap)
	fx -= signf(v_long) * build.rolling * fz
	if burnout > 0.0 and not is_front:
		# Lit up: the tyre spins free against the road, smoking, while the feet hold the bike.
		fx *= 1.0 - 0.85 * burnout
		# A spinning tyre has next to no side grip, so the back steps out where the rider pushes it.
		fy *= 1.0 - 0.8 * burnout
		slip_ratio = maxf(slip_ratio, burnout)
	w["slip"] = slip_ratio
	w["omega"] = omega_new
	w["spin"] = fmod(w["spin"] + omega_new * delta, TAU)
	var force := long_dir * fx + lat_dir * fy
	w["f_side"] = force.dot(b.x)
	apply_force(force, arm)


## The wheel speed at the end of the step: where the wheel's spin change balances the tyre's
## grip on the road, I (w - w0) / dt = -r Fx(w). Fx follows the Magic Formula, so this is solved
## (regula falsi, Illinois) between w0 and rolling speed, where the answer always lies.
func _solve_spin(omega0: float, v_long: float, vden: float, r: float, kp: float, sy: float, f_peak: float,
		i_dt: float, tp: Dictionary) -> float:
	var roll := v_long / r
	var a := omega0
	var b := roll
	var fa := r * f_peak * TyreModel.combined((a * r - v_long) / vden / kp, sy, tp).x
	if absf(fa) < 1e-6 or absf(a - b) < 1e-5:
		return a
	var fb := i_dt * (b - omega0)
	var side := 0
	for i in 10:
		var c := (a * fb - b * fa) / (fb - fa)
		var fc := i_dt * (c - omega0) + r * f_peak * TyreModel.combined((c * r - v_long) / vden / kp, sy, tp).x
		if absf(fc) < 0.5 or absf(b - a) < 1e-4:
			return c
		if (fc > 0.0) == (fb > 0.0):
			b = c
			fb = fc
			if side == -1:
				fa *= 0.5
			side = -1
		else:
			a = c
			fa = fc
			if side == 1:
				fb *= 0.5
			side = 1
	return (a * fb - b * fa) / (fb - fa)


## How carefully the rider (or the ECU's ABS) works this wheel's brake, 0..1: 1 holds it at the
## edge of grip, 0 lets it lock. Riding realism 0.5 and up looks after the front; ABS looks after
## its wheels whatever the setting.
func _brake_care(is_front: bool) -> float:
	if build.has_aid("abs"):
		return 1.0
	if is_front:
		return clampf(assist * 2.0, 0.0, 1.0)
	return 0.0


## How far the surface under a tyre rises above its smooth shape at `at`, in metres: a few
## millimetres of ripple on tarmac, proper ruts and stones off-road.
static func road_bump(at: Vector3, surf: String) -> float:
	var amp: float = BUMP_HEIGHT.get(surf, 0.012)
	if amp <= 0.0:
		return 0.0
	if _bumps == null:
		_bumps = FastNoiseLite.new()
		_bumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_bumps.frequency = 0.9
		_bumps.fractal_octaves = 3
		_bumps.fractal_gain = 0.55
	# Only bumps up: the tyre rides over the high spots and the dips are filled by the smooth ground.
	return amp * maxf(_bumps.get_noise_2d(at.x, at.z) + 0.35, 0.0)


func _apply_aero() -> void:
	var v := linear_velocity
	var drag := -0.5 * BikeBuild.AIR_DENSITY * build.cda * v.length() * v
	apply_central_force(drag)


## The rider's body balances the bike: strong when crawling with feet down, light at speed.
func _apply_rider_balance() -> void:
	var b := global_transform.basis
	var fwd := -b.z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var any_contact: bool = wheels[0]["contact"] or wheels[1]["contact"]
	var strength := lerpf(0.15, 1.0, assist)
	if absf(speed) < 3.0:
		strength = 1.0
	var err := _target_lean() - lean_angle
	var tau := (22.0 * err - 4.0 * lean_rate) * mass * strength
	if build.has_aid("stability") and any_contact:
		# Stability control calms a tank-slapper or a twitchy slide.
		tau -= lean_rate * mass * 3.0 * build.ecu_aid
		apply_torque(-b.y * angular_velocity.dot(b.y) * mass * 0.8 * build.ecu_aid)
	if not any_contact:
		tau *= 0.4
	apply_torque(fwd_flat * tau)
	# Pitch control by shifting body weight, mostly useful in the air.
	var right := b.x
	var pitch_tau := -body_shift * (60.0 if any_contact else 220.0)
	var pitch_rate := angular_velocity.dot(right)
	if not any_contact:
		# Spinning the back wheel up rotates the bike backwards; letting it slow (or dabbing the
		# back brake) drops the nose. A third throttle holds it steady.
		var revs := (throttle - 0.33) if engine_on else -0.2
		pitch_tau += (revs - rear_brake * 0.6) * AIR_REV_PITCH * inertia.x
	elif wheels[0]["contact"] != wheels[1]["contact"]:
		# On one wheel the rider's body soaks up the bobbing so it's easier to hold.
		pitch_tau -= pitch_rate * inertia.x * (lerpf(1.2, 3.0, assist) + 0.4 * float(skills.get("balance", 0)))
	apply_torque(right * pitch_tau)
	if not any_contact:
		# Stop the bike yawing wildly in the air.
		apply_torque(-b.y * angular_velocity.dot(b.y) * mass * 0.6)


func _check_crash() -> void:
	# Airtime (a riding skill) rides out landings a little further nose-up or down.
	var pitch_limit := CRASH_PITCH + deg_to_rad(4.0) * float(skills.get("airtime", 0))
	if absf(lean_angle) > CRASH_LEAN or absf(pitch_angle) > pitch_limit or global_transform.basis.y.y < -0.2:
		crash()


## How steady the rider's hands and body are on one wheel: rider assist, plus the Balance skill.
func _steadiness() -> float:
	return lerpf(0.45, 1.0, assist) + 0.12 * float(skills.get("balance", 0))


func _on_body_shape_entered(_rid: RID, _body: Node, _body_shape: int, local_shape: int) -> void:
	if is_crashed:
		return
	var owner_id := shape_find_owner(local_shape)
	var shape_node := shape_owner_get_owner(owner_id) as Node
	if shape_node and shape_node.get_index() == _rider_shape_index and linear_velocity.length() > 4.0:
		crash()


func crash() -> void:
	if is_crashed:
		return
	is_crashed = true
	_crash_timer = 0.0
	throttle = 0.0
	for w in wheels:
		w["drive_torque"] = 0.0
	if model:
		model.set_rider_visible(false)
	_spawn_ragdoll()
	crashed.emit()


func _spawn_ragdoll() -> void:
	_clear_ragdoll()
	_ragdoll = RiderRagdoll.new()
	get_parent().add_child(_ragdoll)
	_ragdoll.dress(rider_gear, rider_color)
	_ragdoll.global_transform = global_transform.translated_local(Vector3(0.0, build.seat_height, 0.0))
	_ragdoll.linear_velocity = linear_velocity * 0.9 + Vector3.UP * 2.0
	_ragdoll.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))


func _clear_ragdoll() -> void:
	if is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
	_ragdoll = null


## Snapshot for the network: position, rotation, velocity, steering, wheels, engine.
func get_net_state() -> PackedFloat32Array:
	var q := global_transform.basis.get_rotation_quaternion()
	var p := global_position
	var v := linear_velocity
	return PackedFloat32Array([
		p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z,
		steer, wheels[0]["spin"], wheels[1]["spin"], wheels[0]["compression"], wheels[1]["compression"],
		rpm, sound_load(), 1.0 if is_crashed else 0.0, body_shift, 1.0 if engine_on else 0.0, skid,
		1.0 if (horn_audio and horn_audio.pressed) else 0.0, float(gear), burnout, float(beam),
	])


## How many stops the headlight switch has: off, low, high, and high with the fog lights on a
## bike that has them.
func beam_stops() -> int:
	return 4 if build and build.fog_lumens > 0.0 else 3


## The headlight switch: off, low beam, high beam (then high beam and fog lights, with fog
## lights fitted), and round to off. Returns the new setting's name.
func cycle_beam() -> String:
	beam = (beam + 1) % beam_stops()
	if effects:
		effects.beam_mode = beam
	Sfx.play_at("switch", global_position, -10.0)
	return BikeEffects.BEAM_NAMES[beam]


## Fog lamp beams for a bike's fog lights, children of `parent`, off until the engine runs.
static func make_fog_lights(parent: Node3D, bike_model: BikeModel, b: BikeBuild) -> Array:
	var out := []
	if b.fog_lumens <= 0.0:
		return out
	var spots := bike_model.fog_positions()
	for at in spots:
		var l := SpotLight3D.new()
		l.position = at
		l.rotation.x = deg_to_rad(-7.0)
		l.spot_range = 12.0 + b.fog_lumens / 160.0
		l.spot_angle = 38.0 if spots.size() > 1 else 30.0
		l.light_energy = b.fog_lumens / 600.0 / spots.size()
		l.light_color = b.fog_color
		l.shadow_enabled = false
		l.visible = false
		parent.add_child(l)
		out.append(l)
	return out
