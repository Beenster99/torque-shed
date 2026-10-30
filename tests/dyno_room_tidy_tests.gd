extends RefCounted
## The tidied dyno room: the four instruction signs gone from its walls, and the exhaust extraction
## hose hanging from the ceiling over the back of the rig instead of from a hook on the east wall.
## Run from tests/run_tests.gd (its _test_dyno_tidy_* functions hand over to these).

var t: Node   # the test runner: check(), get_tree()

## The signs Simon asked to come down, and the ones that stay.
const GONE := ["STRAP IT DOWN", "LET GO NEAR THE DRUM", "HOSE ON THE EXHAUST", "TUNE AT THE DESK"]
const KEPT := ["DYNO ROOM", "EAR DEFENDERS", "LIGHTS", "FAN"]


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A dyno room built on its own, in the runner's tree, standing still (the shed it hangs off is
## left unbuilt, out of the tree).
func _room() -> DynoRoom:
	var ws := Workshop.new()
	var room := DynoRoom.new()
	room.build(ws)
	t.add_child(room)
	room.set_process(false)
	return room


func _done(room: DynoRoom) -> void:
	var ws := room.workshop
	room.queue_free()
	ws.free()


## A model of `parts` sat on the rig as the shed draws a bike there.
func _on_rig(parts: Dictionary) -> BikeModel:
	var b := BikeBuild.new(PartsDB.sanitize_build(BikeBuild.sensible_fork(parts, 7)))
	var m := BikeModel.new()
	t.add_child(m)
	m.build_from(b)
	m.global_transform = DynoRoom.rig_transform().translated(Vector3(0.0, b.rear_radius, 0.0))
	return m


## Everything on a model, in world space.
static func _bounds(m: BikeModel) -> AABB:
	var box := AABB()
	var first := true
	for slot in m._slot_meshes:
		if (m._slot_meshes[slot] as Array).is_empty():
			continue
		var b := m.global_transform * m.slot_bounds(slot)
		box = b if first else box.merge(b)
		first = false
	return box


## A mesh's box in world space.
static func _box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()


## The four instruction signs are gone, papers and all; the door sign and the switch and ear
## defender labels stay.
func test_signs() -> void:
	var room := _room()
	var texts: Array = room.find_children("*", "Label3D", true, false).map(func(l): return (l as Label3D).text.to_upper())
	var left := GONE.filter(func(g): return texts.any(func(x): return str(x).contains(g)))
	check(left.is_empty(), "the strap, drum, hose and desk signs are gone from the dyno room (%s)" % str(left))
	check(KEPT.all(func(k): return texts.has(k)), "the door sign and the switch and ear defender labels stay (%s)" % str(texts))
	# No blank paper left where a sign was: every poster still has its words.
	var blank := room.get_children().filter(func(n): return n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh and n.find_children("*", "Label3D", false, false).is_empty())
	check(blank.is_empty(), "no blank sign boards left on the walls (%d)" % blank.size())
	_done(room)


## The hose drops from the ceiling over the back of the rig, its duct runs along the ceiling to
## the east wall clear of the lights and beams, and parked it hangs clear over the tallest
## adventure bike and the longest cruiser and chopper on the rig, out of everyone's way.
func test_hose() -> void:
	Shed.start_new("Tester", 21)
	var room := _room()
	var top := DynoRoom.HEIGHT
	# The drop and its duct: up at the ceiling.
	var duct: MeshInstance3D = room.get_node("ExtractDuct")
	var db := _box(duct)
	check(db.end.y <= top + 0.001 and db.end.y > top - 0.12 and DynoRoom.HOSE_DROP.y > top - 0.4,
		"the hose's duct is up at the ceiling (top %.2f m of %.2f) and it drops from there (%.2f m)" % [db.end.y, top, DynoRoom.HOSE_DROP.y])
	check(db.end.x > DynoRoom.CENTER.x + DynoRoom.HALF.x - 0.05 and db.position.x < DynoRoom.HOSE_DROP.x + 0.05,
		"the duct runs along the ceiling from the drop to the east wall (x %.2f..%.2f)" % [db.position.x, db.end.x])
	var collar: MeshInstance3D = room.get_node("HoseCollar")
	check(absf(collar.global_position.x - DynoRoom.HOSE_DROP.x) < 0.01 and _box(collar).end.y > DynoRoom.HOSE_DROP.y,
		"the hose hangs from a collar at the drop")
	# Over the back of the rig, where the silencers end up.
	var rig := DynoRoom.rig_transform()
	var over := rig.affine_inverse() * DynoRoom.HOSE_PARK
	check(over.z > DynoRoom.DRUM_Z and over.z < DynoRoom.DRUM_Z + 0.8 and absf(over.x) < 0.5,
		"it hangs over the back of the bike on the rig (%.2f m behind the drum, %.2f m to the side)" % [over.z - DynoRoom.DRUM_Z, over.x])
	# Clear of the lights, the cross beams, the drum and the desk.
	var hits := []
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m == duct:
			continue
		var mat = m.material_override
		var lamp: bool = mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled and m.mesh is BoxMesh
		var beam: bool = m.mesh is BoxMesh and (m.mesh as BoxMesh).size.x > DynoRoom.HALF.x * 1.9 and _box(m).position.y > top - 0.4
		if (lamp or beam) and _box(m).intersects(db):
			hits.append("%s at %s" % ["light" if lamp else "beam", _box(m).get_center()])
	check(hits.is_empty(), "the duct is clear of the light fittings and the cross beams (%s)" % str(hits))
	# Parked: hangs straight down from the drop, end up out of the way.
	room._draw_hose(room.hose_end_transform())
	var end_at := room.hose_end_transform().origin
	check(end_at.distance_to(DynoRoom.HOSE_PARK) < 0.01, "put away, its end hangs at its parking spot over the rig")
	var hose := AABB(DynoRoom.HOSE_DROP, Vector3.ZERO)
	for seg in room._hose_parts:
		hose = hose.merge(_box(seg))
	for mi in room._hose_end.find_children("*", "MeshInstance3D", true, false):
		hose = hose.merge(_box(mi))
	check(hose.size.x < 0.4 and hose.size.z < 0.4, "it hangs straight down (%.2f x %.2f m)" % [hose.size.x, hose.size.z])
	check(hose.position.y > 1.85, "its lowest point is %.2f m up: over the head of anyone walking under it" % hose.position.y)
	var desk := AABB(DynoRoom.DESK - Vector3(0.8, 0.0, 0.5), Vector3(1.6, 1.2, 1.0))
	var drum := AABB(DynoRoom.CENTER + Vector3(-0.3, -0.7, DynoRoom.DRUM_Z - DynoRoom.DRUM_RADIUS), Vector3(0.6, 0.8, DynoRoom.DRUM_RADIUS * 2.0))
	check(not hose.intersects(desk) and not hose.intersects(drum), "it's nowhere near the desk or the drum")
	# A tall adventure bike loaded up, and long cruisers and choppers, on the rig: the parked hose
	# stays clear of them all.
	var tall: Dictionary = Contracts.style_build("adventure")
	tall.merge({"top_box": "adv_alloy_top_55", "panniers": "adv_alloy_trunks_silver", "aux_tank": "rear_rally_tank_10"}, true)
	var builds := {"adventure": tall}
	for style in ["cruiser", "chopper"]:
		var long: Dictionary = Contracts.style_build(style)
		long.merge({"tail": "cruiser_halo_fender", "top_box": "leather_trunk"}, true)
		builds[style] = long
	for style in builds:
		var m := _on_rig(builds[style])
		var bb := _bounds(m)
		if style == "adventure":
			check(["top_box", "panniers"].all(func(slot): return m.slot_bounds(slot).size.y > 0.1), "the adventure bike has its top box and panniers on")
		check(not hose.intersects(bb), "the parked hose is clear of the %s on the rig (bike %.2f m tall, its end %.2f m up; bike back at %.2f, hose at %.2f)"
			% [style, bb.end.y, hose.position.y, bb.end.z, hose.position.z])
		check(not db.intersects(bb), "and the duct is well above it")
		# Fitted over the exhaust, the end is on the tailpipe and the hose comes down from the drop.
		Shed.dyno["hose"] = "bike"
		var tip := Transform3D(Basis.looking_at(-m.global_transform.basis.z, Vector3.UP), m.global_transform * m.exhaust_tip())
		room._draw_hose(tip)
		var first: MeshInstance3D = room._hose_parts[0]
		check(room._hose_end.global_position.distance_to(tip.origin) < 0.01 and first.global_position.y > bb.end.y,
			"on the %s's exhaust its end sits on the tailpipe and it comes down from the ceiling" % style)
		Shed.dyno["hose"] = "hook"
		m.queue_free()
	# Nothing of it gets in the way of walking: its only bodies are for aiming at.
	var solid := []
	for b in room.find_children("*", "StaticBody3D", true, false):
		var at: Vector3 = (b as Node3D).global_position
		if Vector2(at.x - DynoRoom.HOSE_DROP.x, at.z - DynoRoom.HOSE_DROP.z).length() < 0.5 and (b as StaticBody3D).collision_layer != Workshop.INTERACT_LAYER:
			solid.append(b.name)
	check(solid.is_empty(), "nothing solid hangs where people walk (%s)" % str(solid))
	_done(room)
