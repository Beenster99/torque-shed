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
const LONG_STIFFNESS := 14.0      # longitudinal force per unit slip ratio, per newton of load
const LAT_B := 12.0               # lateral tyre curve shape
const LAT_C := 1.35
const SLIDE_FACTOR := 0.82        # sliding friction relative to peak
const ROLLING_RESISTANCE := 0.015
const CRASH_LEAN := deg_to_rad(78.0)
const CRASH_PITCH := deg_to_rad(72.0)
const AUTO_RESPAWN_TIME := 3.5
const START_TIME := 0.7           # seconds on the starter motor before it fires
const WHEELIE_PITCH := deg_to_rad(28.0)   # where the rider tries to hold a wheelie (weight back: higher)
const STOPPIE_PITCH := deg_to_rad(14.0)   # and a stoppie, nose down
const AIR_REV_PITCH := 7.0        # pitch acceleration (rad/s^2) from blipping the rear wheel in the air
const SKID_SLIP := 0.2            # tyre slip above which it screeches and marks the road
const FRONT_LOCK_SLIP := 0.1      # the rider (or ABS) eases the brake before a wheel slips more than this
const PADDLE_SPEED := 1.1         # walking pace when the rider paddles backwards with their feet
const PADDLE_HOLD := 0.45         # hold the front brake this long at a standstill to start paddling back
const BURNOUT_SPEED := 2.5        # below this, front brake plus throttle lights up the back tyre

var build: BikeBuild

# Rider inputs, set by the player controller or by tests.
var throttle := 0.0
var front_brake := 0.0
var rear_brake := 0.0
var lean_input := 0.0      # -1 lean left .. 1 lean right
var body_shift := 0.0      # -1 weight back (wheelies) .. 1 weight forward
var auto_shift := true
var assist := 0.5          # rider balance help: 0 sim .. 1 easy
var controls_enabled := true
var engine_on := true      # a parked bike you get on starts with it off; tests ride with it running
var fuel_litres := 15.0    # petrol left in the tank
var fuel_used := 0.0       # litres burnt since the last time someone read and cleared it
var effects: BikeEffects

# Simulation state, read by the HUD, camera, audio and network.
var gear := 1
var rpm := 1000.0
var steer := 0.0
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
var rider_color := Color(0, 0, 0, 0)   # the rider's own colours; clear uses the bike's paint
var burnout := 0.0         # 0..1, how hard the back tyre is spinning on the spot
var paddling := false      # walking the bike backwards with the rider's feet
var horn_audio: HornAudio
var _stopped_brake := 0.0  # how long the front brake has been held at a standstill
var _fog: Array = []


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
	add_child(model)
	model.build_from(build, paint)
	for l in _fog:
		l.free()
	_fog = make_fog_lights(self, model, build)
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
	gear = 1
	rpm = build.idle_rpm
	for w in wheels:
		w["omega"] = 0.0
		w["compression"] = 0.0
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
	for l in _fog:
		l.visible = engine_on

	if is_crashed:
		throttle = 0.0
		_crash_timer += delta
		if _crash_timer > AUTO_RESPAWN_TIME:
			respawn()
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
			rear_grip = maxf(rear_grip, clampf(over * 3.0 + rising * 0.6, 0.0, 1.0) * lerpf(0.45, 1.0, assist))
	var front_grip := front_brake
	if not wheels[1]["contact"] and wheels[0]["contact"] and pitch_angle < -deg_to_rad(3.0):
		# Holding a stoppie: ease the front brake as the back climbs past the balance angle.
		var over := -pitch_angle - STOPPIE_PITCH
		var falling := -angular_velocity.dot(global_transform.basis.x)
		front_grip *= clampf(1.0 - (over * 5.0 + falling * 0.8) * lerpf(0.45, 1.0, assist), 0.0, 1.0)
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
	_check_crash()

	if model:
		model.update_pose(self)
	if effects:
		effects.update(delta, speed, throttle, engine_on, build.overall_health(), surface,
			wheels[1]["contact"], wheels[1]["slip"])
		effects.update_skids(self)
		if effects.has_method("set_tyre_smoke"):
			effects.call("set_tyre_smoke", burnout, Vector3(0.0, -build.rear_radius, build.wheelbase * 0.5))


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
	return lean_input * MAX_LEAN * speed_factor


func _max_steer() -> float:
	return lerpf(deg_to_rad(35.0), deg_to_rad(3.5), clampf(absf(speed) / 45.0, 0.0, 1.0))


## The rider steers to reach the lean they want: counter-steer to start the lean,
## then hold the steady-turn steering angle for the current lean and speed.
func _update_steering(delta: float) -> void:
	var v := absf(speed)
	var target := _target_lean()
	var cmd: float
	if v < 2.0:
		# Feet down at walking pace: the bars just point where the rider steers them.
		cmd = lean_input * _max_steer()
	else:
		var steer_eq := atan(build.wheelbase * G * tan(lean_angle) / (v * v))
		var gain := clampf(8.0 / v, 0.25, 2.5)
		var err := target - lean_angle
		cmd = steer_eq - 0.22 * gain * err + 0.06 * gain * lean_rate
	cmd = clampf(cmd, -_max_steer(), _max_steer())
	steer = move_toward(steer, cmd, build.steer_rate * delta)


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
		var launch := lerpf(build.idle_rpm, build.peak_torque_rpm * 0.75, throttle)
		rpm = lerpf(rpm, maxf(launch, wheel_rpm), 1.0 - exp(-10.0 * delta))

	# Rider throttle control: with assist on, roll off when the rear tyre spins up.
	var v_ground := maxf(absf(speed), 1.0)
	var spin_ratio: float = (rear["omega"] * build.rear_radius - v_ground) / v_ground
	var tc_target := 1.0
	var tc := maxf(assist, build.ecu_aid if build.has_aid("traction") else 0.0)
	var tc_from := 0.08 if build.has_aid("traction") else 0.12
	if tc > 0.05 and spin_ratio > tc_from and rear["contact"] and burnout <= 0.0:
		tc_target = clampf(1.0 - (spin_ratio - tc_from) * 4.0 * tc, 0.15, 1.0)
	# In a wheelie the rider feathers the throttle to hold the front up at the balance angle
	# rather than looping it; more assist, steadier hands.
	if not wheels[0]["contact"] and rear["contact"] and pitch_angle > deg_to_rad(4.0):
		var over := pitch_angle - wheelie_target()
		var rising := angular_velocity.dot(global_transform.basis.x)
		var hands := lerpf(0.45, 1.0, assist)
		tc_target = minf(tc_target, clampf(1.0 - (over * 8.0 + rising * 1.2) * hands, 0.0, 1.0))
	if build.has_aid("anti_wheelie") and pitch_angle > deg_to_rad(2.0):
		# The ECU's anti-wheelie trims the power to keep the front wheel skimming the road.
		var cap := deg_to_rad(lerpf(20.0, 4.0, build.ecu_aid))
		tc_target = minf(tc_target, clampf(1.0 - (pitch_angle - cap) * 12.0, 0.05, 1.0))
	_traction = lerpf(_traction, tc_target, 1.0 - exp(-25.0 * delta))
	var torque := build.engine_torque(rpm) * throttle * _traction
	if rpm >= build.redline:
		torque = 0.0  # rev limiter
	var made := maxf(torque, 0.0)
	if engaged:
		# Engine braking when the throttle is closed.
		torque -= (1.0 - throttle) * build.peak_torque * 0.25 * clampf(rpm / build.redline, 0.0, 1.0)
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


## How much revs the engine note should carry: the throttle, except while the clutch is in for a shift.
func sound_load() -> float:
	return throttle * 0.15 if _shift_timer > 0.0 else throttle


func _wheel_forces(w: Dictionary, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var b := global_transform.basis
	var up := b.y
	var mount: Vector3 = global_transform * w["mount"]
	var radius: float = w["radius"]
	var travel: float = w["travel"]
	var ray_len := travel + radius
	var query := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var inertia_w: float = w["inertia"]

	if hit.is_empty():
		w["contact"] = false
		w["load"] = 0.0
		w["compression"] = move_toward(w["compression"], 0.0, delta * 2.0)
		var omega: float = w["omega"] + w["drive_torque"] * delta / inertia_w
		omega = move_toward(omega, 0.0, w["brake_torque"] * delta / inertia_w)
		w["omega"] = omega * 0.999
		w["spin"] = fmod(w["spin"] + w["omega"] * delta, TAU)
		w["slip"] = 0.0
		return

	var dist := mount.distance_to(hit["position"])
	var raw_comp := ray_len - dist
	var comp := clampf(raw_comp, 0.0, travel)
	var comp_vel: float = (comp - w["compression"]) / delta
	w["compression"] = comp
	var n: Vector3 = hit["normal"]
	# Bump damping resists the wheel coming up, rebound damping resists it going back down.
	var damping: float = w["bump"] if comp_vel > 0.0 else w["rebound"]
	var fz: float = w["spring"] * comp + damping * comp_vel
	if raw_comp > travel:
		fz += (raw_comp - travel) * 250000.0  # bump stop
	fz = clampf(fz, 0.0, mass * G * 8.0)
	w["contact"] = true
	w["load"] = fz
	var collider = hit["collider"]
	var surf := "grass"
	if collider and collider.has_meta("surface"):
		surf = collider.get_meta("surface")
	w["surface"] = surf

	var contact: Vector3 = hit["position"]
	w["contact_pos"] = contact
	w["normal"] = n
	var arm := contact - global_position
	apply_force(n * fz, arm)

	# Tyre frame on the ground plane.
	var heading := -b.z
	if w["is_front"]:
		heading = heading.rotated(up, -steer)
	var long_dir := (heading - n * heading.dot(n)).normalized()
	var lat_dir := n.cross(long_dir)
	var v_contact := linear_velocity + angular_velocity.cross(arm)
	var v_long := v_contact.dot(long_dir)
	var v_lat := v_contact.dot(lat_dir)
	var mu: float = float((build.grip_front if w["is_front"] else build.grip_rear).get(surf, 0.7))
	var f_max := mu * fz

	# Longitudinal: implicit wheel spin update so stiff tyres stay stable.
	var omega: float = w["omega"] + w["drive_torque"] * delta / inertia_w
	omega = move_toward(omega, 0.0, w["brake_torque"] * delta / inertia_w)
	var k := LONG_STIFFNESS * fz / maxf(absf(v_long), 3.0)
	var omega_new := (inertia_w * omega + k * radius * v_long * delta) / (inertia_w + k * radius * radius * delta)
	var fx := k * (omega_new * radius - v_long)
	fx -= signf(v_long) * build.rolling * fz

	# Lateral: slip-angle curve, limited so it can't overshoot at low speed.
	var alpha := atan2(v_lat, maxf(absf(v_long), 2.5))
	var fy := -mu * fz * sin(LAT_C * atan(LAT_B * alpha))
	var fy_cap := absf(v_lat) * mass * 0.5 / delta
	fy = clampf(fy, -fy_cap, fy_cap)

	# Friction circle: peak grip, then sliding.
	var total := sqrt(fx * fx + fy * fy)
	var slip_ratio := 0.0
	if total > f_max and total > 0.0:
		# Tarmac lets go once the tyre slides; loose dirt and grass keep biting as it digs in.
		var slide := SLIDE_FACTOR if surf == "tarmac" else 0.95
		var limit := f_max * slide if total > f_max * 1.25 else f_max
		var scale := limit / total
		fx *= scale
		fy *= scale
		omega_new = omega - fx * radius * delta / inertia_w
		slip_ratio = clampf((total - f_max) / f_max, 0.0, 1.0)
	if burnout > 0.0 and not w["is_front"]:
		# Lit up: the tyre spins free against the road, smoking, while the feet hold the bike.
		if total > f_max:
			omega_new = omega - fx * (1.0 - 0.4 * burnout) * radius * delta / inertia_w
		fx *= 1.0 - 0.85 * burnout
		slip_ratio = maxf(slip_ratio, burnout)
	if (w["is_front"] or build.has_aid("abs")) and v_long > 1.0 and w["brake_torque"] > 0.0 \
			and omega_new * radius < v_long * (1.0 - FRONT_LOCK_SLIP):
		# The rider feels the front tyre and holds it at the edge of grip instead of locking it;
		# ABS does the same for the back. Peak grip, no slide, no skid.
		omega_new = v_long * (1.0 - FRONT_LOCK_SLIP) / radius
		fx = -signf(v_long) * sqrt(maxf(f_max * f_max - fy * fy, 0.0))
		slip_ratio = 0.0
	w["slip"] = slip_ratio
	w["omega"] = omega_new
	w["spin"] = fmod(w["spin"] + omega_new * delta, TAU)
	apply_force(long_dir * fx + lat_dir * fy, arm)


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
		pitch_tau -= pitch_rate * inertia.x * lerpf(1.2, 3.0, assist)
	apply_torque(right * pitch_tau)
	if not any_contact:
		# Stop the bike yawing wildly in the air.
		apply_torque(-b.y * angular_velocity.dot(b.y) * mass * 0.6)


func _check_crash() -> void:
	if absf(lean_angle) > CRASH_LEAN or absf(pitch_angle) > CRASH_PITCH or global_transform.basis.y.y < -0.2:
		crash()


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
		1.0 if (horn_audio and horn_audio.pressed) else 0.0, float(gear), burnout,
	])


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
