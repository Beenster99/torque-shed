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
## About as far as anyone leans riding on the road (racers on a track go on further), and the
## share of the steer input that asks for it (see lean_for_input).
const ROAD_LEAN := deg_to_rad(30.0)
const ROAD_INPUT := 0.75
const ROLLING_RESISTANCE := 0.015
const LONG_SLIP_SPEED := 3.0      # m/s: slip ratios are taken against at least this speed, so a crawl stays calm
const LAT_SLIP_SPEED := 2.5       # and slip angles against at least this one
const RELAX_SPEED := 4.0          # grip builds over the relaxation length, timed at no less than this speed
const STEER_LOCK := deg_to_rad(38.0)
const HEAD_DAMPING := 1.2         # Nm per rad/s: the head bearings and the fork seals
const ARM_DAMPING := 2.5          # Nm per rad/s: the rider's hands on the bars soak up a shake, at speed
const ARM_DAMPING_SLOW := 12.0    # and at town speeds, working the bars firmly
const ARM_TRIM := 0.12            # s: how quickly the rider's arms settle into the steady push the bars need
const ARM_INERTIA := 0.35         # kg m^2: the rider's hands and forearms swing with the bars
const ARM_HOLD := 120.0           # Nm per rad: how firmly the rider's arms hold the bars where they aim them, riding
const ARM_HOLD_SLOW := 500.0      # and at walking pace, feet down, steering by hand
const MAX_BAR_TORQUE := 45.0      # Nm: the most a rider pushes through 720 mm bars (wider bars, more leverage)
const DIRECT_BAR_TORQUE := 35.0   # Nm: a full push on the bars in Direct bars mode, 720 mm bars, at DIRECT_PUSH_SPEED
const DIRECT_PUSH_SPEED := 10.0   # m/s: ... growing as the speed to the power 3/4
const DIRECT_PUSH_LEAST := 0.7    # ... from no less than this share at a crawl
const DIRECT_PUSH_MOST := 2.5     # ... to no more than this at speed
const DIRECT_FRONT_REF := 3800.0  # N m per rad: the front stiffness (see _front_stiffness) of a stock road bike the push is set for
const DIRECT_MASS_REF := 260.0     # kg: ... and its weight (a heavier bike takes more to tip in)
const DIRECT_CATCH := 30.0        # N m s per rad: Direct bars, not pushing, the hands steering into a roll they feel (at DIRECT_PUSH_SPEED)
const DIRECT_KEEP := 60.0          # N m per rad: ... and against the lean straying from the one they let go at
const DIRECT_HAND_HOLD := 20.0     # N m per rad: Direct bars, the hands' light hold against a quick shake of the bars
const DIRECT_HAND_FRONT := 0.25    # ... plus this share of the front's stiffness
const DIRECT_BODY_GIVE := 0.6     # how much of their hold on the lean the rider lets go of while pushing the bars at town speeds (all of it from 80 km/h)
const DIRECT_BODY_RATE := 1.0     # Direct bars, riding, not pushing: N m s per radian per kg the rider's body steadies a roll with
const DIRECT_BODY_MAX := 250.0    # N m: the most the rider's body does
const TYRE_RATE := 180000.0       # N/m: how stiffly a tyre's carcass springs back from a ripple in the road
const TYRE_ENVELOPE := 0.1        # m: the tyre wraps round a ripple shorter than about this
const PNEUMATIC_TRAIL := 0.022    # m: how far behind the contact patch a gripping tyre's side force acts
const BODY_SWAY := 0.5            # N m s per rad per kg: the rider's body damping a quick rocking of the bike
const NO_HANDS_LEAN := 2.0        # riding no-handed: N m per radian of lean per kg the rider's hips push back with
const NO_HANDS_RATE := 1.0        # ... and N m s per radian per kg against the bike falling
const NO_HANDS_MAX := 70.0        # N m: as much as a few centimetres of body shift can do
const RIDER_FEEL := 0.035        # s: how quickly the rider feels the bike's lean change
const LEAN_RATE_GAIN := 3.0      # per second: how briskly the rider rolls the bike towards the lean they want
const LEAN_RATE_MAX := 1.0       # rad/s: the quickest they roll it in or out of a lean
const LEAN_CATCH := 2.0          # rad/s^2: how hard they reckon they can stop a roll, so they ease off in time
const STEER_CATCH := 30.0        # rad of bar per rad/s of roll, times speed squared: steering into a fall to catch it
## The most of the tyres' grip the rider uses for a steady lean, keeping the rest in hand.
const GRIP_IN_HAND := 0.8
## Riding realism below this gets no helping push towards the lean: the bars balance the bike.
const BALANCE_FROM := 0.35
const BALANCE_RATE_GAIN := 5.5   # per second: how briskly that push rolls the bike towards the lean asked for
const BALANCE_RATE_MAX := 1.5    # rad/s: no quicker than this, so the steering keeps up
const BALANCE_CATCH := 3.0       # rad/s^2: easing off the roll in time to arrive
const HANG_OFF := 0.12           # m: how far the rider moves their body to the inside, full lean asked for
const CRASH_LEAN := deg_to_rad(78.0)
const CRASH_PITCH := deg_to_rad(72.0)
const AUTO_RESPAWN_TIME := 3.5
const START_TIME := 0.7           # seconds on the starter motor before it fires
const WHEELIE_PITCH := deg_to_rad(28.0)   # where the rider tries to hold a wheelie (weight back: higher)
const STOPPIE_PITCH := deg_to_rad(14.0)   # and a stoppie, nose down
const AIR_REV_PITCH := 7.0        # pitch acceleration (rad/s^2) from blipping the rear wheel in the air
const SKID_SLIP := 0.2            # tyre slip above which it screeches and marks the road
const BUMP_HEIGHT := {"tarmac": 0.006, "concrete": 0.004, "dirt": 0.035, "grass": 0.025, "gravel": 0.03, "sand": 0.02, "snow": 0.012}
static var _bumps: FastNoiseLite
## How much past the grip that's left for braking (normalised slip) a rider with no help lets the
## front go before they'd ease off: with full care (Riding realism 0.5 and up) none at all.
const CARELESS_SLIP := 0.9
const PADDLE_SPEED := 1.1         # walking pace when the rider paddles backwards with their feet
const PADDLE_HOLD := 0.45         # hold the front brake this long at a standstill to start paddling back
const BURNOUT_SPEED := 2.5        # below this, front brake plus throttle lights up the back tyre
const BEAM_FOG := 3               # the headlight switch's last stop on a bike with fog lights
const DONUT_RATE := 2.2           # rad/s: how fast a full-lock burnout swings the back round the front wheel
## Gear 0 is neutral. It sits between first and second, as on a real bike: at a walking pace or
## slower one click finds it (up from first, down from second); riding, a full click goes
## straight between first and second.
const NEUTRAL := 0
const NEUTRAL_FIND_SPEED := 2.0
## In neutral the engine spins only itself: it makes this share of its torque to do it (fuel, heat).
const FREE_REV_LOAD := 0.12

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
## Direct bars: the steer input is the rider's push on the handlebars (push the right grip to lean
## right) instead of a lean the virtual rider steers for. The front end's own geometry does the rest.
var direct_bars := false
## Records the ride for the telemetry overlay and the dyno desk; only the local player's bike has one.
var telemetry: RideTelemetry
## The tyres', brakes' and engine's temperatures and what they do to the bike (see BikeHeat).
var heat: BikeHeat
## The power the engine is making right now, kW (it heats the engine).
var engine_kw := 0.0
var controls_enabled := true
var engine_on := true      # a parked bike you get on starts with it off; tests ride with it running
var fuel_litres := 15.0    # petrol left in the tank
var fuel_used := 0.0       # litres burnt since the last time someone read and cleared it
var effects: BikeEffects

# Simulation state, read by the HUD, camera, audio and network.
var gear := 1               # 0 is neutral (NEUTRAL), then 1 .. build.gear_count()
var rpm := 1000.0
var steer := 0.0            # radians, + bars turned right
var steer_vel := 0.0        # how fast the bars are turning, rad/s
var bar_torque := 0.0       # Nm the rider is putting through the bars, + towards turning them right
## The rider has let go of the bars: nothing but the front end's own geometry steers it.
var hands_off := false
## A push on the bars from outside the virtual rider (N m, + towards turning them right): tests,
## and a hand that wants to try counter-steering for itself.
var push_bars := 0.0
var trail_now := 0.1        # the trail as it is right now, with the fork dived, the bars turned and the bike leaned, m
var trail_seen := 0.1       # ... smoothed over a few hundredths of a second, as the front's feel follows it
var rake_now := 0.4         # the rake against the road right now, rad: less with the fork dived and the back up
var dive := 0.0             # how far the suspension has pitched the bike nose down from level, rad
var trail_springs := 0.1    # the trail with the bike pitched on its springs as it is now (upright, bars straight), m
var wobble := 0.0           # how far the bars are shaking either way about where they're pointing, rad
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
## What's gone wrong with it out on an adventure (Shed's bikes[id]["faults"], see Roadside):
## a snapped chain drives nothing, a blown fuse kills the lights or the ignition, a snapped
## lever leaves a feeble front brake or slow, crunching shifts.
var faults := {}
## Wheeled along on foot (Roadside): no engine, the throttle walks it at up to Roadside.PUSH_SPEED.
var pushing := false
## On a tow strap: the point on the towing bike the strap's tied to (local), else INF.
var tow_anchor := Vector3.INF
var horn_audio: HornAudio
var _stopped_brake := 0.0  # how long the front brake has been held at a standstill
var _throttle_eff := 0.0   # the throttle as the rider's wrist actually turns it (smoothed with realism up)
var _fog: Array = []
var _steer_axis := Vector3.UP       # the steering axis, bike space (raked back)
var _steer_pivot := Vector3.ZERO    # a point on it, bike space
var _offset_arm := Vector3.ZERO     # from the axis out to the front axle, square to it, bike space
var _steer_aim := 0.0               # where the rider is aiming the bars, rad
var _steer_slow := 0.0              # the bars' angle smoothed, to tell a shake from a steer
var _lean_i := 0.0                  # the rider's memory of a lean that keeps falling short (rad s)
var _hang := 0.0                    # how far the rider is hanging off, m (+ to the right)
var _rate_slow := 0.0               # the lean rate smoothed over half a second
var _trim := 0.0                    # the steady push the rider's arms have settled into, N m
var _direct_hold := 0.0              # Direct bars: the lean the rider let go of the bars at, rad
var _prev_w := Vector3.ZERO          # the frame's spin and velocity last tick, for its accelerations
var _prev_v := Vector3.INF
var _seen := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])   # the lean and lean rate as the rider feels them (two stages each)
## The rider's riding skills (see Progress.rider_skills): balance, throttle_control, airtime, quick_reset.
var skills := {}
## Works out riding XP as the bike is ridden; only the local player's bike has one.
var ride_xp: RideXP


func setup(new_build: BikeBuild, paint := Color(0.78, 0.09, 0.08)) -> void:
	add_to_group("ridden_bike")   # shed TVs follow whoever is out riding
	build = new_build
	mass = build.total_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Where the parts sit moves the centre of mass (see BikeBuild._compute_mass_spread).
	_base_com = Vector3(0.0, build.com_height - build.rear_radius, 0.06 + build.com_offset.z)
	center_of_mass = _base_com
	# Rough rider-plus-bike inertia (pitch, yaw, roll), plus the spread of the parts on it.
	var m := build.total_mass
	var wb := build.wheelbase
	var rough := Vector3(m * wb * wb * 0.16, m * wb * wb * 0.13, m * 0.11)
	inertia = (rough + build.inertia_add).max(rough * 0.6)
	# The steering axis, raked back through the steering head, and the front axle the fork's
	# offset ahead of it. A telescopic fork's axle slides up its legs, parallel to the axis, so
	# the offset stays put as it compresses (see _wheel_forces).
	var rake := deg_to_rad(build.rake_deg)
	_steer_axis = Vector3(0.0, cos(rake), sin(rake))
	var ahead := Vector3(0.0, sin(rake), -cos(rake))
	_offset_arm = ahead * build.fork_offset
	_steer_pivot = Vector3(0.0, 0.0, -wb * 0.5) - _offset_arm
	trail_now = build.trail
	trail_seen = build.trail
	trail_springs = build.trail
	rake_now = rake
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	# Air drag and rolling resistance are worked out properly (_apply_aero, _wheel_forces), so
	# the body must not also get the physics engine's default damping on top. Left combined,
	# the project default (0.1 a second) pulls on the bike like a second, far bigger, drag: at
	# 130 km/h it costs a 50 hp bike about 15 hp, and it's why bikes ran out of puff in the
	# middle gears.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
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
	wheels[0].merge({"prog": build.front_progression, "preload": build.front_preload, "knee": build.front_knee}, true)
	wheels[1].merge({"prog": build.rear_progression, "preload": build.rear_preload, "knee": build.rear_knee}, true)
	gear = 1
	rpm = build.idle_rpm
	# Starts warmed through, as a bike that's been ridden; the game cools it to the shed's
	# temperature (or what's left of its last ride) when someone gets on (see BikeHeat.resume).
	heat = BikeHeat.new()
	heat.setup(build)

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
	model.own_rider = true   # your own: the first-person eye leaves your helmet and torso out
	model.rider_color = rider_color
	model.rider_gear = rider_gear
	model.baked = true   # ridden, not worked on: far fewer draw calls (see BikeModel._bake_static)
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
		# The whole push of the road on the tyre (load and grip, world space), the side force on
		# its own, and the way the tyre is rolling: the front's steering works out its torque from them.
		"force": Vector3.ZERO, "f_lat": Vector3.ZERO, "long_dir": Vector3.FORWARD,
		# The suspension: the axle fully extended (bike space), the tyre's grip forces as shares of
		# its load last step (they push the wheel up or down its travel too), the spring and
		# damper's push along the travel (N), and whether it's on the bump stop.
		"axle": Vector3(0.0, mount.y - travel, mount.z), "rx": 0.0, "ry": 0.0, "f_susp": 0.0, "bottomed": false,
		"prog": 0.0, "preload": 0.0, "knee": 1.0,
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
	bar_torque = 0.0
	wobble = 0.0
	_steer_aim = 0.0
	_steer_slow = 0.0
	_prev_w = Vector3.ZERO
	_prev_v = Vector3.INF
	_trim = 0.0
	_direct_hold = 0.0
	_lean_i = 0.0
	_hang = 0.0
	_seen = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	gear = 1
	rpm = build.idle_rpm
	for w in wheels:
		w["omega"] = 0.0
		w["compression"] = 0.0
		w["sy"] = 0.0
		w["rx"] = 0.0
		w["ry"] = 0.0
		w.erase("road_h")
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
	if pushing:
		return "You're pushing it: get on it first ({interact} to stop)."
	if str(faults.get("fuse", "")) == "ignition":
		return "Not even a click, and the dash is dark: a blown fuse. Get off and swap it (under the seat)."
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


## The world's origin moved by `d` (see AdventureWorld): the bike jumps by -d with its speed,
## lean and spin exactly as they were, and so does its rider if they're off it.
func shift_origin(d: Vector3) -> void:
	var t := global_transform
	t.origin -= d
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	for w in wheels:
		if w.has("contact_pos"):
			w["contact_pos"] = (w["contact_pos"] as Vector3) - d
	if is_instance_valid(_ragdoll):
		_ragdoll.global_position -= d


func respawn() -> void:
	var fwd := -global_transform.basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	place(global_position + Vector3.UP * 0.3, heading)


func _physics_process(delta: float) -> void:
	var pt := Perf.t0()
	_physics_process_body(delta)
	Perf.add("bike_physics", pt)


func _physics_process_body(delta: float) -> void:
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
			rpm = idle_now() * 1.3
			engine_changed.emit(true, "")

	if horn_audio:
		horn_audio.pressed = horn and controls_enabled and not is_crashed
	if engine_on and str(faults.get("fuse", "")) == "ignition":
		stop_engine("The engine cut out and the dash went dark: a blown fuse.")
	if str(faults.get("fuse", "")) == "lights":
		beam = 0   # the lights' fuse has gone: the switch does nothing
	# Every lamp, lens and the clocks run off the ignition: a bike that isn't running is dark.
	var fog_on := engine_on and beam >= BEAM_FOG
	for l in _fog:
		l.visible = fog_on
	if model:
		model.set_lights(engine_on, beam > 0, fog_on)
	if effects:
		effects.beam_mode = beam

	if heat:
		heat.step(self, delta)
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
	# Hanging off: riding, the rider moves their body to the inside of the turn they're asking
	# for, which carries the centre of mass over so the bike itself needs a little less lean.
	var hang_to := lean_input * HANG_OFF * clampf((absf(speed) - 3.0) / 5.0, 0.0, 1.0) if controls_enabled else 0.0
	_hang = move_toward(_hang, hang_to, delta * 0.4)
	center_of_mass = _base_com + Vector3(_hang * BikeBuild.RIDER_MASS / mass, 0.0, -shift)

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
	if str(faults.get("lever", "")) == "brake":
		front_grip *= 0.15   # a stub of a lever: barely any front brake
	# Cold pads bite a little less, overcooked ones fade (see BikeHeat).
	wheels[0]["brake_torque"] = front_grip * build.front_brake_torque * _bite(0)
	wheels[1]["brake_torque"] = 0.0 if burnout > 0.0 else rear_grip * build.rear_brake_torque * _bite(1)
	for w in wheels:
		_wheel_forces(w, delta, space)
	_measure_geometry(delta)
	surface =wheels[1]["surface"] if wheels[1]["contact"] else wheels[0]["surface"]
	_apply_wheel_gyro()
	_apply_aero()
	_apply_rider_balance()
	_apply_feet()
	_apply_donut(delta)
	_check_crash()

	if model:
		model.update_pose(self)
		# Coming to rest the rider puts their left foot down (not crashed, airborne or in a burnout).
		model.update_foot(speed, delta, not is_crashed and burnout <= 0.0 and (wheels[0]["contact"] or wheels[1]["contact"]))
		if heat:
			# A tyre going flat squashes out under the rim as it loses its air (see Puncture).
			model.set_flat("front", heat.flat(0))
			model.set_flat("rear", heat.flat(1))
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


## How the suspension has pitched the bike and so changed its steering geometry: the fork diving
## under braking (or the back squatting under power) tips the steering axis up, which takes rake
## and trail off and quickens the steering; the back sinking or the front rising puts them back on.
func _measure_geometry(delta: float) -> void:
	var rake := deg_to_rad(build.rake_deg)
	var f: Dictionary = wheels[0]
	# How far each axle has risen into the bike from fully extended: the bike's pitch on its springs.
	var rise_f := float(f["compression"]) * build.fork_path.y
	var rise_r := build.rear_axle_at(float(wheels[1]["compression"])).y - build.rear_axle_at(0.0).y
	dive = atan2(rise_f - rise_r, build.wheelbase)
	rake_now = rake - dive
	# The trail that leaves (bike upright, bars straight). A linked fork's axle also moves ahead of
	# the steering axis as it compresses, which takes off a little more.
	var offset := build.fork_offset + float(f["compression"]) * build.fork_path.dot(Vector3(0.0, sin(rake), -cos(rake)))
	trail_springs = (build.front_radius * sin(rake_now) - offset) / cos(rake_now)
	trail_seen = lerpf(trail_seen, trail_now, 1.0 - exp(-delta / 0.04))


## The fork's and shock's travel used, 0 (fully extended) .. 1 (bottomed).
func travel_used(i: int) -> float:
	return clampf(float(wheels[i]["compression"]) / maxf(float(wheels[i]["travel"]), 0.01), 0.0, 1.0)


func _target_lean() -> float:
	var speed_factor := clampf((absf(speed) - 1.0) / 8.0, 0.15, 1.0)
	var want := signf(lean_input) * lean_for_input(absf(lean_input)) * speed_factor
	# That's the lean of the line from the tyres to the centre of mass, which sets the turn; the
	# bike itself leans a little further, as the contact patch rolls in round the tyre's crown.
	var rc := _crown()
	var arm := maxf(build.com_height - rc, 0.2)
	return want + asin(clampf(rc * sin(want) / arm, -1.0, 1.0))


## The lean asked for (of the line from the tyres to the centre of mass, rad) by `x` (0..1) of
## the steer input, at speed. Riding on the road nobody leans much past ROAD_LEAN: most of the
## input's range (up to ROAD_INPUT) covers ordinary road riding, and only the last of it goes on
## to what the tyres will hold (with a margin in hand), the way a racer leans.
func lean_for_input(x: float) -> float:
	var top := _grip_lean()
	var road := minf(_balance_lean(ROAD_LEAN), top * 0.85)
	x = clampf(x, 0.0, 1.0)
	if x <= ROAD_INPUT:
		return road * x / ROAD_INPUT
	# Past it, on the same slope at first, curving round to the most the tyres hold at full input.
	var t := (x - ROAD_INPUT) / (1.0 - ROAD_INPUT)
	var s := road / ROAD_INPUT * (1.0 - ROAD_INPUT)
	return minf(road + s * t + (top - road - s) * t * t, top)


## The most lean (of the line from the tyres to the centre of mass) the tyres' grip on the road
## under them holds in a steady turn, less a margin a rider keeps in hand, or the bike's ground
## clearance allows.
func _grip_lean() -> float:
	var surf := str(wheels[1]["surface"]) if not wheels.is_empty() else "tarmac"
	var wet := Weather.wetness()
	var mu := minf(surface_grip(build, true, surf, wet), surface_grip(build, false, surf, wet)) * Weather.grip_mult(surf)
	# With Riding realism up, the rider knows cold (or overcooked) tyres hold less and leans less on
	# them; at 0 they lean as far as warm tyres would hold, and find out.
	if heat:
		mu *= lerpf(1.0, minf(heat.tyre_grip(0, surf), heat.tyre_grip(1, surf)), clampf(assist * 2.0, 0.0, 1.0))
	# And no further than the bike leans before it grounds out.
	return minf(minf(atan(mu * GRIP_IN_HAND), MAX_LEAN), _balance_lean(build.lean_clearance))


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


## The front end turns about its raked steering axis, a real part of the bike with its own
## weight to swing: the road's push on the tyre (the trail turns it into a lean and lines it up
## with where it's rolling), the spinning wheel (it steers into a fall), the head bearings, any
## steering damper and the rider's hands all act on it. The rider steers by pushing on the bars:
## they aim the bars where the lean they want needs them (counter-steering to start a lean, the
## steady-turn angle to hold it, steering into a fall to catch it) and their arms hold the bars on
## that aim, firmly enough to point a front that pulls back hard, and give a little. At walking
## pace, feet down, they just point the bars.
func _update_steering(delta: float) -> void:
	var v := absf(speed)
	var before := steer
	var target := _target_lean()
	# The rake as it is now, the fork dived or not (see _measure_geometry).
	var rake := rake_now
	# The rider feels the lean through the seat and their inner ear, not instantly: a shake at the
	# bars is too quick for them to steer against (two smoothing stages of RIDER_FEEL seconds).
	var k := 1.0 - exp(-delta / RIDER_FEEL)
	_seen[0] = lerpf(_seen[0], lean_angle, k)
	_seen[1] = lerpf(_seen[1], _seen[0], k)
	_seen[2] = lerpf(_seen[2], lean_rate, k)
	_seen[3] = lerpf(_seen[3], _seen[2], k)
	var cmd: float
	if direct_bars:
		# Direct bars: no lean to aim for. The aim is only used feet down, pointing the bars.
		cmd = lean_input * _max_steer()
		_lean_i = 0.0
	elif v < 2.0:
		# Feet down at walking pace: the bars just point where the rider steers them.
		cmd = lean_input * _max_steer()
		_lean_i = 0.0
	else:
		# The bars for a steady turn at this lean: the turn the front wheel makes on the road, seen
		# through the raked axis of a leaned bike.
		var turn := atan(build.wheelbase * G * tan(_balance_lean(_seen[1])) / (v * v))
		var steer_eq := atan(tan(turn) * cos(_seen[1]) / cos(rake))
		var gain := clampf(8.0 / v, 0.25, 2.5)
		var err := target - _seen[1]
		# They trim out a lean that's held a little short, not one they're still getting into.
		if absf(err) < 0.12:
			_lean_i = clampf(_lean_i + err * delta, -0.25, 0.25)
		else:
			_lean_i = move_toward(_lean_i, 0.0, delta * 0.5)
		# They roll the bike towards the lean they want at a pace they can stop it from: briskly
		# while it's a long way off, easing off in time to arrive without overshooting. A front
		# with long trail fights back harder, so they tip it in more slowly (a short-trail front
		# is twitchy).
		var push := clampf(pow(0.09 / maxf(build.trail * cos(rake), 0.02), 2.0), 0.5, 1.3)
		var r_want := clampf(err * LEAN_RATE_GAIN, -LEAN_RATE_MAX, LEAN_RATE_MAX)
		var stop := sqrt(2.0 * LEAN_CATCH * absf(err))
		r_want = clampf(r_want, -stop, stop) * push
		# Then they steer into the lean as fast as it's going faster than that (out of it to speed
		# it up): the faster the bike, the less bar it takes.
		var catch := clampf(STEER_CATCH / (v * v), 0.004, 0.15)
		cmd = steer_eq + catch * (_seen[3] - r_want) - push * gain * 0.25 * _lean_i
	cmd = clampf(cmd, -_max_steer(), _max_steer())
	var aim_was := _steer_aim
	_steer_aim = move_toward(_steer_aim, cmd, build.steer_rate * delta)
	var aim_rate := (_steer_aim - aim_was) / delta
	var riding := clampf((v - 2.0) / 2.5, 0.0, 1.0)   # 0 feet down .. 1 riding

	var self_t := _front_self_torque()
	self_t += _front_carried_torque(delta)
	var hands := not hands_off
	var i_s := build.steer_inertia + (ARM_INERTIA if hands else 0.0)
	# The rider's arms soak up the bars swinging, more firmly at town speeds where they're working
	# the bars hard, more loosely at speed, where the bike steadies itself.
	var arm_c := lerpf(ARM_DAMPING_SLOW, ARM_DAMPING, clampf((v - 10.0) / 15.0, 0.0, 1.0))
	var c := HEAD_DAMPING + build.damper_damping + (arm_c if hands else 0.0)
	# A friction damper holds the bars until they're pushed past its grip.
	c += build.damper_friction / maxf(absf(steer_vel), 0.08)
	var k_s := 0.0   # how stiffly the arms hold the bars on their aim, N m per rad (worked out implicitly)
	bar_torque = 0.0
	if hands:
		var lever := float(build.part("handlebars").get("width", 720.0)) / 720.0
		var hold := lerpf(ARM_HOLD_SLOW, ARM_HOLD, riding) * lever
		var most := MAX_BAR_TORQUE * lever
		if direct_bars:
			# The input is the push itself: the right grip forward (steer right) turns the bars
			# left, which leans the bike right, and the trail then swings the front into the lean.
			# Feet down the hands just point the bars.
			var push := -lean_input * _direct_push(v) * lever
			# Not pushing, their hands still steer a little into a fall they feel, as anyone's do
			# without thinking: the bike holds the lean it's at rather than tipping further in.
			# The lean they let go at is the one they keep.
			var easy := 1.0 - minf(absf(lean_input), 1.0)
			_direct_hold = lerpf(_direct_hold, _seen[1], 1.0 - exp(-absf(lean_input) * delta / 0.05)) if riding > 0.0 else lean_angle
			var catch := _direct_push(v) / DIRECT_BAR_TORQUE * clampf(DIRECT_PUSH_SPEED / maxf(v, 1.0), 0.3, 1.5) * lever
			push += easy * catch * (DIRECT_CATCH * _seen[3] + DIRECT_KEEP * (_seen[1] - _direct_hold))
			# However they push, their hands keep a light hold on the bars and soak up a quick
			# shake about where they're steering.
			var k_hand := (DIRECT_HAND_HOLD + DIRECT_HAND_FRONT * _front_stiffness(v)) * riding
			push += k_hand * (_steer_slow - steer)
			k_s = k_hand * riding
			bar_torque = clampf(lerpf(hold * (_steer_aim - steer), push, riding), -most, most)
		else:
			# The arms hold the bars on their aim as firmly as the front pulls (half its stiffness
			# on top of their own), and slowly put in whatever steady push it takes to keep them
			# right there. They don't push back against what they feel the front doing: done that
			# late, it would feed a shake rather than calm it.
			var k_arm := hold + 0.5 * _front_stiffness(v) * riding
			_trim = clampf(_trim + k_arm * (_steer_aim - steer) * delta / ARM_TRIM * riding, -most, most) if riding > 0.0 else 0.0
			var raw := k_arm * (_steer_aim - steer) + _trim + arm_c * aim_rate
			# Near the most they can push their arms give gradually rather than all at once, so
			# a front pulling hard doesn't flap the bars to and fro against a hard stop.
			var th := tanh(raw / most)
			k_s = k_arm * (1.0 - th * th)
			bar_torque = most * th
	bar_torque += push_bars
	# Stepped implicitly in the damping and the arms' hold, so stiff arms and a firm damper stay
	# steady at the physics rate.
	var vel := (steer_vel + delta * (self_t + bar_torque) / i_s) / (1.0 + delta * c / i_s + delta * delta * k_s / i_s)
	var dyn := steer + vel * delta
	if absf(dyn) > STEER_LOCK:
		dyn = clampf(dyn, -STEER_LOCK, STEER_LOCK)
	steer = lerpf(_steer_aim, dyn, riding) if hands else dyn
	var vel_was := steer_vel
	steer_vel = (steer - before) / delta
	# The road's push on the front tyre went to the whole bike; what swung the front end round
	# its axis didn't turn the rest of it.
	apply_torque(global_transform.basis * _steer_axis * (i_s * (steer_vel - vel_was) / delta * riding))
	# A shake is the bars moving quickly about where they're pointing on the whole.
	_steer_slow = lerpf(_steer_slow, steer, 1.0 - exp(-delta / 0.08))
	wobble = maxf(absf(steer - _steer_slow), wobble * exp(-delta / 0.3))


## The front end rides on the frame: when the frame swings or is shoved sideways, the front's
## own weight out ahead of the axis (on the fork offset) and its inertia about the axis lag
## behind, and gravity pulls that offset weight down into a lean. N m, + turning the bars right.
func _front_carried_torque(delta: float) -> float:
	var w_now := angular_velocity
	var v_now := linear_velocity
	if _prev_v == Vector3.INF:
		_prev_w = w_now
		_prev_v = v_now
	var w_dot := (w_now - _prev_w) / delta
	var a_cm := (v_now - _prev_v) / delta
	_prev_w = w_now
	_prev_v = v_now
	var b := global_transform.basis
	var axis := b * _steer_axis
	var r_piv := b * (_steer_pivot - center_of_mass)
	var a_piv := a_cm + w_dot.cross(r_piv) + w_now.cross(w_now.cross(r_piv))
	var r := b * (Basis(_steer_axis, -steer) * _offset_arm)
	return build.steer_mass * r.cross(a_piv + Vector3.UP * G).dot(axis) + build.steer_inertia * w_dot.dot(axis)


## What the road and the spinning front wheel put on the bars, N m, + turning them right: the
## ground's whole push on the tyre (load and grip) about the steering axis, the side force from
## its slip angle (not its camber thrust) acting a little behind the contact patch while it grips
## (pneumatic trail), and the wheel's spin fighting being tipped over (it steers the front into a
## fall). Also measures the trail as it is right now.
func _front_self_torque() -> float:
	var f: Dictionary = wheels[0]
	var b := global_transform.basis
	var t := _front_gyro().dot(b * _steer_axis)
	if not f["contact"] or not f.has("contact_local"):
		trail_now = build.trail
		return t
	# All in the bike's own space, where the steering axis is fixed.
	var axis := _steer_axis
	var pivot := _steer_pivot
	var at: Vector3 = f["contact_local"]
	var long_dir: Vector3 = f["long_dir"]
	var tq := (at - pivot).cross(f["force"])
	var pt := PNEUMATIC_TRAIL * clampf(1.0 - absf(float(f["sy"])), 0.0, 1.0) * float(f.get("slip_share", 1.0))
	tq += (-long_dir * pt).cross(f["f_lat"])
	# Where the steering axis meets the road, against the contact patch.
	var n: Vector3 = f["normal_local"]
	var along := axis.dot(n)
	if absf(along) > 0.2:
		var meet := pivot + axis * ((at - pivot).dot(n) / along)
		trail_now = (meet - at).dot(long_dir)
	return t - tq.dot(axis)


## The torque the front wheel's spin needs to be turned with the bike and the bars (world): it
## comes from the fork, which takes it from the frame, all but the part along the steering axis,
## which turns the bars.
func _front_gyro() -> Vector3:
	var b := global_transform.basis
	var axis := b * _steer_axis
	var h := -b.x.rotated(axis, -steer) * build.front_inertia * float(wheels[0]["omega"])
	return (angular_velocity - axis * steer_vel).cross(h)


## The spinning wheels fight being tipped: leaning in yaws the bike a touch into the turn, and
## turning stands it up a little, more the faster they spin. The bike's rigid body doesn't know
## its wheels spin, so the frame gets their reaction here (the front's along the steering axis
## turns the bars instead, see _front_self_torque).
func _apply_wheel_gyro() -> void:
	var b := global_transform.basis
	var axis := b * _steer_axis
	var front := _front_gyro()
	var h_rear := -b.x * build.rear_inertia * float(wheels[1]["omega"])
	apply_torque(-(front - axis * front.dot(axis)) - angular_velocity.cross(h_rear))


## How hard the front pulls back towards where it would point on its own, N m per radian the
## bars are turned from there: the front tyre's cornering stiffness on the trail, the rider's
## feel for the bars. Grip builds in as the wheel rolls. `live` takes the geometry as the springs
## have it now (diving on the brakes, the shorter trail and steeper head lighten it; squatting
## under power, the longer trail firms it up), otherwise as the bike stands.
func _front_stiffness(v: float, live := true) -> float:
	var tp: Dictionary = build.tyre_front
	var mu := float(build.grip_front.get("tarmac", 1.0))
	var fz := build.total_mass * G * 0.5
	var trail := trail_springs if live else build.trail
	var rake := rake_now if live else deg_to_rad(build.rake_deg)
	var c_alpha := mu * fz * TyreModel.stiffness_at_zero(tp) / tan(float(tp["alpha_peak"]))
	return maxf(trail, 0.0) * cos(rake) * c_alpha * clampf(v / 6.0, 0.15, 1.0)


## Direct bars: the push a full input puts on 720 mm bars at speed v, N m. A faster bike takes a
## firmer push to tip in at the same pace, so the rider pushes harder as the speed rises.
## A front that turns easily (light, on soft knobblies) takes less of a push to turn the same, a
## heavier bike more.
func _direct_push(v: float) -> float:
	var front := clampf(_front_stiffness(DIRECT_PUSH_SPEED, false) / DIRECT_FRONT_REF * build.total_mass / DIRECT_MASS_REF, 0.35, 1.4)
	return DIRECT_BAR_TORQUE * front * clampf(pow(maxf(v, 0.0) / DIRECT_PUSH_SPEED, 0.75), DIRECT_PUSH_LEAST, DIRECT_PUSH_MOST)


## A shove on the bars (N m s, + towards turning them right), as a hand or a pothole gives them.
func kick_bars(impulse: float) -> void:
	steer_vel += impulse / maxf(build.steer_inertia + (0.0 if hands_off else ARM_INERTIA), 0.05)


func _update_engine(delta: float) -> void:
	var rear: Dictionary = wheels[1]
	# A snapped chain: the engine spins free with nothing to drive, as in neutral.
	var neutral: bool = gear == NEUTRAL or bool(faults.get("chain_snap", false))
	var ratio := build.overall_ratio(maxi(gear, 1))
	var wheel_rpm: float = rear["omega"] * ratio * 60.0 / TAU
	var idle_rpm := idle_now()
	var clutch_rpm := idle_rpm + 900.0
	var engaged := wheel_rpm >= clutch_rpm and not neutral
	var shifting := _shift_timer > 0.0
	_shift_timer -= delta

	if neutral:
		if engine_on:
			# Nothing but the engine's own flywheel to spin: it revs freely, quick to rise on the
			# throttle and slower to fall back to idle, and bounces off the limiter.
			var free := lerpf(idle_rpm, build.redline * 1.01, pow(_throttle_eff, 0.8))
			rpm = lerpf(rpm, free, 1.0 - exp(-(6.0 if free > rpm else 2.5) * delta))
			if rpm >= build.redline:
				rpm -= build.redline * 0.04
	elif shifting and engine_on:
		# The clutch is in: the revs fall (or blip up) to the new gear's speed instead of jumping.
		var f := clampf(1.0 - _shift_timer / maxf(build.shift_time, 0.01), 0.0, 1.0)
		rpm = lerpf(_shift_from_rpm, maxf(wheel_rpm, idle_rpm), f * f)
	elif engaged:
		rpm = wheel_rpm
	else:
		# Slipping clutch: the engine holds launch revs while the wheel catches up.
		var launch := lerpf(idle_rpm, build.peak_torque_rpm * 0.75, _throttle_eff)
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
	# The ECU's traction control, at the level set on the dyno desk (off: the rider alone).
	var tc := maxf(minf(1.0, assist + 0.15 * float(skills.get("throttle_control", 0))), build.aid_strength("traction"))
	var tc_from := lerpf(0.1, 0.06, clampf(build.aid_strength("traction"), 0.0, 1.0)) if build.aid_on("traction") else 0.12
	if tc > 0.05 and spin_ratio > tc_from and rear["contact"] and burnout <= 0.0:
		tc_target = clampf(1.0 - (spin_ratio - tc_from) * 4.0 * tc, 0.15, 1.0)
	# In a wheelie the rider feathers the throttle to hold the front up at the balance angle
	# rather than looping it; more assist, steadier hands.
	if not wheels[0]["contact"] and rear["contact"] and pitch_angle > deg_to_rad(4.0):
		var over := pitch_angle - wheelie_target()
		var rising := angular_velocity.dot(global_transform.basis.x)
		var hands := _steadiness()
		tc_target = minf(tc_target, clampf(1.0 - (over * 8.0 + rising * 1.2) * hands, 0.0, 1.0))
	if build.aid_on("anti_wheelie") and pitch_angle > deg_to_rad(2.0):
		# The ECU's anti-wheelie trims the power to keep the front wheel skimming the road
		# (a gentle level lets it come up further).
		var cap := deg_to_rad(lerpf(20.0, 4.0, minf(build.aid_strength("anti_wheelie"), 1.0)))
		tc_target = minf(tc_target, clampf(1.0 - (pitch_angle - cap) * 12.0, 0.05, 1.0))
	_traction = lerpf(_traction, tc_target, 1.0 - exp(-25.0 * delta))
	var torque := build.engine_torque(rpm) * _throttle_eff * _traction
	if heat:
		torque *= heat.power   # a cold engine is a little down on power, an overheating one more so
	if rpm >= build.redline:
		torque = 0.0  # rev limiter
	var made := maxf(torque, 0.0)
	if engaged:
		# Engine braking when the throttle is closed.
		torque -= (1.0 - _throttle_eff) * build.peak_torque * 0.25 * clampf(rpm / build.redline, 0.0, 1.0)
	if shifting:
		torque = 0.0
		made = 0.0
	if neutral:
		# Nothing to drive: the back wheel just rolls.
		made *= FREE_REV_LOAD
		torque = 0.0
	if not engine_on:
		# Engine off: the bike just rolls. The revs fall away to nothing.
		torque = 0.0
		made = 0.0
		engine_kw = 0.0
		if _starting <= 0.0:
			rpm = wheel_rpm if engaged else move_toward(rpm, 0.0, 3000.0 * delta)
	else:
		engine_kw = made * rpm * TAU / 60.0 / 1000.0
		var burnt := build.fuel_rate(engine_kw, rpm) / 3600.0 * delta
		fuel_litres -= burnt
		fuel_used += burnt
		if fuel_litres <= 0.0:
			fuel_litres = 0.0
			stop_engine("Out of petrol! Push it home or bring it a can.")
	rear["drive_torque"] = torque * ratio * build.drivetrain_efficiency
	rpm = clampf(rpm, idle_rpm * 0.9 if engine_on else 0.0, build.redline * 1.02)

	_since_shift += delta
	if auto_shift and neutral:
		# The automatic box drops into a gear that suits the road speed as soon as the rider opens
		# the throttle (first from a standstill); it never picks neutral by itself.
		if engine_on and throttle > 0.05:
			_select(gear_for_speed())
	elif auto_shift and not shifting and _since_shift > 0.6:
		# Shift on road speed, not engine revs, so wheelspin doesn't confuse the gearbox.
		var road_rpm := absf(speed) / build.rear_radius * ratio * 60.0 / TAU
		if road_rpm > build.redline * 0.9 and gear < build.gear_count():
			_select(gear + 1)
		elif gear > 1:
			var lower_rpm := road_rpm * build.overall_ratio(gear - 1) / ratio
			if road_rpm < build.peak_torque_rpm * 0.5 and lower_rpm < build.redline * 0.8:
				_select(gear - 1)


## The revs the engine idles at now: higher on the choke while it's cold.
func idle_now() -> float:
	return build.idle_rpm * (heat.idle if heat else 1.0)


## A brake's bite from its heat (1 = full).
func _bite(i: int) -> float:
	return heat.bite[i] if heat else 1.0


## One click up: first to neutral at a walking pace or slower (a half click), otherwise first to
## second, neutral to second, and on up the box.
func shift_up() -> void:
	if gear == 1 and absf(speed) < NEUTRAL_FIND_SPEED:
		_select(NEUTRAL)
	elif gear == NEUTRAL:
		_select(mini(2, build.gear_count()))
	elif gear < build.gear_count():
		_select(gear + 1)


## One click down: second to neutral at a walking pace or slower (a half click), otherwise down
## the box to first, and neutral to first.
func shift_down() -> void:
	if gear == 2 and absf(speed) < NEUTRAL_FIND_SPEED:
		_select(NEUTRAL)
	elif gear == NEUTRAL:
		_select(1)
	elif gear > 1:
		_select(gear - 1)


## Puts the box in gear `g` (0 neutral). Into a gear the clutch is in for a moment while the revs
## meet the new gear; into neutral the drive simply lets go.
func _select(g: int) -> void:
	if g == gear:
		return
	_shift_from_rpm = rpm
	gear = g
	_shift_timer = build.shift_time if g != NEUTRAL else 0.0
	if str(faults.get("lever", "")) == "clutch" and g != NEUTRAL:
		_shift_timer *= 3.5   # no clutch lever: every shift crunches in slowly
	_since_shift = 0.0
	gear_changed.emit(gear)


## The lowest gear that doesn't over-rev the engine at the road speed now (first when stopped).
func gear_for_speed() -> int:
	for g in range(1, build.gear_count() + 1):
		if absf(speed) / build.rear_radius * build.overall_ratio(g) * 60.0 / TAU < build.redline * 0.8:
			return g
	return build.gear_count()


## How the dash and HUD show gear `g`: "N" for neutral, else its number.
static func gear_name(g: int) -> String:
	return "N" if g == NEUTRAL else str(g)


## The wheelie angle the rider aims for: with their weight back, the balance angle (higher the
## further back); otherwise they keep the front wheel near the ground.
func wheelie_target() -> float:
	var t := deg_to_rad(6.0)
	if body_shift <= -0.25:
		t = WHEELIE_PITCH + deg_to_rad(10.0) * clampf((-body_shift - 0.25) / 0.75, 0.0, 1.0)
	if build and build.aid_on("anti_wheelie"):
		t = minf(t, deg_to_rad(lerpf(20.0, 4.0, minf(build.aid_strength("anti_wheelie"), 1.0))))
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
	var lit := engine_on and gear != NEUTRAL and on_ground and front_brake > 0.5 and throttle > 0.35 and absf(speed) < BURNOUT_SPEED \
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
	elif pushing:
		# Wheeling it along on foot: walking pace on the throttle, the brakes to stop.
		var v := linear_velocity.dot(flat)
		var want := Roadside.PUSH_SPEED * clampf(throttle, 0.0, 1.0)
		if throttle > 0.05 or v > want:
			apply_central_force(flat * clampf(want - v, -1.5, 1.5) * mass * 2.0)
	if tow_anchor != Vector3.INF:
		_apply_tow()


## On the tow strap: once it's taut it pulls the bike after the towing one, springy and damped.
func _apply_tow() -> void:
	var d := tow_anchor - global_position
	d.y = 0.0
	var dist := d.length()
	if dist <= Roadside.STRAP or dist > 40.0:
		return
	var dir := d / dist
	var closing := linear_velocity.dot(dir)
	var pull := clampf((dist - Roadside.STRAP) * 1800.0 - closing * 600.0, 0.0, mass * 6.0)
	apply_central_force(dir * pull)


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
	var grip: float = surface_grip(build, false, str(wheels[1]["surface"]), Weather.wetness()) * float(wheels[1]["load"])
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
	# A flat tyre folds under the rim: the wheel rides lower, drags and wallows (see Puncture).
	var flat_now := heat.flat(0 if is_front else 1) if heat else 0.0
	if flat_now > 0.0:
		radius -= heat.squash(0 if is_front else 1, radius - (build.front_rim_radius if is_front else build.rear_rim_radius))
	var roll_k := build.rolling * (1.0 + Puncture.FLAT_DRAG * maxf(flat_now - float(build.flat["front" if is_front else "rear"]), 0.0))
	var crown := minf(float(tp.get("crown", 0.0)), radius * 0.6)
	var travel: float = w["travel"]
	var q_was: float = w["compression"]
	# Where the axle would sit with the suspension fully extended, and the way it moves as the
	# suspension squashes (bike space). The front slides up the fork legs (raked back, so it
	# moves back as well as up), swinging round the steering axis with the bars on the fork's
	# offset; the back swings up round the swingarm pivot, taken straight for this one step.
	var axle0: Vector3
	var path: Vector3
	if is_front:
		var turn := Basis(_steer_axis, -steer)
		axle0 = w["axle"] + turn * _offset_arm - _offset_arm
		path = turn * build.fork_path
	else:
		path = build.rear_path_at(q_was)
		axle0 = build.rear_axle_at(q_was) - path * q_was
	var mount: Vector3 = global_transform * (axle0 + path * travel)
	# Leaned over, a round tyre sits lower than a thin disc would: look a little further.
	var ray_len := travel + radius + crown * 2.0
	var query := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var inertia_w: float = w["inertia"]

	var heading := -b.z
	var axle := b.x
	if is_front:
		# The front wheel turns about the raked steering axis, not straight up: turned, it leans
		# over a little too.
		var axis := b * _steer_axis
		heading = heading.rotated(axis, -steer)
		axle = axle.rotated(axis, -steer)
	var raw_comp := -1.0
	var n := Vector3.UP
	var cos_cam := 1.0
	var hit_surf := "grass"
	var path_w := b * path
	var slide := 1.0   # how far the axle rises from the road per metre along its travel
	if not hit.is_empty():
		n = hit["normal"]
		if hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
			hit_surf = str((hit["collider"] as Object).get_meta("surface"))
		# The contact patch rolls round the tyre's crown as it leans: the wheel centre sits
		# (radius - crown) * cos(camber) + crown above the ground.
		var sin_cam := clampf(axle.dot(n), -0.95, 0.95)
		cos_cam = sqrt(1.0 - sin_cam * sin_cam)
		slide = maxf(path_w.dot(n), 0.2)
		var h_mount: float = (mount - hit["position"]).dot(n)
		var hang := (h_mount - crown - (radius - crown) * cos_cam) / slide
		# The ground isn't a billiard table: ripples, ruts and stones under the tyre work the suspension.
		# The tyre's own spring sits between the road and the suspension, and it wraps round a short
		# ripple: one too quick for it is soaked up by the tyre flexing, not jammed straight into the
		# damper (which would make the tyre skip and the front's grip, and so the bars, twitch).
		var bump_h := road_bump(hit["position"], hit_surf)
		var tau := float(w["bump"]) / TYRE_RATE + TYRE_ENVELOPE / maxf(absf(speed), 1.0)
		bump_h = lerpf(float(w.get("road_h", bump_h)), bump_h, 1.0 - exp(-delta / maxf(tau, 1e-4)))
		w["road_h"] = bump_h
		raw_comp = travel - hang + bump_h

	if raw_comp < 0.0:
		w["contact"] = false
		w["load"] = 0.0
		w["compression"] = move_toward(w["compression"], 0.0, delta * 2.0)
		var omega_air: float = w["omega"] + w["drive_torque"] * delta / inertia_w
		omega_air = move_toward(omega_air, 0.0, w["brake_torque"] * delta / inertia_w)
		w["omega"] = omega_air * 0.999
		w["spin"] = fmod(w["spin"] + w["omega"] * delta, TAU)
		w["slip"] = 0.0
		w["p_slip"] = 0.0
		w["p_roll"] = 0.0
		w["grip_used"] = 0.0
		w["gx"] = 0.0
		w["gy"] = 0.0
		w["kappa"] = 0.0
		w["alpha"] = 0.0
		w["sy"] = 0.0
		w["f_side"] = 0.0
		w["eased"] = false
		w["force"] = Vector3.ZERO
		w["f_lat"] = Vector3.ZERO
		w["f_susp"] = 0.0
		w["bottomed"] = false
		return

	# The spring is preloaded: until the road pushes harder than that, the suspension stays
	# topped out and only the tyre squashes.
	var rate: float = w["spring"]
	var pre_gap := rate * float(w["preload"]) / TYRE_RATE
	var comp := clampf(raw_comp - pre_gap, 0.0, travel)
	var was_touching: bool = w["contact"]
	# How fast the wheel is being pushed up its travel. On the first frame of touchdown the
	# wheel was hanging free, so take the bike's own closing speed instead of the jump in travel.
	var closing := -(linear_velocity + angular_velocity.cross(mount - global_position)).dot(n) / slide
	var comp_vel: float = (comp - q_was) / delta if was_touching else closing
	var raw_vel: float = (raw_comp - float(w.get("raw", raw_comp))) / delta if was_touching else closing
	w["raw"] = raw_comp
	w["compression"] = comp
	# Bump damping resists the wheel coming up, rebound damping resists it going back down. Fast
	# hits blow the compression valving open (sooner on a damper with high-speed valving), as real
	# dampers do, so a big landing or a pothole is soaked up rather than kicked back.
	var damp_force: float
	if comp_vel > 0.0:
		var bump: float = w["bump"]
		var knee: float = w["knee"]
		damp_force = bump * (comp_vel if comp_vel < knee else knee + (comp_vel - knee) * 0.45)
	else:
		damp_force = float(w["rebound"]) * comp_vel
	var f_susp: float
	if raw_comp <= pre_gap:
		f_susp = TYRE_RATE * raw_comp
	else:
		f_susp = BikeBuild.spring_force(rate, comp, travel, float(w["prog"]), float(w["preload"])) + damp_force
	w["bottomed"] = raw_comp - pre_gap > travel
	if w["bottomed"]:
		# Bottomed out: a firm, heavily damped rubber stop that eats the energy it takes, both
		# squashing and coming back off it, so it never kicks the bike back up.
		var over := raw_comp - pre_gap - travel
		f_susp += over * 160000.0 + raw_vel * (9000.0 if raw_vel > 0.0 else 14000.0)
	f_susp = maxf(f_susp, 0.0)
	w["f_susp"] = f_susp
	w["contact"] = true
	w["surface"] = hit_surf

	# Where the crown touches: from the wheel centre, down the wheel's plane to the crown's
	# centre, then straight down onto the road.
	var down := -n - axle * (-n).dot(axle)
	down = down.normalized() if down.length() > 0.01 else -up
	var centre := global_transform * (axle0 + path * comp)
	var contact := centre + down * (radius - crown) - n * crown
	contact -= n * (contact - hit["position"]).dot(n)
	var r_eff := (radius - crown) + crown * cos_cam    # the rolling radius at this camber
	w["r_eff"] = r_eff
	w["contact_pos"] = contact
	w["normal"] = n
	var arm := contact - global_position

	# Tyre frame on the ground plane. lat_dir points to the wheel's left. The tyre rolls along the
	# line where its own plane meets the road (square to its axle), not along its heading laid flat:
	# a steered front wheel on a leaned bike turns much more sharply than its heading suggests.
	var long_dir := n.cross(axle)
	long_dir = long_dir.normalized() if long_dir.length() > 0.1 else (heading - n * heading.dot(n)).normalized()
	var lat_dir := n.cross(long_dir)

	# The tyre's load. The suspension only pushes along its own travel; what the road pushes the
	# wheel with along that line is the load and the tyre's grip forces together (the rest goes
	# into the fork legs or the swingarm). Braking drives a telescopic fork down its raked legs as
	# well as loading it, so it dives more than the weight coming forward alone would make it;
	# leaned into a turn the side force works the springs too. At the back, the chain's pull
	# and a rear brake caliper working against the swingarm move it up or down as well
	# (anti-squat: see BikeBuild.anti_squat_at).
	var push := f_susp
	if not is_front:
		var dt: float = w["drive_torque"]
		var pull := b * build.chain_pull_at(axle0 + path * comp, dt >= 0.0)
		push -= absf(dt) / build.sprocket_r_rear * pull.dot(path_w)
	var along := n.dot(path_w) + clampf(float(w["rx"]), -1.6, 1.6) * long_dir.dot(path_w) \
		+ clampf(float(w["ry"]), -1.6, 1.6) * lat_dir.dot(path_w)
	# The brake's reaction. The rear caliper rides on the swingarm, so braking pulls the arm up
	# and squats the back; a leading-link fork's brake works against its arm, which pivots behind
	# the axle, so braking holds the front up. Both scale with the load itself, so they go in
	# with the travel's share of the load rather than lagging a step behind it.
	if w["brake_torque"] > 0.0 and absf(float(w["omega"])) > 0.5:
		var react := maxf(-clampf(float(w["rx"]), -1.6, 1.6), 0.0) * r_eff * signf(float(w["omega"]))
		if not is_front:
			along += react / build.swing_length
		elif build.fork_link > 0.0:
			along -= react / build.fork_link
	# Where the road's push comes close to square to the travel (hard on the power in a big
	# wheelie) the spring carries little of it and the tyre's own give sets the load; the
	# suspension then jacks right out, so the load is held to twice the spring's.
	var fz := clampf(push / maxf(along, 0.5), 0.0, mass * G * 6.0)
	w["load"] = fz
	apply_force(n * fz, arm)
	var v_contact := linear_velocity + angular_velocity.cross(arm)
	if is_front:
		# Turning the bars swings the contact patch sideways round the steering axis, trail and
		# all: the tyre fights that, which damps a shake.
		v_contact += (b * _steer_axis * -steer_vel).cross(contact - global_transform * _steer_pivot)
	var v_long := v_contact.dot(long_dir)
	var v_lat := v_contact.dot(lat_dir)
	var v_abs := absf(v_long)
	# The tyre's grip on what's under it, for its kind of tread (see TyreGrip), and wet roads after
	# rain grip a little less.
	var mu_surf := surface_grip(build, is_front, hit_surf, Weather.wetness())
	mu_surf *= Weather.grip_mult(hit_surf)
	if heat:
		mu_surf *= heat.tyre_grip(0 if is_front else 1, hit_surf)   # a cold tyre (or a cooked one) grips less
	if flat_now > 0.0:
		# The folded carcass bunches up and lets go once a turn of the wheel: it wallows.
		mu_surf *= 1.0 - 0.18 * flat_now * (0.5 + 0.5 * sin(float(w["spin"]) * 2.0))
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
	# How much of the side force is the tyre being steered across its path, rather than leaned
	# (camber thrust): only that part acts behind the contact patch (pneumatic trail).
	var sy_slip := -tan(clampf(alpha, -TyreModel.MAX_SLIP_ANGLE, TyreModel.MAX_SLIP_ANGLE)) / tan(ap)
	w["slip_share"] = clampf(sy_slip / sy_now, 0.0, 1.0) if absf(sy_now) > 1e-4 else 1.0

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
	# The work of the tyre sliding over the road and flexing as it rolls heats it (see BikeHeat).
	w["p_slip"] = absf(fx * (omega_new * r_eff - v_long)) + absf(fy * v_lat)
	w["p_roll"] = roll_k * fz * v_abs
	fx -= signf(v_long) * roll_k * fz
	if burnout > 0.0 and not is_front:
		# Lit up: the tyre spins free against the road, smoking, while the feet hold the bike.
		fx *= 1.0 - 0.85 * burnout
		# A spinning tyre has next to no side grip, so the back steps out where the rider pushes it.
		fy *= 1.0 - 0.8 * burnout
		slip_ratio = maxf(slip_ratio, burnout)
	w["slip"] = slip_ratio
	w["rx"] = fx / maxf(fz, 1.0)
	# The side force's share works the springs as the tyre's carcass and the wheel's own weight
	# take it up, over a moment rather than at once (taken straight, a tyre near its limit would
	# unload itself the instant it slipped a little more).
	w["ry"] = lerpf(float(w["ry"]), fy / maxf(fz, 1.0), 1.0 - exp(-delta / 0.15))
	w["omega"] = omega_new
	w["spin"] = fmod(w["spin"] + omega_new * delta, TAU)
	var force := long_dir * fx + lat_dir * fy
	w["f_side"] = force.dot(b.x)
	# Kept in the bike's own space: by the time the steering reads them the bike has moved on.
	var to_bike := b.inverse()
	w["force"] = to_bike * (force + n * fz)
	w["f_lat"] = to_bike * (lat_dir * fy)
	w["long_dir"] = to_bike * long_dir
	w["contact_local"] = global_transform.affine_inverse() * contact
	w["normal_local"] = to_bike * n
	apply_force(force, arm)


## The wheel speed at the end of the step: where the wheel's spin change balances the tyre's
## grip on the road, I (w - w0) / dt = -r Fx(w). Fx follows the Magic Formula, so this is solved
## (regula falsi, Illinois) between w0 and rolling speed, where the answer always lies.
## Static so the recovery truck and its trailer (RayWheel) solve their tyres the same way.
static func _solve_spin(omega0: float, v_long: float, vden: float, r: float, kp: float, sy: float, f_peak: float,
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


## The grip (mu) of build `b`'s front or back tyre on surface `surf` (the town's tarmac, dirt
## and grass, the adventure roads' gravel, sand and snow) with the ground `wet` 0..1: the one
## place the grip numbers come from (TyreGrip, data/tyre_grip.json).
static func surface_grip(b: BikeBuild, front: bool, surf: String, wet := 0.0) -> float:
	return b.tyre_grip(front, surf, wet)


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


## The rider's feet balance the bike when crawling, feet down. Riding, the bars do the balancing
## (see _update_steering); only with Riding realism turned well up does a helping hand
## (BALANCE_FROM and up) push the bike towards the lean asked for.
func _apply_rider_balance() -> void:
	var b := global_transform.basis
	var fwd := -b.z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var any_contact: bool = wheels[0]["contact"] or wheels[1]["contact"]
	var strength := clampf((assist - BALANCE_FROM) / (1.0 - BALANCE_FROM), 0.0, 1.0)
	var feet_down := 1.0 - clampf(absf(speed) - 2.0, 0.0, 1.0)
	var err := _target_lean() - lean_angle
	# It rolls the bike towards that lean at a pace the steering can follow (a key slammed down
	# doesn't throw it over faster than the front can catch it), easing in to arrive.
	var r_help := clampf(err * BALANCE_RATE_GAIN, -BALANCE_RATE_MAX, BALANCE_RATE_MAX)
	var stop := sqrt(2.0 * BALANCE_CATCH * absf(err))
	r_help = clampf(r_help, -stop, stop)
	# A helping hand, not a crane: it lets go as the tyres run out of grip rather than hold the
	# bike on a lean they can't carry.
	var used := maxf(float(wheels[0].get("grip_used", 0.0)), float(wheels[1].get("grip_used", 0.0)))
	var tau := 4.0 * (r_help - lean_rate) * mass * strength * clampf((1.05 - used) / 0.25, 0.0, 1.0)
	# Feet down at a crawl they simply hold it up, if it isn't already too far over to hold.
	feet_down *= clampf((deg_to_rad(55.0) - absf(lean_angle)) / deg_to_rad(15.0), 0.0, 1.0)
	tau = lerpf(tau, (22.0 * err - 4.0 * lean_rate) * mass, feet_down)
	if direct_bars:
		# No lean to aim for: the bars do the balancing. Feet down at a crawl the rider holds the
		# bike up. Riding, while they push on the bars their body goes with the bike; let go and
		# it steadies the bike on the lean it's at (a little more with realism turned up).
		var feet := 1.0 - clampf((absf(speed) - 2.0) / 2.5, 0.0, 1.0)
		var going_with := 1.0 - lerpf(DIRECT_BODY_GIVE, 1.0, clampf((absf(speed) - 10.0) / 12.0, 0.0, 1.0)) * minf(absf(lean_input), 1.0)
		tau = (-22.0 * lean_angle * feet - (4.0 * feet + (0.4 + 0.4 * assist) * going_with * (1.0 - feet)) * lean_rate) * mass
		if any_contact and not is_crashed:
			tau -= clampf(DIRECT_BODY_RATE * going_with * lean_rate * mass, -DIRECT_BODY_MAX, DIRECT_BODY_MAX) * (1.0 - feet)
	# The rider's body isn't bolted on: it sways on their hips and soaks up a quick rocking of the
	# bike (a weave), though not the bike leaning into a turn. Hands on or off, at any realism.
	var dt := get_physics_process_delta_time()
	_rate_slow = lerpf(_rate_slow, lean_rate, 1.0 - exp(-dt / 0.5))
	if any_contact and not is_crashed:
		tau -= BODY_SWAY * mass * (lean_rate - _rate_slow)
	if hands_off and push_bars == 0.0 and any_contact and not is_crashed and absf(speed) > 3.0:
		# Riding no-handed the rider keeps it up with their hips, gently: the bike, left to itself,
		# slowly falls into a turn on its round tyres.
		tau += clampf((NO_HANDS_LEAN * err - NO_HANDS_RATE * lean_rate) * mass, -NO_HANDS_MAX, NO_HANDS_MAX)
	var stab := build.aid_strength("stability")
	if stab > 0.0 and any_contact:
		# Stability control calms a tank-slapper or a twitchy slide, as firmly as it's set.
		tau -= lean_rate * mass * 3.0 * stab
		apply_torque(-b.y * angular_velocity.dot(b.y) * mass * 0.8 * stab)
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
