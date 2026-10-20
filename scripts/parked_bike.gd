class_name ParkedBike
extends Node3D
## A bike parked up out front of an adventure's bike cafe (AdventureStops._cafe), with a real
## build behind it: a style's (from its seed, the same on every player's game, see
## RoadTraffic.look_of) in the colour it was parked in. From the road it's a few boxes, as the
## stops always drew their bikes. Once you're off your bike and on foot within DRESS_NEAR it's
## drawn as the bike itself, leaning on its side stand (a baked BikeModel: making one takes a
## good part of a frame, so only one goes in every DRESS_GAP seconds, and never while you ride
## in). It's solid, and looked at on foot it can be ordered or have its blueprint copied
## (BikeCopyView, meta "parked_bike").

const DRESS_NEAR := 40.0
const DRESS_GAP := 0.25
const CHECK_EVERY := 0.3
## When a parked bike was last drawn properly (msec), across every stop.
static var _dressed_at := -100000

var seed_value := 0
var paint := Color.WHITE
var build: BikeBuild   # made when it's first drawn properly
var model: BikeModel
var _parts := {}
var _boxes: MeshInstance3D
var _wait := 0.0


## Makes a parked bike at `xf` (facing its -z) from `look_seed`, in `col`, as a stop's piece:
## `top_box` puts a top box on the boxes. Its build is only worked out when it's wanted.
static func make(xf: Transform3D, look_seed: int, col: Color, top_box: bool, near_range: float) -> ParkedBike:
	var pb := ParkedBike.new()
	pb.name = "ParkedBike%d" % (absi(look_seed) % 100000)
	pb.transform = xf
	pb.seed_value = look_seed
	pb.paint = col
	pb._boxes = MeshInstance3D.new()
	pb._boxes.name = "Boxes"
	pb._boxes.mesh = AdventureProps.to_mesh(_box_bike(col, top_box))
	pb._boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	AdventureChunk._range(pb._boxes, near_range)
	pb.add_child(pb._boxes)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.set_meta("parked_bike", pb)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.1, 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.55
	body.add_child(cs)
	pb.add_child(body)
	return pb


## The boxes: a motorbike on its side stand (as the stops drew them before).
static func _box_bike(col: Color, top_box: bool) -> Dictionary:
	var a := AdventureProps.new_arrays()
	var lean := Transform3D(Basis(Vector3.BACK, 0.12), Vector3.ZERO)
	var tyre := Color(0.05, 0.05, 0.05)
	for wz: float in [-0.72, 0.72]:
		# A wheel: two square slabs turned 45 degrees to each other, an octagon from the side.
		for turn: float in [0.0, PI * 0.25]:
			AdventureProps.box(a, lean * Transform3D(Basis(Vector3.RIGHT, turn), Vector3(0, 0.33, wz)) * Transform3D(Basis(), Vector3(0, -0.29, 0)),
				Vector3(0.12, 0.58, 0.58), tyre)
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.38, 0)), Vector3(0.28, 0.32, 0.9), Color(0.2, 0.2, 0.21))   # engine
	AdventureProps.box(a, lean * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.72, -0.12)), Vector3(0.34, 0.26, 0.6), col)   # tank
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.76, 0.45)), Vector3(0.28, 0.1, 0.6), Color(0.08, 0.08, 0.08))   # seat
	AdventureProps.box(a, lean * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, 0.62, -0.65)), Vector3(0.06, 0.55, 0.06), Color(0.6, 0.6, 0.62))   # forks
	AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.95, -0.55)), Vector3(0.7, 0.04, 0.04), Color(0.1, 0.1, 0.1))   # bars
	if top_box:
		AdventureProps.box(a, lean * Transform3D(Basis(), Vector3(0, 0.84, 0.82)), Vector3(0.42, 0.32, 0.36), Color(0.1, 0.1, 0.11))   # top box
	return a


## Its build: slot -> part, a style's from its seed, always on a side stand.
func parts() -> Dictionary:
	if _parts.is_empty():
		var p: Dictionary = RoadTraffic.look_of(seed_value)["parts"]
		if str(p.get("side_stand", "none")) == "none":
			p["side_stand"] = PartsDB.DEFAULT_BUILD["side_stand"]
		_parts = PartsDB.sanitize_build(p)
	return _parts


## Its parts' colours, as BikeBuild's condition: its paint on BikeCopy.PAINTED.
func cond() -> Dictionary:
	var out := {}
	for slot in BikeCopy.PAINTED:
		if str(parts().get(slot, "none")) != "none":
			out[slot] = {"color": paint}
	return out


## What it's called: "Cafe racer, 750cc twin".
func bike_name() -> String:
	return BikeCopy.default_name(parts())


## As a request for ordering one or copying its blueprint carries it (see BikeCopy).
func bike_src() -> Dictionary:
	return BikeCopy.build_src(bike_name(), parts(), paint, cond(), false)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = CHECK_EVERY
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < DRESS_NEAR
	if model != null:
		# Gone back out of range: the boxes again.
		model.visible = near
		_boxes.visible = not near
		return
	var w := get_tree().get_first_node_in_group("local_walker") as Node3D
	if not near or w == null or not w.visible or not w.can_process():
		return
	if Time.get_ticks_msec() - _dressed_at < DRESS_GAP * 1000.0:
		_wait = 0.05
		return
	_dressed_at = Time.get_ticks_msec()
	dress()


## Draws it as the bike itself, leaning on its side stand, in place of the boxes.
func dress() -> void:
	if model != null:
		return
	build = BikeBuild.new(parts(), cond())
	var lean := Node3D.new()
	lean.name = "Lean"
	lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(str(parts()["side_stand"])).get("lean", 12.0))))
	add_child(lean)
	model = BikeModel.new()
	model.baked = true   # parked, never worked on: far fewer draw calls (see BikeModel._bake_static)
	model.stand_pose = "side"
	model.position.y = build.rear_radius
	lean.add_child(model)
	model.build_from(build, paint, {}, null, false)
	_boxes.visible = false
