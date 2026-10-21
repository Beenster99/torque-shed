class_name SalesView
extends Node3D
## What selling looks and sounds like in the world, drawn from Shed.sales (see Sales) on every
## player's game; nothing here is shared state.
##   - Part-exchange buyers ride their own bike in, park it on the forecourt, walk in to the bike
##     they're after and stand by it (quietly: no shop bell rings as they come in). Look at one and
##     press F to open the Sales page on them. Sent away, they ride off on their own bike; with
##     a deal done they get on yours and ride it away, and theirs stays.
##   - A buyer whose offer was taken walks in from the car park, gets on the bike and rides it out
##     through the doors and away.
##   - A cash till rings at the office PC, with a chime in the shed, each time a buyer sends an
##     offer or answers one ("sale_offer").
##   - The price cards on the display stands show each bike and its price, and the office PC's
##     big screen shows what's on sale and who's waiting.
## Main makes one and puts it in the world (like ContractsView).

signal talk_requested(px_id: int)

const REACH := 3.5
## The till's sound, and where it's heard: at the office PC and, quieter, in the shed.
const TILL := "sale_offer"
const PC_POS := SalesOffice.CENTER + Vector3(-2.66, SalesOffice.MEZZ_Y + 1.2, 1.0)

var main: Node                 # for the walker and whether a menu is open
var views := {}                # part-exchange id -> CustomerView
var collecting := {}           # collect entry id -> CustomerView (null once seen or skipped)
var browsing := {}             # browser id -> StaffFigure, having a look round (SalesBrowse)
var _clock := 0.0              # the sales clock the browsers are drawn by (see _browse_clock)
## Times the till has rung here (tests).
var tills := 0
var _alerts_seen := -1
var _looked := 0
var _screen_timer := 0.0


func _ready() -> void:
	Shed.changed.connect(sync_state)


## Brings the figures, the till, the stands' price cards and the office screen into line with
## Shed.sales.
func sync_state() -> void:
	if not Shed.active:
		for id in views.keys():
			if is_instance_valid(views[id]):
				views[id].queue_free()
		views.clear()
		collecting.clear()
		for id in browsing.keys():
			if is_instance_valid(browsing[id]):
				browsing[id].queue_free()
		browsing.clear()
		_alerts_seen = -1
		return
	_ring_till()
	_sync_px()
	_sync_collect()
	_sync_browse()
	update_signs()


## The till rings for each new offer or answer since last time (not for the ones already there
## when the shed opened or was joined).
func _ring_till() -> void:
	var alerts := int(Sales._st().get("alerts", 0))
	if _alerts_seen >= 0 and alerts > _alerts_seen:
		ring_till()
	_alerts_seen = alerts


## The till's bell rings only for those indoors, not out along the High Street (see Sfx.indoors).
func ring_till() -> void:
	tills += 1
	if not Sfx.indoors():
		return
	Sfx.play_at(TILL, PC_POS, 0.0)
	Sfx.play_at(TILL, SalesOffice.SHED_CHIME_POS, -8.0)


# ---------------------------------------------------------------------------- paths

## Just outside and just inside the sales office's front doors.
static func door_out() -> Vector3:
	return SalesOffice.SALES_DOOR + Vector3(0.0, 0.0, 1.3)


static func door_in() -> Vector3:
	return SalesOffice.SALES_DOOR + Vector3(0.0, 0.0, -1.3)


## Where a visitor stands to look at the bike on stand `i`: in front of its plinth towards the
## doors, and which way they face (-Z at the bike).
static func viewing_xf(i: int) -> Transform3D:
	var o: Vector3 = SalesOffice.SHOWROOM_SPOTS[clampi(i, 0, SalesOffice.SHOWROOM_SPOTS.size() - 1)].origin
	o.y = 0.0
	var d := door_in() - o
	d.y = 0.0
	var at := o + d.normalized() * (SalesOffice.PLINTH_RADIUS + 0.45)
	var look := o - at
	return Transform3D(Basis(Vector3.UP, atan2(-look.x, -look.z)), at)


## A part-exchange buyer's ride in: along the road past the yard and up onto the forecourt,
## into their spot by the glass (their own way, with a `rider` id: see Contracts.ride_in_path).
static func px_ride_in(park: int, rider := -1) -> PackedVector3Array:
	return Contracts.ride_in_to(Sales.PX_SPOTS[clampi(park, 0, Sales.PX_SPOTS.size() - 1)].origin, rider)


## Their walk from their bike in through the doors to the bike they're after.
static func px_walk(p: Dictionary) -> PackedVector3Array:
	var spot := Sales.PX_SPOTS[clampi(int(p.get("park", 0)), 0, Sales.PX_SPOTS.size() - 1)].origin
	var side := spot + Vector3(-0.75, 0.0, 0.4)
	var stand := Sales.stand_of(int(p.get("target", 0)))
	var pts := PackedVector3Array([side, Vector3(side.x, 0.0, 72.4), door_out() + Vector3(0.0, 0.0, 0.4), door_in(),
		viewing_xf(maxi(stand, 0)).origin])
	return pts


## A buyer's walk in from the car park edge to the side of the bike on its stand at `xf`.
static func collect_walk(xf: Transform3D, from := Vector3.INF) -> PackedVector3Array:
	var side := xf.origin + xf.basis.x * 0.8
	side.y = 0.0
	if from != Vector3.INF:
		return PackedVector3Array([from, side])
	return PackedVector3Array([Contracts.entry().origin, door_out(), door_in(), side])


## The ride away from a stand: out through the doors, across the forecourt clear of the car
## park bays, and off along the road (their own way, with a `rider` id).
static func ride_out(xf: Transform3D, rider := -1) -> PackedVector3Array:
	var pts := PackedVector3Array([Vector3(xf.origin.x, 0.0, xf.origin.z), door_in() + Vector3(0.0, 0.0, -0.6), door_out() + Vector3(0.0, 0.0, 1.0),
		Vector3(SalesOffice.SALES_DOOR.x + 3.0, 0.0, 77.0)])
	var away := Contracts.ride_out_path(Transform3D(Basis(), Vector3(SalesOffice.FORECOURT.end.x + 1.0, 0.0, 77.0)), rider)
	for p in away:
		pts.append(p)
	return pts


## Real seconds since the sales clock read `at`.
static func _since(at: float) -> float:
	return (Sales.clock() - at) / maxf(Contracts.hours_rate(), 0.000001)


static func _length(pts: PackedVector3Array) -> float:
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k].distance_to(pts[k - 1])
	return length


## A visitor's bike as CustomerView draws it: {parts, paint, cond}, its tank and fairing painted.
static func _bike_look(parts: Dictionary, paint: Color, cond: Dictionary) -> Dictionary:
	var c: Dictionary = cond.duplicate(true)
	for slot in ["tank", "fairing"]:
		if c.has(slot) and c[slot] is Dictionary and not c[slot].has("color"):
			c[slot]["color"] = paint
	return {"parts": parts, "paint": paint, "cond": c}


# ---------------------------------------------------------------------------- figures

func _sync_px() -> void:
	for id in views.keys():
		if not Sales.px().has(id):
			var v: CustomerView = views[id]
			views.erase(id)
			if not is_instance_valid(v):
				continue
			var deal := _collect_for(int(id))
			if deal.is_empty():
				v.leave(true)   # sent away, or tired of waiting: back on their own bike and off
			else:
				# The deal's done: their bike is the shed's now; they ride off on ours.
				v.set_process(false)   # no last frame riding a bike it no longer has
				v.drop_bike()
				_start_collect(deal, v.global_position)
				v.queue_free()
	for id in Sales.px():
		if views.has(id):
			continue
		var p: Dictionary = Sales.px()[id]
		var walk := px_walk(p)
		var ride := px_ride_in(int(p.get("park", 0)), Sales.PX_ID_BASE + int(id))
		var paint: Color = Shed.PAINTS[int(p.get("paint", 0)) % Shed.PAINTS.size()]
		var secs := _length(walk) / Contracts.WALK_SPEED + _length(ride) / Contracts.RIDE_SPEED * 1.5 + 2.0
		var v := CustomerView.new()
		add_child(v)
		var stand := Sales.stand_of(int(p.get("target", 0)))
		v.setup({"id": Sales.PX_ID_BASE + int(id), "name": p.get("name", "Buyer"), "look": p.get("look", {})}, walk,
			viewing_xf(maxi(stand, 0)).basis, _since(float(p.get("arrived", 0.0))) > secs, ride,
			_bike_look(p.get("parts", {}), paint, p.get("cond", {})))
		views[id] = v


## The collect entry of the part-exchange deal with visitor `px_id`, or {}.
func _collect_for(px_id: int) -> Dictionary:
	for d in Sales._st().get("collect", []):
		if d is Dictionary and int(d.get("visitor", -1)) == px_id:
			return d
	return {}


func _sync_collect() -> void:
	for d in Sales._st().get("collect", []):
		if not (d is Dictionary) or not (d.get("xf") is Transform3D) or collecting.has(int(d.get("id", 0))):
			continue
		var walk := collect_walk(d["xf"])
		var ride := ride_out(d["xf"], Sales.BUYER_ID_BASE + int(d.get("id", 0)))
		var secs := _length(walk) / Contracts.WALK_SPEED + _length(ride) / Contracts.RIDE_SPEED * 1.5 + 2.0
		if _since(float(d.get("at", 0.0))) > secs:
			collecting[int(d["id"])] = null
			continue
		_start_collect(d)


## A buyer comes for the bike they bought (from `from` when they're already in the showroom),
## gets on it and rides away.
func _start_collect(d: Dictionary, from := Vector3.INF) -> void:
	var id := int(d.get("id", 0))
	if collecting.has(id):
		return
	var xf: Transform3D = d["xf"]
	var v := CustomerView.new()
	add_child(v)
	v.setup_collect({"id": Sales.BUYER_ID_BASE + id, "name": d.get("name", ""), "look": d.get("look", {})}, collect_walk(xf, from),
		{"parts": d.get("parts", {}), "paint": d.get("paint"), "cond": d.get("cond", {})}, xf, ride_out(xf, Sales.BUYER_ID_BASE + id))
	collecting[id] = v


## Buyers looking round the showroom (SalesBrowse): a figure for each, gone when they've gone.
func _sync_browse() -> void:
	var list := SalesBrowse.browsers()
	for id in browsing.keys():
		if not list.has(id):
			if is_instance_valid(browsing[id]):
				browsing[id].queue_free()
			browsing.erase(id)
	for id in list:
		if browsing.has(id):
			continue
		var b: Dictionary = list[id]
		var f := StaffFigure.new()
		add_child(f)
		f.build({"id": Sales.BUYER_ID_BASE + int(id), "name": b.get("name", "Buyer"), "role": "browser", "look": b.get("look", {})})
		f.body.collision_layer = 0
		f.add_to_group(SalesOffice.VISITOR_GROUP)
		browsing[id] = f
		_browse_clock(0.0)
		_pose_browser(f, b, 0.0)


## The sales clock as the browsers are drawn by: the host's own, a joiner's run on between
## syncs (the clock only comes over now and then) and never put back.
func _browse_clock(delta: float) -> float:
	if Shed.is_authority() or _clock < Sales.clock():
		_clock = Sales.clock()
	else:
		_clock += delta * Contracts.hours_rate()
	return _clock


## Puts browser `b`'s figure where they are now, doing what they're doing.
func _pose_browser(f: StaffFigure, b: Dictionary, delta: float) -> void:
	var p := SalesBrowse.pose(b, (_clock - float(b.get("at", 0.0))) / maxf(Contracts.hours_rate(), 0.000001))
	f.visible = not p["gone"]
	if p["gone"]:
		return
	var yaw := float(p["yaw"])
	if f.position.distance_to(p["pos"]) > 1.5 or delta <= 0.0:
		f.rotation.y = yaw
	else:
		f.rotation.y = lerp_angle(f.rotation.y, yaw, minf(1.0, delta * 8.0))
	f.position = p["pos"]
	var act := str(p["act"])
	f.animate(maxf(delta, 0.0), bool(p["walking"]), false, false, act, act == "crouch")


# ---------------------------------------------------------------------------- signs

## The stands' price cards and the office PC's screen.
func update_signs() -> void:
	var office := get_tree().get_first_node_in_group("sales_office") if is_inside_tree() else null
	if office == null or not office.has_method("stand_tag"):
		return
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		var tag: Label3D = office.stand_tag(i)
		if tag:
			tag.text = stand_card(i)
	var screen: Label3D = office.screen_text()
	if screen:
		Controls.bind_text(screen, screen_lines())


## What stand `i`'s price card says.
static func stand_card(i: int) -> String:
	var b := Sales.bike_on_stand(i)
	if b == 0:
		return "STAND %d\n\nfree" % (i + 1)
	var nm := str(Shed.bikes[b]["name"]).left(16)
	if Sales.listings().has(b):
		return "%s\n\n%s" % [nm, Sales.money(int(Sales.listings()[b]["ask"]))]
	return "%s\n\nON SHOW" % nm


## The office PC's big screen: what's on the stands, offers and part-exchange buyers waiting.
static func screen_lines() -> String:
	var lines := ["TORQUE SHED SALES", ""]
	for i in SalesOffice.SHOWROOM_SPOTS.size():
		var b := Sales.bike_on_stand(i)
		if b == 0:
			lines.append("Stand %d  ·  free" % (i + 1))
		else:
			var ask := int(Sales.listings().get(b, {}).get("ask", 0))
			lines.append("Stand %d  ·  %s  ·  %s" % [i + 1, str(Shed.bikes[b]["name"]).left(18), Sales.money(ask) if ask > 0 else "not priced"])
	lines.append("")
	var open := Sales.offers().values().filter(func(o): return str(o["state"]) == "open")
	lines.append("%d offer%s waiting" % [open.size(), "" if open.size() == 1 else "s"] if not open.is_empty() else "No offers waiting")
	for p in Sales.px().values():
		lines.append("Part-ex: %s, by %s" % [str(p["name"]), str(p["target_name"]).left(16)])
	lines.append("")
	lines.append("{interact}: open the Sales page")
	return "\n".join(lines)


# ---------------------------------------------------------------------------- talking to them

## The part-exchange buyer under the crosshair of the player on foot, or 0.
func looked_at() -> int:
	if main == null or main.walker == null or main.bike != null:
		return 0
	if Shed.pushing_bike(Shed.me()) != 0 or Shed.moving(Shed.me()) != 0:
		return 0
	var cam: Camera3D = main.walker.camera
	if cam == null or not cam.is_inside_tree():
		return 0
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH, Workshop.INTERACT_LAYER | 1)
	q.exclude = [main.walker.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and (hit["collider"] as Object).has_meta("customer"):
		var id := int((hit["collider"] as Object).get_meta("customer")) - Sales.PX_ID_BASE
		if views.has(id) and is_instance_valid(views[id]) and (views[id] as CustomerView).at_counter:
			return id
	return 0


func _process(delta: float) -> void:
	var pt := Perf.t0()
	_process_body(delta)
	Perf.add("sales_visitors", pt)


func _process_body(delta: float) -> void:
	var id := looked_at() if main and main.walker and main.walker.controls_enabled else 0
	if id != _looked:
		if views.has(_looked) and is_instance_valid(views[_looked]):
			(views[_looked] as CustomerView).set_hint(false)
		if views.has(id):
			(views[id] as CustomerView).set_hint(true)
		_looked = id
	if not browsing.is_empty():
		_browse_clock(delta)
		var list := SalesBrowse.browsers()
		for bid in browsing:
			if list.has(bid) and is_instance_valid(browsing[bid]):
				_pose_browser(browsing[bid], list[bid], delta)
	_screen_timer -= delta
	if _screen_timer <= 0.0 and Shed.active:
		_screen_timer = 1.0
		update_signs()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or main == null or main.walker == null or not main.walker.controls_enabled:
		return
	var id := looked_at()
	if id != 0 and Sales.px().has(id):
		get_viewport().set_input_as_handled()
		talk_requested.emit(id)
