extends RefCounted
## The Rig built look's tank, seat and tail (bodywork track H3), fitted to the bike's rig
## (RigBodywork), run from tests/run_tests.gd: its _test_rig_body_* functions hand over to these.

var t: Node

## How far the tank's tunnel roof may sit off the rig's tank floor along its middle.
const ROOF_TOL := 0.006
## How far the seat's top over the rider's hip may sit from the rig's seat surface (a cruiser's
## scooped seat on its high rails takes its foam down as far as it goes and stays 33 mm proud).
const HIP_TOL := 0.04
## The most gap between the tank's back and the seat's nose (none where the seat runs over it).
const JOIN_GAP := 0.02
const HIGH_FENDER := ["mx", "supermoto"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A model in the Rig built look, its Blender-made parts on, in the runner's tree.
func _model() -> BikeModel:
	var m := BikeModel.new()
	m.look = BikeLook.NEW
	t.add_child(m)
	return m


## Every vertex of a slot's meshes, in the model's space.
static func points(m: BikeModel, slot: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in m._slot_meshes.get(slot, []):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var xf := m._local_xform(mi)
		var mesh := (mi as MeshInstance3D).mesh
		for k in mesh.get_surface_count():
			for v: Vector3 in mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				out.append(xf * v)
	return out


## How the tank, seat and tail sit on one stock bike: {"roof": the worst its tunnel's roof sits
## off the floor, "top": its top over the style's line, "hip": seat top at the hip less the seat
## surface, "gap": tank back to seat nose, "tail_gap": seat's back to the tail's front}.
static func measure(m: BikeModel) -> Dictionary:
	var r := m.rig
	var floor_line: PackedVector3Array = r["tank_floor"]
	var tank := points(m, "tank")
	var z0 := INF
	var z1 := -INF
	var top := -INF
	for v in tank:
		z0 = minf(z0, v.z)
		z1 = maxf(z1, v.z)
		top = maxf(top, v.y)
	# (Along the roof, short of the 2 cm at each end where it rounds up into the tunnel's mouths:
	# on a short tank, an MX bike's, those come well inside its middle.)
	var span := z1 - z0
	var low := []
	var r0 := INF
	var r1 := -INF
	for v in tank:
		if absf(v.x) > 0.002 or v.z < z0 + span * 0.2 or v.z > z1 - span * 0.2:
			continue
		var on: Vector3 = RigBodywork.line_at(floor_line, v.z)[0]
		if v.y < on.y + 0.03:
			low.append(Vector2(v.z, v.y - on.y))
			r0 = minf(r0, v.z)
			r1 = maxf(r1, v.z)
	var roof := 0.0
	for q: Vector2 in low:
		if q.x > r0 + 0.02 and q.x < r1 - 0.02:
			roof = maxf(roof, absf(q.y))
	var hip: Vector3 = r["seat_surface"]
	var seat := points(m, "saddle")
	var seat_top := -INF
	var s0 := INF
	var s1 := -INF
	for v in seat:
		s0 = minf(s0, v.z)
		s1 = maxf(s1, v.z)
		if absf(v.z - hip.z) < 0.03 and absf(v.x) < 0.04:
			seat_top = maxf(seat_top, v.y)
	var tail_gap := 0.0
	var tail := points(m, "tail")
	if not tail.is_empty() and not seat.is_empty():
		var t0 := INF
		for v in tail:
			t0 = minf(t0, v.z)
		tail_gap = t0 - s1
	return {"roof": roof, "top": top - float(r["tank_top_max"]), "hip": seat_top - hip.y, "gap": s0 - z1,
		"tail_gap": tail_gap}


## Every style's stock bike in the Rig built look: its tank's tunnel sits on the backbone's tank
## floor (lines agreement 3) and its top no higher than the style's line allows; the seat's top is
## at the published seat height over the rider's hip; the seat's nose meets the tank's back (or
## runs over it) and the tail carries on from the seat, with no gap between them.
func test_on_rig() -> void:
	var m := _model()
	var off := []
	var worst := {}
	for style in PartsDB.STYLES:
		m.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style))))
		if not m._rig_bodywork():
			off.append("%s: not rig fitted" % style)
			continue
		var d := measure(m)
		for k in d:
			worst[k] = maxf(float(worst.get(k, -INF)), absf(float(d[k])) if k in ["roof", "hip"] else float(d[k]))
		if float(d["roof"]) > ROOF_TOL:
			off.append("%s: tunnel %.0f mm off the tank floor" % [style, float(d["roof"]) * 1000.0])
		if float(d["top"]) > BikeRig.TANK_HIGH + 0.001:
			off.append("%s: tank top %.0f mm over its line" % [style, float(d["top"]) * 1000.0])
		if absf(float(d["hip"])) > HIP_TOL:
			off.append("%s: seat %.0f mm off its height at the hip" % [style, float(d["hip"]) * 1000.0])
		# (An MX or supermoto's high fender is laid out clear of the rear tyre at full travel,
		# which sweeps up past the seat's back on those rails; it isn't on the seat's line.)
		if style in HIGH_FENDER:
			d["tail_gap"] = 0.0
		if float(d["gap"]) > JOIN_GAP or float(d["tail_gap"]) > JOIN_GAP:
			off.append("%s: %.0f mm from tank to seat, %.0f from seat to tail" % [style, float(d["gap"]) * 1000.0, float(d["tail_gap"]) * 1000.0])
	m.queue_free()
	check(off.is_empty(), "every stock bike's tank sits on its backbone and meets its seat, the seat at its height and the tail carrying on from it %s %s" % [worst, off])


## The fitting is worked out from the bike's parts alone: a second model (a co-op guest's) draws
## the same tank, seat and tail to the last digit; and the Classic look keeps its own.
func test_deterministic() -> void:
	var same := true
	for style in ["cruiser", "sport", "mx"]:
		var build := BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build(style)))
		var a := _model()
		var b := _model()
		a.build_from(build)
		BikeRig._cache.clear()
		b.build_from(build)
		for slot in ["tank", "saddle", "tail"]:
			same = same and points(a, slot) == points(b, slot)
		a.free()
		b.free()
	var c := BikeModel.new()
	c.look = BikeLook.CLASSIC
	t.add_child(c)
	c.build_from(BikeBuild.new(PartsDB.sanitize_build(Contracts.style_build("cruiser"))))
	check(same and not c._rig_bodywork(), "the tank, seat and tail are fitted the same on every machine, and the Classic look keeps its own")
	c.free()



