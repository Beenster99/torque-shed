class_name AdventureNeedsView
extends Node
## Your hands at an adventure's stops (see AdventureNeeds for the shared state): walk up to a
## seat ("adv_seat" nodes: a bench, a rock, a cafe chair; -Z is the way you face, meta "places"
## how many sit on it side by side, "height" its seat above the ground) and {interact} sits you
## down; a bed ("adv_bed": an inn room or a tent pitch, meta "places" too) lies you down, and
## once the whole crew is in bed the host calls it a night.

## How close (m) you have to be to a seat or bed to use it.
const REACH := 1.8
## Your eye above a seat, sat on it, and above a bed, lying in it.
const SIT_EYE := 0.75
const BED_EYE := 0.28
## How far below your hips a seat is by default.
const SEAT_HEIGHT := 0.45
## A bed's node is at its door (an inn room's, a tent's), facing in: you lie this far in.
const BED_IN := 1.4
## Seconds the host's word on a sit or a bed has to arrive before you're stood back up.
const ANSWER_WAIT := 2.0

var trip: AdventureTrip
var _layer: CanvasLayer
var _prompt: Label
var _confirm: PanelContainer
var _confirm_text: Label
## Where you're sat or lying: the node, which place on it, its key and how far along the road
## it is; {} when you're on your feet.
var perch := {}
var _perch_since := 0
## The seat or bed you're close enough to use: {kind, node, place, key, s}, or {}.
var near := {}
var _nights_seen := -1
var _paid_for := ""            # the bed you've paid for tonight (going back to it is free)
var _near_timer := 0.0


func _ready() -> void:
	name = "AdventureNeeds"
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_prompt = UITheme.label("", 18, UITheme.ACCENT)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -520
	_prompt.offset_right = 520
	_prompt.offset_top = -150
	_prompt.offset_bottom = -120
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_prompt)
	_confirm = PanelContainer.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_confirm.offset_left = -300
	_confirm.offset_right = 300
	_confirm.offset_top = -90
	_confirm.offset_bottom = 90
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.86)
	style.border_color = Color(UITheme.ACCENT, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_confirm.add_theme_stylebox_override("panel", style)
	_confirm_text = UITheme.label("", 18, Color.WHITE)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(_confirm_text)
	_confirm.visible = false
	_layer.add_child(_confirm)


## Off the adventure: on your feet, nothing on the screen.
func reset() -> void:
	_leave_perch(false)
	near = {}
	_nights_seen = -1
	_paid_for = ""
	if _layer:
		_prompt.text = ""
		_confirm.visible = false


func _on() -> bool:
	return trip != null and trip.on_trip() and not AdventureNeeds.of(Shed.me()).is_empty()


func _process(_delta: float) -> void:
	if not _on() and (not perch.is_empty() or (_prompt and _prompt.text != "") or (_confirm and _confirm.visible)):
		reset()


func _physics_process(delta: float) -> void:
	if not _on():
		return
	var pt := Perf.t0()
	var main: Node = trip.main
	_keep_perch()
	if not perch.is_empty() and main.walker and main.walker.controls_enabled:
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + Controls.stick()
		if move.length() > 0.5:
			stand_up()
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.15
		near = find_near() if main.bike == null and perch.is_empty() and main.walker else {}
	_prompt.text = Controls.hint(prompt_text())
	_update_confirm()
	var nights := int(Shed.adventure.get("nights", 0))
	if _nights_seen >= 0 and nights > _nights_seen:
		_paid_for = ""   # a new day: tonight's bed is paid for afresh
		if Shed.is_authority() and main.get("saver") != null and main.saver.has_method("save_soon"):
			main.saver.save_soon()   # the night's stop is safe on disk at once
	_nights_seen = nights
	Perf.add("adventure_needs", pt)


## What the line near the bottom of the screen offers: sit, lie down, get up, sleep.
func prompt_text() -> String:
	if abed():
		return "In bed. {interact}: get up"
	if not perch.is_empty():
		return "Sat down. {interact} or walk: get up"
	match str(near.get("kind", "")):
		"seat":
			return "{interact}: sit down" + ("   ·   someone's sat there" if str(near.get("key", "")) == "" else "")
		"bed":
			if str(near.get("key", "")) == "":
				return "That bed's taken"
			var bed: Node = near["node"]
			var price := ceili(float(bed.get_meta("price", 0.0)))
			return "{interact}: %s%s" % ["go to bed" if not bed.has_meta("name") else "take " + str(bed.get_meta("name")).to_lower(),
				"" if price <= 0 or _paid_for == str(near["key"]) else " (%s)" % TvChannels.money_text(price)]
	return ""


## The host's call once everyone's in bed; the others are told they're waiting on it.
func _update_confirm() -> void:
	var on := abed() and AdventureNeeds.all_abed()
	_confirm.visible = on
	if not on:
		return
	var c := AdventureNeeds.bed_count()
	if Shed.is_authority():
		_confirm_text.text = Controls.hint("Everyone's in bed (%d of %d).\n\n{alt_act}: sleep till morning\nThe adventure is saved, to carry on now or another day.\n\n{interact}: get up" % [c[0], c[1]])
	else:
		_confirm_text.text = Controls.hint("Everyone's in bed (%d of %d).\n\nWaiting for the host to call it a night.\n\n{interact}: get up" % [c[0], c[1]])


# ---------------------------------------------------------------------------- seats and beds

## Whether you're lying in a bed.
func abed() -> bool:
	return str(perch.get("kind", "")) == "bed"


## The places on a seat or bed node: their transforms (your feet's, sat on a seat; lying in a
## bed, BED_IN through its door). A node's "places" meta has more than one side by side.
static func places_of(node: Node3D) -> Array:
	var n := maxi(1, int(node.get_meta("places", 1)))
	var bed := node.is_in_group(AdventureNeeds.BED_GROUP)
	var gap := float(node.get_meta("spacing", 0.9 if bed else 0.6))
	var out := []
	for i in n:
		out.append(node.global_transform * Transform3D(Basis(), Vector3((i - (n - 1) * 0.5) * gap, 0.0, -BED_IN if bed else 0.0)))
	return out


## A seat, bed or counter's name, the same on every player's game: its "key" meta, else what it
## is and where it is along the road.
func key_of(node: Node3D, kind: String) -> String:
	if node.has_meta("key"):
		return "%s:%s" % [kind, str(node.get_meta("key"))]
	var hit := trip.world.locate_local(node.global_position) if trip.world else {}
	return "%s:%d:%d" % [kind, roundi(float(hit.get("s", 0.0)) * 2.0), roundi(float(hit.get("lat", 0.0)) * 2.0)]


## How far along the road `node` is.
func s_of(node: Node3D) -> float:
	if trip.world == null:
		return 0.0
	return maxf(0.0, trip.world.distance_of(node.global_position))


## The nearest seat or bed within REACH of you, with its free place nearest you:
## {kind, node, place, key (of the place; "" when every place is taken), s}, or {}.
func find_near() -> Dictionary:
	var at: Vector3 = trip.main.walker.global_position
	var best := {}
	var best_d := REACH
	for pair in [["seat", AdventureNeeds.SEAT_GROUP], ["bed", AdventureNeeds.BED_GROUP]]:
		for node in get_tree().get_nodes_in_group(pair[1]):
			var n3 := node as Node3D
			if n3 == null or not n3.is_inside_tree() or absf(n3.global_position.y - at.y) > 2.0:
				continue
			var places := places_of(n3)
			var base := key_of(n3, pair[0])
			var field := "sat" if pair[0] == "seat" else "bed"
			var free_i := -1
			var free_d := INF
			var any_d := INF
			for i in places.size():
				# A bed's used from its door; a seat from beside it.
				var p: Vector3 = n3.global_position if pair[0] == "bed" else (places[i] as Transform3D).origin
				var d := Vector2(p.x - at.x, p.z - at.z).length()
				any_d = minf(any_d, d)
				if not AdventureNeeds.taken("%s#%d" % [base, i], field, Shed.me()) and d < free_d:
					free_d = d
					free_i = i
			var near_d := free_d if free_i >= 0 else any_d
			if near_d < best_d:
				best_d = near_d
				best = {"kind": pair[0], "node": n3, "place": free_i, "key": "%s#%d" % [base, free_i] if free_i >= 0 else ""}
	if not best.is_empty():
		best["s"] = s_of(best["node"])
	return best


## Sits you down (or lies you down) on `spot` (as find_near gives it), asking the host. A bed
## (its node's "price" meta) is paid for out of your own money, once a night. "" when it's done,
## else why not.
func take(spot: Dictionary) -> String:
	if spot.is_empty() or str(spot.get("key", "")) == "":
		return "There's nowhere free there."
	var main: Node = trip.main
	if main.bike != null:
		return "Get off the bike first."
	var kind := str(spot["kind"])
	if kind == "bed" and _paid_for != str(spot["key"]):
		var price := ceili(float((spot["node"] as Node).get_meta("price", 0.0)))
		var what := str((spot["node"] as Node).get_meta("name", "the bed"))
		if not Progress.spend(price, "Bed: %s" % what.left(30)):
			return "You haven't got %s for %s." % [TvChannels.money_text(price), what.to_lower()]
		_paid_for = str(spot["key"])
	perch = {"kind": kind, "node": spot["node"], "place": int(spot["place"]), "key": str(spot["key"]), "s": float(spot.get("s", 0.0))}
	_perch_since = Time.get_ticks_msec()
	var req := {"a": "needs_sit" if kind == "seat" else "needs_bed", "key": perch["key"], "s": perch["s"], "on": true}
	if kind == "bed" and trip.world != null and trip.world.roads != null:
		# On the network, where the bed is (the region's frame): you wake up there however you came.
		var node: Node3D = spot["node"]
		var xz := trip.world.route_xz(node.global_position)
		var fwd := -node.global_transform.basis.z
		req["at"] = [xz[0], xz[1], atan2(fwd.x, -fwd.z)]
	Shed.request(req)
	_keep_perch()
	Sfx.play_at("pickup", main.walker.global_position, -14.0)
	return ""


## Up off the seat or out of bed.
func stand_up() -> void:
	if perch.is_empty():
		return
	Shed.request({"a": "needs_sit" if perch["kind"] == "seat" else "needs_bed", "on": false})
	_leave_perch(true)


## Lets the walker go from where it was perched, standing in front of the seat (or beside the bed).
func _leave_perch(place_walker: bool) -> void:
	if perch.is_empty():
		return
	var walker: Walker = trip.main.walker if trip and trip.main else null
	var xf = _perch_xf()
	var node = perch.get("node")
	var h := float((node as Node3D).get_meta("height", SEAT_HEIGHT)) if is_instance_valid(node) else SEAT_HEIGHT
	perch = {}
	if walker == null:
		return
	if place_walker and xf != null:
		var at: Transform3D = xf
		var out := at.origin - at.basis.z * 0.7 - Vector3.UP * h
		if is_instance_valid(node) and (node as Node).is_in_group(AdventureNeeds.BED_GROUP):
			out = (node as Node3D).global_position   # back out of the door
		walker.unperch(Transform3D(at.basis, out))
	else:
		walker.perch = null
		walker._shape_node.disabled = false


## Where your place on the seat or bed is now (the world's origin moves under it), or null.
func _perch_xf():
	var node = perch.get("node")
	if not is_instance_valid(node) or not (node as Node3D).is_inside_tree():
		return null
	var places := places_of(node)
	return places[clampi(int(perch.get("place", 0)), 0, places.size() - 1)]


## Keeps you on your seat or in your bed: moved with it, and stood up when it's gone, the host
## has said no, or you're on a bike.
func _keep_perch() -> void:
	if perch.is_empty():
		var walker: Walker = trip.main.walker
		if walker and walker.perch != null:
			walker.perch = null
			walker._shape_node.disabled = false
		return
	var xf = _perch_xf()
	var field := "sat" if perch["kind"] == "seat" else "bed"
	var said := str(AdventureNeeds.of(Shed.me()).get(field, ""))
	var refused := said != str(perch["key"]) and Time.get_ticks_msec() - _perch_since > ANSWER_WAIT * 1000.0
	if xf == null or refused or trip.main.bike != null or trip.main.walker == null:
		_leave_perch(xf != null)
		return
	var lying: bool = perch["kind"] == "bed"
	var at: Transform3D = xf
	if trip.main.walker.perch == null:
		trip.main.walker.perch_at(at, BED_EYE if lying else SIT_EYE)
	else:
		trip.main.walker.perch = at


func _unhandled_input(event: InputEvent) -> void:
	if not _on() or event.is_echo():
		return
	var main: Node = trip.main
	if main.menu.visible:
		return
	if main.bike != null or main.walker == null:
		return
	if not perch.is_empty():
		if event.is_action_pressed("interact") or event.is_action_pressed("crouch"):
			get_viewport().set_input_as_handled()
			stand_up()
		elif event.is_action_pressed("alt_act") and abed() and Shed.is_authority() and AdventureNeeds.all_abed():
			get_viewport().set_input_as_handled()
			Shed.request({"a": "needs_sleep"})
		elif event.is_action_pressed("alt_act") or event.is_action_pressed("jump"):
			get_viewport().set_input_as_handled()   # sat still: nothing else to do with your hands
		return
	if near.is_empty():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if str(near.get("key", "")) != "":
			var why := take(near)
			if why != "":
				main.hud.flash(why, 2.5, true)
		else:
			main.hud.flash("Every place there is taken.", 2.0, true)


# ---------------------------------------------------------------------------- the crew, seen

## Poses a standing figure (its body's look node `look`, with legs "LegR"/"LegL", its `head`
## node and the `head_look` in it, and the `hand` holding their tool) for player `peer` sat on a
## seat or lying in a bed out on an adventure, easing into it (the amount kept on `holder`).
## Returns whether it's posed at all; stood up again, everything's put back as it was.
static func pose_figure(look: Node3D, head: Node3D, head_look: Node3D, hand: Node3D, holder: Object, peer: int, delta: float) -> bool:
	var n := AdventureNeeds.of(peer)
	var lying := str(n.get("bed", "")) != ""
	var sitting := str(n.get("sat", "")) != ""
	var was := float(holder.get_meta("perch_amt", 0.0))
	var amt := move_toward(was, 1.0 if (lying or sitting) else 0.0, delta / 0.45)
	holder.set_meta("perch_amt", amt)
	if amt <= 0.0:
		if was > 0.0:
			look.position = Vector3.ZERO
			look.rotation.x = 0.0
			head.position = Vector3(0.0, Walker.EYE, 0.0)
			head_look.rotation.x = 0.0
			hand.visible = true
		return false
	hand.visible = amt < 0.5
	if lying or (was > 0.0 and str(holder.get_meta("perch_kind", "")) == "bed" and not sitting):
		# On their back, head on the pillow at the far end.
		holder.set_meta("perch_kind", "bed")
		var a := PI * 0.5 * amt
		look.rotation.x = a
		look.position = Vector3(0.0, 0.12 * amt, -0.85 * amt)
		head.position = look.position + Vector3(0.0, Walker.EYE * cos(a), Walker.EYE * sin(a))
		head_look.rotation.x = a
	else:
		holder.set_meta("perch_kind", "seat")
		look.rotation.x = 0.0
		look.position = Vector3(0.0, -0.82 * amt, 0.0)
		head.position = Vector3(0.0, Walker.EYE - 0.82 * amt, 0.0)
		head_look.rotation.x = 0.0
		for leg_name in ["LegR", "LegL"]:
			var leg := look.get_node_or_null(leg_name) as Node3D
			if leg:
				leg.rotation.x = 1.0 * amt
	return true
