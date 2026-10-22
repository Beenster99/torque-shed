class_name BikeModel
extends Node3D
## The visible bike and rider, built from primitive meshes to match the chosen parts.
## Every mesh belongs to one part slot, so a bike in the shed can show missing parts,
## rust and grime per part, highlight the part a player is looking at, and give each
## part its own click target. Shared by ridden, parked and other players' bikes.

const PICK_LAYER := 4
const CHAIN_PITCH := 0.015875   # m: a 5/8" chain, the pitch of every 520, 525 and 530 chain
## The glossiest any surface of a bike is drawn (roughness), and its clear coat: the sun glinting
## off a smoother mirror or chrome is brighter than the screen's HDR can hold, which comes out as
## NaN that the glow spreads into big white blobs speckled black (see _floor_shine).
const MIN_ROUGHNESS := 0.08
const MIN_CLEARCOAT_ROUGHNESS := 0.1
const SPRAY_LAYER := 16   # fitted shapes on loose parts, only for the spray to land on

static var _rust_masks := {}     # rust level (1..10) -> NoiseTexture2D mask
static var _rust_albedo: NoiseTexture2D
static var _patina_albedo: NoiseTexture2D
static var _part_sizes := {}      # part id -> bounding size, for sizing delivery boxes
static var _cardboard: StandardMaterial3D
static var _highlight_mat: StandardMaterial3D
static var _letters := {}         # "letter|height" -> its mesh, for the tyre walls (see _tyre_lettering)

var paint := Color(0.78, 0.09, 0.08)
var jacket := Color(0.1, 0.12, 0.16)
var rider_color := Color(0, 0, 0, 0)   # the rider's own colour; clear means dress to match the bike
## The rider's gear, slot -> RiderGear item id (see RiderFigure). With it or a rider colour the
## rider wears that gear (the free defaults where it's empty); with neither they match the bike.
var rider_gear := {}
var present := {}                # slot -> bool; missing slots are not drawn
var condition := {}              # slot -> {rust, dirt, wear, color, finish}
var stand_pose := ""             # "side" or "centre" draws that stand down on the ground; set before build_from
## The rider's helmet is on its own render layer so the first-person camera can leave it out.
const HELMET_LAYER := 2
## Whether this is your own ride: only then do the rider's helmet, torso and upper arms go on
## HELMET_LAYER, out of your first-person eye. Everyone else's riders stay whole in it.
var own_rider := false
## The rider's left foot put down on the ground as the ridden bike comes to rest (update_foot):
## below FOOT_DOWN_SPEED (m/s) it goes down, above FOOT_UP_SPEED it's lifted back onto the peg,
## each over FOOT_TIME seconds; the foot lands FOOT_OUT to the left of the bike, which leans
## FOOT_LEAN onto it. FOOT_SAG is how far the bike sits down on its springs, for the ground.
const FOOT_DOWN_SPEED := 1.1
const FOOT_UP_SPEED := 1.8
const FOOT_TIME := 0.3
const FOOT_OUT := 0.42
const FOOT_LEAN := 0.08
const FOOT_SAG := 0.035
## How far the foot's down now, 0 (on the peg) .. 1 (on the ground), and where it's going.
var foot_down := 0.0
var _foot_want := 0.0
## Set before build_from: the parts are merged into fewer meshes as they're drawn (see
## _bake_static), for a bike that's ridden past rather than worked on. How many went, after.
var baked := false
var baked_away := 0

var _build: BikeBuild
var _slot_meshes := {}           # slot -> Array of GeometryInstance3D
var _current_slot := "frame"
var _steer_node: Node3D
var _front_hub: Node3D
var _front_wheel: Node3D
var _rear_hub: Node3D
var _rear_wheel: Node3D
var _flat_tyres := {}   # side -> the squashed tyre's mesh, held still as the wheel turns (see set_flat)
var _swingarm: Node3D
var _rider: Node3D
## The rider's head (helmet) and left arm, each on a pivot of its own (at the neck and the left
## shoulder) so the rider can nod, wave and look round (see gesture and look_back).
var _rider_head: Node3D
var _arm_left: Node3D
var _arm_rest := Vector3.ZERO     # the left arm's line at rest, shoulder to grip, in the rider's space
## The gesture under way on the bike (see Emotes.RIDING) and how far into it, in seconds.
var _gesture := ""
var _gesture_t := 0.0
var _nod := 0.0                    # the head's dip forward now (rad)
## How far the rider looks back over their left shoulder, 0 (ahead) .. 1 (right round).
var look_back := 0.0:
	set(v):
		look_back = v
		if v != 0.0:
			set_process(true)
const LOOK_BACK_YAW := 2.0
var _look_shown := 0.0
var _steer_axis := Vector3.UP
var _head := Vector3.ZERO
var _head_bottom := Vector3.ZERO
var _pivot := Vector3.ZERO
var _seat_y := 0.5
var _seat_front := Vector3.ZERO
var _tail := Vector3.ZERO
var _engine_c := Vector3.ZERO
var _peg := Vector3(0.17, 0.02, 0.0)   # the right footpeg (the left is its mirror)
var _frame_geo := {}             # the frame part's mounting points (see build_from)
var _block_w := 0.3
var _bore_r := 0.048             # cylinder barrel radius
var _tank_a := Vector3.ZERO      # the tank's underside line, nose to tail (see _draw_tank)
var _tank_b := Vector3.ZERO
var _tank_secs: Array = []       # the tank's sections as drawn, for what sits on top of it (see tank_top_at)
## The middle of the tank's filler cap, on top of it (model space; zero with no tank), where the
## shed pump's nozzle goes in (see ShedPump).
var filler := Vector3.ZERO
var _satnav_screen: MeshInstance3D   # the sat nav's screen, lit with the live map (see set_satnav_texture)
var _satnav_cradle: Node3D       # a phone's cradle on its arm, buzzing with the engine (see set_gauges)
var _satnav_rest := Vector3.ZERO # where the cradle sits still
var _satnav_glow: OmniLight3D    # the screen's glow on the bars after dark (see _show_satnav)
var _satnav_live: Texture2D      # the live map from the rider's own sat nav (see set_satnav_texture)
var _satnav_driven := false      # whether a live sat nav (Satnav) has the screen
var _satnav_dark := -1.0         # the darkness the glow was last set for
## Where a phone sat nav went on the bars (KitModel._phone): {clamp, centre (steering space),
## spot (which of the places tried), dash_hidden, hits, blocked}; empty for any other unit.
var satnav_fit := {}
var _bar_line := PackedVector3Array()   # the right half of the bar from the middle out to its end, in steering space
var _screen_lift: Node3D         # an adjustable screen hangs from this, moved up its rails (see set_screen_raise)
var _screen_dir := Vector3.UP
var _covered: Array[AABB] = []   # what a full fairing hides, side on (see _hide_covered)
var _eng_s := 1.0                # engine size relative to a 700 cc
var _spine_kink := Vector3.ZERO  # where a long, low frame's backbone drops to the seat, behind the engine (see _fit_bay); zero for a straight one
var _rail_low := 0.0             # how low that frame's cradle rails run under the engine (see _fit_bay)
var _down_z := 0.0               # where its downtubes come down in front of the engine (see _fit_bay)
var _bay := false                # the frame is one of BAY_FRAMES, built round its engine
var _head_k := 1.0               # how big the barrels and heads are drawn (see _place_cylinders)
var _cyls := []                  # {base, up} per cylinder barrel
var _arm_len := 0.6
var _struts: Array = []     # rear shocks: [{mi, top (model space), bottom (on the swingarm), rest}]
var _grip_l := Vector3(-0.31, 0.12, 0.06)   # handlebar grips, in steering space
var _grip_r := Vector3(0.31, 0.12, 0.06)
var _highlighted := ""
var _exhaust_tip := Vector3.ZERO
var _eye := Vector3.ZERO
var _grime: StandardMaterial3D
var dirt_layer: DirtLayer        # the road dirt drawn over the parts (see show_dirt)
var finish_layer: FinishLayer    # detailed panels' gloss, burns and ceramic coat (see show_shine)
var _dash_label: Label3D
var _needles := []               # {node, what: "speed" or "rpm"} on dial clocks
var _leds := []                  # shift lights: {mat, color}
var _dash_screen := Transform3D()  # where the readout text sits on the clocks, in steering space
var _dash_face := PackedVector3Array()   # points over the clocks' faces, in steering space (see dash_hidden)
var _rear_guard: Array[MeshInstance3D] = []   # the rear mudguard's pieces (see _draw_tail)
var _plates: Array[MeshInstance3D] = []       # the number plate on the tail
var _bars_tm: TriangleMesh = null             # the bars as triangles, for the clocks' sight lines
var _dash_raised := 0.0                       # m: how far the clocks were raised to clear the bars
var _fit_only := false                        # drawing just what the fit checks look at (see build_fit_parts)
var _rails: Array = []                        # the frame's tubes as drawn: {pts (along the middle), r} (see engine_clash)
const DASH_LIFT_MAX := 0.25   # m: the most the clocks rise to be seen past the bars
const DASH_EYE_SPARE := 0.03  # m: how far under the rider's eye the clocks still clear the bars from
const GUARD_GAP := 0.015      # m: from the rear tyre, shock fully compressed, to the middle of its mudguard
const PLATE_GAP := 0.004      # m: kept between the number plate and the rear mudguard
var _lamps: Array = []           # lit lenses and clocks: {mat, albedo, energy, group ("ign", "head", "fog", "tail", "ind_l" or "ind_r")}
var _lit := [true, true, true]   # [ignition, headlight, fog lights] as last set
## The rear light's glow: dim as a tail light with the headlight on, bright as the stop lamp
## (see set_signals), when a small red lamp also lights the guard and the road behind it.
const TAIL_ENERGY := 0.7
const STOP_ENERGY := 6.0
const STOP_GLOW := 2.0        # the red lamp's energy while braking
const STOP_GLOW_RANGE := 3.0  # m
## An indicator's lens while it flashes on; between flashes it's dull amber glass.
const INDICATOR_ENERGY := 12.0
var _signals := [false, false, false]   # [stop lamp, left indicators, right indicators] as last set
var _stop_glow: SpotLight3D             # the red lamp shining back from the rear light (see set_signals)
## The slots whose meshes carry indicators: "indicators" with a set fitted, else the stock pair's
## "headlight" and "tail" (see _stock_indicators).
var _indicator_slots: Array[String] = []
var _stock_pieces := {}   # the stock indicators' meshes (see _stock_indicators) -> true
## This bike's own fit for each part, set in geometry mode: slot -> {p, r, s} (see GeoGizmo),
## about the part's middle in the model's axes. Set it before build_from, or change it any time
## with apply_geometry. Looks only: the physics never see it.
var geometry := {}
var _geo_nodes := {}             # slot -> [{node, parent, anchor}]: a node per slot per parent its meshes hang from
var _geo_pivots := {}            # slot -> the part's middle at rest, in model space
var _geo_anchors := {}           # node -> its rest transform in model space, for the nodes offsets ride on
## slot -> meshes drawn for the part besides its own: a baked model's shadow-only casters (see
## _bake_static) and the dirt drawn over its merged pieces (see DirtLayer). They move with it.
var _slot_extras := {}
var _baked_pieces := {}          # instance id -> true for each mesh _bake_static merged
## Each bent tube's line and thickness, by its mesh's instance id (see _bend). Kept here rather
## than as a meta on the mesh, which would stop _bake_static merging it.
var _bends := {}


## Builds the model. `fitted` maps slot -> bool (all fitted when empty); `part_condition`
## maps slot -> {rust, dirt, wear, color} and defaults to the build's own condition.
func build_from(build: BikeBuild, paint_color := paint, fitted := {}, part_condition = null, with_rider := true) -> void:
	_build = build
	paint = paint_color
	jacket = paint.darkened(0.45)
	present = fitted
	condition = build.condition if part_condition == null else part_condition
	_slot_meshes.clear()
	mirrors.clear()
	_slot_extras.clear()
	_baked_pieces.clear()
	_bends.clear()
	_covered.clear()
	_lamps.clear()
	_lit = [true, true, true]
	_signals = [false, false, false]
	_stop_glow = null
	_indicator_slots.clear()
	_stock_pieces.clear()
	_highlighted = ""
	for slot in PartsDB.SLOTS:
		_slot_meshes[slot] = []
	for child in get_children():
		child.free()
	_rider = null
	dirt_layer = null
	finish_layer = null
	_geo_nodes.clear()
	_geo_pivots.clear()
	_geo_anchors.clear()
	_rear_guard.clear()
	_plates.clear()
	_flat_tyres.clear()
	_dash_face = PackedVector3Array()
	_tank_secs = []
	_rails = []
	filler = Vector3.ZERO
	_satnav_screen = null
	_satnav_cradle = null
	_satnav_glow = null
	_satnav_dark = -1.0
	satnav_fit = {}
	_bar_line = PackedVector3Array()
	_screen_lift = null

	var zr := _lay_out(build)
	_layout_cylinders(build)

	_draw_frame(build, zr)
	_draw_tank()
	_draw_saddle()
	_draw_engine()
	_draw_head()
	_draw_spark_plugs()
	_draw_fuel()
	_draw_air_filter()
	_draw_oil_filter()
	_draw_cooling()
	_draw_gearbox()
	_draw_exhaust(zr)

	_add_steer_node()
	_draw_fork(build)
	_draw_handlebars()
	_draw_dashboard()
	_bars_tm = null   # only wanted again by the fit checks, which make it afresh
	_draw_front_master()
	_draw_headlight()

	_front_wheel = Node3D.new()
	_front_hub.add_child(_front_wheel)
	_add_rear_hub()
	for side in ["front", "rear"]:
		var front: bool = side == "front"
		var wheel := _front_wheel if front else _rear_wheel
		var hub := _front_hub if front else _rear_hub
		var rim_r := build.front_rim_radius if front else build.rear_rim_radius
		var width := build.front_tyre_width if front else build.rear_tyre_width
		_current_slot = side + "_wheel"
		var rim_w := rim_width_of(_part())
		_draw_rim(wheel, rim_r, rim_w)
		_current_slot = side + "_tyre"
		_draw_tyre(wheel, rim_r, build.front_radius if front else build.rear_radius, width, rim_w)
		set_flat(side, float(build.flat.get(side, 0.0)))
		_draw_brake(side, wheel, hub, rim_r, rim_w)
	_draw_rear_master()
	_draw_final_drive(zr)
	_draw_shock()
	_draw_side_stand(build)
	_draw_centre_stand(build)
	_draw_horn()
	_draw_ecu()
	_draw_panniers(build, zr)
	_draw_top_box()
	_draw_fog_lights()
	_draw_tail(build)
	_draw_fairing()
	_draw_mirrors()
	_draw_front_mudguard(build)
	_draw_indicators()
	_draw_side_panels()
	_draw_rearsets()
	_draw_guards()
	_draw_number_boards()
	_draw_steering_damper()
	_draw_lever_guards()
	KitModel.draw(self, build, zr)

	# A full fairing carries its own lamps: the plain headlight is tucked away inside it.
	if _full_fairing_fitted():
		for mi in _slot_meshes.get("headlight", []):
			(mi as Node).set_meta("under_fairing", true)
		_hide_covered()
		_service_caps()
	_apply_visibility()
	_current_slot = ""
	if with_rider:
		_build_rider()
		Graphics.avatar_meshes(_rider)
	update_pose_from(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	set_gauges(0.0, 0.0)
	# Parked, every lamp and the clocks are dark until the engine runs (see set_lights).
	set_lights(false, false)
	baked_away = _bake_static() if baked else 0
	_floor_shine()
	# Before the bike's own fit moves anything: the mask is laid out where the parts were drawn.
	_show_blasted()
	_show_paint_fx()
	# Ahead of the dirt, which copies the paint's passes into its own.
	_show_shine()
	_show_dirt()
	if not geometry.is_empty():
		apply_geometry(geometry)


## Where everything is placed from, for `build`: the steering head, the swingarm pivot, the seat
## and tail, the engine, the footpegs and the rider's eye. Returns the rear axle's z.
func _lay_out(build: BikeBuild) -> float:
	_build = build
	var wb := build.wheelbase
	var zf := -wb * 0.5
	var zr := wb * 0.5
	var rake := deg_to_rad(build.rake_deg)
	_steer_axis = Vector3(0.0, cos(rake), sin(rake))
	_head = Vector3(0.0, 0.0, zf) + _steer_axis * build.fork_length
	_head_bottom = _head - _steer_axis * 0.16
	_seat_y = build.seat_height - build.rear_radius
	# Each frame has its own mounting points (its "geo"): where the swingarm pivots, where the
	# engine hangs, how far the seat rails run, where the footpegs go. Everything else is
	# placed from these, so a long, low cruiser frame and a tall MX frame give different bikes.
	_frame_geo = PartsDB.get_part(str(build.parts.get("frame", ""))).get("geo", {})
	_pivot = Vector3(0.0, _geo("pivot_y", 0.16), zr - _geo("arm", 0.6))
	# The seat starts over the swingarm pivot, leaving the tank its own space behind the bars.
	_seat_front = Vector3(0.0, _seat_y - _geo("seat_drop", 0.1), _pivot.z + 0.02)
	_tail = Vector3(0.0, build.seat_height - build.rear_radius - 0.02 + _geo("tail_y", 0.0), zr - _geo("tail_back", 0.12))
	_engine_c = Vector3(0.0, _geo("engine_y", 0.1), lerpf(_head_bottom.z, _pivot.z, _geo("engine_at", 0.48)))
	var peg: Array = _frame_geo.get("peg", [0.02, 0.02])
	# Rearsets and forward controls put the feet where they say, wherever the frame had them.
	var sets := PartsDB.get_part(str(build.parts.get("rearsets", "none")))
	if sets.get("peg") is Array and is_fitted("rearsets"):
		peg = sets["peg"]
	_peg = Vector3(0.17, float(peg[0]), _pivot.z + float(peg[1]))
	_eye = _eye_point()
	return zr


## The rider's eyes, sat on the seat (as _build_rider sits them) looking down over the bars.
func _eye_point() -> Vector3:
	var hips := Vector3(0.0, _seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	return hips + Vector3(0.0, 0.5, -0.3) + Vector3(0.0, 0.28, 0.28)


## The node the bars, clocks, fork and front wheel hang from, turning about the steering axis.
func _add_steer_node() -> void:
	_steer_node = Node3D.new()
	_steer_node.position = _head
	add_child(_steer_node)
	_front_hub = Node3D.new()
	_steer_node.add_child(_front_hub)


## The node the rear wheel hangs from, moving up and down with the shock.
func _add_rear_hub() -> void:
	_rear_hub = Node3D.new()
	add_child(_rear_hub)
	_rear_wheel = Node3D.new()
	_rear_hub.add_child(_rear_wheel)


## Road dirt over every dirty part, region by region (see Dirt and DirtLayer), from each part's
## condition (its "dirt" and "grime").
func _show_dirt() -> void:
	var levels := {}
	for slot in _slot_meshes:
		var cond = condition.get(slot)
		if not (cond is Dictionary) or float((cond as Dictionary).get("dirt", 0.0)) <= 0.003 or (_slot_meshes[slot] as Array).is_empty():
			continue
		levels[slot] = Dirt.cells(cond, str(slot))
	if not levels.is_empty():
		ensure_dirt_layer().set_levels(levels)


## Detailed panels' finish (see Detail and FinishLayer), from each part's condition ("shine").
func _show_shine() -> void:
	var finishes := {}
	for slot in Detail.PANELS:
		var cond = condition.get(slot)
		if cond is Dictionary and (cond as Dictionary).get("shine") is Dictionary and not (_slot_meshes.get(slot, []) as Array).is_empty():
			finishes[slot] = Detail.data(cond)
	if finishes.is_empty():
		return
	finish_layer = FinishLayer.new()
	finish_layer.name = "FinishLayer"
	add_child(finish_layer)
	finish_layer.setup(self, finishes)


## Shows each detailed panel's finish as it is now (slot -> finish, see Detail.of_bike), without
## redrawing the bike. A panel that wasn't detailed when it was drawn waits for the redraw.
func show_shine(finishes: Dictionary) -> void:
	if finish_layer != null and is_instance_valid(finish_layer):
		finish_layer.show(finishes)


## The layer the dirt's drawn in (made if it hasn't been yet).
func ensure_dirt_layer() -> DirtLayer:
	if dirt_layer == null or not is_instance_valid(dirt_layer):
		dirt_layer = DirtLayer.new()
		dirt_layer.name = "DirtLayer"
		add_child(dirt_layer)
		dirt_layer.setup(self, {})
	return dirt_layer


## Keeps every surface of the bike at least MIN_ROUGHNESS rough (and its clear coat
## MIN_CLEARCOAT_ROUGHNESS): a mirror-smooth one catching the sun puts out more light than the
## HDR picture holds. Dirt used to dull a ridden bike's mirrors and chrome; now it's drawn over
## them (DirtLayer) they stay as smooth as new, which is how the cafe's bikes came to glare.
func _floor_shine() -> void:
	var seen := {}
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var g := n as GeometryInstance3D
		if g == null:
			continue
		var mats: Array = [g.material_override, g.material_overlay]
		var mi := g as MeshInstance3D
		if mi != null and mi.mesh != null:
			for si in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(si))
				mats.append(mi.mesh.surface_get_material(si))
		for m in mats:
			var at: Material = m
			while at != null and not seen.has(at):
				seen[at] = true
				if at is BaseMaterial3D:
					var b := at as BaseMaterial3D
					if b.roughness < MIN_ROUGHNESS:
						b.roughness = MIN_ROUGHNESS
					if b.clearcoat_enabled and b.clearcoat_roughness < MIN_CLEARCOAT_ROUGHNESS:
						b.clearcoat_roughness = MIN_CLEARCOAT_ROUGHNESS
				at = at.next_pass


## Shows each part's dirt as it is now (slot -> Dirt levels, see Dirt.of_bike), without redrawing
## the bike. Not while someone's washing it here (their WashJob draws it as it goes).
func show_dirt(levels: Dictionary) -> void:
	if dirt_layer != null and is_instance_valid(dirt_layer) and dirt_layer.held_by_job:
		return
	var any := false
	for slot in levels:
		if DirtLayer._any(levels[slot]):
			any = true
			break
	if not any and (dirt_layer == null or not is_instance_valid(dirt_layer)):
		return
	var shown := {}
	for slot in levels:
		if (_slot_meshes.get(slot, []) as Array).is_empty():
			continue
		shown[slot] = levels[slot]
	ensure_dirt_layer().set_levels(shown)


## Sandblasted bare metal on the engine, wherever it's drawn (see BlastMarks.show_saved). A part
## off its engine is drawn bare only if it was blasted all over: where exactly depends on the
## engine it was on.
func _show_blasted() -> void:
	var looks := {}
	var on_engine := is_fitted("engine") and not (_slot_meshes.get("engine", []) as Array).is_empty()
	for slot in ["engine"] + Array(PartsDB.ENGINE_SLOTS):
		var cond = condition.get(slot)
		if not (cond is Dictionary) or not ((cond as Dictionary).has("blast") or (cond as Dictionary).get("blast_full", false)):
			continue
		var look: Dictionary = (cond as Dictionary).duplicate()
		if not on_engine:
			look.erase("blast")
			if not look.get("blast_full", false):
				continue
		looks[slot] = look
	if not looks.is_empty():
		BlastMarks.show_saved(self, looks)


## Mixed paint's effects pass (PaintMix.fx_pass) needs to know where each painted mesh sits in
## the part, for stripes, a two-tone split or a fade to line up across all of it.
func _show_paint_fx() -> void:
	for slot in _slot_meshes:
		var box := AABB()
		var found := false
		for mi in _slot_meshes[slot]:
			var g := mi as GeometryInstance3D
			if g == null or not is_instance_valid(g) or g.material_override == null or not g.material_override.has_meta("paint_fx"):
				continue
			if not found:
				box = slot_bounds(str(slot))
				found = true
			PaintMix.place_fx(g, _local_xform(g), box)


## Where each cylinder's barrel sits and which way it points, for the engine layout. Barrels
## are sized from the bore, so a 50 cc twin looks tiny next to a 1200.
func _layout_cylinders(build: BikeBuild) -> void:
	var block := PartsDB.get_part(str(build.parts.get("engine", "")))
	_bore_r = clampf(float(block.get("bore", 80.0)) * 0.0006, 0.022, 0.062)
	_eng_s = clampf(pow(build.displacement / 700.0, 0.3), 0.55, 1.2)
	_bay = str(PartsDB.get_part(str(build.parts.get("frame", ""))).get("style", "")) in BAY_FRAMES
	_head_k = 1.0
	_place_cylinders(build)
	_fit_bay(build)


## The cylinders' barrels round the engine's middle, at its size (_eng_s). Each one's "up" runs
## along the barrel, as long as the barrels and heads are drawn (_head_k: 1, but less in a frame
## built round a smaller engine than this one, see _fit_bay).
func _place_cylinders(build: BikeBuild) -> void:
	_cyls.clear()
	var cyl := build.cylinders
	var s := _eng_s
	match build.layout:
		"vtwin":
			_block_w = 0.22 * s
			# A cruiser's or chopper's V-twin is the narrow 45 degree kind; the rest open wider.
			for dir in [-1.0, 1.0]:
				var up := Vector3(0.0, cos(0.6), 0.6 * dir).normalized()
				if _bay:
					up = Vector3(0.0, cos(PI / 8.0), sin(PI / 8.0) * dir)
				up *= _head_k
				_cyls.append({"base": _engine_c + Vector3(0.0, 0.13 * s, 0.07 * dir * s) + up * 0.12 * s, "up": up})
			return
		"boxer":
			# Flat twin: the barrels stick straight out either side, ahead of the rider's knees.
			_block_w = 0.24 * s
			for dir in [-1.0, 1.0]:
				var up := Vector3(dir, 0.08, -0.05).normalized() * _head_k
				_cyls.append({"base": _engine_c + Vector3(0.1 * dir * s, 0.03, -0.06) + up * 0.1 * s, "up": up})
			return
	_block_w = (0.2 + 0.11 * (cyl - 1)) * s
	# A classic twin stands upright; two-strokes lean right forward; the rest lean a little.
	var lean := {"twin": 0.04, "2stroke": 0.4}.get(build.layout, 0.25) as float
	var up := Vector3(0.0, 1.0, -lean).normalized() * _head_k
	for c in cyl:
		var cx := (c - (cyl - 1) * 0.5) * maxf(0.12 * s, _bore_r * 2.4)
		_cyls.append({"base": _engine_c + Vector3(cx, 0.14 * s, -0.04) + up * 0.1 * s, "up": up})


## The frames whose backbone runs over the engine to the seat and whose cradle rails run under it
## (see _fit_bay).
const BAY_FRAMES := ["softail", "chopper", "cruiser"]
const BAY_SPINE_R := 0.032    # m: the backbone's radius (the biggest of these frames')
const BAY_DOWN_R := 0.019     # m: the downtubes' and cradle rails' radius
const BAY_POST_R := 0.026     # m: the seat post's radius
const BAY_CLEAR := 0.012      # m: daylight kept between the engine and a tube
const BAY_RAIL_X := 0.1       # m: the cradle rails either side of the middle
const BAY_RISE := 0.11        # m: how far ahead of the swingarm pivot the cradle rails start up to it
const BAY_DROP_LEAN := 0.36   # how far back the backbone's drop to the seat leans, per m it falls (about 20 degrees)


## A softail, chopper or cruiser frame is built round its engine, the way a real one is: the
## engine sits between the downtubes and the seat post, the cradle rails run under its cases and
## the backbone (and the tank on it) runs over its heads, then drops down to the seat behind the
## back cylinder. A big engine moves back in the bay as far as the seat lets it; if it still
## won't go in, it's drawn a little smaller until it does.
func _fit_bay(build: BikeBuild) -> void:
	_spine_kink = Vector3.ZERO
	_rail_low = _engine_c.y - 0.17 * _eng_s
	_down_z = _engine_c.z - 0.17 * _eng_s - 0.075
	if not _bay:
		return
	var want_z := _engine_c.z
	var front_limit := _bay_front_limit(build)
	for attempt in 16:
		var pts := _engine_corners()
		var e := _engine_c
		var low := _bay_low(pts)
		# The furthest back the engine can go: its heads ahead of the backbone's drop to the
		# seat, its cases ahead of the seat post and of the cradle rails rising to the pivot.
		var rise_a := Vector2(_pivot.z - BAY_RISE, low - 0.01)
		var rise_b := Vector2(_pivot.z - 0.02, _pivot.y - 0.03)
		var back := INF
		for c in pts:
			var p: Vector3 = c[0]
			var lim := INF
			if p.y >= _seat_front.y - 0.06:
				if float(c[1]) <= 0.15:   # ahead of the drop to the seat, and the seat's nose
					lim = _drop_z(p.y) - (BAY_SPINE_R + BAY_CLEAR) * 1.07
			elif float(c[1]) <= BAY_POST_R + BAY_CLEAR:
				lim = _post_z(p.y) - BAY_POST_R - BAY_CLEAR
			if _over_rails(c) and p.y < rise_b.y + BAY_DOWN_R:
				var f := clampf((p.y - rise_a.y) / (rise_b.y - rise_a.y), 0.0, 1.0)
				lim = minf(lim, lerpf(rise_a.x, rise_b.x, f) - BAY_DOWN_R - BAY_CLEAR)
			back = minf(back, lim - (p.z - e.z))
		var ez := minf(want_z, back)
		while ez <= back + 0.0001:
			var dz := ez - e.z
			var kink := _bay_kink(pts, dz)
			var front := _bay_front(pts, dz, low)
			if front >= front_limit and kink.y <= _head.y - 0.06:
				_down_z = front
				_engine_c.z = ez
				_place_cylinders(build)
				_rail_low = _bay_low(_engine_corners())
				# Only bend the backbone when a straight one would run into the engine, and then
				# with a proper drop to the seat rather than a kink in it.
				if kink.y > _seat_front.y - 0.04 + 0.001:
					kink.y = maxf(kink.y, _seat_front.y + 0.08)
					kink.z = _drop_z(kink.y)
					_spine_kink = kink
				return
			ez += 0.01
		_eng_s *= 0.96
		_head_k *= 0.96
		_place_cylinders(build)


## The seat post's middle, as _draw_frame bends it from under the seat to the swingarm pivot:
## its z at height `y`.
func _post_z(y: float) -> float:
	var top := _seat_front + Vector3(0.0, -0.04, -0.02)
	var mid := _seat_front.lerp(_pivot, 0.5) + Vector3(0.0, 0.0, -0.05)
	var bottom := _pivot + Vector3(0.0, 0.05, -0.04)
	if y >= mid.y:
		return lerpf(mid.z, top.z, clampf((y - mid.y) / maxf(top.y - mid.y, 0.001), 0.0, 1.0))
	return lerpf(bottom.z, mid.z, clampf((y - bottom.y) / maxf(mid.y - bottom.y, 0.001), 0.0, 1.0))


## How low the cradle rails run: under the engine wherever it reaches out over them.
func _bay_low(pts: Array) -> float:
	var low := _engine_c.y - 0.17 * _eng_s
	for c in pts:
		if _over_rails(c):
			low = minf(low, (c[0] as Vector3).y - BAY_DOWN_R - BAY_CLEAR * 0.5)
	return low


## Whether a piece (as _engine_corners lists its corners) reaches out over the cradle rails.
static func _over_rails(c: Array) -> bool:
	return float(c[2]) >= BAY_RAIL_X - BAY_DOWN_R - 0.004 and float(c[1]) <= BAY_RAIL_X + BAY_DOWN_R + 0.004


## How far forward (z) the downtubes have to come down in front of the engine moved back by
## `dz`, from the head stock to where they bend back under it as the cradle rails, for every
## point of it to be behind them side on: just ahead of the cases, or further forward to clear a
## tall cylinder leaning forward. -INF when no line from the head stock clears it.
func _bay_front(pts: Array, dz: float, low: float) -> float:
	var top := Vector2(_head_bottom.z + 0.02, _head_bottom.y - 0.01)
	var front_y := _engine_c.y - 0.02
	var front_z := _engine_c.z + dz - 0.17 * _eng_s - 0.075
	var under := Vector2(_engine_c.z + dz - 0.2 * _eng_s, low)
	for c in pts:
		if float(c[1]) > BAY_RAIL_X + BAY_DOWN_R + 0.02:
			continue   # out beyond the tubes (a boxer's heads)
		var p: Vector3 = c[0]
		var z := p.z + dz - BAY_DOWN_R - BAY_CLEAR
		if p.y >= front_y and p.y <= top.y:
			var f := (p.y - front_y) / maxf(top.y - front_y, 0.001)
			if f > 0.999:
				if top.x > z:
					return -INF
				continue
			front_z = minf(front_z, (z - f * top.x) / (1.0 - f))
		elif p.y < front_y and p.y >= under.y:
			var f := (p.y - under.y) / maxf(front_y - under.y, 0.001)
			if f < 0.001:
				if under.x > z:
					return -INF
				continue
			front_z = minf(front_z, (z - (1.0 - f) * under.x) / f)
	return front_z


## How far forward the downtubes can come down before the front tyre, its fork pushed right
## up, would touch them.
func _bay_front_limit(build: BikeBuild) -> float:
	var axle := Vector3(0.0, 0.0, -build.wheelbase * 0.5) + _steer_axis * build.front_travel
	var dy := _engine_c.y - 0.02 - axle.y
	var r := build.front_radius + BAY_DOWN_R + 0.02
	return axle.z + sqrt(maxf(r * r - dy * dy, 0.0))


## Where the backbone has to bend down to the seat to clear the engine moved back by `dz`: over
## the seat's front, high enough that the backbone from the head stock, and the tank sat on it,
## pass over every head.
func _bay_kink(pts: Array, dz: float) -> Vector3:
	var neck := _head + Vector3(0.0, -0.01, 0.02)
	var kink := Vector3(0.0, _seat_front.y - 0.04, _seat_front.z)
	var nose := _head + Vector3(0.0, -0.03, 0.06)
	var rise := tan(deg_to_rad(_geo("tank_slope", 13.0)))
	for step in 6:
		kink.z = _drop_z(kink.y)
		var need := kink.y
		var b := kink + Vector3(0.0, 0.02, 0.0)
		var a_y := minf(nose.y, b.y + rise * maxf(b.z - nose.z, 0.01))
		for c in pts:
			if float(c[1]) > 0.16:
				continue
			var p: Vector3 = (c[0] as Vector3) + Vector3(0.0, 0.0, dz)
			# Under the backbone's line from the neck to the kink...
			var t := (p.z - neck.z) / maxf(kink.z - neck.z, 0.001)
			if t > 0.05 and t <= 1.0:
				need = maxf(need, neck.y + (p.y + BAY_SPINE_R + BAY_CLEAR - neck.y) / t)
			# ...and under the tank sat on it (see _draw_tank), its nose held down to its slope.
			var u := (p.z - nose.z) / maxf(b.z - nose.z, 0.001)
			if u >= 0.0 and u <= 1.0:
				need = maxf(need, kink.y + p.y + BAY_CLEAR - lerpf(a_y, b.y, u))
		kink.y = need
	kink.z = _drop_z(kink.y)
	return kink


## The backbone's drop to the seat (see _fit_bay), leaning back as it comes down: its z at height
## `y`.
func _drop_z(y: float) -> float:
	var seat := _seat_front + Vector3(0.0, -0.04, 0.0)
	return seat.z - maxf(y - seat.y, 0.0) * BAY_DROP_LEAN


## The corners of the engine's cases, barrels, heads and plugs, as _draw_engine, _draw_head and
## _draw_spark_plugs draw them round the cylinders laid out now: [point, the piece's least and greatest distance out from the
## middle (|x|)] each, for fitting the frame round them (see _fit_bay).
func _engine_corners() -> Array:
	var out := []
	var s := _eng_s
	var e := _engine_c
	var half := _block_w * 0.5
	_add_box_corners(out, e, Basis(), Vector3(half, 0.13 * s, 0.17 * s))
	if _build.layout == "2stroke":
		_add_box_corners(out, e + Vector3(0.0, -0.16 * s, 0.02), Basis(), Vector3(_block_w * 0.35, 0.03, 0.12 * s))
	else:
		var sump_w := minf(_block_w * 0.55, 0.16)
		_add_box_corners(out, Vector3(e.x, e.y - 0.13 * s - 0.029, e.z - 0.01), Basis(), Vector3(sump_w * 0.5, 0.03, 0.11 * s))
	# The alternator cover out on the left.
	_add_box_corners(out, e + Vector3(-half - 0.025, -0.015 * s, -0.06 * s), Basis(), Vector3(0.025, 0.085 * s, 0.085 * s))
	for c in _cyls:
		var up: Vector3 = c["up"]
		var fin := _bore_r * 1.55 * _head_k
		_add_box_corners(out, (c["base"] as Vector3) - up * 0.005, _basis_up(up), Vector3(fin, 0.095 * _head_k, fin))
	# The spark plugs and their caps on top of each head, out to the side (see _draw_spark_plugs).
	if _build.layout != "boxer":
		for c in _cyls:
			var up: Vector3 = c["up"]
			_add_box_corners(out, (c["base"] as Vector3) + up * 0.225 + Vector3(0.0, 0.0, 0.02), _basis_up(up), Vector3(0.068, 0.035, 0.025))
	# How far each head reaches up its barrel past the base, and its half width and depth.
	var reach := {"2stroke": [0.145, _bore_r * 1.8, _bore_r * 1.8], "boxer": [0.235, 0.08, 0.085], "vtwin": [0.215, 0.075, 0.085]}
	var head: Array = reach.get(_build.layout, [0.215, 0.06, 0.075])
	var k := _head_k
	var lo := 0.09
	var hi := float(head[0])
	if _cyls.size() > 1 and not _build.layout in ["2stroke", "boxer", "vtwin"]:
		# One long head across the row.
		var first: Dictionary = _cyls[0]
		var last: Dictionary = _cyls[_cyls.size() - 1]
		var up: Vector3 = first["up"]
		var mid: Vector3 = ((first["base"] as Vector3) + (last["base"] as Vector3)) * 0.5
		var span := absf((last["base"] as Vector3).x - (first["base"] as Vector3).x) * 0.5 + 0.08 * k
		_add_box_corners(out, mid + up * (lo + hi) * 0.5, _basis_up(up), Vector3(span, (hi - lo) * 0.5 * k, float(head[2]) * k))
		return out
	for c in _cyls:
		var up: Vector3 = c["up"]
		_add_box_corners(out, (c["base"] as Vector3) + up * (lo + hi) * 0.5, _basis_up(up), Vector3(float(head[1]) * k, (hi - lo) * 0.5 * k, float(head[2]) * k))
	return out


## Adds a box's eight corners (centre `c`, turned by `b`, half sizes `h`) to `out`, the way
## _engine_corners lists them.
static func _add_box_corners(out: Array, c: Vector3, b: Basis, h: Vector3) -> void:
	var corners: Array[Vector3] = []
	var x_lo := INF
	var x_hi := -INF
	for i in 8:
		var p := c + b * Vector3(h.x * (1.0 if i & 1 else -1.0), h.y * (1.0 if i & 2 else -1.0), h.z * (1.0 if i & 4 else -1.0))
		corners.append(p)
		x_lo = minf(x_lo, p.x)
		x_hi = maxf(x_hi, p.x)
	var near := 0.0 if x_lo <= 0.0 and x_hi >= 0.0 else minf(absf(x_lo), absf(x_hi))
	var far := maxf(absf(x_lo), absf(x_hi))
	for p in corners:
		out.append([p, near, far])


func _part_id() -> String:
	return str(_build.parts.get(_current_slot, ""))


func _part() -> Dictionary:
	return PartsDB.get_part(_part_id())


## The colour of the part being drawn: its own paint, or the catalogue colour.
func _col() -> Color:
	var cond: Dictionary = condition.get(_current_slot, {})
	if cond.has("color"):
		return cond["color"]
	return PartsDB.default_color(_part_id())


# ---------------------------------------------------------------------------- chassis

func _draw_frame(build: BikeBuild, zr: float) -> void:
	_current_slot = "frame"
	var style := str(_part().get("style", "cradle"))
	var carbon := _part_id() == "carbon_monocoque"
	var frame_mat := _skin(_mat(_col(), 0.2 if carbon else 0.7, 0.25 if carbon else 0.35, 0.8 if carbon else 0.0))
	frame_mat = _look_finish(str(_look().get("finish", "")), frame_mat)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.7)
	var hb := _head_bottom
	match style:
		"spar":
			var thick := 1.6 if carbon else 1.0
			for side in [-1.0, 1.0]:
				_tube(hb + Vector3(0.09 * side, 0.05, 0.0), _pivot + Vector3(0.12 * side, 0.1, 0.0), 0.045, frame_mat, Vector3(thick, 1.0, 2.2))
				_tube(_pivot + Vector3(0.12 * side, 0.1, 0.0), _pivot + Vector3(0.12 * side, -0.12, 0.02), 0.04, frame_mat)
				_tube(_seat_front + Vector3(0.08 * side, 0.0, 0.0), _tail + Vector3(0.06 * side, 0.0, 0.0), 0.016, frame_mat)
				_tube(_pivot + Vector3(0.1 * side, 0.12, 0.0), _tail + Vector3(0.06 * side, -0.02, -0.05), 0.014, frame_mat)
		"trellis", "adv":
			var adv := style == "adv"
			for side in [-1.0, 1.0]:
				var top := []
				var bottom := []
				for i in 5:
					var f := i / 4.0
					top.append(hb.lerp(_pivot + Vector3(0.0, 0.18, 0.0), f) + Vector3(0.1 * side, 0.08, 0.0))
					bottom.append(hb.lerp(_pivot, f) + Vector3(0.11 * side, -0.12 * sin(f * PI), 0.0))
				for i in 4:
					_tube(top[i], top[i + 1], 0.013 if adv else 0.012, frame_mat)
					_tube(bottom[i], bottom[i + 1], 0.013 if adv else 0.012, frame_mat)
					_tube(top[i], bottom[i + 1], 0.01, frame_mat)
				_tube(top[4], bottom[4], 0.012, frame_mat)
				_tube(_seat_front + Vector3(0.07 * side, 0.0, 0.0), _tail + Vector3(0.06 * side, 0.0, 0.0), 0.012, frame_mat)
				_tube(top[3], _tail + Vector3(0.06 * side, -0.03, -0.05), 0.01, frame_mat)
				if adv:
					# A bolt-on luggage rack: rails out past the tail and a hoop over the back.
					var rail := _rack_mat()
					_bend([_tail + Vector3(0.09 * side, 0.02, -0.25), _tail + Vector3(0.1 * side, 0.03, 0.05), _tail + Vector3(0.08 * side, 0.03, 0.22),
						_tail + Vector3(0.0, 0.03, 0.26)], 0.009, rail)
					_tube(_tail + Vector3(0.1 * side, 0.03, 0.05), _tail + Vector3(0.12 * side, -0.16, 0.0), 0.008, rail)
			if adv:
				_box(_tail + Vector3(0.0, 0.035, 0.1), Vector3(0.16, 0.008, 0.2), _rack_mat())
		"backbone":
			_tube(_head, _pivot + Vector3(0.0, 0.22, 0.0), 0.045, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.22, 0.0), _pivot, 0.035, frame_mat)
			_tube(_seat_front, _tail, 0.018, frame_mat)
			_tube(_pivot + Vector3(0.0, 0.2, 0.0), _tail + Vector3(0.0, -0.03, -0.05), 0.016, frame_mat)
		"softail", "chopper", "cruiser":
			# A single big backbone from the neck to the seat, twin downtubes cradling the
			# engine, and a seat post behind the gearbox down to the swingarm pivot.
			var chop := style == "chopper"
			var spine_mid := _head.lerp(_seat_front, 0.5) + Vector3(0.0, 0.0 if chop else 0.03, 0.0)
			var neck := _head + Vector3(0.0, -0.01, 0.02)
			var seat := _seat_front + Vector3(0.0, -0.04, 0.0)
			if _spine_kink != Vector3.ZERO:
				# Over a big engine the backbone runs back over the heads under the tank, then
				# bends down to the seat behind the back cylinder.
				var k := _spine_kink
				spine_mid = neck.lerp(k, 0.5)
				var bend := [k + (neck - k).normalized() * 0.035, k + (seat - k).normalized() * 0.035]
				_bend([neck, spine_mid, bend[0], bend[1], seat], 0.03 if not chop else 0.032, frame_mat)
			else:
				_bend([neck, spine_mid, seat], 0.03 if not chop else 0.032, frame_mat)
			if chop:
				# A gusset under the stretched neck, where the backbone meets it.
				var gusset := _shell([{"c": _head + Vector3(0.0, -0.06, 0.03), "w": 0.012, "up": 0.04, "down": 0.04, "n": 5.0},
					{"c": _head.lerp(spine_mid, 0.35) + Vector3(0.0, -0.06, 0.0), "w": 0.012, "up": 0.04, "down": 0.01, "n": 5.0}], frame_mat)
				gusset.name = "Gusset"
			# The downtubes come down in front of the engine and run back under its cases as the
			# cradle (see _fit_bay).
			var low_y := _rail_low
			for side in [-1.0, 1.0]:
				var x: float = BAY_RAIL_X * side
				_bend([hb + Vector3(0.045 * side, -0.01, 0.02), Vector3(x, _engine_c.y - 0.02, _down_z),
					Vector3(x, low_y, _engine_c.z - 0.2 * _eng_s), Vector3(x, low_y - 0.01, _pivot.z - BAY_RISE), Vector3(x, _pivot.y - 0.03, _pivot.z - 0.02)], BAY_DOWN_R, frame_mat)
				# Rails from the seat back to the tail, carrying the fender.
				_bend([_seat_front + Vector3(0.07 * side, -0.02, -0.04), _seat_front.lerp(_tail, 0.5) + Vector3(0.075 * side, -0.02, 0.0),
					_tail + Vector3(0.07 * side, -0.03, 0.02)], 0.015, frame_mat)
			_bend([_seat_front + Vector3(0.0, -0.04, -0.02), _seat_front.lerp(_pivot, 0.5) + Vector3(0.0, 0.0, -0.05), _pivot + Vector3(0.0, 0.05, -0.04)], 0.026, frame_mat)
			_tube(_pivot + Vector3(-0.1, 0.0, 0.0), _pivot + Vector3(0.1, 0.0, 0.0), 0.022, frame_mat)
			if style == "cruiser":
				# Twin shocks need upper rails to push against, from the seat post back to the tail.
				for side in [-1.0, 1.0]:
					_bend([_pivot + Vector3(0.09 * side, 0.08, -0.04), _pivot + Vector3(0.12 * side, 0.3, _arm_rest_z() - 0.2), _tail + Vector3(0.075 * side, -0.05, 0.0)], 0.014, frame_mat)
		"perimeter":
			# Two big cast beams wrapped round the engine from the head stock to the pivot, deep
			# pivot plates, and a light subframe kicking up to the tail.
			var wide := maxf(0.15, _block_w * 0.5 + 0.05)
			# Under a full race fairing the beams tuck in along the tank (the engine they'd wrap
			# is out of sight), so they don't stick out of the bodywork.
			var beam := minf(wide, 0.2) if _race_fairing_fitted() else wide
			if beam < wide:
				wide = minf(wide, 0.25)
			for side in [-1.0, 1.0]:
				var path := [hb + Vector3(0.045 * side, 0.04, 0.03), hb.lerp(_pivot, 0.25) + Vector3(beam * side, 0.09, 0.0),
					hb.lerp(_pivot, 0.65) + Vector3(beam * side, 0.1, 0.0), _pivot + Vector3((wide - 0.02) * side, 0.11, -0.06)]
				var smooth := ShapeKit.smooth(path, 4)
				var secs := []
				for k in smooth.size():
					var f := float(k) / (smooth.size() - 1)
					secs.append({"c": smooth[k], "w": 0.022, "up": lerpf(0.05, 0.065, sin(f * PI)), "down": lerpf(0.04, 0.06, sin(f * PI)), "n": 6.0})
				_shell(secs, frame_mat)
				var plate := _shell([{"c": _pivot + Vector3((wide - 0.02) * side, 0.12, -0.06), "w": 0.022, "up": 0.04, "down": 0.04, "n": 6.0},
					{"c": _pivot + Vector3((wide - 0.03) * side, 0.0, -0.02), "w": 0.022, "up": 0.05, "down": 0.05, "n": 6.0},
					{"c": _pivot + Vector3((wide - 0.04) * side, -0.12, 0.0), "w": 0.02, "up": 0.03, "down": 0.03, "n": 6.0}], frame_mat)
				plate.name = "PivotPlate"
				_bend([_pivot + Vector3((wide - 0.04) * side, 0.14, -0.04), _seat_front + Vector3(0.075 * side, -0.02, 0.02), _tail + Vector3(0.05 * side, -0.01, -0.02)], 0.014, frame_mat)
				_tube(_pivot + Vector3((wide - 0.04) * side, 0.06, 0.0), _tail + Vector3(0.05 * side, -0.05, -0.08), 0.012, frame_mat)
		"mx":
			# A single downtube that splits into twin loops under the engine, a big backbone
			# to the top of the pivot, and a subframe sweeping up to the tail.
			var split := Vector3(0.0, _engine_c.y - 0.06, _engine_c.z - 0.22 * _eng_s - 0.05)
			_bend([hb + Vector3(0.0, -0.01, 0.02), hb.lerp(split, 0.55) + Vector3(0.0, 0.0, -0.01), split], 0.022, frame_mat)
			var low_y := _engine_c.y - 0.2 * _eng_s
			var top := _pivot + Vector3(0.0, 0.22, -0.06)
			for side in [-1.0, 1.0]:
				var x: float = 0.06 * side
				_bend([split, Vector3(x, low_y + 0.04, split.z + 0.06), Vector3(x, low_y, _engine_c.z + 0.05),
					Vector3(x + 0.01 * side, low_y + 0.01, _pivot.z - 0.14), Vector3(0.08 * side, _pivot.y - 0.05, _pivot.z - 0.03), _pivot + Vector3(0.09 * side, 0.08, -0.04)], 0.016, frame_mat)
				_bend([top + Vector3(0.0, 0.0, 0.0), _pivot + Vector3(0.09 * side, 0.16, -0.06), _pivot + Vector3(0.09 * side, 0.02, -0.03)], 0.02, frame_mat)
				_bend([top + Vector3(0.05 * side, 0.02, 0.02), _seat_front + Vector3(0.07 * side, 0.0, 0.06), _tail + Vector3(0.06 * side, -0.02, 0.02)], 0.012, frame_mat)
				_tube(_pivot + Vector3(0.08 * side, 0.06, 0.0), _seat_front.lerp(_tail, 0.6) + Vector3(0.065 * side, -0.03, 0.0), 0.011, frame_mat)
			_bend([_head + Vector3(0.0, -0.02, 0.02), _head.lerp(top, 0.5) + Vector3(0.0, 0.03, 0.0), top], 0.034, frame_mat)
		_:
			_tube(_head, _seat_front, 0.024, frame_mat)
			_tube(_seat_front, _tail, 0.018, frame_mat)
			_tube(_seat_front, _pivot, 0.02, frame_mat)
			_tube(_pivot, _tail, 0.016, frame_mat)
			var cradle_front := Vector3(0.0, _engine_c.y - 0.2, _engine_c.z - 0.2)
			var cradle_back := Vector3(0.0, _engine_c.y - 0.2, _pivot.z)
			_tube(hb, cradle_front, 0.024, frame_mat)
			_tube(cradle_front, cradle_back, 0.022, frame_mat)
			_tube(cradle_back, _pivot, 0.022, frame_mat)
	_tube(_head - _steer_axis * 0.02, hb, 0.038, frame_mat)
	if not style in ["softail", "chopper"]:
		_box(Vector3(0.0, 0.06, lerpf(_engine_c.z, _pivot.z, 0.6)), Vector3(0.18, 0.14, 0.14), black)  # battery box
	# The frame's own footpegs, unless a set of rearsets is bolted on in their place.
	var own_pegs := str(build.parts.get("rearsets", "none")) == "none" or not is_fitted("rearsets")
	for side in ([-1.0, 1.0] if own_pegs else []):
		var peg := Vector3(_peg.x * side, _peg.y, _peg.z)
		_box(peg, Vector3(0.1, 0.02, 0.04), black)  # footpegs
		if _peg.z < _pivot.z - 0.2:
			# Forward controls: the pegs stand out on stalks off the downtubes.
			_tube(Vector3(0.08 * side, _peg.y + 0.01, _peg.z + 0.02), peg, 0.011, frame_mat)
		elif absf(_peg.y - 0.02) > 0.04 or absf(_peg.z - _pivot.z) > 0.04:
			# Rearsets: a hanger plate from the frame by the pivot down to the peg.
			_box((peg + Vector3(0.12 * side, _pivot.y, _pivot.z - 0.02)) * 0.5, Vector3(0.012, absf(_peg.y - _pivot.y) + 0.06, 0.06), frame_mat)
	_draw_swingarm(build, zr, frame_mat)


## Which swingarm the bike has: its own (a swingarm part, see SWINGARM_TYPES) if one's fitted,
## else the one its frame comes with ("box", "braced", "softail" or "single").
func _arm_type() -> String:
	var own := PartsDB.get_part(str(_build.parts.get("swingarm", "none"))) if _build else {}
	if not own.is_empty() and is_fitted("swingarm"):
		return str(own.get("arm", "box_section"))
	return str(_frame_geo.get("swingarm", "box"))


## The swingarm, hung off the pivot: plain box arms, tall braced beams, or (on a softail) a
## triangulated rear end that looks rigid but moves as one with the shocks hidden underneath.
## A swingarm part of its own replaces it: a deep box-section arm, a banana arm curving up over
## the exhaust, a braced MX arm with its truss underneath and chain slider, a rigid hardtail rear
## end, or a single-sided arm.
func _draw_swingarm(build: BikeBuild, zr: float, frame_mat: Material) -> void:
	_swingarm = Node3D.new()
	_swingarm.position = _pivot
	add_child(_swingarm)
	_arm_len = Vector3(0.0, 0.0, zr).distance_to(_pivot)
	# The arms clear the back tyre and rim, however fat they are.
	var arm_x := maxf(0.11, maxf(build.rear_tyre_width, rim_width_of(PartsDB.get_part(str(build.parts.get("rear_wheel", ""))))) * 0.5 + 0.035)
	var kind := _arm_type()
	var own := PartsDB.get_part(str(build.parts.get("swingarm", "none")))
	if not own.is_empty() and is_fitted("swingarm"):
		_current_slot = "swingarm"
		var col: Array = own.get("color", [0.1, 0.1, 0.11])
		frame_mat = _mat(Color(col[0], col[1], col[2]), float(own.get("metal", 0.6)), float(own.get("rough", 0.4)))
		if _draw_own_swingarm(kind, arm_x, frame_mat):
			_current_slot = "frame"
			return
	match kind:
		"braced":
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var secs := []
				for k in 6:
					var f := k / 5.0
					secs.append({"c": Vector3(x, 0.0, lerpf(0.0, _arm_len + 0.03, f)), "w": 0.02, "up": lerpf(0.06, 0.035, f), "down": lerpf(0.045, 0.03, f), "n": 5.0})
				_shell(secs, frame_mat, false, 0.0, TAU, _swingarm)
			# The brace arching over the right-hand arm.
			_bend([Vector3(arm_x, 0.05, 0.08), Vector3(arm_x, 0.11, _arm_len * 0.4), Vector3(arm_x, 0.04, _arm_len * 0.78)], 0.014, frame_mat, _swingarm)
			for f in [0.3, 0.55]:
				_tube(Vector3(arm_x, 0.03, _arm_len * f), Vector3(arm_x, 0.1, _arm_len * f), 0.008, frame_mat, Vector3.ONE, _swingarm)
		"single":
			# A single-sided arm (a Ducati, an RC30): one deep, cast beam down the chain side
			# with the wheel hung off it, the right-hand side of the wheel left bare.
			var x := -arm_x - 0.01
			var secs := []
			for k in 7:
				var f := k / 6.0
				secs.append({"c": Vector3(x, 0.01 * sin(f * PI), lerpf(0.0, _arm_len, f)), "w": lerpf(0.04, 0.03, f),
					"up": lerpf(0.075, 0.06, f), "down": lerpf(0.06, 0.05, f), "n": 3.0})
			var beam := _shell(secs, frame_mat, false, 0.0, TAU, _swingarm)
			beam.name = "SingleSidedArm"
			_mesh_instance(_cylinder(0.075, 0.05), frame_mat, Vector3(x + 0.02, 0.0, _arm_len), _swingarm).rotation.z = PI * 0.5
			# The big centre nut on the bare side.
			var nut := _mesh_instance(_cylinder(0.035, 0.03, 0.035, 6), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15),
				Vector3(arm_x - 0.02, 0.0, _arm_len), _swingarm)
			nut.rotation.z = PI * 0.5
			_box(Vector3(0.0, 0.0, 0.04), Vector3(arm_x + 0.03, 0.07, 0.05), frame_mat, _swingarm).position.x = -arm_x * 0.5
			_current_slot = "frame"
			return
		"softail":
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var axle := Vector3(x, 0.0, _arm_len)
				var post := _to_arm(Vector3(x, _seat_front.y - 0.05, _pivot.z + 0.14))
				var top := _to_arm(Vector3(0.09 * side, _pivot.y + 0.1, _pivot.z - 0.02))
				_tube(Vector3(0.09 * side, 0.0, 0.0), axle, 0.02, frame_mat, Vector3.ONE, _swingarm)
				_tube(axle, post, 0.017, frame_mat, Vector3.ONE, _swingarm)
				_tube(post, top, 0.017, frame_mat, Vector3.ONE, _swingarm)
				_box(axle, Vector3(0.02, 0.06, 0.07), frame_mat, _swingarm)   # axle plate
			var cross := _to_arm(Vector3(0.0, _seat_front.y - 0.05, _pivot.z + 0.14))
			_tube(cross - Vector3(arm_x, 0.0, 0.0), cross + Vector3(arm_x, 0.0, 0.0), 0.014, frame_mat, Vector3.ONE, _swingarm)
		_:
			for side in [-1.0, 1.0]:
				_box(Vector3(arm_x * side, 0.0, _arm_len * 0.5), Vector3(0.035, 0.07, _arm_len), frame_mat, _swingarm)
	_box(Vector3(0.0, 0.0, 0.04), Vector3(arm_x * 2.0 + 0.02, 0.07, 0.05), frame_mat, _swingarm)
	_current_slot = "frame"


## The swingarm parts' own shapes (see _draw_swingarm). False for one drawn the frame's way.
func _draw_own_swingarm(kind: String, arm_x: float, mat: Material) -> bool:
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.1, 0.7)
	var steel := _mat(Color(0.75, 0.76, 0.78), 1.0, 0.25)
	match kind:
		"box_section":
			# Deep, tapered box-section arms (an extrusion, welded at the pivot), with the axle
			# in slotted end blocks and a chain adjuster bolt behind each.
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var secs := []
				for k in 7:
					var f := k / 6.0
					secs.append({"c": Vector3(x, 0.012 * sin(f * PI), lerpf(0.0, _arm_len - 0.02, f)), "w": 0.022,
						"up": lerpf(0.055, 0.032, f), "down": lerpf(0.05, 0.03, f), "n": 7.0})
				_shell(secs, mat, false, 0.0, TAU, _swingarm).name = "BoxArm"
				_box(Vector3(x, 0.0, _arm_len), Vector3(0.05, 0.06, 0.09), mat, _swingarm)
				_tube(Vector3(x, 0.0, _arm_len + 0.045), Vector3(x, 0.0, _arm_len + 0.075), 0.006, steel, Vector3.ONE, _swingarm)
			_tube(Vector3(-arm_x, 0.0, _arm_len * 0.36), Vector3(arm_x, 0.0, _arm_len * 0.36), 0.016, mat, Vector3.ONE, _swingarm)
		"banana":
			# The banana arm (a two-stroke racer's, an RD's): the arms bow up in a long curve so
			# the expansion chambers tuck in underneath, the right-hand one the most.
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var bow := 0.11 if side > 0.0 else 0.07
				var secs := []
				for k in 9:
					var f := k / 8.0
					secs.append({"c": Vector3(x, bow * sin(pow(f, 0.85) * PI) * (1.0 - 0.25 * f), lerpf(0.0, _arm_len, f)), "w": 0.02,
						"up": lerpf(0.045, 0.03, f), "down": lerpf(0.04, 0.028, f), "n": 4.0})
				_shell(secs, mat, false, 0.0, TAU, _swingarm).name = "BananaArm"
				_box(Vector3(x, 0.0, _arm_len), Vector3(0.04, 0.055, 0.075), mat, _swingarm)
			_tube(Vector3(-arm_x, 0.06, _arm_len * 0.4), Vector3(arm_x, 0.08, _arm_len * 0.4), 0.014, mat, Vector3.ONE, _swingarm)
		"braced_mx":
			# A motocrosser's arm: tall alloy box arms with a truss braced underneath each one,
			# a rubber chain slider over the front of the left arm and a chain guide at the back.
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var secs := []
				for k in 7:
					var f := k / 6.0
					secs.append({"c": Vector3(x, 0.0, lerpf(0.0, _arm_len - 0.02, f)), "w": 0.02,
						"up": lerpf(0.05, 0.03, f), "down": lerpf(0.06, 0.03, f), "n": 6.0})
				_shell(secs, mat, false, 0.0, TAU, _swingarm).name = "MxArm"
				var low := [Vector3(x, -0.05, 0.06), Vector3(x, -0.1, _arm_len * 0.38), Vector3(x, -0.05, _arm_len * 0.78)]
				_bend(low, 0.013, mat, _swingarm)
				for f in [0.22, 0.42, 0.62]:
					var y := -0.05 - 0.05 * sin(clampf(f / 0.78, 0.0, 1.0) * PI)
					_tube(Vector3(x, -0.03, _arm_len * f), Vector3(x, y + 0.005, _arm_len * f), 0.007, mat, Vector3.ONE, _swingarm)
				_box(Vector3(x, 0.0, _arm_len), Vector3(0.045, 0.06, 0.08), mat, _swingarm)
			_box(Vector3(-arm_x, 0.04, _arm_len * 0.22), Vector3(0.03, 0.025, _arm_len * 0.4), dark, _swingarm).name = "ChainSlider"
			_box(Vector3(-arm_x - 0.005, -0.07, _arm_len * 0.8), Vector3(0.03, 0.06, 0.12), dark, _swingarm).name = "ChainGuide"
		"hardtail":
			# No swingarm at all: a rigid rear end, chain stays straight back from the frame to
			# the axle plates and seat stays up to the frame under the seat, bobber-style. The
			# shocks hide (see _draw_shock), so it rides as a hardtail looks.
			for side in [-1.0, 1.0]:
				var x: float = arm_x * side
				var axle := Vector3(x, 0.0, _arm_len)
				var top := _to_arm(Vector3(0.1 * side, _seat_front.y - 0.02, _pivot.z + 0.05))
				_tube(Vector3(0.09 * side, 0.0, 0.0), axle, 0.019, mat, Vector3.ONE, _swingarm)
				_tube(axle, top, 0.018, mat, Vector3.ONE, _swingarm).name = "SeatStay"
				_box(axle, Vector3(0.016, 0.075, 0.09), mat, _swingarm)   # the axle plate
			var cross := _to_arm(Vector3(0.0, _seat_front.y - 0.06, _pivot.z + 0.12))
			_tube(cross - Vector3(arm_x * 0.85, 0.0, 0.0), cross + Vector3(arm_x * 0.85, 0.0, 0.0), 0.013, mat, Vector3.ONE, _swingarm)
		_:
			return false
	_box(Vector3(0.0, 0.0, 0.04), Vector3(arm_x * 2.0 + 0.02, 0.07, 0.05), mat, _swingarm)
	return true


## A point in the model's space, at rest, as seen from the swingarm (whose +Z runs to the axle).
func _to_arm(p: Vector3) -> Vector3:
	var to_axle := Vector3(0.0, 0.0, _build.wheelbase * 0.5) - _pivot
	var rest := Basis(Vector3.RIGHT, -atan2(to_axle.y, to_axle.z))
	return rest.inverse() * (p - _pivot)


## How far back from the pivot the rear axle is, along the ground.
func _arm_rest_z() -> float:
	return _build.wheelbase * 0.5 - _pivot.z


func _rack_mat() -> StandardMaterial3D:
	return _mat(Color(0.08, 0.08, 0.09), 0.6, 0.45)


## Tanks are lofted along the frame's top tube: their underside sits on the line from the head
## stock back to the front of the seat, they butt up against the seat, and each style has its
## own shape (knee dents on a café tank, the airbox hump on a sport tank, a teardrop peanut).
## Profiles: [share of the length, half-width, rise above, drop below] from nose to tail.
const TANK_SHAPES := {
	"cafe": {"len": 0.62, "n": 2.6, "bw": 0.8, "keys": [[0.0, 0.07, 0.05, 0.04], [0.12, 0.13, 0.11, 0.06], [0.35, 0.155, 0.13, 0.07],
		[0.6, 0.14, 0.12, 0.07], [0.8, 0.115, 0.1, 0.065], [0.95, 0.1, 0.07, 0.05], [1.0, 0.06, 0.03, 0.03]]},
	"peanut": {"len": 0.44, "n": 2.2, "bw": 0.75, "keys": [[0.0, 0.05, 0.04, 0.03], [0.2, 0.1, 0.09, 0.05], [0.5, 0.115, 0.1, 0.06],
		[0.8, 0.09, 0.08, 0.05], [1.0, 0.04, 0.03, 0.02]]},
	"sport": {"len": 0.56, "n": 3.4, "bw": 0.85, "keys": [[0.0, 0.1, 0.08, 0.06], [0.15, 0.17, 0.15, 0.09], [0.4, 0.19, 0.16, 0.1],
		[0.65, 0.16, 0.12, 0.09], [0.85, 0.12, 0.08, 0.07], [1.0, 0.08, 0.04, 0.04]]},
	"enduro": {"len": 0.5, "n": 2.4, "bw": 0.9, "keys": [[0.0, 0.06, 0.05, 0.05], [0.2, 0.12, 0.09, 0.08], [0.5, 0.13, 0.1, 0.08],
		[0.8, 0.1, 0.07, 0.06], [1.0, 0.05, 0.03, 0.03]]},
	"touring": {"len": 0.66, "n": 2.6, "bw": 0.85, "keys": [[0.0, 0.1, 0.07, 0.06], [0.15, 0.18, 0.14, 0.11], [0.45, 0.21, 0.16, 0.13],
		[0.75, 0.19, 0.14, 0.12], [0.92, 0.14, 0.1, 0.09], [1.0, 0.09, 0.05, 0.05]]},
	# Shapes a part can ask for by its look (see _look): the teardrop of a 50s classic, a slab-sided
	# 70s tank, a coffin, a big split cruiser tank, a slim Sportster peanut, a little Wassell, a
	# long café tank with deep knee cut-outs and a long low pointed one.
	"teardrop": {"len": 0.52, "n": 2.3, "bw": 0.8, "keys": [[0.0, 0.06, 0.05, 0.04], [0.15, 0.13, 0.11, 0.07], [0.35, 0.145, 0.12, 0.075],
		[0.7, 0.11, 0.09, 0.06], [1.0, 0.045, 0.03, 0.025]]},
	"slab": {"len": 0.6, "n": 3.8, "bw": 0.85, "keys": [[0.0, 0.08, 0.06, 0.05], [0.12, 0.14, 0.12, 0.08], [0.7, 0.14, 0.12, 0.08],
		[0.92, 0.12, 0.09, 0.07], [1.0, 0.07, 0.04, 0.04]]},
	"coffin": {"len": 0.5, "n": 5.0, "bw": 0.95, "keys": [[0.0, 0.07, 0.06, 0.04], [0.08, 0.11, 0.09, 0.06], [0.9, 0.11, 0.09, 0.06],
		[1.0, 0.07, 0.05, 0.04]]},
	"fatbob": {"len": 0.64, "n": 2.8, "bw": 0.9, "keys": [[0.0, 0.1, 0.08, 0.07], [0.15, 0.18, 0.15, 0.1], [0.5, 0.2, 0.16, 0.11],
		[0.85, 0.17, 0.13, 0.09], [1.0, 0.1, 0.06, 0.05]]},
	"sportster": {"len": 0.52, "n": 2.2, "bw": 0.8, "keys": [[0.0, 0.05, 0.04, 0.03], [0.2, 0.095, 0.085, 0.05], [0.55, 0.105, 0.095, 0.055],
		[0.85, 0.08, 0.07, 0.045], [1.0, 0.035, 0.025, 0.02]]},
	"wassell": {"len": 0.38, "n": 2.6, "bw": 0.85, "keys": [[0.0, 0.05, 0.05, 0.03], [0.2, 0.09, 0.1, 0.05], [0.6, 0.09, 0.1, 0.05],
		[1.0, 0.04, 0.03, 0.02]]},
	"kneedent": {"len": 0.66, "n": 2.6, "bw": 0.8, "keys": [[0.0, 0.07, 0.05, 0.04], [0.12, 0.135, 0.11, 0.06], [0.35, 0.155, 0.13, 0.07],
		[0.62, 0.1, 0.12, 0.07], [0.8, 0.105, 0.1, 0.065], [0.95, 0.09, 0.07, 0.05], [1.0, 0.05, 0.03, 0.03]]},
	# Creased, angular shapes for the modern bikes: an adventure bike's tall, wide-shouldered tank
	# that tapers back to a narrow waist, a supermoto's low flat slab, and a Bonneville-style
	# classic tank, long and level with a low crown.
	"adv": {"len": 0.58, "n": 1.8, "bw": 0.9, "keys": [[0.0, 0.11, 0.06, 0.11], [0.15, 0.18, 0.1, 0.15], [0.45, 0.17, 0.085, 0.12],
		[0.75, 0.13, 0.065, 0.08], [1.0, 0.08, 0.03, 0.05]]},
	"sm": {"len": 0.46, "n": 1.9, "bw": 0.9, "keys": [[0.0, 0.08, 0.05, 0.07], [0.2, 0.14, 0.075, 0.1], [0.6, 0.12, 0.065, 0.08],
		[1.0, 0.06, 0.03, 0.04]]},
	"bonnie": {"len": 0.56, "n": 2.4, "bw": 0.8, "keys": [[0.0, 0.07, 0.045, 0.04], [0.15, 0.13, 0.08, 0.06], [0.5, 0.145, 0.088, 0.065],
		[0.85, 0.12, 0.072, 0.055], [1.0, 0.06, 0.03, 0.03]]},
	"spitfire": {"len": 0.68, "n": 2.4, "bw": 0.8, "keys": [[0.0, 0.03, 0.03, 0.02], [0.2, 0.11, 0.08, 0.05], [0.5, 0.14, 0.1, 0.06],
		[0.8, 0.12, 0.09, 0.055], [1.0, 0.06, 0.03, 0.03]]},
}


func _draw_tank() -> void:
	_current_slot = "tank"
	var p := _part()
	var look := _look()
	var mat := _skin(_mat(_col(), 0.25, 0.2, 0.6))
	var style := str(p.get("style", "cafe"))
	var shape_key := str(look.get("shape", style))
	var shape: Dictionary = TANK_SHAPES.get(shape_key, TANK_SHAPES.get(style, TANK_SHAPES["cafe"]))
	var size := pow(float(p.get("capacity", 15.0)) / 15.0, 0.33)
	var sc := _look_vec("scale", Vector3.ONE)   # length, width, height
	# The top tube, from the head stock back to the front of the seat.
	var a := _head + Vector3(0.0, -0.03, 0.06)
	var b := _seat_front + Vector3(0.0, 0.03, 0.0)
	if _spine_kink != Vector3.ZERO:
		# On a backbone bent over a big engine, the tank sits on its top run (see _fit_bay).
		b = _spine_kink + Vector3(0.0, 0.02, 0.0)
	# Real tanks sit nearly level along the frame: cap the nose-up slope so a tall head stock
	# (scramblers, classics on long forks) doesn't stand the tank up on end.
	var max_rise := tan(deg_to_rad(_geo("tank_slope", 13.0))) * maxf(b.z - a.z, 0.01)
	if a.y - b.y > max_rise:
		a.y = b.y + max_rise
	_tank_a = a
	_tank_b = b
	var back := b.z + 0.03
	var room := back - (a.z + 0.03)
	var length := clampf(float(shape["len"]) * lerpf(0.85, 1.0, size) * sc.x, 0.25, maxf(room, 0.25))
	length = minf(length, room)
	var front := back - length
	var secs := []
	var keys: Array = shape["keys"]
	var steps := 14
	for i in steps + 1:
		var u := float(i) / steps
		var k := _key_at(keys, u)
		var z := lerpf(front, back, u)
		var base_y := lerpf(a.y, b.y, clampf((z - a.z) / maxf(b.z - a.z, 0.01), 0.0, 1.0))
		var down: float = k[2] * size * sc.z
		secs.append({"c": Vector3(0.0, base_y + down, z), "w": k[0] * size * sc.y, "up": k[1] * size * sc.z, "down": down,
			"n": shape["n"], "bw": shape["bw"]})
	var body := _shell(secs, mat)
	body.name = "TankBody"
	_tank_secs = secs
	if look.get("shrouds", false):
		# Radiator shrouds: angular plastic wings either side of the tank, from the head stock
		# back to the seat and down over the radiator and the top of the engine, the way a
		# motard is dressed. They fill the space a bare frame leaves between tank and engine.
		var shroud_mat := _mat(_accent(_col()), 0.0, 0.45)
		var flash_mat := _mat(_col(), 0.0, 0.45)
		for side in [-1.0, 1.0]:
			var panel := []
			var stripe := []
			for k in 5:
				var f := k / 4.0
				var z := lerpf(front + 0.02, back - 0.1, f)
				var top := tank_base_y(z) + lerpf(0.06, 0.02, f)
				var bottom := top - lerpf(0.26, 0.1, f) * _eng_s
				var x := lerpf(0.13, 0.11, f) + 0.02 * sin(f * PI)
				panel.append({"c": Vector3(x * side, (top + bottom) * 0.5, z), "w": 0.007, "up": (top - bottom) * 0.5, "down": (top - bottom) * 0.5, "n": 5.0})
				stripe.append({"c": Vector3((x + 0.006) * side, top - (top - bottom) * 0.3, z), "w": 0.003, "up": 0.012, "down": 0.012, "n": 5.0})
			_shell(panel, shroud_mat).name = "TankShroud"
			_shell(stripe, flash_mat)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15)
	var accent := _mat(_accent(), 0.3, 0.25, 0.6)
	# Paint schemes over the base colour: the top in a second colour, pinstripes along the
	# sides, twin racing stripes over the top, or a band round the middle.
	var paint_look := str(look.get("paint", ""))
	match paint_look:
		"two_tone":
			_shell(_grown(secs, 1.012, 1, steps - 1), accent, true, 0.35, PI - 0.35)
		"band":
			_shell(_grown(secs, 1.015, roundi(steps * 0.38), roundi(steps * 0.62)), accent, false)
		"racing":
			for x in [-0.028, 0.028]:
				var path := []
				for s in secs.slice(1, steps):
					path.append(_on_loft(s, PI * 0.5 + x * 6.0, 1.004))
				_bend(path, 0.009, accent, self, 6)
		"scallop":
			for side in [-1.0, 1.0]:
				var path := []
				for i in range(1, roundi(steps * 0.7)):
					var f := float(i) / (steps * 0.7)
					path.append(_on_loft(secs[i], (0.15 + 0.55 * sin(f * PI)) if side > 0.0 else PI - (0.15 + 0.55 * sin(f * PI)), 1.004))
				_bend(path, 0.012, accent, self, 6)
		"pin":
			for side in [-1.0, 1.0]:
				for lift in [0.25, 0.4]:
					var path := []
					for s in secs.slice(1, steps):
						path.append(_on_loft(s, lift if side > 0.0 else PI - lift, 1.004))
					_bend(path, 0.0028, accent, self, 5)
	# The filler cap on top, a third of the way back: a plain cap, a raised Monza flip cap, a flush
	# aircraft cap, or two of them on a cruiser's split tank.
	var cap_s: Dictionary = secs[roundi(steps * 0.3)]
	var cap_at: Vector3 = cap_s["c"] + Vector3(0.0, float(cap_s["up"]) - 0.004, 0.0)
	filler = cap_at
	match str(look.get("cap", "stock")):
		"monza":
			_mesh_instance(_cylinder(0.045, 0.03, 0.04), chrome, cap_at + Vector3(0.0, 0.01, 0.0), self)
			_box(cap_at + Vector3(0.0, 0.03, 0.03), Vector3(0.03, 0.012, 0.03), chrome)
		"flush":
			_mesh_instance(_cylinder(0.04, 0.006), chrome, cap_at + Vector3(0.0, 0.002, 0.0), self)
		"twin":
			for x in [-0.05, 0.05]:
				_mesh_instance(_cylinder(0.03, 0.02), chrome, cap_at + Vector3(x, -0.004, 0.0), self)
		_:
			_mesh_instance(_cylinder(0.035, 0.02), chrome, cap_at, self)
	# A chrome console down the middle of a cruiser tank, with the speedo set in it.
	if look.get("console", false):
		var path := []
		for s in secs.slice(roundi(steps * 0.35), roundi(steps * 0.85)):
			path.append(_on_loft(s, PI * 0.5, 1.0))
		_bend(path, 0.03, chrome, self, 10)
		var dial := _mesh_instance(_cylinder(0.035, 0.012), _mat(Color(0.05, 0.05, 0.05), 0.3, 0.3), path[1] + Vector3(0.0, 0.02, 0.0), self)
		dial.rotation.x = -0.3
	# Badges on the sides: a chrome oval, a big round roundel, a long winged script or none.
	var badge_s: Dictionary = secs[roundi(steps * 0.3)]
	var badge := str(look.get("badge", "oval"))
	for side in ([-1.0, 1.0] if badge != "none" else []):
		var at: Vector3 = badge_s["c"] + Vector3(float(badge_s["w"]) * 0.97 * side, float(badge_s["up"]) * 0.05, 0.0)
		var bm := _mesh_instance(_sphere(0.03), chrome if badge != "roundel" else accent, at, self)
		match badge:
			"roundel":
				bm.scale = Vector3(0.12, 1.1, 1.1)
				var inner := _mesh_instance(_sphere(0.018), chrome, at + Vector3(0.003 * side, 0.0, 0.0), self)
				inner.scale = Vector3(0.12, 1.0, 1.0)
			"wing":
				bm.scale = Vector3(0.1, 0.35, 2.6)
			_:
				bm.scale = Vector3(0.15, 0.55, 1.1)
	var pads := bool(look.get("pads", style in ["cafe", "peanut"] and not p.get("lightweight", false)))
	if pads:
		var pad_s: Dictionary = secs[roundi(steps * 0.72)]
		var rubber := _tex(_mat(Color(0.05, 0.05, 0.05), 0.0, 0.85), "grain", 18.0, 1.4)
		for side in [-1.0, 1.0]:
			var at: Vector3 = pad_s["c"] + Vector3(float(pad_s["w"]) * 0.93 * side, -float(pad_s["down"]) * 0.1, 0.0)
			var pad := _mesh_instance(_sphere(0.05), rubber, at, self)
			pad.scale = Vector3(0.18, 0.75, 1.3)
	if style == "sport" and not look.get("no_pad", false):
		# A grippy pad over the back of a sports tank, where the rider's chest lands.
		var pad_mat := _tex(_mat(Color(0.06, 0.06, 0.065), 0.0, 0.8), "grain", 22.0, 1.5)
		var top_pad := _shell(_grown(secs, 1.01, roundi(steps * 0.62), steps - 1), pad_mat, true, PI * 0.5 - 0.55, PI * 0.5 + 0.55)
		top_pad.name = "TankPad"
	if style == "enduro":
		# Radiator shrouds flaring forward either side of the tank.
		for side in [-1.0, 1.0]:
			var top: Dictionary = secs[2]
			var c: Vector3 = top["c"]
			_shell([{"c": c + Vector3(0.14 * side, 0.02, 0.07), "w": 0.012, "up": 0.04, "down": 0.03, "n": 3.0},
				{"c": c + Vector3(0.16 * side, -0.06, 0.035), "w": 0.012, "up": 0.08, "down": 0.1, "n": 3.0},
				{"c": c + Vector3(0.155 * side, -0.12, -0.01), "w": 0.012, "up": 0.06, "down": 0.1, "n": 3.0},
				{"c": c + Vector3(0.13 * side, -0.16, -0.035), "w": 0.01, "up": 0.02, "down": 0.04, "n": 3.0}], mat)


## Loft sections `from`..`to` (inclusive) made a little bigger all round, for paint laid over a shell.
static func _grown(secs: Array, by: float, from: int, to: int) -> Array:
	var out := []
	for i in range(from, mini(to, secs.size() - 1) + 1):
		var s: Dictionary = (secs[i] as Dictionary).duplicate()
		s["w"] = float(s["w"]) * by + 0.001
		s["up"] = float(s["up"]) * by + 0.001
		s["down"] = float(s.get("down", s["up"])) * by + 0.001
		out.append(s)
	return out


## A point on a loft section's skin at angle `a` (0 the right side, PI/2 the top; see ShapeKit),
## pushed out by `grow`. Sections are taken as standing upright, which tanks and seats nearly do.
static func _on_loft(s: Dictionary, a: float, grow := 1.0) -> Vector3:
	var e := 2.0 / float(s.get("n", 2.4))
	var ca := cos(a)
	var sa := sin(a)
	var w := float(s["w"]) * (float(s.get("bw", 1.0)) if sa < 0.0 else 1.0)
	var x := signf(ca) * pow(absf(ca), e) * w
	var y := signf(sa) * pow(absf(sa), e) * (float(s["up"]) if sa > 0.0 else float(s.get("down", s["up"])))
	return (s["c"] as Vector3) + Vector3(x, y, 0.0) * grow


## The part being drawn's extra look (its "look" in data/parts.json): shapes, paint schemes,
## caps, badges and the like that make two parts of the same kind look different.
func _look() -> Dictionary:
	return _part().get("look", {})


## A look setting given as [x, y, z], or `default`.
func _look_vec(key: String, default: Vector3) -> Vector3:
	var v = _look().get(key)
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else default


## The part's second colour (stripes, a two-tone top, piping), or `default`.
func _accent(default := Color(0.95, 0.93, 0.88)) -> Color:
	var a = _look().get("accent")
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else default


## A profile key list's [half-width, rise, drop] at `u` along it.
static func _key_at(keys: Array, u: float) -> Array:
	for i in keys.size() - 1:
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if u <= float(k1[0]):
			var f := (u - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.0001)
			f = f * f * (3.0 - 2.0 * f)
			return [lerpf(k0[1], k1[1], f), lerpf(k0[2], k1[2], f), lerpf(k0[3], k1[3], f)]
	var last: Array = keys[keys.size() - 1]
	return [last[1], last[2], last[3]]


## Seats are lofted along the seat rails, from the front of the seat back to the tail:
## [share of the length, half-width, rise above the rail, drop below, lift of the middle].
const SEAT_SHAPES := {
	"bench": {"n": 3.2, "from": -0.02, "to": 0.02, "keys": [[0.0, 0.1, 0.02, 0.03, 0.0], [0.08, 0.13, 0.04, 0.035, 0.0], [0.5, 0.14, 0.045, 0.035, -0.005],
		[0.92, 0.13, 0.04, 0.035, 0.0], [1.0, 0.1, 0.02, 0.03, 0.0]]},
	"cafe": {"n": 3.0, "from": -0.02, "to": 0.0, "keys": [[0.0, 0.1, 0.02, 0.03, 0.0], [0.08, 0.12, 0.035, 0.03, 0.0], [0.5, 0.125, 0.035, 0.03, -0.005],
		[0.6, 0.12, 0.035, 0.03, 0.0], [0.7, 0.11, 0.06, 0.06, 0.035], [0.88, 0.1, 0.06, 0.07, 0.06], [1.0, 0.06, 0.03, 0.05, 0.045]]},
	"enduro": {"n": 4.0, "from": -0.32, "to": 0.06, "keys": [[0.0, 0.06, 0.03, 0.03, 0.04], [0.12, 0.09, 0.045, 0.04, 0.035], [0.4, 0.1, 0.05, 0.04, 0.0],
		[0.9, 0.095, 0.045, 0.04, 0.0], [1.0, 0.07, 0.025, 0.035, 0.0]]},
	"sport": {"n": 3.0, "from": -0.02, "to": 0.04, "keys": [[0.0, 0.1, 0.02, 0.025, 0.0], [0.1, 0.12, 0.03, 0.03, 0.0], [0.42, 0.12, 0.03, 0.03, 0.0],
		[0.55, 0.105, 0.05, 0.05, 0.03], [0.85, 0.08, 0.06, 0.07, 0.07], [1.0, 0.05, 0.03, 0.06, 0.08]]},
	"touring": {"n": 3.4, "from": -0.03, "to": 0.02, "keys": [[0.0, 0.12, 0.03, 0.04, 0.0], [0.1, 0.17, 0.05, 0.05, -0.005], [0.42, 0.175, 0.05, 0.05, -0.015],
		[0.55, 0.16, 0.06, 0.05, 0.04], [0.85, 0.16, 0.065, 0.05, 0.05], [1.0, 0.12, 0.04, 0.04, 0.05]]},
	# Shapes a part can ask for by its look: a thin flat brat seat, a stepped two-up cruiser seat,
	# a king-and-queen with the pillion perched up high, a sprung solo pan, a gunfighter solo that
	# swoops down at the front, a long café hump and a thin flat-track seat.
	"brat": {"n": 4.5, "from": -0.02, "to": 0.06, "keys": [[0.0, 0.11, 0.015, 0.02, 0.0], [0.05, 0.12, 0.025, 0.02, 0.0], [0.95, 0.12, 0.025, 0.02, 0.0],
		[1.0, 0.11, 0.015, 0.02, 0.0]]},
	"stepped": {"n": 3.2, "from": -0.03, "to": 0.04, "keys": [[0.0, 0.13, 0.03, 0.035, 0.0], [0.1, 0.17, 0.05, 0.04, -0.01], [0.38, 0.17, 0.05, 0.04, -0.015],
		[0.5, 0.13, 0.06, 0.04, 0.04], [0.6, 0.12, 0.04, 0.04, 0.06], [0.95, 0.12, 0.04, 0.04, 0.065], [1.0, 0.1, 0.02, 0.03, 0.06]]},
	"king_queen": {"n": 3.2, "from": -0.03, "to": 0.04, "keys": [[0.0, 0.13, 0.03, 0.035, 0.0], [0.1, 0.17, 0.05, 0.04, -0.01], [0.38, 0.17, 0.05, 0.04, -0.015],
		[0.5, 0.13, 0.08, 0.04, 0.07], [0.6, 0.12, 0.05, 0.04, 0.11], [0.95, 0.12, 0.05, 0.04, 0.11], [1.0, 0.1, 0.03, 0.03, 0.11]]},
	"solo": {"n": 3.0, "from": -0.02, "to": 0.0, "span": 0.55, "keys": [[0.0, 0.08, 0.02, 0.02, 0.0], [0.15, 0.12, 0.035, 0.025, 0.0],
		[0.75, 0.14, 0.045, 0.025, 0.01], [1.0, 0.12, 0.03, 0.025, 0.02]]},
	"gunfighter": {"n": 3.0, "from": -0.06, "to": 0.0, "span": 0.7, "keys": [[0.0, 0.07, 0.02, 0.03, -0.02], [0.2, 0.13, 0.04, 0.03, -0.01],
		[0.6, 0.15, 0.05, 0.03, 0.0], [0.85, 0.14, 0.07, 0.03, 0.04], [1.0, 0.11, 0.04, 0.03, 0.06]]},
	"hump_long": {"n": 3.0, "from": -0.02, "to": 0.04, "keys": [[0.0, 0.1, 0.02, 0.03, 0.0], [0.08, 0.12, 0.035, 0.03, 0.0], [0.45, 0.125, 0.035, 0.03, -0.005],
		[0.55, 0.12, 0.05, 0.05, 0.02], [0.75, 0.11, 0.08, 0.08, 0.06], [0.92, 0.09, 0.07, 0.08, 0.07], [1.0, 0.05, 0.03, 0.05, 0.05]]},
	"flat_track": {"n": 4.0, "from": -0.02, "to": 0.08, "keys": [[0.0, 0.08, 0.02, 0.02, 0.0], [0.1, 0.1, 0.03, 0.025, 0.0], [0.8, 0.1, 0.03, 0.025, 0.01],
		[0.9, 0.09, 0.06, 0.06, 0.05], [1.0, 0.07, 0.04, 0.05, 0.05]]},
}


func _draw_saddle() -> void:
	_current_slot = "saddle"
	var p := _part()
	var look := _look()
	var mat := _mat(_col(), 0.0, 0.6)
	# The cover: diamond quilting, or leather or vinyl grain.
	_tex(mat, "quilt" if str(look.get("pattern", "")) == "diamond" else "grain")
	var y := _seat_y
	var style := str(p.get("style", "bench"))
	var shape: Dictionary = SEAT_SHAPES.get(str(look.get("shape", style)), SEAT_SHAPES.get(style, SEAT_SHAPES["bench"]))
	var sc := _look_vec("scale", Vector3.ONE)   # length, width, height
	var z0 := _seat_front.z + float(shape["from"])
	var z1 := _tail.z + float(shape["to"])
	# A solo seat only covers the front of the rails; the rest is left bare (or for a pillion pad).
	z1 = lerpf(z0, z1, float(shape.get("span", 1.0)) * sc.x)
	var keys: Array = shape["keys"]
	var secs := []
	var steps := 16
	for i in steps + 1:
		var u := float(i) / steps
		var k := _seat_key_at(keys, u)
		var z := lerpf(z0, z1, u)
		# The rail rises from the front of the seat to the tail with the frame.
		var rail_y := y + lerpf(0.0, _tail.y - (_seat_y - 0.02), (z - z0) / maxf(_tail.z - z0, 0.01)) * 0.5
		secs.append({"c": Vector3(0.0, rail_y + k[3] * sc.z, z), "w": k[0] * sc.y, "up": k[1] * sc.z, "down": k[2], "n": shape["n"], "bw": 0.85})
	var pad := _shell(secs, mat)
	pad.name = "SeatPad"
	if style == "touring" and not look.has("shape"):
		var back := _box(Vector3(0.0, y + 0.22, z1 + 0.04), Vector3(0.3, 0.26, 0.06), mat)
		back.rotation.x = 0.2
	var seam := _mat(_accent(_col().darkened(0.35)) if look.has("accent") else _col().darkened(0.35), 0.0, 0.7)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15)
	# Stitching on the top: tuck-and-roll pleats across it, ribs along it or diamond quilting.
	match str(look.get("pattern", "")):
		"tuck":
			for i in range(2, steps - 1, 2):
				var s: Dictionary = secs[i]
				var path := []
				for k in 7:
					path.append(_on_loft(s, lerpf(0.35, PI - 0.35, k / 6.0), 1.006))
				_bend(path, 0.0035, seam, self, 4)
		"ribs":
			for a in [1.2, 1.45, 1.7, 1.95]:
				var path := []
				for s in secs.slice(1, steps):
					path.append(_on_loft(s, a, 1.006))
				_bend(path, 0.0035, seam, self, 4)
		"diamond":
			for i in range(1, steps - 2, 2):
				for k in 3:
					var a := lerpf(0.9, PI - 0.9, k / 2.0)
					_bend([_on_loft(secs[i], a - 0.25, 1.006), _on_loft(secs[i + 1], a, 1.006), _on_loft(secs[i + 2], a - 0.25, 1.006)], 0.003, seam, self, 4)
	# Piping round the edge, a shade darker (or the piping colour), and the front seam.
	var mid: Dictionary = secs[roundi(steps * 0.3)]
	_box(mid["c"] + Vector3(0.0, float(mid["up"]) * 0.2, 0.0), Vector3(float(mid["w"]) * 2.02, 0.006, 0.006), seam)
	for a in [0.12, PI - 0.12]:
		var path := []
		for sec in secs.slice(1, steps):
			path.append(_on_loft(sec, a, 1.01))
		_bend(path, 0.0038, seam, self, 5).name = "Piping"
	# A two-up seat has a grab rail round the back and pillion pegs on hangers.
	var two_up: bool = str(look.get("shape", style)) in ["bench", "touring", "stepped", "king_queen", "hump_long"] and float(look.get("sissy", 0.0)) <= 0.0
	if two_up and not p.get("solo", false):
		var rail_mat := _tex(_mat(Color(0.12, 0.12, 0.13), 0.8, 0.35), "brushed", -1.0, 0.5) if not look.has("accent") else chrome
		var back: Dictionary = secs[steps - 1]
		var front_s: Dictionary = secs[roundi(steps * 0.55)]
		var ry: float = (back["c"] as Vector3).y - float(back["down"]) * 0.3
		var loop := []
		for side in [1.0, -1.0]:
			var w0: float = float(front_s["w"]) + 0.03
			var w1: float = float(back["w"]) + 0.028
			var pts := [Vector3(w0 * side, ry - 0.01, (front_s["c"] as Vector3).z), Vector3(w1 * side, ry, (back["c"] as Vector3).z),
				Vector3(w1 * 0.55 * side, ry + 0.005, (back["c"] as Vector3).z + 0.07)]
			if side < 0.0:
				pts.reverse()
			loop.append_array(pts)
		loop.insert(3, Vector3(0.0, ry + 0.008, (back["c"] as Vector3).z + 0.085))
		_bend(loop, 0.011, rail_mat, self, 10).name = "GrabRail"
		for side in [-1.0, 1.0]:
			var at: Vector3 = loop[0 if side > 0.0 else loop.size() - 1]
			_tube(at, at + Vector3(-0.02 * side, -0.09, 0.02), 0.009, rail_mat)
		var hanger := _mat(Color(0.1, 0.1, 0.11), 0.7, 0.4)
		var grip := _tex(_mat(Color(0.05, 0.05, 0.05), 0.0, 0.85), "knurl", 50.0)
		for side in [-1.0, 1.0]:
			# Behind the swingarm pivot, whatever the rider's own pegs are doing (forward controls).
			var peg := Vector3((_peg.x + 0.02) * side, maxf(_peg.y + 0.07, _pivot.y + 0.06), maxf(_peg.z + 0.3, _pivot.z + 0.16))
			_plank(peg + Vector3(-0.02 * side, 0.0, 0.0), Vector3((_peg.x - 0.02) * side, _seat_y - 0.12, peg.z - 0.06), 0.03, 0.008, hanger)
			var pp := _tube(peg + Vector3(-0.015 * side, 0.0, 0.0), peg + Vector3(0.065 * side, 0.0, 0.0), 0.011, grip)
			pp.name = "PillionPeg"
	# A sprung solo seat sits on a pair of coil springs at the back.
	if look.get("springs", false):
		var rear: Dictionary = secs[steps]
		for side in [-1.0, 1.0]:
			var top: Vector3 = rear["c"] + Vector3(0.07 * side, -float(rear["down"]), -0.02)
			var foot := Vector3(top.x, _seat_y - 0.1, top.z + 0.03)
			for k in 6:
				var ring := _mesh_instance(_torus(0.017, 0.004), chrome, top.lerp(foot, (k + 0.5) / 6.0), self)
				ring.rotation.x = 0.0
	# A sissy bar: a chrome loop standing up behind the seat, `sissy` metres tall.
	var sissy := float(look.get("sissy", 0.0))
	if sissy > 0.0:
		var root := Vector3(0.0, _tail.y + 0.02, _tail.z - 0.02)
		for side in [-1.0, 1.0]:
			_bend([root + Vector3(0.1 * side, -0.08, -0.04), root + Vector3(0.1 * side, sissy * 0.6, 0.02), root + Vector3(0.06 * side, sissy, 0.04),
				root + Vector3(0.0, sissy + 0.02, 0.045)], 0.009, chrome)
		if look.get("backrest", false):
			var rest := _box(root + Vector3(0.0, sissy * 0.55, 0.0), Vector3(0.2, 0.16, 0.05), mat)
			rest.rotation.x = 0.15


## A seat profile's [half-width, rise, drop, lift] at `u` along it.
static func _seat_key_at(keys: Array, u: float) -> Array:
	for i in keys.size() - 1:
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if u <= float(k1[0]):
			var f := (u - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.0001)
			f = f * f * (3.0 - 2.0 * f)
			return [lerpf(k0[1], k1[1], f), lerpf(k0[2], k1[2], f), lerpf(k0[3], k1[3], f), lerpf(k0[4], k1[4], f)]
	var last: Array = keys[keys.size() - 1]
	return [last[1], last[2], last[3], last[4]]


# ---------------------------------------------------------------------------- engine

func _draw_engine() -> void:
	_current_slot = "engine"
	var col := _col()
	var mat := _mat(col, 0.8, 0.4)
	var s := _eng_s
	var e := _engine_c
	var half := _block_w * 0.5
	# The crankcase: a rounded cast case rather than a box, with a crinkle finish when it's
	# painted dark and a brushed cast-alloy look when it's bare.
	var case_mat := _tex(_mat(col, 0.8, 0.45), "crinkle" if col.get_luminance() < 0.3 else "brushed", -1.0, 0.8)
	var secs := []
	for k in [[0.0, 0.78], [0.07, 0.95], [0.25, 1.0], [0.75, 1.0], [0.93, 0.95], [1.0, 0.78]]:
		var f: float = k[0]
		var g: float = k[1]
		secs.append({"c": e + Vector3(0.0, 0.0, lerpf(-0.17, 0.17, f) * s), "w": half * g, "up": 0.13 * s * g, "down": 0.13 * s * g, "n": 3.6})
	var crank := _shell(secs, case_mat)
	crank.name = "Crankcase"
	var fins := _build.layout in ["boxer", "twin", "2stroke"]
	for c in _cyls:
		_tube(c["base"] - c["up"] * 0.1, c["base"] + c["up"] * 0.09, _bore_r, mat)
		if fins:
			# Deep cooling fins round the barrel.
			for k in 5:
				var at: Vector3 = c["base"] + c["up"] * (-0.07 + k * 0.036)
				var fin := _mesh_instance(_cylinder(_bore_r * (1.55 if _build.layout == "2stroke" else 1.45), 0.007), mat, at)
				fin.basis = _cyl_basis(c["up"])
	var chrome := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.12)
	var bolt := _mat(Color(0.62, 0.63, 0.66), 1.0, 0.3)
	# The alternator cover bulging out of the left side, held on by a ring of bolts.
	var alt_r := 0.085 * s
	var alt_at := e + Vector3(-half - 0.012, -0.015 * s, -0.06 * s)
	var alt := _mesh_instance(_cylinder(alt_r, 0.026, alt_r * 0.9), case_mat, alt_at)
	alt.rotation.z = PI * 0.5
	alt.name = "AlternatorCover"
	_bolt_ring(alt_at + Vector3(-0.014, 0.0, 0.0), Vector3.LEFT, alt_r * 0.82, 6, bolt)
	# A small points / ignition cover on the right.
	var pts_at := e + Vector3(half + 0.008, -0.03 * s, -0.12 * s)
	var pts := _mesh_instance(_cylinder(0.042 * s, 0.018), case_mat, pts_at)
	pts.rotation.z = PI * 0.5
	_bolt_ring(pts_at + Vector3(0.01, 0.0, 0.0), Vector3.RIGHT, 0.033 * s, 3, bolt)
	if _build.layout == "2stroke":
		# Expansion chamber bulge under the engine instead of a sump.
		_box(e + Vector3(0.0, -0.16 * s, 0.02), Vector3(_block_w * 0.7, 0.06, 0.24 * s), mat)
	else:
		# A finned sump under the cases.
		var sump_w := minf(_block_w * 0.55, 0.16)
		var sump_y := e.y - 0.13 * s - 0.016
		_box(Vector3(e.x, sump_y, e.z - 0.01), Vector3(sump_w, 0.032, 0.22 * s), case_mat).name = "Sump"
		for k in 4:
			var x := lerpf(-sump_w * 0.38, sump_w * 0.38, k / 3.0)
			_box(Vector3(e.x + x, sump_y - 0.02, e.z - 0.01), Vector3(0.005, 0.012, 0.2 * s), case_mat)
		_mesh_instance(_cylinder(0.011, 0.012), bolt, Vector3(e.x, sump_y - 0.022, e.z + 0.07 * s))
	match _build.layout:
		"vtwin":
			# The cam chest on the right: a chrome teardrop nose cone, and a pair of pushrod
			# tubes from it up to each head.
			var cone := _mesh_instance(_sphere(0.07 * s), chrome, e + Vector3(half + 0.006, 0.03 * s, -0.02 * s))
			cone.scale = Vector3(0.28, 0.85, 1.35)
			cone.rotation.x = 0.5
			cone.name = "NoseCone"
			var chest := e + Vector3(half * 0.55, 0.11 * s, -0.01 * s)
			for c in _cyls:
				var head: Vector3 = c["base"] + c["up"] * 0.125 + Vector3(half * 0.55, 0.0, 0.0)
				for dz in [-0.013, 0.013]:
					var tube := _tube(chest + Vector3(0.0, 0.0, dz), head + Vector3(0.0, 0.0, dz), 0.008, chrome)
					tube.name = "Pushrod"
		"inline", "triple":
			# A wide crankcase with the cam chain tunnel up the middle and a starter cover.
			_box(e + Vector3(0.0, 0.1 * s, -0.12 * s), Vector3(0.06, 0.08 * s, 0.04), case_mat)
			var starter := _mesh_instance(_cylinder(0.03, 0.12), case_mat, e + Vector3(-half * 0.4, 0.14 * s, 0.12 * s))
			starter.rotation.z = PI * 0.5


## A ring of `count` bolt heads facing `normal`, `radius` out from `at`.
func _bolt_ring(at: Vector3, normal: Vector3, radius: float, count: int, mat: Material, parent: Node3D = self) -> void:
	var b := _basis_up(normal)
	for k in count:
		var a := TAU * k / count + 0.3
		var head := _mesh_instance(_cylinder(0.0055, 0.008, -1.0, 6), mat, at + b * Vector3(cos(a) * radius, 0.0, sin(a) * radius), parent)
		head.basis = b


func _draw_head() -> void:
	_current_slot = "head"
	var col := _col()
	var mat := _mat(col, 0.85, 0.3)
	var gasket := _mat(Color(0.15, 0.15, 0.16), 0.5, 0.5)
	# Rocker and cam covers: crinkle black, or polished when they're bright.
	var cover_mat := _tex(_mat(col, 0.85, 0.3), "crinkle") if col.get_luminance() < 0.3 else _mat(col, 0.95, 0.18)
	var bolt := _mat(Color(0.62, 0.63, 0.66), 1.0, 0.3)
	var valves := int(_part().get("valves", 4))
	match _build.layout:
		"2stroke":
			# No valves, no cam cover: just a deeply finned head round the plug.
			for c in _cyls:
				var top: Vector3 = c["base"] + c["up"] * 0.12
				var h := _mesh_instance(_cylinder(_bore_r * 1.3, 0.05), mat, top)
				h.basis = _cyl_basis(c["up"])
				for k in 4:
					var fin := _mesh_instance(_cylinder(_bore_r * 1.8, 0.006), mat, top + c["up"] * (-0.018 + k * 0.013))
					fin.basis = _cyl_basis(c["up"])
			return
		"boxer":
			# The heads stick right out into the wind: big finned rocker covers on each side.
			for c in _cyls:
				var top: Vector3 = c["base"] + c["up"] * 0.13
				var b := _cyl_basis(c["up"])
				_box(top, Vector3(0.13, 0.08, 0.15), gasket).basis = b
				for k in 3:
					_box(top + c["up"] * (-0.025 + k * 0.025), Vector3(0.16, 0.006, 0.17), mat).basis = b
				var cover := _mesh_instance(_cylinder(0.07, 0.06, 0.062), cover_mat, top + c["up"] * 0.07)
				cover.basis = b * Basis.from_scale(Vector3(1.0, 1.0, 1.15))
				cover.name = "ValveCover"
				_bolt_ring(top + c["up"] * 0.101, c["up"], 0.045, 4, bolt)
			return
		"vtwin":
			for c in _cyls:
				var top: Vector3 = c["base"] + c["up"] * 0.13
				var b := _cyl_basis(c["up"])
				_box(top, Vector3(0.12, 0.08, 0.15), gasket).basis = b
				for k in 3:
					_box(top + c["up"] * (-0.025 + k * 0.022), Vector3(0.15, 0.005, 0.17), mat).basis = b
				_box(top + c["up"] * 0.06, Vector3(0.11, 0.05, 0.14), cover_mat).basis = b
				# The rocker box seam, a chrome strip round the cover.
				_box(top + c["up"] * 0.045, Vector3(0.115, 0.008, 0.145), _mat(Color(0.86, 0.87, 0.89), 1.0, 0.12)).basis = b
			return
	if _cyls.size() > 1:
		# One head and one long cam cover across the whole row of cylinders.
		var first: Vector3 = _cyls[0]["base"] + _cyls[0]["up"] * 0.13
		var last: Vector3 = _cyls[_cyls.size() - 1]["base"] + _cyls[_cyls.size() - 1]["up"] * 0.13
		var up: Vector3 = _cyls[0]["up"]
		var b := _cyl_basis(up)
		var mid := (first + last) * 0.5
		# (Across the row in the head's own size, which b scales back up to the row's width.)
		var span := absf(last.x - first.x) / up.length() + 0.12
		_box(mid, Vector3(span, 0.08, 0.15), gasket).basis = b
		var cover := _box(mid + up * 0.06, Vector3(span - 0.01, 0.05, 0.14 if valves > 2 else 0.1), cover_mat)
		cover.basis = b
		cover.name = "CamCover"
		# Bolts along both long edges, and the cam-end caps.
		for k in _cyls.size() + 1:
			var x := lerpf(-span * 0.44, span * 0.44, float(k) / _cyls.size())
			for z in [-0.06, 0.06]:
				_mesh_instance(_cylinder(0.006, 0.01, -1.0, 6), bolt, mid + up * 0.087 + b * Vector3(x, 0.0, z)).basis = b
		for side in [-1.0, 1.0]:
			var cap := _mesh_instance(_cylinder(0.03, 0.02), cover_mat, mid + up * 0.06 + b * Vector3((span * 0.5 + 0.005) * side, 0.0, 0.0))
			cap.basis = b * Basis(Vector3.BACK, PI * 0.5)
		return
	for c in _cyls:
		var top: Vector3 = c["base"] + c["up"] * 0.13
		var h := _box(top, Vector3(0.12, 0.08, 0.15), gasket)
		h.basis = _cyl_basis(c["up"])
		var cover := _box(top + c["up"] * 0.06, Vector3(0.11, 0.05, 0.14 if valves > 2 else 0.1), cover_mat)
		cover.basis = _cyl_basis(c["up"])
		cover.name = "CamCover"
		for x in [-0.045, 0.045]:
			for z in [-0.055, 0.055]:
				_mesh_instance(_cylinder(0.006, 0.01, -1.0, 6), bolt, top + c["up"] * 0.087 + h.basis * Vector3(x, 0.0, z)).basis = h.basis


func _draw_spark_plugs() -> void:
	_current_slot = "spark_plugs"
	var ceramic := _mat(_col(), 0.0, 0.3)
	var cap := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.6)
	var lead := _mat(Color(0.42, 0.05, 0.04), 0.0, 0.55)
	var ends := []
	for i in _cyls.size():
		var c: Dictionary = _cyls[i]
		var up: Vector3 = c["up"]
		var at: Vector3 = c["base"] + up * 0.2 + Vector3(0.0, 0.0, 0.02)
		_tube(at, at + up * 0.03, 0.011, ceramic)
		# Plug caps come off the head sideways, the way real ones do, so they stay clear of
		# the tank and the saddle: out to the right on upright cylinders (alternating on a
		# twin), straight out along the cylinder on a boxer.
		var out := up
		if absf(up.x) < 0.5:
			out = Vector3(-1.0 if _cyls.size() == 2 and i == 0 else 1.0, 0.0, 0.0)
		var elbow: Vector3 = at + up * 0.035
		var end: Vector3 = elbow + out * 0.05 - up * 0.01
		_bend([at + up * 0.02, elbow, end], 0.014, cap, self, 4)
		ends.append(end)
	if ends.is_empty():
		return
	# HT leads from the plug caps back to the coil tucked under the tank.
	var top := -INF
	var mid := Vector3.ZERO
	for end in ends:
		top = maxf(top, end.y)
		mid += end
	mid /= ends.size()
	# The coil sits low behind the cylinders, out of sight under the tank rather than up in it.
	var coil := Vector3(0.0, top - 0.11, mid.z + 0.16)
	var body := _bike_only(_box(coil, Vector3(0.045, 0.035, 0.075), _mat(Color(0.06, 0.06, 0.07), 0.3, 0.5)))
	body.name = "Coil"
	for i in ends.size():
		var end: Vector3 = ends[i]
		var into := coil + Vector3((i - (ends.size() - 1) * 0.5) * 0.012, 0.0, -0.035)
		var sag := end.lerp(into, 0.5) + Vector3(0.0, -0.03, 0.0)
		var wire := _bike_only(_bend([end, end + Vector3(0.0, 0.012, 0.02), sag, into], 0.0045, lead, self, 6))
		wire.name = "HTLead"


## Where the intake meets each cylinder, and where the fuel system hands over to the air filter.
func _intake_points() -> Array:
	var out := []
	if _build.layout == "vtwin":
		# A V-twin breathes out of the right-hand side of the vee, into the big round air
		# cleaner a Harley or an Indian wears there, not up into the tank.
		out.append({"port": _engine_c + Vector3(0.04, 0.3 * _eng_s, 0.0), "dir": Vector3(1.0, 0.05, 0.0).normalized()})
		return out
	for c in _cyls:
		out.append({"port": c["base"] + c["up"] * 0.12 + Vector3(0.0, 0.0, 0.09), "dir": Vector3(0.0, 0.15, 1.0).normalized()})
	return out


func _draw_fuel() -> void:
	_current_slot = "fuel"
	var p := _part()
	var mat := _mat(_col(), 0.85, 0.3)
	var style := str(p.get("style", "carbs"))
	var points := _intake_points()
	if style == "carb" and points.size() > 1:
		var mid := Vector3.ZERO
		for pt in points:
			mid += pt["port"]
			_tube(pt["port"], pt["port"] + Vector3(0.0, 0.0, 0.05), 0.02, mat)
		mid /= points.size()
		_box(mid + Vector3(0.0, 0.0, 0.08), Vector3(0.07, 0.07, 0.07), mat)
		return
	for pt in points:
		var at: Vector3 = pt["port"]
		_tube(at, at + pt["dir"] * 0.07, 0.026 if style != "fi" else 0.03, mat)
		if style == "fi":
			_box(at + pt["dir"] * 0.04 + Vector3(0.0, 0.04, 0.0), Vector3(0.02, 0.04, 0.02), _mat(Color(0.05, 0.05, 0.05), 0.2, 0.5))
		else:
			_box(at + pt["dir"] * 0.05 + Vector3(0.0, -0.01, 0.0), Vector3(0.055, 0.07, 0.06), mat)


## How far out to the right (m) the air filter reaches at least, so its element shows past the
## frame and the tank's edge and you can get at it with the engine in the frame.
const AIR_FILTER_OUT := 0.21


func _draw_air_filter() -> void:
	_current_slot = "air_filter"
	var mat := _mat(_col(), 0.0, 0.8)
	var points := _intake_points()
	# Rubber intake boots and hoses from the carbs out to where the filter sits.
	var boot := _mat(Color(0.06, 0.06, 0.06), 0.0, 0.75)
	match str(_part().get("style", "airbox")):
		"pods", "stacks":
			# One per carb, splayed out sideways from under the tank so the outer ones stand
			# clear of it, on a short boot where they'd otherwise be buried.
			var stacks: bool = _part().get("style") == "stacks"
			var chrome := _mat(_col(), 1.0, 0.15)
			for pt in points:
				var port: Vector3 = pt["port"]
				var side := -1.0 if port.x < -0.01 else 1.0
				var dir := (pt["dir"] as Vector3 + Vector3(side * 0.9, 0.0, 0.0)).normalized()
				var half_len := 0.025 if stacks else 0.045
				var reach := maxf(0.11 if stacks else 0.13, (AIR_FILTER_OUT - absf(port.x)) / absf(dir.x) - half_len)
				var at := port + dir * reach
				if reach > 0.14:
					_tube(port + dir * 0.06, at - dir * half_len, 0.024, boot)
				var piece := _mesh_instance(_cylinder(0.026, 0.05, 0.042), chrome, at) if stacks else _mesh_instance(_cylinder(0.04, 0.09), mat, at)
				piece.basis = _basis_up(dir)
				piece.name = "VelocityStack" if stacks else "PodFilter"
		"cone":
			# A cone filter on an elbow out of the right-hand side, its open end clear of the tank.
			var mid := Vector3.ZERO
			for pt in points:
				mid += pt["port"]
			mid /= points.size()
			var dir := Vector3(0.75, 0.05, 0.66).normalized()
			var at := Vector3(maxf(AIR_FILTER_OUT, mid.x + 0.12) - dir.x * 0.07, mid.y + 0.02, mid.z + 0.16)
			at.y = minf(at.y, tank_base_y(at.z) - 0.07)
			_bend([mid + Vector3(0.0, 0.0, 0.07), mid + Vector3(0.0, 0.01, 0.13), at - dir * 0.07], 0.035, boot)
			var cone := _mesh_instance(_cylinder(0.065, 0.14, 0.04), mat, at)
			cone.basis = _basis_up(dir)
			cone.name = "ConeFilter"
		_:
			if _build.layout == "vtwin" and not points.is_empty():
				var pt: Dictionary = points[0]
				var port: Vector3 = pt["port"]
				var dir: Vector3 = pt["dir"]
				# Up under the tank: out past the frame's beams and the tank's edge, on a short boot
				# if it has to be.
				var edge := maxf(AIR_FILTER_OUT, slot_bounds("tank").end.x if not _slot_meshes["tank"].is_empty() else 0.0)
				var reach := maxf(0.1, (edge - port.x) / dir.x)
				if reach > 0.11:
					_tube(port + dir * 0.06, port + dir * (reach - 0.02), 0.03, boot)
				var cleaner := _mesh_instance(_cylinder(0.07, 0.045), _mat(_col().darkened(0.2), 0.75, 0.3), port + dir * reach)
				cleaner.basis = _basis_up(dir)
				cleaner.name = "AirCleaner"
				var rim := _mesh_instance(_cylinder(0.095, 0.012), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15), port + dir * (reach + 0.028))
				rim.basis = _basis_up(dir)
				return
			var mid := Vector3.ZERO
			for pt in points:
				mid += pt["port"]
			mid /= points.size()
			# The airbox lives under the tank, never up through it.
			var at := mid + Vector3(0.0, 0.04, 0.16)
			at.y = minf(at.y, tank_base_y(at.z) - 0.08)
			var wide := maxf(0.2, _block_w * 0.8)
			var box := _box(at, Vector3(wide, 0.15, 0.14), mat)
			box.name = "Airbox"
			# The element's housing on the right-hand end, with its lid out past the frame and
			# the tank's edge, where the filter comes out.
			var out := maxf(AIR_FILTER_OUT, wide * 0.5 + 0.05)
			var housing := _mesh_instance(_cylinder(0.06, out - wide * 0.5 + 0.01), mat, Vector3((wide * 0.5 + out) * 0.5, at.y, at.z))
			housing.rotation.z = PI * 0.5
			housing.name = "FilterHousing"
			var lid := _mesh_instance(_cylinder(0.066, 0.012), _mat(_col().lightened(0.15), 0.3, 0.5), Vector3(out, at.y, at.z))
			lid.rotation.z = PI * 0.5
			lid.name = "FilterLid"


## Where the spin-on oil filter sits: low on the right at the front of the crankcase, under the
## ignition cover and ahead of the clutch cover and the footrests, standing out sideways so you
## can see it and get a hand to it with the engine in the frame, standing or crouched. Returns
## its middle; it points along oil_filter_dir().
func oil_filter_at() -> Vector3:
	if _build.layout == "boxer":
		# Under a boxer's barrels there's no room: it stands out of the front of the cases.
		return _engine_c + Vector3(0.05 * _eng_s, -0.08 * _eng_s, -0.17 * _eng_s - 0.03)
	return _engine_c + Vector3(_block_w * 0.5 + OIL_FILTER_LEN * 0.5 - 0.003, -0.1 * _eng_s - 0.015, -0.11 * _eng_s - 0.005)


## Which way the oil filter points out of the cases (see oil_filter_at).
func oil_filter_dir() -> Vector3:
	return Vector3.FORWARD if _build.layout == "boxer" else Vector3.RIGHT

const OIL_FILTER_LEN := 0.07


func _draw_oil_filter() -> void:
	_current_slot = "oil_filter"
	var mat := _mat(_col(), 0.5, 0.4)
	var at := oil_filter_at()
	var dir := oil_filter_dir()
	var f := _mesh_instance(_cylinder(0.035, OIL_FILTER_LEN), mat, at)
	f.basis = _basis_up(dir)
	f.name = "OilFilter"
	# The flat end with its spanner flats, facing out.
	var cap := _mesh_instance(_cylinder(0.016, 0.008, -1.0, 6), _mat(_col().darkened(0.3), 0.6, 0.35), at + dir * (OIL_FILTER_LEN * 0.5 + 0.003))
	cap.basis = _basis_up(dir)


func _draw_cooling() -> void:
	_current_slot = "cooling"
	var mat := _mat(_col(), 0.7, 0.45)
	var core := _mat(Color(0.08, 0.08, 0.08), 0.6, 0.6)
	var front_z := _engine_c.z - 0.3
	match str(_part().get("style", "fins")):
		"fins":
			for c in _cyls:
				for i in 5:
					var fin := _box(c["base"] + c["up"] * (-0.07 + i * 0.035), Vector3(0.14, 0.01, 0.15), mat)
					fin.basis = _cyl_basis(c["up"])
		"oil":
			_box(Vector3(0.0, _engine_c.y + 0.2, front_z + 0.04), Vector3(0.24, 0.1, 0.035), core)
			_box(Vector3(0.0, _engine_c.y + 0.2, front_z + 0.02), Vector3(0.26, 0.12, 0.01), mat)
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.1 * side, _engine_c.y + 0.15, front_z + 0.04), _engine_c + Vector3(0.08 * side, -0.05, -0.17), 0.007, mat)
		"radiator", "race":
			var big: bool = _part().get("style") == "race"
			var w := 0.42 if big else 0.3
			var h := 0.34 if big else 0.28
			var c := Vector3(0.0, _engine_c.y + 0.25, front_z)
			var rb := Basis(Vector3.RIGHT, -0.25)
			# The core: fine fins and tubes.
			var rad := _box(c, Vector3(w, h, 0.05), _tex(core, "core", 14.0))
			rad.basis = rb
			rad.name = "RadiatorCore"
			# The side tanks and the top and bottom of the surround.
			for sx in [-1.0, 1.0]:
				_box(c + rb * Vector3((w * 0.5 + 0.012) * sx, 0.0, 0.0), Vector3(0.024, h + 0.02, 0.055), mat).basis = rb
			for sy in [-1.0, 1.0]:
				_box(c + rb * Vector3(0.0, (h * 0.5 + 0.01) * sy, 0.0), Vector3(w + 0.03, 0.02, 0.05), mat).basis = rb
			# A grille in front: slim slats across the core.
			var grille := _mat(Color(0.12, 0.12, 0.13), 0.7, 0.4)
			for k in 7:
				var slat := _box(c + rb * Vector3(0.0, lerpf(-h * 0.42, h * 0.42, k / 6.0), -0.032), Vector3(w - 0.01, 0.006, 0.012), grille)
				slat.basis = rb
				slat.name = "RadiatorGrille"
			# The fan behind, and the shrouds that steer air through the core.
			var fan := _mesh_instance(_cylinder(minf(w, h) * 0.38, 0.03), _mat(Color(0.06, 0.06, 0.06), 0.3, 0.5), c + rb * Vector3(0.0, 0.0, 0.045))
			fan.basis = rb * Basis(Vector3.RIGHT, PI * 0.5)
			for sx in [-1.0, 1.0]:
				var shroud := _box(c + rb * Vector3((w * 0.5 + 0.035) * sx, 0.0, -0.02), Vector3(0.008, h * 0.95, 0.12), mat)
				shroud.basis = rb * Basis(Vector3.UP, -0.45 * sx)
				shroud.name = "RadiatorShroud"
			# Coolant hoses: the top one to the thermostat on the head, the bottom one to the pump.
			var hose := _mat(Color(0.05, 0.05, 0.055), 0.0, 0.7)
			var top := c + rb * Vector3(w * 0.32, h * 0.5 + 0.005, 0.03)
			var head := _engine_c + Vector3(0.0, 0.3 * _eng_s, -0.04)
			if not _cyls.is_empty():
				var mid := Vector3.ZERO
				for cy in _cyls:
					mid += cy["base"] + cy["up"] * 0.13
				head = mid / _cyls.size() + Vector3(0.0, 0.02, -0.085)
			_bike_only(_box(head, Vector3(0.04, 0.03, 0.03), mat)).name = "Thermostat"
			_bike_only(_bend([top, top + Vector3(0.0, 0.03, 0.04), head.lerp(top, 0.4) + Vector3(0.0, 0.03, 0.0), head], 0.014, hose, self, 10)).name = "CoolantHose"
			var bottom := c + rb * Vector3(-w * 0.32, -h * 0.5 - 0.005, 0.03)
			var pump := _engine_c + Vector3(-_block_w * 0.3, -0.05, -0.17)
			_bike_only(_bend([bottom, bottom + Vector3(0.0, -0.04, 0.03), pump + Vector3(0.0, 0.02, -0.04), pump], 0.015, hose, self, 10)).name = "CoolantHose"
			_bike_only(_mesh_instance(_cylinder(0.025, 0.03), mat, pump)).rotation.x = PI * 0.5
		"twin":
			for side in [-1.0, 1.0]:
				var rad := _box(Vector3(0.16 * side, _engine_c.y + 0.24, front_z + 0.08), Vector3(0.05, 0.28, 0.22), core)
				rad.rotation.y = 0.35 * side
				_box(Vector3(0.19 * side, _engine_c.y + 0.24, front_z + 0.08), Vector3(0.01, 0.3, 0.24), mat).rotation.y = 0.35 * side


func _draw_gearbox() -> void:
	_current_slot = "gearbox"
	var case_mat := _mat(_col(), 0.75, 0.45)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	_box(_engine_c + Vector3(0.0, -0.06, 0.22), Vector3(_block_w * 0.8, 0.18, 0.16), case_mat)
	var clutch := _mesh_instance(_cylinder(0.1, 0.04), case_mat, _engine_c + Vector3(_block_w * 0.5 + 0.02, -0.02, 0.1))
	clutch.rotation.z = PI * 0.5
	_tube(_engine_c + Vector3(-_block_w * 0.5 - 0.06, -0.09, 0.2), _engine_c + Vector3(-_block_w * 0.5 - 0.14, -0.13, 0.12), 0.008, chrome)
	# The clutch cover's bolt ring and the oil filler cap.
	_bolt_ring(clutch.position + Vector3(0.021, 0.0, 0.0), Vector3.RIGHT, 0.085, 8, _mat(Color(0.6, 0.61, 0.64), 1.0, 0.3))
	_mesh_instance(_cylinder(0.016, 0.018, -1.0, 8), _mat(Color(0.05, 0.05, 0.05), 0.2, 0.5), clutch.position + Vector3(0.0, 0.095, 0.03))
	if _build.layout in ["single", "2stroke", "twin"]:
		# A kickstart lever folded up behind the right footpeg.
		var shaft := _engine_c + Vector3(_block_w * 0.5 + 0.035, -0.04, 0.2)
		_mesh_instance(_cylinder(0.012, 0.03), chrome, shaft).rotation.z = PI * 0.5
		var pedal := shaft + Vector3(0.02, 0.1, 0.13)
		var arm := _tube(shaft + Vector3(0.015, 0.0, 0.0), pedal, 0.009, chrome)
		arm.name = "Kickstart"
		var foot := _mesh_instance(_cylinder(0.011, 0.05), _tex(_mat(Color(0.05, 0.05, 0.05), 0.0, 0.85), "knurl", 50.0), pedal + Vector3(0.025, 0.0, 0.0))
		foot.rotation.z = PI * 0.5


## The exhaust: a header from each cylinder bent round the frame along a route, then the can.
## The route is the part's own ("route") or the frame's ("exhaust" in its geo): low under the
## engine, high up the side (scrambler), upswept under the side panel (MX), up under the seat,
## a stubby can under the pivot, shotgun pipes (one per cylinder, long and low), or expansion
## chambers on a two-stroke. The can is the part's "can": round, oval, megaphone, hex, short,
## peashooter, slash-cut or none at all (an open pipe).
func _draw_exhaust(zr: float) -> void:
	_current_slot = "exhaust"
	var p := _part()
	var pipe_mat := _mat(_col(), 1.0, 0.15)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var style := str(p.get("style", "stock"))
	var lk := _look()
	var can := str(lk.get("can", p.get("can", "round")))
	var route := str(p.get("route", _frame_geo.get("exhaust", "low")))
	if _build.layout == "2stroke" and route == "low":
		route = "chamber"
	# A slip-on is a chrome link pipe into a coloured can; the rest are one colour.
	var header_mat := chrome if style == "slip" else pipe_mat
	var can_mat := _mat(_col(), 0.3, 0.3, 0.7) if style == "slip" else pipe_mat
	# A look can change the headers' finish (chrome, black, titanium, heat wrap...) and the can's.
	header_mat = _look_finish(str(lk.get("header", "")), header_mat)
	can_mat = _look_finish(str(lk.get("can_finish", "")), can_mat)
	var ports := []
	for i in _cyls.size():
		var c: Dictionary = _cyls[i]
		var port: Vector3 = c["base"] + c["up"] * 0.11 + Vector3(0.0, 0.0, -0.08)
		if _build.layout == "vtwin" and i == 1:
			port = c["base"] + c["up"] * 0.1 + Vector3(0.07, 0.0, 0.0)
		ports.append(port)
		# The header flange bolted to the port.
		var flange := _mesh_instance(_cylinder(0.03, 0.01), _mat(Color(0.55, 0.56, 0.58), 1.0, 0.3), port)
		flange.basis = _basis_up(Vector3(0.0, -0.05, -0.05).normalized() if not (_build.layout == "vtwin" and i == 1) else Vector3.RIGHT)
	var e := _engine_c
	var s := _eng_s
	var under := e.y - 0.19 * s
	var front_z := e.z - 0.16 * s - 0.05
	var r := 0.02 if _cyls.size() > 2 else 0.022
	var tip := Vector3.ZERO
	match route:
		"shotgun":
			# One long pipe per cylinder down the right, staggered one above the other.
			for i in ports.size():
				var dy := -0.075 * i
				var port: Vector3 = ports[i]
				var end := Vector3(0.17, _pivot.y - 0.02 + dy * 0.7, zr + 0.2)
				_bend([port, port + Vector3(0.05, -0.03, -0.03), Vector3(0.15, e.y - 0.06 + dy * 0.6, e.z + 0.04),
					Vector3(0.17, _pivot.y - 0.06 + dy * 0.8, _pivot.z + 0.05), Vector3(0.17, _pivot.y - 0.05 + dy * 0.75, _pivot.z + 0.3)], 0.026, header_mat)
				var t := _can(Vector3(0.17, _pivot.y - 0.05 + dy * 0.75, _pivot.z + 0.3), end, can, can_mat, 0.04)
				if i == 0:
					tip = t
		"high":
			var join := Vector3(0.17, e.y + 0.08, e.z + 0.14)
			for port in ports:
				_bend([port, port + Vector3(0.0, -0.03, -0.06), Vector3(0.12, e.y - 0.02, e.z - 0.14 * s), Vector3(0.16, e.y + 0.02, e.z + 0.0), join], r, header_mat)
			var can_a := Vector3(0.18, _seat_y - 0.2, _pivot.z + 0.02)
			_bend([join, join.lerp(can_a, 0.5) + Vector3(0.005, 0.0, 0.0), can_a], 0.026, header_mat)
			tip = _can(can_a, Vector3(0.18, _seat_y - 0.12, _tail.z - 0.02), can, can_mat, 0.045)
			# A heat shield over the pipe where the rider's leg goes.
			var shield := _mat(Color(0.12, 0.12, 0.13), 0.8, 0.4)
			_shell([{"c": join + Vector3(0.0, -0.01, 0.06), "w": 0.034, "up": 0.034, "n": 2.0},
				{"c": join.lerp(can_a, 0.6) + Vector3(0.0, 0.0, 0.0), "w": 0.034, "up": 0.034, "n": 2.0}], shield, true, -1.1, 1.1)
		"upswept":
			var join := Vector3(0.13, e.y - 0.04, e.z + 0.12)
			for port in ports:
				_bend([port, port + Vector3(0.0, -0.06, -0.05), Vector3(0.09, e.y - 0.12, front_z + 0.02), join], r, header_mat)
			var can_a := Vector3(0.15, e.y + 0.14, _pivot.z + 0.02)
			_bend([join, Vector3(0.145, e.y + 0.04, _pivot.z - 0.08), can_a], 0.025, header_mat)
			tip = _can(can_a, Vector3(0.15, _seat_y - 0.04, zr + 0.0), can, can_mat, 0.045)
		"underseat":
			var gather := Vector3(0.0, under + 0.01, e.z + 0.04)
			for port in ports:
				_bend([port, port + Vector3(0.0, -0.06, -0.04), Vector3(port.x * 0.5, under + 0.02, front_z + 0.06), gather], r, header_mat)
			var up := Vector3(0.0, _seat_y - 0.24, _pivot.z + 0.1)
			_bend([gather, Vector3(0.0, under + 0.03, _pivot.z - 0.1), Vector3(0.0, _pivot.y + 0.06, _pivot.z - 0.02), up], 0.03, header_mat)
			for x in [-0.05, 0.05]:
				var t := _can(up + Vector3(x, 0.08, 0.04), Vector3(x, _seat_y - 0.1, _tail.z + 0.06), can, can_mat, 0.035)
				if x > 0.0:
					tip = t
			_bend([up, up + Vector3(0.0, 0.06, 0.02), up + Vector3(0.05, 0.08, 0.04)], 0.025, header_mat)
			_bend([up + Vector3(0.0, 0.06, 0.02), up + Vector3(-0.05, 0.08, 0.04)], 0.025, header_mat)
		"chamber":
			# Two-stroke expansion chambers: fat tuned pipes under the engine, a small silencer.
			for i in ports.size():
				var port: Vector3 = ports[i]
				var x := port.x * 0.6 + 0.02
				var end := Vector3(0.12 + 0.03 * i, _pivot.y - 0.05, _pivot.z + 0.06)
				_bend([port, port + Vector3(0.0, -0.06, -0.06), Vector3(x, under - 0.02, front_z + 0.06), Vector3(x + 0.02, under - 0.01, e.z + 0.12), end],
					[0.022, 0.03, 0.055, 0.06, 0.024], header_mat)
				var t := _can(end, Vector3(0.14 + 0.03 * i, 0.16 + 0.04 * i, zr - 0.12), can, can_mat, 0.04)
				if i == 0:
					tip = t
		_:
			# Low: down in front of the engine, under it, and back past the pivot to the can. A
			# classic twin with stock pipes has a pipe and a can each side.
			var both := bool(lk.get("pair", style == "stock" and _cyls.size() == 2 and _build.layout in ["twin", "parallel", "boxer"]))
			var stubby := route == "stubby"
			for side in ([-1.0, 1.0] if both else [1.0]):
				var sx: float = side
				var collector := Vector3(0.15 * sx, _pivot.y - 0.2, _pivot.z + 0.05)
				if stubby:
					collector = Vector3(0.11, under + 0.02, _pivot.z - 0.14)
				for port in ports:
					if both and signf(port.x) != sx and absf(port.x) > 0.01:
						continue
					_bend([port, port + Vector3(0.0, -0.05, -0.05), Vector3(0.06 * sx + port.x * 0.4, under + 0.02, front_z),
						Vector3(0.11 * sx, under, e.z + 0.06), collector], r, header_mat)
				var can_a := collector + Vector3(0.0, 0.03, 0.12)
				var can_b := Vector3(0.16 * sx, 0.2, zr - 0.08)
				if stubby:
					can_a = collector + Vector3(0.02, 0.02, 0.06)
					can_b = Vector3(0.15, _pivot.y - 0.06, _pivot.z + 0.2)
				_bend([collector, collector.lerp(can_a, 0.5), can_a], 0.026, header_mat)
				var t := _can(can_a, can_b, can, can_mat, 0.06 if style == "stock" else 0.05)
				if sx > 0.0:
					tip = t
	_exhaust_tip = tip


## A silencer from `a` to `b` in the part's can shape, `r` its biggest radius; returns where
## the gas comes out.
func _can(a: Vector3, b: Vector3, shape: String, mat: Material, r: float) -> Vector3:
	var dir := (b - a).normalized()
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.4, 0.5)
	match shape:
		"open":
			_bend([a, b], 0.028, mat)
			return b + dir * 0.01
		"fishtail":
			# A long can ending in a flattened, flared fishtail.
			var bb := a.lerp(b, 0.78)
			_bend([a, a.lerp(b, 0.1), bb], [r * 0.5, r * 0.85, r * 0.85], mat, self, 14)
			var tail := _shell([{"c": bb, "w": r * 0.8, "up": r * 0.8, "n": 2.0}, {"c": b, "w": r * 1.5, "up": r * 0.35, "n": 3.0}], mat)
			tail.name = "Fishtail"
			return b + dir * 0.01
		"turnout":
			# A slim can whose end pipe turns out to the side.
			var bb := a.lerp(b, 0.85)
			_bend([a, a.lerp(b, 0.12), bb], [r * 0.55, r * 0.9, r * 0.85], mat, self, 14)
			var out := bb + Vector3(signf(bb.x + 0.0001) * 0.05, -0.01, 0.04)
			_bend([bb, bb + dir * 0.03, out], 0.016, mat)
			return out
		"baloney":
			# A long slim cigar with rounded ends.
			_bend([a, a.lerp(b, 0.06), a.lerp(b, 0.5), b.lerp(a, 0.06), b], [r * 0.4, r * 0.7, r * 0.75, r * 0.7, r * 0.35], mat, self, 16)
			return b + dir * 0.01
		"trumpet":
			# A straight pipe that flares into a bell at the end.
			_bend([a, a.lerp(b, 0.6), a.lerp(b, 0.85), b], [r * 0.45, r * 0.45, r * 0.6, r * 1.15], mat, self, 16)
			_tip(b, dir, r * 0.7, dark)
			return b + dir * 0.01
		"reverse":
			# A reverse cone: fat at the back with a dished cap.
			_bend([a, a.lerp(b, 0.15), b], [r * 0.5, r * 0.8, r * 1.1], mat, self, 16)
			var cap := _mesh_instance(_cylinder(r * 1.1, 0.03, r * 0.6), _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1), b + dir * 0.015)
			cap.basis = _basis_up(dir)
			_tip(b + dir * 0.03, dir, r * 0.35, dark)
			return b + dir * 0.04
		"tri":
			_bend([a, a.lerp(b, 0.12), a.lerp(b, 0.88), b], [r * 0.55, r * 1.05, r * 1.05, r * 0.9], mat, self, 3)
			_tip(b, dir, r * 0.45, dark)
			return b + dir * 0.01
		"stubby":
			var bb := a.lerp(b, 0.4)
			_bend([a, a.lerp(bb, 0.2), bb], [r * 0.7, r * 1.15, r * 1.1], mat, self, 16)
			_tip(bb, dir, r * 0.55, dark)
			return bb + dir * 0.01
		"slash":
			_bend([a, b], 0.032, mat)
			var lip := _mesh_instance(_cylinder(0.032, 0.012, 0.038), mat, b)
			lip.basis = _basis_up(dir)
			return b + dir * 0.01
		"megaphone":
			_bend([a, a.lerp(b, 0.3), a.lerp(b, 0.75), b, b + dir * 0.02], [r * 0.5, r * 0.65, r * 0.95, r * 1.1, r * 1.0], mat, self, 16)
			var cone := _mesh_instance(_cylinder(r * 0.98, 0.05, r * 0.5), mat, b + dir * 0.03)
			cone.basis = _basis_up(dir)
			_tip(b + dir * 0.055, dir, r * 0.35, dark)
			return b + dir * 0.06
		"hex":
			_bend([a, a.lerp(b, 0.12), a.lerp(b, 0.85), b], [r * 0.55, r * 0.95, r, r * 0.9], mat, self, 6)
			_tip(b, dir, r * 0.6, dark)
			_can_details(a.lerp(b, 0.12), b, dir, r * 0.95, r * 0.9)
			return b + dir * 0.01
		"short":
			var bb := a.lerp(b, 0.6)
			_bend([a, a.lerp(bb, 0.15), bb], [r * 0.6, r, r * 0.95], mat, self, 14)
			_tip(bb, dir, r * 0.5, dark)
			return bb + dir * 0.01
		"peashooter":
			_bend([a, a.lerp(b, 0.15), a.lerp(b, 0.9), b], [r * 0.6, r * 0.8, r * 0.8, r * 0.7], mat, self, 14)
			_tip(b, dir, r * 0.4, dark)
			return b + dir * 0.01
		"oval":
			_bend([a, a.lerp(b, 0.12), a.lerp(b, 0.88), b], [r * 0.55, r, r, r * 0.8], mat, self, 14)
			_tip(b, dir, r * 0.5, dark)
			_can_details(a.lerp(b, 0.12), b, dir, r, r * 0.8)
			return b + dir * 0.01
		_:
			_bend([a, a.lerp(b, 0.1), a.lerp(b, 0.9), b], [r * 0.55, r, r, r * 0.85], mat, self, 16)
			_tip(b, dir, r * 0.45, dark)
			_can_details(a.lerp(b, 0.1), b, dir, r, r * 0.85)
			return b + dir * 0.01


## A silencer's fittings: the clamp band where it slips on, and the riveted end cap.
func _can_details(inlet: Vector3, end: Vector3, dir: Vector3, r_in: float, r_end: float) -> void:
	var steel := _mat(Color(0.8, 0.81, 0.83), 1.0, 0.2)
	var band := _mesh_instance(_torus(r_in * 0.62, 0.006), steel, inlet)
	band.basis = _basis_up(dir)
	band.name = "CanClamp"
	var cap := _mesh_instance(_torus(r_end * 0.98, 0.0055), steel, end - dir * 0.004)
	cap.basis = _basis_up(dir)
	cap.name = "EndCap"
	_bolt_ring(end - dir * 0.006, dir, r_end * 0.7, 6, steel)


## The dark tailpipe end in the middle of a can's end cap.
func _tip(at: Vector3, dir: Vector3, radius: float, mat: Material) -> void:
	var t := _mesh_instance(_cylinder(radius, 0.02), mat, at)
	t.basis = _basis_up(dir)


# ---------------------------------------------------------------------------- front end

func _draw_fork(build: BikeBuild) -> void:
	_current_slot = "fork"
	var style := str(_part().get("style", "conventional"))
	var lk := _look()
	var main_mat := _mat(_col(), 0.9, 0.2)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.3, 0.5)
	var gold := _mat(Color(0.8, 0.65, 0.2), 1.0, 0.15)
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var fl := build.fork_length
	match style:
		"girder":
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.09 * side, 0.02, -0.03), Vector3(0.09 * side, 0.0, -0.03) - _steer_axis * fl, 0.02, main_mat, Vector3(1.0, 1.0, 2.2), _steer_node)
				_box(Vector3(0.09 * side, 0.0, 0.0) - _steer_axis * (fl * 0.5), Vector3(0.025, 0.04, 0.12), main_mat, _steer_node)
			var spring := _tube(Vector3(0.0, 0.0, -0.06), Vector3(0.0, 0.0, -0.06) - _steer_axis * 0.18, 0.025, chrome, Vector3.ONE, _steer_node)
			spring.name = "Spring"
		"springer":
			# Rear legs fixed to the yokes, front legs on a rocker at the axle, and the springs
			# out in the open between them at the top.
			for side in [-1.0, 1.0]:
				var x: float = 0.085 * side
				_tube(Vector3(x, 0.02, 0.02), Vector3(x, 0.0, 0.02) - _steer_axis * (fl * 0.97), 0.013, main_mat, Vector3.ONE, _steer_node)
				_tube(Vector3(x, 0.0, -0.06) - _steer_axis * 0.22, Vector3(x, 0.0, -0.06) - _steer_axis * (fl * 0.92), 0.012, main_mat, Vector3.ONE, _steer_node)
				# The rocker carrying the axle.
				_box(Vector3(x, 0.0, -0.02), Vector3(0.016, 0.03, 0.1), main_mat, _front_hub)
				for k in 7:
					var ring := _mesh_instance(_torus(0.018, 0.005), chrome, Vector3(x, 0.0, -0.06) - _steer_axis * (0.04 + k * 0.026), _steer_node)
					ring.basis = _basis_up(_steer_axis)
			var spring := _tube(Vector3(0.0, 0.0, -0.06) - _steer_axis * 0.02, Vector3(0.0, 0.0, -0.06) - _steer_axis * 0.22, 0.006, chrome, Vector3.ONE, _steer_node)
			spring.name = "Spring"
		"leading_link":
			# Fixed legs down past the wheel to a pivot behind the axle, a short link forward
			# to the axle (or, on an Earles fork, a long swinging arm from a pivot behind the
			# tyre) and a spring and damper unit each side.
			var earles := bool(lk.get("earles", false))
			var pivot_off := Vector3(0.0, 0.07, 0.3) if earles else Vector3(0.0, 0.035, 0.1)
			var at_rest := -_steer_axis * fl
			for side in [-1.0, 1.0]:
				var x: float = 0.085 * side
				var pivot := at_rest + pivot_off + Vector3(x, 0.0, 0.0)
				var knee := Vector3(x, 0.0, 0.0) - _steer_axis * (fl * 0.55) + Vector3(0.0, 0.0, 0.1 if earles else 0.03)
				_bend([Vector3(x, 0.02, 0.0), knee, pivot], 0.017, main_mat, _steer_node, 10).name = "Leg"
				_mesh_instance(_cylinder(0.02, 0.03), main_mat, pivot, _steer_node).rotation.z = PI * 0.5
				var link := _tube(Vector3(x, 0.0, 0.0), Vector3(x, 0.0, 0.0) + pivot_off, 0.016, main_mat, Vector3(1.0, 1.0, 1.6), _front_hub)
				link.name = "Link"
				var top := knee.lerp(pivot, 0.2) + Vector3(0.0, 0.0, -0.06)
				_tube(top, at_rest + pivot_off * 0.45 + Vector3(x, 0.03, -0.01), 0.02, chrome, Vector3.ONE, _steer_node).name = "Damper"
				for k in 6:
					var ring := _mesh_instance(_torus(0.026, 0.005), chrome, top.lerp(at_rest + pivot_off * 0.45 + Vector3(x, 0.03, -0.01), 0.15 + k * 0.12), _steer_node)
					ring.basis = _basis_up((top - at_rest).normalized())
			var spring := _box(at_rest + pivot_off + Vector3(0.0, 0.0, 0.0), Vector3(0.17, 0.025, 0.03), main_mat, _steer_node)
			spring.name = "Spring"
		_:
			# A look can spread the legs ("wide", a wide glide), fatten them ("leg"), change the
			# sliders' finish ("lowers"), add rubber gaiters, chrome shrouds over the stanchions
			# or a fork brace.
			var lx := 0.09 * float(lk.get("wide", 1.0))
			var lr := float(lk.get("leg", 1.0))
			var usd := style == "usd"
			var lowers := _look_finish(str(lk.get("lowers", "")), gold if usd else black)
			for side in [-1.0, 1.0]:
				var x: float = lx * side
				_tube(Vector3(x, 0.02, 0.0), Vector3(x, 0.0, 0.0) - _steer_axis * (fl * 0.55), (0.034 if usd else 0.024) * lr, main_mat, Vector3.ONE, _steer_node)
				_tube(Vector3(x, 0.0, 0.0), Vector3(x, 0.0, 0.0) + _steer_axis * (fl * 0.5), (0.022 if usd else 0.032) * lr, lowers, Vector3.ONE, _front_hub)
				if lk.get("gaiters", false):
					var rub := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.9)
					for k in 6:
						var ring := _mesh_instance(_torus(0.03 * lr, 0.009), rub, Vector3(x, 0.0, 0.0) + _steer_axis * (fl * 0.5 + 0.02 + k * 0.022), _front_hub)
						ring.basis = _basis_up(_steer_axis)
				if lk.get("shrouds", false):
					var cover := _look_finish(str(lk.get("shroud_finish", "chrome")), chrome)
					_tube(Vector3(x, 0.0, 0.0), Vector3(x, 0.0, 0.0) - _steer_axis * 0.2, 0.038 * lr, cover, Vector3.ONE, _steer_node)
			if lk.get("brace", false):
				_box(Vector3(0.0, 0.0, 0.0) + _steer_axis * (fl * 0.25), Vector3(lx * 2.0, 0.03, 0.05), main_mat, _front_hub)
			# Axle clamps at the foot of each slider, pinched by two bolts, and the axle nuts.
			var bolt := _mat(Color(0.6, 0.61, 0.64), 1.0, 0.3)
			for side in [-1.0, 1.0]:
				var x: float = lx * side
				var foot := _box(Vector3(x, 0.0, 0.0), Vector3(0.05 * lr, 0.06, 0.075), lowers, _front_hub)
				foot.basis = _basis_up(_steer_axis)
				foot.name = "AxleClamp"
				for k in [-0.014, 0.014]:
					_mesh_instance(_cylinder(0.006, 0.014, -1.0, 6), bolt, Vector3(x, 0.0, 0.0) + _steer_axis * k + Vector3(0.0, 0.0, 0.042), _front_hub).rotation.x = PI * 0.5
				var nut := _mesh_instance(_cylinder(0.014, 0.012, -1.0, 6), bolt, Vector3(x + side * (0.025 * lr + 0.006), 0.0, 0.0), _front_hub)
				nut.rotation.z = PI * 0.5
			# Headlamp ears: the lamp brackets of a classic fork, down from the top yoke.
			if not usd and lk.get("ears", lk.get("shrouds", lk.get("gaiters", false))):
				for side in [-1.0, 1.0]:
					var ear := _bend([Vector3(lx * side, -0.03, -0.01) - _steer_axis * 0.04, Vector3((lx + 0.01) * side, -0.07, -0.06), Vector3(0.1 * side, -0.08, -0.115)],
						0.011, _look_finish(str(lk.get("shroud_finish", "chrome")), chrome), _steer_node, 10)
					ear.name = "HeadlampEar"
	var clamp_mat := _mat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
	_box(Vector3.ZERO, Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	_box(-_steer_axis * 0.16, Vector3(0.24, 0.04, 0.08), clamp_mat, _steer_node)
	# The front mudguard is a part of its own now: see _draw_front_mudguard.


func _draw_handlebars() -> void:
	_current_slot = "handlebars"
	_bars_tm = null
	var p := _part()
	var mat := _skin(_mat(_col(), 0.6, 0.35))
	var rubber := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.92)
	var hw := float(p.get("width", 720)) / 2000.0
	var rise := float(p.get("rise", 0.08))
	var ends := []
	var lk := _look()
	match "Look" if lk.has("bend") else str(p.get("style", "Flat")):
		"Look":
			ends = _bent_bar(lk, hw, rise, mat)
		"Clip-ons":
			for side in [-1.0, 1.0]:
				var a := Vector3(0.09 * side, -0.07, 0.0)
				var b := Vector3(hw * side, rise, 0.13)
				_tube(a, b, 0.013, mat, Vector3.ONE, _steer_node)
				ends.append(b)
			_bar_line = PackedVector3Array([Vector3(0.09, -0.07, 0.0), Vector3(hw, rise, 0.13)])
		"Ape hanger":
			for side in [-1.0, 1.0]:
				var post_top := Vector3(0.12 * side, rise, 0.0)
				_tube(Vector3(0.05 * side, 0.02, 0.0), post_top, 0.012, mat, Vector3.ONE, _steer_node)
				var end := Vector3(hw * side, rise - 0.03, 0.14)
				_tube(post_top, end, 0.012, mat, Vector3.ONE, _steer_node)
				ends.append(end)
			_bar_line = PackedVector3Array([Vector3(0.05, 0.02, 0.0), Vector3(0.12, rise, 0.0), Vector3(hw, rise - 0.03, 0.14)])
		"MX braced":
			for side in [-1.0, 1.0]:
				var mid := Vector3(0.14 * side, rise, 0.0)
				var end := Vector3(hw * side, rise + 0.03, 0.1)
				_tube(mid, end, 0.014, mat, Vector3.ONE, _steer_node)
				_tube(Vector3(0.04 * side, 0.02, 0.0), mid, 0.016, mat, Vector3.ONE, _steer_node)
				ends.append(end)
			_tube(Vector3(-0.14, rise, 0.0), Vector3(0.14, rise, 0.0), 0.014, mat, Vector3.ONE, _steer_node)
			_tube(Vector3(-0.12, rise + 0.07, 0.01), Vector3(0.12, rise + 0.07, 0.01), 0.01, mat, Vector3.ONE, _steer_node)
			_bar_line = PackedVector3Array([Vector3(0.0, rise, 0.0), Vector3(0.14, rise, 0.0), Vector3(hw, rise + 0.03, 0.1)])
		_:
			_tube(Vector3(-hw, rise, 0.06), Vector3(hw, rise, 0.06), 0.012, mat, Vector3.ONE, _steer_node)
			for side in [-1.0, 1.0]:
				_tube(Vector3(0.04 * side, 0.0, 0.0), Vector3(0.04 * side, rise, 0.06), 0.014, mat, Vector3.ONE, _steer_node)
				ends.append(Vector3(hw * side, rise, 0.06))
			_bar_line = PackedVector3Array([Vector3(0.0, rise, 0.06), Vector3(hw, rise, 0.06)])
	_tex(rubber, "knurl", 70.0)
	for end in ends:
		var inward := Vector3(-signf(end.x) * 0.1, 0.0, 0.0)
		_tube(end, end + inward, 0.018, rubber, Vector3.ONE, _steer_node).name = "Grip"
		# The grip's flange at the inner end.
		var flange := _mesh_instance(_cylinder(0.022, 0.006), rubber, end + inward, _steer_node)
		flange.rotation.z = PI * 0.5
	_grip_l = ends[0] + Vector3(0.05, 0.0, 0.0)
	_grip_r = ends[1] + Vector3(-0.05, 0.0, 0.0)
	_draw_controls(ends[0], ends[1])


## A one-piece bar bent to the shape its look names in "bend": tracker, moto, drag, buckhorn,
## z, t (one fat post in the middle), clubman (dropping below the clamp) or ape. "pull" is how
## far the ends come back to the rider, "drop" how far they fall at the tips, "risers" the
## height of the risers under the clamp, "brace" an MX cross bar (with a "pad" on it) and
## "thick" the tube. Returns the left and right bar ends.
func _bent_bar(lk: Dictionary, hw: float, rise: float, mat: Material) -> Array:
	var bend := str(lk.get("bend", "tracker"))
	var pull := float(lk.get("pull", 0.08))
	var drop := float(lk.get("drop", 0.0))
	var rh := float(lk.get("risers", 0.02))
	var thick := float(lk.get("thick", 0.012))
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	var right := []
	match bend:
		"drag":
			right = [Vector3(0.0, rh, 0.0), Vector3(hw * 0.6, rh + rise * 0.5, pull * 0.4), Vector3(hw, rh + rise, pull)]
		"buckhorn":
			right = [Vector3(0.0, rh, 0.0), Vector3(0.1, rh, 0.0), Vector3(0.17, rh + rise, -0.02), Vector3(hw * 0.85, rh + rise + 0.02, pull * 0.8), Vector3(hw, rh + rise - drop - 0.03, pull)]
		"z":
			right = [Vector3(0.0, rh, 0.0), Vector3(0.1, rh, 0.0), Vector3(0.12, rh + 0.02, 0.0), Vector3(0.13, rh + rise - 0.02, 0.01), Vector3(0.15, rh + rise, 0.02), Vector3(hw, rh + rise - drop, pull)]
		"t":
			right = [Vector3(0.0, rh + rise, 0.0), Vector3(hw * 0.5, rh + rise, pull * 0.3), Vector3(hw, rh + rise - drop, pull)]
		"clubman":
			right = [Vector3(0.0, rh, 0.0), Vector3(0.08, rh, 0.0), Vector3(0.15, rh - drop * 0.7, pull * 0.5), Vector3(hw, rh - drop, pull)]
		"ape":
			right = [Vector3(0.0, rh, 0.0), Vector3(0.09, rh, 0.0), Vector3(0.12, rh + rise * 0.6, -0.01), Vector3(0.14, rh + rise, 0.02), Vector3(hw * 0.8, rh + rise, pull * 0.7), Vector3(hw, rh + rise - drop - 0.02, pull)]
		_:
			right = [Vector3(0.0, rh, 0.0), Vector3(0.1, rh, 0.0), Vector3(0.18, rh + rise * 0.8, pull * 0.4), Vector3(hw, rh + rise - drop, pull)]
	var path := []
	for i in range(right.size() - 1, 0, -1):
		var q: Vector3 = right[i]
		path.append(Vector3(-q.x, q.y, q.z))
	path.append_array(right)
	_bend(path, thick, mat, _steer_node, 10)
	_bar_line = PackedVector3Array(right)
	if bend == "t":
		_tube(Vector3(0.0, -0.01, 0.0), Vector3(0.0, rh + rise, 0.0), 0.022, mat, Vector3.ONE, _steer_node)
	elif rh > 0.025:
		for side in [-1.0, 1.0]:
			_tube(Vector3(0.04 * side, -0.01, 0.0), Vector3(0.04 * side, rh + 0.005, 0.0), 0.016, chrome if lk.get("chrome_risers", false) else mat, Vector3.ONE, _steer_node)
	else:
		_box(Vector3(0.0, rh, 0.0), Vector3(0.1, 0.03, 0.04), _mat(Color(0.2, 0.2, 0.22), 0.8, 0.35), _steer_node)
	if lk.get("brace", false):
		var by := rh + maxf(rise, 0.02) * 0.7
		_tube(Vector3(-0.13, by, pull * 0.3), Vector3(0.13, by, pull * 0.3), 0.009, mat, Vector3.ONE, _steer_node)
		if lk.get("pad", false):
			var pad := _mesh_instance(_capsule(0.025, 0.2), _mat(_accent(Color(0.9, 0.1, 0.1)), 0.0, 0.8), Vector3(0.0, by + 0.005, pull * 0.3), _steer_node)
			pad.rotation.z = PI * 0.5
	var tip: Vector3 = right[right.size() - 1]
	return [Vector3(-tip.x, tip.y, tip.z), tip]


## A finish from a look ("chrome", "black", "brushed", "titanium", "gold", "copper", "carbon",
## "wrap" heat wrap, "wrap_black", "white", "polished"), or `fallback`.
func _look_finish(name: String, fallback: Material) -> Material:
	match name:
		"chrome":
			return _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1)
		"polished":
			return _mat(Color(0.8, 0.8, 0.8), 1.0, 0.2)
		"black":
			return _mat(Color(0.05, 0.05, 0.05), 0.6, 0.45)
		"brushed":
			return _tex(_mat(Color(0.7, 0.71, 0.73), 1.0, 0.38), "brushed")
		"titanium":
			return _tex(_mat(Color(0.42, 0.44, 0.62), 1.0, 0.22), "brushed", -1.0, 0.6)
		"gold":
			return _mat(Color(0.82, 0.66, 0.25), 1.0, 0.18)
		"copper":
			return _mat(Color(0.72, 0.42, 0.25), 1.0, 0.25)
		"carbon":
			return _tex(_mat(Color(0.07, 0.07, 0.08), 0.25, 0.3, 1.0), "carbon")
		"wrap":
			return _mat(Color(0.74, 0.69, 0.58), 0.0, 0.95)
		"wrap_black":
			return _mat(Color(0.08, 0.08, 0.08), 0.0, 0.95)
		"white":
			return _mat(Color(0.92, 0.92, 0.9), 0.1, 0.35, 0.5)
		"red":
			return _mat(Color(0.75, 0.08, 0.06), 0.3, 0.3, 0.6)
	return fallback


func _draw_dashboard() -> void:
	_current_slot = "dashboard"
	_needles.clear()
	_leds.clear()
	_dash_screen = Transform3D()
	_dash_raised = 0.0
	var p := _part()
	var housing := _mat(_col(), 0.6, 0.35)
	var at := Vector3(0.0, 0.1, -0.06)
	if _race_fairing_fitted():
		# Tucked down behind a full fairing's screen.
		at = Vector3(0.0, 0.01, 0.02)
	# The clocks lean back towards the rider, so their faces look up and back at the eyes.
	var tilt := Basis(Vector3.RIGHT, 0.9)
	var face_mat := _lamp(Color(0.95, 0.9, 0.75), 1.2, "ign")
	var needle_mat := _lamp(Color(1.0, 0.25, 0.1), 2.5, "ign")
	match str(p.get("style", "analog")):
		"analog", "twin":
			var twin: bool = p.get("style") == "twin"
			var dials := [{"x": -0.06, "what": "speed"}, {"x": 0.06, "what": "rpm"}] if twin else [{"x": 0.0, "what": "speed"}]
			for d in dials:
				var c: Vector3 = at + Vector3(d["x"], 0.0, 0.0)
				var dial := _mesh_instance(_cylinder(0.05, 0.05), housing, c, _steer_node)
				dial.basis = tilt
				var face := _mesh_instance(_cylinder(0.043, 0.004), face_mat, c + tilt.y * 0.026, _steer_node)
				face.basis = tilt
				_add_face(c + tilt.y * 0.028, tilt, 0.04, 0.04, true)
				# Tick marks round the dial.
				for i in 9:
					var a := lerpf(-2.35, 2.35, i / 8.0)
					var tick := _box(c + tilt.y * 0.029 + tilt * Vector3(sin(a) * 0.036, 0.0, -cos(a) * 0.036), Vector3(0.003, 0.002, 0.008), _mat(Color(0.05, 0.05, 0.05), 0.0, 0.8), _steer_node)
					tick.basis = tilt * Basis(Vector3.UP, -a)
				var pivot := Node3D.new()
				pivot.position = c + tilt.y * 0.031
				pivot.basis = tilt
				_steer_node.add_child(pivot)
				_box(Vector3(0.0, 0.0, -0.016), Vector3(0.004, 0.003, 0.034), needle_mat, pivot)
				_needles.append({"node": pivot, "what": d["what"]})
			# The little window under the needle (or between the two dials) for gear and fuel.
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.032 + tilt * Vector3(0.0, 0.0, 0.046 if twin else 0.022))
		"lcd", "tft":
			var tft: bool = p.get("style") == "tft"
			var size := Vector3(0.2, 0.03, 0.12) if tft else Vector3(0.16, 0.03, 0.09)
			var body := _box(at, size, housing, _steer_node)
			body.basis = tilt
			var screen := _box(at + tilt.y * 0.016, Vector3(size.x - 0.02, 0.004, size.z - 0.02),
				_lamp(Color(0.05, 0.12, 0.25) if tft else Color(0.42, 0.55, 0.42), 1.0, "ign"), _steer_node)
			screen.basis = tilt
			_add_face(at + tilt.y * 0.018, tilt, size.x * 0.5 - 0.01, size.z * 0.5 - 0.01)
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.019)
			if tft:
				_add_leds(at + tilt.y * 0.017 + tilt * Vector3(0.0, 0.0, -size.z * 0.5 - 0.008), tilt, 0.14)
		_:
			var body := _box(at, Vector3(0.22, 0.03, 0.09), housing, _steer_node)
			body.basis = tilt
			var screen := _box(at + tilt.y * 0.016 + tilt * Vector3(0.0, 0.0, 0.012), Vector3(0.18, 0.004, 0.05),
				_lamp(Color(0.03, 0.03, 0.04), 0.6, "ign"), _steer_node)
			screen.basis = tilt
			_add_face(at + tilt.y * 0.018 + tilt * Vector3(0.0, 0.0, 0.012), tilt, 0.09, 0.025)
			_dash_screen = Transform3D(tilt, at + tilt.y * 0.019 + tilt * Vector3(0.0, 0.0, 0.012))
			_add_leds(at + tilt.y * 0.017 + tilt * Vector3(0.0, 0.0, -0.028), tilt, 0.18)
	_lift_clear_of_bars(at)


## Raises the clocks, if need be, until the bars (and what's on them) hide none of their faces
## from the rider's eye, nor from a little below it for a rider sat lower: tall, braced and
## T-bars all rise across the middle, right where the clocks sit. Clocks raised more than a
## little stand on a stalk from the top yoke (the clocks sit at `at` before they're raised).
func _lift_clear_of_bars(at: Vector3) -> void:
	if _dash_face.is_empty():
		return
	var bars := _bars_mesh()
	if bars == null:
		return
	var lift := _dash_lift(bars, _eye - _head)
	if lift == 0.0:
		return
	_dash_raised = lift
	for mi in _slot_meshes["dashboard"]:
		if (mi as Node).get_parent() == _steer_node:
			(mi as Node3D).position.y += lift
	for n in _needles:
		(n["node"] as Node3D).position.y += lift
	_dash_screen.origin.y += lift
	for i in _dash_face.size():
		_dash_face[i] += Vector3(0.0, lift, 0.0)
	if lift > 0.02:
		_tube(Vector3(0.0, 0.0, at.z), at + Vector3(0.0, lift - 0.012, 0.0), 0.009, _mat(Color(0.06, 0.06, 0.065), 0.5, 0.4), Vector3.ONE, _steer_node)


## How far the clocks have to rise (m, in 5 mm steps up to DASH_LIFT_MAX) for none of their
## faces to be hidden by `bars` from `eye` (in steering space) or from DASH_EYE_SPARE below it.
func _dash_lift(bars: TriangleMesh, eye: Vector3) -> float:
	var low := eye + Vector3(0.0, -DASH_EYE_SPARE, 0.0)
	var lift := 0.0
	while lift < DASH_LIFT_MAX and (_face_hidden(bars, eye, lift - _dash_raised) > 0 or _face_hidden(bars, low, lift - _dash_raised) > 0):
		lift += 0.005
	return lift


## The bars and everything on them, as triangles in steering space (for _face_hidden).
func _bars_mesh() -> TriangleMesh:
	if _bars_tm != null:
		return _bars_tm
	var faces := PackedVector3Array()
	for mi in _slot_meshes.get("handlebars", []):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != _steer_node and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		faces.append_array(xf * (mi as MeshInstance3D).mesh.get_faces())
	if faces.is_empty():
		return null
	_bars_tm = TriangleMesh.new()
	_bars_tm.create_from_faces(faces)
	return _bars_tm


## How many of the points over the clocks' faces (raised `lift`) the bars hide from `eye`, all
## in steering space.
func _face_hidden(bars: TriangleMesh, eye: Vector3, lift := 0.0) -> int:
	var hidden := 0
	for q in _dash_face:
		var from: Vector3 = q + Vector3(0.0, lift, 0.0)
		from += (eye - from).normalized() * 0.002
		if not bars.intersect_segment(from, eye).is_empty():
			hidden += 1
	return hidden


## Records a dial or screen of the clocks for dash_hidden: points over a face `hx` by `hz`
## across (half sizes, in the face's own plane), a 5 by 5 grid, or on two rings and the middle
## of a round one, close enough that no bar can pass between them.
func _add_face(center: Vector3, tilt: Basis, hx: float, hz: float, round := false) -> void:
	if round:
		_dash_face.append(center)
		for ring in [[0.5, 8], [1.0, 12]]:
			for i in ring[1]:
				var a: float = TAU * i / float(ring[1])
				_dash_face.append(center + tilt * Vector3(cos(a) * hx, 0.0, sin(a) * hz) * float(ring[0]))
		return
	for i in 5:
		for j in 5:
			_dash_face.append(center + tilt * Vector3((i * 0.5 - 1.0) * hx, 0.0, (j * 0.5 - 1.0) * hz))


## A row of shift lights across the top of the clocks, green to amber to red.
func _add_leds(center: Vector3, tilt: Basis, width: float) -> void:
	var colors := [Color(0.1, 1.0, 0.2), Color(0.1, 1.0, 0.2), Color(1.0, 0.85, 0.1), Color(1.0, 0.85, 0.1), Color(1.0, 0.1, 0.05), Color(1.0, 0.1, 0.05)]
	for i in 6:
		var mat := _glow(colors[i], 0.0)
		var led := _box(center + tilt.x * (-width * 0.5 + width * (i + 0.5) / 6.0), Vector3(0.016, 0.004, 0.01), mat, _steer_node)
		led.basis = tilt
		_leds.append({"mat": mat, "color": colors[i]})


## Moves the needles and shift lights: `speed_frac` and `rpm_frac` are 0..1 of full scale.
func set_gauges(speed_frac: float, rpm_frac: float) -> void:
	for n in _needles:
		var f: float = speed_frac if n["what"] == "speed" else rpm_frac
		(n["node"] as Node3D).basis = _dash_screen.basis * Basis(Vector3.UP, lerpf(2.35, -2.35, clampf(f, 0.0, 1.0)))
	for i in _leds.size():
		var lit := rpm_frac > 0.55 + i * 0.07
		var m: StandardMaterial3D = _leds[i]["mat"]
		m.emission_energy_multiplier = 3.0 if lit else 0.0
		m.albedo_color = _leds[i]["color"] if lit else Color(0.08, 0.08, 0.08)
	_buzz_satnav(rpm_frac)
	if not geometry.is_empty() and not _needles.is_empty():
		_update_geometry()


## A phone in its cradle buzzes a little with the engine (`rpm_frac` 0..1 of full scale, 0 with it
## stopped): a fraction of a millimetre at tickover, more up the revs.
func _buzz_satnav(rpm_frac: float) -> void:
	if _satnav_cradle == null or not is_instance_valid(_satnav_cradle):
		return
	if rpm_frac < 0.02:
		_satnav_cradle.position = _satnav_rest
		return
	var amp := KitModel.BUZZ * (0.35 + 0.65 * clampf(rpm_frac, 0.0, 1.0))
	var t := Time.get_ticks_msec() * 0.001
	var w := 140.0 + 260.0 * clampf(rpm_frac, 0.0, 1.0)
	_satnav_cradle.position = _satnav_rest + _satnav_cradle.basis * Vector3(sin(t * w * 0.83) * 0.5, sin(t * w + 1.3), 0.0) * amp


## The bits on the bars round the grips: the clutch lever on its perch, switch gear both sides,
## the throttle housing, bar-end weights, and the clutch and throttle cables. Each cable runs
## from the bars to just under the bottom yoke (turning with the steering), then on to the
## engine side of the frame.
func _draw_controls(l_end: Vector3, r_end: Vector3) -> void:
	var alloy := _tex(_mat(Color(0.7, 0.71, 0.73), 1.0, 0.3), "brushed")
	var black := _mat(Color(0.05, 0.05, 0.055), 0.2, 0.5)
	var cable := _mat(Color(0.03, 0.03, 0.035), 0.0, 0.6)
	var steel := _mat(Color(0.82, 0.83, 0.85), 1.0, 0.2)
	var inward_l := Vector3(1.0, 0.0, 0.0)
	# Switch gear housings just inboard of each grip, and the throttle tube on the right.
	var sw_l := l_end + inward_l * 0.118
	_box(sw_l, Vector3(0.03, 0.042, 0.048), black, _steer_node).name = "SwitchGear"
	_box(sw_l + Vector3(0.0, 0.005, -0.026), Vector3(0.016, 0.01, 0.006), _mat(Color(0.85, 0.1, 0.06), 0.1, 0.4), _steer_node)
	var thr := r_end - inward_l * 0.103
	var housing := _mesh_instance(_cylinder(0.022, 0.022), black, thr, _steer_node)
	housing.rotation.z = PI * 0.5
	housing.name = "Throttle"
	_box(thr + Vector3(0.0, 0.02, 0.0), Vector3(0.02, 0.016, 0.03), black, _steer_node)
	# Bar-end weights.
	for be in [l_end, r_end]:
		var out := Vector3(signf(be.x), 0.0, 0.0)
		var w := _mesh_instance(_cylinder(0.017, 0.022), steel, be + out * 0.008, _steer_node)
		w.rotation.z = PI * 0.5
		w.name = "BarEnd"
	# The clutch lever: a clamp on the bar, the blade sweeping out in front of the grip.
	var perch := l_end + inward_l * 0.152
	var clamp := _mesh_instance(_cylinder(0.019, 0.026), alloy, perch, _steer_node)
	clamp.rotation.z = PI * 0.5
	_box(perch + Vector3(0.0, 0.0, -0.026), Vector3(0.026, 0.02, 0.028), alloy, _steer_node)
	var blade := _bend([perch + Vector3(0.0, -0.004, -0.04), perch + Vector3(-0.04, -0.008, -0.05), l_end + Vector3(0.025, -0.012, -0.045)],
		0.0055, alloy, _steer_node, 6)
	blade.name = "ClutchLever"
	_mesh_instance(_sphere(0.009), alloy, l_end + Vector3(0.023, -0.012, -0.045), _steer_node)
	# Cables: out of the perch and the throttle, down past the headstock.
	var j_l := -_steer_axis * 0.24 + Vector3(-0.055, 0.0, 0.035)
	var j_r := -_steer_axis * 0.24 + Vector3(0.055, 0.0, 0.035)
	var c1 := _bike_only(_bend([perch + Vector3(0.012, 0.0, -0.05), perch.lerp(j_l, 0.35) + Vector3(0.0, 0.03, -0.14), j_l], 0.0042, cable, _steer_node, 6))
	c1.name = "ClutchCable"
	var c2 := _bike_only(_bend([thr + Vector3(-0.01, 0.0, -0.02), thr.lerp(j_r, 0.35) + Vector3(0.0, 0.03, -0.14), j_r], 0.0042, cable, _steer_node, 6))
	c2.name = "ThrottleCable"
	# ...then on in the frame to the clutch arm and the carbs or throttle bodies.
	var jl := _head + j_l
	var jr := _head + j_r
	var e := _engine_c
	var clutch_end := e + Vector3(-_block_w * 0.5 - 0.02, 0.07 * _eng_s, 0.15 * _eng_s)
	_bike_only(_bend([jl, jl + Vector3(-0.01, -0.06, 0.08), clutch_end + Vector3(-0.015, 0.1, -0.08), clutch_end], 0.0042, cable, self, 6))
	_bike_only(_mesh_instance(_cylinder(0.008, 0.02), steel, clutch_end, self))
	var intake: Array = _intake_points()
	if not intake.is_empty():
		var thr_end: Vector3 = intake[0]["port"] + intake[0]["dir"] * 0.05 + Vector3(0.03, 0.045, 0.0)
		_bike_only(_bend([jr, jr + Vector3(0.01, -0.04, 0.08), thr_end + Vector3(0.0, 0.06, -0.06), thr_end], 0.0042, cable, self, 6))


## How far out the fork legs sit, for the parts that clip to them.
func _fork_x() -> float:
	var fork := PartsDB.get_part(str(_build.parts.get("fork", "")))
	match str(fork.get("style", "conventional")):
		"girder":
			return 0.09
		"springer", "leading_link":
			return 0.085
	return 0.09 * float((fork.get("look", {}) as Dictionary).get("wide", 1.0))


## Where the front brake line hands over from the bars to the fork leg, in steering space.
func _brake_line_joint() -> Vector3:
	return Vector3(_fork_x() + 0.035, 0.0, 0.04) - _steer_axis * 0.3


func _front_is_drum() -> bool:
	return str(PartsDB.get_part(str(_build.parts.get("front_disc", ""))).get("style", "")) == "drum"


func _rear_is_drum() -> bool:
	return str(PartsDB.get_part(str(_build.parts.get("rear_disc", ""))).get("style", "")) == "drum"


func _draw_front_master() -> void:
	_current_slot = "front_master"
	var mat := _tex(_mat(_col(), 0.6, 0.35), "brushed", -1.0, 0.6)
	var radial := str(_part().get("type", "")).begins_with("Radial")
	var at := _grip_r + Vector3(-0.08, 0.0, 0.0)
	_box(at, Vector3(0.04, 0.04, 0.05) if radial else Vector3(0.035, 0.035, 0.035), mat, _steer_node)
	var res := _mesh_instance(_cylinder(0.022 if radial else 0.018, 0.03), mat, at + Vector3(0.0, 0.04, 0.0), _steer_node)
	res.name = "Reservoir"
	_mesh_instance(_cylinder(0.02 if radial else 0.016, 0.004), _mat(Color(0.05, 0.05, 0.05), 0.2, 0.5), at + Vector3(0.0, 0.057, 0.0), _steer_node)
	# The lever: a shaped blade with a ball end, in front of the grip.
	var tip := _grip_r + Vector3(0.06, -0.012, -0.05)
	var blade := _bend([at + Vector3(0.0, -0.004, -0.03), at + Vector3(0.04, -0.008, -0.05), tip], 0.0055,
		_tex(_mat(Color(0.7, 0.71, 0.73), 1.0, 0.3), "brushed"), _steer_node, 6)
	blade.name = "BrakeLever"
	_mesh_instance(_sphere(0.009), _mat(Color(0.7, 0.71, 0.73), 1.0, 0.3), tip, _steer_node)
	# The brake hose (or cable, for a drum) from the master down to the fork leg.
	var line := _mat(Color(0.03, 0.03, 0.035), 0.1, 0.55) if _front_is_drum() else _mat(Color(0.05, 0.05, 0.06), 0.3, 0.4)
	var j := _brake_line_joint()
	var hose := _bike_only(_bend([at + Vector3(0.0, -0.01, -0.025), at.lerp(j, 0.3) + Vector3(0.0, 0.0, -0.16), j], 0.005 if not _front_is_drum() else 0.0042, line, _steer_node, 8))
	hose.name = "BrakeHose"
	_mesh_instance(_cylinder(0.0075, 0.016), _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2), at + Vector3(0.0, -0.01, -0.03), _steer_node)


func _draw_rear_master() -> void:
	_current_slot = "rear_master"
	var mat := _mat(_col(), 0.6, 0.35)
	var at := Vector3(0.15, 0.06, _pivot.z - 0.04)
	_tube(at, at + Vector3(0.0, 0.1, 0.03), 0.014, mat)
	_mesh_instance(_cylinder(0.02, 0.04), mat, at + Vector3(0.0, 0.16, 0.08))


## The headlight on the fork: round, a café bucket, twin lamps, twin bug-eyes, an old-school
## square lamp, an enduro plate or an LED projector.
func _draw_headlight() -> void:
	_current_slot = "headlight"
	var p := _part()
	if p.is_empty():
		return
	var at := Vector3(0.0, -0.08, -0.13)
	var size := float(p.get("size", 0.08))
	var shell := _mat(_col(), 0.7, 0.3)
	var lens := _lamp(Color(1.0, 0.95, 0.82) if float(p.get("lumens", 0)) < 2000 else Color(0.9, 0.95, 1.0), 2.5, "head")
	var lk := _look()
	size *= float(lk.get("size", 1.0))
	var chrome := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1)
	shell = _look_finish(str(lk.get("shell", "")), shell)
	# Where the lens is, for a look's chrome ring, grille or visor.
	var front := at + Vector3(0.0, 0.0, -size * 0.7)
	var face_r := size * 0.9
	match str(lk.get("lamp", p.get("style", "round"))):
		"bullet":
			var body := _mesh_instance(_cylinder(size, size * 1.9, size * 0.45), shell, at + Vector3(0.0, 0.0, size * 0.5), _steer_node)
			body.rotation.x = -PI * 0.5
			var face := _mesh_instance(_cylinder(size * 0.9, 0.012), lens, at + Vector3(0.0, 0.0, -size * 0.45), _steer_node)
			face.rotation.x = PI * 0.5
			front = at + Vector3(0.0, 0.0, -size * 0.45)
		"oval":
			var lamp := _mesh_instance(_sphere(size), shell, at, _steer_node)
			lamp.scale = Vector3(1.3, 0.8, 0.75)
			var face := _mesh_instance(_cylinder(size * 0.9, 0.012), lens, at + Vector3(0.0, 0.0, -size * 0.7), _steer_node)
			face.rotation.x = PI * 0.5
			face.scale = Vector3(1.3, 1.0, 0.8)
		"quad":
			for x in [-0.045, 0.045]:
				for y in [-0.04, 0.04]:
					var cell := _box(at + Vector3(x, y, 0.0), Vector3(0.08, 0.07, 0.08), shell, _steer_node)
					cell.name = "Cell"
					_box(at + Vector3(x, y, -0.042), Vector3(0.066, 0.056, 0.006), lens, _steer_node)
			face_r = 0.0
		"stacked":
			for y in [-0.055, 0.055]:
				var lamp := _mesh_instance(_sphere(size * 0.7), shell, at + Vector3(0.0, y, 0.0), _steer_node)
				lamp.scale = Vector3(1.0, 1.0, 0.75)
				var face := _mesh_instance(_cylinder(size * 0.62, 0.01), lens, at + Vector3(0.0, y, -size * 0.5), _steer_node)
				face.rotation.x = PI * 0.5
			face_r = 0.0
		"square":
			_square_lamp(at, size, shell, lens, lk)
			face_r = 0.0
		"bugeye":
			_bugeye_lamps(at, size, shell, lens, chrome)
			face_r = 0.0
		"nacelle":
			# A round lamp sunk into a cowl that wraps back over the fork tops.
			_shell([{"c": at + Vector3(0.0, 0.0, -size * 0.5), "w": size * 1.05, "up": size * 1.05, "n": 2.0},
				{"c": at + Vector3(0.0, 0.01, 0.06), "w": size * 1.35, "up": size * 1.25, "down": size * 1.1, "n": 2.3},
				{"c": at + Vector3(0.0, 0.03, 0.16), "w": size * 1.2, "up": size * 0.9, "down": size * 0.9, "n": 2.6}], shell, false, 0.0, TAU, _steer_node)
			var face := _mesh_instance(_cylinder(size * 0.95, 0.012), lens, at + Vector3(0.0, 0.0, -size * 0.52), _steer_node)
			face.rotation.x = PI * 0.5
			front = at + Vector3(0.0, 0.0, -size * 0.52)
		"bucket":
			var bucket := _mesh_instance(_cylinder(size, size * 1.1, size * 0.75), shell, at + Vector3(0.0, 0.0, 0.03), _steer_node)
			bucket.rotation.x = -PI * 0.5
			var face := _mesh_instance(_cylinder(size * 0.92, 0.01), lens, at + Vector3(0.0, 0.0, -0.03), _steer_node)
			face.rotation.x = PI * 0.5
		"twin":
			for x in [-0.07, 0.07]:
				var lamp := _mesh_instance(_sphere(size), shell, at + Vector3(x, 0.0, 0.01), _steer_node)
				lamp.scale = Vector3(1.0, 1.0, 0.7)
				var face := _mesh_instance(_cylinder(size * 0.85, 0.01), lens, at + Vector3(x, 0.0, -size * 0.6), _steer_node)
				face.rotation.x = PI * 0.5
		"plate":
			var plate := _box(at + Vector3(0.0, -0.02, -0.02), Vector3(0.22, 0.27, 0.02), shell, _steer_node)
			plate.rotation.x = 0.25
			var face := _box(at + Vector3(0.0, 0.0, -0.035), Vector3(0.1, 0.07, 0.01), lens, _steer_node)
			face.rotation.x = 0.25
		"projector":
			_box(at + Vector3(0.0, 0.0, 0.0), Vector3(0.17, 0.09, 0.09), shell, _steer_node)
			for x in [-0.04, 0.04]:
				var face := _mesh_instance(_cylinder(0.025, 0.01), lens, at + Vector3(x, 0.0, -0.05), _steer_node)
				face.rotation.x = PI * 0.5
			_box(at + Vector3(0.0, -0.035, -0.047), Vector3(0.15, 0.008, 0.004), _lamp(Color(0.85, 0.92, 1.0), 3.0, "head"), _steer_node)
		_:
			var lamp := _mesh_instance(_sphere(size), shell, at, _steer_node)
			lamp.scale = Vector3(1.0, 1.0, 0.75)
			var face := _mesh_instance(_cylinder(size * 0.9, 0.012), lens, at + Vector3(0.0, 0.0, -size * 0.7), _steer_node)
			face.rotation.x = PI * 0.5
	if face_r > 0.0:
		if lk.get("ring", false):
			var ring := _mesh_instance(_torus(face_r, 0.009), chrome, front + Vector3(0.0, 0.0, -0.004), _steer_node)
			ring.rotation.x = PI * 0.5
		if lk.get("grille", false):
			for k in 3:
				_box(front + Vector3(0.0, (k - 1) * face_r * 0.5, -0.012), Vector3(face_r * 1.7, 0.006, 0.006), _mat(Color(0.05, 0.05, 0.05), 0.5, 0.5), _steer_node)
			_box(front + Vector3(0.0, 0.0, -0.014), Vector3(0.006, face_r * 1.7, 0.006), _mat(Color(0.05, 0.05, 0.05), 0.5, 0.5), _steer_node)
		if lk.get("visor", false):
			var peak := _shell([{"c": front + Vector3(0.0, face_r * 0.15, 0.02), "w": face_r * 1.05, "up": face_r * 1.05, "n": 2.0},
				{"c": front + Vector3(0.0, face_r * 0.15, -0.05), "w": face_r * 1.0, "up": face_r * 0.95, "n": 2.0}], shell, true, 0.2, PI - 0.2, _steer_node)
			peak.name = "Visor"
	if lk.get("brackets", false):
		for side in [-1.0, 1.0]:
			_tube(at + Vector3(size * 1.05 * side, 0.0, 0.0), Vector3(0.09 * side, -0.02, 0.0), 0.007, chrome, Vector3.ONE, _steer_node)


## An old-school rectangular headlight centred on `at` (steering space), `size` setting its scale:
## a deep pressed-steel bucket tapering to the back, fluted glass with the bulb's hot spot behind
## it, and a bezel round the glass (look "bezel": chrome or black). On ears to the fork legs.
func _square_lamp(at: Vector3, size: float, shell: Material, lens: Material, lk: Dictionary) -> void:
	var w := size * 2.3
	var h := size * 1.7
	var front := at.z - size * 0.3
	var body := _box(at + Vector3(0.0, 0.0, size * 0.12), Vector3(w * 0.96, h * 0.94, size * 0.84), shell, _steer_node)
	body.name = "LampBody"
	_box(at + Vector3(0.0, 0.0, size * 0.7), Vector3(w * 0.7, h * 0.64, size * 0.4), shell, _steer_node)
	var bezel := _look_finish(str(lk.get("bezel", "chrome")), shell)
	var t := size * 0.13
	for y in [-1.0, 1.0]:
		_box(Vector3(at.x, at.y + y * (h - t) * 0.5, front - 0.004), Vector3(w, t, 0.02), bezel, _steer_node).name = "Bezel"
	for x in [-1.0, 1.0]:
		_box(Vector3(at.x + x * (w - t) * 0.5, at.y, front - 0.004), Vector3(t, h - t * 2.0 + 0.002, 0.02), bezel, _steer_node).name = "Bezel"
	var glass := Vector2(w - t * 2.0 + 0.004, h - t * 2.0 + 0.004)
	_box(Vector3(at.x, at.y, front), Vector3(glass.x, glass.y, 0.008), lens, _steer_node).name = "Lens"
	# The reflector's hot spot round the bulb, and the glass's flutes and its middle rib over it.
	var spot := _mesh_instance(_cylinder(size * 0.26, 0.004), _lamp(Color(1.0, 0.97, 0.88), 4.0, "head"), Vector3(at.x, at.y, front - 0.005), _steer_node)
	spot.rotation.x = PI * 0.5
	var flute := _lamp(Color(0.78, 0.7, 0.56), 0.9, "head")
	for i in 7:
		var x := (i - 3) / 3.0 * glass.x * 0.42
		_box(Vector3(at.x + x, at.y, front - 0.008), Vector3(0.003, glass.y * 0.96, 0.003), flute, _steer_node)
	_box(Vector3(at.x, at.y, front - 0.009), Vector3(glass.x * 0.96, 0.003, 0.003), flute, _steer_node)
	if not lk.get("brackets", false):
		# Black steel ears back to the fork legs (chrome ones are the "brackets" look's).
		var ear := _mat(Color(0.05, 0.05, 0.055), 0.6, 0.45)
		for side in [-1.0, 1.0]:
			_tube(at + Vector3(w * 0.45 * side, 0.0, size * 0.2), Vector3(0.09 * side, -0.02, 0.0), 0.008, ear, Vector3.ONE, _steer_node)


## Twin bug-eye headlamps centred on `at` (steering space): two small oval lamps side by side,
## close together, each turned out a little and tilted top-outward like a wasp's eyes, with a
## chrome rim, a reflector ring and the bulb's hot spot in each glass. They sit on a short
## black bracket to the fork legs, under a little tinted fly-screen when no fairing is fitted.
func _bugeye_lamps(at: Vector3, size: float, shell: Material, lens: Material, chrome: Material) -> void:
	var gap := size * 1.04
	var spot := _lamp(Color(1.0, 0.97, 0.88), 4.0, "head")
	var black := _mat(Color(0.05, 0.05, 0.055), 0.6, 0.4)
	for side in [-1.0, 1.0]:
		var c := at + Vector3(side * gap, 0.0, 0.0)
		var b := Basis(Vector3.UP, -side * 0.3) * Basis(Vector3.BACK, -side * 0.28)
		var oval := Basis.from_scale(Vector3(0.88, 1.18, 1.0))
		var body := _mesh_instance(_sphere(size), shell, c, _steer_node)
		body.basis = b * Basis.from_scale(Vector3(0.9, 1.2, 1.05))
		body.name = "BugEye"
		# A tapered back on each lamp shell, pointing back towards the bracket.
		var back := _mesh_instance(_cylinder(size * 0.75, size * 1.1, size * 0.35), shell, c + b * Vector3(0.0, 0.0, size * 0.75), _steer_node)
		back.basis = b * Basis(Vector3.RIGHT, PI * 0.5)
		var face_at := c + b * Vector3(0.0, 0.0, -size * 1.0)
		var face := _mesh_instance(_cylinder(size * 0.86, 0.01), lens, face_at, _steer_node)
		face.basis = b * oval * Basis(Vector3.RIGHT, PI * 0.5)
		face.name = "Lens"
		var rim := _mesh_instance(_torus(size * 0.88, 0.005), chrome, face_at + b * Vector3(0.0, 0.0, 0.002), _steer_node)
		rim.basis = b * oval * Basis(Vector3.RIGHT, PI * 0.5)
		var ring := _mesh_instance(_torus(size * 0.55, 0.0018), chrome, face_at + b * Vector3(0.0, 0.0, -0.006), _steer_node)
		ring.basis = b * oval * Basis(Vector3.RIGHT, PI * 0.5)
		var hot := _mesh_instance(_cylinder(size * 0.3, 0.003), spot, face_at + b * Vector3(0.0, 0.0, -0.006), _steer_node)
		hot.basis = b * oval * Basis(Vector3.RIGHT, PI * 0.5)
		# The bracket: a short arm from the lamp's back to the fork leg.
		_tube(c + b * Vector3(0.0, -size * 0.3, size * 0.9), Vector3(0.09 * side, -0.02, 0.0), 0.008, black, Vector3.ONE, _steer_node)
	var plate := _box(at + Vector3(0.0, -size * 0.55, size * 0.95), Vector3(gap * 2.0, 0.012, size * 0.9), black, _steer_node)
	plate.name = "LampBracket"
	if _build and is_fitted("fairing") and str(_build.parts.get("fairing", "none")) != "none":
		return
	# A small tinted fly-screen over the pair, raked back.
	var glass := _mat(Color(0.18, 0.2, 0.24), 0.2, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.6
	var dir := Vector3(0.0, cos(0.55), sin(0.55))
	var base := at + Vector3(0.0, size * 1.0, -size * 0.2)
	var secs := []
	for k in 4:
		var f := k / 3.0
		secs.append({"c": base + dir * 0.1 * f, "w": gap * 1.9 * lerpf(1.0, 0.7, f), "up": 0.03, "down": 0.0, "n": 2.0})
	_shell(secs, glass, true, 0.25, PI - 0.25, _steer_node).name = "FlyScreen"


## The horn under the headstock: a disc, a pair of snail or air trumpets, a klaxon or a bulb.
func _draw_horn() -> void:
	_current_slot = "horn"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.8, 0.25)
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	var at := _head_bottom + Vector3(0.0, -0.1, 0.07)
	match str(p.get("style", "disc")):
		"snail":
			for x in [-0.045, 0.045]:
				var shell := _mesh_instance(_sphere(0.035), mat, at + Vector3(x, 0.0, 0.0))
				shell.scale = Vector3(0.6, 1.0, 1.0)
				var bell := _mesh_instance(_cylinder(0.012, 0.04, 0.025), mat, at + Vector3(x, 0.0, -0.04))
				bell.rotation.x = -PI * 0.5
		"air":
			var n := int(p.get("tones", [1, 1]).size())
			for i in n:
				var x := (i - (n - 1) * 0.5) * 0.04
				var length := 0.12 + 0.03 * i
				var horn := _mesh_instance(_cylinder(0.009, length, 0.03), mat, at + Vector3(x, 0.0, -length * 0.3))
				horn.rotation.x = -PI * 0.5
			_box(at + Vector3(0.0, -0.03, 0.04), Vector3(0.07, 0.05, 0.06), dark)
		"klaxon":
			var tube := _mesh_instance(_cylinder(0.018, 0.12, 0.05), mat, at + Vector3(0.0, 0.0, -0.04))
			tube.rotation.x = -PI * 0.5
			_mesh_instance(_sphere(0.04), mat, at + Vector3(0.0, 0.0, 0.05))
		"bulb":
			var tube := _mesh_instance(_cylinder(0.01, 0.1, 0.03), _mat(Color(0.78, 0.6, 0.25), 0.9, 0.2), at + Vector3(0.0, 0.0, -0.03))
			tube.rotation.x = -PI * 0.5
			_mesh_instance(_sphere(0.035), mat, at + Vector3(0.0, 0.0, 0.05))
		"melody":
			for i in 5:
				var horn := _mesh_instance(_cylinder(0.007, 0.08 + 0.02 * i, 0.022), mat, at + Vector3((i - 2) * 0.026, 0.0, -0.03))
				horn.rotation.x = -PI * 0.5
		_:
			var disc := _mesh_instance(_cylinder(0.04, 0.03), mat, at)
			disc.rotation.x = PI * 0.5
			var grille := _mesh_instance(_cylinder(0.03, 0.006), dark, at + Vector3(0.0, 0.0, -0.017))
			grille.rotation.x = PI * 0.5


## The ECU: a small box tucked under the side panel, below the front of the seat.
func _draw_ecu() -> void:
	_current_slot = "ecu"
	var p := _part()
	if p.is_empty():
		return
	var at := Vector3(0.12, _seat_y - 0.17, lerpf(_seat_front.z, _tail.z, 0.3))
	_box(at, Vector3(0.035, 0.08, 0.13), _mat(_col(), 0.5, 0.35))
	_box(at + Vector3(0.019, 0.0, 0.0), Vector3(0.004, 0.05, 0.09), _mat(Color(0.75, 0.76, 0.78), 0.9, 0.3))
	_tube(at + Vector3(0.0, 0.04, -0.06), at + Vector3(-0.08, 0.1, -0.16), 0.006, _mat(Color(0.05, 0.05, 0.05), 0.0, 0.7))


## Panniers either side of the back wheel, hung off a rack: canvas throw-overs, roll-top dry
## bags, leather saddlebags, rounded plastic cases or riveted aluminium boxes.
func _draw_panniers(build: BikeBuild, zr: float) -> void:
	_current_slot = "panniers"
	var p := _part()
	if p.is_empty():
		return
	var mat := _skin(_mat(_col(), 0.9 if p.get("style", "") == "alloy" else 0.0, 0.35 if p.get("style", "") in ["alloy", "hard"] else 0.8))
	var rack := _mat(Color(0.1, 0.1, 0.11), 0.6, 0.4)
	var litres := float(p.get("litres", 40.0))
	var k := pow(litres / 60.0, 0.33)
	var top := _seat_y - 0.04
	var w := build.rear_tyre_width * 0.5 + 0.12
	for side in [-1.0, 1.0]:
		var depth := 0.15 * k
		var c := Vector3(side * (w + depth * 0.5), top - 0.17 * k, zr - 0.08)
		match str(_look().get("shape", p.get("style", "hard"))):
			"saddlebag":
				# Cruiser saddlebags: tall leather boxes with a rounded bottom and a domed lid.
				var body := _shell([{"c": c + Vector3(0.0, 0.0, -0.2 * k), "w": depth * 0.5, "up": 0.15 * k, "down": 0.15 * k, "n": 3.0},
					{"c": c + Vector3(0.0, 0.0, 0.0), "w": depth * 0.5, "up": 0.16 * k, "down": 0.17 * k, "n": 3.0},
					{"c": c + Vector3(0.0, 0.02, 0.2 * k), "w": depth * 0.5, "up": 0.15 * k, "down": 0.1 * k, "n": 3.0}], mat)
				body.name = "Saddlebag"
				_box(c + Vector3(side * 0.005, 0.15 * k, 0.0), Vector3(depth + 0.02, 0.03, 0.42 * k), _mat(_col().darkened(0.25), 0.0, 0.7))
				for z in [-0.1, 0.1]:
					_box(c + Vector3(side * (depth * 0.5 + 0.008), 0.05 * k, z * k), Vector3(0.006, 0.14 * k, 0.025), _mat(_accent(Color(0.8, 0.7, 0.4)), 0.9, 0.3))
			"hard_top", "hard":
				# Touring hard cases with a rounded top and a lid seam.
				var body := _shell([{"c": c + Vector3(0.0, 0.0, -0.22 * k), "w": depth * 0.5, "up": 0.15 * k, "down": 0.17 * k, "n": 4.0},
					{"c": c, "w": depth * 0.5, "up": 0.18 * k, "down": 0.17 * k, "n": 4.0},
					{"c": c + Vector3(0.0, 0.0, 0.22 * k), "w": depth * 0.5, "up": 0.15 * k, "down": 0.17 * k, "n": 4.0}], mat)
				body.name = "Case"
				_box(c + Vector3(side * (depth * 0.5 + 0.002), 0.06 * k, 0.0), Vector3(0.006, 0.012, 0.42 * k), _mat(_accent(Color(0.1, 0.1, 0.11)), 0.5, 0.4))
			"roll":
				_roll_pannier(c, depth, k, mat, side, Vector3(side * w, top, c.z))
			"soft":
				_throw_over(c, depth, k, mat, side, Vector3(side * w, top, c.z))
			"alloy":
				_alu_case(c, Vector3(depth, 0.34 * k, 0.46 * k), mat, Vector3(side, 0.0, 0.0))
			"leather":
				_box(c, Vector3(depth, 0.3 * k, 0.4 * k), mat)
				var flap := _box(c + Vector3(side * 0.01, 0.1 * k, 0.0), Vector3(depth + 0.02, 0.12 * k, 0.42 * k), mat)
				flap.rotation.z = -side * 0.05
				for z in [-0.1, 0.1]:
					_box(c + Vector3(side * (depth * 0.5 + 0.012), 0.04 * k, z * k), Vector3(0.006, 0.12 * k, 0.02),
						_mat(Color(0.8, 0.7, 0.4), 0.9, 0.3))
			_:
				_box(c, Vector3(depth, 0.34 * k, 0.46 * k), mat)
				_box(c + Vector3(0.0, 0.17 * k + 0.012, 0.0), Vector3(depth + 0.01, 0.025, 0.47 * k), _mat(_col().darkened(0.3), 0.5, 0.4))
				_box(c + Vector3(side * (depth * 0.5 + 0.004), 0.08 * k, 0.0), Vector3(0.006, 0.02, 0.1), rack)
		_tube(Vector3(side * w, top, _pivot.z + 0.1), Vector3(side * w, top, zr + 0.16), 0.008, rack)
		_tube(Vector3(side * w, top, zr + 0.16), Vector3(side * w, top - 0.3 * k, zr + 0.12), 0.008, rack)


## A top box on a rack behind the seat, on a mounting plate: a rounded plastic case (a 30 L, or
## a 45 L with a pillion backrest), a riveted alloy case, a wooden crate, a leather trunk, or a
## waterproof roll bag strapped across the rack.
func _draw_top_box() -> void:
	_current_slot = "top_box"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "small"))
	var mat := _skin(_mat(_col(), 0.9 if style == "alloy" else 0.0, 0.35 if style in ["alloy", "small", "large"] else 0.85))
	var rack := _mat(Color(0.75, 0.76, 0.78) if style == "trunk" else Color(0.1, 0.1, 0.11), 0.8, 0.3)
	var k := pow(float(p.get("litres", 35.0)) / 35.0, 0.33)
	var size := Vector3(0.36, 0.26, 0.34) * k
	if style == "roll":
		size = Vector3(0.56, 0.24, 0.27) * k
	# The rack runs back off the subframe past the seat, so the box sits behind the pillion.
	var base := Vector3(0.0, _seat_y + 0.04, _tail.z + 0.03 + size.z * 0.5)
	_top_rack(base, size, rack)
	match style:
		"crate":
			_crate(base + Vector3(0.0, 0.012, 0.0), size, mat)
		"trunk":
			_trunk(base + Vector3(0.0, 0.012, 0.0), size, mat)
		"alloy":
			_alu_case(base + Vector3(0.0, 0.016 + size.y * 0.5, 0.0), size, mat, Vector3.BACK)
		"roll":
			_roll_bag(base, size, mat)
		_:
			_plastic_case(base + Vector3(0.0, 0.016, 0.0), size, mat, style == "large")


## The top box's rack: rails back from the subframe either side, stays down to it, a cross bar at
## the back and the mounting plate the box clicks onto (or a flat carrier for a soft bag).
func _top_rack(base: Vector3, size: Vector3, mat: Material) -> void:
	var back := base.z + size.z * 0.42
	for x in [-1.0, 1.0]:
		var rail := Vector3(0.1 * x, base.y - 0.012, 0.0)
		_bend([_tail + Vector3(0.08 * x, -0.02, -0.12), _tail + Vector3(0.1 * x, rail.y - _tail.y, 0.02),
			Vector3(rail.x, rail.y, back)], 0.009, mat)
		_tube(Vector3(rail.x, rail.y, base.z - size.z * 0.1), _tail + Vector3(0.085 * x, -0.13, 0.04), 0.008, mat)
	_bend([Vector3(-0.1, base.y - 0.012, back), Vector3(0.0, base.y - 0.012, back + 0.025), Vector3(0.1, base.y - 0.012, back)], 0.009, mat)
	_tube(Vector3(-0.1, base.y - 0.012, base.z - size.z * 0.3), Vector3(0.1, base.y - 0.012, base.z - size.z * 0.3), 0.008, mat)
	var plate := _mat(Color(0.05, 0.05, 0.055), 0.1, 0.6)
	_box(base, Vector3(0.24, 0.014, minf(size.z * 0.86, 0.32)), plate)
	_box(base + Vector3(0.0, -0.004, 0.0), Vector3(0.05, 0.018, minf(size.z * 0.7, 0.26)), plate)


## A plastic top case: a tub and a domed lid with a seam between them, hinged at the front and
## latched with a key lock at the back, a red reflector across the back and (`backrest`) a pad
## on the front for the pillion. `at` is the middle of its base.
func _plastic_case(at: Vector3, size: Vector3, lid_mat: Material, backrest: bool) -> void:
	var w := size.x * 0.5
	var d := size.z * 0.5
	var h := size.y
	var tub_mat := _mat(Color(0.05, 0.05, 0.055), 0.0, 0.55)
	var dark := _mat(Color(0.02, 0.02, 0.022), 0.0, 0.8)
	var seam := 0.5 * h
	var tub := []
	for s in [[0.0, 0.86, 0.84], [0.04, 0.95, 0.94], [0.12, 1.0, 1.0], [0.5, 1.0, 1.0]]:
		tub.append({"c": at + Vector3(0.0, s[0] * h, 0.0), "w": w * s[1], "up": d * s[2], "down": d * s[2] * 1.03, "n": 3.6})
	_shell(tub, tub_mat).name = "Tub"
	var lid := []
	for s in [[0.52, 1.015, 1.015], [0.62, 1.01, 1.0], [0.78, 0.97, 0.95], [0.9, 0.88, 0.84], [0.97, 0.72, 0.66], [1.0, 0.5, 0.42]]:
		lid.append({"c": at + Vector3(0.0, s[0] * h, 0.0), "w": w * s[1], "up": d * s[2], "down": d * s[2] * 1.03, "n": 3.2})
	_shell(lid, lid_mat).name = "Lid"
	_shell([{"c": at + Vector3(0.0, seam, 0.0), "w": w * 1.006, "up": d * 1.006, "down": d * 1.036, "n": 3.6},
		{"c": at + Vector3(0.0, seam + 0.02 * h, 0.0), "w": w * 1.006, "up": d * 1.006, "down": d * 1.036, "n": 3.6}], dark).name = "Seam"
	var bz := d * 1.03
	# A wide red reflector across the back of the tub, and the lock and latch over the seam.
	_box(at + Vector3(0.0, seam - 0.09 * h, bz + 0.002), Vector3(w * 1.3, 0.035 * h / 0.26, 0.008), _lamp(Color(0.9, 0.1, 0.05), 0.6, "ign"))
	_box(at + Vector3(0.0, seam + 0.01 * h, bz + 0.006), Vector3(0.08, 0.045, 0.014), _mat(Color(0.12, 0.12, 0.13), 0.3, 0.5))
	var lock := _mesh_instance(_cylinder(0.009, 0.01, -1.0, 12), _mat(Color(0.82, 0.83, 0.85), 1.0, 0.2), at + Vector3(0.0, seam + 0.012 * h, bz + 0.014))
	lock.rotation.x = PI * 0.5
	for x in [-1.0, 1.0]:
		var hinge := _mesh_instance(_cylinder(0.008, 0.05, -1.0, 10), dark, at + Vector3(x * w * 0.5, seam + 0.01 * h, -d - 0.004))
		hinge.rotation.z = PI * 0.5
	if backrest:
		var pad := _shell([{"c": at + Vector3(0.0, 0.46 * h, -d - 0.012), "w": 0.12, "up": 0.0, "down": 0.03, "n": 3.0},
			{"c": at + Vector3(0.0, 0.62 * h, -d - 0.016), "w": 0.125, "up": 0.0, "down": 0.034, "n": 3.0},
			{"c": at + Vector3(0.0, 0.78 * h, -d - 0.008), "w": 0.11, "up": 0.0, "down": 0.03, "n": 3.0}],
			_tex(_mat(Color(0.07, 0.07, 0.07), 0.0, 0.8), "grain"))
		pad.name = "Backrest"


## An aluminium adventure case centred on `c`: flat riveted panels with rolled edges, a pressed
## rib round the middle, black corner protectors, a lid on top with a seal under it, a carry
## handle, and two latches with a reflector on the face pointing along `face` (the back of a
## top case, the outside of a pannier).
func _alu_case(c: Vector3, size: Vector3, mat: Material, face: Vector3) -> void:
	var h := size.y
	var body_h := h * 0.66
	var lid_h := h - body_h - 0.01
	var bottom := c.y - h * 0.5
	var corner := _mat(Color(0.03, 0.03, 0.035), 0.0, 0.6)
	var steel := _mat(Color(0.8, 0.81, 0.83), 1.0, 0.25)
	_box(Vector3(c.x, bottom + body_h * 0.5, c.z), Vector3(size.x, body_h, size.z), mat).name = "Body"
	_box(Vector3(c.x, bottom + body_h + 0.005, c.z), Vector3(size.x - 0.006, 0.012, size.z - 0.006), corner)
	var lid_y := bottom + body_h + 0.01 + lid_h * 0.5
	_box(Vector3(c.x, lid_y, c.z), Vector3(size.x + 0.008, lid_h, size.z + 0.008), mat).name = "Lid"
	var hx := size.x * 0.5 + 0.002
	var hz := size.z * 0.5 + 0.002
	# Rolled edges up every corner and round the lid and the base.
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var e := Vector3(c.x + x * hx, 0.0, c.z + z * hz)
			_tube(e + Vector3(0.0, bottom + 0.02, 0.0), e + Vector3(0.0, bottom + body_h - 0.01, 0.0), 0.007, mat)
			_tube(e + Vector3(0.0, lid_y - lid_h * 0.5 + 0.01, 0.0), e + Vector3(0.0, lid_y + lid_h * 0.5 - 0.01, 0.0), 0.007, mat)
	for y in [bottom + 0.004, lid_y + lid_h * 0.5 + 0.002, bottom + body_h - 0.004]:
		for z in [-1.0, 1.0]:
			_tube(Vector3(c.x - hx, y, c.z + z * hz), Vector3(c.x + hx, y, c.z + z * hz), 0.006, mat)
		for x in [-1.0, 1.0]:
			_tube(Vector3(c.x + x * hx, y, c.z - hz), Vector3(c.x + x * hx, y, c.z + hz), 0.006, mat)
	# A pressed rib round the body, a hand's width up.
	_box(Vector3(c.x, bottom + body_h * 0.45, c.z), Vector3(size.x + 0.006, 0.018, size.z + 0.006), mat)
	# Black plastic corners top and bottom.
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			for y in [bottom + 0.022, lid_y + lid_h * 0.5 - 0.018]:
				_box(Vector3(c.x + x * (hx - 0.012), y, c.z + z * (hz - 0.012)), Vector3(0.05, 0.048, 0.05), corner)
	# Rivets along the base and under the lid on the faces.
	var rivet := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.2)
	for f in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var span := size.z if absf(f.x) > 0.5 else size.x
		var along := Vector3.BACK if absf(f.x) > 0.5 else Vector3.RIGHT
		var out := Vector3(f.x * hx, 0.0, f.z * hz)
		var n := maxi(3, roundi(span / 0.07))
		for i in n:
			var t := (i + 0.5) / n - 0.5
			for y in [bottom + 0.035, bottom + body_h - 0.02]:
				var r := _mesh_instance(_cylinder(0.004, 0.004, -1.0, 6), rivet, Vector3(c.x, y, c.z) + out + along * t * (span - 0.08) + f * 0.002)
				r.basis = _basis_up(f)
	# Latches over the seam and a reflector, on the face that opens.
	var fo := Vector3(face.x * hx, 0.0, face.z * hz)
	var side := Vector3(face.z, 0.0, face.x).abs()
	var fspan := size.z if absf(face.x) > 0.5 else size.x
	for s in [-1.0, 1.0]:
		var at: Vector3 = Vector3(c.x, bottom + body_h + 0.004, c.z) + fo + side * s * fspan * 0.3
		var latch := _box(at + face * 0.007, Vector3(0.04, 0.07, 0.04) * (side + Vector3.UP) + face.abs() * 0.012, _mat(Color(0.1, 0.1, 0.11), 0.4, 0.4))
		latch.name = "Latch"
		_box(at + face * 0.016 + Vector3(0.0, -0.012, 0.0), Vector3(0.025, 0.04, 0.025) * (side + Vector3.UP) + face.abs() * 0.006, steel)
	_box(Vector3(c.x, bottom + body_h * 0.72, c.z) + fo + face * 0.003, side * fspan * 0.4 + Vector3(0.0, 0.022, 0.0) + face.abs() * 0.005,
		_lamp(Color(0.9, 0.1, 0.05), 0.4, "ign"))
	# A folding carry handle on the lid.
	var top := lid_y + lid_h * 0.5
	var hs := Vector3(face.x, 0.0, face.z).abs()
	var hl := (Vector3(1.0, 0.0, 1.0) - hs) * minf(size.x, size.z) * 0.22 + hs * 0.0
	_bend([Vector3(c.x, top, c.z) - hl, Vector3(c.x, top + 0.022, c.z) - hl * 0.8, Vector3(c.x, top + 0.022, c.z) + hl * 0.8,
		Vector3(c.x, top, c.z) + hl], 0.008, corner)


## A wooden crate on the rack, `at` the middle of its base: corner posts, slatted sides with gaps
## between the boards, a solid floor and an open top.
func _crate(at: Vector3, size: Vector3, mat: Material) -> void:
	var dark := _mat(_col().darkened(0.25), 0.0, 0.9)
	var w := size.x * 0.5
	var d := size.z * 0.5
	_box(at + Vector3(0.0, 0.008, 0.0), Vector3(size.x, 0.016, size.z), dark)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(at + Vector3(x * (w - 0.012), size.y * 0.5, z * (d - 0.012)), Vector3(0.026, size.y, 0.026), dark)
	var slats := 3
	var gap := 0.022
	var sh := (size.y - gap * (slats - 1)) / slats
	for i in slats:
		var y := (i + 0.5) * (sh + gap) - gap * 0.5
		for z in [-1.0, 1.0]:
			_box(at + Vector3(0.0, y, z * (d - 0.006)), Vector3(size.x - 0.05, sh, 0.012), mat)
		for x in [-1.0, 1.0]:
			_box(at + Vector3(x * (w - 0.006), y, 0.0), Vector3(0.012, sh, size.z - 0.05), mat)
	# A stencilled band of darker wood across the back, like an old fruit crate.
	_box(at + Vector3(0.0, (sh + gap) * 1.0 + sh * 0.5, d + 0.0005), Vector3(size.x * 0.4, sh * 0.5, 0.002), _mat(_col().darkened(0.5), 0.0, 0.9))


## A leather trunk, `at` the middle of its base: a rounded body and a domed lid with a welt round
## the seam, two straps over the lid with buckles at the back, a lock plate and a carry handle.
func _trunk(at: Vector3, size: Vector3, mat: Material) -> void:
	var w := size.x * 0.5
	var d := size.z * 0.5
	var h := size.y
	var welt := _mat(_col().darkened(0.35), 0.0, 0.8)
	var brass := _mat(_accent(Color(0.8, 0.66, 0.3)), 0.9, 0.3)
	var body := []
	for s in [[0.0, 0.95], [0.03, 1.0], [0.66, 1.0]]:
		body.append({"c": at + Vector3(0.0, s[0] * h, 0.0), "w": w * s[1], "up": d * s[1], "down": d * s[1], "n": 6.0})
	_shell(body, mat).name = "Trunk"
	var lid := []
	for s in [[0.68, 1.01], [0.88, 1.0], [0.97, 0.93], [1.0, 0.8]]:
		lid.append({"c": at + Vector3(0.0, s[0] * h, 0.0), "w": w * s[1], "up": d * s[1], "down": d * s[1], "n": 6.0})
	_shell(lid, mat).name = "Lid"
	_shell([{"c": at + Vector3(0.0, 0.655 * h, 0.0), "w": w * 1.02, "up": d * 1.02, "down": d * 1.02, "n": 6.0},
		{"c": at + Vector3(0.0, 0.69 * h, 0.0), "w": w * 1.02, "up": d * 1.02, "down": d * 1.02, "n": 6.0}], welt)
	var strap := _mat(_col().darkened(0.45), 0.0, 0.75)
	for x in [-1.0, 1.0]:
		var sx: float = x * w * 0.55
		_box(at + Vector3(sx, h + 0.003, 0.0), Vector3(0.04, 0.006, size.z * 0.86), strap)
		for z in [-1.0, 1.0]:
			_box(at + Vector3(sx, h * 0.72, z * (d + 0.003)), Vector3(0.04, h * 0.56, 0.006), strap)
		_box(at + Vector3(sx, h * 0.58, d + 0.008), Vector3(0.05, 0.04, 0.006), brass)
	_box(at + Vector3(0.0, 0.66 * h, d + 0.008), Vector3(0.05, 0.06, 0.006), brass)
	_bend([at + Vector3(-0.06, h, 0.0), at + Vector3(-0.045, h + 0.03, 0.0), at + Vector3(0.045, h + 0.03, 0.0), at + Vector3(0.06, h, 0.0)], 0.009, strap)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(at + Vector3(x * (w - 0.01), 0.02, z * (d - 0.01)), Vector3(0.035, 0.04, 0.035), brass)


## A waterproof roll bag lying across the rack: a fabric cylinder with each end rolled down
## three times and clipped, compression straps round it with buckles on top, a carry handle, a
## reflective patch on the back and two cargo straps down to the rack rails.
func _roll_bag(base: Vector3, size: Vector3, mat: Material) -> void:
	var r := size.y * 0.5
	var half := size.x * 0.5 - 0.06
	var c := base + Vector3(0.0, r * 0.92 + 0.008, 0.0)
	var web := _mat(Color(0.06, 0.06, 0.065), 0.0, 0.9)
	var clip := _mat(Color(0.02, 0.02, 0.02), 0.0, 0.4)
	# The bag is lofted along its own Z and turned to lie across the bike: a fat oval middle that
	# pinches at each end into the flat strip of fabric the closure is rolled from.
	var dz := size.z * 0.5
	var secs := []
	for s in [[-1.0, 0.03, 0.72], [-0.92, 0.4, 0.86], [-0.8, 0.9, 0.97], [-0.6, 1.0, 1.0], [0.0, 1.03, 1.02], [0.6, 1.0, 1.0],
			[0.8, 0.9, 0.97], [0.92, 0.4, 0.86], [1.0, 0.03, 0.72]]:
		secs.append({"c": Vector3(0.0, 0.0, s[0] * (half + 0.05)), "w": dz * s[1], "up": r * s[2], "down": r * s[2], "n": 2.3})
	var body := _mesh_instance(ShapeKit.loft(secs), mat, c)
	body.basis = Basis(Vector3.UP, PI * 0.5)
	body.name = "RollBag"
	for x in [-1.0, 1.0]:
		# Each end's flat strip rolled down three times into a tube across the end, clipped top and bottom.
		var roll := _mesh_instance(_cylinder(0.026, r * 1.5, -1.0, 16), mat, c + Vector3(x * (half + 0.072), 0.0, 0.0))
		roll.name = "RolledEnd"
		_mesh_instance(_cylinder(0.02, r * 1.5 + 0.01, -1.0, 12), _mat(_col().darkened(0.3), 0.0, 0.6), c + Vector3(x * (half + 0.08), 0.0, 0.0))
		for y in [-1.0, 1.0]:
			_box(c + Vector3(x * (half + 0.075), y * (r * 0.75 + 0.012), 0.0), Vector3(0.034, 0.022, 0.034), clip)
		# A strap from the rolled end back over the top to a buckle, holding it down.
		_box(c + Vector3(x * (half - 0.02), r * 0.98, 0.0), Vector3(0.16, 0.006, 0.025), web)
		_box(c + Vector3(x * (half - 0.07), r + 0.006, 0.0), Vector3(0.035, 0.012, 0.03), clip)
	# Compression straps round the middle, each with a side-release buckle on top.
	for x in [-1.0, 1.0]:
		var bx: float = x * half * 0.5
		var band := _mesh_instance(_cylinder(r + 0.004, 0.028, -1.0, 28), web, c + Vector3(bx, 0.0, 0.0))
		band.rotation.z = PI * 0.5
		band.scale = Vector3(1.0, 1.0, (size.z * 0.5 + 0.004) / (r + 0.004))
		_box(c + Vector3(bx, r + 0.008, 0.0), Vector3(0.034, 0.014, 0.05), clip)
		# Cargo straps down to the rack rails, front and back, hooked on.
		for z in [-1.0, 1.0]:
			var top := c + Vector3(bx, r * 0.55, z * size.z * 0.42)
			var foot := Vector3(0.1 * signf(bx), base.y - 0.012, c.z + z * (size.z * 0.5 + 0.015))
			_strip(top, foot, 0.022, 0.004, _mat(Color(0.75, 0.32, 0.08), 0.0, 0.8))
			_box(foot + Vector3(0.0, 0.008, 0.0), Vector3(0.012, 0.025, 0.02), _mat(Color(0.7, 0.71, 0.73), 0.9, 0.3))
	_bend([c + Vector3(-0.06, r * 0.98, 0.0), c + Vector3(-0.04, r + 0.03, 0.0), c + Vector3(0.04, r + 0.03, 0.0),
		c + Vector3(0.06, r * 0.98, 0.0)], 0.008, web)
	_box(c + Vector3(0.0, 0.0, size.z * 0.5 + 0.002), Vector3(half * 0.6, r * 0.35, 0.004), _mat(Color(0.82, 0.83, 0.85), 0.6, 0.25))


## A flat strap or band from `a` to `b`, `width` wide and `thick` thick, lying as flat as it can.
func _strip(a: Vector3, b: Vector3, width: float, thick: float, mat: Material) -> MeshInstance3D:
	var along := b - a
	var mi := _box((a + b) * 0.5, Vector3(width, thick, along.length()), mat)
	var z := along.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.basis = Basis(x, z.cross(x), z)
	return mi


## A roll-top soft pannier centred on `c`, on the `side` of the bike: a rounded fabric bag whose
## top is rolled down into a tube and clipped to two straps down its outside, a compression strap
## round it, a reflective patch and straps up to the rack rail (`rail`).
func _roll_pannier(c: Vector3, depth: float, k: float, mat: Material, side: float, rail: Vector3) -> void:
	var hb := 0.3 * k
	var half_l := 0.21 * k
	var y0 := c.y - hb * 0.5
	var web := _mat(Color(0.06, 0.06, 0.065), 0.0, 0.9)
	var clip := _mat(Color(0.02, 0.02, 0.02), 0.0, 0.4)
	var secs := []
	for s in [[0.0, 0.75, 0.85], [0.06, 0.96, 0.97], [0.5, 1.0, 1.0], [0.86, 0.9, 0.97], [1.0, 0.45, 0.95]]:
		secs.append({"c": Vector3(c.x, y0 + s[0] * hb, c.z), "w": depth * 0.5 * s[1], "up": half_l * s[2], "down": half_l * s[2], "n": 2.8})
	_shell(secs, mat).name = "RollBag"
	# The top rolled down three turns into a tube along the bag, folded over to the outside.
	var roll_at := Vector3(c.x + side * depth * 0.12, y0 + hb + 0.022, c.z)
	var roll := _mesh_instance(_cylinder(0.03, half_l * 1.9, -1.0, 16), mat, roll_at)
	roll.rotation.x = PI * 0.5
	roll.name = "RolledTop"
	var outer := c.x + side * (depth * 0.5 + 0.004)
	for z in [-1.0, 1.0]:
		var sz: float = c.z + z * half_l * 0.6
		_box(Vector3(c.x + side * depth * 0.32, roll_at.y + 0.028, sz), Vector3(depth * 0.4, 0.006, 0.024), web)
		_box(Vector3(outer, y0 + hb * 0.62, sz), Vector3(0.006, hb * 0.62, 0.024), web)
		_box(Vector3(outer + side * 0.006, y0 + hb * 0.42, sz), Vector3(0.014, 0.04, 0.034), clip)
		# Up to the rack rail and round it.
		_strip(Vector3(c.x - side * depth * 0.3, y0 + hb * 0.92, sz), rail + Vector3(0.0, 0.0, z * 0.08), 0.022, 0.004, web)
	_shell([{"c": Vector3(c.x, y0 + hb * 0.25, c.z), "w": depth * 0.5 + 0.004, "up": half_l + 0.004, "down": half_l + 0.004, "n": 2.8},
		{"c": Vector3(c.x, y0 + hb * 0.25 + 0.026, c.z), "w": depth * 0.5 + 0.004, "up": half_l + 0.004, "down": half_l + 0.004, "n": 2.8}], web)
	_box(Vector3(outer + side * 0.006, y0 + hb * 0.25 + 0.013, c.z), Vector3(0.014, 0.034, 0.04), clip)
	_box(Vector3(outer, y0 + hb * 0.72, c.z), Vector3(0.004, hb * 0.16, half_l * 0.5), _mat(Color(0.82, 0.83, 0.85), 0.6, 0.25))


## A canvas throw-over pannier centred on `c`, on the `side`: a soft rounded bag with a flap
## buckled down over its top, slung from a yoke over the rack (`rail`) to the middle.
func _throw_over(c: Vector3, depth: float, k: float, mat: Material, side: float, rail: Vector3) -> void:
	var hb := 0.3 * k
	var half_l := 0.2 * k
	var y0 := c.y - hb * 0.5
	var secs := []
	for s in [[0.0, 0.7, 0.8], [0.08, 0.95, 0.96], [0.55, 1.0, 1.0], [1.0, 0.85, 0.97]]:
		secs.append({"c": Vector3(c.x, y0 + s[0] * hb, c.z), "w": depth * 0.5 * s[1], "up": half_l * s[2], "down": half_l * s[2], "n": 3.0})
	_shell(secs, mat).name = "Bag"
	var flap_mat := _mat(_col().darkened(0.2), 0.0, 0.9)
	_box(Vector3(c.x, y0 + hb + 0.004, c.z), Vector3(depth * 0.9, 0.008, half_l * 2.0), flap_mat)
	var outer := c.x + side * (depth * 0.5 + 0.004)
	_box(Vector3(outer, y0 + hb * 0.8, c.z), Vector3(0.008, hb * 0.4, half_l * 2.0), flap_mat)
	var leather := _mat(Color(0.25, 0.13, 0.06), 0.0, 0.7)
	for z in [-1.0, 1.0]:
		_box(Vector3(outer + side * 0.005, y0 + hb * 0.62, c.z + z * half_l * 0.55), Vector3(0.006, hb * 0.34, 0.022), leather)
		_box(Vector3(outer + side * 0.009, y0 + hb * 0.5, c.z + z * half_l * 0.55), Vector3(0.006, 0.026, 0.03), _mat(Color(0.8, 0.7, 0.4), 0.9, 0.3))
	# The yoke: a canvas band from the bag's inside edge up over the rack to the middle.
	_strip(Vector3(c.x - side * depth * 0.4, y0 + hb, c.z), Vector3(0.0, rail.y + 0.012, c.z), half_l * 1.4, 0.006, flap_mat)


## Fog or spot lamps on the fork legs, or an LED bar across the fork.
func _draw_fog_lights() -> void:
	_current_slot = "fog_lights"
	var p := _part()
	if p.is_empty():
		return
	var shell := _skin(_mat(_col(), 0.8, 0.25))
	var b: Array = p.get("beam", [1.0, 0.9, 0.8])
	var lens := _lamp(Color(b[0], b[1], b[2]), 2.0, "fog")
	var style := str(p.get("style", "round"))
	if style == "bar":
		var mid := -_steer_axis * 0.2 + Vector3(0.0, 0.0, -0.1)
		_box(mid, Vector3(0.34, 0.045, 0.05), shell, _steer_node)
		_box(mid + Vector3(0.0, 0.0, -0.026), Vector3(0.31, 0.03, 0.004), lens, _steer_node)
		return
	for x in [-1.0, 1.0]:
		var at := -_steer_axis * 0.34 + Vector3(0.15 * x, 0.0, -0.06)
		match style:
			"cube":
				_box(at, Vector3(0.06, 0.06, 0.06), shell, _steer_node)
				_box(at + Vector3(0.0, 0.0, -0.031), Vector3(0.048, 0.048, 0.004), lens, _steer_node)
			"rally":
				var can := _mesh_instance(_cylinder(0.06, 0.06), shell, at, _steer_node)
				can.rotation.x = PI * 0.5
				var face := _mesh_instance(_cylinder(0.055, 0.006), lens, at + Vector3(0.0, 0.0, -0.032), _steer_node)
				face.rotation.x = PI * 0.5
				for i in 3:
					_box(at + Vector3(0.0, (i - 1) * 0.03, -0.04), Vector3(0.11, 0.006, 0.006), shell, _steer_node)
			_:
				var can := _mesh_instance(_sphere(0.04), shell, at, _steer_node)
				can.scale = Vector3(1.0, 1.0, 0.8)
				var face := _mesh_instance(_cylinder(0.035, 0.006), lens, at + Vector3(0.0, 0.0, -0.03), _steer_node)
				face.rotation.x = PI * 0.5


## Where the fog lamps sit, in the bike's own space (straight ahead), or [] with none fitted.
func fog_positions() -> Array:
	var p := PartsDB.get_part(str(_build.parts.get("fog_lights", "none"))) if _build else {}
	if p.is_empty():
		return []
	if str(p.get("style", "")) == "bar":
		return [_head - _steer_axis * 0.2 + Vector3(0.0, 0.0, -0.13)]
	return [_head - _steer_axis * 0.34 + Vector3(-0.15, 0.0, -0.09), _head - _steer_axis * 0.34 + Vector3(0.15, 0.0, -0.09)]


## The tail unit behind the seat: the rear light, the mudguard (or hugger) and the number plate,
## as a long classic guard, a café hump, a scrambler loop, a sports tail tidy, a bobbed fender
## or a high enduro fender. The lamp sits where the part says (see tail_light_position).
func _draw_tail(build: BikeBuild) -> void:
	_current_slot = "tail"
	var p := _part()
	if p.is_empty():
		return
	var metal := str(p.get("material", "")) == "metal"
	var mat := _skin(_mat(_col(), 0.85 if metal else 0.1, 0.25 if metal else 0.45, 0.0 if metal else 0.4))
	var black := _mat(Color(0.04, 0.04, 0.045), 0.3, 0.6)
	var plate := _mat(Color(0.95, 0.82, 0.16), 0.0, 0.5)
	var lamp := tail_light_position()
	var axle := Vector3(0.0, 0.0, build.wheelbase * 0.5)
	var r := build.rear_radius
	var w := build.rear_tyre_width + 0.05
	var lk := _look()
	if lk.has("cowl") and not _fit_only:
		_tail_cowl(str(lk["cowl"]), mat, lk)
	if lk.get("struts", false):
		# Chrome struts from the axle up to the guard.
		var chrome := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1)
		for side in [-1.0, 1.0]:
			var x: float = (w * 0.5 + 0.015) * side
			_tube(axle + Vector3(x, 0.0, 0.0), axle + Vector3(x, r * 0.78, -0.12), 0.011, chrome)
			_tube(axle + Vector3(x, 0.0, 0.0), axle + Vector3(x, r * 0.6, 0.3), 0.009, chrome)
	match str(p.get("style", "classic")):
		"cafe":
			var cowl := _box(_tail + Vector3(0.0, 0.0, 0.14), Vector3(0.24, 0.12, 0.3), mat)
			cowl.rotation.x = -0.08
			var hump := _box(_tail + Vector3(0.0, 0.08, 0.1), Vector3(0.2, 0.07, 0.24), mat)
			hump.rotation.x = 0.22
			_rear_guard.append_array(_rear_arc(r + 0.03, w, -0.25, 0.75, black, 5))
			_tube(_tail + Vector3(0.0, -0.05, 0.24), _tail + Vector3(0.0, -0.15, 0.31), 0.008, black)
			_number_plate(_tail + Vector3(0.0, -0.2, 0.32), Vector2(0.18, 0.12), -0.2, plate)
		"loop":
			for side in [-1.0, 1.0]:
				_tube(_tail + Vector3(0.07 * side, 0.0, -0.08), _tail + Vector3(0.07 * side, 0.01, 0.2), 0.012, mat)
				_tube(_tail + Vector3(0.07 * side, 0.01, 0.2), _tail + Vector3(0.04 * side, 0.04, 0.25), 0.012, mat)
			_tube(_tail + Vector3(-0.04, 0.04, 0.25), _tail + Vector3(0.04, 0.04, 0.25), 0.012, mat)
			_rear_guard.append_array(_rear_arc(r + 0.04, w, -0.3, 0.8, mat, 5))
			_tube(_tail + Vector3(0.0, 0.01, 0.2), lamp, 0.008, black)
			_number_plate(lamp + Vector3(0.0, -0.09, 0.0), Vector2(0.16, 0.11), -0.1, plate)
		"tidy":
			var tray := _box(_tail + Vector3(0.0, -0.05, 0.1), Vector3(0.18, 0.025, 0.28), mat)
			tray.rotation.x = -0.15
			_rear_guard.append(tray)
			_lift_clear_of_tyre(tray)
			_box(lamp - Vector3(0.0, 0.0, 0.012), Vector3(0.16, 0.035, 0.02), mat)
			_tube(_tail + Vector3(0.0, -0.06, 0.2), _tail + Vector3(0.0, -0.15, 0.33), 0.01, black)
			_number_plate(_tail + Vector3(0.0, -0.2, 0.34), Vector2(0.17, 0.11), -0.35, plate)
		"bobber":
			_rear_guard.append_array(_rear_arc(r + 0.035, w, -0.55, 1.05, mat, 6))
			var plate_at := axle + Vector3(-(w * 0.5 + 0.06), 0.14, 0.04)
			_tube(axle + Vector3(-(w * 0.5 + 0.02), 0.04, 0.0), plate_at, 0.008, black)
			var side_plate := _number_plate(plate_at, Vector2(0.17, 0.12), 0.0, plate)
			side_plate.rotation.y = PI * 0.5
		"enduro":
			var a := _tail + Vector3(0.0, -0.05, -0.12)
			var b := _tail + Vector3(0.0, -0.02, 0.2)
			var c := _tail + Vector3(0.0, 0.06, 0.46)
			for plank in [_plank(a, b, w + 0.02, 0.012, mat), _plank(b, c, w, 0.012, mat)]:
				_rear_guard.append(plank)
				_lift_clear_of_tyre(plank)
			_number_plate(lamp + Vector3(0.0, -0.07, -0.01), Vector2(0.13, 0.08), -0.3, plate)
		_:
			_rear_guard.append_array(_rear_arc(r + 0.05, w + 0.02, -0.45, 2.0, mat, 10))
			# The lamp on a bracket off the guard, the plate below it.
			var a := atan2(lamp.z - axle.z, lamp.y - axle.y)
			_tube(lamp, _rear_guard_at(a, r + 0.05), 0.01, mat)
			var below := a + 0.4
			_number_plate(_rear_guard_at(below, r + 0.05) + Vector3(0.0, cos(below), sin(below)) * 0.03, Vector2(0.2, 0.13), -0.25, plate)
	_rear_guard = _rear_guard.filter(func(piece): return is_instance_valid(piece))
	_clear_plates(black)
	if _fit_only:
		return
	# The rear light: a dim tail light with the headlight on, bright as the stop lamp.
	var lens := _lamp(Color(1.0, 0.05, 0.02), TAIL_ENERGY, "tail")
	# Its red light shines back and down from the lamp, onto the road behind (not the rider).
	_stop_glow = SpotLight3D.new()
	_stop_glow.name = "StopGlow"
	_stop_glow.light_color = Color(1.0, 0.08, 0.04)
	_stop_glow.light_energy = STOP_GLOW
	_stop_glow.spot_range = STOP_GLOW_RANGE
	_stop_glow.spot_angle = 70.0
	_stop_glow.spot_attenuation = 1.2
	_stop_glow.shadow_enabled = false
	_stop_glow.light_volumetric_fog_energy = 0.0
	_stop_glow.position = lamp + Vector3(0.0, 0.0, 0.05)
	_stop_glow.basis = Basis.looking_at(Vector3(0.0, -0.6, 1.0).normalized(), Vector3.UP)
	_stop_glow.visible = false
	add_child(_stop_glow)
	var face: MeshInstance3D
	match str(lk.get("lamp", p.get("light", "round"))):
		"tombstone":
			var chrome := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1)
			_box(lamp, Vector3(0.1, 0.06, 0.05), chrome)
			var dome := _mesh_instance(_cylinder(0.05, 0.05), chrome, lamp + Vector3(0.0, 0.03, 0.0))
			dome.rotation.x = PI * 0.5
			face = _box(lamp + Vector3(0.0, 0.01, 0.027), Vector3(0.085, 0.07, 0.006), lens)
		"cateye":
			var body := _mesh_instance(_capsule(0.022, 0.13), _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1), lamp)
			body.rotation.z = PI * 0.5
			face = _mesh_instance(_capsule(0.018, 0.11), lens, lamp + Vector3(0.0, 0.0, 0.012))
			face.rotation.z = PI * 0.5
			face.scale = Vector3(1.0, 1.0, 0.5)
		"twin":
			for x in [-0.045, 0.045]:
				var can := _mesh_instance(_cylinder(0.026, 0.035), black, lamp + Vector3(x, 0.0, 0.0))
				can.rotation.x = PI * 0.5
				var f := _mesh_instance(_cylinder(0.023, 0.006), lens, lamp + Vector3(x, 0.0, 0.019))
				f.rotation.x = PI * 0.5
				if x > 0.0:
					face = f
		"halo":
			face = _mesh_instance(_torus(0.034, 0.006), lens, lamp)
			face.rotation.x = PI * 0.5
			_mesh_instance(_cylinder(0.03, 0.02), black, lamp - Vector3(0.0, 0.0, 0.01)).rotation.x = PI * 0.5
		"lucas":
			_box(lamp, Vector3(0.12, 0.07, 0.07), _mat(Color(0.85, 0.86, 0.88), 1.0, 0.15))
			face = _box(lamp + Vector3(0.0, 0.0, 0.037), Vector3(0.1, 0.05, 0.008), lens)
		"strip":
			face = _box(lamp, Vector3(0.14, 0.022, 0.01), lens)
		"bullet":
			var shell := _mesh_instance(_sphere(0.03), black, lamp)
			shell.scale = Vector3(1.0, 1.0, 1.5)
			face = _mesh_instance(_cylinder(0.025, 0.006), lens, lamp + Vector3(0.0, 0.0, 0.043))
			face.rotation.x = PI * 0.5
		"led":
			_box(lamp - Vector3(0.0, 0.0, 0.01), Vector3(0.07, 0.035, 0.03), black)
			face = _box(lamp + Vector3(0.0, 0.0, 0.006), Vector3(0.06, 0.025, 0.006), lens)
		_:
			var can := _mesh_instance(_cylinder(0.036, 0.04), black, lamp)
			can.rotation.x = PI * 0.5
			face = _mesh_instance(_cylinder(0.032, 0.006), lens, lamp + Vector3(0.0, 0.0, 0.022))
			face.rotation.x = PI * 0.5
	face.name = "TailLight"


## A lofted seat cowl or tail section from a look: "ducktail" (kicking up at the end), "hump"
## (a cafe racer hump), "solo" (a round solo cowl with a back stop), "tracker" (a flat-track
## tail with an oval number board on the end), "sport" (a sharp tail rising to a point) or
## "racing" (a race hump with a pointed tail). "length" stretches it.
func _tail_cowl(kind: String, mat: Material, lk: Dictionary) -> void:
	var t := _tail
	var ln := float(lk.get("length", 1.0))
	var keys := []   # [z, half-width, up, down, lift, squareness]
	match kind:
		"ducktail":
			keys = [[-0.14, 0.12, 0.03, 0.04, 0.0, 3.0], [0.04, 0.12, 0.05, 0.05, 0.01, 3.0], [0.2, 0.1, 0.05, 0.05, 0.05, 3.0], [0.32, 0.09, 0.03, 0.02, 0.11, 3.5]]
		"hump":
			keys = [[-0.12, 0.13, 0.03, 0.04, 0.0, 2.6], [-0.02, 0.13, 0.11, 0.05, 0.0, 2.6], [0.14, 0.12, 0.1, 0.05, 0.0, 2.6], [0.28, 0.1, 0.05, 0.05, 0.0, 3.0], [0.33, 0.07, 0.02, 0.03, 0.0, 3.0]]
		"solo":
			keys = [[-0.1, 0.12, 0.02, 0.04, 0.0, 2.2], [0.02, 0.13, 0.14, 0.05, 0.0, 2.2], [0.14, 0.12, 0.12, 0.05, 0.0, 2.2], [0.24, 0.09, 0.04, 0.04, 0.0, 2.2]]
		"tracker":
			keys = [[-0.14, 0.13, 0.03, 0.05, 0.0, 4.0], [0.1, 0.13, 0.03, 0.05, 0.0, 4.0], [0.3, 0.12, 0.03, 0.05, 0.0, 4.0]]
		"sport":
			keys = [[-0.16, 0.13, 0.05, 0.06, 0.0, 2.8], [0.04, 0.11, 0.05, 0.07, 0.04, 2.8], [0.22, 0.07, 0.04, 0.05, 0.1, 2.8], [0.36, 0.025, 0.015, 0.02, 0.15, 2.5]]
		"racing":
			keys = [[-0.14, 0.13, 0.03, 0.05, 0.0, 2.6], [0.0, 0.13, 0.12, 0.06, 0.02, 2.6], [0.16, 0.1, 0.09, 0.06, 0.06, 2.6], [0.32, 0.03, 0.02, 0.03, 0.12, 2.4]]
		_:
			return
	if kind in ["sport", "racing"]:
		_facet_cowl(keys, ln, mat, lk)
		return
	var secs := []
	for k in keys:
		secs.append({"c": t + Vector3(0.0, float(k[4]), float(k[0]) * ln), "w": k[1], "up": k[2], "down": k[3], "n": k[5]})
	var cowl := _shell(secs, mat)
	cowl.name = "TailCowl"
	if kind == "tracker":
		var board := _mesh_instance(_cylinder(0.12, 0.012), _mat(_accent(Color(0.95, 0.95, 0.92)), 0.0, 0.5), t + Vector3(0.0, 0.07, 0.31 * ln))
		board.rotation.x = PI * 0.5 - 0.15
		board.scale = Vector3(1.15, 1.0, 0.75)
	elif kind == "solo":
		_box(t + Vector3(0.0, 0.1, 0.2 * ln), Vector3(0.18, 0.08, 0.04), mat)
	if lk.has("accent"):
		# A stripe along the cowl in the second colour.
		var stripe := []
		for sec in secs:
			stripe.append((sec["c"] as Vector3) + Vector3(0.0, float(sec["up"]) + 0.002, 0.0))
		_bend(stripe, 0.012, _mat(_accent(), 0.1, 0.35, 0.6))


## A sports or race tail (keys as in _tail_cowl) built from flat panels to match the full
## fairings: a tucked-in underside, a sharp crease along each flank, a ridged top, tapering to
## a point, with the accent colour as a stripe along the upper flank.
func _facet_cowl(keys: Array, ln: float, mat: Material, lk: Dictionary) -> void:
	var rows := []
	for k in keys.size():
		var a: Array = keys[k]
		var b: Array = keys[mini(k + 1, keys.size() - 1)]
		for step in (3 if k < keys.size() - 1 else 1):
			var f := step / 3.0
			var z := lerpf(float(a[0]), float(b[0]), f) * ln
			var w := lerpf(float(a[1]), float(b[1]), f)
			var up := lerpf(float(a[2]), float(b[2]), f)
			var down := lerpf(float(a[3]), float(b[3]), f)
			var c := _tail + Vector3(0.0, lerpf(float(a[4]), float(b[4]), f), z)
			rows.append(PackedVector3Array([c + Vector3(0.0, -down, 0.0), c + Vector3(w * 0.62, -down, 0.0), c + Vector3(w, lerpf(-down, up, 0.4), 0.0),
				c + Vector3(w * 0.72, up * 0.82, 0.0), c + Vector3(w * 0.3, up, 0.0), c + Vector3(0.0, up + 0.008, 0.0)]))
	var cowl := _facets(rows, mat)
	cowl.name = "TailCowl"
	for end in [0, rows.size() - 1]:
		_mesh_instance(ShapeKit.fan(_mirror_row(rows[end]), Vector3.FORWARD if end == 0 else Vector3.BACK), mat, Vector3.ZERO)
	if lk.has("accent"):
		_grid_patch(rows, [0.0, 0.0, 1.0, 1.0], 3.15, 3.7, 0.003, _mat(_accent(), 0.1, 0.35, 0.6))


## Where the rear light sits, in the bike's own space: the tail unit's "light_at" (up and back
## from the end of the subframe). Vector3.ZERO with no tail unit.
func tail_light_position() -> Vector3:
	var p := PartsDB.get_part(str(_build.parts.get("tail", "none"))) if _build else {}
	if p.is_empty():
		return Vector3.ZERO
	var at: Array = p.get("light_at", [0.0, 0.25])
	return _tail + Vector3(0.0, float(at[0]), float(at[1]))


## A mudguard following a wheel: plates round an arc of `radius` about `c`, from angle `a0` to
## `a1` (radians from straight up, positive towards the back).
func _guard(c: Vector3, radius: float, width: float, a0: float, a1: float, mat: Material, segs := 8, parent: Node3D = self) -> Array[MeshInstance3D]:
	var step := (a1 - a0) / segs
	var out: Array[MeshInstance3D] = []
	for i in segs:
		var a := a0 + step * (i + 0.5)
		var seg := _box(c + Vector3(0.0, cos(a), sin(a)) * radius, Vector3(width, 0.012, radius * step * 1.1), mat, parent)
		seg.rotation.x = a
		out.append(seg)
	return out


## How far from the rear axle (as drawn, at rest) the rear mudguard sits at angle `a` (as in
## _guard), for a guard drawn `radius` out: never nearer than clears the tyre with the shock
## fully compressed, so the tyre can't show through it. Over the top that raises it by about
## the travel less the gap it had; round the back the tyre moves along the guard, so it stays.
func _rear_guard_r(a: float, radius: float) -> float:
	var t := _build.rear_travel
	var need := _build.rear_radius + GUARD_GAP
	var s := t * sin(a)
	return maxf(radius, t * cos(a) + sqrt(maxf(need * need - s * s, 0.0)))


## The point on the rear mudguard at angle `a` (see _rear_guard_r), in the model's space.
func _rear_guard_at(a: float, radius: float) -> Vector3:
	return Vector3(0.0, 0.0, _build.wheelbase * 0.5) + Vector3(0.0, cos(a), sin(a)) * _rear_guard_r(a, radius)


## The rear mudguard as plates round the rear wheel (as _guard), each far enough out to clear
## the tyre with the shock fully compressed (see _rear_guard_r). A plate that would have to go
## up into the seat to clear it is left out: the seat covers the tyre there.
func _rear_arc(radius: float, width: float, a0: float, a1: float, mat: Material, segs: int) -> Array[MeshInstance3D]:
	var step := (a1 - a0) / segs
	var out: Array[MeshInstance3D] = []
	for i in segs:
		var a := a0 + step * (i + 0.5)
		var at := _rear_guard_at(a, radius)
		if _rear_guard_r(a, radius) > radius + 0.002 and _in_seat(at):
			continue
		var d := _rear_guard_at(a + step * 0.5, radius) - _rear_guard_at(a - step * 0.5, radius)
		var seg := _box(at, Vector3(width, 0.012, d.length() * 1.1), mat)
		seg.rotation.x = atan2(-d.y, d.z)
		out.append(seg)
	return out


## Whether `at` (model space) is up in the seat: above the tail's rail and ahead of its end.
func _in_seat(at: Vector3) -> bool:
	return at.y > _tail.y - 0.02 and at.z < _tail.z + 0.04


## Raises a flat piece of the rear mudguard (a tray or a fender blade) until the tyre, with the
## shock fully compressed, is clear of it. One that would end up in the seat is left out.
func _lift_clear_of_tyre(piece: MeshInstance3D) -> void:
	var start := piece.position.y
	for i in 40:
		var depth := _tyre_depth(piece)
		if depth <= 0.0:
			break
		piece.position.y += depth + 0.003
	if piece.position.y > start + 0.002 and _in_seat(piece.position + Vector3(0.0, -0.02, 0.0)):
		_slot_meshes["tail"].erase(piece)
		piece.free()


## Moves each number plate off the rear mudguard where they'd cut into each other (with
## PLATE_GAP to spare), the shortest way out of all its pieces: straight out through its own
## face either way, out from the wheel, back or down. It hangs on a short bracket from where it was.
func _clear_plates(mat: Material) -> void:
	var axle := Vector3(0.0, 0.0, _build.wheelbase * 0.5)
	for plate in _plates:
		var start := plate.position
		var face := plate.basis.z.normalized()
		var best := Vector3.ZERO
		var best_d := INF
		for way in [face, -face, Vector3(0.0, start.y - axle.y, start.z - axle.z).normalized(), Vector3.BACK, Vector3.DOWN]:
			# In 1 cm steps, then back in 2 mm ones to the nearest clear spot.
			for i in 16:
				var d := i * 0.01
				if d >= best_d:
					break
				plate.position = start + way * d
				if _plate_clear(plate):
					while d > 0.0:
						plate.position = start + way * (d - 0.002)
						if not _plate_clear(plate):
							break
						d -= 0.002
					best = way * d
					best_d = d
					break
		plate.position = start + best
		if best.length() > 0.01:
			_tube(start, plate.position, 0.006, mat)


## Whether a number plate is clear of every piece of the rear mudguard, PLATE_GAP to spare.
func _plate_clear(plate: MeshInstance3D) -> bool:
	var a := _obb(plate, PLATE_GAP)
	for piece in _rear_guard:
		if _obb_push(a, _obb(piece)) != Vector3.ZERO:
			return false
	return true


## A flat plate from `a` to `b` (both on the centre line), `width` across and `thick` deep.
func _plank(a: Vector3, b: Vector3, width: float, thick: float, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var d := b - a
	var plank := _box((a + b) * 0.5, Vector3(width, thick, d.length()), mat, parent)
	plank.rotation.x = atan2(-d.y, d.z)
	return plank


## The front mudguard. Low ones follow the tyre on the fork legs, so they ride up and down with
## the wheel: a short hugger, a carbon sport hugger, a slim cafe blade, a bobbed blade or a long
## valanced classic on stays. High ones (MX and enduro) bolt under the bottom yoke and stay put
## while the wheel moves under them. Painted ones take the part's own colour like the tank.
func _draw_front_mudguard(build: BikeBuild) -> void:
	_current_slot = "front_mudguard"
	var p := _part()
	if p.is_empty():
		return
	var material := str(p.get("material", "plastic"))
	var col := _col()
	var mat: StandardMaterial3D
	match material:
		"metal":
			mat = _mat(col, 0.25 if p.get("paint_match", false) else 0.9, 0.2 if p.get("paint_match", false) else 0.15, 0.6 if p.get("paint_match", false) else 0.0)
		"carbon":
			mat = _mat(col, 0.2, 0.25, 0.8)
		_:
			mat = _mat(col, 0.1, 0.4, 0.5)
	if not p.get("paint_match", false):
		mat = _skin(mat)
	var stay := _mat(Color(0.82, 0.83, 0.85), 0.95, 0.2)
	var black := _mat(Color(0.04, 0.04, 0.045), 0.3, 0.6)
	var r := build.front_radius
	var w := build.front_tyre_width + 0.03
	var style := str(p.get("style", "hugger"))
	if style in ["high", "enduro"]:
		# Under the bottom yoke, sweeping forward and up into a beak; the enduro one is longer
		# at the back and has a lip at the front.
		# A hand's width above the tyre at rest (in steering space), held up off the yoke on stays.
		var axle := Vector3(0.0, 0.0, -build.wheelbase * 0.5) - _head
		var top := axle + Vector3(0.0, r + 0.1, 0.0)
		var yoke := -_steer_axis * 0.16
		var base := Vector3(0.0, minf(top.y, yoke.y - 0.03), lerpf(top.z, yoke.z, 0.5))
		var long := style == "enduro"
		var back := base + Vector3(0.0, -0.04, 0.14 if long else 0.08)
		var mid := base + Vector3(0.0, 0.0, -0.08)
		var nose := base + Vector3(0.0, 0.06, -0.3 if long else -0.34)
		_plank(back, base, w + 0.02, 0.012, mat, _steer_node)
		_plank(base, mid, w + 0.01, 0.012, mat, _steer_node)
		_plank(mid, nose, w, 0.012, mat, _steer_node)
		if long:
			_plank(nose, nose + Vector3(0.0, -0.05, -0.03), w * 0.8, 0.012, mat, _steer_node)
		for side in [-1.0, 1.0]:
			_tube(base + Vector3(0.05 * side, 0.0, 0.0), yoke + Vector3(0.05 * side, -0.02, 0.0), 0.008, black, Vector3.ONE, _steer_node)
		return
	var gap := 0.03
	var a0 := -0.5
	var a1 := 0.75
	match style:
		"sport":
			gap = 0.02
			a0 = -0.35
			a1 = 0.65
			w -= 0.01
		"cafe":
			gap = 0.035
			a0 = -0.75
			a1 = 0.95
			w -= 0.02
		"bobbed":
			gap = 0.03
			a0 = -0.3
			a1 = 0.45
		"classic":
			gap = 0.045
			a0 = -1.0
			a1 = 1.3
			w += 0.03
	var lk := _look()
	gap = float(lk.get("gap", gap))
	a0 = float(lk.get("a0", a0))
	a1 = float(lk.get("a1", a1))
	w += float(lk.get("wider", 0.0))
	var radius := r + gap
	_guard(Vector3.ZERO, radius, w, a0, a1, mat, 10 if style == "classic" else 6, _front_hub)
	if lk.get("rib", false):
		# A chrome rib along the crown of the guard.
		var rib := []
		for i in 9:
			var a := lerpf(a0, a1, i / 8.0)
			rib.append(Vector3(0.0, cos(a), sin(a)) * (radius + 0.008))
		_bend(rib, 0.006, _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1), _front_hub)
	if lk.has("accent"):
		for side in [-0.03, 0.03]:
			var stripe := []
			for i in 9:
				var a := lerpf(a0, a1, i / 8.0)
				stripe.append(Vector3(side, 0.0, 0.0) + Vector3(0.0, cos(a), sin(a)) * (radius + 0.007))
			_bend(stripe, 0.004, _mat(_accent(), 0.1, 0.35, 0.6), _front_hub)
	if style == "classic":
		# Deep valances down each side of the tyre.
		for side in [-1.0, 1.0]:
			var step := (a1 - a0) / 8.0
			for i in 8:
				var a := a0 + step * (i + 0.5)
				var seg := _box(Vector3(w * 0.5 * side, 0.0, 0.0) + Vector3(0.0, cos(a), sin(a)) * (radius - 0.025),
					Vector3(0.008, 0.05, radius * step * 1.1), mat, _front_hub)
				seg.rotation.x = a
	# Bolted to the fork legs either side, just above the tyre.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.09 * side, radius * 0.92, 0.0), Vector3(0.03, 0.02, 0.05), black, _front_hub)
	if style in ["classic", "cafe", "bobbed"]:
		# Wire stays from the axle out to the guard, front and back.
		var ends := [a0 + 0.2, a1 - 0.2] if style != "bobbed" else [a1 - 0.1]
		for side in [-1.0, 1.0]:
			var x: float = (w * 0.5 + 0.01) * side
			for a: float in ends:
				_tube(Vector3(x, 0.0, 0.0), Vector3(x, 0.0, 0.0) + Vector3(0.0, cos(a), sin(a)) * radius, 0.005, stay, Vector3.ONE, _front_hub)


## A number plate facing backwards, its top leaning back by `tilt` (radians).
func _number_plate(at: Vector3, size: Vector2, tilt: float, mat: Material) -> MeshInstance3D:
	var plate := _box(at, Vector3(size.x, size.y, 0.005), mat)
	plate.rotation.x = tilt
	plate.name = "NumberPlate"
	_plates.append(plate)
	return plate


## The fairing round the headlight: a flyscreen or bikini fairing on the forks (they turn with
## the bars), or a half, touring or full race fairing on the frame, each with its screen. They're
## curved shells lofted round the headlight, open at the nose so the headlight shines through;
## the race fairing adds side panels and a belly pan wrapped under the engine.
func _draw_fairing() -> void:
	_current_slot = "fairing"
	var p := _part()
	if p.is_empty():
		return
	var carbon := str(p.get("material", "")) == "carbon"
	var mat := _skin(_mat(_col(), 0.2 if carbon else 0.15, 0.25 if carbon else 0.2, 0.8 if carbon else 0.6))
	var glass := _mat(Color(0.5, 0.58, 0.66), 0.2, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.35
	var dark := _mat(Color(0.04, 0.04, 0.045), 0.2, 0.6)
	var screen := float(p.get("screen", 0.15))
	var style := str(p.get("style", "half"))
	# A look can redraw the shell ("shape": batwing, cowl, screen for a bare cruiser screen,
	# seeley for a round club racer half fairing) and resize it ("wide", "tall", "n" squareness).
	var lk := _look()
	var shape := str(lk.get("shape", style))
	if shape == "screen":
		# A tall screen on chrome stays off the bars, nothing else.
		var lamp := Vector3(0.0, -0.08, -0.13)
		var chrome := _mat(Color(0.86, 0.87, 0.89), 1.0, 0.1)
		_screen(lamp + Vector3(0.0, 0.1, 0.02), 0.2 * float(lk.get("wide", 1.0)), screen, 0.3, glass, _steer_node)
		for side in [-1.0, 1.0]:
			_tube(lamp + Vector3(0.16 * side, 0.08, 0.02), Vector3(0.09 * side, 0.02, 0.02), 0.007, chrome, Vector3.ONE, _steer_node)
			_tube(lamp + Vector3(0.16 * side, 0.08, 0.02), Vector3(0.09 * side, -0.14, 0.0), 0.007, chrome, Vector3.ONE, _steer_node)
		return
	if style in ["flyscreen", "bikini"] or shape in ["batwing", "cowl"]:
		var lamp := Vector3(0.0, -0.08, -0.13)   # the headlight, in steering space (see _draw_headlight)
		var big := style == "bikini" or shape == "batwing"
		var w: float = {"batwing": 0.3, "cowl": 0.11}.get(shape, 0.17 if big else 0.12)
		w *= float(lk.get("wide", 1.0))
		var tall := float(lk.get("tall", 1.0)) * (1.25 if shape == "batwing" else 1.0)
		var low := 1.8 if shape == "batwing" else (1.3 if big else 0.7)
		var secs := []
		for k in 4:
			var f := k / 3.0
			secs.append({"c": lamp + Vector3(0.0, 0.01 * f, lerpf(-0.05, 0.1, f)), "w": w * lerpf(0.85, 1.05, f), "up": lerpf(0.1, 0.12, f) * (1.1 if big else 1.0) * tall,
				"down": lerpf(0.08, 0.1, f) * low, "n": float(lk.get("n", 2.6))})
		_shell(secs, mat, true, -0.45, PI + 0.45, _steer_node)
		var top: Dictionary = secs[1]
		if shape != "cowl" or screen > 0.05:
			_screen(top["c"] + Vector3(0.0, float(top["up"]) - 0.01, 0.0), w * 0.8, screen, 0.35 if shape == "batwing" else 0.45, glass, _steer_node)
		if lk.has("accent"):
			var stripe := []
			for sec in secs:
				stripe.append((sec["c"] as Vector3) + Vector3(0.0, float(sec["up"]) + 0.003, 0.0))
			_bend(stripe, 0.01, _mat(_accent(), 0.1, 0.35, 0.6), _steer_node)
		return
	var touring := style == "touring"
	var race := style == "race"
	if race and shape != "seeley":
		_full_fairing(mat, glass, dark, screen, lk)
		return
	if shape == "adventure":
		_adventure_fairing(mat, glass, dark, screen, lk)
		return
	var wide := (0.27 if touring else 0.2) * float(lk.get("wide", 1.0))
	var tall := (1.25 if touring else 1.0) * float(lk.get("tall", 1.0))
	var h := lamp_position()
	var keys := [[-0.07, 0.11, 0.09, 0.1, 0.0], [0.02, 0.19, 0.14, 0.16, 0.01], [0.16, 0.22, 0.15, 0.22, 0.0], [0.28, 0.2, 0.12, 0.26, -0.02]]
	if race:
		keys = [[-0.13, 0.05, 0.04, 0.05, -0.02], [-0.06, 0.13, 0.1, 0.13, 0.0], [0.04, 0.19, 0.13, 0.2, 0.01], [0.16, 0.21, 0.12, 0.26, 0.0], [0.26, 0.19, 0.09, 0.28, -0.02]]
	var secs := []
	for k in keys:
		secs.append({"c": h + Vector3(0.0, float(k[4]) * tall, float(k[0])), "w": float(k[1]) * wide / 0.2, "up": float(k[2]) * tall,
			"down": float(k[3]) * (1.6 if touring else 1.0), "n": float(lk.get("n", (2.0 if shape == "seeley" else (2.5 if race else 2.8))))})
	# A modern half fairing is flat panels with creases, like the full ones: each section's
	# outline taken at a few points round it and joined straight (the old round shell stays for
	# a club racer's Seeley-style half and the touring ones).
	var faceted := style == "half" and shape != "seeley"
	var shell: MeshInstance3D
	if faceted:
		var rows := []
		for sec: Dictionary in secs:
			if not lk.has("n"):
				sec["n"] = 2.4
			var row := PackedVector3Array()
			for a: float in [-0.75, -0.45, -0.1, 0.4, 0.95, PI * 0.5]:
				row.append(_on_loft(sec, a))
			rows.append(row)
		shell = _facets(rows, mat)
	else:
		shell = _shell(secs, mat, true, -0.75, PI + 0.75)
	if lk.has("accent"):
		var stripe := []
		for sec in secs:
			stripe.append((sec["c"] as Vector3) + Vector3(0.0, float(sec["up"]) + 0.003, 0.0))
		_bend(stripe, 0.012, _mat(_accent(), 0.1, 0.35, 0.6))
	if lk.get("roundel", false):
		# Racing number roundels on the nose sides.
		for side in [-1.0, 1.0]:
			var nose: Dictionary = secs[1]
			var disc := _mesh_instance(_cylinder(0.06, 0.004), _mat(Color(0.95, 0.95, 0.92), 0.0, 0.5), (nose["c"] as Vector3) + Vector3(float(nose["w"]) * 0.93 * side, -0.02, 0.02))
			disc.rotation.z = PI * 0.5
	shell.name = "FairingShell"
	# Twin headlamp "eyes" set into the nose, lit with the headlight.
	var eye_s: Dictionary = secs[1] if race else secs[0]
	var bezel := _mat(Color(0.03, 0.03, 0.035), 0.4, 0.3)
	var lens := _lamp(Color(1.0, 0.97, 0.9), 3.0, "head")
	for side in [-1.0, 1.0]:
		var at := _on_loft(eye_s, (0.25 if race else -0.1) if side > 0.0 else PI - (0.25 if race else -0.1), 1.0)
		at.z -= 0.012
		var b := _mesh_instance(_sphere(0.04 if not touring else 0.05), bezel, at)
		b.scale = Vector3(1.0, 0.5, 0.35)
		b.rotation.y = 0.35 * side
		var eye := _mesh_instance(_sphere(0.034 if not touring else 0.044), lens, at + Vector3(0.0, 0.0, -0.006))
		eye.scale = Vector3(1.0, 0.42, 0.3)
		eye.rotation.y = 0.35 * side
		eye.name = "FairingLamp"
	var crown: Dictionary = secs[1]
	if faceted:
		_facet_screen(crown["c"] + Vector3(0.0, float(crown["up"]) - 0.045, 0.02), float(crown["w"]) * 0.8, screen, 0.55, glass)
	else:
		_screen(crown["c"] + Vector3(0.0, float(crown["up"]) - 0.015, 0.02), float(crown["w"]) * 0.8, screen,
			{"race": 0.85, "touring": 0.3}.get(style, 0.55) as float, glass)
	if race:
		# A ram-air intake under the nose.
		var nose: Dictionary = secs[0]
		var duct := _mesh_instance(_sphere(0.04), dark, nose["c"] + Vector3(0.0, -float(nose["down"]) * 0.6, 0.01))
		duct.scale = Vector3(1.2, 0.55, 0.4)
		# Side panels and a belly pan wrapped under the engine, as one U-shaped shell.
		var side_x := maxf(wide, _block_w * 0.5 + 0.07)
		var z0 := h.z + 0.1
		var z1 := _engine_c.z + 0.16
		var mid_y := _engine_c.y + 0.08
		var low := mid_y - (_engine_c.y - 0.2 * _eng_s)
		var lower := []
		for k in 5:
			var f := k / 4.0
			# The front edge tucks in behind the wheel; the panels swell round the engine.
			var swell := lerpf(0.55, 1.0, minf(f * 2.5, 1.0))
			lower.append({"c": Vector3(0.0, mid_y + 0.04 * (1.0 - f), lerpf(z0, z1, f)), "w": side_x * swell,
				"up": 0.12 * swell, "down": low * lerpf(0.55, 1.0, minf(f * 2.0, 1.0)), "n": 3.2})
		var belly := _shell(lower, mat, true, PI - 0.35, TAU + 0.35)
		belly.name = "LowerFairing"
		# Vents in the side panels.
		for side in [-1.0, 1.0]:
			for v in 3:
				var at := Vector3(side_x * 0.97 * side, mid_y + 0.02 - v * 0.035, lerpf(z0, z1, 0.3) + v * 0.02)
				_box(at, Vector3(0.006, 0.012, 0.09), dark)
	elif not touring:
		# Side vents in a half fairing, letting the engine heat out.
		var flank: Dictionary = secs[2]
		for side in [-1.0, 1.0]:
			for v in 4:
				var at := _on_loft(flank, (-0.45 if side > 0.0 else PI + 0.45), 1.004) + Vector3(0.0, 0.02 - v * 0.022, -0.02 + v * 0.012)
				var slat := _box(at, Vector3(0.006, 0.008, 0.07), dark)
				slat.rotation.y = 0.2 * side
				slat.name = "FairingVent"
	if touring:
		# Knee wings to keep the rain off the rider's legs.
		for side in [-1.0, 1.0]:
			_shell([{"c": h + Vector3((wide + 0.0) * side, -0.22, 0.1), "w": 0.015, "up": 0.08, "down": 0.08, "n": 3.0},
				{"c": h + Vector3((wide + 0.03) * side, -0.3, 0.22), "w": 0.015, "up": 0.1, "down": 0.08, "n": 3.0},
				{"c": h + Vector3((wide - 0.02) * side, -0.34, 0.3), "w": 0.012, "up": 0.06, "down": 0.05, "n": 3.0}], mat)


## A modern full fairing (a Panigale, an S1000RR, a ZX-10R, a MotoGP bike), built from flat
## panels with crisp creases rather than round lofts: a sharp nose (slim headlight slits on a
## road bike; a blank number-plate nose with a ram-air slot on a race bike), a straight raked
## top line up to a short laid-back screen, faceted flanks with a character line running back
## from the nose, a layered side cover with a dark vent gap in front of it, a narrow V belly pan
## under the engine, and side panels carried on back under the seat. Its look can ask for
## "wings" (winglets a side; two on a race bike unless it says), "lamps": false (a race nose),
## "tall" (how high the nose stands), "wide", and "n" (lower is a sharper, deeper crease).
func _full_fairing(mat: Material, glass: Material, dark: Material, screen: float, lk: Dictionary) -> void:
	var h := lamp_position()
	var zf := -_build.wheelbase * 0.5
	var rf := _build.front_radius
	var lamps := bool(lk.get("lamps", true))
	var low := float(lk.get("tall", 1.0))
	# Sized round the engine as drawn: wide enough for the crankcase, low enough to wrap
	# under it, long enough to reach back past the gearbox.
	var body := AABB(_engine_c, Vector3.ZERO)
	var case_x := 0.0
	for slot in ["engine", "gearbox"]:
		for mi in _slot_meshes.get(slot, []):
			var box := _model_aabb(mi as VisualInstance3D)
			body = body.merge(box)
			if (mi as Node).name.begins_with("Crankcase"):
				case_x = maxf(case_x, maxf(absf(box.position.x), absf(box.end.x)))
	var side_x := clampf(maxf(case_x, _block_w * 0.4) + 0.04, 0.22, 0.29) * float(lk.get("wide", 1.0))
	var z1 := clampf(body.end.z + 0.03, lerpf(_engine_c.z, _pivot.z, 0.6), _pivot.z - 0.02)
	var belly := minf(_engine_c.y - 0.24 * _eng_s, body.position.y) - 0.025
	var crease := clampf((3.0 - float(lk.get("n", 2.6))) / 0.7, 0.0, 1.0)
	# The outline side on, all straight runs: the top line from the tip up to the screen and down
	# under the tank, the lower edge from the chin round the front wheel in three cuts to the
	# belly, and the width, each as a function of z.
	var nose_z := h.z - (0.17 if lamps else 0.19)
	var tip_y := h.y - (0.04 if lamps else 0.07)
	var crown := Vector2(h.z + 0.04, h.y + 0.16 * low)
	var tank_z := _head.z + 0.1
	var top_line := [Vector2(nose_z - 0.1, tip_y), Vector2(nose_z, tip_y), crown]
	for k in 5:
		var z := lerpf(tank_z, z1 + 0.3, k / 4.0)
		top_line.append(Vector2(z, tank_base_y(z) + 0.02))
	var wheel_r := (rf + 0.06) * 1.04
	var chin := Vector2(nose_z + 0.08, h.y - (0.12 if lamps else 0.14))
	var cut := [Vector2(nose_z - 0.1, tip_y - 0.03), chin]
	var chin_a := atan2(chin.x - zf, chin.y)
	for a in [lerpf(chin_a, PI * 0.5, 0.4), lerpf(chin_a, PI * 0.5, 0.75), PI * 0.5]:
		cut.append(Vector2(zf + sin(a) * wheel_r, cos(a) * wheel_r))
	# Behind the wheel the edge slants on down to the belly, then rises a little to the back.
	var pan_z := zf + wheel_r + 0.1
	cut.append(Vector2(pan_z, belly + 0.03))
	cut.append(Vector2(z1, belly + 0.13))
	cut.append(Vector2(z1 + 0.5, belly + 0.13))
	var wide := [Vector2(nose_z - 0.1, 0.03), Vector2(nose_z, 0.035), Vector2(nose_z + 0.1, side_x * 0.55),
		Vector2(h.z + 0.16, side_x * 0.93), Vector2(_engine_c.z, side_x), Vector2(z1, side_x * 0.9)]
	# The profile, edge to centre line: the lower edge, the lower crease, the character line
	# (the widest), the shoulder, the top edge and the spine. The nose is narrower and more
	# pointed; each line starts a little further back than the one above it (the nose rakes
	# back to the chin) and ends a little further forward (the trailing edge slants up).
	var r_nose := [0.0, 0.2, 0.45, 0.72, 0.92, 1.0]
	var x_nose := [0.5, 0.85, 1.0, 0.82, 0.42, 0.0]
	var r_body := [0.0, 0.22, 0.5, 0.78, 0.94, 1.0]
	var x_body := [0.62, 0.87 - 0.05 * crease, 1.0, 0.76 - 0.06 * crease, 0.42, 0.0]
	var z_in := [0.08, 0.05, 0.02, 0.008, 0.002, 0.0]
	var z_out := [0.0, -0.06, -0.15, -0.22, -0.26, -0.26]
	var rows := []
	var steps := 18
	for i in steps + 1:
		var f := float(i) / steps
		var t := smoothstep(0.0, 0.35, f)
		var row := PackedVector3Array()
		for j in 6:
			var z := lerpf(nose_z + float(z_in[j]), z1 + float(z_out[j]), f)
			var top := _pwl(top_line, z)
			var bottom := minf(_pwl(cut, z), top - 0.06)
			var y := lerpf(bottom, top, lerpf(float(r_nose[j]), float(r_body[j]), t))
			row.append(Vector3(_pwl(wide, z) * lerpf(float(x_nose[j]), float(x_body[j]), t), y, z))
		rows.append(row)
	var shell := _facets(rows, mat)
	shell.name = "FairingShell"
	# A dark lining just inside, as real bodywork's inner faces are, seen through the wheel cut.
	var lining := []
	for i in rows.size():
		var row := PackedVector3Array()
		for j in 6:
			row.append((rows[i] as PackedVector3Array)[j] - _grid_normal(rows, i, clampf(j, 0.02, 4.98)) * 0.004)
		lining.append(row)
	_facets(lining, dark).name = "FairingLiner"
	# The nose: a dark ram-air mouth on a road bike, or blank paint with a slot under it on a
	# race bike.
	var front := _mirror_row(rows[0])
	var cap := _mesh_instance(ShapeKit.fan(front, Vector3.FORWARD), dark if lamps else mat, Vector3.ZERO)
	cap.name = "RamAir" if lamps else "NoseCap"
	if not lamps:
		var tip3: Vector3 = (rows[0] as PackedVector3Array)[5]
		var chin3: Vector3 = (rows[0] as PackedVector3Array)[0]
		var d := (chin3 - tip3).normalized()
		var fwd := Vector3(0.0, d.z, -d.y) * (1.0 if d.y < 0.0 else -1.0)
		var c := tip3.lerp(chin3, 0.7) + fwd * 0.004
		var slot := _mesh_instance(ShapeKit.plate(PackedVector3Array([c + Vector3(-0.035, 0.0, 0.0) - d * 0.01, c + Vector3(0.035, 0.0, 0.0) - d * 0.01,
			c + Vector3(0.025, 0.0, 0.0) + d * 0.012, c + Vector3(-0.025, 0.0, 0.0) + d * 0.012]), 0.004), dark, Vector3.ZERO)
		slot.name = "RamAir"
	if lamps:
		# Slim LED slits swept back and up along the nose's upper facets.
		var lens := _lamp(Color(0.92, 0.96, 1.0), 3.0, "head")
		for eye in _grid_patch(rows, [0.07, 0.03, 0.25, 0.32], 2.2, 2.75, 0.003, lens):
			eye.name = "FairingLamp"
	# The layered side cover, standing proud of the flank, with the dark vent gap ahead of it
	# where the hot air from the radiator gets out, and a vent in each shoulder.
	for cover in _grid_patch(rows, [0.62, 0.42, 0.98, 0.9], 0.45, 2.0, 0.012, mat):
		cover.name = "SideCover"
	for vent in _grid_patch(rows, [0.53, 0.33, 0.62, 0.42], 0.45, 2.0, 0.004, dark):
		vent.name = "FairingVent"
	for vent in _grid_patch(rows, [0.3, 0.28, 0.4, 0.38], 3.15, 3.75, 0.003, dark):
		vent.name = "FairingVent"
	if lk.has("accent"):
		# A stripe that runs along the top of the character line, the way race liveries do.
		_grid_patch(rows, [0.08, 0.08, 0.98, 0.9], 2.08, 2.42, 0.004, _mat(_accent(), 0.1, 0.35, 0.6))
	if lk.get("roundel", false):
		var plate := _mat(Color(0.95, 0.95, 0.92), 0.0, 0.5)
		for side in [-1.0, 1.0]:
			_disc_on(rows, 0.74 * steps, 1.3, 0.016, 0.055, side, plate)
		# And the number board across the front of the nose.
		_grid_patch(rows, [0.0, 0.0, 0.12, 0.1], 3.0, 5.0, 0.003, plate)
	# A narrow belly pan under the engine with a sharp keel, tucked inside the lower edge.
	var pan := []
	for i in 9:
		var f := i / 8.0
		var z := lerpf(pan_z - 0.08, z1 + 0.02, f)
		var w := _pwl(wide, z) * lerpf(0.62, 0.5, f) * minf(1.0, 0.35 + f * 4.0)
		var y := belly + 0.1 * f
		pan.append(PackedVector3Array([Vector3(w, y + 0.09, z), Vector3(w * 0.62, y - 0.005, z), Vector3(0.0, y - 0.04 - 0.012 * crease, z)]))
	_facets(pan, mat, true, true).name = "LowerFairing"
	# Side panels carry the bodywork on back under the seat to the tail, hiding the battery
	# and the subframe.
	var rear := []
	var r0 := z1 - 0.12
	var r1 := _tail.z - 0.12
	for k in 5:
		var f := float(k) / 4
		var z := lerpf(r0, r1, f)
		var top := lerpf(tank_base_y(z) + 0.01, _tail.y - 0.01, smoothstep(0.0, 1.0, f))
		var bottom := lerpf(_pivot.y + 0.1, _tail.y - 0.12, f)
		var w := lerpf(0.19, 0.12, f)
		rear.append(PackedVector3Array([Vector3(w * 0.88, bottom, z), Vector3(w, lerpf(bottom, top, 0.45), z), Vector3(w * 0.84, lerpf(bottom, top, 0.82), z),
			Vector3(w * 0.4, top, z), Vector3(0.0, top + 0.005, z)]))
	_facets(rear, mat).name = "SidePanel"
	# Whatever sits wholly behind the panels, side on, is out of sight (see _hide_covered).
	var top_y := -INF
	for row: PackedVector3Array in rows:
		for p in row:
			if p.z > _head.z + 0.1:
				top_y = maxf(top_y, p.y)
	# From the nose back, so the radiator and the headers behind the wheel cut go too.
	var cover_z0 := nose_z - 0.02
	_covered = [AABB(Vector3(-1.0, belly - 0.03, cover_z0), Vector3(2.0, top_y - belly + 0.03, z1 - cover_z0)),
		AABB(Vector3(-1.0, _pivot.y + 0.12, r0), Vector3(2.0, _tail.y - _pivot.y - 0.12, r1 - r0))]
	# A short screen laid well back from the crown, stood up and stretched only as far as it
	# takes for the clocks to sit below its top line.
	var tilt := 0.95 if lamps else 1.1
	var base := Vector3(0.0, crown.y - 0.012, crown.x - 0.006)
	var tall := clampf(screen, 0.1, 0.17) * (1.0 if lamps else 0.85)
	var clock_end := -INF
	for mi in _slot_meshes.get("dashboard", []):
		var box := _model_aabb(mi as VisualInstance3D)
		var dy := box.end.y + 0.02 - base.y
		if dy <= 0.0:
			continue
		for z in [box.position.z, box.end.z]:
			if z > base.z:
				tilt = minf(tilt, atan2(z - base.z, dy))
		clock_end = maxf(clock_end, box.end.z + 0.01)
	tilt = maxf(tilt, 0.75)
	if clock_end > base.z:
		tall = clampf((clock_end - base.z) / sin(tilt), tall, 0.2)
	_facet_screen(base, _pwl(wide, crown.x) * 0.56, tall, tilt, glass)
	# Winglets off the nose: one deck on a road bike that asks for them, two on a race bike, each
	# a thin swept blade out to a tall slim endplate.
	var wings := int(lk.get("wings", 0 if lamps else 2))
	if wings > 0:
		var roots := []
		var reach := 0.0
		for i in wings:
			var jw := 2.45 if wings == 1 else lerpf(2.2, 2.75, float(i) / maxf(wings - 1, 1))
			var fa := (0.14 + 0.02 * i) * steps
			var le := _grid_at(rows, fa, jw)
			var te := _grid_at(rows, fa + (0.15 if lamps else 0.18) * steps, jw)
			roots.append([le, te])
			reach = maxf(reach, maxf(le.x, te.x))
		# The tips all reach out to the one endplate.
		reach += 0.075 if lamps else 0.1
		for side in [-1.0, 1.0]:
			var lo := INF
			var hi := -INF
			var za := INF
			var zb := -INF
			for r in roots:
				var le: Vector3 = r[0]
				var te: Vector3 = r[1]
				var tip_le := Vector3(reach, le.y - 0.012, le.z + 0.06)
				var tip_te := Vector3(reach, te.y - 0.012, te.z + 0.015)
				var outline := PackedVector3Array()
				for p in [le, tip_le, tip_te, te]:
					outline.append(p * Vector3(side, 1.0, 1.0))
				_mesh_instance(ShapeKit.plate(outline, 0.006), mat, Vector3.ZERO).name = "Winglet"
				lo = minf(lo, minf(tip_le.y, tip_te.y))
				hi = maxf(hi, maxf(tip_le.y, tip_te.y))
				za = minf(za, tip_le.z)
				zb = maxf(zb, tip_te.z)
			# A tall slim endplate standing across the tips.
			lo -= 0.04
			hi += 0.015
			var x: float = reach * side
			var endplate := _mesh_instance(ShapeKit.plate(PackedVector3Array([Vector3(x, lo, za + 0.01), Vector3(x, hi, za + 0.025),
				Vector3(x, hi, zb), Vector3(x, lo, zb - 0.01)]), 0.005), mat, Vector3.ZERO)
			endplate.name = "Winglet"


## A screen rising from `base`, `half` wide, `height` long, leaning back by `tilt` (radians
## from upright): flat panes creased down the middle and either side, tapering to the top.
func _facet_screen(base: Vector3, half: float, height: float, tilt: float, glass: Material, parent: Node3D = self) -> MeshInstance3D:
	var dir := Vector3(0.0, cos(tilt), sin(tilt))
	var up := Vector3(0.0, sin(tilt), -cos(tilt))
	var pane := []
	for k in 4:
		var f := k / 3.0
		var at := base + dir * height * f
		var hw := half * lerpf(1.0, 0.7, f)
		var bulge := 0.04 * lerpf(1.0, 0.75, f)
		pane.append(PackedVector3Array([at + Vector3(hw, 0.0, 0.0), at + Vector3(hw * 0.6, 0.0, 0.0) + up * bulge * 0.8, at + up * bulge]))
	var mi := _facets(pane, glass, true, false, parent)
	mi.name = "Screen"
	return mi


## A faceted shell (see ShapeKit.facets) for the part being drawn.
func _facets(rows: Array, mat: Material, mirror := true, flip := false, parent: Node3D = self) -> MeshInstance3D:
	return _mesh_instance(ShapeKit.facets(rows, mirror, flip), mat, Vector3.ZERO, parent)


## A row's right half mirrored into the whole profile, left edge round to right edge.
static func _mirror_row(half: PackedVector3Array) -> PackedVector3Array:
	var row := PackedVector3Array()
	for k in half.size() - 1:
		row.append(half[k] * Vector3(-1.0, 1.0, 1.0))
	row.append(half[half.size() - 1])
	for k in range(half.size() - 2, -1, -1):
		row.append(half[k])
	return row


## A point on a faceted shell's right half (rows as for ShapeKit.facets): `fi` along the rows,
## `ji` across the profile's points, both fractional.
static func _grid_at(rows: Array, fi: float, ji: float) -> Vector3:
	var i := clampi(floori(fi), 0, rows.size() - 2)
	var w: int = (rows[0] as PackedVector3Array).size()
	var j := clampi(floori(ji), 0, w - 2)
	var a: PackedVector3Array = rows[i]
	var b: PackedVector3Array = rows[i + 1]
	var tf := clampf(fi - i, 0.0, 1.0)
	var tj := clampf(ji - j, 0.0, 1.0)
	return a[j].lerp(a[j + 1], tj).lerp(b[j].lerp(b[j + 1], tj), tf)


## Which way is out from a faceted shell's right half at (`fi`, `ji`); on a crease, the two
## facets' average.
static func _grid_normal(rows: Array, fi: float, ji: float) -> Vector3:
	var df := _grid_at(rows, fi + 0.2, ji) - _grid_at(rows, fi - 0.2, ji)
	var dj := _grid_at(rows, fi, ji + 0.01) - _grid_at(rows, fi, ji - 0.01)
	return dj.cross(df).normalized()


## A panel laid over a faceted shell, both sides: a patch of its skin from `ji0` to `ji1` across
## the profile, lifted `lift` off it, keeping the shell's creases. `f` is [front at ji0, front
## at ji1, back at ji0, back at ji1] as shares of the shell's length, so a patch can have
## slanted ends. Returns the right and left patches.
func _grid_patch(rows: Array, f: Array, ji0: float, ji1: float, lift: float, mat: Material) -> Array:
	var steps := rows.size() - 1
	var js := [ji0]
	for k in range(ceili(ji0 + 0.001), ceili(ji1 - 0.001)):
		js.append(float(k))
	js.append(ji1)
	# Rows at the shell's own rows (held at the patch's slanted ends), so the patch lies on the
	# shell's facets rather than cutting through them.
	var i0 := floori(minf(float(f[0]), float(f[1])) * steps)
	var i1 := ceili(maxf(float(f[2]), float(f[3])) * steps)
	var right := []
	var left := []
	for i in range(i0, i1 + 1):
		var row := PackedVector3Array()
		var mirrored := PackedVector3Array()
		for jv: float in js:
			var tj := (jv - ji0) / maxf(ji1 - ji0, 0.0001)
			var fi := clampf(float(i), lerpf(float(f[0]), float(f[1]), tj) * steps, lerpf(float(f[2]), float(f[3]), tj) * steps)
			# The ends take their own facet's normal; a crease inside takes the two facets' average.
			var jn := jv
			if is_equal_approx(jv, ji0):
				jn = jv + 0.02
			elif is_equal_approx(jv, ji1):
				jn = jv - 0.02
			var p := _grid_at(rows, fi, jv) + _grid_normal(rows, fi, jn) * lift
			mirrored.append(p * Vector3(-1.0, 1.0, 1.0))
			# The right half runs centre to edge, the way the shell's own right half does.
			row.insert(0, p)
		right.append(row)
		left.append(mirrored)
	return [_facets(right, mat, false, false), _facets(left, mat, false, false)]


## A flat round disc (a racing number roundel) on a faceted shell's flank, lifted `lift` off it,
## on the right (`side` 1) or the left (-1).
func _disc_on(rows: Array, fi: float, ji: float, lift: float, radius: float, side: float, mat: Material) -> MeshInstance3D:
	var c := _grid_at(rows, fi, ji)
	var n := _grid_normal(rows, fi, ji)
	var along := (_grid_at(rows, fi + 0.5, ji) - _grid_at(rows, fi - 0.5, ji)).normalized()
	var across := n.cross(along).normalized()
	var ring := PackedVector3Array()
	for k in 16:
		var a := TAU * k / 16.0
		ring.append((c + n * lift + (along * cos(a) + across * sin(a)) * radius) * Vector3(side, 1.0, 1.0))
	var disc := _mesh_instance(ShapeKit.plate(ring, 0.003), mat, Vector3.ZERO)
	disc.name = "Roundel"
	return disc


## The height of a polyline of (z, y) points at `z`, held flat past either end.
static func _pwl(points: Array, z: float) -> float:
	var first: Vector2 = points[0]
	if z <= first.x:
		return first.y
	for k in range(1, points.size()):
		var a: Vector2 = points[k - 1]
		var b: Vector2 = points[k]
		if z <= b.x:
			return lerpf(a.y, b.y, (z - a.x) / maxf(b.x - a.x, 0.0001))
	return (points[points.size() - 1] as Vector2).y


## An adventure bike's beak-nosed half fairing (a Multistrada, a GS, a Tracer): a tall, creased
## nose round the lamps with a big adjustable screen, and side wings that run back to shroud
## the front of the tank.
func _adventure_fairing(mat: Material, glass: Material, dark: Material, screen: float, lk: Dictionary) -> void:
	var h := lamp_position()
	var wide := 0.2 * float(lk.get("wide", 1.0))
	var tall := float(lk.get("tall", 1.0))
	var tank_a := _head + Vector3(0.0, -0.05, 0.06)
	var secs := []
	var steps := 7
	var z1 := _head.z + 0.3
	for k in steps + 1:
		var f := float(k) / steps
		var z := lerpf(h.z - 0.1, z1, f)
		var top := h.y + (0.04 + 0.1 * smoothstep(0.0, 0.4, f)) * tall - 0.06 * smoothstep(0.5, 1.0, f)
		var bottom := h.y - 0.1 - 0.12 * smoothstep(0.2, 0.8, f)
		if f > 0.5:
			bottom = minf(bottom, tank_a.y - 0.14)
		var mid := (top + bottom) * 0.5
		secs.append({"c": Vector3(0.0, mid, z), "w": lerpf(0.07, wide + 0.04, smoothstep(0.0, 0.6, f)), "up": top - mid,
			"down": mid - bottom, "n": float(lk.get("n", 1.7)), "bw": 0.85})
	var shell := _shell(secs, mat, true, -0.9, PI + 0.9)
	shell.name = "FairingShell"
	# The lamps, set in the creased nose.
	var lens := _lamp(Color(0.92, 0.96, 1.0), 3.0, "head")
	var nose: Dictionary = secs[1]
	for side in [-1.0, 1.0]:
		var at := _on_loft(nose, -0.15 if side > 0.0 else PI + 0.15, 1.01)
		var eye := _box(at, Vector3(0.012, 0.03, 0.06), lens)
		eye.rotation = Vector3(0.0, 0.6 * side, 0.15 * side)
		eye.name = "FairingLamp"
	# Black side panels where the fairing meets the tank, and the screen standing tall.
	var flank: Dictionary = secs[steps - 1]
	for side in [-1.0, 1.0]:
		var vent := _box(_on_loft(flank, -0.4 if side > 0.0 else PI + 0.4, 1.006), Vector3(0.006, 0.06, 0.12), dark)
		vent.rotation.y = 0.12 * side
		vent.name = "FairingVent"
	var crown: Dictionary = secs[3]
	# An adjustable screen hangs from its own node, moved up its rails as the rider sets it.
	var base: Vector3 = crown["c"] + Vector3(0.0, float(crown["up"]) - 0.015, -0.03)
	var adjust := float(_part().get("screen_adjust", 0.0))
	var host: Node3D = self
	if adjust > 0.0:
		_screen_lift = Node3D.new()
		_screen_lift.name = "ScreenLift"
		add_child(_screen_lift)
		_screen_dir = Vector3(0.0, cos(0.42), sin(0.42))
		_screen_lift.position = _screen_dir * (_build.screen_raise if _build else 0.0)
		host = _screen_lift
		# The rails it slides up, either side behind the screen.
		for side in [-1.0, 1.0]:
			_tube(base + Vector3(float(crown["w"]) * 0.45 * side, -0.02, 0.02), base + Vector3(float(crown["w"]) * 0.45 * side, 0.0, 0.02) + _screen_dir * (adjust + 0.06),
				0.006, dark)
	_screen(base, float(crown["w"]) * 0.7, maxf(screen, 0.28), 0.42, glass, host)
	if lk.has("accent"):
		var stripe := []
		for sec in secs:
			stripe.append(_on_loft(sec, -0.3, 1.004))
		_bend(stripe, 0.01, _mat(_accent(), 0.1, 0.35, 0.6))


## The top of the tank at `z` (along the bike): [height of its top, its half width there]. A
## tank bag sits on it.
func tank_top_at(z: float) -> Vector2:
	if _tank_secs.is_empty():
		return Vector2(_seat_y + 0.1, 0.12)
	var best: Dictionary = _tank_secs[0]
	for sec: Dictionary in _tank_secs:
		if absf(float((sec["c"] as Vector3).z) - z) < absf(float((best["c"] as Vector3).z) - z):
			best = sec
	return Vector2(float((best["c"] as Vector3).y) + float(best["up"]), float(best["w"]))


## Where the tank starts at the front (its nose's z).
func _tank_front() -> float:
	return float((_tank_secs[0]["c"] as Vector3).z) if not _tank_secs.is_empty() else _head.z + 0.1


## Lights the sat nav's screen with `tex` (the live map, see SatnavScreen), or blanks it with
## null: the rider's own sat nav (Satnav) has the screen from then on. `driven` false hands it
## back (getting off): then, like everyone else's bikes, it shows a still map while the
## ignition's on (see set_lights).
func set_satnav_texture(tex: Texture2D, driven := true) -> void:
	_satnav_live = tex
	_satnav_driven = driven
	_show_satnav()


## The sat nav's screen as drawn, or null with none fitted.
func satnav_screen() -> MeshInstance3D:
	return _satnav_screen if _satnav_screen != null and is_instance_valid(_satnav_screen) else null


## A phone sat nav's cradle (it holds the phone and its screen), or null for any other unit.
func satnav_cradle() -> Node3D:
	return _satnav_cradle if _satnav_cradle != null and is_instance_valid(_satnav_cradle) else null


## The light the sat nav's screen casts after dark, or null with none fitted.
func satnav_glow() -> OmniLight3D:
	return _satnav_glow if _satnav_glow != null and is_instance_valid(_satnav_glow) else null


## What's on the sat nav's screen now: the live map while the rider's own sat nav drives it,
## else a still map (KitModel.idle_screen) with the ignition on, or dark. After dark it glows,
## lighting the cradle and the gloves round it a little.
func _show_satnav() -> void:
	if _satnav_screen == null or not is_instance_valid(_satnav_screen):
		return
	var mat := _satnav_screen.material_override as StandardMaterial3D
	var tex: Texture2D = _satnav_live if _satnav_driven else (KitModel.idle_screen() if _lit[0] else null)
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE if tex != null else Color(0.02, 0.03, 0.04)
	_satnav_dark = Daylight.darkness()
	if _satnav_glow != null and is_instance_valid(_satnav_glow):
		var glow := smoothstep(0.2, 0.6, _satnav_dark) if tex != null and _satnav_screen.visible else 0.0
		_satnav_glow.light_energy = KitModel.GLOW_ENERGY * glow
		_satnav_glow.visible = glow > 0.01


## The bar as drawn, its right half from the middle out to the end (steering space; the left
## is its mirror image).
func bar_line() -> PackedVector3Array:
	return _bar_line


## The bar's length from the middle out to one end (m, along it).
func bar_length() -> float:
	var n := 0.0
	for i in range(1, _bar_line.size()):
		n += _bar_line[i].distance_to(_bar_line[i - 1])
	return n


## The point on the right of the bar `back` metres along it in from the end (steering space),
## and which way the bar runs there: [point, direction out towards the end].
func bar_point(back: float) -> Array:
	if _bar_line.size() < 2:
		return [_grip_r + Vector3(-0.15, 0.0, 0.0), Vector3.RIGHT]
	var left := maxf(back, 0.0)
	for i in range(_bar_line.size() - 1, 0, -1):
		var a := _bar_line[i - 1]
		var b := _bar_line[i]
		var d := a.distance_to(b)
		if left <= d or i == 1:
			return [b.lerp(a, clampf(left / maxf(d, 0.0001), 0.0, 1.0)), (b - a).normalized()]
		left -= d
	return [_bar_line[0], (_bar_line[1] - _bar_line[0]).normalized()]


## How far `p` (steering space) is from the middle of the bar's tube, either side.
func bar_distance(p: Vector3) -> float:
	var q := Vector3(absf(p.x), p.y, p.z)
	var best := INF
	for i in range(1, _bar_line.size()):
		var c := Geometry3D.get_closest_point_to_segment(q, _bar_line[i - 1], _bar_line[i])
		best = minf(best, c.distance_to(q))
	return best


## Moves an adjustable screen `raise` metres up its rails (0 right down), as the rider sets it.
func set_screen_raise(raise: float) -> void:
	if _screen_lift != null and is_instance_valid(_screen_lift):
		_screen_lift.position = _screen_dir * raise


## Under a full fairing the engine's covers, the airbox, the coil and the electrics are out of
## sight: anything of theirs that sits wholly inside the bodywork, seen side on, is left
## undrawn while the fairing is on (it shows again with the fairing off). So are the exhaust's
## headers under the front of it, though not the silencer.
const COVERED_SLOTS := ["engine", "head", "gearbox", "cooling", "air_filter", "fuel", "spark_plugs", "oil_filter", "ecu", "horn", "exhaust"]

func _hide_covered() -> void:
	for slot in COVERED_SLOTS:
		for mi in _slot_meshes.get(slot, []):
			var box := _model_aabb(mi as VisualInstance3D)
			for c in (_covered.slice(0, 1) if slot == "exhaust" else _covered):
				var inner: AABB = c
				# A little give at the ends: the fairing's own edge hides the last few cm.
				if box.position.y >= inner.position.y - 0.02 and box.end.y <= inner.end.y + 0.02 \
						and box.position.z >= inner.position.z - 0.05 and box.end.z <= inner.end.z + 0.04:
					(mi as Node).set_meta("under_fairing", true)
					break


## The filters you change with the engine in the frame. Under a full fairing each has a
## quick-release cap on the right-hand panel, over where it sits, that it comes out through:
## the cap goes with the filter, so it's what you see and aim at to get the filter out.
const SERVICE_CAPS: Array[String] = ["air_filter", "oil_filter"]

func _service_caps() -> void:
	var skin := []   # the fairing's triangles, in the model's space
	for mi in _slot_meshes.get("fairing", []):
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
			var xf := _local_xform(mi)
			for v in (mi as MeshInstance3D).mesh.get_faces():
				skin.append(xf * v)
	for slot in SERVICE_CAPS:
		var meshes: Array = _slot_meshes.get(slot, [])
		var box := slot_bounds(slot)
		# Partly behind the panels is behind them: the cap stands in for the lot (an oil filter
		# hanging out under the belly pan with the engine out of sight would look lost).
		var behind := meshes.any(func(mi): return (mi as Node).has_meta("under_fairing"))
		for c in _covered:
			var inner: AABB = c
			behind = behind or (box.end.y > inner.position.y and box.position.y < inner.end.y \
				and box.end.z > inner.position.z and box.position.z < inner.end.z)
		if meshes.is_empty() or not behind:
			continue
		for mi in meshes:
			(mi as Node).set_meta("under_fairing", true)
		var mid := box.get_center()
		# The panel straight out to the right of it, or as near that as the panel goes.
		var at := Vector3.ZERO
		var normal := Vector3.RIGHT
		for d in [Vector2.ZERO, Vector2(0.0, 0.05), Vector2(0.0, -0.05), Vector2(-0.05, 0.0), Vector2(0.05, 0.0),
				Vector2(-0.05, 0.08), Vector2(-0.05, -0.08), Vector2(0.0, 0.12), Vector2(0.0, -0.12), Vector2(-0.1, 0.0)]:
			var y: float = mid.y + d.x
			var z: float = mid.z + d.y
			var best := -INF
			for f in range(0, skin.size() - 2, 3):
				var hit = Geometry3D.segment_intersects_triangle(Vector3(1.0, y, z), Vector3(0.0, y, z), skin[f], skin[f + 1], skin[f + 2])
				if hit != null and (hit as Vector3).x > best:
					best = (hit as Vector3).x
					normal = (skin[f + 2] - skin[f]).cross(skin[f + 1] - skin[f]).normalized()
			if best > -INF:
				at = Vector3(best, y, z)
				break
		if at == Vector3.ZERO or (slot == "air_filter" and mid.x > at.x):
			# No panel over it after all (it's in a gap in the bodywork), or it stands out past
			# the panel (a V-twin's round air cleaner): it shows as it is.
			for mi in meshes:
				(mi as Node).remove_meta("under_fairing")
			continue
		if normal.x < 0.0:
			normal = -normal
		_current_slot = slot
		var col := _col()
		var cap := _mesh_instance(_cylinder(0.045, 0.012), _mat(col, 0.5, 0.4), at + normal * 0.006)
		cap.basis = _basis_up(normal)
		cap.name = "ServiceCap"
		cap.set_meta("service_cap", slot)
		var rim := _mesh_instance(_cylinder(0.052, 0.006), _mat(Color(0.08, 0.08, 0.09), 0.3, 0.5), at + normal * 0.002)
		rim.basis = _basis_up(normal)
		var grip := _box(at + normal * 0.014, Vector3(0.06, 0.008, 0.012), _mat(col.darkened(0.35), 0.5, 0.4))
		grip.basis = _basis_up(normal)
	_current_slot = ""


## A drawn mesh's bounds in the model's own space.
func _model_aabb(vi: VisualInstance3D) -> AABB:
	var xf := Transform3D.IDENTITY
	var n: Node = vi
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * vi.get_aabb()


## How high the tank's underside is at `z` (from the front of the tank back to the seat).
func tank_base_y(z: float) -> float:
	if _tank_b == _tank_a:
		return _seat_y
	return lerpf(_tank_a.y, _tank_b.y, clampf((z - _tank_a.z) / maxf(_tank_b.z - _tank_a.z, 0.01), 0.0, 1.0))


## Whether the fitted fairing is a full sports or race one (see _full_fairing).
func _race_fairing_fitted() -> bool:
	var f := PartsDB.get_part(str(_build.parts.get("fairing", "none")))
	if f.is_empty() or not is_fitted("fairing"):
		return false
	return str(f.get("style", "")) == "race" and str((f.get("look", {}) as Dictionary).get("shape", "race")) != "seeley"


## Whether the fitted fairing is a full race-style one that hides the headlight inside it.
func _full_fairing_fitted() -> bool:
	var f := PartsDB.get_part(str(_build.parts.get("fairing", "none")))
	if f.is_empty() or not is_fitted("fairing"):
		return false
	var shape := str((f.get("look", {}) as Dictionary).get("shape", f.get("style", "")))
	return str(f.get("style", "")) == "race" and shape != "seeley" or shape == "adventure"


## A curved screen rising from `base`, `half` wide, `height` tall, leaning back by `tilt`.
func _screen(base: Vector3, half: float, height: float, tilt: float, glass: Material, parent: Node3D = self) -> void:
	var dir := Vector3(0.0, cos(tilt), sin(tilt))
	var secs := []
	for k in 4:
		var f := k / 3.0
		secs.append({"c": base + dir * height * f - Vector3(0.0, 0.035, 0.0), "w": half * lerpf(1.0, 0.8, f), "up": 0.04, "down": 0.0, "n": 2.0})
	var pane := _shell(secs, glass, true, 0.25, PI - 0.25, parent)
	pane.name = "Screen"


## Mirrors: round or sport ones on stalks from the bars, round ones off the bar ends, tall
## touring ones, or pods on the fairing. The glass is a mirror finish, so from the saddle it
## catches the sky and the road round you.
func _draw_mirrors() -> void:
	_current_slot = "mirrors"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.8, 0.25)
	var glass := _mat(Color(0.9, 0.92, 0.95), 1.0, 0.02)
	var style := str(_look().get("shape", p.get("style", "round")))
	_mirror_k = float(_look().get("size", 1.0))
	var fairing := PartsDB.get_part(str(_build.parts.get("fairing", "none")))
	if style == "fairing" and fairing.is_empty():
		style = "sport"   # nothing to bolt to (a loose part on its own): shown as stalks
	for side in [-1.0, 1.0]:
		var grip: Vector3 = _grip_r if side > 0.0 else _grip_l
		var base := Vector3(grip.x * 0.55, grip.y + 0.01, grip.z - 0.02)
		match style:
			"bar_end":
				var end := grip + Vector3(0.06 * side, 0.0, 0.0)
				var head := end + Vector3(0.07 * side, -0.04, -0.01)
				_tube(end, head, 0.008, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.045, 0.0), mat, glass, _steer_node)
			"sport":
				var head := base + Vector3(0.13 * side, 0.1, -0.08)
				_tube(base, head, 0.007, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.13, 0.06), mat, glass, _steer_node)
			"rect":
				var head := base + Vector3(0.14 * side, 0.28, -0.02)
				_tube(base, head, 0.008, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.13, 0.09), mat, glass, _steer_node)
			"fairing":
				if fairing.get("frame_mount", false):
					var wide := 0.27 if str(fairing.get("style", "")) == "touring" else 0.2
					var h := lamp_position()
					var head := h + Vector3((wide + 0.05) * side, 0.1, 0.06)
					_tube(h + Vector3((wide - 0.01) * side, 0.08, 0.04), head, 0.01, mat)
					_mirror_head(head, Vector2(0.11, 0.055), mat, glass, self)
				else:
					var lamp := Vector3(0.0, -0.08, -0.13)
					var head := lamp + Vector3(0.2 * side, 0.08, 0.05)
					_tube(lamp + Vector3(0.12 * side, 0.06, 0.03), head, 0.009, mat, Vector3.ONE, _steer_node)
					_mirror_head(head, Vector2(0.1, 0.05), mat, glass, _steer_node)
			_:
				var head := base + Vector3(0.08 * side, 0.2, -0.03)
				_tube(base, head, 0.007, mat, Vector3.ONE, _steer_node)
				_mirror_head(head, Vector2(0.05, 0.0), mat, glass, _steer_node)


var _mirror_k := 1.0   # the mirrors' look "size", while they're drawn
## Each mirror's glass, for live reflections (see BikeMirrors): {"glass": the glass mesh,
## "frame": a node on the glass's face (+Z out towards the rider, X to their right), "size": its
## width and height}.
var mirrors: Array = []
## Where a rider sets their mirrors to look: back past their shoulder, a little out and level.
const MIRROR_AIM := Vector3(0.16, 0.0, 1.0)


## One mirror facing the rider: round (`size.x` its radius, `size.y` 0) or a rectangle `size`.
## The head swivels on its stalk to look back past the rider's shoulder from their eyes, as a
## rider sets them.
func _mirror_head(at: Vector3, size: Vector2, mat: Material, glass: Material, parent: Node3D) -> void:
	size *= _mirror_k
	var head := Node3D.new()
	head.name = "MirrorHead"
	head.position = at
	parent.add_child(head)
	head.basis = _mirror_aim(at, parent)
	var face: MeshInstance3D
	var dims: Vector2
	if size.y <= 0.0:
		var shell := _mesh_instance(_cylinder(size.x, 0.02), mat, Vector3.ZERO, head)
		shell.rotation.x = PI * 0.5
		face = _mesh_instance(_cylinder(size.x * 0.88, 0.002), glass, Vector3(0.0, 0.0, 0.011), head)
		face.rotation.x = PI * 0.5
		dims = Vector2.ONE * size.x * 1.76
	else:
		_box(Vector3.ZERO, Vector3(size.x, size.y, 0.02), mat, head)
		dims = Vector2(size.x - 0.01, size.y - 0.01)
		face = _box(Vector3(0.0, 0.0, 0.011), Vector3(dims.x, dims.y, 0.002), glass, head)
	face.name = "MirrorGlass"
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.set_meta("mirror_glass", true)   # kept out of the baked meshes, so BikeMirrors can swap its look
	var frame := Node3D.new()
	frame.name = "MirrorFrame"
	frame.position = Vector3(0.0, 0.0, 0.012)
	head.add_child(frame)
	mirrors.append({"glass": face, "frame": frame, "size": dims})


## The way a mirror head at `at` (in `parent`'s space) faces: half way between back at the
## rider's eyes and MIRROR_AIM, so from the saddle it shows the road behind.
func _mirror_aim(at: Vector3, parent: Node3D) -> Basis:
	var to_model := Transform3D(Basis(), _head) if parent == _steer_node else Transform3D()
	var p := to_model * at
	var eye := _eye if _eye != Vector3.ZERO else _eye_point()
	var aim := Vector3(MIRROR_AIM.x * signf(p.x), MIRROR_AIM.y, MIRROR_AIM.z).normalized()
	var n := to_model.basis.inverse() * ((eye - p).normalized() + aim).normalized()
	return Basis.looking_at(-n, Vector3.UP)


## The indicators: a pair either side of the headlight (turning with the bars) and a pair
## either side of the rear light, on rubber stalks, as chrome bullets, mini LEDs, LEDs set flush
## into the bodywork or big square touring lamps.
## Each side's lenses share one amber material, so left and right flash on their own (see
## set_signals), front and back.
func _draw_indicators() -> void:
	_current_slot = "indicators"
	var p := _part()
	if p.is_empty():
		_stock_indicators()
		return
	_indicator_slots.append("indicators")
	_indicator_set(str(p.get("style", "stalk")), [true, false])


## A bike with no indicators fitted still has the little stock pair a road bike leaves the
## factory with, where it can: small black stalks beside the headlight (not behind a fairing, which
## would hide them) and beside the rear light, drawn as part of those so they come and go with
## them. Race and MX bikes have none.
func _stock_indicators() -> void:
	if _fit_only:
		return
	var frame_styles := PartsDB.styles_of(str(_build.parts.get("frame", "")))
	if not frame_styles.is_empty() and frame_styles.all(func(st): return st in ["race", "mx"]):
		return
	var front := not PartsDB.get_part(str(_build.parts.get("headlight", "none"))).is_empty() \
			and PartsDB.get_part(str(_build.parts.get("fairing", "none"))).is_empty()
	for slot in (["headlight"] if front else []) + (["tail"] if tail_light_position() != Vector3.ZERO else []):
		_current_slot = slot
		_indicator_slots.append(slot)
		var had: int = _slot_meshes[slot].size()
		_indicator_set("stalk", [slot == "headlight"], Color(0.05, 0.05, 0.055))
		# Left out of the part's size (see slot_bounds): they're not what the part measures.
		for mi in (_slot_meshes[slot] as Array).slice(had):
			_stock_pieces[mi] = true
	_current_slot = "indicators"


## Whether the bike has indicators to flash: a fitted set, or the stock ones on parts fitted now.
func has_indicators() -> bool:
	return _indicator_slots.any(func(slot): return is_fitted(slot))


## The amber lens for one side's indicators (-1 left, 1 right), made the first time.
func _indicator_lens(side: float) -> StandardMaterial3D:
	var group := "ind_l" if side < 0.0 else "ind_r"
	for l in _lamps:
		if l["group"] == group:
			return l["mat"]
	return _lamp(Color(1.0, 0.5, 0.05), INDICATOR_ENERGY, group)


## A pair of indicators, one a side, at the front (`ends` has true: on the bars) and/or the back
## (false), in a style ("stalk", "bullet", "mini", "flush" or "touring"). `colour` is the
## body's, else the part's own.
func _indicator_set(style: String, ends: Array, colour := Color(0, 0, 0, 0)) -> void:
	var chrome := style == "bullet"
	var body := _mat(colour if colour.a > 0.0 else _col(), 1.0 if chrome else 0.2, 0.15 if chrome else 0.5)
	var black := _mat(Color(0.05, 0.05, 0.055), 0.1, 0.7)
	var rear := tail_light_position()
	if rear == Vector3.ZERO:
		rear = _tail + Vector3(0.0, -0.04, 0.12)
	var reach: float = {"stalk": 0.09, "bullet": 0.07, "mini": 0.05, "flush": 0.0, "touring": 0.13}.get(style, 0.08)
	for side in [-1.0, 1.0]:
		var amber := _indicator_lens(side)
		for front in ends:
			var parent: Node3D = _steer_node if front else self
			var base := Vector3(0.08 * side, -0.05, -0.08) if front else rear + Vector3(0.05 * side, -0.02, -0.04)
			var face := -1.0 if front else 1.0   # the lens looks forward at the front, back at the rear
			var tip := base + Vector3(reach * side, 0.0, 0.0)
			match style:
				"flush":
					tip = Vector3(0.075 * side, -0.08, -0.17) if front else rear + Vector3(0.06 * side, 0.0, 0.0)
					_box(tip, Vector3(0.035, 0.012, 0.01), amber, parent)
				"bullet":
					_tube(base, tip, 0.005, body, Vector3.ONE, parent)
					var shell := _mesh_instance(_sphere(0.018), body, tip, parent)
					shell.scale = Vector3(1.0, 1.0, 1.7)
					var lens := _mesh_instance(_sphere(0.015), amber, tip + Vector3(0.0, 0.0, 0.022 * face), parent)
					lens.scale = Vector3(1.0, 1.0, 0.6)
				"mini":
					_tube(base, tip, 0.004, black, Vector3.ONE, parent)
					_box(tip, Vector3(0.012, 0.012, 0.028), black, parent)
					_box(tip + Vector3(0.0, 0.0, 0.015 * face), Vector3(0.011, 0.011, 0.004), amber, parent)
				"touring":
					_tube(base, tip, 0.008, black, Vector3.ONE, parent)
					_box(tip, Vector3(0.07, 0.05, 0.04), body, parent)
					_box(tip + Vector3(0.0, 0.0, 0.021 * face), Vector3(0.064, 0.044, 0.004), amber, parent)
				_:
					_tube(base, tip, 0.007, black, Vector3.ONE, parent)
					_box(tip, Vector3(0.045, 0.032, 0.03), black, parent)
					_box(tip + Vector3(0.0, 0.0, 0.016 * face), Vector3(0.042, 0.03, 0.006), amber, parent)


## Where the race numbers go on boards and plates: the same number all over one bike.
func _race_number() -> String:
	return str(1 + absi(hash(str(paint))) % 99)


## A race number printed on a plate, facing out along `normal` (its own +Z after the turn).
func _number_on(plate: Node3D, normal: Vector3, height: float, ink := Color(0.05, 0.05, 0.06)) -> void:
	var label := Label3D.new()
	label.text = _race_number()
	label.font_size = 64
	label.pixel_size = height / 64.0
	label.modulate = ink
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	plate.add_child(label)
	# Placed in the plate's parent space, then brought into the plate's own (which may be turned
	# and stretched into an oval).
	var want := Transform3D(Basis.looking_at(-normal, Vector3.UP), plate.position + normal * 0.008)
	label.transform = plate.transform.affine_inverse() * want


## Side panels in the triangle under the seat, over the battery and wiring: painted classic
## triangles, oval number panels, MX side plates, sculpted sports cowls or a chrome cover.
func _draw_side_panels() -> void:
	_current_slot = "side_panels"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "triangle"))
	var shiny := style == "chrome"
	var metal := str(p.get("material", "")) == "metal"
	var mat := _mat(_col(), 1.0 if shiny else (0.35 if metal else 0.1), 0.12 if shiny else 0.35, 0.0 if shiny else 0.5)
	var c := Vector3(0.0, lerpf(_pivot.y, _seat_y, 0.55), _pivot.z + 0.07)
	var h := clampf((_seat_y - _pivot.y) * 0.62, 0.1, 0.24)
	for side in [-1.0, 1.0]:
		var at := c + Vector3(0.115 * side, 0.0, 0.0)
		match style:
			"oval":
				var disc := _mesh_instance(_cylinder(h * 0.5, 0.012), mat, at, self)
				disc.basis = Basis(Vector3.BACK, PI * 0.5 * side) * Basis.from_scale(Vector3(1.0, 1.0, 1.35))
				_number_on(disc, Vector3(side, 0.0, 0.0), h * 0.55)
			"mx":
				var plate := _box(at + Vector3(0.012 * side, -0.01, 0.1), Vector3(0.01, h * 1.15, 0.34), mat)
				plate.rotation.x = -0.18
			"cowl":
				var cowl := _box(at + Vector3(0.008 * side, 0.03, -0.03), Vector3(0.014, h * 0.85, 0.36), mat)
				cowl.rotation.x = 0.32
				_box(at + Vector3(0.016 * side, -h * 0.25, -0.02), Vector3(0.006, 0.02, 0.3), _mat(Color(0.85, 0.86, 0.88), 0.9, 0.2))
			"chrome":
				var cover := _mesh_instance(_cylinder(h * 0.45, 0.02), mat, at + Vector3(0.01 * side, -0.01, -0.02), self)
				cover.basis = Basis(Vector3.BACK, PI * 0.5 * side) * Basis.from_scale(Vector3(1.0, 1.0, 1.2))
			_:
				# A classic's pressed-steel side cover (a Bonneville's): a domed, round-cornered
				# panel, taller at the front, under the nose of the seat, with a little badge.
				var secs := []
				for k in 6:
					var f := k / 5.0
					var tall := h * lerpf(1.0, 0.7, f) * (0.75 + 0.25 * sin(PI * clampf(f * 1.2, 0.0, 1.0)))
					secs.append({"c": at + Vector3(0.006 * side * sin(f * PI), lerpf(0.0, h * 0.12, f), lerpf(-0.1, 0.1, f)),
						"w": 0.012, "up": tall * 0.5, "down": tall * 0.5, "n": 4.0})
				var panel := _shell(secs, mat)
				panel.name = "SideCover"
				var badge := _mesh_instance(_cylinder(0.022, 0.006), _mat(Color(0.86, 0.87, 0.89), 1.0, 0.15), at + Vector3(0.02 * side, 0.01, -0.02), self)
				badge.basis = Basis(Vector3.BACK, PI * 0.5 * side) * Basis.from_scale(Vector3(1.0, 1.0, 1.5))


## The footpegs, pedal and gear lever where the rearsets put them (see build_from: a set with a
## "peg" moves the rider's feet): plain rubber pegs, billet rearsets up and back, cleated MX
## pegs, forward controls out in front, or footboards.
func _draw_rearsets() -> void:
	_current_slot = "rearsets"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "road"))
	var mat := _skin(_mat(_col(), 0.9 if style in ["rearset", "forward", "cleat"] else 0.3, 0.2 if style != "boards" else 0.7))
	var black := _mat(Color(0.04, 0.04, 0.045), 0.1, 0.8)
	var hanger := _mat(Color(0.12, 0.12, 0.13), 0.8, 0.3)
	for side in [-1.0, 1.0]:
		var peg := Vector3(_peg.x * side, _peg.y, _peg.z)
		var root := Vector3(0.1 * side, _pivot.y - 0.02, _pivot.z - 0.03)
		match style:
			"forward":
				var mount := Vector3(0.08 * side, _peg.y + 0.02, _peg.z + 0.08)
				_tube(mount, peg, 0.012, mat)
				var stub := _tube(peg - Vector3(0.04 * side, 0.0, 0.0), peg + Vector3(0.05 * side, 0.0, 0.0), 0.016, black)
				stub.name = "Footpeg"
				_tube(peg + Vector3(-0.02 * side, 0.0, -0.02), peg + Vector3(-0.02 * side, 0.08, -0.08), 0.008, mat)
			"boards":
				_tube(Vector3(0.08 * side, _peg.y + 0.01, _peg.z), Vector3(0.14 * side, _peg.y, _peg.z), 0.01, hanger)
				var board := _box(Vector3(0.2 * side, _peg.y, _peg.z), Vector3(0.12, 0.022, 0.27), black)
				board.name = "Footpeg"
				_box(Vector3(0.2 * side, _peg.y - 0.014, _peg.z), Vector3(0.124, 0.008, 0.275), mat)
			"rearset":
				_box((peg + root) * 0.5 + Vector3(0.015 * side, 0.0, 0.0), Vector3(0.01, absf(peg.y - root.y) + 0.07, absf(peg.z - root.z) + 0.07), mat)
				var stub := _tube(peg - Vector3(0.02 * side, 0.0, 0.0), peg + Vector3(0.07 * side, 0.0, 0.0), 0.011, mat)
				stub.name = "Footpeg"
				for k in 4:
					_tube(peg + Vector3((0.01 + k * 0.016) * side, -0.012, 0.0), peg + Vector3((0.01 + k * 0.016) * side, 0.012, 0.0), 0.012, black)
				_tube(peg + Vector3(0.0, -0.01, 0.0), peg + Vector3(-0.005 * side, -0.02, -0.13), 0.006, mat)
			"cleat":
				_box((peg + root) * 0.5, Vector3(0.012, absf(peg.y - root.y) + 0.06, 0.06), hanger)
				var cleat := _box(peg + Vector3(0.015 * side, 0.0, 0.0), Vector3(0.11, 0.018, 0.055), mat)
				cleat.name = "Footpeg"
				for k in 3:
					_box(peg + Vector3((-0.025 + k * 0.035) * side, 0.013, 0.0), Vector3(0.006, 0.01, 0.058), mat)
				_tube(peg + Vector3(-0.03 * side, -0.01, 0.0), peg + Vector3(-0.03 * side, -0.02, -0.14), 0.007, mat)
			_:
				if absf(peg.y - root.y) > 0.04 or absf(peg.z - root.z) > 0.06:
					_box((peg + root) * 0.5, Vector3(0.012, absf(peg.y - root.y) + 0.06, 0.06), hanger)
				var rubber := _box(peg + Vector3(0.01 * side, 0.0, 0.0), Vector3(0.1, 0.024, 0.038), black)
				rubber.name = "Footpeg"
				_tube(peg + Vector3(-0.03 * side, 0.0, 0.0), peg + Vector3(-0.03 * side, -0.03, -0.15), 0.007, hanger)


## Engine guards: chrome bars round the front of the engine, a full adventure cage up round the
## tank, an alloy bash plate or an MX skid plate under it, or nylon frame sliders. They stand off
## the engine by its own width, so a boxer's bars go out round its cylinders.
func _draw_guards() -> void:
	_current_slot = "guards"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "bars"))
	var shiny := style == "bars"
	var mat := _skin(_mat(_col(), 1.0 if shiny else (0.85 if style == "plate" else 0.2), 0.12 if shiny else 0.35))
	var s := _eng_s
	var out := _block_w * 0.5 + 0.07
	if _build.layout == "boxer":
		out = maxf(out, 0.36 * s + 0.06)
	var bottom := _engine_c.y - 0.13 * s
	var nose := _engine_c.z - 0.17 * s
	match style:
		"bars", "cage":
			for side in [-1.0, 1.0]:
				_bend([_head_bottom + Vector3(0.05 * side, -0.06, 0.04), Vector3(out * 0.8 * side, _engine_c.y + 0.12 * s, nose - 0.04),
					Vector3(out * side, _engine_c.y, nose + 0.02), Vector3(out * 0.85 * side, bottom + 0.02, nose + 0.08),
					Vector3(0.08 * side, bottom - 0.03, nose + 0.14)], 0.013 if shiny else 0.015, mat)
				if style == "cage":
					# Up round the tank and back to the frame under the seat.
					_bend([_head_bottom + Vector3(0.05 * side, 0.0, 0.03), _head + Vector3(0.2 * side, -0.16, 0.22),
						_seat_front + Vector3(0.18 * side, -0.12, -0.12), _seat_front + Vector3(0.1 * side, -0.16, 0.0)], 0.014, mat)
					_tube(Vector3(out * side, _engine_c.y, nose + 0.02), _head + Vector3(0.2 * side, -0.16, 0.22), 0.012, mat)
			if style == "cage":
				_tube(Vector3(-0.08, bottom - 0.03, nose + 0.14), Vector3(0.08, bottom - 0.03, nose + 0.14), 0.013, mat)
		"plate", "skid":
			var w := 0.24 if style == "plate" else 0.19
			var tray := _box(Vector3(0.0, bottom - 0.035, _engine_c.z + 0.02), Vector3(w, 0.01 if style == "plate" else 0.014, 0.34 * s + 0.08), mat)
			tray.rotation.x = -0.05
			_plank(Vector3(0.0, bottom - 0.03, nose - 0.03), Vector3(0.0, bottom + 0.06, nose - 0.08), w * 0.9, 0.01, mat)
			if style == "plate":
				for side in [-1.0, 1.0]:
					_box(Vector3(w * 0.5 * side, bottom - 0.01, _engine_c.z + 0.02), Vector3(0.008, 0.05, 0.3 * s + 0.06), mat)
		_:
			for side in [-1.0, 1.0]:
				for at in [Vector3(out * 0.8 * side, _engine_c.y + 0.1 * s, nose + 0.06), Vector3(0.11 * side, _pivot.y + 0.06, _pivot.z - 0.04)]:
					var bob := _mesh_instance(_cylinder(0.022, 0.05), mat, at + Vector3(0.012 * side, 0.0, 0.0), self)
					bob.rotation.z = PI * 0.5


## Number boards: an MX front plate with side boards under the seat, a single front race plate,
## radiator shrouds either side of the tank, oval club-racer plates on the nose and the tail, or
## big yellow flat-track side boards. Each carries the bike's race number (see _race_number).
func _draw_number_boards() -> void:
	_current_slot = "number_boards"
	var p := _part()
	if p.is_empty():
		return
	var style := str(p.get("style", "mx"))
	var mat := _mat(_col(), 0.0 if style != "oval" else 0.5, 0.45)
	var side_at := Vector3(0.0, _seat_y - 0.1, lerpf(_seat_front.z, _tail.z, 0.62))
	if style in ["mx", "front", "oval"]:
		var plate: MeshInstance3D
		if style == "oval":
			plate = _mesh_instance(_cylinder(0.1, 0.008), mat, Vector3(0.0, -0.02, -0.2), _steer_node)
			plate.basis = Basis(Vector3.RIGHT, PI * 0.5 + 0.15) * Basis.from_scale(Vector3(1.25, 1.0, 1.0))
		else:
			plate = _box(Vector3(0.0, -0.05, -0.2), Vector3(0.22, 0.21, 0.008), mat, _steer_node)
			plate.rotation.x = 0.22
		_number_on(plate, Vector3(0.0, 0.2, -1.0).normalized(), 0.11)
	match style:
		"mx", "tracker":
			for side in [-1.0, 1.0]:
				var board: MeshInstance3D
				if style == "tracker":
					board = _mesh_instance(_cylinder(0.12, 0.01), mat, side_at + Vector3(0.14 * side, 0.0, 0.0), self)
					board.basis = Basis(Vector3.BACK, PI * 0.5 * side) * Basis.from_scale(Vector3(1.0, 1.0, 1.4))
				else:
					board = _box(side_at + Vector3(0.14 * side, 0.0, 0.0), Vector3(0.008, 0.19, 0.27), mat)
					board.rotation.x = -0.12
				_number_on(board, Vector3(side, 0.0, 0.0), 0.12)
		"shrouds":
			for side in [-1.0, 1.0]:
				var wing := _box(_head + Vector3(0.16 * side, -0.2, 0.2), Vector3(0.01, 0.2, 0.24), mat)
				wing.basis = Basis(Vector3.UP, -0.3 * side) * Basis(Vector3.RIGHT, 0.35)
				_box(_head + Vector3(0.165 * side, -0.27, 0.16), Vector3(0.012, 0.03, 0.18), _mat(Color(0.05, 0.05, 0.06), 0.1, 0.6))
		"oval":
			var back := _mesh_instance(_cylinder(0.08, 0.008), mat, _tail + Vector3(0.0, 0.06, 0.2), self)
			back.basis = Basis(Vector3.RIGHT, PI * 0.5 - 0.25) * Basis.from_scale(Vector3(1.25, 1.0, 1.0))
			_number_on(back, Vector3(0.0, 0.25, 1.0).normalized(), 0.09)


## The steering damper: a linear one is an oil-filled body along the left of the frame with its
## rod out to the bottom yoke; a rotary one sits on the top yoke with a link back to the frame;
## an old friction damper is a knob under the steering head.
func _draw_steering_damper() -> void:
	_current_slot = "steering_damper"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.7, 0.3)
	var rod_mat := _mat(Color(0.82, 0.83, 0.85), 0.9, 0.15)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.3, 0.5)
	match str(p.get("style", "linear")):
		"linear":
			# The body sits along the frame under the tank's edge, the rod's eye on the bottom yoke
			# turns with the bars.
			var back := _head_bottom + Vector3(0.14, -0.025, 0.25)
			var front := _head_bottom + Vector3(0.14, -0.02, 0.1)
			_tube(back, front, 0.016, mat)
			_mesh_instance(_sphere(0.013), dark, back)
			var to_steer := _steer_node.transform.affine_inverse()
			var eye_at := to_steer * (_head_bottom + Vector3(0.11, -0.02, -0.03))
			_tube(to_steer * front, eye_at, 0.006, rod_mat, Vector3.ONE, _steer_node)
			_mesh_instance(_sphere(0.011), dark, eye_at, _steer_node)
		"rotary":
			var puck := _mesh_instance(_cylinder(0.035, 0.022), mat, Vector3(0.0, 0.04, 0.05), _steer_node)
			puck.basis = Basis(Vector3.RIGHT, atan2(_steer_axis.z, _steer_axis.y))   # flat on the yoke
			_mesh_instance(_cylinder(0.008, 0.012), dark, Vector3(0.0, 0.057, 0.05), _steer_node)
			# The link back to its bracket on the frame.
			_tube(_head + Vector3(0.0, 0.02, 0.06), _head + Vector3(0.0, 0.0, 0.16), 0.006, rod_mat)
		_:
			_mesh_instance(_cylinder(0.022, 0.018), mat, _head_bottom + Vector3(0.0, -0.05, 0.02))
			_mesh_instance(_cylinder(0.006, 0.05), rod_mat, _head_bottom + Vector3(0.0, -0.02, 0.02))


## Lever guards: a hoop off the bar end that curves round in front of the lever's tip, so a
## knock (or another bike's bars) can't pull the lever on or snap it. A "brake" one guards only
## the front brake lever on the right; a "pair" guards the clutch lever too. Each bolts into the
## bar end with a round boss over the bar-end weight.
func _draw_lever_guards() -> void:
	_current_slot = "lever_guards"
	var p := _part()
	if p.is_empty():
		return
	var carbon := str(p.get("material", "metal")) == "carbon"
	var mat := _tex(_mat(_col(), 0.2, 0.3), "carbon") if carbon else _tex(_mat(_col(), 0.85, 0.25), "brushed", -1.0, 0.5)
	var sides := [1.0, -1.0] if str(p.get("style", "brake")) == "pair" else [1.0]
	for side in sides:
		var bar_end: Vector3 = (_grip_r if side > 0.0 else _grip_l) + Vector3(0.05 * side, 0.0, 0.0)
		var boss := _mesh_instance(_cylinder(0.019, 0.016), mat, bar_end + Vector3(0.026 * side, 0.0, 0.0), _steer_node)
		boss.rotation.z = PI * 0.5
		# Out from the boss, forward past the lever's tip and back in across the front of it.
		var hoop := _bend([bar_end + Vector3(0.03 * side, -0.004, -0.012), bar_end + Vector3(0.042 * side, -0.01, -0.05),
			bar_end + Vector3(0.024 * side, -0.014, -0.082), bar_end + Vector3(-0.045 * side, -0.014, -0.09)], 0.0065, mat, _steer_node, 8)
		hoop.name = "LeverGuard"


## The side stand on the left, under the footpeg: tucked up along the frame, or down on the
## ground with the bike leaning over onto it.
func _draw_side_stand(build: BikeBuild) -> void:
	_current_slot = "side_stand"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.6, 0.4)
	var pivot := Vector3(-0.12, -0.04, _pivot.z - 0.16)
	var length := float(p.get("length", 0.3))
	var foot: Vector3
	if stand_pose == "side":
		# Swing the leg out until it reaches the ground with the bike leaned over by the stand's lean.
		var lean := deg_to_rad(float(p.get("lean", 12.0)))
		var height := pivot.y + build.rear_radius
		var best := 0.0
		var best_err := INF
		for i in 90:
			var a := deg_to_rad(float(i))
			var fx := pivot.x - length * sin(a)
			var fy := height - length * cos(a)
			var err := absf(fy * cos(lean) + fx * sin(lean))
			if err < best_err:
				best_err = err
				best = a
		foot = pivot + Vector3(-length * sin(best), -length * cos(best), -0.06)
	else:
		foot = pivot + Vector3(-0.03, -0.04, length * 0.95)
	_tube(pivot, foot, 0.012, mat)
	var pad := _box(foot, Vector3(0.05, 0.012, 0.07), mat)
	pad.name = "StandFoot"
	_box(pivot, Vector3(0.03, 0.04, 0.04), mat)


## The centre stand under the engine: two legs and a foot lever, swung down to lift the
## back wheel off the ground, or folded up behind.
func _draw_centre_stand(build: BikeBuild) -> void:
	_current_slot = "centre_stand"
	var p := _part()
	if p.is_empty():
		return
	var mat := _mat(_col(), 0.6, 0.4)
	var z := _pivot.z - 0.08
	var reach := build.rear_radius - 0.06 + float(p.get("lift", 0.04))
	for side in [-1.0, 1.0]:
		var top := Vector3(0.1 * side, -0.06, z)
		var foot := top + (Vector3(0.02 * side, -reach, -0.02) if stand_pose == "centre" else Vector3(0.0, -0.08, reach * 0.9))
		_tube(top, foot, 0.013, mat)
		_box(foot, Vector3(0.05, 0.012, 0.06), mat)
	var bar_z := z - 0.02 if stand_pose == "centre" else z + reach * 0.9
	var bar_y := -0.06 - reach if stand_pose == "centre" else -0.14
	_tube(Vector3(-0.1, bar_y + 0.04, bar_z), Vector3(0.1, bar_y + 0.04, bar_z), 0.01, mat)
	_tube(Vector3(-0.1, bar_y + 0.04, bar_z), Vector3(-0.2, bar_y + 0.08, bar_z + 0.05), 0.01, mat)


# ---------------------------------------------------------------------------- wheels and brakes

## A rim's width across its bead seats, in metres, from the wheel part's rim width in inches.
static func rim_width_of(wheel: Dictionary) -> float:
	return float(wheel.get("rim_width", 3.5)) * 0.0254


## The rim: a barrel `rim_w` wide between two flanges the tyre's beads sit inside, and the spokes.
func _draw_rim(wheel: Node3D, rim_r: float, rim_w: float) -> void:
	var p := _part()
	var style := str(p.get("style", "cast"))
	var rim_mat := _skin(_mat(_col(), 0.9 if style != "carbon" else 0.2, 0.25, 0.8 if style == "carbon" else 0.0))
	if style == "carbon" and _surface() == "":
		_tex(rim_mat, "carbon")
	var chrome := _mat(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	# A look can polish the rim lip, change the spokes' finish, cover the wheel in a moon disc,
	# split cast spokes into pairs, add a rim stripe or a big finned drum hub.
	var lk := _look()
	var lip := _look_finish(str(lk.get("lip", "")), rim_mat)
	var spoke_mat := _look_finish(str(lk.get("spoke_finish", "")), chrome)
	# The barrel is open at the sides, so it's drawn from both faces.
	var barrel_mat := rim_mat.duplicate() as StandardMaterial3D
	barrel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrel := _mesh_instance(_cylinder(rim_r - 0.004, rim_w, -1.0, 40), barrel_mat, Vector3.ZERO, wheel)
	(barrel.mesh as CylinderMesh).cap_top = false
	(barrel.mesh as CylinderMesh).cap_bottom = false
	barrel.rotation.z = PI * 0.5
	barrel.set_meta("hoop", Vector3(rim_r - 0.03, rim_r, rim_w))
	for side in [-1.0, 1.0]:
		var flange := TorusMesh.new()
		flange.inner_radius = rim_r - 0.012
		flange.outer_radius = rim_r + 0.009
		flange.rings = 40
		flange.ring_segments = 8
		var f := _mesh_instance(flange, lip, Vector3(side * rim_w * 0.5, 0.0, 0.0), wheel)
		f.rotation.z = PI * 0.5
		f.scale = Vector3(1.0, 0.4, 1.0)
	if lk.has("stripe"):
		var sc: Array = lk["stripe"]
		var tape := _mat(Color(float(sc[0]), float(sc[1]), float(sc[2])), 0.2, 0.4, 0.5)
		for side in [-1.0, 1.0]:
			var t := _mesh_instance(_torus(rim_r - 0.016, 0.003), tape, Vector3(side * (rim_w * 0.5 + 0.002), 0.0, 0.0), wheel)
			t.rotation.z = PI * 0.5
	if lk.get("disc", false):
		# Moon discs: smooth domed covers over both sides of the wheel.
		var cover := _look_finish(str(lk.get("disc_finish", "")), rim_mat)
		for side in [-1.0, 1.0]:
			var d := _mesh_instance(_cylinder(rim_r - 0.012, 0.012, rim_r * 0.4, 40), cover, Vector3(side * rim_w * 0.42, 0.0, 0.0), wheel)
			d.rotation.z = -PI * 0.5 * side
			d.name = "MoonDisc"
	elif style == "spoked" or style == "wire":
		var count := int(lk.get("spokes", p.get("spokes", 36 if style == "wire" else 18)))
		for i in count:
			var a := TAU * i / count
			var spoke := _tube(Vector3(0.025 * (1 if i % 2 == 0 else -1), 0.0, 0.0),
				Vector3(0.0, cos(a), sin(a)) * (rim_r - 0.02), 0.003 if style == "spoked" else 0.0022, spoke_mat, Vector3.ONE, wheel)
			spoke.name = "Spoke%d" % i
	else:
		var spokes := int(p.get("spokes", 3 if style == "carbon" else 5))
		# Fewer spokes are chunkier; a "y" wheel splits each spoke in two near the rim.
		var thick := clampf(0.12 / spokes, 0.016, 0.04)
		var depth := clampf(rim_w * 0.45, 0.03, 0.05)
		for i in spokes:
			var a := TAU * i / spokes
			if lk.get("split", false):
				for split in [-0.09, 0.09]:
					var b: float = a + split
					var arm := _box(Vector3(0.0, cos(b), sin(b)) * rim_r * 0.5, Vector3(depth * 0.8, rim_r * 0.95, thick * 0.5), rim_mat, wheel)
					arm.rotation.x = -b
			elif style == "y":
				_box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.3, Vector3(depth * 0.65, rim_r * 0.55, 0.022), rim_mat, wheel).rotation.x = -a
				for split in [-0.2, 0.2]:
					var b: float = a + split
					var arm := _box(Vector3(0.0, cos(a), sin(a)) * rim_r * 0.55 + Vector3(0.0, cos(b), sin(b)) * rim_r * 0.2,
						Vector3(depth * 0.5, rim_r * 0.45, 0.016), rim_mat, wheel)
					arm.rotation.x = -(a + split * 0.5)
			else:
				# A cast spoke: thick at the hub, tapering and sweeping a touch as it reaches the
				# rim, with a fillet where it meets each end.
				var path := []
				for f in [0.0, 0.3, 0.65, 1.0]:
					var b: float = a + 0.07 * sin(f * PI)
					path.append(Vector3(0.0, cos(b), sin(b)) * lerpf(0.045, rim_r - 0.01, f))
				var spoke := _bend(path, [thick * 0.85, thick * 0.6, thick * 0.5, thick * 0.62], rim_mat, wheel, 10)
				spoke.scale = Vector3(depth / thick * 0.7, 1.0, 1.0)
				spoke.name = "CastSpoke%d" % i
	if _current_slot == "rear_wheel":
		# The cush drive carrying the sprocket: rubber blocks in a cast carrier.
		var carrier := _mesh_instance(_cylinder(0.07, 0.03), rim_mat, Vector3(-0.092, 0.0, 0.0), wheel)
		carrier.rotation.z = PI * 0.5
		carrier.name = "CushDrive"
		_bolt_ring(Vector3(-0.108, 0.0, 0.0), Vector3.LEFT, 0.052, 6, _mat(Color(0.6, 0.61, 0.64), 1.0, 0.3), wheel)
	# The tyre valve poking through the rim.
	var valve := _tube(Vector3(0.0, rim_r - 0.012, 0.0), Vector3(0.0, rim_r - 0.05, 0.0), 0.004, _mat(Color(0.05, 0.05, 0.05), 0.0, 0.7), Vector3.ONE, wheel)
	valve.name = "Valve"
	var hub_kind := str(lk.get("hub", ""))
	var hub := _mesh_instance(_cylinder(0.09 if hub_kind == "drum" else 0.05, 0.14 if hub_kind != "drum" else 0.12), _look_finish(str(lk.get("hub_finish", "")), chrome), Vector3.ZERO, wheel)
	hub.rotation.z = PI * 0.5
	if hub_kind == "drum":
		# A big finned drum brake hub, with its torque arm stub.
		for k in 4:
			var fin := _mesh_instance(_torus(0.088, 0.006), chrome, Vector3(-0.045 + k * 0.03, 0.0, 0.0), wheel)
			fin.rotation.z = PI * 0.5
		var plate := _mesh_instance(_cylinder(0.085, 0.02), _mat(Color(0.3, 0.3, 0.32), 0.9, 0.35), Vector3(-0.07, 0.0, 0.0), wheel)
		plate.rotation.z = PI * 0.5


## The tyre, drawn to its size: `width` is its section width and its height off the rim
## (radius - rim_r) comes from its profile, so a 180/55 is 180 mm wide and 99 mm tall. Its
## beads sit inside the rim's flanges, `rim_w` apart.
func _draw_tyre(wheel: Node3D, rim_r: float, radius: float, width: float, rim_w: float) -> void:
	var style := str(_part().get("style", "road"))
	var rubber := _mat(_col(), 0.0, 0.88)
	rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Rubber never rusts (its road dirt is drawn over it, see DirtLayer), so a tired tyre still
	# reads black in a low warm sun. A little less specular than the default keeps the sunset's
	# glow off the sidewalls.
	rubber.detail_enabled = false
	rubber.albedo_color = _col()
	rubber.roughness = 0.88
	rubber.metallic = 0.0
	rubber.metallic_specular = 0.3
	var tyre_mi := _mesh_instance(tyre_mesh(rim_r, radius, width, rim_w, style), rubber, Vector3.ZERO, wheel)
	tyre_mi.rotation.z = PI * 0.5
	tyre_mi.set_meta("hoop", Vector3(rim_r, radius, width))
	var wall = _look().get("wall")
	if wall is Array and (wall as Array).size() >= 3:
		# A whitewall (or a coloured wall stripe) round both sidewalls.
		var wm := _mat(Color(float(wall[0]), float(wall[1]), float(wall[2])), 0.0, 0.7)
		# Laid on the outside of the wall at its widest point (40% of the way up, where the
		# section bulges to the full width), standing a hair proud of the rubber so it reads
		# as a painted band rather than something sunk inside the tyre.
		var mid := lerpf(rim_r, radius, 0.42)
		for side in [-1.0, 1.0]:
			var band := _mesh_instance(_torus(mid, (radius - rim_r) * float(_look().get("wall_w", 0.18))), wm, Vector3(side * (width * 0.5 + 0.0012), 0.0, 0.0), wheel)
			band.rotation.z = PI * 0.5
			band.scale = Vector3(1.0, 0.12, 1.0)
			band.name = "WallBand"
	_tyre_lettering(tyre_mi, rim_r, radius, width)
	# The tread: knobs on an off-road tyre (bigger, flatter blocks on a 50/50 adventure one, studs
	# in them on a studded one), fine sipes cut across a winter tyre; a road tyre is smooth.
	var tread := str(_part().get("tread", "knobs" if style == "offroad" else ""))
	if tread == "":
		return
	if tread == "sipes":
		_tread_ring(wheel, radius, Vector3(width * 0.72, 0.003, 0.004), 72, 0.0015, 0.0, _mat(Color(0.015, 0.015, 0.015), 0.0, 0.95))
		return
	var blocks := tread == "blocks"
	var size := Vector3(width * 0.42, 0.012, 0.045) if blocks else Vector3(width * 0.36, 0.022, 0.03)
	var placed := _tread_ring(wheel, radius, size, 56 if blocks else 80, 0.008 if not blocks else 0.004, width * (0.2 if blocks else 0.19), rubber)
	if tread == "studs":
		# A tungsten stud in the top of every knob.
		var stud := CylinderMesh.new()
		stud.top_radius = 0.0035
		stud.bottom_radius = 0.0035
		stud.height = 0.006
		stud.radial_segments = 6
		var studs := MultiMesh.new()
		studs.transform_format = MultiMesh.TRANSFORM_3D
		studs.mesh = stud
		studs.instance_count = placed.size()
		var stud_at: Array[Transform3D] = []
		for i in placed.size():
			var t := placed[i].translated_local(Vector3(0.0, size.y * 0.5 + 0.002, 0.0))
			studs.set_instance_transform(i, t)
			stud_at.append(t)
		var smi := MultiMeshInstance3D.new()
		smi.set_meta("instances", stud_at)
		smi.multimesh = studs
		smi.material_override = _mat(Color(0.7, 0.72, 0.75), 1.0, 0.25)
		wheel.add_child(smi)
		_slot_meshes[_current_slot].append(smi)


## A ring of tread pieces (`size` each, `count` of them, staggered `stagger` either side of the
## middle and sunk `sink` into the rubber) round a tyre of `radius`, as one multimesh. Returns
## where each piece went.
func _tread_ring(wheel: Node3D, radius: float, size: Vector3, count: int, sink: float, stagger: float, mat: Material) -> Array[Transform3D]:
	var knobs := MultiMesh.new()
	knobs.transform_format = MultiMesh.TRANSFORM_3D
	var knob := BoxMesh.new()
	knob.size = size
	knobs.mesh = knob
	knobs.instance_count = count
	var placed: Array[Transform3D] = []
	var rows := count / 2
	for i in count:
		var a := TAU * (i / 2) / rows + (PI / rows if i % 2 else 0.0)
		var t := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0.0, cos(a), sin(a)) * (radius - sink))
		t = t.translated_local(Vector3((stagger if i % 2 == 0 else -stagger), 0.0, 0.0))
		knobs.set_instance_transform(i, t)
		placed.append(t)
	var mmi := MultiMeshInstance3D.new()
	# Kept on the node too: a headless run (the .glb exporter, GlbExport) can't read them back.
	mmi.set_meta("instances", placed)
	mmi.multimesh = knobs
	mmi.material_override = mat
	wheel.add_child(mmi)
	_slot_meshes[_current_slot].append(mmi)
	return placed


## A flat tyre squashed down under its rim, 0 (holding its shape) .. 1 (no air in it, see
## Puncture): the bottom of the tyre flattened onto the ground the rim has sunk towards, and the
## sidewalls bulging out round it. The squashed tyre is held still while the rim turns inside it
## (see update_pose_from), so the flat stays at the bottom.
func set_flat(side: String, amount: float) -> void:
	var wheel := _front_wheel if side == "front" else _rear_wheel
	if wheel == null or _build == null:
		return
	var tyre_mi: MeshInstance3D = null
	for c in wheel.get_children():
		if c is MeshInstance3D and c.has_meta("hoop"):
			tyre_mi = c
			break
	if tyre_mi == null:
		return
	if absf(float(tyre_mi.get_meta("flat", 0.0)) - amount) < 0.02 and (amount > 0.02) == _flat_tyres.has(side):
		return
	if not tyre_mi.has_meta("round"):
		tyre_mi.set_meta("round", tyre_mi.mesh)
	var round_mesh: Mesh = tyre_mi.get_meta("round")
	tyre_mi.set_meta("flat", amount)
	if amount <= 0.02:
		tyre_mi.mesh = round_mesh
		tyre_mi.rotation.x = 0.0
		_flat_tyres.erase(side)
		return
	var hoop: Vector3 = tyre_mi.get_meta("hoop")
	# Squashed as it sits with the wheel still (it's held that way, see update_pose_from).
	var still := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, tyre_mi.rotation.z)), tyre_mi.position)
	tyre_mi.mesh = _squashed_tyre(round_mesh, still, hoop.x, hoop.y, amount)
	_flat_tyres[side] = tyre_mi


## How far a flat tyre lets its rim down towards the ground, metres (see Puncture).
static func flat_drop(build: BikeBuild, side: String) -> float:
	var front := side == "front"
	var h := (build.front_radius - build.front_rim_radius) if front else (build.rear_radius - build.rear_rim_radius)
	return float(build.flat.get(side, 0.0)) * Puncture.SQUASH * h


## A copy of a tyre's mesh squashed flat by `amount` (0..1), from where it sits on the wheel (`xf`).
static func _squashed_tyre(round_mesh: Mesh, xf: Transform3D, rim_r: float, radius: float, amount: float) -> ArrayMesh:
	var h := radius - rim_r
	var ground := -(radius - amount * Puncture.SQUASH * h)
	var inv := xf.affine_inverse()
	var out := ArrayMesh.new()
	for si in round_mesh.get_surface_count():
		var arrays := round_mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var p := xf * verts[i]
			var dist := Vector2(p.y, p.z).length()
			# Below the axle the sidewalls bulge out, most at mid-height, more the nearer the ground.
			if p.y < 0.0 and dist > rim_r:
				var low := clampf(-p.y / maxf(radius, 0.01), 0.0, 1.0)
				var wall := sin(PI * clampf((dist - rim_r) / maxf(h, 0.005), 0.0, 1.0))
				p.x *= 1.0 + 0.45 * amount * low * low * wall
			if p.y < ground:
				p.y = ground
			verts[i] = inv * p
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The maker's name and the size moulded into both sidewalls, in raised rubber a shade lighter
## than the tyre: "TORQUE RADIAL" over the top, "120/70 ZR17" under it. Every letter on a tyre
## goes into one mesh (its text kept in the "text" meta): drawn one by one, a bike's 88 letters
## were 88 more draw calls whenever it came within 9 m, which is why being a couple of metres
## from someone else's bike cost so much more than seeing it from further off.
func _tyre_lettering(tyre_mi: MeshInstance3D, rim_r: float, radius: float, width: float) -> void:
	var p := _part()
	var brand := str((p.get("look", {}) as Dictionary).get("brand", "TORQUE " + {"offroad": "TRAX", "slick": "RACE"}.get(str(p.get("style", "road")), "RADIAL")))
	var size := "%d/%d %sR%d" % [roundi(width * 1000.0), roundi((radius - rim_r) / maxf(width, 0.01) * 100.0 / 5.0) * 5,
		"Z" if str(p.get("style", "road")) != "offroad" else "", roundi(rim_r / 0.0127)]
	var ink := _col().lightened(0.28)
	var at_r := lerpf(rim_r, radius, 0.5)
	var st := SurfaceTool.new()
	var letters := 0
	for side in [-1.0, 1.0]:
		for line in [[brand, 0.0, 0.026], [size, PI, 0.018]]:
			var text: String = line[0]
			var centre: float = line[1]
			var px: float = line[2]
			var step := px * 0.75 / at_r
			for i in text.length():
				var ch := text.substr(i, 1)
				if ch == " ":
					continue
				# Laid round the wall: the top line reads left to right over the top, the
				# size line under the wheel the same way up.
				var off := (i - (text.length() - 1) * 0.5) * step
				var top_line: bool = centre == 0.0
				var a: float = centre + off * (-side if top_line else side)
				var glyph := _letter_mesh(ch, px)
				if glyph.get_surface_count() == 0:
					continue
				var up := Vector3(0.0, cos(a), sin(a)) * (1.0 if top_line else -1.0)
				var out := Vector3(side, 0.0, 0.0)
				st.append_from(glyph, 0, Transform3D(Basis(up.cross(out), up, out),
					Vector3(side * (width * 0.5 + 0.0015), cos(a) * at_r, sin(a) * at_r)))
				letters += 1
	# Hung off the tyre itself, so the lettering shows, hides and moves with it, but laid out
	# in the wheel's own space.
	var holder := MeshInstance3D.new()
	holder.name = "TyreLettering"
	holder.set_meta("text", brand + " " + size)
	if letters > 0:
		holder.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = ink
	m.roughness = 0.85
	holder.material_override = m
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.visibility_range_end = 9.0
	tyre_mi.add_child(holder)
	holder.transform = tyre_mi.transform.affine_inverse()


## One letter `ch`, `px` metres tall, facing +Z as a Label3D would (made once, then shared).
static func _letter_mesh(ch: String, px: float) -> Mesh:
	var key := "%s|%.4f" % [ch, px]
	if not _letters.has(key):
		var tm := TextMesh.new()
		tm.text = ch
		tm.font_size = 64
		tm.pixel_size = px / 64.0
		# Flat, as the labels were, and with coarse curves: a few dozen triangles a letter, not
		# a few hundred, for something 2 cm tall.
		tm.depth = 0.0
		tm.curve_step = 4.0
		var mesh := ArrayMesh.new()
		var arrays := tm.get_mesh_arrays()
		if not arrays.is_empty() and not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_letters[key] = mesh
	return _letters[key]


## A tyre as a solid of revolution round local Y, like a TorusMesh: its cross-section rises
## from the beads (inside the rim flanges, `rim_w` apart) and bulges out to the full section
## `width` low on the sidewall, then rounds over the tread to `radius`. Road and race tyres
## have a round crown to lean on; knobblies and tourers are squarer.
static func tyre_mesh(rim_r: float, radius: float, width: float, rim_w: float, style := "road", segments := 48) -> ArrayMesh:
	var h := maxf(radius - rim_r, 0.02)
	var half := width * 0.5
	var bead := minf(rim_w * 0.5 - 0.004, half * 0.9)
	var bulge_r := rim_r + h * 0.4
	var p := 2.0 if style in ["slick", "road"] else 2.8
	var prof: Array[Vector2] = []    # (radial, axial) from the right-hand bead over the crown
	var n := 6
	for i in n:
		var t := float(i) / n
		prof.append(Vector2(lerpf(rim_r - 0.006, bulge_r, 1.0 - cos(t * PI * 0.5)), lerpf(bead, half, sin(t * PI * 0.5))))
	var m := 10
	for i in m + 1:
		var th := float(i) / m * PI * 0.5
		var c := pow(cos(th), 2.0 / p)
		var sn := pow(sin(th), 2.0 / p)
		prof.append(Vector2(bulge_r + (rim_r + h - bulge_r) * sn, half * c))
	for i in range(prof.size() - 2, -1, -1):
		prof.append(Vector2(prof[i].x, -prof[i].y))
	var normals: Array[Vector2] = []
	for j in prof.size():
		var tangent := prof[mini(j + 1, prof.size() - 1)] - prof[maxi(j - 1, 0)]
		normals.append(Vector2(-tangent.y, tangent.x).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments + 1:
		var a := TAU * i / segments
		var ca := cos(a)
		var sa := sin(a)
		for j in prof.size():
			st.set_uv(Vector2(float(i) / segments, float(j) / (prof.size() - 1)))
			st.set_normal(Vector3(ca * normals[j].x, normals[j].y, sa * normals[j].x))
			st.add_vertex(Vector3(ca * prof[j].x, prof[j].y, sa * prof[j].x))
	var rows := prof.size()
	for i in segments:
		for j in rows - 1:
			var a0 := i * rows + j
			var b0 := (i + 1) * rows + j
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	return st.commit()


func _draw_brake(side: String, wheel: Node3D, hub: Node3D, rim_r: float, rim_w := 0.09) -> void:
	var front := side == "front"
	# The disc bolts on just outside the rim.
	var x := maxf(0.068 if front else 0.07, rim_w * 0.5 + 0.012)
	_current_slot = side + "_disc"
	var disc := _part()
	var disc_r := minf(float(disc.get("diameter", 280)) / 2000.0, rim_r - 0.03)
	var style := str(disc.get("style", "round"))
	if style == "drum":
		_draw_drum(side, wheel, hub, rim_r, x)
		return
	var steel := _tex(_mat(_col(), 1.0, 0.3), "brushed", 30.0, 0.5)
	var d := _mesh_instance(_cylinder(disc_r, 0.006, -1.0, 10 if style == "wave" else 32), steel, Vector3(x, 0.0, 0.0), wheel)
	d.rotation.z = PI * 0.5
	var bolt := _mat(Color(0.6, 0.61, 0.64), 1.0, 0.3)
	if style == "floating":
		var carrier := _mesh_instance(_cylinder(disc_r * 0.62, 0.008), _mat(Color(0.8, 0.62, 0.2), 0.9, 0.3), Vector3(x + 0.002, 0.0, 0.0), wheel)
		carrier.rotation.z = PI * 0.5
		# The floating buttons joining rotor to carrier.
		_bolt_ring(Vector3(x + 0.006, 0.0, 0.0), Vector3.RIGHT, disc_r * 0.66, 10, bolt, wheel)
	elif style == "drilled":
		var ring := _mesh_instance(_cylinder(disc_r * 0.55, 0.008), _mat(Color(0.2, 0.2, 0.22), 0.8, 0.4), Vector3(x + 0.002, 0.0, 0.0), wheel)
		ring.rotation.z = PI * 0.5
	_bolt_ring(Vector3(x + 0.004, 0.0, 0.0), Vector3.RIGHT, 0.045, 5, bolt, wheel)
	_current_slot = side + "_caliper"
	var pistons := int(_part().get("pistons", 2))
	var cal_size := Vector3(0.045, 0.06 + 0.008 * pistons, 0.07 + 0.01 * pistons)
	var cal_at := Vector3(x + 0.012, disc_r * 0.62, disc_r * 0.62 if front else -disc_r * 0.62)
	var cal := _box(cal_at, cal_size, _mat(_col(), 0.5, 0.35), hub)
	cal.rotation.x = -PI * 0.25 if front else PI * 0.25
	# Bleed nipple and the two mounting bolts.
	_mesh_instance(_cylinder(0.005, 0.016), bolt, cal_at + cal.basis * Vector3(0.012, cal_size.y * 0.5 + 0.006, 0.0), hub).basis = cal.basis
	for k in [-1.0, 1.0]:
		var b := _mesh_instance(_cylinder(0.008, 0.012), bolt, cal_at + cal.basis * Vector3(cal_size.x * 0.5 + 0.004, 0.0, cal_size.z * 0.35 * k), hub)
		b.basis = cal.basis * Basis(Vector3.BACK, PI * 0.5)
	if front:
		# The hose from the bottom yoke down the back of the fork leg to the caliper.
		var j := _brake_line_joint() + _steer_axis * _build.fork_length
		var fx := _fork_x() + 0.035
		var slide := Vector3(fx, 0.0, 0.045) + _steer_axis * (_build.fork_length * 0.42)
		var hose := _bike_only(_bend([j, j.lerp(slide, 0.5) + Vector3(0.012, 0.0, 0.0), slide, cal_at + cal.basis * Vector3(0.0, cal_size.y * 0.5 + 0.004, 0.0)],
			0.005, _mat(Color(0.05, 0.05, 0.06), 0.3, 0.4), hub, 8))
		hose.name = "BrakeHose"
		_bike_only(_box(slide, Vector3(0.012, 0.025, 0.02), _mat(Color(0.2, 0.2, 0.22), 0.6, 0.4), hub))
	_current_slot = side + "_pads"
	var pad := _box(cal_at + Vector3(0.0, 0.0, 0.0) + cal.basis.y * (cal_size.y * 0.5 + 0.012), Vector3(0.035, 0.024, 0.05), _mat(_col(), 0.4, 0.6), hub)
	pad.basis = cal.basis


## A drum brake: a finned drum cast into the hub (turning with the wheel), and a backplate
## that stays still with the brake arm, the cable or rod to it and the torque stay that stops
## it turning. A twin leading shoe ("tls") has two cams joined by a link rod; a four leading
## shoe ("4ls") a drum each side. The caliper and pad slots draw the arm and the shoes.
func _draw_drum(side: String, wheel: Node3D, hub: Node3D, rim_r: float, x: float) -> void:
	var front := side == "front"
	var p := _part()
	var r := clampf(float(p.get("diameter", 180)) / 2000.0 * 1.1, 0.07, rim_r - 0.05)
	var shoes := str(p.get("shoes", "sls"))
	var alloy := _tex(_mat(_col(), 0.9, 0.3), "brushed", 20.0, 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.6, 0.45)
	var sides := [1.0, -1.0] if shoes == "4ls" else [1.0]
	for sx in sides:
		var drum := _mesh_instance(_cylinder(r, 0.07), alloy, Vector3(0.018 * sx, 0.0, 0.0), wheel)
		drum.rotation.z = PI * 0.5
		drum.name = "BrakeDrum"
		for k in 5:
			var fin := _mesh_instance(_torus(r + 0.003, 0.004), alloy, Vector3((-0.012 + k * 0.012) * sx, 0.0, 0.0), wheel)
			fin.rotation.z = PI * 0.5
		var plate := _mesh_instance(_cylinder(r * 0.98, 0.012, r * 0.85), alloy, Vector3((x - 0.012) * sx, 0.0, 0.0), hub)
		plate.rotation.z = -PI * 0.5 * sx
		plate.name = "Backplate"
		# An air scoop on the front of a racing backplate.
		if shoes != "sls":
			var scoop := _box(Vector3((x - 0.006) * sx, r * 0.35, -r * 0.55 if front else r * 0.55), Vector3(0.012, r * 0.35, r * 0.25), dark, hub)
			scoop.name = "AirScoop"
	# The torque stay: to the fork leg at the front, forward along the swingarm at the back.
	var stay_mat := _mat(Color(0.75, 0.76, 0.78), 1.0, 0.25)
	if front:
		_tube(Vector3(x, -r * 0.6, -r * 0.2), Vector3(x, 0.05, 0.02), 0.007, stay_mat, Vector3.ONE, hub)
	else:
		_tube(Vector3(x, -r * 0.5, -r * 0.3), Vector3(x, -0.03, -0.32), 0.008, stay_mat, Vector3.ONE, hub)
	_current_slot = side + "_caliper"
	# The brake arm (two on a twin leading shoe, with the link rod between them).
	var arm_mat := _mat(_col(), 0.9, 0.3)
	var cams := [[r * 0.6, r * 0.5]] if shoes == "sls" else [[r * 0.6, r * 0.5], [-r * 0.6, -r * 0.5]]
	var tips := []
	for cam in cams:
		var at := Vector3(x + 0.01, float(cam[0]), float(cam[1]) * (1.0 if front else -1.0))
		var tip := at + Vector3(0.0, 0.07, 0.03 if front else -0.03)
		_mesh_instance(_cylinder(0.012, 0.016), arm_mat, at, hub).rotation.z = PI * 0.5
		_tube(at, tip, 0.007, arm_mat, Vector3(1.0, 1.0, 1.8), hub).name = "BrakeArm"
		tips.append(tip)
	if tips.size() > 1:
		_tube(tips[0], tips[1], 0.004, arm_mat, Vector3.ONE, hub).name = "LinkRod"
	if front:
		var j := _brake_line_joint() + _steer_axis * _build.fork_length
		_bike_only(_bend([j, j.lerp(tips[0], 0.5) + Vector3(0.02, 0.0, 0.03), tips[0]], 0.0042, _mat(Color(0.03, 0.03, 0.035), 0.0, 0.6), hub, 6)).name = "BrakeCable"
	else:
		# A rod forward to the brake pedal.
		_bike_only(_tube(tips[0], Vector3(x + 0.02, 0.0, -0.45), 0.004, arm_mat, Vector3.ONE, hub)).name = "BrakeRod"
	_current_slot = side + "_pads"
	# The shoes, hidden in the drum but there to swap.
	for sx in sides:
		for k in [-1.0, 1.0]:
			_box(Vector3((x - 0.022) * sx, r * 0.6 * k, 0.0), Vector3(0.025, 0.02, r * 0.9), _mat(_col(), 0.3, 0.7), hub)


## A sprocket's radius out to its tooth tips, m: the pitch circle of a 5/8" chain (every road and
## MX chain, 520 to 530) round `teeth` teeth, plus the tips. A 45 tooth rear is about 23 cm across,
## a 15 tooth front about 8.
static func sprocket_radius(teeth: int) -> float:
	return CHAIN_PITCH / (2.0 * sin(PI / maxf(teeth, 6))) + 0.003


func _draw_final_drive(zr: float) -> void:
	_current_slot = "final_drive"
	var fd := _part()
	var front_r := sprocket_radius(int(fd.get("front", 15)))
	var rear_r := sprocket_radius(int(fd.get("rear", 45)))
	var sprocket_mat := _mat(_col(), 0.9, 0.35)
	var front_sp := _mesh_instance(_cylinder(front_r, 0.012, -1.0, int(fd.get("front", 15))), sprocket_mat, Vector3(-0.13, 0.0, 0.0), _swingarm)
	front_sp.rotation.z = PI * 0.5
	var rear_sp := _mesh_instance(_cylinder(rear_r, 0.008, -1.0, int(fd.get("rear", 45))), sprocket_mat, Vector3(-0.12, 0.0, 0.0), _rear_wheel)
	rear_sp.rotation.z = PI * 0.5
	# Lightening holes and the bolts holding it to the cush drive.
	var holes := _mat(Color(0.06, 0.06, 0.06), 0.2, 0.7)
	for k in 5:
		var a := TAU * k / 5.0
		var hole := _mesh_instance(_cylinder(rear_r * 0.12, 0.0085), holes, Vector3(-0.12, cos(a) * rear_r * 0.72, sin(a) * rear_r * 0.72), _rear_wheel)
		hole.rotation.z = PI * 0.5
	_current_slot = "chain"
	if _part_id() == "" or _part_id() == "none":
		return
	# The bottom run sags with the chain's slack; a dry chain goes rusty brown.
	var lube := float(condition.get("chain", {}).get("lube", 1.0))
	var slack := float(condition.get("chain", {}).get("slack", 30.0))
	var chain_mat := _mat(_col().lerp(Color(0.4, 0.22, 0.1), clampf(0.7 - lube, 0.0, 0.7)), 0.8, lerpf(0.75, 0.4, lube))
	# The top run, tight from the top of one sprocket to the top of the other.
	_tube(Vector3(-0.125, front_r, 0.0), Vector3(-0.125, rear_r, _arm_len), 0.006, chain_mat, Vector3.ONE, _swingarm)
	var sag := clampf((slack - 20.0) / 1000.0, 0.0, 0.07)
	var a := Vector3(-0.125, -front_r, 0.0)
	var b := Vector3(-0.125, -rear_r, _arm_len)
	var low := (a + b) * 0.5 + Vector3(0.0, -sag, 0.0)
	_tube(a, low, 0.006, chain_mat, Vector3.ONE, _swingarm)
	_tube(low, b, 0.006, chain_mat, Vector3.ONE, _swingarm)


func _draw_shock() -> void:
	_current_slot = "shock"
	var shock := _part()
	var col := _col()
	var chrome := _mat(Color(0.8, 0.8, 0.82), 1.0, 0.2)
	_struts.clear()
	if shock.get("layout", "mono") == "twin":
		var gas: bool = _part_id() == "twin_shock_gas"
		var spring_mat := _mat(col, 0.6, 0.3)
		var softail := _arm_type() in ["softail", "hardtail"]
		for side in [-1.0, 1.0]:
			if softail:
				# A softail hides its shocks: they lie flat under the gearbox, between the frame
				# and the front of the swingarm's triangle, so the back end looks rigid.
				var front := Vector3(0.07 * side, _pivot.y - 0.03, _pivot.z - 0.28)
				var arm_end := Vector3(0.07 * side, -0.05, 0.1)
				_strut(front, arm_end, 0.012, chrome)
				_strut(front.lerp(_pivot + arm_end, 0.1), arm_end + (front - _pivot - arm_end) * 0.35, 0.026, spring_mat)
				continue
			# Each shock runs from the swingarm up to the frame, and works as the arm swings.
			var top := _pivot + Vector3(0.12 * side, 0.3, _arm_len - 0.2)
			# On a low frame the shock tops tuck in under the seat rail instead of standing
			# up above the saddle; the bottom mount stays on the arm, so the shock just lays
			# down further, the way a bobber's does.
			top.y = minf(top.y, _seat_y - 0.07)
			var bottom := Vector3(0.12 * side, 0.02, _arm_len - 0.08)
			_strut(top, bottom, 0.012, chrome)
			_strut(top + (_pivot + bottom - top) * 0.08, bottom + (top - _pivot - bottom) * 0.25, 0.028, spring_mat)
			if gas:
				_tube(Vector3(0.155 * side, 0.22, _arm_len - 0.17), Vector3(0.155 * side, 0.32, _arm_len - 0.21), 0.016, chrome, Vector3.ONE, _swingarm)
	else:
		var top := Vector3(0.0, _seat_y - 0.14, _pivot.z + 0.02)
		var bottom := Vector3(0.0, 0.07, 0.14)
		_strut(top, bottom, 0.016, chrome)
		_strut(top + (_pivot + bottom - top) * 0.1, bottom + (top - _pivot - bottom) * 0.3, 0.038, _mat(col, 0.3, 0.4))


## A shock absorber part between a point on the frame (`top`, model space) and one on the
## swingarm (`bottom`, in the arm's space), stretched to fit as the arm moves.
func _strut(top: Vector3, bottom: Vector3, radius: float, mat: Material) -> void:
	var low := _pivot + bottom
	var mi := _tube(top, low, radius, mat)
	_struts.append({"mi": mi, "top": top, "bottom": bottom, "rest": top.distance_to(low)})


func _update_struts() -> void:
	for s in _struts:
		var mi: MeshInstance3D = s["mi"]
		if not is_instance_valid(mi):
			continue
		var top: Vector3 = s["top"]
		var low: Vector3 = _swingarm.transform * (s["bottom"] as Vector3)
		var dir := low - top
		var length := dir.length()
		mi.position = (top + low) * 0.5
		mi.basis = _basis_up(dir / maxf(length, 0.001)) * Basis.from_scale(Vector3(1.0, length / float(s["rest"]), 1.0))


## The render layers of the rider's parts that would block the first-person eye: HELMET_LAYER
## on your own ride, the ordinary layer on anyone else's.
func eye_layers() -> int:
	return 1 << (HELMET_LAYER - 1) if own_rider else 1


## Sits the rider on the bike, in their gear or plain colours, the left foot ready to go down.
func _build_rider() -> void:
	_rider = Node3D.new()
	add_child(_rider)
	if rider_color.a > 0.0 or not rider_gear.is_empty():
		_build_dressed_rider()
	else:
		_build_plain_rider()
	if foot_down > 0.0:
		_pose_foot()   # built again with the foot down (redressed at a standstill)


## The rider in plain colours (no gear chosen): overalls, lid and boots.
func _build_plain_rider() -> void:
	var seat_y := _seat_y
	# The rider wears their own colours, the same as on foot: overalls in a darker shade, lid in the colour.
	var mine := rider_color.a > 0.0
	var suit := _mat(rider_color.darkened(0.35) if mine else jacket, 0.0, 0.55)
	var pants := _mat(Color(0.06, 0.06, 0.07), 0.0, 0.7)
	var helmet := _mat(rider_color if mine else paint.lightened(0.15), 0.4, 0.15)
	var visor := _mat(Color(0.02, 0.02, 0.03), 0.9, 0.05)
	var gloves := _mat(Color(0.04, 0.04, 0.04), 0.0, 0.6)
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	var torso := _tube(hips, shoulders, 0.15, suit, Vector3(1.25, 1.0, 0.8), _rider)
	var lid := _mesh_instance(_sphere(0.15), helmet, shoulders + Vector3(0.0, 0.2, -0.08), _rider)
	var v := _mesh_instance(_sphere(0.1), visor, shoulders + Vector3(0.0, 0.2, -0.17), _rider)
	v.scale = Vector3(1.1, 0.6, 0.5)
	_rider_head = _make_pivot(shoulders + NECK, [lid, v], "Head")
	var grip_l := _head + _grip_l
	var grip_r := _head + _grip_r
	# The first-person eye is the rider's own, inside the helmet, looking down the road over the
	# bars; the torso, helmet and upper arms, which would be in the way, are hidden from it.
	var hidden := eye_layers()
	for mi in [torso, lid, v]:
		(mi as GeometryInstance3D).layers = hidden
	_eye = _eye_point()
	for side in [-1.0, 1.0]:
		var sh := shoulders + Vector3(0.19 * side, -0.04, 0.0)
		var grip := grip_r if side > 0 else grip_l
		var elbow := sh.lerp(grip, 0.5) + Vector3(0.08 * side, -0.06, 0.04)
		var arm_from := _rider.get_child_count()
		var upper := _tube(sh, elbow, 0.05, suit, Vector3.ONE, _rider)
		upper.layers = hidden
		_tube(elbow, grip, 0.045, suit, Vector3.ONE, _rider)
		_mesh_instance(_sphere(0.045), gloves, grip, _rider)
		if side < 0.0:
			_arm_left = _make_pivot(sh, _rider.get_children().slice(arm_from), "ArmL")
			_arm_rest = (grip - sh).normalized()
		var hip := hips + Vector3(0.12 * side, -0.02, 0.0)
		var knee := Vector3(0.19 * side, seat_y - 0.02, minf(hips.z - 0.36, lerpf(hips.z, _peg.z, 0.55)))
		var peg := Vector3(_peg.x * side, _peg.y, _peg.z)
		var legs := _rider_legs(side, hip, knee, peg)
		for k in legs.size():
			var leg: Array = legs[k]
			_tube(hip, leg[1], 0.075, pants, Vector3.ONE, leg[0])
			_tube(leg[1], leg[2], 0.06, pants, Vector3.ONE, leg[0])
			_box(leg[2] + (Vector3(0.0, -0.02, -0.06) if k == 0 else Vector3(0.0, -0.03, -0.07)), Vector3(0.09, 0.08, 0.22), gloves, leg[0])


## The rider in their own gear (see RiderGear and RiderFigure), sat the same way as the plain
## one in _build_rider: helmet, jacket on the torso and arms, gloves on the grips, trousers on the
## legs and boots on the pegs.
func _build_dressed_rider() -> void:
	var worn := RiderGear.clean_worn(rider_gear)
	var tint := rider_color if rider_color.a > 0.0 else paint.lightened(0.15)
	var jacket := str(worn["jacket"])
	var trousers := str(worn["trousers"])
	var jm := RiderFigure.material(jacket, tint)
	var tm := RiderFigure.material(trousers, tint)
	var jx: Array = RiderGear.get_item(jacket).get("extras", [])
	var tx: Array = RiderGear.get_item(trousers).get("extras", [])
	var hidden := eye_layers()   # kept out of your own first-person eye, as in _build_rider
	var seat_y := _seat_y
	var hips := Vector3(0.0, seat_y + 0.1, lerpf(_seat_front.z, _tail.z, 0.42))
	var shoulders := hips + Vector3(0.0, 0.5, -0.3)
	var torso := RiderFigure.limb(_rider, hips, shoulders, 0.15, jm, hidden)
	torso.basis = torso.basis * Basis.from_scale(Vector3(1.25, 1.0, 0.8))
	var head_from := _rider.get_child_count()
	RiderFigure.helmet(_rider, shoulders + Vector3(0.0, 0.2, -0.08), 0.15, str(worn["helmet"]), tint, hidden, true, worn)
	_rider_head = _make_pivot(shoulders + NECK, _rider.get_children().slice(head_from), "Head")
	var back := (shoulders - hips).normalized().cross(Vector3.RIGHT)
	if jx.has("hump"):
		var hump := RiderFigure.mesh(_rider, RiderFigure.sphere(0.5), jm, shoulders.lerp(hips, 0.15) - back * 0.13, hidden)
		hump.scale = Vector3(0.24, 0.18, 0.14)
	if jx.has("collar"):
		RiderFigure.tube(_rider, shoulders + Vector3(0.0, 0.04, -0.02), shoulders + Vector3(0.0, 0.09, -0.04), 0.08,
			RiderFigure.material(jacket, tint, "trim"), hidden)
	_eye = _eye_point()
	var grip_l := _head + _grip_l
	var grip_r := _head + _grip_r
	for side in [-1.0, 1.0]:
		var sh := shoulders + Vector3(0.19 * side, -0.04, 0.0)
		var grip := grip_r if side > 0 else grip_l
		var elbow := sh.lerp(grip, 0.5) + Vector3(0.08 * side, -0.06, 0.04)
		var arm_from := _rider.get_child_count()
		RiderFigure.limb(_rider, sh, elbow, 0.05, jm, hidden)
		RiderFigure.limb(_rider, elbow, grip, 0.045, jm)
		RiderFigure.glove(_rider, grip, elbow, 0.045, str(worn["gloves"]), tint)
		if side < 0.0:
			_arm_left = _make_pivot(sh, _rider.get_children().slice(arm_from), "ArmL")
			_arm_rest = (grip - sh).normalized()
		var hip := hips + Vector3(0.12 * side, -0.02, 0.0)
		var knee := Vector3(0.19 * side, seat_y - 0.02, minf(hips.z - 0.36, lerpf(hips.z, _peg.z, 0.55)))
		var peg := Vector3(_peg.x * side, _peg.y, _peg.z)
		for leg: Array in _rider_legs(side, hip, knee, peg):
			var at: Node3D = leg[0]
			RiderFigure.limb(at, hip, leg[1], 0.075, tm)
			RiderFigure.limb(at, leg[1], leg[2], 0.06, tm)
			if tx.has("knees"):
				RiderFigure.knee_guard(at, leg[1], hip, leg[2], 0.065, trousers, tint)
			RiderFigure.boot(at, leg[2] + Vector3(0.0, -0.06, 0.0), leg[1], Vector3.FORWARD, str(worn["boots"]), tint)


## Where the rider's leg on `side` goes, from `hip` through `knee` to the ankle at `peg`, as
## [[node to build it under, knee, ankle], ...]: the right leg once, on its peg; the left twice,
## on its peg ("LegLPeg") and put down on the ground beside the bike ("LegLDown", hidden till the
## bike comes to rest: see update_foot), the knee bent forward and out to reach it.
func _rider_legs(side: float, hip: Vector3, knee: Vector3, peg: Vector3) -> Array:
	if side > 0.0:
		return [[_rider, knee, peg]]
	var on_peg := Node3D.new()
	on_peg.name = "LegLPeg"
	_rider.add_child(on_peg)
	var down := Node3D.new()
	down.name = "LegLDown"
	down.visible = false
	_rider.add_child(down)
	var thigh := hip.distance_to(knee)
	var shin := knee.distance_to(peg)
	# The ground, with the bike leaned over onto the foot (about the tyres' contact line).
	var ground := foot_ground_y()
	var foot_x := -FOOT_OUT
	var ankle := Vector3(foot_x, ground + FOOT_OUT * tan(FOOT_LEAN) + 0.065, hip.z - 0.08)
	var to := ankle - hip
	var reach := thigh + shin - 0.005
	if to.length() > reach:
		ankle = hip + to.normalized() * reach   # a short leg on a tall bike: on tiptoe
		to = ankle - hip
	var d := to.length()
	var along := (thigh * thigh - shin * shin + d * d) / (2.0 * d)
	var lift := sqrt(maxf(thigh * thigh - along * along, 0.0))
	var axis := to / d
	var pole := Vector3(-0.35, 0.0, -1.0).normalized()
	pole = (pole - axis * pole.dot(axis)).normalized()
	var knee_down := hip + axis * along + pole * lift
	return [[on_peg, knee, peg], [down, knee_down, ankle]]


## The ground under the bike in the model's own space (its origin's at the axles, roughly).
func foot_ground_y() -> float:
	return -(_build.rear_radius if _build else 0.3) + FOOT_SAG


## The ridden bike coming to rest (`speed` m/s; `can` is false crashed, in the air or in a
## burnout): below walking pace the rider puts their left foot down and the bike leans a little
## onto it, and as it pulls away they lift it back onto the peg. Eases in and out over `delta`.
## Returns how far down the foot is, 0..1.
func update_foot(speed: float, delta: float, can := true) -> float:
	if not can or absf(speed) > FOOT_UP_SPEED:
		_foot_want = 0.0
	elif absf(speed) < FOOT_DOWN_SPEED:
		_foot_want = 1.0
	var was := foot_down
	foot_down = move_toward(foot_down, _foot_want, delta / FOOT_TIME)
	if foot_down != was:
		_pose_foot()
	return foot_down


func _pose_foot() -> void:
	if _rider == null:
		return
	var on_peg := _rider.get_node_or_null("LegLPeg") as Node3D
	var down := _rider.get_node_or_null("LegLDown") as Node3D
	if on_peg and down:
		down.visible = foot_down > 0.5
		on_peg.visible = not down.visible
	# Leaned over onto the foot about where the tyres meet the road.
	var c := Vector3(0.0, foot_ground_y(), 0.0)
	var lean := Basis(Vector3.BACK, FOOT_LEAN * smoothstep(0.0, 1.0, foot_down))   # top over to the left
	transform = Transform3D(lean, c - lean * c) if foot_down > 0.0 else Transform3D()


## Where the head turns from: the neck, from the rider's shoulders.
const NECK := Vector3(0.0, 0.08, -0.04)


## A pivot at `at` in the rider's space with `nodes` (the rider's own children) moved onto it
## where they were, so turning the pivot turns them about that point.
func _make_pivot(at: Vector3, nodes: Array, pivot_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = at
	_rider.add_child(pivot)
	for n in nodes:
		var n3 := n as Node3D
		if n3 == null or n3 == pivot:
			continue
		var xf := n3.transform
		_rider.remove_child(n3)
		pivot.add_child(n3)
		n3.transform = Transform3D(Basis(), -at) * xf
	return pivot


## The rider does a gesture on the bike: "nod" or "ride_wave" (see Emotes.RIDING). A new one
## takes over from one under way.
func gesture(e: String) -> void:
	if not Emotes.is_riding(e):
		return
	_gesture = e
	_gesture_t = 0.0
	set_process(true)


## The gesture under way, "" when there's none.
func gesture_now() -> String:
	return _gesture


## How far the left hand is up off the bar now, 0..1 (for the tests).
func wave_amount() -> float:
	if _arm_left == null or _arm_rest == Vector3.ZERO:
		return 0.0
	var now := _arm_left.basis * _arm_rest
	return clampf(_arm_rest.angle_to(now) / 1.2, 0.0, 1.0)


func _ready() -> void:
	set_process(_gesture != "" or look_back != 0.0)


func _process(delta: float) -> void:
	var p := {"nod": 0.0, "arm": Vector3.ZERO, "w": 0.0}
	if _gesture != "":
		_gesture_t += delta
		p = Emotes.riding_pose(_gesture, _gesture_t)
		if _gesture_t >= float(Emotes.LENGTH.get(_gesture, 1.0)):
			_gesture = ""
	_nod = float(p["nod"])
	_look_shown = move_toward(_look_shown, look_back, delta * 5.0)
	if _rider_head:
		var yaw := LOOK_BACK_YAW * smoothstep(0.0, 1.0, _look_shown)
		_rider_head.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -_nod)
	if _arm_left:
		var arm: Vector3 = p["arm"]
		var turn := Quaternion.IDENTITY
		if arm != Vector3.ZERO and _arm_rest.dot(arm.normalized()) > -0.999:
			turn = Quaternion(_arm_rest, arm.normalized())
		_arm_left.basis = Basis(Quaternion.IDENTITY.slerp(turn, float(p["w"])))
	if _gesture == "" and look_back == 0.0 and _look_shown == 0.0:
		set_process(false)


## Dresses the rider again in `gear` (when its rider changes their gear mid-ride).
func redress(gear: Dictionary) -> void:
	rider_gear = gear
	if _rider == null:
		return
	var xf := _rider.transform
	var shown := _rider.visible
	_rider.free()
	_build_rider()
	_rider.transform = xf
	_rider.visible = shown


## A basis whose Y axis points along `up`.
## A turn that stands a piece up along cylinder barrel `up`, sized with the barrel (see
## _place_cylinders).
func _cyl_basis(up: Vector3) -> Basis:
	return _basis_up(up).scaled(Vector3.ONE * up.length())


func _basis_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))


## Moves wheels, suspension, steering and rider to match the simulation.
func update_pose(bike: Bike) -> void:
	update_pose_from(bike.steer, bike.wheels[0]["spin"], bike.wheels[1]["spin"],
		bike.wheels[0]["compression"], bike.wheels[1]["compression"], bike.body_shift, bike.lean_input)


func update_pose_from(steer: float, spin_f: float, spin_r: float, comp_f: float, comp_r: float,
		body_shift: float, lean_in: float) -> void:
	if _build == null:
		return
	var wb := _build.wheelbase
	_steer_node.basis = Basis(_steer_axis, -steer)
	# The front axle slides up the fork legs, the back one swings up round the swingarm pivot
	# (the same paths the riding physics uses: see BikeBuild.fork_path and rear_axle_at).
	var front_axle := Vector3(0.0, 0.0, -wb * 0.5) + _build.fork_path * comp_f
	_front_hub.position = _steer_node.transform.affine_inverse() * front_axle
	_front_wheel.rotation.x = -spin_f
	# A flat tyre stays squashed at the bottom while the rim turns inside it (see set_flat).
	if _flat_tyres.has("front"):
		(_flat_tyres["front"] as Node3D).rotation.x = spin_f
	if _flat_tyres.has("rear"):
		(_flat_tyres["rear"] as Node3D).rotation.x = spin_r
	var rear_axle := _build.rear_axle_at(comp_r)
	_rear_hub.position = rear_axle
	_rear_wheel.rotation.x = -spin_r
	var to_axle := rear_axle - _pivot
	_swingarm.rotation.x = -atan2(to_axle.y, to_axle.z)
	_update_struts()
	if _rider:
		_rider.position = Vector3(lean_in * 0.05, 0.0, -body_shift * 0.1)
		_rider.rotation = Vector3(-body_shift * 0.12, 0.0, -lean_in * 0.12)
	if not geometry.is_empty():
		_update_geometry()


## Where the rider's eyes are, looking down over the bars at the clocks, in the model's space.
func eye_transform() -> Transform3D:
	var at := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-21.0)), _eye)
	if _rider_head and _nod != 0.0:
		# Nodding, the eye dips with the head (looking back is the camera's own turn).
		var neck := _rider_head.position
		at = Transform3D(Basis(Vector3.RIGHT, -_nod), neck) * Transform3D(Basis(), -neck) * at
	return (_rider.transform * at) if _rider else at


func exhaust_tip() -> Vector3:
	return _exhaust_tip


func lamp_position() -> Vector3:
	return _head + Vector3(0.0, -0.08, -0.13)


## Road muck over the whole bike while it's ridden, 0 (none) .. 1 (plastered).
func set_grime(level: float) -> void:
	if level < 0.02:
		if _grime:
			for slot in _slot_meshes:
				for mi in _slot_meshes[slot]:
					(mi as GeometryInstance3D).material_overlay = null
			_grime = null
		return
	if _grime == null:
		_grime = StandardMaterial3D.new()
		_grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grime.albedo_color = Color(0.3, 0.22, 0.13, 0.0)
		_grime.albedo_texture = _splatter()
		_grime.uv1_triplanar = true
		_grime.uv1_scale = Vector3(4.0, 4.0, 4.0)
		_grime.roughness = 1.0
		for slot in _slot_meshes:
			for mi in _slot_meshes[slot]:
				(mi as GeometryInstance3D).material_overlay = _grime
	_grime.albedo_color.a = clampf(level, 0.0, 0.9)


static var _splatter_tex: NoiseTexture2D


## Blotchy alpha for mud: big clumps with gaps between.
static func _splatter() -> NoiseTexture2D:
	if _splatter_tex:
		return _splatter_tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 1.0))
	ramp.add_point(0.45, Color(1, 1, 1, 0.0))
	ramp.add_point(0.6, Color(1, 1, 1, 0.9))
	_splatter_tex = NoiseTexture2D.new()
	_splatter_tex.width = 256
	_splatter_tex.height = 256
	_splatter_tex.seamless = true
	_splatter_tex.noise = noise
	_splatter_tex.color_ramp = ramp
	return _splatter_tex


## A readout on the clocks for the rider: speed, gear and fuel, printed on the screen (or under
## the needle on dial clocks). Only the ridden bike has one.
func dash_readout() -> Label3D:
	if _dash_label == null:
		_dash_label = Label3D.new()
		var dials := not _needles.is_empty()
		_dash_label.font_size = 28 if dials else 40
		_dash_label.pixel_size = 0.0004
		_dash_label.outline_size = 0
		_dash_label.modulate = Color(0.1, 0.1, 0.1) if dials else Color(0.75, 1.0, 0.85)
		# Label3D faces +Z; lay it flat on the face, which looks along the tilted Y.
		_dash_label.transform = Transform3D(_dash_screen.basis * Basis(Vector3.RIGHT, -PI * 0.5), _dash_screen.origin)
		_dash_label.line_spacing = -4.0
		_dash_label.shaded = false
		_dash_label.double_sided = false
		# With the clocks moved in geometry mode, the readout goes with them.
		var host: Node3D = _steer_node
		for e in _geo_nodes.get("dashboard", []):
			if e["parent"] == _steer_node:
				host = e["node"]
		host.add_child(_dash_label)
	return _dash_label


func has_dials() -> bool:
	return not _needles.is_empty()


func set_rider_visible(v: bool) -> void:
	if _rider:
		_rider.visible = v


func is_fitted(slot: String) -> bool:
	return present.is_empty() or bool(present.get(slot, false))


func _apply_visibility() -> void:
	for slot in _slot_meshes:
		for mi in _slot_meshes[slot]:
			mi.visible = is_fitted(slot) and not ((mi as Node).has_meta("under_fairing") and is_fitted("fairing"))


## A merged piece smaller than this (m) casts no shadow (see _bake_static).
const SHADOW_MIN := 0.08


## Draws the parts with fewer, bigger meshes. A bike is drawn from about 300 small meshes, each
## a draw call in every pass (the shadows' too), which is what cost the frame rate riding beside
## someone else. Each part's pieces that hang from the same node and share a material become
## one mesh, so the part still shows, hides, moves in geometry mode, gets dirty and polished as
## before. Left as they are: anything that moves or changes by itself (the shock springs, the
## needles, the tyres, which go flat), anything hidden, anything carrying its own data (metas,
## per-mesh shader values, overlays) and the rider. Their shadows go further: a node's merged
## pieces cast theirs as one shadow-only mesh. Called from build_from when `baked` is set,
## ahead of the dirt and the paint's effects. Returns how many meshes were merged away.
func _bake_static() -> int:
	var moving := {}
	for s in _struts:
		moving[s["mi"]] = true
	for n in _needles:
		moving[n["node"]] = true
	for side in _flat_tyres:
		moving[_flat_tyres[side]] = true
	var gone := 0
	for slot in _slot_meshes:
		var groups := {}    # [parent, material, shadows, layers] -> [[mesh, surface, transform], ...]
		var stock := {}     # the same keys -> whether every piece is a stock indicator's
		var shadow_groups := {}   # [parent, layers] -> the merged meshes whose shadows go together
		var keep := []
		for mi in _slot_meshes[slot]:
			if not _can_bake(mi, moving):
				keep.append(mi)
				continue
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var key := [m.get_parent(), m.get_active_material(s), m.cast_shadow, m.layers]
				if not groups.has(key):
					groups[key] = []
					stock[key] = true
				groups[key].append([m.mesh, s, m.transform])
				stock[key] = stock[key] and _stock_pieces.has(mi)
			m.get_parent().remove_child(m)
			m.queue_free()
			gone += 1
		for key in groups:
			var st := SurfaceTool.new()
			for piece in groups[key]:
				st.append_from(piece[0], piece[1], piece[2])
			var merged := MeshInstance3D.new()
			merged.name = "Baked_" + str(slot)
			merged.mesh = st.commit()
			merged.material_override = key[1]
			merged.cast_shadow = key[2]
			# A shadow too small to see isn't drawn into the shadow maps.
			if merged.mesh.get_aabb().get_longest_axis_size() < SHADOW_MIN:
				merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			merged.layers = key[3]
			(key[0] as Node).add_child(merged)
			keep.append(merged)
			_baked_pieces[merged.get_instance_id()] = true
			if stock[key]:
				_stock_pieces[merged] = true   # still left out of the part's size
			gone -= 1
			if merged.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and _plain_caster(key[1]):
				var sk := [key[0], key[3]]
				if not shadow_groups.has(sk):
					shadow_groups[sk] = []
				shadow_groups[sk].append(merged)
		_slot_meshes[slot] = keep
		# One shadow for each node's merged pieces, whatever they're painted: a bike near the
		# camera (yours, or the one beside you) is drawn into all four of the sun's shadow
		# splits, and each material's piece was a draw in every one.
		for sk in shadow_groups:
			var pieces: Array = shadow_groups[sk]
			if pieces.size() < 2:
				continue
			var sh := MeshInstance3D.new()
			sh.name = "BakedShadow_" + str(slot)
			sh.mesh = shape_mesh(pieces)
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.layers = sk[1]
			(sk[0] as Node).add_child(sh)
			for mi in pieces:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_slot_extra(slot, sh)
	return gone


## Keeps `mi`, a mesh drawn for `slot`'s part besides its own (see _slot_extras), with the part.
func add_slot_extra(slot: String, mi: GeometryInstance3D) -> void:
	if not _slot_extras.has(slot):
		_slot_extras[slot] = []
	_slot_extras[slot].append(mi)


## Whether `g` is one of the meshes a baked model's pieces were merged into (see _bake_static):
## it stays as it is, and others drawn over it can go into one mesh with its neighbours'.
func baked_piece(g: Node) -> bool:
	return g != null and _baked_pieces.has(g.get_instance_id())


## Whether a material's shadow is the plain one (opaque, front faces only), as a shadow-only
## mesh with no material of its own casts it.
static func _plain_caster(mat: Material) -> bool:
	if mat == null:
		return true
	if not (mat is BaseMaterial3D) or mat.next_pass != null:
		return false
	var b := mat as BaseMaterial3D
	return b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and b.cull_mode == BaseMaterial3D.CULL_BACK \
		and not b.grow and not b.use_point_size and b.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED


## One mesh of the shapes of `pieces` (MeshInstance3Ds hanging from the same node), as they sit
## there: just where the corners are and which way they face (for a shadow's normal bias, or a
## pass drawn over them).
static func shape_mesh(pieces: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	for mi in pieces:
		var m := mi as MeshInstance3D
		var xf := m.transform
		var nb := xf.basis.inverse().transposed()
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n = arrays[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				normals.append((nb * (n[i] as Vector3)).normalized() if n is PackedVector3Array and i < (n as PackedVector3Array).size() else Vector3.UP)
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
				for i in idx:
					index.append(base + i)
			else:
				for i in v.size():
					index.append(base + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = index
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Whether a part's mesh can be merged into others (see _bake_static).
func _can_bake(mi, moving: Dictionary) -> bool:
	if not is_instance_valid(mi) or (mi as Object).get_class() != "MeshInstance3D" or moving.has(mi):
		return false
	var m := mi as MeshInstance3D
	if m.mesh == null or m.get_child_count() > 0 or not m.visible or m.material_overlay != null or m.get_parent() == null:
		return false
	if not m.get_meta_list().is_empty() or (m.get_script() != null) or (_rider != null and _rider.is_ancestor_of(m)):
		return false
	for s in m.mesh.get_surface_count():
		if m.mesh is ArrayMesh and (m.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var mat := m.get_active_material(s)
		while mat != null:
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
					and (mat as ShaderMaterial).shader.code.contains("instance uniform"):
				return false
			mat = mat.next_pass
	# Hidden by something it hangs from: left alone (it doesn't draw).
	var n := m.get_parent()
	while n != null and n != self:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## Draws a glow over one part (or none with "").
func highlight(slot: String) -> void:
	if slot == _highlighted:
		return
	if _highlight_mat == null:
		_highlight_mat = StandardMaterial3D.new()
		_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_mat.albedo_color = Color(1.0, 0.6, 0.15, 0.3)
		_highlight_mat.grow = true
		_highlight_mat.grow_amount = 0.004
	for s in _slot_meshes:
		for mi in _slot_meshes[s]:
			(mi as GeometryInstance3D).material_overlay = _highlight_mat if s == slot else null
	_highlighted = slot


# ---------------------------------------------------------------------------- geometry (per-bike fit)

## Moves, turns and sizes each part by this bike's own fit (see `geometry`). The first time,
## every slot's meshes are hung from a node of their own under whatever they were drawn on
## (the frame, the steering, a hub, a wheel, the swingarm), so this works for any slot, new
## ones included. Wheels and needles still spin under their offset rather than wobbling.
func apply_geometry(geo: Dictionary) -> void:
	geometry = geo
	if _build == null:
		return
	if _geo_pivots.is_empty():
		if geo.is_empty():
			return
		_wrap_slots()
	_update_geometry()


## The middle of a part as it was drawn, before its fit, in this model's space.
func geo_pivot(slot: String) -> Vector3:
	if _geo_pivots.has(slot):
		return _geo_pivots[slot]
	return slot_bounds(slot).get_center()


## Where a part's middle is now and how it's turned, in this model's space (for the gizmo).
func geo_xform(slot: String) -> Transform3D:
	var off := GeoGizmo.offset_of(geometry, slot)
	return Transform3D(GeoGizmo.rotation_of(off), geo_pivot(slot) + (off["p"] as Vector3))


func _wrap_slots() -> void:
	var anchors: Array = [self]
	for n in [_steer_node, _front_hub, _rear_hub, _swingarm]:
		if n != null and is_instance_valid(n):
			anchors.append(n)
	for a in anchors:
		_geo_anchors[a] = Transform3D.IDENTITY if a == self else _local_xform(a)
	for slot in _slot_meshes:
		var meshes: Array = (_slot_meshes[slot] + _slot_extras.get(slot, [])).filter(func(m): return is_instance_valid(m))
		if meshes.is_empty():
			continue
		_geo_pivots[slot] = slot_bounds(slot).get_center()
		var by_parent := {}
		var nodes := []
		for mi in meshes:
			var parent: Node = (mi as Node).get_parent()
			if parent == null:
				continue
			if not by_parent.has(parent):
				var g := Node3D.new()
				g.name = "Geo_" + slot
				parent.add_child(g)
				by_parent[parent] = g
				var anchor: Node = parent
				while anchor != null and not _geo_anchors.has(anchor):
					anchor = anchor.get_parent()
				nodes.append({"node": g, "parent": parent, "anchor": anchor if anchor != null else self})
			(mi as Node).reparent(by_parent[parent], false)
		_geo_nodes[slot] = nodes


## Sets every slot node from `geometry`: the offset is in model space at rest, carried into
## the frame of what it rides on (so moved bars still steer) and undone through anything that
## spins between (so a moved wheel still turns about its own middle).
func _update_geometry() -> void:
	for slot in _geo_nodes:
		var o := GeoGizmo.offset_xform(geometry.get(slot, {}), _geo_pivots[slot])
		for e in _geo_nodes[slot]:
			var g: Node3D = e["node"]
			if not is_instance_valid(g):
				continue
			var a0: Transform3D = _geo_anchors.get(e["anchor"], Transform3D.IDENTITY)
			var oa := a0.affine_inverse() * o * a0
			var q := Transform3D.IDENTITY
			var n: Node = e["parent"]
			while n != null and n != e["anchor"] and n is Node3D:
				q = (n as Node3D).transform * q
				n = n.get_parent()
			g.transform = q.affine_inverse() * oa * q


## Turns the whole model into a see-through glowing hologram (for blueprint builds).
func make_ghost(mat: Material) -> void:
	for slot in _slot_meshes:
		for mi in _slot_meshes[slot]:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).material_override = mat
				(mi as GeometryInstance3D).material_overlay = null
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for slot in _slot_extras:
		for sh in _slot_extras[slot]:
			if is_instance_valid(sh):
				(sh as Node3D).visible = false
	if _dash_label:
		_dash_label.visible = false


## Local-space bounding box of a part's meshes.
func slot_bounds(slot: String) -> AABB:
	var box := AABB()
	var first := true
	for mi in _slot_meshes.get(slot, []):
		if _stock_pieces.has(mi):
			continue   # the stock indicators on a headlight or tail unit
		var aabb: AABB = _local_xform(mi) * (mi as VisualInstance3D).get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	return box


## Points spread evenly over a part's surfaces, about `cell` apart, in this model's space, with
## the outward surface normal at each: [points, normals]. For the sandblaster's coverage map.
func surface_points(slot: String, cell: float) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot)
	for mi in _slot_meshes.get(slot, []):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null or not is_instance_valid(mi):
			continue
		var xf := _local_xform(mi)
		var faces := (mi as MeshInstance3D).mesh.get_faces()
		for f in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[f]
			var b: Vector3 = xf * faces[f + 1]
			var c: Vector3 = xf * faces[f + 2]
			# Godot's front faces wind clockwise, so this cross product points out of the surface.
			var n := (c - a).cross(b - a)
			var area := n.length() * 0.5
			if area < 1e-7:
				continue
			n = n.normalized()
			var count := ceili(area / (cell * cell) * 1.5)
			for k in count:
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := a + (b - a) * u + (c - a) * v
				var key := Vector3i((p / cell).floor())
				if seen.has(key):
					continue
				seen[key] = true
				points.append(p)
				normals.append(n)
	return [points, normals]


## Bodywork whose crosshair shapes follow its surface (see build_pickers).
const SHELL_PICKS: Array[String] = ["frame", "tank", "fairing", "side_panels", "tail"]
## Parts round the engine whose bent tubes get a crosshair box along each stretch, so you can aim
## between them at the filters (see build_pickers). Elsewhere (the bars and the front end) a bent
## tube keeps one box round the lot, easier to catch from further off.
const BEND_PICKS: Array[String] = ["frame", "swingarm", "exhaust", "guards", "cooling", "rearsets",
	"side_stand", "centre_stand", "engine", "head", "fuel", "air_filter", "oil_filter", "spark_plugs", "gearbox"]

## Adds a static click target per fitted part, with box shapes fitted to its meshes.
## Each body carries metadata "slot", plus everything in `meta`; `slot_meta` replaces `meta`
## for particular slots. Rings (tyres, spoked rims) get a hoop of boxes so the ray can still
## reach the disc and caliper inside them.
func build_pickers(meta: Dictionary, slot_meta := {}, layer := PICK_LAYER) -> void:
	clear_pickers()
	for slot in _slot_meshes:
		if not is_fitted(slot) or _slot_meshes[slot].is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "Pick_" + slot
		body.collision_layer = layer
		body.collision_mask = 0
		body.set_meta("slot", slot)
		var m: Dictionary = slot_meta.get(slot, meta)
		for key in m:
			body.set_meta(key, m[key])
		for mi in _slot_meshes[slot]:
			if mi is MultiMeshInstance3D or str(mi.name).begins_with("Spoke"):
				continue
			var xf := _local_xform(mi)
			var exact := layer == PICK_LAYER   # for the crosshair: shapes that follow what's drawn
			if exact and mi.has_meta("under_fairing") and is_fitted("fairing"):
				continue   # tucked away out of sight under a full fairing
			if exact and _bends.has(mi.get_instance_id()) and slot in BEND_PICKS:
				# A bent tube (a frame rail, a header, crash bars): a box along each stretch of it,
				# so you can aim past it at what's behind and between its bends.
				var bend: Dictionary = _bends[mi.get_instance_id()]
				var line: Array = ShapeKit.smooth(bend["path"], 2)
				var thick := maxf(float(bend["r"]) * 2.0 + 0.01, 0.03)
				for i in range(1, line.size()):
					var a: Vector3 = xf * (line[i - 1] as Vector3)
					var b: Vector3 = xf * (line[i] as Vector3)
					if a.distance_to(b) < 0.001:
						continue
					var along := (b - a).normalized()
					var across := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
					var piece := Transform3D(Basis(across, along, across.cross(along)), (a + b) * 0.5)
					_add_box(body, piece, Vector3(thick, a.distance_to(b) + thick * 0.5, thick))
				continue
			if mi.has_meta("hoop"):
				# A ring (the tyre, a rim barrel): boxes round it, with the middle left open.
				var hoop: Vector3 = mi.get_meta("hoop")
				var mid_r := (hoop.x + hoop.y) * 0.5
				var deep := hoop.y - hoop.x
				for i in 16:
					var a := TAU * i / 16.0
					var piece := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.0, sin(a)) * mid_r)
					_add_box(body, xf * piece, Vector3(deep, hoop.z, TAU * mid_r / 16.0))
				continue
			if (mi as MeshInstance3D).mesh is TorusMesh:
				var torus: TorusMesh = mi.mesh
				var mid := (torus.inner_radius + torus.outer_radius) * 0.5
				var depth := torus.outer_radius - torus.inner_radius
				for i in 12:
					var a := TAU * i / 12.0
					var piece := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.0, sin(a)) * mid)
					_add_box(body, xf * piece, Vector3(depth, depth, TAU * mid / 12.0))
				continue
			var aabb: AABB = (mi as VisualInstance3D).get_aabb()
			if exact and SHELL_PICKS.has(slot) and (mi as MeshInstance3D).mesh is ArrayMesh and aabb.get_longest_axis_size() > 0.15:
				# Bodywork is a shell round other parts: its own surface, not the box round it,
				# so you can see and reach what's under its edges (the filters under a tank).
				var faces := (mi as MeshInstance3D).mesh.get_faces()
				for f in faces.size():
					faces[f] = xf * faces[f]
				var trimesh := ConcavePolygonShape3D.new()
				trimesh.set_faces(faces)
				trimesh.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = trimesh
				body.add_child(cs)
				continue
			var size := aabb.size
			if slot == "chain":
				# A chain is thin; make it easy to aim at from the side, standing out past the frame.
				size = size.max(Vector3(0.14, 0.07, 0.07))
			_add_box(body, xf * Transform3D(Basis(), aabb.get_center() + (Vector3(-0.06, 0.0, 0.0) if slot == "chain" else Vector3.ZERO)), size)
		add_child(body)


func _add_box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = (size * xf.basis.get_scale()).max(Vector3(0.03, 0.03, 0.03))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.add_child(cs)


## Frees every mesh that isn't part of `keep`, for showing loose parts on their own.
func strip_to(keep: Array) -> void:
	for s in _slot_meshes:
		if keep.has(s):
			continue
		for mi in _slot_meshes[s] + _slot_extras.get(s, []):
			if is_instance_valid(mi):
				mi.free()
		_slot_meshes[s] = []
		_slot_extras.erase(s)


## Loose parts on their own, sitting with their base on the origin. `parts` maps slot ->
## part id for each part to show; `cond` maps slot -> condition. The node's "size" meta is
## the bounding size and its "model" meta is the BikeModel inside.
static func assembly_display(parts: Dictionary, cond: Dictionary, unseen := {}) -> Node3D:
	var build := PartsDB.DEFAULT_BUILD.duplicate()
	build.merge(unseen, true)
	var fitted := {}
	for slot in parts:
		build[slot] = parts[slot]
		fitted[slot] = true
	var model := BikeModel.new()
	model.build_from(BikeBuild.new(build, cond), Color(0.55, 0.56, 0.58), fitted, cond, false)
	model.strip_to(parts.keys())
	# Off the bike, a part leaves behind the cables and hoses that ran to the rest of it.
	for slot in model._slot_meshes:
		for mi in (model._slot_meshes[slot] as Array).duplicate():
			if (mi as Node).has_meta("bike_only"):
				(model._slot_meshes[slot] as Array).erase(mi)
				mi.free()
	var bounds := AABB()
	var first := true
	for slot in parts:
		var b := model.slot_bounds(slot)
		if b.size == Vector3.ZERO:
			continue
		bounds = b if first else bounds.merge(b)
		first = false
	var root := Node3D.new()
	root.add_child(model)
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	root.set_meta("size", bounds.size)
	root.set_meta("model", model)
	return root


## One loose part from the catalogue.
static func part_display(part_id: String, cond: Dictionary) -> Node3D:
	if PartsDB.is_fluid(part_id):
		return fluid_display(part_id, 0.0 if PartsDB.get_part(part_id).get("empty", false) else 1.0)
	var slot: String = PartsDB.slots_for_kind(PartsDB.kind_of(part_id))[0]
	if slot == "front_tyre":
		# A loose tyre keeps the size it is on a wheel it's made for (`unseen` sizes it, and isn't drawn).
		var fits: Array = PartsDB.wheels_for(part_id)
		if not fits.is_empty():
			return assembly_display({slot: part_id}, {slot: cond}, {"front_wheel": fits[0]})
	return assembly_display({slot: part_id}, {slot: cond})


## A loose item from the shed, drawn with whatever is fitted to it (an engine with its head,
## carbs and so on).
static func item_display(item_id: int) -> Node3D:
	var it: Dictionary = Shed.items[item_id]
	if it.get("boxed", false):
		return OrderNote.attach(box_display(str(it["part"]), item_id), it)
	if PartsDB.is_fluid(str(it["part"])):
		var f: Dictionary = it.get("fluid", {})
		return fluid_display(str(it["part"]), float(f.get("litres", 0.0)) / maxf(PartsDB.fluid_capacity(str(it["part"])), 0.01))
	if Shed.is_engine(item_id):
		var asm := Shed.engine_assembly(item_id)
		var shown := {}
		for slot in asm["fitted"]:
			if asm["fitted"][slot]:
				shown[slot] = asm["parts"][slot]
		return assembly_display(shown, asm["cond"])
	var tyre := Shed.tyre_on_wheel(item_id)
	if tyre != 0:
		# A wheel off the bike with its tyre still on.
		return assembly_display({"front_wheel": it["part"], "front_tyre": Shed.items[tyre]["part"]},
			{"front_wheel": Shed.condition_of(it), "front_tyre": Shed.condition_of(Shed.items[tyre])})
	return part_display(it["part"], Shed.condition_of(it))


## A can, bottle or pan of fluid, sitting on its base. `full` 0..1 shows how much is in it
## where you can see in (the drain pan and the bleed bottle).
static func fluid_display(part_id: String, full: float) -> Node3D:
	var p := PartsDB.get_part(part_id)
	var c: Array = p.get("color", [0.5, 0.5, 0.5])
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(c[0], c[1], c[2])
	body.roughness = 0.45
	body.metallic = 0.3 if PartsDB.kind_of(part_id) == "petrol" else 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	dark.roughness = 0.6
	var l: Array = p.get("liquid", [0.5, 0.4, 0.2])
	var liquid := StandardMaterial3D.new()
	liquid.albedo_color = Color(l[0], l[1], l[2])
	liquid.roughness = 0.1
	liquid.metallic = 0.2
	# Containers are translucent plastic (or have a sight strip), so you can see how much is left.
	var see := body.duplicate() as StandardMaterial3D
	see.albedo_color.a = 0.42
	see.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	see.metallic = 0.0
	see.roughness = 0.25
	see.cull_mode = BaseMaterial3D.CULL_DISABLED
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(0.9, 0.92, 0.95, 0.3)
	strip.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	strip.roughness = 0.05
	var level := clampf(full, 0.0, 1.0)
	var root := Node3D.new()
	var size := Vector3.ONE * 0.2
	var pieces := []   # [mesh, material, position]
	match str(p.get("container", "")):
		"Jerry can":
			var big := float(p["litres"]) > 6.0
			size = Vector3(0.14 if big else 0.11, 0.38 if big else 0.3, 0.3 if big else 0.24)
			pieces = [[_box_mesh(size), see, Vector3(0.0, size.y * 0.5, 0.0)],
				[_box_mesh(Vector3(0.03, 0.04, size.z * 0.6)), body, Vector3(0.0, size.y + 0.02, 0.0)],
				[_cyl_mesh(0.022, 0.05), dark, Vector3(0.0, size.y + 0.01, size.z * 0.38)]]
			if level > 0.01:
				var inner := size - Vector3(0.012, 0.012, 0.012)
				pieces.append([_box_mesh(Vector3(inner.x, inner.y * level, inner.z)), liquid, Vector3(0.0, 0.006 + inner.y * level * 0.5, 0.0)])
		"Aerosol":
			# A spray can of chain lube with a red straw nozzle and a clear level strip down the side.
			size = Vector3(0.066, 0.22, 0.066)
			var straw := StandardMaterial3D.new()
			straw.albedo_color = Color(0.8, 0.1, 0.08)
			pieces = [[_cyl_mesh(0.033, 0.19), body, Vector3(0.0, 0.095, 0.0)],
				[_cyl_mesh(0.026, 0.03, 0.033), dark, Vector3(0.0, 0.205, 0.0)],
				[_box_mesh(Vector3(0.004, 0.004, 0.09)), straw, Vector3(0.0, 0.215, -0.05)],
				[_box_mesh(Vector3(0.014, 0.16, 0.004)), strip, Vector3(0.0, 0.095, 0.0335)]]
			if level > 0.01:
				pieces.append([_box_mesh(Vector3(0.01, 0.155 * level, 0.004)), liquid, Vector3(0.0, 0.018 + 0.0775 * level, 0.034)])
		"Repair kit":
			# A puncture repair kit: a little tin box with the soapy spray bottle and the T-handle reamer.
			size = Vector3(0.16, 0.06, 0.1)
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color(0.7, 0.72, 0.75)
			steel.metallic = 0.8
			steel.roughness = 0.35
			pieces = [[_box_mesh(Vector3(0.16, 0.05, 0.1)), body, Vector3(0.0, 0.025, 0.0)],
				[_box_mesh(Vector3(0.162, 0.012, 0.102)), dark, Vector3(0.0, 0.05, 0.0)],
				[_cyl_mesh(0.004, 0.09), steel, Vector3(0.03, 0.06, 0.0)],
				[_box_mesh(Vector3(0.05, 0.012, 0.012)), dark, Vector3(0.03, 0.105, 0.0)]]
			if level > 0.01:
				# The plugs left, brown sticky strips in a row on the lid.
				var n := clampi(ceili(level * 5.0), 1, 5)
				for i in n:
					pieces.append([_box_mesh(Vector3(0.006, 0.004, 0.05)), liquid, Vector3(-0.07 + i * 0.012, 0.058, 0.0)])
		"Race fuel drum":
			size = Vector3(0.2, 0.3, 0.2)
			pieces = [[_cyl_mesh(0.1, 0.3), see, Vector3(0.0, 0.15, 0.0)], [_cyl_mesh(0.02, 0.03), dark, Vector3(0.05, 0.315, 0.0)]]
			if level > 0.01:
				pieces.append([_cyl_mesh(0.094, 0.29 * level), liquid, Vector3(0.0, 0.005 + 0.145 * level, 0.0)])
		"Oil bottle":
			size = Vector3(0.11, 0.3, 0.17)
			pieces = [[_box_mesh(Vector3(0.11, 0.26, 0.17)), see, Vector3(0.0, 0.13, 0.0)],
				[_cyl_mesh(0.025, 0.04), dark, Vector3(0.0, 0.28, -0.04)],
				[_box_mesh(Vector3(0.112, 0.08, 0.1)), dark, Vector3(0.0, 0.12, 0.02)]]
			if level > 0.01:
				pieces.append([_box_mesh(Vector3(0.1, 0.25 * level, 0.16)), liquid, Vector3(0.0, 0.005 + 0.125 * level, 0.0)])
		"Drain pan":
			size = Vector3(0.46, 0.08, 0.46)
			pieces = [[_cyl_mesh(0.23, 0.08, 0.2), body, Vector3(0.0, 0.04, 0.0)]]
			if full > 0.01:
				pieces.append([_cyl_mesh(0.2, 0.006), liquid, Vector3(0.0, 0.01 + 0.06 * full, 0.0)])
		"Bleed bottle":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.85, 0.9, 0.95, 0.35)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			size = Vector3(0.09, 0.2, 0.09)
			pieces = [[_cyl_mesh(0.045, 0.16), glass, Vector3(0.0, 0.08, 0.0)], [_cyl_mesh(0.004, 0.25), dark, Vector3(0.0, 0.2, 0.0)]]
			if full > 0.01:
				pieces.append([_cyl_mesh(0.04, 0.15 * full), liquid, Vector3(0.0, 0.075 * full, 0.0)])
		_:
			size = Vector3(0.08, 0.17, 0.08)
			pieces = [[_cyl_mesh(0.04, 0.14), see, Vector3(0.0, 0.07, 0.0)], [_cyl_mesh(0.022, 0.03), dark, Vector3(0.0, 0.155, 0.0)]]
			if level > 0.01:
				pieces.append([_cyl_mesh(0.036, 0.134 * level), liquid, Vector3(0.0, 0.003 + 0.067 * level, 0.0)])
	for piece in pieces:
		var mi := MeshInstance3D.new()
		mi.mesh = piece[0]
		mi.material_override = piece[1]
		mi.position = piece[2]
		root.add_child(mi)
	root.set_meta("size", size)
	return root


static func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl_mesh(radius: float, height: float, top := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = 24
	return m


## Made-up delivery firms whose shipping labels go on the boxes (no real companies): name, the
## colour of their band, the ink on it and the little mark beside the name.
const COURIERS := [
	{"name": "HEDGEHOG PARCELS", "bg": Color(0.98, 0.78, 0.12), "ink": Color(0.12, 0.1, 0.08), "mark": "disc"},
	{"name": "RAPID ROOSTER", "bg": Color(0.82, 0.12, 0.1), "ink": Color(1.0, 0.95, 0.85), "mark": "chevron"},
	{"name": "SPANNER EXPRESS", "bg": Color(0.12, 0.3, 0.72), "ink": Color(1.0, 1.0, 1.0), "mark": "stripes"},
	{"name": "KWIKKRATE", "bg": Color(0.1, 0.55, 0.3), "ink": Color(1.0, 1.0, 1.0), "mark": "diamond"},
	{"name": "OTTERPOST", "bg": Color(0.42, 0.2, 0.62), "ink": Color(1.0, 0.9, 0.3), "mark": "disc"},
	{"name": "MUDGUARD MAIL", "bg": Color(0.2, 0.2, 0.22), "ink": Color(0.98, 0.6, 0.1), "mark": "stripes"},
	{"name": "PISTON PARCEL CO", "bg": Color(0.95, 0.45, 0.08), "ink": Color(0.1, 0.1, 0.1), "mark": "diamond"},
	{"name": "BOLT & BARREL", "bg": Color(0.0, 0.55, 0.6), "ink": Color(1.0, 1.0, 1.0), "mark": "chevron"},
]
static var _sticker_mats := {}    # colour -> material for shipping labels


## Which delivery firm brought a box: an index into COURIERS, always the same for one box.
static func courier_for(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("courier:%d" % seed_value)
	return rng.randi_range(0, COURIERS.size() - 1)


## The tracking number printed on a box's label, from the same seed.
static func tracking_for(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tracking:%d" % seed_value)
	return "TS %03d %04d %03d" % [rng.randi_range(0, 999), rng.randi_range(0, 9999), rng.randi_range(0, 999)]


## The size a loose part is drawn at (width, height, depth), as it sits on a bench.
static func part_size(part_id: String) -> Vector3:
	if not _part_sizes.has(part_id):
		var probe := part_display(part_id, {})
		_part_sizes[part_id] = probe.get_meta("size", Vector3.ONE * 0.3)
		probe.free()
	return _part_sizes[part_id]


## The size of the cardboard box a part comes in.
static func box_size(part_id: String) -> Vector3:
	return part_size(part_id).max(Vector3(0.15, 0.1, 0.15)) + Vector3(0.06, 0.05, 0.06)


## How much room a part takes up where it's put down (width, height, depth): its box if it's
## still boxed. Used to fit parts onto benches, washers and repair machines.
static func footprint(part_id: String, boxed := false) -> Vector3:
	if boxed:
		return box_size(part_id)
	return part_size(part_id)


static func _sticker_mat(c: Color) -> StandardMaterial3D:
	if not _sticker_mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.65
		_sticker_mats[c] = m
	return _sticker_mats[c]


static func _quad(parent: Node3D, size: Vector2, at: Vector3, c: Color, roll := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = _sticker_mat(c)
	mi.position = at
	mi.rotation.z = roll
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _sticker_text(parent: Node3D, text: String, at: Vector3, fit: Vector2, c: Color, font := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.outline_size = 0
	l.modulate = c
	# Big enough to read, small enough to fit: about 0.7 of the font size a letter.
	l.pixel_size = maxf(0.00012, minf(fit.x / (maxf(1.0, text.length()) * 0.7 * font), fit.y / font))
	l.position = at
	parent.add_child(l)


## A shipping label facing +Z, `w` by `h` metres: the courier's band with its mark and name,
## what's in the box, and the tracking number.
static func _box_sticker(w: float, h: float, part_id: String, seed_value: int) -> Node3D:
	var c: Dictionary = COURIERS[courier_for(seed_value)]
	var root := Node3D.new()
	root.name = "Label"
	_quad(root, Vector2(w, h), Vector3.ZERO, Color(0.95, 0.94, 0.9))
	var band := h * 0.36
	var by := h * 0.5 - band * 0.5
	_quad(root, Vector2(w, band), Vector3(0.0, by, 0.0006), c["bg"])
	# The firm's mark beside its name.
	var m := band * 0.62
	var mx := -w * 0.5 + m * 0.75
	var ink: Color = c["ink"]
	match str(c["mark"]):
		"disc":
			_quad(root, Vector2(m, m) * 0.72, Vector3(mx, by, 0.0012), ink, PI * 0.25)
			_quad(root, Vector2(m, m) * 0.72, Vector3(mx, by, 0.0012), ink)
		"diamond":
			_quad(root, Vector2(m, m) * 0.68, Vector3(mx, by, 0.0012), ink, PI * 0.25)
		"chevron":
			for side in [-1.0, 1.0]:
				_quad(root, Vector2(m * 0.75, m * 0.2), Vector3(mx, by + side * m * 0.2, 0.0012), ink, -side * 0.65)
		_:
			for i in 3:
				_quad(root, Vector2(m * (1.0 - i * 0.25), m * 0.16), Vector3(mx + i * m * 0.12, by + (1 - i) * m * 0.3, 0.0012), ink)
	var name_w := w - m * 1.7
	_sticker_text(root, str(c["name"]), Vector3(mx + m * 0.6 + name_w * 0.5, by, 0.0016), Vector2(name_w * 0.95, band * 0.62), ink)
	_sticker_text(root, PartsDB.part_name(part_id), Vector3(0.0, -h * 0.06, 0.0016), Vector2(w * 0.92, h * 0.24), Color(0.1, 0.09, 0.08))
	_sticker_text(root, tracking_for(seed_value), Vector3(0.0, -h * 0.36, 0.0016), Vector2(w * 0.7, h * 0.12), Color(0.25, 0.25, 0.25), 32)
	return root


## A new part still in its cardboard box, sized to fit it, with a delivery firm's shipping
## label on the lid and the front saying what's inside. `seed_value` (the item id) picks the
## firm and the tracking number, so a box always looks the same.
static func box_display(part_id: String, seed_value := 0) -> Node3D:
	if seed_value == 0:
		seed_value = hash(part_id)
	var size := box_size(part_id)
	if _cardboard == null:
		_cardboard = StandardMaterial3D.new()
		_cardboard.albedo_color = Color(0.66, 0.5, 0.32)
		_cardboard.roughness = 0.95
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _cardboard
	box.position.y = size.y * 0.5
	root.add_child(box)
	var tape := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(0.06, 0.004, size.z + 0.004)
	tape.mesh = strip
	var tape_mat := StandardMaterial3D.new()
	tape_mat.albedo_color = Color(0.8, 0.72, 0.5)
	tape_mat.roughness = 0.4
	tape.material_override = tape_mat
	tape.position.y = size.y + 0.001
	root.add_child(tape)
	# On the lid, lying face up and reading along the box's longer side, from the front when
	# it's wider than deep and from its right-hand side when it's deeper.
	var long_z := size.z > size.x * 1.15
	var across := size.z if long_z else size.x
	var along := size.x if long_z else size.z
	var lw := minf(across * 0.82, 0.32)
	var lh := minf(along * 0.7, lw * 0.62)
	var lid := _box_sticker(lw, lh, part_id, seed_value)
	lid.rotation = Vector3(-PI * 0.5, PI * 0.5 if long_z else 0.0, 0.0)
	lid.rotation_order = EULER_ORDER_YXZ
	lid.position = Vector3(0.0, size.y + 0.0045, 0.0)   # over the tape
	root.add_child(lid)
	# And upright on the front, for a box on a shelf.
	var fw := minf(size.x * 0.8, 0.3)
	var fh := minf(size.y * 0.75, fw * 0.62)
	var front := _box_sticker(fw, fh, part_id, seed_value)
	front.name = "FrontLabel"
	front.position = Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.002)
	root.add_child(front)
	root.set_meta("size", size)
	root.set_meta("courier", courier_for(seed_value))
	return root


func clear_pickers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.free()


# ---------------------------------------------------------------------------- fit checks

## Draws only what the fit checks look at, placed as build_from places them: the bars and the
## clocks (`tail` false) or the tail unit's guard and plate (`tail` true, without its cowl or lamp). Much quicker than a whole bike, for
## running the checks over every build the style builder can come up with.
func build_fit_parts(build: BikeBuild, tail: bool) -> void:
	_build = build
	present = {}
	condition = build.condition
	for child in get_children():
		child.free()
	_rider = null
	for slot in PartsDB.SLOTS:
		_slot_meshes[slot] = []
	_rear_guard.clear()
	_plates.clear()
	_flat_tyres.clear()
	_dash_face = PackedVector3Array()
	_lay_out(build)
	_layout_cylinders(build)
	_add_steer_node()
	_add_rear_hub()
	_fit_only = true
	if tail:
		_draw_tail(build)
	else:
		_draw_handlebars()
		_draw_dashboard()
	_fit_only = false
	_current_slot = ""


## Draws only the frame, the tank and the engine and its head, placed as build_from places them,
## for checking the engine sits in its frame (see engine_clash) over many builds quickly.
func build_engine_bay(build: BikeBuild) -> void:
	_build = build
	present = {}
	condition = build.condition
	for child in get_children():
		child.free()
	_rider = null
	for slot in PartsDB.SLOTS:
		_slot_meshes[slot] = []
	_tank_secs = []
	_rails = []
	var zr := _lay_out(build)
	_layout_cylinders(build)
	_draw_frame(build, zr)
	_draw_tank()
	_draw_engine()
	_draw_head()
	_current_slot = ""


## How far the engine (its cases, barrels and heads, or the parts in `slots`) cuts into the frame's
## tubes and the tank, in m (0 when it's clear): {"tube": deepest into a frame tube, "tank": highest
## above the tank's underside, "where": the deepest clash's engine piece}. A tube clashes where an engine corner
## comes inside it or its middle line runs through an engine piece; the tank where an engine corner
## comes up past the tank's underside within its width.
func engine_clash(slots: Array = ["engine", "head"]) -> Dictionary:
	var out := {"tube": 0.0, "tank": 0.0, "where": ""}
	var pieces := []
	for slot in slots:
		for mi in _slot_meshes.get(slot, []):
			if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
				continue
			var xf := _local_xform(mi)
			var mesh := (mi as MeshInstance3D).mesh
			var pts := PackedVector3Array()
			for k in mesh.get_surface_count():
				pts.append_array(mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX])
			for i in pts.size():
				pts[i] = xf * pts[i]
			pieces.append({"mi": mi, "xf": xf, "pts": pts, "box": xf * mesh.get_aabb()})
	# The tank: its underside runs along the top tube (see tank_base_y), as wide as each section.
	if not _tank_secs.is_empty():
		var z0 := float((_tank_secs[0]["c"] as Vector3).z)
		var z1 := float((_tank_secs[_tank_secs.size() - 1]["c"] as Vector3).z)
		var floor_y := minf(tank_base_y(z0), tank_base_y(z1))
		for pc in pieces:
			var box: AABB = pc["box"]
			if box.end.y < floor_y or box.end.z < z0 or box.position.z > z1:
				continue
			for v: Vector3 in pc["pts"]:
				if v.z < z0 or v.z > z1 or v.y < floor_y or absf(v.x) > tank_top_at(v.z).y:
					continue
				var over := v.y - tank_base_y(v.z)
				if over > out["tank"]:
					out["tank"] = over
					out["where"] = "%s under the tank" % (pc["mi"] as Node).name
	for rail in _rails:
		var r := float(rail["r"])
		var path: Array = rail["pts"]
		for k in path.size() - 1:
			var a: Vector3 = path[k]
			var b: Vector3 = path[k + 1]
			var seg := AABB(a, Vector3.ZERO).expand(b).grow(r)
			for pc in pieces:
				var box: AABB = pc["box"]
				if not box.intersects(seg):
					continue
				# Engine corners inside the tube.
				for v: Vector3 in pc["pts"]:
					if seg.has_point(v):
						var d := r - v.distance_to(Geometry3D.get_closest_point_to_segment(v, a, b))
						if d > out["tube"]:
							out["tube"] = d
							out["where"] = "%s in a frame tube" % (pc["mi"] as Node).name
				# The tube's middle running through the piece.
				var steps := maxi(1, ceili(a.distance_to(b) / 0.005))
				for j in steps + 1:
					var p := a.lerp(b, float(j) / steps)
					if box.has_point(p) and _inside(pc, p) and r > out["tube"]:
						out["tube"] = r
						out["where"] = "a frame tube through %s" % (pc["mi"] as Node).name
	return out


## Whether model-space point `p` is inside an engine piece (as engine_clash lists them): an odd
## number of its faces crossed going straight up from it.
func _inside(pc: Dictionary, p: Vector3) -> bool:
	if not pc.has("tm"):
		pc["tm"] = (pc["mi"] as MeshInstance3D).mesh.generate_triangle_mesh()
	var tm: TriangleMesh = pc["tm"]
	var inv: Transform3D = (pc["xf"] as Transform3D).affine_inverse()
	var from := inv * p
	var to := inv * (p + Vector3(0.0123, 3.0, 0.0371))
	var hits := 0
	for i in 64:
		var hit := tm.intersect_segment(from, to)
		if hit.is_empty():
			break
		hits += 1
		from = (hit["position"] as Vector3) + (to - from).normalized() * 0.0002
	return hits % 2 == 1


## How far a number plate cuts into the rear mudguard (m; 0 when it's clear): the deepest
## overlap of a plate's box with any piece of the guard.
func plate_cut() -> float:
	var worst := 0.0
	for plate in _plates:
		var a := _obb(plate)
		for piece in _rear_guard:
			worst = maxf(worst, _obb_push(a, _obb(piece)).length())
	return worst


## How far the rear tyre comes up through the rear mudguard with the shock compressed by
## `travel` (all of its travel by default), in m: the deepest point of a guard piece inside the
## tyre's own section (see tyre_mesh).
func tyre_through_guard(travel := -1.0) -> float:
	var worst := 0.0
	for piece in _rear_guard:
		worst = maxf(worst, _tyre_depth(piece, travel))
	return worst


## How deep into the rear tyre one piece of the mudguard goes (m; 0 or less when clear), with
## the shock compressed by `travel` (all of it by default): over a grid of points on both faces.
func _tyre_depth(piece: MeshInstance3D, travel := -1.0) -> float:
	var t := _build.rear_travel if travel < 0.0 else travel
	var axle := Vector3(0.0, t, _build.wheelbase * 0.5)
	var r := _build.rear_radius
	var half := _build.rear_tyre_width * 0.5
	var bulge := _build.rear_rim_radius + (r - _build.rear_rim_radius) * 0.4
	var style := str(PartsDB.get_part(str(_build.parts.get("rear_tyre", ""))).get("style", "road"))
	var p := 2.0 if style in ["slick", "road"] else 2.8
	var o := _obb(piece)
	var worst := -INF
	for i in 5:
		for j in 5:
			for k in [-1.0, 1.0]:
				var at: Vector3 = o[0] + o[1] * (i * 0.5 - 1.0) + o[2] * k + o[3] * (j * 0.5 - 1.0)
				var x := absf(at.x) / half
				if x >= 1.0:
					continue
				var crown := bulge + (r - bulge) * pow(1.0 - pow(x, p), 1.0 / p)
				worst = maxf(worst, crown - Vector2(at.y - axle.y, at.z - axle.z).length())
	return worst


## The share (0..1) of the clocks' faces the bars and what's on them hide from the rider's eye,
## sat on the seat with the bars straight.
func dash_hidden() -> float:
	var bars := _bars_mesh()
	if _dash_face.is_empty() or bars == null:
		return 0.0
	return float(_face_hidden(bars, _local_xform(_steer_node).affine_inverse() * _eye)) / _dash_face.size()


## As dash_hidden, for the rider's eye at `eye` (in steering space) with the clocks raised as
## they would be for it (see _lift_clear_of_bars): for the fit checks to try one set of bars and
## clocks from every seat they could be ridden from without drawing them again.
func dash_hidden_from(eye: Vector3) -> float:
	var bars := _bars_mesh()
	if _dash_face.is_empty() or bars == null:
		return 0.0
	var lift := _dash_lift(bars, eye)
	return float(_face_hidden(bars, eye, lift - _dash_raised)) / _dash_face.size()


## A mesh's box in the model's space, grown by `grow` all round: [centre, and the three
## half-size axes].
func _obb(mi: MeshInstance3D, grow := 0.0) -> Array:
	var xf := _local_xform(mi)
	var box := mi.mesh.get_aabb().grow(grow)
	return [xf * box.get_center(), xf.basis.x * box.size.x * 0.5, xf.basis.y * box.size.y * 0.5, xf.basis.z * box.size.z * 0.5]


## How far, and which way, box `a` has to move to come out of box `b` (both as _obb gives
## them): the shortest way out along the axes that could part them, Vector3.ZERO when they
## don't overlap.
static func _obb_push(a: Array, b: Array) -> Vector3:
	var axes: Array[Vector3] = []
	for i in 3:
		axes.append((a[i + 1] as Vector3).normalized())
		axes.append((b[i + 1] as Vector3).normalized())
	for i in 3:
		for j in 3:
			var n := (a[i + 1] as Vector3).cross(b[j + 1])
			if n.length() > 1e-6:
				axes.append(n.normalized())
	var least := INF
	var way := Vector3.ZERO
	var gap: Vector3 = a[0] - b[0]
	for n in axes:
		var reach := 0.0
		for i in 3:
			reach += absf((a[i + 1] as Vector3).dot(n)) + absf((b[i + 1] as Vector3).dot(n))
		var overlap := reach - absf(gap.dot(n))
		if overlap <= 0.0:
			return Vector3.ZERO
		if overlap < least:
			least = overlap
			way = n * (overlap if gap.dot(n) >= 0.0 else -overlap)
	return way


func _local_xform(node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != self and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# ---------------------------------------------------------------------------- materials

## A material for the part being built, weathered by that part's rust and dirt.
func _mat(color: Color, metallic: float, roughness: float, clearcoat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.1
	var cond: Dictionary = condition.get(_current_slot, {}) if _current_slot != "" else {}
	# The painted surfaces: where a spray job's coat is drawn (SprayMarks), and in grey primer
	# while that's the top coat (the colour stays underneath until it's painted over).
	if cond.has("color") and color == cond["color"]:
		m.set_meta("paint_surface", true)
		if cond.get("primer", false):
			m.albedo_color = Shed.PRIMER_COLOR
			m.metallic = 0.0
			m.roughness = 0.82
			m.clearcoat_enabled = false
			color = Shed.PRIMER_COLOR
			metallic = 0.0
			roughness = 0.82
			cond = cond.duplicate()
			cond.erase("finish")
			cond.erase("coat")
	# A sprayed finish only goes on the painted surfaces, not the rubber or chrome bits.
	var finish := str(cond.get("finish", ""))
	var mixed: bool = not cond.get("primer", false) and ((cond.get("mix") is Dictionary) or (cond.get("mask") is Dictionary) \
		or (cond.get("tape") is Dictionary) or float(cond.get("flat", 0.0)) > 0.0)
	if mixed and cond.has("color") and color == cond["color"]:
		# Paint mixed in the mixing bay: its effect, masked stripes, tape and sheen (PaintMix).
		PaintMix.apply(m, cond)
		metallic = m.metallic
		roughness = m.roughness
	elif finish != "" and cond.has("color") and color == cond["color"]:
		_apply_finish(m, color, finish)
		metallic = m.metallic
		roughness = m.roughness
	# A clear protective coat over paint adds its own gloss.
	var lacquer := Shed.coat_gloss(str(cond.get("coat", ""))) if cond.has("coat") else 0.0
	if lacquer > 0.0 and cond.has("color") and color == cond["color"]:
		m.clearcoat_enabled = true
		m.clearcoat = maxf(m.clearcoat, lacquer)
		m.clearcoat_roughness = 0.05
		m.roughness = m.roughness * (1.0 - 0.4 * lacquer)
		roughness = m.roughness
	# Road dirt isn't tinted in: it's drawn over the part where it really is (see DirtLayer).
	var rust := float(cond.get("rust", 0.0))
	if rust > 0.05:
		# Rust creeps in as patches: a blotchy mask that grows with the rust level.
		m.detail_enabled = true
		m.detail_mask = _rust_mask(rust)
		m.detail_albedo = _rust_texture()
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		m.metallic = metallic * (1.0 - rust * 0.7)
		m.roughness = lerpf(roughness, 0.95, rust)
		m.clearcoat_enabled = m.clearcoat_enabled and rust < 0.4
	return m


## Gloss is wet-look clear coat, matte soaks up the light, metallic has flake under the lacquer,
## chrome is a tinted mirror and patina is faded, mottled old paint.
static func _apply_finish(m: StandardMaterial3D, color: Color, finish: String) -> void:
	m.clearcoat_enabled = false
	match finish:
		"gloss":
			m.metallic = 0.05
			m.roughness = 0.12
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
		"matte":
			m.metallic = 0.0
			m.roughness = 0.9
			m.albedo_color = color.darkened(0.08)
		"metallic":
			m.metallic = 0.8
			m.roughness = 0.32
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.05
			m.albedo_color = color.lightened(0.08)
		"chrome":
			m.metallic = 1.0
			m.roughness = 0.1
			m.albedo_color = color.lerp(Color(0.97, 0.97, 0.99), 0.7)
		"patina":
			m.metallic = 0.15
			m.roughness = 0.78
			var faded := Color.from_hsv(color.h, color.s * 0.55, color.v * 0.8)
			m.albedo_color = faded
			m.detail_enabled = true
			m.detail_mask = _rust_mask(0.45)
			m.detail_albedo = _patina_texture()
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)


static func _patina_texture() -> NoiseTexture2D:
	if _patina_albedo:
		return _patina_albedo
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.58, 0.5))
	ramp.set_color(1, Color(0.95, 0.93, 0.88))
	_patina_albedo = NoiseTexture2D.new()
	_patina_albedo.width = 256
	_patina_albedo.height = 256
	_patina_albedo.seamless = true
	_patina_albedo.noise = noise
	_patina_albedo.color_ramp = ramp
	return _patina_albedo


## A lens or lit face that only glows with the ignition on ("ign": tail light, clocks), the
## headlight switched on too ("head") or the fog lights switched on ("fog").
func _lamp(color: Color, energy: float, group: String) -> StandardMaterial3D:
	var m := _glow(color, energy)
	_lamps.append({"mat": m, "albedo": m.albedo_color, "energy": energy, "group": group})
	return m


## Lights the lenses and clocks: `ignition` for the engine running, `headlight` for the
## headlight switched on as well, `fog` for the fog lamps. Unlit, the lenses are dull glass.
func set_lights(ignition: bool, headlight: bool, fog := false) -> void:
	headlight = headlight and ignition
	fog = fog and ignition
	if _satnav_glow != null and absf(Daylight.darkness() - _satnav_dark) > 0.02:
		_show_satnav()   # dusk coming on (or dawn): the screen's glow follows it
	if _lit[0] == ignition and _lit[1] == headlight and _lit[2] == fog:
		return
	_lit = [ignition, headlight, fog]
	_show_satnav()
	_show_lamps()


## The stop lamp and the indicators, on top of set_lights: `brake` lights the rear light bright
## (and a small red lamp behind it), `left` and `right` each side's indicators (the caller
## flashes them; see BikeLamps). All need the ignition on.
func set_signals(brake: bool, left: bool, right: bool) -> void:
	if _signals[0] == brake and _signals[1] == left and _signals[2] == right:
		return
	_signals = [brake, left, right]
	_show_lamps()


## The signals as set (see set_signals): [stop lamp, left indicators, right indicators].
func signals() -> Array:
	return _signals.duplicate()


## Whether the stop lamp is glowing bright (braking with the ignition on).
func stop_lit() -> bool:
	return _signals[0] and _lit[0]


## Lights each lens by its group: the clocks and most lenses with the ignition, the headlight's
## and fog lamps' with their switch, the rear light dim with the headlight and bright braking,
## and the indicators while they flash on.
func _show_lamps() -> void:
	var ign: bool = _lit[0]
	for l in _lamps:
		var energy := float(l["energy"])
		var on := ign
		match str(l["group"]):
			"head":
				on = _lit[1]
			"fog":
				on = _lit[2]
			"tail":
				on = _lit[1] or (ign and _signals[0])
				if ign and _signals[0]:
					energy = STOP_ENERGY
			"ind_l":
				on = ign and _signals[1]
			"ind_r":
				on = ign and _signals[2]
		var m: StandardMaterial3D = l["mat"]
		var c: Color = l["albedo"]
		m.emission_enabled = on
		m.emission_energy_multiplier = energy if on else 0.0
		# Unlit, a lens is dull glass; indicators stay plainly amber.
		m.albedo_color = c if on else c.darkened(0.3 if str(l["group"]).begins_with("ind") else 0.6)
	if _stop_glow:
		_stop_glow.visible = stop_lit() and is_fitted("tail")


## Whether any lens or clock is glowing.
func lights_lit() -> bool:
	return _lit[0] or _lit[1] or _lit[2]


## Whether the fog lamp lenses are glowing.
func fog_lit() -> bool:
	return _lit[2]


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.0, 0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _rust_mask(rust: float) -> NoiseTexture2D:
	var level := clampi(roundi(rust * 10.0), 1, 10)
	if _rust_masks.has(level):
		return _rust_masks[level]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var edge := 1.0 - level / 10.0 * 0.85
	var ramp := Gradient.new()
	ramp.set_color(0, Color.BLACK)
	ramp.set_color(1, Color.WHITE)
	ramp.add_point(clampf(edge - 0.06, 0.01, 0.98), Color.BLACK)
	ramp.add_point(clampf(edge + 0.04, 0.02, 0.99), Color.WHITE)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	_rust_masks[level] = tex
	return tex


static func _rust_texture() -> NoiseTexture2D:
	if _rust_albedo:
		return _rust_albedo
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.09, 0.04))
	ramp.set_color(1, Color(0.48, 0.24, 0.1))
	_rust_albedo = NoiseTexture2D.new()
	_rust_albedo.width = 256
	_rust_albedo.height = 256
	_rust_albedo.seamless = true
	_rust_albedo.noise = noise
	_rust_albedo.color_ramp = ramp
	return _rust_albedo


# ---------------------------------------------------------------------------- mesh helpers

func _mesh_instance(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if _current_slot != "":
		_slot_meshes[_current_slot].append(mi)
	return mi


func _box(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(mesh, mat, center, parent)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


func _torus(radius: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - thick
	t.outer_radius = radius + thick
	t.rings = 16
	t.ring_segments = 6
	return t


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


## A cylinder along local Y. A negative top radius means the same as the bottom.
func _cylinder(radius: float, height: float, top := -1.0, segments := 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = segments
	return c


## A cylinder from a to b. `stretch` scales its cross-section (x, z) and length (y).
func _tube(a: Vector3, b: Vector3, radius: float, mat: Material, stretch := Vector3.ONE, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(a.distance_to(b), 0.001)
	mesh.radial_segments = 12
	mesh.rings = 1
	var mi := _mesh_instance(mesh, mat, (a + b) * 0.5, parent)
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	var rot := Basis()
	if axis.length() > 0.0001:
		rot = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	elif dir.y < 0.0:
		rot = Basis(Vector3.RIGHT, PI)
	mi.basis = rot * Basis.from_scale(stretch)
	if _current_slot == "frame" and parent == self:
		_rails.append({"pts": [a, b], "r": radius * maxf(stretch.x, stretch.z)})
	return mi


## How the fitted frame places a mounting point (see build_from), or `default`.
func _geo(key: String, default: float) -> float:
	return float(_frame_geo.get(key, default))


## A lofted shell (see ShapeKit.loft) for the part being drawn.
func _shell(sections: Array, mat: Material, open := false, a0 := 0.0, a1 := TAU, parent: Node3D = self) -> MeshInstance3D:
	return _mesh_instance(ShapeKit.loft(sections, ShapeKit.RING, open, a0, a1), mat, Vector3.ZERO, parent)


## A round tube bent smoothly through `path` (see ShapeKit.sweep): `radius` a float, or one per point.
func _bend(path: Array, radius, mat: Material, parent: Node3D = self, sides := 12) -> MeshInstance3D:
	var mi := _mesh_instance(ShapeKit.sweep(path, radius, sides), mat, Vector3.ZERO, parent)
	if _current_slot == "frame" and parent == self:
		_rails.append({"pts": ShapeKit.smooth(path, 6), "r": (radius as Array).max() if radius is Array else float(radius)})
	# Its line and thickness, so its click target follows the tube (see build_pickers) rather
	# than filling the whole box round the bend.
	var thick := 0.0
	for r in (radius if radius is Array else [radius]):
		thick = maxf(thick, float(r))
	_bends[mi.get_instance_id()] = {"path": path, "r": thick}
	return mi


## Marks a mesh that joins the part being drawn to another part (a cable, hose or lead): drawn
## on the bike, left off when the part is shown loose (see assembly_display).
func _bike_only(mi: MeshInstance3D) -> MeshInstance3D:
	mi.set_meta("bike_only", true)
	return mi


## `m` with one of TextureKit's surface textures on it (knurl, quilt, grain, carbon, brushed,
## crinkle, core).
func _tex(m: StandardMaterial3D, kind: String, scale := -1.0, strength := 1.0) -> StandardMaterial3D:
	TextureKit.apply(m, kind, scale, strength)
	return m


## The surface the part being drawn is made of, from its "surface" (in its look) or its name:
## carbon fibre weave, brushed alloy or titanium, or nothing special.
func _surface() -> String:
	var p := _part()
	var lk: Dictionary = p.get("look", {})
	if lk.has("surface"):
		return str(lk["surface"])
	var words := (_part_id() + " " + str(p.get("name", "")) + " " + str(p.get("type", "")) + " " + str(p.get("material", ""))).to_lower()
	# A painted carbon part (a white race fairing) shows its paint, not the weave.
	if "carbon" in words and not ("white" in words or "painted" in words):
		return "carbon"
	for w in ["brushed", "alloy", "alumin", "titanium", "billet"]:
		if w in words and not ("black" in words or "painted" in words or "gold" in words):
			return "brushed"
	return ""


## `m` in the part's own surface (see _surface).
func _skin(m: StandardMaterial3D) -> StandardMaterial3D:
	match _surface():
		"carbon":
			m.metallic = 0.25
			m.roughness = 0.3
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.04
			return _tex(m, "carbon")
		"brushed":
			m.metallic = maxf(m.metallic, 0.9)
			m.roughness = clampf(m.roughness, 0.28, 0.42)
			return _tex(m, "brushed")
	return m
