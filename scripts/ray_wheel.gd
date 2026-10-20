class_name RayWheel
extends RefCounted
## One wheel of the recovery truck or its trailer: a ray-cast suspension (spring, bump and
## rebound damping, a rubber bump stop) and the bikes' own tyre model (TyreModel's Magic Formula
## with combined slip, the longitudinal spin solved implicitly as Bike does), on a car tyre: flat
## across its tread, so it has no crown to roll round and next to no camber thrust.
##
## A wheel is a Dictionary (see make()); step() works it for one physics tick and pushes the body.

const G := 9.81
const LONG_SLIP_SPEED := 3.0      # m/s: as Bike, slips are taken against at least these speeds
const LAT_SLIP_SPEED := 2.5
const RELAX_SPEED := 4.0
const ROLLING := 0.013            # rolling resistance of a car tyre
## Grip by surface for the truck's all-terrain tyres (the bikes' road tyres' table, a bit kinder off-road).
const GRIP := {"tarmac": 0.92, "concrete": 0.88, "dirt": 0.7, "gravel": 0.66, "grass": 0.56}


## A car tyre's numbers: a radial road tyre of `width` mm, flat-treaded (no crown) and a little
## stiffer than a bike tyre in the carcass.
static func car_tyre(width := 245.0, stiffness := 1.1) -> Dictionary:
	var p := TyreModel.params_of({"style": "road", "construction": "radial", "width": width, "stiffness": stiffness, "slide": 0.82})
	p["crown"] = 0.0
	p["camber"] = 0.08
	p["relax"] = 0.35
	return p


## A wheel: `mount` is where the top of its travel is in the body's own space.
static func make(mount: Vector3, radius: float, travel: float, spring: float, bump: float, rebound: float,
		inertia: float, tyre: Dictionary) -> Dictionary:
	return {"mount": mount, "radius": radius, "travel": travel, "spring": spring, "bump": bump, "rebound": rebound,
		"inertia": inertia, "tyre": tyre, "steer": 0.0, "drive_torque": 0.0, "brake_torque": 0.0, "omega": 0.0,
		"spin": 0.0, "compression": 0.0, "contact": false, "load": 0.0, "surface": "tarmac", "sy": 0.0, "kappa": 0.0,
		"alpha": 0.0, "slip": 0.0, "grip_used": 0.0, "fx": 0.0, "fy": 0.0, "contact_pos": Vector3.ZERO, "abs": false,
		"raw": 0.0}


## Works wheel `w` on `body` for one tick: finds the ground under it, the spring and damper's
## push, then the tyre's drive, brake and side forces, and spins the wheel by what the road gives
## back. `share` is the body's mass this wheel carries for the crawl-speed caps, `fz0` the tyre's
## nominal load. Wheels with "abs" set ease their brake at the edge of grip.
static func step(body: RigidBody3D, w: Dictionary, delta: float, space: PhysicsDirectSpaceState3D, share: float,
		fz0: float) -> void:
	var b := body.global_basis
	var up := b.y
	var radius: float = w["radius"]
	var travel: float = w["travel"]
	var mount: Vector3 = body.global_transform * (w["mount"] as Vector3)
	var query := PhysicsRayQueryParameters3D.create(mount, mount - up * (travel + radius), 1)
	query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	var inertia_w: float = w["inertia"]
	var raw_comp := -1.0
	var n := Vector3.UP
	var surf := "grass"
	if not hit.is_empty():
		n = hit["normal"]
		if hit["collider"] and (hit["collider"] as Object).has_meta("surface"):
			surf = str((hit["collider"] as Object).get_meta("surface"))
		var along := (mount - (hit["position"] as Vector3)).dot(up)
		raw_comp = travel + radius - along + Bike.road_bump(hit["position"], surf) * 0.6
	if raw_comp < 0.0:
		w["contact"] = false
		w["load"] = 0.0
		w["compression"] = move_toward(w["compression"], 0.0, delta * 2.0)
		var om: float = w["omega"] + w["drive_torque"] * delta / inertia_w
		om = move_toward(om, 0.0, w["brake_torque"] * delta / inertia_w)
		w["omega"] = om * 0.999
		w["spin"] = fmod(w["spin"] + w["omega"] * delta, TAU)
		w["slip"] = 0.0
		w["fx"] = 0.0
		w["fy"] = 0.0
		return
	var comp := clampf(raw_comp, 0.0, travel)
	var was: bool = w["contact"]
	var arm0 := mount - body.global_position
	var closing := -(body.linear_velocity + body.angular_velocity.cross(arm0)).dot(up)
	var comp_vel: float = (comp - float(w["compression"])) / delta if was else closing
	var raw_vel: float = (raw_comp - float(w["raw"])) / delta if was else closing
	w["raw"] = raw_comp
	w["compression"] = comp
	var damp: float = float(w["bump"]) * comp_vel if comp_vel > 0.0 else float(w["rebound"]) * comp_vel
	var fz: float = float(w["spring"]) * comp + damp
	if raw_comp > travel:
		fz += (raw_comp - travel) * 200000.0 + raw_vel * (12000.0 if raw_vel > 0.0 else 18000.0)
	fz = clampf(fz, 0.0, share * G * 8.0)
	w["contact"] = true
	w["load"] = fz
	w["surface"] = surf
	var contact: Vector3 = hit["position"]
	w["contact_pos"] = contact
	var arm := contact - body.global_position
	body.apply_force(n * fz, arm)

	# The tyre's frame on the ground: lat_dir points to the wheel's left.
	var heading := (-b.z).rotated(up, -float(w["steer"]))
	var long_dir := (heading - n * heading.dot(n)).normalized()
	var lat_dir := n.cross(long_dir)
	var v_contact := body.linear_velocity + body.angular_velocity.cross(arm)
	var v_long := v_contact.dot(long_dir)
	var v_lat := v_contact.dot(lat_dir)
	var v_abs := absf(v_long)
	var tp: Dictionary = w["tyre"]
	var mu := TyreModel.mu_at(float(GRIP.get(surf, 0.6)) * Weather.grip_mult(surf), fz, fz0, tp)
	var f_peak := mu * fz
	var kp: float = tp["kappa_peak"]
	var ap: float = tp["alpha_peak"]
	var alpha := atan2(v_lat, maxf(v_abs, LAT_SLIP_SPEED))
	w["alpha"] = alpha
	var sy_now := -tan(clampf(alpha, -TyreModel.MAX_SLIP_ANGLE, TyreModel.MAX_SLIP_ANGLE)) / tan(ap)
	var sy := sy_now
	if was:
		var keep := exp(-maxf(v_abs, RELAX_SPEED) * delta / float(tp["relax"]))
		sy = sy_now + (float(w["sy"]) - sy_now) * keep
	w["sy"] = sy
	var vden := maxf(v_abs, LONG_SLIP_SPEED)
	var r := radius   # a car tyre's rolling radius barely changes with load
	var omega: float = w["omega"] + w["drive_torque"] * delta / inertia_w
	# The brake before the road's push (as Bike): the tyre's grip then works against the brake in
	# the same solve, so a light pedal is a light stop, and one strong enough still locks it.
	omega = move_toward(omega, 0.0, w["brake_torque"] * delta / inertia_w)
	var omega_new := 0.0
	# Stopped by the brake and the brake still stronger than the road can turn it: it stays locked.
	var road_turn := absf(r * f_peak * TyreModel.combined(-v_long / vden / kp, sy, tp).x)
	if not (omega == 0.0 and float(w["brake_torque"]) >= road_turn and float(w["brake_torque"]) > 0.0):
		omega_new = Bike._solve_spin(omega, v_long, vden, r, kp, sy, f_peak, inertia_w / delta, tp)
	if w["abs"] and v_abs > 1.0 and float(w["brake_torque"]) > 0.0:
		# ABS: the brake is eased before the wheel goes past the grip it has left.
		var left := maxf(sqrt(maxf(1.0 - sy * sy, 0.0)), 0.25)
		if signf(v_long) * (omega_new * r - v_long) / vden / kp < -left:
			omega_new = (v_long - signf(v_long) * left * kp * vden) / r
	var sx := (omega_new * r - v_long) / vden / kp
	var g := TyreModel.combined(sx, sy, tp)
	var fx := f_peak * g.x
	var fy := f_peak * g.y
	w["kappa"] = sx * kp
	var rho := Vector2(sx, sy).length()
	w["grip_used"] = g.length() if rho <= 1.0 else rho
	w["slip"] = clampf(rho - 1.0, 0.0, 1.0)
	# At a crawl a tyre can't push harder than it takes to stop the creep.
	var cap := share * 0.5 / delta
	fy = clampf(fy, -absf(v_lat) * cap, absf(v_lat) * cap)
	if absf(omega_new) < 0.05 and float(w["brake_torque"]) > 0.0:
		fx = clampf(fx, -absf(v_long) * cap, absf(v_long) * cap)
	fx -= signf(v_long) * ROLLING * fz * clampf(v_abs / 0.5, 0.0, 1.0)
	w["fx"] = fx
	w["fy"] = fy
	w["omega"] = omega_new
	w["spin"] = fmod(w["spin"] + omega_new * delta, TAU)
	body.apply_force(long_dir * fx + lat_dir * fy, arm)
