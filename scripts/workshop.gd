class_name Workshop
extends Node3D
## The shed: a snug workshop with a roller door onto the Build Yard. Inside are four bike bays
## with paddock stands and a screen above each, a workbench, an engine stand, a parts computer
## with delivery pallets, a parts washer, a repair bench, a bin and the crew board, and through
## the back wall the dyno room (DynoRoom). It also draws every parked bike and every loose
## part from the shared Shed state.

const CENTER := Vector3(0.0, 0.0, 65.0)
const HALF := Vector2(6.5, 5.5)           # interior half size in x and z
const HEIGHT := 4.5
const DOOR_HALF := 2.3
const DOOR_HEIGHT := 3.2
const BAY_COUNT := 4
const INTERACT_LAYER := 8
## The wash bay: a lean-to on the west wall, open to the yard, with a pressure washer whose
## hose reaches anywhere inside it and a little way out.
const WASH_CENTER := Vector3(-9.3, 0.0, 66.0)
const WASH_HALF := Vector2(2.4, 3.4)
const WASH_POS := Vector3(-11.3, 0.0, 63.2)
const WASH_REACH := 8.0
## Doorways through the shed's side walls into the paint shop and the storage room.
const SIDE_DOOR_HALF := 0.65
const SIDE_DOOR_HEIGHT := 2.4
const ROOM_HEIGHT := 3.4
## The paint shop: a room off the east wall, entered through a doorway from inside the shed,
## with the shed's own open-topped downdraft spray bay (ten hooks on two rails) built into it
## and a ceiling of hexagon LED tiles. Interior x 6.8..14.0, z 59.8..70.2.
const BOOTH_ROOM_CENTER := Vector3(10.4, 0.0, 65.0)
const BOOTH_ROOM_HALF := Vector2(3.6, 5.2)
const PAINT_DOOR_Z := 68.5
const BOOTH_MODEL := "booth_shop"
## The spray bay's open front faces the walkway by the door (its +Z points along -X).
const BOOTH_XF := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0)),
	Vector3(11.6, 0.0, 65.0))
## The storage room: an empty room off the west wall behind the wash bay, through a doorway
## by the back corner, for lining up shelving. Interior x -15.0..-6.8, z 54.0..62.2.
const STORE_CENTER := Vector3(-10.9, 0.0, 58.1)
const STORE_HALF := Vector2(4.1, 4.1)
const STORE_DOOR_Z := 60.5
## The tyre changer, built in against the west wall just past the end of the workbench and
## facing into the shed, clear of the bays, the doors and the whiteboard.
const CHANGER_XF := Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0)),
	Vector3(-6.04, 0.0, 68.55))
## Widths of the screens built into the shed: over the middle bays, over the outer bays, and
## the crew board. Wall TVs from the parts computer are at least as big as the smallest.
const BAY_SCREEN_INNER := 2.6
const BAY_SCREEN_OUTER := 2.6
## Where each bay's screen hangs along the back wall (x from CENTER): the four sit in pairs
## either side of the dyno room doorway, nudged off their bays to clear it.
const BAY_SCREEN_X := [-5.04, -2.32, 2.32, 5.04]
const CREW_SCREEN := 3.0
## The bins by the roller door: general waste and the two recycling bins, left to right
## from the door, tucked under the end of the whiteboard. x offset from CENTER, lid colour.
const BINS := {"general": [-2.75, Color(0.1, 0.1, 0.1)], "plastic": [-3.33, Color(0.1, 0.35, 0.85)],
	"metal": [-3.91, Color(0.2, 0.55, 0.3)]}
const BIN_SIZE := Vector3(0.52, 0.9, 0.6)
## How far a live TV picture's camera sits behind and above the rider.
const FEED_BACK := 4.5
const FEED_UP := 1.8
## The sales office (SalesOffice, east of the paint shop): where a customer stands at the
## reception desk (-Z facing it), where a player stands behind the desk to serve them, where
## customers arrive from (the car park edge, facing the doors), the front doors, and the
## showroom's display plinths for bikes on show.
const RECEPTION := SalesOffice.RECEPTION
const RECEPTION_DESK := SalesOffice.RECEPTION_DESK
const CUSTOMER_ENTRY := SalesOffice.CUSTOMER_ENTRY
const SALES_DOOR := SalesOffice.SALES_DOOR
const SHOWROOM_SPOTS := SalesOffice.SHOWROOM_SPOTS

var bike_views := {}       # bike id -> Node3D holding a BikeModel
var _view_sigs := {}
var _spot_nodes := {}      # spot -> Node3D
var _spot_sigs := {}
var furniture_nodes := {} # furniture id -> EquipmentView
var _furniture_sigs := {}
var _floor_nodes := {}     # item id -> Node3D for parts put down anywhere
var _floor_sigs := {}
var _holo_views := {}      # bay -> Node3D: the hologram of a blueprint build waiting for its frame
var _holo_sigs := {}
var _ghost_mat: StandardMaterial3D
var _ghosts := 0           # holograms drawn, so the flicker only runs while there are some
var _bay_screens: Array[Dashboard] = []
var _crew_screen: Dashboard
var _dash_timer := 0.0
var _dash_dirty := true
var _mats := {}
var radio: ShedRadio
var dyno_room: DynoRoom     # the tuning room through the back wall
var sales_office: SalesOffice   # the showroom and office east of the paint shop
## A live riding picture a TV is showing (the first one, if there are several), or null.
var tv_feed: SubViewport
## Live riding pictures, one per rider being watched: bike node instance id -> {vp, cam, node}.
var _feeds := {}
var _screen_shown := {}    # screen key -> the channel it last drew, to flash the name on a change
var _screens_sig := ""
var door_open_amount := 1.0   # the roller door: 0 down, 1 rolled up
var _door_panel: MeshInstance3D
var _door_shape: CollisionShape3D
var _door_sound: AudioStreamPlayer3D
var _shed_lights: Array[Light3D] = []
var _fixture_mats: Array[StandardMaterial3D] = []
var _probe: ReflectionProbe
var _lights_shown := true
## The side rooms' lights, fixtures and ambient probes, by room ("paint", "storage").
var _room_lights := {"paint": [], "storage": []}
var _room_mats := {"paint": [], "storage": []}
var _room_probes := {}
var _room_shown := {}
## Garage upgrades built onto the shed (WorkshopUpgrades), and the stretches of wall they
## knock doorways through: "wing" (the shed's back wall behind bay 4), "annex" (the storage
## room's back wall), each [wall body, inside faces...].
var upgrades: WorkshopUpgrades
var knock := {"wing": [], "annex": []}


static func bay_transform(bay: int) -> Transform3D:
	if bay >= BAY_COUNT:
		# The bays in the garage's extension (GarageUpgrades), facing its back wall.
		var i := clampi(bay - BAY_COUNT, 0, GarageUpgrades.WING_BAY_X.size() - 1)
		return Transform3D(Basis(Vector3.UP, PI), Vector3(float(GarageUpgrades.WING_BAY_X[i]), 0.0, GarageUpgrades.WING_BAY_Z))
	var x := -4.8 + 3.2 * clampi(bay, 0, BAY_COUNT - 1)
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.0, -3.5))


## How many bays there are: the shed's four and any the garage has added (GarageUpgrades).
static func bay_count() -> int:
	return BAY_COUNT + GarageUpgrades.extra_bays(Shed.upgrades)


## Where each work spot puts a part, and which way it faces.
static func spot_transform(spot: String) -> Transform3D:
	if spot.begins_with("bench_"):
		var i := int(spot.trim_prefix("bench_"))
		return Transform3D(Basis(), CENTER + Vector3(-HALF.x + 0.5, 0.96, -1.2 + i * 1.2))
	if spot.begins_with("delivery_"):
		var i := int(spot.trim_prefix("delivery_"))
		return Transform3D(Basis(Vector3.UP, PI * 0.5), CENTER + Vector3(-5.6 + (i % 2) * 1.2, 0.16, 3.8 + (i / 2) * 1.1))
	match spot:
		"engine_stand":
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), CENTER + Vector3(HALF.x - 0.9, 0.72, -0.4))
	return Transform3D(Basis(), CENTER)


## The floor of each room, as x/z rectangles: the shed, the paint shop, the storage room, the
## dyno room, and the sales office ("sales", the whole building) with its mezzanine office upstairs
## ("sales_office", over the west end of it).
static func rooms() -> Dictionary:
	var out := {
		"shed": Rect2(CENTER.x - HALF.x, CENTER.z - HALF.y, HALF.x * 2.0, HALF.y * 2.0),
		"paint": Rect2(BOOTH_ROOM_CENTER.x - BOOTH_ROOM_HALF.x, BOOTH_ROOM_CENTER.z - BOOTH_ROOM_HALF.y, BOOTH_ROOM_HALF.x * 2.0, BOOTH_ROOM_HALF.y * 2.0),
		"storage": Rect2(STORE_CENTER.x - STORE_HALF.x, STORE_CENTER.z - STORE_HALF.y, STORE_HALF.x * 2.0, STORE_HALF.y * 2.0),
		"dyno": Rect2(DynoRoom.CENTER.x - DynoRoom.HALF.x, DynoRoom.CENTER.z - DynoRoom.HALF.y, DynoRoom.HALF.x * 2.0, DynoRoom.HALF.y * 2.0),
		"sales": SalesOffice.footprint(),
		"sales_office": SalesOffice.office_rect(),
	}
	# The extension and storage annex, once the garage has built them.
	out.merge(GarageUpgrades.rooms(Shed.upgrades))
	return out


## Which room a point is in ("shed", "paint", "storage", "dyno", "sales", "sales_office"
## upstairs in the sales office, "lounge" upstairs on the shed), or "" outside.
static func room_at(at: Vector3) -> String:
	if SalesOffice.office_rect().has_point(Vector2(at.x, at.z)) and at.y > SalesOffice.MEZZ_Y - 0.3:
		return "sales_office"
	if Shed.upgrades.has("lounge") and GarageUpgrades.LOFT.has_point(Vector2(at.x, at.z)) and at.y > GarageUpgrades.LOFT_FLOOR - 0.3:
		return "lounge"   # the crew lounge, upstairs on top of the shed
	var all := rooms()
	all.erase("sales_office")
	for room in all:
		if (all[room] as Rect2).has_point(Vector2(at.x, at.z)):
			return room
	return ""


## The floor the paint shop's spray bay stands on, as an x/z rectangle.
static func booth_footprint() -> Rect2:
	var size: Vector3 = Equipment.get_model(BOOTH_MODEL).get("size", Vector3.ONE)
	var a := BOOTH_XF * Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	var b := BOOTH_XF * Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


## Where the doorway through a side wall of the shed is: {x (the wall's middle), z, half}.
static func side_doors() -> Dictionary:
	return {"paint": {"x": CENTER.x + HALF.x + 0.15, "z": PAINT_DOOR_Z, "half": SIDE_DOOR_HALF},
		"storage": {"x": CENTER.x - HALF.x - 0.15, "z": STORE_DOOR_Z, "half": SIDE_DOOR_HALF}}


## Where players appear on foot when they arrive.
static func walker_spawn(index: int) -> Transform3D:
	var x := -1.5 + (index % 4) * 1.0
	return Transform3D(Basis(Vector3.UP, PI), CENTER + Vector3(x, 0.1, 2.6 - (index / 4) * 1.0))


func build() -> void:
	name = "Workshop"
	add_to_group("workshop")
	_make_materials()
	_build_shell()
	_build_bays()
	_build_bench()
	_build_computer()
	_build_delivery_area()
	_build_bin()
	_build_radio()
	_build_wash_bay()
	_build_booth_room()
	_build_storage_room()
	_build_lights()
	_build_door_and_switches()
	# The whiteboard is drawn with the equipment, so it can be hung on any wall (EquipmentView).
	dyno_room = DynoRoom.new()
	add_child(dyno_room)
	dyno_room.build(self)
	_build_sales_office()
	_crew_screen = Dashboard.new("crew", CREW_SCREEN)
	_crew_screen.position = CENTER + Vector3(-HALF.x + 0.1, 2.55, 0.6)
	_crew_screen.rotation.y = PI * 0.5
	add_child(_crew_screen)
	_screen_target(_crew_screen, "crew")
	upgrades = WorkshopUpgrades.new()
	add_child(upgrades)
	upgrades.setup(self)


## Lets players look at a built-in screen to change its channel.
func _screen_target(screen: Dashboard, key: String) -> void:
	var h := screen.width * Dashboard.PX.y / Dashboard.PX.x
	_target(Vector3(0.0, 0.0, 0.04), Vector3(screen.width + 0.08, h + 0.08, 0.08), {"screen": key}, screen)


# ---------------------------------------------------------------------------- state

## Redraws parked bikes, loose parts and screens to match the Shed state.
func sync_state() -> void:
	if upgrades:
		upgrades.sync()
	for id in bike_views.keys():
		if not Shed.bikes.has(id) or Shed.bikes[id]["rider"] != 0:
			bike_views[id].queue_free()
			bike_views.erase(id)
			_view_sigs.erase(id)
	for id in Shed.bikes:
		var bike: Dictionary = Shed.bikes[id]
		if bike["rider"] != 0:
			continue
		var sig := _bike_signature(id)
		if _view_sigs.get(id, "") != sig:
			_view_sigs[id] = sig
			if bike_views.has(id):
				bike_views[id].free()
			bike_views[id] = _make_bike_view(id)
		# Moving a bike only moves its view; the one you're wheeling follows you directly.
		if bike.get("pusher", 0) != Shed.me() or bike.get("pusher", 0) == 0:
			bike_views[id].transform = bike["xf"]
	_sync_holograms()
	_sync_furniture()
	var spots := Shed.all_spots()
	for spot in _spot_nodes.keys():
		if not spots.has(spot):
			_drop_spot_node(_spot_nodes[spot]).queue_free()
			_spot_nodes.erase(spot)
			_spot_sigs.erase(spot)
	for spot in spots:
		var item_id := Shed.item_at_spot(spot)
		var sig := "" if item_id == 0 else _item_signature(item_id) + str(Shed.items[item_id].get("place", ""))
		if _spot_sigs.get(spot, "") == sig:
			continue
		if item_id != 0 and _spot_nodes.has(spot) and Shed.spot_role(spot) == "blaster" \
				and Shed.blaster_user(int(Shed.furniture_of_spot(spot).get("id", 0))) != 0 \
				and str(_spot_sigs.get(spot, "")).begins_with("%d:" % item_id):
			# Mid-blast the rust comes off as you go: the engine keeps its bare-metal look until
			# you step back, then it's redrawn.
			continue
		_spot_sigs[spot] = sig
		if _spot_nodes.has(spot):
			_drop_spot_node(_spot_nodes[spot]).free()
			_spot_nodes.erase(spot)
		if item_id != 0:
			var display := BikeModel.item_display(item_id)
			var f := Shed.furniture_of_spot(spot)
			if Shed.surface_of_spot(spot) != "":
				# Put down anywhere on a bench, washer or repair machine: a box round it to aim at.
				_pick_box(display, {"spot": spot})
			if f.is_empty():
				display.transform = Shed.spot_transform(spot)
				add_child(display)
			elif Shed.spot_role(spot) == "changer":
				# A wheel lies flat on the tyre changer's turntable and turns with it.
				var view: Node3D = furniture_nodes[int(f["id"])]
				var table: Node3D = view.get_node_or_null("Turntable")
				var size: Vector3 = display.get_meta("size", Vector3(0.1, 0.6, 0.6))
				var flat := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(size.y * 0.5, size.x * 0.5, 0.0))
				if table:
					display.transform = flat
					table.add_child(display)
				else:
					display.transform = Shed.local_spot_transform(spot) * flat
					view.add_child(display)
			elif Shed.spot_role(spot) == "blaster":
				# In the sandblaster: on its turntable, turning about the engine's middle.
				var view: Node3D = furniture_nodes[int(f["id"])]
				var pivot: Node3D = view.get_node_or_null("Pivot")
				var size: Vector3 = display.get_meta("size", Vector3(0.4, 0.4, 0.4))
				if pivot:
					# Held up off the grate on the turntable's post, high enough to tip right over.
					var lift := Equipment.blaster_lift(size)
					pivot.position = Shed.local_spot_transform(spot).origin + Vector3.UP * lift
					display.position = Vector3.DOWN * size.y * 0.5
					pivot.add_child(display)
					var post: Node3D = view.get_node_or_null("Post")
					if post:
						post.position.y = Shed.local_spot_transform(spot).origin.y
						post.scale.y = maxf(0.01, lift - size.y * 0.5 + 0.02)
				else:
					display.transform = Shed.local_spot_transform(spot)
					view.add_child(display)
				if Shed.is_engine(item_id) and not Shed.items[item_id].get("boxed", false) and display.has_meta("model"):
					# Close up through the glass: the castings, fins and bolts (BlastDetail), and
					# fitted shapes for the blast to land on; the crosshair passes through them.
					var engine_model: BikeModel = display.get_meta("model")
					BlastDetail.add_to(engine_model)
					engine_model.build_pickers({"engine": item_id}, {"engine": {"spot": spot}}, BikeModel.SPRAY_LAYER)
					(view as EquipmentView).fit_blast_colliders(engine_model)
			elif Shed.spot_role(spot) == "booth":
				# Hung from a booth hook: the part, its hook and wire swing together as one
				# pendulum from the wire's mount on the ceiling rail.
				var hang := Shed.local_spot_transform(spot)
				var booth: EquipmentView = furniture_nodes[int(f["id"])]
				var swing := Swing.new()
				swing.name = "Swing"
				swing.length = maxf(0.3, Equipment.rail_height(str(f.get("model", ""))) - hang.origin.y)
				swing.position = hang.origin + Vector3.UP * swing.length
				booth.add_child(swing)
				booth.add_hook_wire(swing, swing.length)
				var fixed: Node3D = booth.get_node_or_null("Hanger_" + spot)
				if fixed:
					# The empty hook's wire is hidden while this one swings in its place.
					fixed.visible = false
					swing.tree_exiting.connect(func():
						if is_instance_valid(fixed):
							fixed.visible = true)
				display.transform = Transform3D(hang.basis, Vector3.DOWN * swing.length)
				swing.add_child(display)
				swing.push(Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)))
			else:
				# Parts on a stand or shelf ride along with it when it's moved.
				display.transform = Shed.local_spot_transform(spot)
				furniture_nodes[int(f["id"])].add_child(display)
			if Shed.spot_role(spot) == "booth" and display.has_meta("model"):
				# Hung in the paint booth: fitted shapes, so the spray lands on the part itself.
				(display.get_meta("model") as BikeModel).build_pickers({"spot": spot}, {}, BikeModel.SPRAY_LAYER)
			if Shed.is_stand_spot(spot) and Shed.is_engine(item_id) and not Shed.items[item_id].get("boxed", false):
				# Parts on the engine can be worked on right there; the block itself is picked up.
				var model: BikeModel = display.get_meta("model")
				model.build_pickers({"engine": item_id}, {"engine": {"spot": spot}})
			_spot_nodes[spot] = display
	_sync_floor()
	radio.sync()
	for id in furniture_nodes:
		var view: EquipmentView = furniture_nodes[id]
		if view.washer_sound:
			var busy := false
			for spot in Shed.furniture_spots(id):
				var washing := Shed.item_at_spot(spot)
				busy = busy or (washing != 0 and float(Shed.items[washing]["dirt"]) > 0.0)
			Sfx.set_loop(view.washer_sound, "washer" if busy else "")
	_dash_dirty = true
	# A channel changed: show it straight away rather than at the next refresh.
	var sig := str(Shed.screens)
	if sig != _screens_sig:
		_screens_sig = sig
		_dash_timer = 0.0


# ---------------------------------------------------------------------------- furniture

## Draws the shed's equipment where it stands. One being moved by this player follows them
## directly (see preview_furniture), so it doesn't lag behind.
func _sync_furniture() -> void:
	for id in furniture_nodes.keys():
		if not Shed.furniture.has(id) or furniture_nodes[id].look != EquipmentView.look_of(Shed.furniture[id]):
			furniture_nodes[id].queue_free()
			furniture_nodes.erase(id)
			_furniture_sigs.erase(id)
			for spot in _spot_nodes.keys():
				if spot.get_slice_count("_") >= 2 and int(spot.get_slice("_", 1)) == id:
					_spot_sigs.erase(spot)
					_spot_nodes.erase(spot)
	for id in Shed.furniture:
		var f: Dictionary = Shed.furniture[id]
		if not furniture_nodes.has(id):
			furniture_nodes[id] = EquipmentView.create(self, id)
		var node: Node3D = furniture_nodes[id]
		if f["mover"] != Shed.me() or f["mover"] == 0:
			node.transform = f["xf"]
		var label: Label3D = node.get_node_or_null("Label")
		if label:
			label.text = str(f.get("label", ""))


func preview_bike(id: int, xf: Transform3D) -> void:
	if bike_views.has(id):
		bike_views[id].transform = xf


## Every physics body that belongs to one piece of equipment.
func furniture_rids(id: int) -> Array[RID]:
	var out: Array[RID] = []
	if not furniture_nodes.has(id):
		return out
	var stack: Array[Node] = [furniture_nodes[id]]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
		stack.append_array(n.get_children())
	return out


func preview_furniture(id: int, xf: Transform3D) -> void:
	if furniture_nodes.has(id):
		furniture_nodes[id].transform = xf


## Every wall TV in the shed.
func tvs() -> Array:
	var out := []
	for id in furniture_nodes:
		if furniture_nodes[id].tv:
			out.append(furniture_nodes[id].tv)
	return out


## Every screen with channels, by its key (see TvChannels): bought TVs, bay screens, crew board.
func screens() -> Dictionary:
	var out := {"crew": _crew_screen}
	for bay in _bay_screens.size():
		out["bay%d" % bay] = _bay_screens[bay]
	for id in furniture_nodes:
		if furniture_nodes[id].tv:
			out["f%d" % id] = furniture_nodes[id].tv.board
	return out


## The bike node a rider is out on (theirs or a remote one), or null.
func _ridden_node(peer: int) -> Node3D:
	var bike_id := int(Shed.crew.get(peer, {}).get("riding", 0))
	var only: Node3D = null
	var count := 0
	for b in get_tree().get_nodes_in_group("ridden_bike"):
		if not (b is Node3D and (b as Node3D).is_inside_tree() and (b as Node3D).visible):
			continue
		count += 1
		only = b
		if bike_id != 0 and int(b.get_meta("shed_bike", 0)) == bike_id:
			return b
	# A bike that doesn't say which it is: fine when it's the only one out.
	return only if count == 1 and not only.has_meta("shed_bike") else null


## Points a chase camera at each rider a screen is tuned to, and puts the live picture on
## those screens. Screens on other channels, or live with nobody out, show their page.
func _update_tv_feed(delta: float) -> void:
	var riders := Shed.riders()
	var want := {}     # bike node instance id -> {node, screens: [[dashboard, caption]]}
	var all := screens()
	for key in all:
		var dash: Dashboard = all[key]
		var state := Shed.screen_channel(key)
		var node: Node3D = null
		var peer := 0
		if state["ch"] == "live":
			peer = TvChannels.live_rider(state, riders)
			node = _ridden_node(peer) if peer != 0 else null
		if node == null:
			dash.show_feed(null, "")
			continue
		var riding := int(Shed.crew[peer].get("riding", 0))
		var caption := "LIVE: %s on %s" % [Shed.crew[peer]["name"], Shed.bikes[riding]["name"]] if Shed.bikes.has(riding) else "LIVE"
		var nid := node.get_instance_id()
		if not want.has(nid):
			want[nid] = {"node": node, "screens": []}
		want[nid]["screens"].append([dash, caption])
	for nid in _feeds.keys():
		if not want.has(nid):
			_feeds[nid]["vp"].queue_free()
			_feeds.erase(nid)
	tv_feed = null
	for nid in want:
		var node: Node3D = want[nid]["node"]
		var fresh := not _feeds.has(nid)
		if fresh:
			var vp := SubViewport.new()
			vp.size = Vector2i(640, 360)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(vp)
			var cam := Camera3D.new()
			cam.fov = 60.0
			cam.far = 1500.0
			vp.add_child(cam)
			_feeds[nid] = {"vp": vp, "cam": cam}
		# A broadcast-style chase camera: behind and above, easing after the bike.
		var cam: Camera3D = _feeds[nid]["cam"]
		var bxf := node.global_transform
		var back := Vector3(bxf.basis.z.x, 0.0, bxf.basis.z.z).normalized()
		var at := bxf.origin + back * FEED_BACK + Vector3.UP * FEED_UP
		cam.global_position = at if fresh else cam.global_position.lerp(at, 1.0 - exp(-4.0 * delta))
		if not cam.global_position.is_equal_approx(bxf.origin + Vector3.UP * 0.8):
			cam.look_at(bxf.origin + Vector3.UP * 0.8, Vector3.UP)
		var vp: SubViewport = _feeds[nid]["vp"]
		if tv_feed == null:
			tv_feed = vp
		for s in want[nid]["screens"]:
			(s[0] as Dashboard).show_feed(vp.get_texture(), s[1])


## Parts put down anywhere, each with a box around it to aim at and pick it up by.
func _sync_floor() -> void:
	var loose := Shed.floor_items()
	for id in _floor_nodes.keys():
		if not loose.has(id):
			_floor_nodes[id].queue_free()
			_floor_nodes.erase(id)
			_floor_sigs.erase(id)
	for id in loose:
		var xf: Transform3D = Shed.items[id]["ref"]
		var sig := _item_signature(id) + str(xf)
		if _floor_sigs.get(id, "") == sig:
			continue
		_floor_sigs[id] = sig
		if _floor_nodes.has(id):
			_floor_nodes[id].free()
		var display := BikeModel.item_display(id)
		display.transform = xf
		add_child(display)
		_pick_box(display, {"item": id})
		if display.has_meta("model") and not Shed.items[id].get("boxed", false):
			# Fitted shapes as well as the box round it, so spray lands on the part itself.
			(display.get_meta("model") as BikeModel).build_pickers({"item": id}, {}, BikeModel.SPRAY_LAYER)
		_floor_nodes[id] = display


## A box round a loose part's display to aim at it by, carrying `meta` ({item} or {spot}).
func _pick_box(display: Node3D, meta: Dictionary) -> void:
	var size: Vector3 = display.get_meta("size", Vector3.ONE * 0.3)
	size = size.max(Vector3(0.12, 0.08, 0.12))
	var body := StaticBody3D.new()
	body.collision_layer = INTERACT_LAYER
	body.collision_mask = 0
	for key in meta:
		body.set_meta(key, meta[key])
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	display.add_child(body)


## The model a part target is drawn on: a parked bike, or the engine on the stand.
func model_for(target: Dictionary) -> BikeModel:
	var engine := int(target.get("engine", 0))
	if engine != 0:
		var spot := str(Shed.items.get(engine, {}).get("ref", ""))
		if _spot_nodes.has(spot):
			return _spot_nodes[spot].get_meta("model") if _spot_nodes[spot].has_meta("model") else null
		return null
	if bike_views.has(target.get("bike", 0)):
		return bike_model(int(target["bike"]))
	return null


## Where a part is drawn and how big it is, for spraying it: {xf: the frame its box is in,
## box: AABB in that frame}, or {} when it isn't drawn.
func item_frame(item_id: int) -> Dictionary:
	if not Shed.items.has(item_id):
		return {}
	var it: Dictionary = Shed.items[item_id]
	match str(it["at"]):
		"bike":
			var bike := int(it["ref"])
			if not bike_views.has(bike):
				return {}
			var model := bike_model(bike)
			for slot in PartsDB.BIKE_SLOTS:
				if Shed.item_on(bike, slot) == item_id:
					return {"xf": model.global_transform, "box": model.slot_bounds(slot), "node": model}
		"engine":
			var block := int(it["ref"])
			var model := model_for({"engine": block})
			if model == null:
				return {}
			for slot in PartsDB.ENGINE_SLOTS:
				if Shed.engine_item(block, slot) == item_id:
					return {"xf": model.global_transform, "box": model.slot_bounds(slot), "node": model}
		"spot":
			if _spot_nodes.has(str(it["ref"])):
				return _node_frame(_spot_nodes[str(it["ref"])])
		"floor":
			if _floor_nodes.has(item_id):
				return _node_frame(_floor_nodes[item_id])
		"wheel":
			# A tyre on a loose wheel is drawn with it.
			return item_frame(int(it["ref"]))
	return {}


## {xf, box} round a piece of equipment, for pings.
func furniture_frame(id: int) -> Dictionary:
	if furniture_nodes.has(id):
		return _node_frame(furniture_nodes[id])
	return {}


## The node to remove for a spot's display: its hook swing, if it hangs from one.
func _drop_spot_node(n: Node) -> Node:
	return n.get_parent() if n.get_parent() is Swing else n


func _node_frame(node: Node3D) -> Dictionary:
	var box := AABB()
	var first := true
	var stack: Array = [[node, Transform3D()]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Node = top[0]
		var xf: Transform3D = top[1]
		for child in n.get_children():
			if child is Node3D:
				var cxf: Transform3D = xf * (child as Node3D).transform
				if child is VisualInstance3D and not (child is Label3D):
					var b: AABB = cxf * (child as VisualInstance3D).get_aabb()
					box = b if first else box.merge(b)
					first = false
				stack.append([child, cxf])
	if first:
		return {}
	return {"xf": node.global_transform, "box": box, "node": node}


## The model drawn for a parked bike (inside its lean pivot).
func bike_model(id: int) -> BikeModel:
	return bike_views[id].get_child(0).get_child(0) as BikeModel


## Every part within `radius` of a point: fitted to parked bikes, on the engine stand, on the
## work spots or put down anywhere. Used by the brush to scrub everything it touches.
func items_near(at: Vector3, radius: float) -> Array:
	var out := []
	for id in bike_views:
		var model: BikeModel = bike_model(id)
		for slot in PartsDB.SLOTS:
			var item := Shed.item_at_target({"bike": id, "slot": slot})
			if item != 0 and _near(model, model.slot_bounds(slot), at, radius):
				out.append(item)
	for spot in _spot_nodes:
		var node: Node3D = _spot_nodes[spot]
		var item := Shed.item_at_spot(spot)
		var model: BikeModel = node.get_meta("model") if node.has_meta("model") else null
		if Shed.is_engine(item) and model:
			for slot in PartsDB.ENGINE_SLOTS:
				var sub := Shed.engine_item(item, slot)
				if sub != 0 and _near(model, model.slot_bounds(slot), at, radius):
					out.append(sub)
			if _near(model, model.slot_bounds("engine"), at, radius):
				out.append(item)
		elif item != 0 and node.global_position.distance_to(at) < radius + 0.3:
			out.append(item)
			if Shed.tyre_on_wheel(item) != 0:
				out.append(Shed.tyre_on_wheel(item))
	for id in _floor_nodes:
		var node: Node3D = _floor_nodes[id]
		var size: Vector3 = node.get_meta("size", Vector3.ONE * 0.3)
		if (node.global_position + Vector3.UP * size.y * 0.5).distance_to(at) < radius + size.length() * 0.5:
			out.append(id)
			if Shed.tyre_on_wheel(id) != 0:
				out.append(Shed.tyre_on_wheel(id))
	return out


func _near(model: BikeModel, box: AABB, at: Vector3, radius: float) -> bool:
	if box.size == Vector3.ZERO:
		return false
	var local := model.global_transform.affine_inverse() * at
	var closest := local.clamp(box.position, box.end)
	return closest.distance_to(local) < radius


func _item_signature(item_id: int) -> String:
	var it: Dictionary = Shed.items[item_id]
	var sig := "%d:%s:%.1f:%.1f:%.1f:%s:%s:%s" % [item_id, it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", ""),
		"%.1f" % float(it["fluid"]["litres"]) if it.has("fluid") and PartsDB.is_fluid(it["part"]) else ""]
	if Shed.is_engine(item_id):
		for slot in PartsDB.ENGINE_SLOTS:
			var sub := Shed.engine_item(item_id, slot)
			sig += "|" + ("-" if sub == 0 else _item_signature(sub) + str(Shed.engine_bolted(item_id, slot)))
	var tyre := Shed.tyre_on_wheel(item_id)
	if tyre != 0:
		sig += "|tyre " + _item_signature(tyre)
	return sig


func _bike_signature(id: int) -> String:
	var bike: Dictionary = Shed.bikes[id]
	var parts := []
	for slot in PartsDB.SLOTS:
		var item_id := Shed.item_on(id, slot)
		if item_id == 0:
			parts.append("-")
		else:
			var it: Dictionary = Shed.items[item_id]
			parts.append("%s:%.1f:%.1f:%.1f:%s:%s:%s" % [it["part"], it["rust"], it["dirt"], it["wear"], it["color"], it.get("finish", ""), Shed.is_bolted(id, slot)])
	var pose := "paddock" if Shed.on_paddock(id) and bike.get("pusher", 0) == 0 else str(bike.get("stand", ""))
	# Its own fit (geometry mode) and any blueprint it's being built to redraw it too.
	return "%s|%s|%s|%s|%s" % [",".join(parts), pose, str(bike["paint"]), str(Shed.geometry_of(id)),
		str(bike.get("blueprint", {}).get("parts", "")) if bike.get("blueprint") is Dictionary else ""]


func _make_bike_view(id: int) -> Node3D:
	var bike: Dictionary = Shed.bikes[id]
	var view := Node3D.new()
	view.name = "Bike%d" % id
	view.transform = bike["xf"]
	add_child(view)
	var build := Shed.build_of(id)
	var model := BikeModel.new()
	# Leaning on its side stand, or lying on its side, the bike tips over about the tyres' contact line.
	var lean := Node3D.new()
	view.add_child(lean)
	lean.add_child(model)
	var on_stand: bool = Shed.on_paddock(id) and bike.get("pusher", 0) == 0
	var stand := "" if on_stand else str(bike.get("stand", ""))
	var lift := 0.06 if on_stand else 0.0
	if stand == "centre":
		lift = build.centre_lift
	elif stand == "side":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(float(PartsDB.get_part(build.parts["side_stand"]).get("lean", 12.0))))
	elif stand == "down":
		lean.basis = Basis(Vector3.BACK, deg_to_rad(74.0))
		lift = 0.12
	model.position.y = build.rear_radius + lift
	model.stand_pose = stand
	model.geometry = Shed.geometry_of(id)
	model.build_from(build, bike["paint"], Shed.fitted_map(id), build.condition, false)
	model.build_pickers({"bike": id})
	if on_stand:
		_paddock_stand(view, build)
	var plan = bike.get("blueprint")
	if plan is Dictionary:
		# Being built to a blueprint: the parts still to go on show as a hologram, in place.
		var show := {}
		for slot in PartsDB.SLOTS:
			show[slot] = Shed.item_on(id, slot) == 0 and str(plan["parts"].get(slot, "none")) != "none"
		var ghost := ghost_model(plan, show)
		ghost.position = model.position
		lean.add_child(ghost)
	return view


## A blueprint drawn as a flickering blue hologram, only the slots in `show` (all when empty).
func ghost_model(plan: Dictionary, show := {}) -> BikeModel:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ghost_mat.albedo_color = Color(0.25, 0.6, 1.0, 0.35)
	var build := BikeBuild.new(PartsDB.sanitize_build(plan.get("parts", {}).duplicate()))
	var ghost := BikeModel.new()
	ghost.name = "Hologram"
	ghost.geometry = GeoGizmo.sanitize(plan.get("geo", {}))
	ghost.build_from(build, plan.get("paint", Color.WHITE) if plan.get("paint") is Color else Color.WHITE, show, null, false)
	ghost.make_ghost(_ghost_mat)
	ghost.set_meta("hologram", true)
	_ghosts += 1
	return ghost


## Bays with a blueprint build waiting for its frame show the whole bike as a hologram.
func _sync_holograms() -> void:
	for bay in _holo_views.keys():
		if not Shed.holograms.has(bay):
			_holo_views[bay].queue_free()
			_holo_views.erase(bay)
			_holo_sigs.erase(bay)
			_ghosts = maxi(0, _ghosts - 1)
	for bay in Shed.holograms:
		var plan: Dictionary = Shed.holograms[bay]
		var sig := str(plan.get("parts", {})) + str(plan.get("geo", {})) + str(plan.get("name", ""))
		if _holo_sigs.get(bay, "") == sig:
			continue
		_holo_sigs[bay] = sig
		if _holo_views.has(bay):
			_holo_views[bay].free()
			_ghosts = maxi(0, _ghosts - 1)
		var view := Node3D.new()
		view.name = "Hologram%d" % bay
		view.transform = bay_transform(int(bay))
		add_child(view)
		var ghost := ghost_model(plan)
		ghost.position.y = BikeBuild.new(PartsDB.sanitize_build(plan.get("parts", {}).duplicate())).rear_radius + 0.06
		view.add_child(ghost)
		var label := Label3D.new()
		label.text = "BLUEPRINT: %s\nPut a frame on the stand to start" % str(plan.get("name", "")).to_upper()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 1.75, 0.0)
		label.font_size = 40
		label.pixel_size = 0.005
		label.outline_size = 8
		label.modulate = Color(0.55, 0.8, 1.0)
		view.add_child(label)
		_holo_views[bay] = view


## The holograms' flicker: a soft shimmer with the odd dip, like a projector.
func _flicker_holograms() -> void:
	if _ghost_mat == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var a := 0.3 + 0.06 * sin(t * 7.0) + 0.04 * sin(t * 23.0)
	if fmod(t, 3.7) < 0.08:
		a *= 0.4
	_ghost_mat.albedo_color.a = a


func _paddock_stand(parent: Node3D, build: BikeBuild) -> void:
	var steel: Material = _mats["stand"]
	for z in [-build.wheelbase * 0.5 + 0.12, build.wheelbase * 0.5 - 0.15]:
		_deco(parent, Vector3(0.0, 0.03, z), Vector3(0.5, 0.06, 0.08), steel)
		for side in [-1.0, 1.0]:
			_deco(parent, Vector3(0.22 * side, build.rear_radius * 0.5, z), Vector3(0.04, build.rear_radius, 0.04), steel)
	_deco(parent, Vector3(0.0, build.rear_radius - 0.06, 0.0), Vector3(0.12, 0.12, build.wheelbase * 0.55), steel)


func _process(delta: float) -> void:
	_flicker_holograms()
	_update_tv_feed(delta)
	_update_door(delta)
	spin_changers(delta)
	if _lights_shown != Shed.lights_on:
		set_lights(Shed.lights_on)
	for room in _room_lights:
		if _room_shown.get(room, null) != Shed.room_lit(room):
			set_room_lights(room, Shed.room_lit(room))
	_dash_timer -= delta
	if _dash_timer > 0.0:
		return
	_dash_timer = 0.5
	_refresh_dashboards()


## Turns a tyre changer's turntable, with the wheel on it, while someone works a tyre on or off,
## and rocks the mount head as it levers the bead over the rim.
func spin_changers(delta: float) -> void:
	for id in furniture_nodes:
		var view: EquipmentView = furniture_nodes[id]
		if view.kind != "changer":
			continue
		var busy := changer_turning(id)
		var table: Node3D = view.get_node_or_null("Turntable")
		var head: Node3D = view.get_node_or_null("Head")
		if table and busy:
			table.rotation.y = wrapf(table.rotation.y + delta * 2.2, 0.0, TAU)
		if head:
			var t := Time.get_ticks_msec() / 1000.0
			head.rotation.x = sin(t * 9.0) * 0.06 if busy else lerpf(head.rotation.x, 0.0, minf(1.0, delta * 6.0))


## Whether a tyre changer's turntable is turning (someone is working a tyre on it).
func changer_turning(id: int) -> bool:
	for peer in Shed.crew:
		if int(Shed.crew[peer].get("changer", 0)) == id and str(Shed.crew[peer].get("activity", "")) != "":
			return true
	return false


func _refresh_dashboards() -> void:
	if not Shed.active:
		return
	var bays_dirty := _dash_dirty
	_dash_dirty = false
	var riders := Shed.riders()
	var pages := {}    # channel -> its page data, worked out once for every screen on it
	var all := screens()
	for key in all:
		var dash: Dashboard = all[key]
		var state := Shed.screen_channel(key)
		var ch: String = state["ch"]
		var shown := "%s:%d" % [ch, TvChannels.live_rider(state, riders) if ch == "live" else 0]
		var changed: bool = _screen_shown.get(key, shown) != shown
		if changed:
			dash.show_osd(TvChannels.osd_label(key, state, riders))
		if not _screen_shown.has(key):
			changed = true
		_screen_shown[key] = shown
		match ch:
			"bay":
				if bays_dirty or changed:
					dash.show_page("bike", _bay_data(int(key.trim_prefix("bay"))))
			"crew":
				dash.show_page("crew", {"players": _crew_rows()})
			_:
				if ch == "live" and dash.is_live():
					continue
				if not pages.has(ch):
					pages[ch] = TvChannels.page_data(ch)
				dash.show_page(TvChannels.page_kind(ch), pages[ch])


## The crew board's rows: everyone here and what they're up to.
func _crew_rows() -> Array:
	var players := []
	var ids: Array = Shed.crew.keys()
	ids.sort()
	for peer in ids:
		var c: Dictionary = Shed.crew[peer]
		var doing := str(c.get("activity", ""))
		var riding := int(c.get("riding", 0))
		if riding != 0 and Shed.bikes.has(riding):
			doing = "Riding %s, %s" % [Shed.bikes[riding]["name"], Units.kmh(float(c.get("kmh", 0.0)))]
		elif Shed.held_by(peer) != 0:
			doing = "Carrying " + Shed.item_title(Shed.held_by(peer))
		elif doing == "":
			doing = "Holding the %s" % Walker.TOOL_NAMES.get(c.get("tool", "hands"), "hands").to_lower() if c.get("tool", "hands") != "hands" else "Looking around"
		var p := c.duplicate()
		p["doing"] = doing
		p["color"] = Shed.PAINTS[int(c.get("slot", 0)) % Shed.PAINTS.size()]
		players.append(p)
	return players


func _bay_data(bay: int) -> Dictionary:
	var bike_id := 0
	for id in Shed.bikes:
		if Shed.bikes[id]["bay"] == bay:
			bike_id = id
			if Shed.bikes[id]["xf"].origin.distance_to(bay_transform(bay).origin) < 2.5:
				break
	var plan := Shed.plan_at(bay)
	if not plan.is_empty():
		return _blueprint_data(plan, Shed.plan_bike(bay))
	if bike_id == 0:
		return {}
	var bike: Dictionary = Shed.bikes[bike_id]
	var build := Shed.build_of(bike_id)
	var missing := Shed.missing_slots(bike_id)
	var loose := Shed.loose_slots(bike_id)
	var status := "READY TO RIDE"
	if bike["rider"] != 0:
		status = "OUT RIDING: %s" % Shed.crew.get(bike["rider"], {}).get("name", "someone")
	elif not missing.is_empty():
		status = "%d PART%s MISSING" % [missing.size(), "" if missing.size() == 1 else "S"]
	elif not loose.is_empty():
		status = "%d PART%s LOOSE" % [loose.size(), "" if loose.size() == 1 else "S"]
	var parts := []
	var has_engine := Shed.item_on(bike_id, "engine") != 0
	for slot in PartsDB.SLOTS:
		if PartsDB.is_engine_slot(slot) and not has_engine:
			continue
		var item_id := Shed.item_on(bike_id, slot)
		if item_id == 0 and PartsDB.is_optional(slot):
			continue
		var name: String = PartsDB.slot_name(slot)
		if slot == "engine" and not has_engine:
			name = "Engine (out)"
		parts.append({"name": name, "fitted": item_id != 0, "bolted": Shed.is_bolted(bike_id, slot),
			"health": BikeBuild.part_health(Shed.condition_of(Shed.items[item_id])) if item_id != 0 else 0.0})
	var fluids := [
		["Fuel", build.fuel_litres / maxf(build.fuel_capacity, 0.1), build.fuel_age],
		["Oil", build.oil_litres / maxf(build.oil_capacity, 0.1) if has_engine else 0.0, build.oil_age],
		["Brake F", build.brake_fluid["front"], 0.0],
		["Brake R", build.brake_fluid["rear"], 0.0],
	]
	return {"name": bike["name"], "status": status, "now": build.summary(), "delivered": bike["delivered"], "parts": parts,
		"notes": build.notes, "fluids": fluids, "range_km": build.range_km()}


## A bay screen's blueprint page: the parts the build needs and how far it's got.
func _blueprint_data(plan: Dictionary, bike_id: int) -> Dictionary:
	var rows := Shed.plan_rows(plan, bike_id)
	var done := rows.filter(func(r): return r["state"] in ["fitted", "other"]).size()
	var price := 0
	for r in rows:
		if r["state"] == "needed":
			price += Shed.part_price(str(r["part"]))
	return {"name": str(plan.get("name", "Blueprint")), "blueprint": rows, "done": done, "price": price,
		"status": "BLUEPRINT BUILD: %d OF %d PARTS" % [done, rows.size()], "framed": bike_id != 0}


# ---------------------------------------------------------------------------- building

func _make_materials() -> void:
	_mats["floor"] = _material(Color(0.36, 0.37, 0.38), 0.0, 0.3, _noise(0.08, 0.92, 1.04), 6.0)
	_mats["wall_in"] = _material(Color(0.78, 0.76, 0.72), 0.0, 0.85, _noise(0.2, 0.9, 1.04), 2.0)
	_mats["wall_low"] = _material(Color(0.2, 0.24, 0.27), 0.0, 0.6)
	var cladding := _material(Color(0.3, 0.33, 0.36), 0.7, 0.45)
	cladding.normal_enabled = true
	cladding.normal_texture = _corrugation()
	cladding.normal_scale = 1.0
	cladding.uv1_triplanar = true
	cladding.uv1_scale = Vector3(2.5, 2.5, 2.5)
	_mats["cladding"] = cladding
	_mats["roof"] = _material(Color(0.25, 0.27, 0.29), 0.6, 0.5)
	_mats["steel"] = _material(Color(0.3, 0.32, 0.35), 0.85, 0.35)
	_mats["stand"] = _material(Color(0.85, 0.35, 0.05), 0.5, 0.4)
	_mats["wood"] = _material(Color(0.5, 0.36, 0.22), 0.0, 0.7, _noise(0.5, 0.85, 1.08), 3.0)
	_mats["yellow"] = _material(Color(0.95, 0.75, 0.05), 0.0, 0.5)
	_mats["dark"] = _material(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	_mats["box"] = _material(Color(0.62, 0.47, 0.3), 0.0, 0.9, _noise(0.6, 0.9, 1.05), 2.0)
	_mats["blue"] = _material(Color(0.1, 0.3, 0.65), 0.6, 0.35)
	_mats["red"] = _material(Color(0.7, 0.08, 0.06), 0.5, 0.35)
	_mats["chrome"] = _material(Color(0.85, 0.86, 0.88), 1.0, 0.15)


func _material(color: Color, metallic: float, roughness: float, tex: Texture2D = null, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv) * 0.25
	return m


func _noise(freq: float, dark: float, light: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.1
	noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(dark, dark, dark))
	ramp.set_color(1, Color(light, light, light))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


## A normal map of vertical ridges, for corrugated steel cladding.
func _corrugation() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.5, 1.0))
	g.set_color(1, Color(0.5, 0.5, 1.0))
	g.add_point(0.25, Color(0.9, 0.5, 0.85))
	g.add_point(0.75, Color(0.1, 0.5, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.repeat = GradientTexture2D.REPEAT
	return tex


func _solid(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta("surface", "tarmac")
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
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


## Invisible collision, so players can't walk through furniture made of loose meshes.
func _blocker(center: Vector3, size: Vector3, parent: Node3D = self) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


## An invisible click target for the player's hands and tools.
func _target(center: Vector3, size: Vector3, meta: Dictionary, parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = INTERACT_LAYER
	body.collision_mask = 0
	body.position = center
	for key in meta:
		body.set_meta(key, meta[key])
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


## A small printed sign pinned to the wall behind a work area, instead of big floating letters.
func _poster(text: String, pos: Vector3, rot_y: float, size := Vector2(0.56, 0.2)) -> void:
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	paper.mesh = quad
	paper.material_override = _material(Color(0.86, 0.82, 0.7), 0.0, 0.9)
	paper.position = pos
	paper.rotation.y = rot_y
	add_child(paper)
	var ink := Label3D.new()
	ink.text = text
	ink.font_size = 40
	ink.pixel_size = 0.0018
	ink.modulate = Color(0.15, 0.12, 0.1)
	ink.outline_size = 0
	ink.position = Vector3(0.0, 0.0, 0.004)
	paper.add_child(ink)


func _label(text: String, pos: Vector3, rot_y: float, size := 32, color := Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 6
	add_child(l)
	return l


func _build_shell() -> void:
	var c := CENTER
	var hx := HALF.x
	var hz := HALF.y
	var t := 0.3
	# Floor: a polished epoxy slab sitting on the yard concrete, with bay markings.
	var floor_mi := _deco(self, c + Vector3(0.0, 0.004, 0.0), Vector3(hx * 2.0, 0.008, hz * 2.0), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Walls: back (with the doorway to the dyno room), sides, and the front wall either side of
	# the roller door.
	var back_w := hx + t - DynoRoom.DOOR_HALF
	var walls := [
		[c + Vector3(0.0, (HEIGHT + DynoRoom.DOOR_HEIGHT) * 0.5, -hz - t * 0.5), Vector3(DynoRoom.DOOR_HALF * 2.0, HEIGHT - DynoRoom.DOOR_HEIGHT, t)],
	]
	# The side walls, each with a doorway: the storage room to the west, the paint shop east.
	for side in [-1.0, 1.0]:
		var door_z: float = STORE_DOOR_Z if side < 0.0 else PAINT_DOOR_Z
		for seg in _wall_runs(c.z - hz, c.z + hz, door_z, SIDE_DOOR_HALF):
			walls.append([Vector3(c.x + side * (hx + t * 0.5), HEIGHT * 0.5, seg[0]), Vector3(t, HEIGHT, seg[1])])
		walls.append([Vector3(c.x + side * (hx + t * 0.5), (HEIGHT + SIDE_DOOR_HEIGHT) * 0.5, door_z), Vector3(t, HEIGHT - SIDE_DOOR_HEIGHT, SIDE_DOOR_HALF * 2.0)])
	var side_w := hx - DOOR_HALF
	for side in [-1.0, 1.0]:
		walls.append([c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5, hz + t * 0.5), Vector3(side_w + t, HEIGHT, t)])
		walls.append([c + Vector3(side * (DynoRoom.DOOR_HALF + back_w * 0.5), HEIGHT * 0.5, -hz - t * 0.5), Vector3(back_w, HEIGHT, t), side > 0.0])
	walls.append([c + Vector3(0.0, (HEIGHT + DOOR_HEIGHT) * 0.5, hz + t * 0.5), Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_HEIGHT, t)])
	for w in walls:
		var body := _solid(w[0], w[1], _mats["cladding"])
		if w.size() > 2 and w[2]:
			knock["wing"].append(body)   # the extension's doorway goes through here
	# Inside faces: painted plaster upper, dark lower band; the back wall's round the doorway.
	var in_w := hx - DynoRoom.DOOR_HALF
	for side in [-1.0, 1.0]:
		var x: float = side * (DynoRoom.DOOR_HALF + in_w * 0.5)
		var upper := _deco(self, c + Vector3(x, HEIGHT * 0.5 + 0.6, -hz + 0.01), Vector3(in_w, HEIGHT - 1.2, 0.02), _mats["wall_in"])
		var lower := _deco(self, c + Vector3(x, 0.6, -hz + 0.01), Vector3(in_w, 1.2, 0.02), _mats["wall_low"])
		if side > 0.0:
			knock["wing"].append_array([upper, lower])
	_deco(self, c + Vector3(0.0, (HEIGHT + DynoRoom.DOOR_HEIGHT) * 0.5, -hz + 0.01), Vector3(DynoRoom.DOOR_HALF * 2.0, HEIGHT - DynoRoom.DOOR_HEIGHT, 0.02), _mats["wall_in"])
	for side in [-1.0, 1.0]:
		var door_z: float = STORE_DOOR_Z if side < 0.0 else PAINT_DOOR_Z
		var wx: float = c.x + side * (hx - 0.01)
		for seg in _wall_runs(c.z - hz, c.z + hz, door_z, SIDE_DOOR_HALF):
			_deco(self, Vector3(wx, HEIGHT * 0.5 + 0.6, seg[0]), Vector3(0.02, HEIGHT - 1.2, seg[1]), _mats["wall_in"])
			_deco(self, Vector3(wx, 0.6, seg[0]), Vector3(0.02, 1.2, seg[1]), _mats["wall_low"])
		_deco(self, Vector3(wx, (HEIGHT + SIDE_DOOR_HEIGHT) * 0.5, door_z), Vector3(0.02, HEIGHT - SIDE_DOOR_HEIGHT, SIDE_DOOR_HALF * 2.0), _mats["wall_in"])
		# Hazard-yellow frame round the doorway, through the wall's thickness.
		var fx: float = c.x + side * (hx + t * 0.5)
		for end in [-1.0, 1.0]:
			_deco(self, Vector3(fx, SIDE_DOOR_HEIGHT * 0.5, door_z + end * (SIDE_DOOR_HALF + 0.05)), Vector3(t + 0.06, SIDE_DOOR_HEIGHT, 0.1), _mats["yellow"])
		_deco(self, Vector3(fx, SIDE_DOOR_HEIGHT + 0.05, door_z), Vector3(t + 0.06, 0.1, SIDE_DOOR_HALF * 2.0 + 0.2), _mats["yellow"])
		var door_sign := _label("STORAGE" if side < 0.0 else "PAINT SHOP", Vector3(c.x + side * (hx - 0.03), SIDE_DOOR_HEIGHT + 0.35, door_z),
			-side * PI * 0.5, 44, Color(0.08, 0.08, 0.08))
		door_sign.outline_size = 0
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5 + 0.6, hz - 0.01), Vector3(side_w, HEIGHT - 1.2, 0.02), _mats["wall_in"])
		_deco(self, c + Vector3(side * (DOOR_HALF + side_w * 0.5), 0.6, hz - 0.01), Vector3(side_w, 1.2, 0.02), _mats["wall_low"])
		# Hazard-yellow door posts.
		_deco(self, c + Vector3(side * (DOOR_HALF + 0.08), DOOR_HEIGHT * 0.5, hz + 0.02), Vector3(0.16, DOOR_HEIGHT, t + 0.08), _mats["yellow"])
	# Roof with steel trusses.
	_solid(c + Vector3(0.0, HEIGHT + 0.15, 0.0), Vector3(hx * 2.0 + 1.0, 0.3, hz * 2.0 + 1.0), _mats["roof"])
	for i in 5:
		var z := -hz + 0.8 + i * (hz * 2.0 - 1.6) / 4.0
		_deco(self, c + Vector3(0.0, HEIGHT - 0.2, z), Vector3(hx * 2.0, 0.18, 0.1), _mats["steel"])
	# The roller door, rolled up into its drum above the opening.
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = DOOR_HALF * 2.0 + 0.3
	drum.mesh = cyl
	drum.material_override = _mats["cladding"]
	drum.position = c + Vector3(0.0, DOOR_HEIGHT + 0.34, hz - 0.38)
	drum.rotation.z = PI * 0.5
	add_child(drum)
	_deco(self, c + Vector3(0.0, DOOR_HEIGHT + 0.02, hz - 0.08), Vector3(DOOR_HALF * 2.0, 0.08, 0.1), _mats["dark"])
	# Sign over the door.
	var sign := Label3D.new()
	sign.text = "TORQUE SHED"
	sign.font_size = 110
	sign.outline_size = 18
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.position = c + Vector3(0.0, DOOR_HEIGHT + 0.6, hz + t + 0.05)
	sign.pixel_size = 0.008
	add_child(sign)
	# Painted bay boxes and a walkway line.
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		for side in [-1.0, 1.0]:
			_deco(self, xf.origin + Vector3(side * 1.5, 0.01, 0.4), Vector3(0.06, 0.004, 3.1), _mats["yellow"])
		_label("BAY %d" % (bay + 1), xf.origin + Vector3(0.0, 0.012, 1.75), 0.0, 72, Color(0.95, 0.8, 0.2)).rotation.x = -PI * 0.5
	_deco(self, c + Vector3(0.0, 0.01, -1.4), Vector3(hx * 2.0 - 3.0, 0.004, 0.06), _mats["yellow"])


func _build_bays() -> void:
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		# Full-width screens, in pairs either side of the dyno room doorway between bays 2 and 3.
		var inner := absf(xf.origin.x - CENTER.x) < 2.0
		var screen := Dashboard.new("bike", BAY_SCREEN_INNER if inner else BAY_SCREEN_OUTER)
		screen.position = Vector3(CENTER.x + float(BAY_SCREEN_X[bay]), 2.45, CENTER.z - HALF.y + 0.1)
		add_child(screen)
		_bay_screens.append(screen)
		_screen_target(screen, "bay%d" % bay)


func _build_bench() -> void:
	var x := CENTER.x - HALF.x + 0.5
	var z_from := spot_transform("bench_0").origin.z - 0.6
	var z_to := spot_transform("bench_3").origin.z + 0.6
	var mid := (z_from + z_to) * 0.5
	var length := z_to - z_from
	# Solid up to just under the wooden top, so a trinket put down on it sits on the wood.
	_solid(Vector3(x, 0.4725, mid), Vector3(0.9, 0.945, length), _mats["steel"])
	_deco(self, Vector3(x, 0.92, mid), Vector3(0.95, 0.06, length + 0.05), _mats["wood"])
	for i in 3:
		_deco(self, Vector3(x + 0.46, 0.25 + i * 0.25, mid), Vector3(0.02, 0.2, length - 0.2), _mats["red"])
	# Parts go down anywhere along the top (see Shed.surface); each one has its own box to pick it up by.
	_target(Vector3(x, spot_transform("bench_0").origin.y + 0.015, mid), Vector3(0.95, 0.03, length), {"top": "bench"})
	_poster("WORKBENCH", Vector3(CENTER.x - HALF.x + 0.012, 1.32, spot_transform("bench_3").origin.z + 0.2), PI * 0.5)


## The parts computer, Car Dealer Simulator style: order anything, it arrives on a pallet.
func _build_computer() -> void:
	var pos := CENTER + Vector3(HALF.x - 0.45, 0.0, 1.9)
	_solid(pos + Vector3(0.0, 0.37, 0.0), Vector3(0.75, 0.74, 1.3), _mats["wood"])
	_deco(self, pos + Vector3(0.0, 0.76, 0.0), Vector3(0.8, 0.04, 1.35), _mats["dark"])
	var monitor := _deco(self, pos + Vector3(0.12, 1.1, 0.0), Vector3(0.05, 0.42, 0.68), _mats["dark"])
	monitor.name = "Monitor"
	var screen_mat := _material(Color(0.1, 0.3, 0.5), 0.0, 0.3)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.25, 0.6, 1.0)
	screen_mat.emission_energy_multiplier = 1.4
	_deco(self, pos + Vector3(0.09, 1.1, 0.0), Vector3(0.01, 0.36, 0.62), screen_mat)
	_deco(self, pos + Vector3(0.16, 0.86, 0.0), Vector3(0.06, 0.18, 0.06), _mats["dark"])
	_deco(self, pos + Vector3(-0.15, 0.79, 0.0), Vector3(0.18, 0.02, 0.45), _mats["dark"])  # keyboard
	var title := _label("PARTS", pos + Vector3(0.08, 1.22, 0.0), -PI * 0.5, 40, Color(0.7, 0.9, 1.0))
	title.outline_size = 0
	_label("Order anything", pos + Vector3(0.08, 1.08, 0.0), -PI * 0.5, 20, Color(0.7, 0.9, 1.0)).outline_size = 0
	_target(pos + Vector3(0.0, 1.0, 0.0), Vector3(0.8, 0.6, 1.3), {"pc": true})


## Deliveries are left outside, to the side of the roller door: a painted bay on the yard (see
## Shed.DELIVERY_AREA), boxes packed on its front part and the delivery racking (equipment the
## shed comes with) along the back, with a hatched aisle in front of the racking.
func _build_delivery_area() -> void:
	var paint := _material(Color(0.85, 0.7, 0.2), 0.0, 0.8)
	var area: Rect2 = Shed.DELIVERY_AREA
	var c := Vector3(area.get_center().x, 0.0, area.get_center().y)
	var w := area.size.x + 0.2
	var d := area.size.y + 0.2
	for side in [-1.0, 1.0]:
		_deco(self, c + Vector3(side * w * 0.5, 0.005, 0.0), Vector3(0.08, 0.01, d), paint)
		_deco(self, c + Vector3(0.0, 0.005, side * d * 0.5), Vector3(w, 0.01, 0.08), paint)
	# The aisle in front of the racking, kept clear: hatched.
	var floor_end: float = Shed.DELIVERY_FLOOR.end.y + 0.05
	_deco(self, Vector3(c.x, 0.005, floor_end), Vector3(w, 0.01, 0.06), paint)
	var aisle := Shed.DELIVERY_RACK_XFS[0].origin.z - 0.35 - floor_end
	for i in int(area.size.x / 0.6):
		var stripe := _deco(self, Vector3(area.position.x + 0.3 + i * 0.6, 0.005, floor_end + aisle * 0.5), Vector3(0.06, 0.01, aisle * 1.2), paint)
		stripe.rotation.y = 0.6
	var mark := _label("DELIVERIES", Vector3(c.x, 0.012, area.position.y - 0.45), 0.0, 64, Color(0.85, 0.7, 0.2, 0.8))
	mark.rotation = Vector3(-PI * 0.5, PI, 0.0)
	mark.outline_size = 0


## The shed's bins against the front wall, left of the roller door: general waste (black), and
## recycling for plastic (blue) and metal (green). Hold a part and look at one to throw it away.
func _build_bin() -> void:
	for which in BINS:
		var x: float = BINS[which][0]
		var color: Color = BINS[which][1]
		var pos := CENTER + Vector3(x, 0.0, HALF.y - BIN_SIZE.z * 0.5 - 0.03)
		var body := _material(color, 0.1, 0.55)
		_solid(pos + Vector3(0.0, BIN_SIZE.y * 0.5 - 0.02, 0.0), BIN_SIZE - Vector3(0.0, 0.04, 0.0), body)
		# Lid with an overhang and a handle at the back, wheels at the bottom.
		_deco(self, pos + Vector3(0.0, BIN_SIZE.y - 0.01, -0.02), Vector3(BIN_SIZE.x + 0.04, 0.04, BIN_SIZE.z + 0.06), _material(color.lightened(0.12), 0.1, 0.45))
		_deco(self, pos + Vector3(0.0, BIN_SIZE.y - 0.06, BIN_SIZE.z * 0.5 + 0.02), Vector3(BIN_SIZE.x - 0.06, 0.04, 0.04), _material(color.darkened(0.3), 0.1, 0.5))
		for side in [-1.0, 1.0]:
			var wheel := _deco(self, pos + Vector3(side * (BIN_SIZE.x * 0.5 - 0.06), 0.08, BIN_SIZE.z * 0.5 - 0.06), Vector3(0.05, 0.16, 0.16), _mats["dark"])
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A white label on the front (facing into the shed) saying what goes in.
		var front := pos + Vector3(0.0, 0.58, -BIN_SIZE.z * 0.5 - 0.006)
		var plate := _deco(self, front, Vector3(BIN_SIZE.x - 0.08, 0.26, 0.01), _material(Color(0.95, 0.95, 0.93), 0.0, 0.7))
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var title := Label3D.new()
		title.text = "GENERAL\nWASTE" if which == "general" else which.to_upper()
		title.font_size = 44
		title.pixel_size = 0.0021
		title.modulate = color.darkened(0.2) if which != "general" else Color(0.1, 0.1, 0.1)
		title.outline_size = 0
		title.position = front + Vector3(0.0, 0.03 if which != "general" else 0.0, -0.007)
		title.rotation.y = PI
		add_child(title)
		if which != "general":
			var sub := Label3D.new()
			sub.text = "RECYCLING"
			sub.font_size = 26
			sub.pixel_size = 0.0021
			sub.modulate = Color(0.25, 0.25, 0.25)
			sub.outline_size = 0
			sub.position = front + Vector3(0.0, -0.07, -0.007)
			sub.rotation.y = PI
			add_child(sub)
		_target(pos + Vector3(0.0, BIN_SIZE.y * 0.5 - 0.02, 0.0), BIN_SIZE + Vector3(0.04, 0.0, 0.04), {"bin": which})


## A wall shelf over the back end of the workbench with the shed radio on it.
func _build_radio() -> void:
	var x := CENTER.x - HALF.x
	var z := spot_transform("bench_0").origin.z - 0.25
	_deco(self, Vector3(x + 0.17, 1.6, z), Vector3(0.34, 0.03, 0.6), _mats["wood"])
	for dz in [-0.22, 0.22]:
		_deco(self, Vector3(x + 0.04, 1.52, z + dz), Vector3(0.03, 0.14, 0.03), _mats["steel"])
	radio = ShedRadio.new()
	radio.position = Vector3(x + 0.19, 1.615, z)
	radio.rotation.y = PI * 0.5
	add_child(radio)


## A lean-to wash bay on the west side of the shed, open to the yard: a concrete pad with a
## drain, a pressure washer on the back wall and a strip light. Ride or wheel a muddy bike in
## and blast it clean with the pressure washer (tool 6).
func _build_wash_bay() -> void:
	var c := WASH_CENTER
	var hx := WASH_HALF.x
	var hz := WASH_HALF.y
	var h := 3.0
	var pad := _material(Color(0.42, 0.44, 0.45), 0.0, 0.25, _noise(0.3, 0.85, 1.05), 4.0)
	var floor_mi := _deco(self, c + Vector3(0.0, 0.006, 0.0), Vector3(hx * 2.0, 0.012, hz * 2.0), pad)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_deco(self, c + Vector3(0.0, 0.014, 0.6), Vector3(1.6, 0.006, 0.2), _mats["dark"]).name = "Drain"
	# Back and outer walls (the shed wall is the inner side); open to the yard at the front.
	_solid(c + Vector3(0.0, h * 0.5, -hz - 0.1), Vector3(hx * 2.0 + 0.2, h, 0.2), _mats["cladding"])
	_solid(c + Vector3(-hx - 0.1, h * 0.5, 0.0), Vector3(0.2, h, hz * 2.0 + 0.2), _mats["cladding"])
	var tiles := _material(Color(0.82, 0.86, 0.88), 0.0, 0.2)
	_deco(self, c + Vector3(0.0, 1.0, -hz + 0.005), Vector3(hx * 2.0, 2.0, 0.01), tiles)
	_deco(self, c + Vector3(-hx + 0.005, 1.0, 0.0), Vector3(0.01, 2.0, hz * 2.0), tiles)
	_solid(c + Vector3(0.0, h + 0.08, 0.0), Vector3(hx * 2.0 + 0.4, 0.12, hz * 2.0 + 0.4), _mats["roof"])
	_deco(self, c + Vector3(-hx + 0.1, h * 0.5, hz - 0.1), Vector3(0.12, h, 0.12), _mats["yellow"])
	_deco(self, c + Vector3(0.0, h - 0.1, hz - 0.05), Vector3(hx * 2.0, 0.2, 0.1), _mats["yellow"])
	var sign := _label("WASH BAY", c + Vector3(0.0, h - 0.1, hz + 0.02), 0.0, 64, Color(0.08, 0.08, 0.08))
	sign.outline_size = 0
	# The pressure washer: a yellow trolley unit with a hose reel, against the back wall.
	var unit := WASH_POS
	_solid(unit + Vector3(0.0, 0.45, 0.0), Vector3(0.5, 0.9, 0.4), _mats["yellow"])
	_deco(self, unit + Vector3(0.0, 0.92, 0.0), Vector3(0.52, 0.04, 0.42), _mats["dark"])
	var reel := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = 0.22
	drum.bottom_radius = 0.22
	drum.height = 0.12
	reel.mesh = drum
	reel.material_override = _mats["dark"]
	reel.position = unit + Vector3(0.45, 1.4, -0.1)
	reel.rotation.x = PI * 0.5
	add_child(reel)
	_poster("PRESSURE WASHER: TOOL 6", unit + Vector3(-0.1, 1.75, -0.19), 0.0, Vector2(0.9, 0.2))
	var lamp := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.95, 0.85)
	lamp.emission_energy_multiplier = 3.0
	_deco(self, c + Vector3(0.0, h - 0.06, 0.0), Vector3(0.15, 0.04, 1.6), lamp)
	var light := OmniLight3D.new()
	light.position = c + Vector3(0.0, h - 0.4, 0.0)
	light.omni_range = 5.5
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.95, 0.88)
	add_child(light)


## Splits a wall running from `from` to `to` round a doorway at `door` (half width `half`):
## [[middle, length]] of the solid runs either side.
static func _wall_runs(from: float, to: float, door: float, half: float) -> Array:
	var out := []
	if door - half > from:
		out.append([(from + door - half) * 0.5, door - half - from])
	if door + half < to:
		out.append([(door + half + to) * 0.5, to - door - half])
	return out


## The paint shop off the east wall, entered from inside the shed through the doorway by the
## parts computer: white walls, a dark ceiling with a honeycomb of hexagon LED tiles, its own
## light switch by the door, and the downdraft spray bay (equipment "booth_shop") built in.
func _build_booth_room() -> void:
	var c := BOOTH_ROOM_CENTER
	var hx := BOOTH_ROOM_HALF.x
	var hz := BOOTH_ROOM_HALF.y
	var h := ROOM_HEIGHT
	var floor_mat := _material(Color(0.33, 0.35, 0.37), 0.0, 0.4, _noise(0.3, 0.85, 1.05), 4.0)
	var floor_mi := _deco(self, c + Vector3(0.0, 0.006, 0.0), Vector3(hx * 2.0, 0.012, hz * 2.0), floor_mat)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Back, front and outer walls, all closed: the way in is from the shed (its east wall is
	# this room's west side).
	_solid(c + Vector3(0.0, h * 0.5, -hz - 0.1), Vector3(hx * 2.0 + 0.4, h, 0.2), _mats["cladding"])
	_solid(c + Vector3(0.0, h * 0.5, hz + 0.1), Vector3(hx * 2.0 + 0.4, h, 0.2), _mats["cladding"])
	_solid(c + Vector3(hx + 0.1, h * 0.5, 0.0), Vector3(0.2, h, hz * 2.0 + 0.4), _mats["cladding"])
	_solid(c + Vector3(0.0, h + 0.08, 0.0), Vector3(hx * 2.0 + 0.4, 0.12, hz * 2.0 + 0.4), _mats["roof"])
	var white := _material(Color(0.9, 0.91, 0.92), 0.0, 0.35)
	_deco(self, c + Vector3(0.0, h * 0.5, -hz + 0.005), Vector3(hx * 2.0, h, 0.01), white)
	_deco(self, c + Vector3(0.0, h * 0.5, hz - 0.005), Vector3(hx * 2.0, h, 0.01), white)
	_deco(self, c + Vector3(hx - 0.005, h * 0.5, 0.0), Vector3(0.01, h, hz * 2.0), white)
	var wx := c.x - hx + 0.005
	for seg in _wall_runs(c.z - hz, c.z + hz, PAINT_DOOR_Z, SIDE_DOOR_HALF):
		_deco(self, Vector3(wx, h * 0.5, seg[0]), Vector3(0.01, h, seg[1]), white)
	_deco(self, Vector3(wx, (h + SIDE_DOOR_HEIGHT) * 0.5, PAINT_DOOR_Z), Vector3(0.01, h - SIDE_DOOR_HEIGHT, SIDE_DOOR_HALF * 2.0), white)
	_poster("SPRAY GUN: TOOL 7", Vector3(wx + 0.01, 1.6, PAINT_DOOR_Z - SIDE_DOOR_HALF - 1.2), PI * 0.5, Vector2(0.8, 0.2))
	# A dark ceiling so the hexagon tiles stand out.
	var ceiling := _deco(self, c + Vector3(0.0, h - 0.005, 0.0), Vector3(hx * 2.0, 0.01, hz * 2.0), _material(Color(0.08, 0.08, 0.09), 0.2, 0.6))
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room_mats["paint"].append(_hex_ceiling(Rect2(c.x - hx + 0.35, c.z - hz + 0.35, hx * 2.0 - 0.7, hz * 2.0 - 0.7), h - 0.04, 0.55))
	# Real light under the tiles: bright clean white from above, shadowed so none of it shines
	# through the walls into the shed.
	for p in [Vector2(-1.8, -2.6), Vector2(1.2, -2.6), Vector2(-1.8, 2.6), Vector2(1.2, 2.6)]:
		var spot := SpotLight3D.new()
		spot.position = c + Vector3(p.x, h - 0.12, p.y)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 72.0
		spot.spot_range = 5.5
		spot.spot_attenuation = 0.8
		spot.light_energy = 1.7
		spot.light_color = Color(0.97, 0.99, 1.0)
		spot.shadow_enabled = true
		add_child(spot)
		_room_lights["paint"].append(spot)
	_room_probe("paint", c, Vector3(hx * 2.0 + 0.1, h, hz * 2.0 + 0.1), Color(0.8, 0.82, 0.86), 0.6)
	_room_switch("paint", Vector3(c.x - hx + 0.03, 1.35, PAINT_DOOR_Z - SIDE_DOOR_HALF - 0.3), 1.0)


## A honeycomb of hexagon LED tubes across a ceiling, the shared edges drawn once, inside a
## rectangular frame. Returns the glowing material (its brightness follows the light switch).
func _hex_ceiling(area: Rect2, y: float, r: float) -> StandardMaterial3D:
	var glow := _material(Color(1.0, 1.0, 1.0), 0.0, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(0.97, 0.99, 1.0)
	glow.emission_energy_multiplier = 4.0
	var edges := {}   # rounded middle -> [a, b]
	var row_h := sqrt(3.0) * r
	var cols := int(floor((area.size.x - 2.0 * r) / (1.5 * r))) + 1
	var rows := int(floor((area.size.y - row_h) / row_h)) + 1
	# Centre the honeycomb in the area.
	var span := Vector2((cols - 1) * 1.5 * r + 2.0 * r, rows * row_h + (row_h * 0.5 if cols > 1 else 0.0))
	var origin := area.position + (area.size - span) * 0.5 + Vector2(r, row_h * 0.5)
	for col in cols:
		for row in rows:
			var centre := origin + Vector2(col * 1.5 * r, row * row_h + (row_h * 0.5 if col % 2 == 1 else 0.0))
			for k in 6:
				var a := centre + Vector2.from_angle(k * PI / 3.0) * r
				var b := centre + Vector2.from_angle((k + 1) * PI / 3.0) * r
				var key := Vector2i(roundi((a.x + b.x) * 50.0), roundi((a.y + b.y) * 50.0))
				edges[key] = [a, b]
	# The frame round the whole array.
	var lo := origin - Vector2(r, row_h * 0.5) - Vector2(0.12, 0.12)
	var hi := lo + span + Vector2(0.24, 0.24)
	var frame := [[lo, Vector2(hi.x, lo.y)], [Vector2(hi.x, lo.y), hi], [hi, Vector2(lo.x, hi.y)], [Vector2(lo.x, hi.y), lo]]
	var segs: Array = edges.values() + frame
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var tube := BoxMesh.new()
	tube.size = Vector3(0.035, 0.025, 1.0)
	mm.mesh = tube
	mm.instance_count = segs.size()
	for i in segs.size():
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var d := b - a
		var turn := Basis(Vector3.UP, atan2(d.x, d.y)) * Basis.from_scale(Vector3(1.0, 1.0, d.length() * 0.94))
		mm.set_instance_transform(i, Transform3D(turn, Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "HexLights"
	mmi.multimesh = mm
	mmi.material_override = glow
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return glow


## The storage room off the west wall: an empty, lit room with a plain concrete floor for
## lining up shelving in rows, through the doorway by the shed's back corner.
func _build_storage_room() -> void:
	var c := STORE_CENTER
	var hx := STORE_HALF.x
	var hz := STORE_HALF.y
	var h := ROOM_HEIGHT
	# Part of it sits off the back of the yard slab, so it has its own floor slab.
	_solid(c + Vector3(0.0, -0.25, 0.0), Vector3(hx * 2.0 + 0.4, 0.5, hz * 2.0 + 0.4), _mats["floor"]).name = "StorageFloor"
	var floor_mi := _deco(self, c + Vector3(0.0, 0.004, 0.0), Vector3(hx * 2.0, 0.008, hz * 2.0), _mats["floor"])
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its own walls on three sides and the stretch of the fourth behind the shed; the shed's
	# west wall, with the doorway, closes the rest.
	var shed_back := CENTER.z - HALF.y - 0.3
	knock["annex"].append(_solid(c + Vector3(0.0, h * 0.5, -hz - 0.1), Vector3(hx * 2.0 + 0.4, h, 0.2), _mats["cladding"]))
	_solid(c + Vector3(0.0, h * 0.5, hz + 0.1), Vector3(hx * 2.0 + 0.4, h, 0.2), _mats["cladding"])
	_solid(c + Vector3(-hx - 0.1, h * 0.5, 0.0), Vector3(0.2, h, hz * 2.0 + 0.4), _mats["cladding"])
	var east_len := shed_back - (c.z - hz - 0.2)
	_solid(Vector3(c.x + hx + 0.1, h * 0.5, c.z - hz - 0.2 + east_len * 0.5), Vector3(0.2, h, east_len), _mats["cladding"])
	_solid(c + Vector3(0.0, h + 0.08, 0.0), Vector3(hx * 2.0 + 0.4, 0.12, hz * 2.0 + 0.4), _mats["roof"])
	# Inside faces: plaster over a dark band, like the shed.
	var faces := [
		[c + Vector3(0.0, 0.0, -hz + 0.01), Vector3(hx * 2.0, 0.0, 0.02)],
		[c + Vector3(0.0, 0.0, hz - 0.01), Vector3(hx * 2.0, 0.0, 0.02)],
		[c + Vector3(-hx + 0.01, 0.0, 0.0), Vector3(0.02, 0.0, hz * 2.0)],
	]
	for seg in _wall_runs(c.z - hz, c.z + hz, STORE_DOOR_Z, SIDE_DOOR_HALF):
		faces.append([Vector3(c.x + hx - 0.01, 0.0, seg[0]), Vector3(0.02, 0.0, seg[1])])
	for f in faces:
		var face_at: Vector3 = f[0]
		var size: Vector3 = f[1]
		var upper := _deco(self, face_at + Vector3(0.0, h * 0.5 + 0.6, 0.0), size + Vector3(0.0, h - 1.2, 0.0), _mats["wall_in"])
		var lower := _deco(self, face_at + Vector3(0.0, 0.6, 0.0), size + Vector3(0.0, 1.2, 0.0), _mats["wall_low"])
		if f == faces[0]:
			knock["annex"].append_array([upper, lower])   # the back wall: the annex's doorway
	_deco(self, Vector3(c.x + hx - 0.01, (h + SIDE_DOOR_HEIGHT) * 0.5, STORE_DOOR_Z), Vector3(0.02, h - SIDE_DOOR_HEIGHT, SIDE_DOOR_HALF * 2.0), _mats["wall_in"])
	_poster("STORAGE", Vector3(c.x - hx + 0.012, 1.7, c.z), PI * 0.5, Vector2(0.5, 0.18))
	# Strip lights in two rows, a shadowed lamp under each so the shelving throws shadows.
	var fixture := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	_room_mats["storage"].append(fixture)
	for i in 2:
		for j in 2:
			var at := c + Vector3((i - 0.5) * hx, h - 0.06, (j - 0.5) * hz)
			_deco(self, at, Vector3(0.18, 0.05, 1.4), fixture)
			if j == 0:
				continue
			var spot := SpotLight3D.new()
			spot.position = Vector3(at.x, h - 0.15, c.z)
			spot.rotation.x = -PI * 0.5
			spot.spot_angle = 70.0
			spot.spot_range = 5.5
			spot.light_energy = 1.6
			spot.light_color = Color(1.0, 0.95, 0.88)
			spot.shadow_enabled = true
			add_child(spot)
			_room_lights["storage"].append(spot)
	_room_probe("storage", c, Vector3(hx * 2.0 + 0.1, h, hz * 2.0 + 0.1), Color(0.55, 0.5, 0.45), 0.4)
	_room_switch("storage", Vector3(c.x + hx - 0.03, 1.35, STORE_DOOR_Z + SIDE_DOOR_HALF + 0.3), -1.0)


## A room's ambient light: warm fill while its lights are on, dark when they're off.
func _room_probe(room: String, at: Vector3, size: Vector3, color: Color, energy: float) -> void:
	var probe := ReflectionProbe.new()
	probe.position = at + Vector3(0.0, size.y * 0.5, 0.0)
	probe.size = size
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = color
	probe.ambient_color_energy = energy
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.set_meta("energy", energy)
	add_child(probe)
	_room_probes[room] = probe


## A light switch for a side room on a wall facing along x (`facing` +1 or -1).
func _room_switch(room: String, at: Vector3, facing: float) -> void:
	var plate := _material(Color(0.92, 0.92, 0.9), 0.0, 0.5)
	_deco(self, at, Vector3(0.03, 0.14, 0.1), plate)
	var rocker := _deco(self, at + Vector3(facing * 0.02, 0.0, 0.0), Vector3(0.015, 0.07, 0.04), _material(Color(0.85, 0.85, 0.82), 0.0, 0.5))
	rocker.name = "LightRocker_" + room
	_poster("LIGHTS", at + Vector3(facing * 0.018, 0.13, 0.0), facing * PI * 0.5, Vector2(0.16, 0.06))
	_target(at, Vector3(0.1, 0.2, 0.16), {"light_switch": room})


## A side room's lights on or off (its switch by the door).
func set_room_lights(room: String, on: bool) -> void:
	_room_shown[room] = on
	for l in _room_lights.get(room, []):
		(l as Light3D).visible = on
	for m in _room_mats.get(room, []):
		(m as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.0
	var probe: ReflectionProbe = _room_probes.get(room, null)
	if probe:
		probe.ambient_color_energy = float(probe.get_meta("energy", 0.4)) if on else 0.0
		probe.intensity = 1.0 if on else 0.15
	var rocker := get_node_or_null("LightRocker_" + room)
	if rocker:
		rocker.rotation.z = 0.0 if on else 0.5


## The roller door that comes down over the opening, and the switches inside beside it: one for
## the door, one for the lights.
func _build_door_and_switches() -> void:
	var c := CENTER
	var hz := HALF.y
	_door_panel = MeshInstance3D.new()
	var slats := BoxMesh.new()
	slats.size = Vector3(DOOR_HALF * 2.0, 1.0, 0.05)
	_door_panel.mesh = slats
	var steel: StandardMaterial3D = _material(Color(0.62, 0.64, 0.66), 0.7, 0.45, _noise(0.3, 0.92, 1.05), 1.0)
	steel.uv1_scale = Vector3(1.0, 12.0, 1.0)
	_door_panel.material_override = steel
	add_child(_door_panel)
	var body := StaticBody3D.new()
	body.set_meta("surface", "tarmac")
	body.position = c + Vector3(0.0, DOOR_HEIGHT * 0.5, hz + 0.15)
	_door_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_HALF * 2.0, DOOR_HEIGHT, 0.12)
	_door_shape.shape = shape
	body.add_child(_door_shape)
	add_child(body)
	_door_sound = Sfx.make_loop_player(self)
	_door_sound.position = c + Vector3(0.0, DOOR_HEIGHT + 0.3, hz - 0.3)
	# Switch boxes on the wall to the right of the door, inside.
	var at := c + Vector3(DOOR_HALF + 0.55, 1.35, hz - 0.03)
	_deco(self, at, Vector3(0.14, 0.24, 0.05), _mats["yellow"])
	_deco(self, at + Vector3(0.0, 0.05, -0.03), Vector3(0.05, 0.05, 0.02), _material(Color(0.1, 0.6, 0.15), 0.0, 0.4))
	_deco(self, at + Vector3(0.0, -0.05, -0.03), Vector3(0.05, 0.05, 0.02), _mats["red"])
	_poster("DOOR", at + Vector3(0.0, 0.2, -0.026), PI, Vector2(0.16, 0.06))
	_target(at, Vector3(0.2, 0.3, 0.12), {"door_switch": true})
	var ls := at + Vector3(0.38, 0.0, 0.0)
	_deco(self, ls, Vector3(0.1, 0.14, 0.03), _material(Color(0.92, 0.92, 0.9), 0.0, 0.5))
	var rocker := _deco(self, ls + Vector3(0.0, 0.0, -0.02), Vector3(0.04, 0.07, 0.015), _material(Color(0.85, 0.85, 0.82), 0.0, 0.5))
	rocker.name = "LightRocker"
	_poster("LIGHTS", ls + Vector3(0.0, 0.13, -0.018), PI, Vector2(0.16, 0.06))
	_target(ls, Vector3(0.16, 0.2, 0.1), {"light_switch": true})
	_update_door(0.0)


func _update_door(delta: float) -> void:
	if _door_panel == null:
		return
	var want := 1.0 if Shed.door_open else 0.0
	var was := door_open_amount
	door_open_amount = move_toward(door_open_amount, want, delta / 2.5)
	var moving := not is_equal_approx(was, door_open_amount)
	if _door_sound:
		Sfx.set_loop(_door_sound, "door" if moving else "")
	var down := 1.0 - door_open_amount
	_door_panel.visible = down > 0.01
	var h := maxf(down * DOOR_HEIGHT, 0.01)
	_door_panel.scale = Vector3(1.0, h, 1.0)
	_door_panel.position = CENTER + Vector3(0.0, DOOR_HEIGHT - h * 0.5, HALF.y + 0.15)
	# Bikes and people get through once it's most of the way up.
	_door_shape.disabled = door_open_amount > 0.75


## Shed lights on or off (the switch by the door).
func set_lights(on: bool) -> void:
	_lights_shown = on
	for l in _shed_lights:
		l.visible = on
	for m in _fixture_mats:
		m.emission_energy_multiplier = 4.0 if on else 0.0
	if _probe:
		# Lights off is properly dark: no warm fill, dim reflections; the screens and the open
		# door are all that's left.
		_probe.ambient_color_energy = 0.45 if on else 0.0
		_probe.intensity = 1.0 if on else 0.15
	var rocker := get_node_or_null("LightRocker")
	if rocker:
		rocker.rotation.x = 0.0 if on else 0.5


func _build_lights() -> void:
	var fixture := _material(Color(1.0, 0.97, 0.9), 0.0, 0.5)
	fixture.emission_enabled = true
	fixture.emission = Color(1.0, 0.95, 0.85)
	fixture.emission_energy_multiplier = 4.0
	for bay in BAY_COUNT:
		var xf := bay_transform(bay)
		_deco(self, Vector3(xf.origin.x, HEIGHT - 0.35, xf.origin.z), Vector3(0.2, 0.05, 1.3), fixture)
		var spot := SpotLight3D.new()
		spot.position = Vector3(xf.origin.x, HEIGHT - 0.45, xf.origin.z + 0.4)
		spot.rotation.x = -PI * 0.5
		spot.spot_angle = 50.0
		spot.spot_range = 6.5
		spot.light_energy = 2.6
		spot.light_color = Color(1.0, 0.95, 0.88)
		spot.shadow_enabled = true
		add_child(spot)
		_shed_lights.append(spot)
	for p in [Vector3(-4.2, 0.0, 1.5), Vector3(4.2, 0.0, 1.5), Vector3(0.0, 0.0, 3.5)]:
		_deco(self, CENTER + p + Vector3(0.0, HEIGHT - 0.35, 0.0), Vector3(0.2, 0.05, 1.3), fixture)
		var omni := OmniLight3D.new()
		omni.position = CENTER + p + Vector3(0.0, HEIGHT - 0.6, 0.0)
		omni.omni_range = 7.0
		omni.light_energy = 1.2
		omni.light_color = Color(1.0, 0.93, 0.82)
		omni.shadow_enabled = p.x == 0.0
		add_child(omni)
		_shed_lights.append(omni)
	# Indoors the sky shouldn't light everything blue: a probe gives the shed warm ambient light.
	var probe := ReflectionProbe.new()
	probe.position = CENTER + Vector3(0.0, HEIGHT * 0.5, 0.0)
	probe.size = Vector3(HALF.x * 2.0 + 0.2, HEIGHT, HALF.y * 2.0 + 0.2)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.55, 0.5, 0.45)
	probe.ambient_color_energy = 0.45
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
	_probe = probe
	_fixture_mats.append(fixture)


# ---------------------------------------------------------------------------- sales office

func _build_sales_office() -> void:
	sales_office = SalesOffice.new()
	add_child(sales_office)
	sales_office.build()
