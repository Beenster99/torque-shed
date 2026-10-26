class_name AdventureBikePicker
extends Control
## Off on an adventure: which bike do you take? Each player chooses for themselves from the bikes
## they could ride: the shed's (the garage's) and their own (in the yard, or at home in their
## collection: one at home is taken out for the ride, as home_take does). The one you're on, or
## the one you're standing by, comes first and is taken if nothing's picked in WAIT seconds, so a
## player who's away from the keyboard doesn't hold anyone up. "On foot" comes along walking.
##
## AdventureTrip.enter() asks with choose() and sends the answer with adventure_join.

signal chosen(choice: Dictionary)

## Seconds before the first choice is taken for you.
const WAIT := 20.0

var choices: Array = []
var _left := 0.0
var _list: VBoxContainer
var _clock: Label


## What `peer` could take: [{bike (Shed.bikes id, 0 for one at home), home (its collection id, 0 for
## one in the shed), name, kind ("personal" or "garage")}], `first` (a shed bike id) at the top
## when it's among them, then the rest by name; the bike they're on is always among them.
static func choices_for(peer: int, first := 0) -> Array:
	var me := Collection.name_of(peer)
	var riding := Shed.riding(peer)
	var out := []
	var ids := Shed.bikes.keys()
	ids.sort()
	for id in ids:
		if int(id) == riding or _free_to_ride(peer, int(id)):
			var owner := Collection.owner_of_bike(int(id))
			out.append({"bike": int(id), "home": 0, "name": str(Shed.bikes[id].get("name", "Bike")),
				"kind": "personal" if owner != "" and owner == me else "garage"})
	for cid in Collection.bikes_of(me):
		var e := Collection.entry(int(cid))
		if int(e.get("out", 0)) == 0 and e.has("pack"):
			out.append({"bike": 0, "home": int(cid), "name": str(e.get("name", "Bike")), "kind": "personal"})
	out.sort_custom(func(a, b):
		var fa := int(a["bike"]) != 0 and int(a["bike"]) == first
		var fb := int(b["bike"]) != 0 and int(b["bike"]) == first
		if fa != fb:
			return fa
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Whether `peer` could get on shed bike `id` as it stands: nobody else on it or pushing it, all
## there and bolted up, off the lift, and not someone else's own.
static func _free_to_ride(peer: int, id: int) -> bool:
	var b: Dictionary = Shed.bikes[id]
	if int(b.get("rider", 0)) != 0 or int(b.get("pusher", 0)) not in [0, peer]:
		return false
	var owner := Collection.owner_of_bike(id)
	if owner != "" and owner != Collection.name_of(peer):
		return false
	if Shed.riding(peer) == 0:
		return Shed.check(peer, {"a": "mount", "bike": id}) == ""
	return Shed.missing_slots(id).is_empty() and Shed.loose_slots(id).is_empty() and not Shed.lift_raised(id)


## The line a choice is shown as.
static func line_of(c: Dictionary) -> String:
	if c.is_empty():
		return "On foot"
	var where := "your own, at home" if int(c["home"]) != 0 else ("your own" if c["kind"] == "personal" else "the garage's")
	return "%s (%s)" % [str(c["name"]), where]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UITheme.title("WHICH BIKE ARE YOU TAKING?", 24))
	var note := UITheme.label("Your own bikes or one of the garage's. You'll be on it at the start.", 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_clock = UITheme.label("", 15, Color(0.7, 0.75, 0.8))
	box.add_child(_clock)
	visible = false


## Shows `list` (from choices_for) and gives back the one picked: {} for on foot.
func choose(list: Array) -> Dictionary:
	choices = list
	for c in _list.get_children():
		c.free()
	var groups := [["YOUR OWN", "personal"], ["THE GARAGE'S", "garage"]]
	for g in groups:
		var of_kind := list.filter(func(c): return c["kind"] == g[1])
		if of_kind.is_empty():
			continue
		_list.add_child(UITheme.label(g[0], 14, UITheme.ACCENT))
		for c in of_kind:
			var b := Button.new()
			b.text = line_of(c)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func(): pick(c))
			_list.add_child(b)
	var foot := Button.new()
	foot.text = "On foot"
	foot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.pressed.connect(func(): pick({}))
	_list.add_child(foot)
	_left = WAIT
	visible = true
	var first := _list.get_children().filter(func(n): return n is Button)
	if not first.is_empty():
		(first[0] as Button).grab_focus.call_deferred()
	return await chosen


## Takes choice `c` ({} for on foot).
func pick(c: Dictionary) -> void:
	if not visible:
		return
	visible = false
	chosen.emit(c)


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	var first: Dictionary = choices[0] if not choices.is_empty() else {}
	_clock.text = "Taking %s in %d s if nothing's picked." % [line_of(first), ceili(maxf(_left, 0.0))]
	if _left <= 0.0:
		pick(first)
