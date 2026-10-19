class_name AdventureNeedsView
extends Node
## Your hunger, thirst and tiredness out on an adventure (see AdventureNeeds for the shared
## meters): three small meters at the bottom left, and what they do to you. Tired, the bars
## answer slower (steer), the edges of the screen darken and now and then your eyes close in a
## slow blink; hungry or thirsty you're warned, and once empty you walk slower and tire faster.
##
## It's also your hands at the stops: walk up to a seat ("adv_seat" nodes: a bench, a rock, a
## cafe chair; -Z is the way you face, meta "places" how many sit on it side by side, "height"
## its seat above the ground) and {interact} sits you down, a counter ("adv_counter", meta "menu":
## [{name, price, food, drink}]) sells you something to eat out of your own pocket, a bed
## ("adv_bed": an inn room or a tent pitch, meta "places" too) lies you down, and once the whole
## crew is in bed the host calls it a night. {eat} has a bite or a cup from the lunch and flask
## packed on your bike, stopped or sat down (sat down goes further, sat with mates further still).

## How close (m) you have to be to a seat, bed or counter to use it.
const REACH := 1.8
## Your eye above a seat, sat on it, and above a bed, lying in it.
const SIT_EYE := 0.75
const BED_EYE := 0.28
## Seconds a mouthful takes (you can't have the next one sooner).
const EAT_TIME := 2.5
## How far below your hips a seat is by default, and the most a tired rider's bars lag (s).
const SEAT_HEIGHT := 0.45
const MAX_LAG := 0.28
## Slower than this (m/s) on a bike you're stopped, for eating.
const STOPPED := 1.0
## A bed's node is at its door (an inn room's, a tent's), facing in: you lie this far in.
const BED_IN := 1.4
## How far your eyes close lying in bed (the world dims to a slit while you wait for the night).
const BED_LIDS := 0.8
## Seconds the host's word on a sit or a bed has to arrive before you're stood back up.
const ANSWER_WAIT := 2.0

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float blink = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.25, 1.0);
	float r = length(d);
	float edge = smoothstep(0.78 - amount * 0.4, 0.98 - amount * 0.25, r) * min(1.0, amount * 1.5);
	float open_half = (1.0 - blink) * 0.56;
	float lid = smoothstep(open_half - 0.06, open_half, abs(UV.y - 0.5));
	COLOR = vec4(0.0, 0.0, 0.0, max(edge, lid));
}
"""

var trip: AdventureTrip
var _layer: CanvasLayer
var _meters: Control
var _vignette: ColorRect
var _shade: ShaderMaterial
var _prompt: Label
var _confirm: PanelContainer
var _confirm_text: Label
var _steer := 0.0
## Your eyes closing (0 open .. 1 shut), how far into a blink you are, and when the next one comes.
var blink := 0.0
var _blink_t := -1.0
var _next_blink := 20.0
var vignette := 0.0
var _bands := {}               # meter -> 0 fine, 1 low, 2 empty: what you've been told
## Where you're sat or lying: the node, which place on it, its key and how far along the road
## it is; {} when you're on your feet.
var perch := {}
var _perch_since := 0
## The seat, bed or counter you're close enough to use: {kind, node, place, key, s}, or {}.
var near := {}
var menu_index := 0
var _eat_ready := 0            # ticks: when you can have the next mouthful
var _eat_seen := -1            # your mouthfuls as last seen, for the food in your hand
var _food: Node3D              # what you're eating, in front of your eyes
var _food_t := 0.0
var _nights_seen := -1
var _paid_for := ""            # the bed you've paid for tonight (going back to it is free)
var _near_timer := 0.0
var _meter_timer := 0.0


func _ready() -> void:
	name = "AdventureNeeds"
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_shade = ShaderMaterial.new()
	_shade.shader = sh
	_vignette.material = _shade
	_vignette.visible = false
	_layer.add_child(_vignette)
	_meters = Control.new()
	_meters.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meters.draw.connect(_draw_meters)
	_meters.visible = false
	_layer.add_child(_meters)
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
	_steer = 0.0
	blink = 0.0
	vignette = 0.0
	_blink_t = -1.0
	_bands.clear()
	_eat_seen = -1
	_nights_seen = -1
	_paid_for = ""
	if is_instance_valid(_food):
		_food.queue_free()
	_food = null
	if trip and trip.main and trip.main.walker:
		trip.main.walker.pace_scale = 1.0
	if _layer:
		_meters.visible = false
		_vignette.visible = false
		_prompt.text = ""
		_confirm.visible = false


func _on() -> bool:
	return trip != null and trip.on_trip() and not AdventureNeeds.of(Shed.me()).is_empty()


# ---------------------------------------------------------------------------- the effects

## How tired `n` is (one rider's needs): 0 fine, rising past AdventureNeeds.LOW to 1 worn out.
static func tiredness(n: Dictionary) -> float:
	return clampf((AdventureNeeds.LOW - float(n.get("rest", 1.0))) / AdventureNeeds.LOW, 0.0, 1.0)


## How long (s) the bars take to answer for `n`: nothing fresh, up to MAX_LAG worn out, a little
## more starving or parched.
static func steer_lag(n: Dictionary) -> float:
	var lag := MAX_LAG * tiredness(n)
	if float(n.get("drink", 1.0)) < AdventureNeeds.EMPTY:
		lag += 0.06
	if float(n.get("food", 1.0)) < AdventureNeeds.EMPTY:
		lag += 0.04
	return lag


## How dark the edges of the screen go for `n`, 0..1.
static func vignette_of(n: Dictionary) -> float:
	var v := 0.75 * tiredness(n)
	if float(n.get("drink", 1.0)) < AdventureNeeds.EMPTY:
		v += 0.2
	return clampf(v, 0.0, 1.0)


## Walking pace for `n`: slower once starving.
static func pace_of(n: Dictionary) -> float:
	return 0.75 if float(n.get("food", 1.0)) < AdventureNeeds.EMPTY else 1.0


## The steer the rider asks for (`want`), as the bike gets it: as asked fresh, slower to follow
## the more tired you are.
func steer(want: float, delta: float) -> float:
	var lag := steer_lag(AdventureNeeds.of(Shed.me())) if _on() else 0.0
	if lag < 0.01:
		_steer = want
	else:
		_steer = lerpf(_steer, want, 1.0 - exp(-delta / lag))
	return _steer


## Darkens the edges and blinks your eyes, by how tired you are.
func _process(delta: float) -> void:
	var pt := Perf.t0()
	if not _on():
		if _meters and _meters.visible:
			reset()
		Perf.add("adventure_needs", pt)
		return
	var n := AdventureNeeds.of(Shed.me())
	var t := tiredness(n)
	vignette = move_toward(vignette, vignette_of(n), delta * 0.3)
	if abed():
		blink = move_toward(blink, BED_LIDS, delta * 0.8)   # eyes closing, waiting for the night
		_blink_t = -1.0
	elif _blink_t >= 0.0:
		# A slow blink: 0.5 s closing, held a moment (longer the more tired), 0.5 s opening.
		_blink_t += delta
		var hold := 0.15 + 0.6 * t
		blink = clampf(_blink_t / 0.5, 0.0, 1.0) if _blink_t < 0.5 else (1.0 if _blink_t < 0.5 + hold else clampf(1.0 - (_blink_t - 0.5 - hold) / 0.5, 0.0, 1.0))
		if _blink_t > 1.0 + hold:
			_blink_t = -1.0
			blink = 0.0
	elif t > 0.3:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_t = 0.0
			_next_blink = randf_range(10.0, 26.0) * (1.25 - t)
	_vignette.visible = vignette > 0.01 or blink > 0.01
	_shade.set_shader_parameter("amount", vignette)
	_shade.set_shader_parameter("blink", blink)
	_meters.visible = true
	_meter_timer -= delta
	if _meter_timer <= 0.0:
		_meter_timer = 0.25
		_meters.queue_redraw()
	_update_food(delta)
	Perf.add("adventure_needs", pt)


func _physics_process(delta: float) -> void:
	if not _on():
		return
	var pt := Perf.t0()
	var main: Node = trip.main
	var me := Shed.me()
	var n := AdventureNeeds.of(me)
	if main.walker:
		main.walker.pace_scale = pace_of(n)
	_warnings(n)
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
		_blink_t = -1.0
		_next_blink = 30.0
		if Shed.is_authority() and main.get("saver") != null and main.saver.has_method("save_soon"):
			main.saver.save_soon()   # the night's stop is safe on disk at once
	_nights_seen = nights
	Perf.add("adventure_needs", pt)


## Tells you once as a meter runs low, and again as it runs out.
func _warnings(n: Dictionary) -> void:
	var said := {"food": ["You're getting hungry. Stop for something to eat ({eat}, or a cafe).", "You're starving: you're slowing down and tiring faster."],
		"drink": ["You're getting thirsty. Stop for a drink.", "You're parched: it's getting hard to concentrate."],
		"rest": ["You're getting tired. Take a break, or find a bed for the night.", "You're exhausted: the bars feel heavy and your eyes keep closing. Find a bed."]}
	for key in said:
		var v := float(n.get(key, 1.0))
		var band := 2 if v < AdventureNeeds.EMPTY else (1 if v < AdventureNeeds.LOW else 0)
		var was := int(_bands.get(key, 0))
		if band > was:
			trip.main.hud.flash(said[key][band - 1], 5.0, true)
		if band < was and v < AdventureNeeds.LOW + 0.05:
			band = was   # just topped over the line: not told again till it's well up
		_bands[key] = band


# ---------------------------------------------------------------------------- the meters

func _draw_meters() -> void:
	var n := AdventureNeeds.of(Shed.me())
	if n.is_empty():
		return
	var font := _meters.get_theme_default_font()
	var sz := _meters.size
	var r := Rect2(24.0, sz.y - 24.0 - 200.0 - 14.0 - 96.0, 230.0, 96.0)
	_meters.draw_rect(r, Color(0.03, 0.04, 0.06, 0.62))
	_meters.draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), UITheme.ACCENT)
	var rows := [["FOOD", "food"], ["DRINK", "drink"], ["REST", "rest"]]
	for i in rows.size():
		var v := float(n.get(rows[i][1], 1.0))
		var y := r.position.y + 10.0 + i * 22.0
		var col := Color(0.45, 0.85, 0.45) if v >= 0.5 else (Color(0.95, 0.75, 0.2) if v >= AdventureNeeds.LOW else Color(0.95, 0.35, 0.3))
		_meters.draw_string(font, Vector2(r.position.x + 12.0, y + 12.0), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
		var bar := Rect2(r.position.x + 64.0, y + 3.0, 150.0, 9.0)
		_meters.draw_rect(bar, Color(1, 1, 1, 0.12))
		_meters.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v, 0.0, 1.0), bar.size.y)), col)
	var me := Shed.me()
	var pack := "Lunch %d   Flask %d" % [AdventureNeeds.left(me, "lunch"), AdventureNeeds.left(me, "flask")]
	if AdventureNeeds.sat(me):
		pack += "   sat down" if AdventureNeeds.bonus(me) < AdventureNeeds.PICNIC_BONUS else "   picnic"
	_meters.draw_string(font, Vector2(r.position.x + 12.0, r.end.y - 8.0), pack, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


## What the line near the bottom of the screen offers: sit, lie down, buy, eat, get up, sleep.
func prompt_text() -> String:
	var me := Shed.me()
	if abed():
		return "In bed. {interact}: get up"
	if not perch.is_empty():
		var t := "Sat down. {eat}: eat or drink   ·   {interact} or walk: get up"
		if AdventureNeeds.left(me, "lunch") + AdventureNeeds.left(me, "flask") == 0:
			t = "Sat down, resting. {interact} or walk: get up"
		return t
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
		"counter":
			var menu := AdventureNeeds.menu_of(near["node"])
			if menu.is_empty():
				return ""
			var e: Dictionary = menu[menu_index % menu.size()]
			return "{interact}: buy %s (%s)   ·   {alt_act}: next (%d of %d)" % [str(e["name"]).to_lower(), TvChannels.money_text(int(e["price"])),
				menu_index % menu.size() + 1, menu.size()]
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


# ---------------------------------------------------------------------------- seats, beds, counters

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


## The nearest seat, bed or counter within REACH of you, with its free place nearest you:
## {kind, node, place, key (of the place; "" when every place is taken), s}, or {}.
func find_near() -> Dictionary:
	var at: Vector3 = trip.main.walker.global_position
	var best := {}
	var best_d := REACH
	for pair in [["seat", AdventureNeeds.SEAT_GROUP], ["bed", AdventureNeeds.BED_GROUP], ["counter", AdventureNeeds.COUNTER_GROUP]]:
		for node in get_tree().get_nodes_in_group(pair[1]):
			var n3 := node as Node3D
			if n3 == null or not n3.is_inside_tree() or absf(n3.global_position.y - at.y) > 2.0:
				continue
			if pair[0] == "counter":
				var d := Vector2(n3.global_position.x - at.x, n3.global_position.z - at.z).length()
				if d < best_d:
					best_d = d
					best = {"kind": "counter", "node": n3}
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
	if not best.is_empty() and best["kind"] != "counter":
		best["s"] = s_of(best["node"])
	return best


## Sits you down (or lies you down) on `spot` (as find_near gives it), asking the host. A bed
## (its node's "price" meta) is paid for out of your own money, once a night. "" when it's done,
## else why not.
func take(spot: Dictionary) -> String:
	if spot.is_empty() or str(spot.get("key", "")) == "" or spot["kind"] == "counter":
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
	Shed.request({"a": "needs_sit" if kind == "seat" else "needs_bed", "key": perch["key"], "s": perch["s"], "on": true})
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


## Buys the item on a counter's menu the line shows, out of your own money, and eats it there.
func buy(counter: Node, index: int) -> String:
	var menu := AdventureNeeds.menu_of(counter)
	if menu.is_empty():
		return "There's nothing for sale here."
	var e: Dictionary = menu[index % menu.size()]
	var price := int(e["price"])
	if Time.get_ticks_msec() < _eat_ready:
		return "Finish that first."
	if not Progress.spend(price, "Food: %s" % str(e["name"]).left(30)):
		return "You haven't got %s on you." % TvChannels.money_text(price)
	_eat_ready = Time.get_ticks_msec() + int(EAT_TIME * 1000.0)
	Shed.request({"a": "needs_eat", "src": "buy", "name": e["name"], "food": e["food"], "drink": e["drink"], "rest": e["rest"], "paid": price})
	return ""


## A bite of your packed lunch or a cup from the flask (whichever you need more and have),
## stopped or on foot. "" when it's on its way, else why not.
func eat() -> String:
	var me := Shed.me()
	var main: Node = trip.main
	if abed():
		return "Not in bed."
	if main.bike != null and absf(main.bike.speed) > STOPPED:
		return "Pull over first to eat or drink."
	if Time.get_ticks_msec() < _eat_ready:
		return ""
	var n := AdventureNeeds.of(me)
	var order := ["lunch", "flask"] if float(n.get("food", 1.0)) <= float(n.get("drink", 1.0)) else ["flask", "lunch"]
	for what in order:
		if AdventureNeeds.left(me, what) > 0:
			_eat_ready = Time.get_ticks_msec() + int(EAT_TIME * 1000.0)
			Shed.request({"a": "needs_eat", "src": what})
			return ""
	return "Your packed lunch and flask are empty (or you didn't pack any): buy something at a cafe or shop."


func _unhandled_input(event: InputEvent) -> void:
	if not _on() or event.is_echo():
		return
	var main: Node = trip.main
	if main.menu.visible:
		return
	if event.is_action_pressed("eat"):
		get_viewport().set_input_as_handled()
		var why := eat()
		if why != "":
			main.hud.flash(why, 3.0, true)
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
		if near["kind"] == "counter":
			var why := buy(near["node"], menu_index)
			if why != "":
				main.hud.flash(why, 2.5, true)
		elif str(near.get("key", "")) != "":
			var why := take(near)
			if why != "":
				main.hud.flash(why, 2.5, true)
		else:
			main.hud.flash("Every place there is taken.", 2.0, true)
	elif event.is_action_pressed("alt_act") and near["kind"] == "counter":
		get_viewport().set_input_as_handled()
		menu_index += 1


# ---------------------------------------------------------------------------- eating, seen

## Something to eat or drink in front of your eyes for a moment, each mouthful.
func _update_food(delta: float) -> void:
	var n := AdventureNeeds.of(Shed.me())
	var count := int(n.get("eat", 0))
	var walker: Walker = trip.main.walker
	if _eat_seen >= 0 and count > _eat_seen and walker:
		if is_instance_valid(_food):
			_food.queue_free()
		_food = food_model(str(n.get("eat_what", "lunch")))
		walker.camera.add_child(_food)
		_food_t = 0.0
	_eat_seen = count
	if is_instance_valid(_food):
		_food_t += delta
		var up := sin(clampf(_food_t / EAT_TIME, 0.0, 1.0) * PI)
		_food.position = Vector3(0.12, -0.32 + 0.2 * up, -0.42 + 0.12 * up)
		_food.visible = trip.main.bike == null or trip.main.camera.mode == ChaseCamera.Mode.HELMET
		if _food_t > EAT_TIME:
			_food.queue_free()
			_food = null


## A sandwich ("lunch") or a cup of tea from the flask ("flask").
static func food_model(what: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Food"
	var mat := StandardMaterial3D.new()
	if what == "flask":
		mat.albedo_color = Color(0.82, 0.12, 0.1)
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.03
		cm.height = 0.07
		cup.mesh = cm
		cup.material_override = mat
		root.add_child(cup)
		var tea := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.032
		tm.bottom_radius = 0.032
		tm.height = 0.002
		tea.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.45, 0.28, 0.14)
		tea.material_override = tmat
		tea.position.y = 0.03
		root.add_child(tea)
	else:
		mat.albedo_color = Color(0.92, 0.8, 0.55)
		for k in 2:
			var slice := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, 0.012, 0.1)
			slice.mesh = bm
			slice.material_override = mat
			slice.position.y = 0.02 * k
			root.add_child(slice)
		var fill := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.095, 0.008, 0.095)
		fill.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.35, 0.62, 0.25)
		fill.material_override = fmat
		fill.position.y = 0.01
		root.add_child(fill)
		root.rotation = Vector3(0.5, 0.6, 0.0)
	return root


## Poses a standing figure (its body's look node `look`, with legs "LegR"/"LegL" and arms
## "ArmR"/"ArmL", its `head` node and the `head_look` in it, and the `hand` holding their tool)
## for player `peer` sat on a seat or lying in a bed out on an adventure, easing into it (the
## amount kept on `holder`), with the right hand going to the mouth as they eat. Returns whether
## it's posed at all; stood up again, everything's put back as it was.
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
	# A mouthful: the right hand up to the mouth and back, twice.
	var count := int(n.get("eat", 0))
	if count != int(holder.get_meta("eat_seen", count)):
		holder.set_meta("eat_t", 0.0)
	holder.set_meta("eat_seen", count)
	var et := float(holder.get_meta("eat_t", 99.0)) + delta
	holder.set_meta("eat_t", et)
	var arm := look.get_node_or_null("ArmR") as Node3D
	if arm and et < EAT_TIME:
		var w := absf(sin(et / EAT_TIME * TAU))
		arm.quaternion = Quaternion.IDENTITY.slerp(Emotes.arm_turn(true, Vector3(-0.2, 0.75, -0.45)), w)
	elif arm and et < EAT_TIME + 0.2:
		arm.quaternion = Quaternion.IDENTITY
	return true
