extends RefCounted
## Simon's helmets: the five kinds built as proper models, the shell colours and visors you can
## pick in the Shop (saved with your gear), and the visor flicked up and down for everyone to
## see. Run from tests/run_tests.gd (its _test_helmet_* functions hand over to these).

var t: Node   # the test runner: check(), _press(), get_tree()

## A helmet of each kind from the shop, and what each must have on it.
const KINDS := {
	"helmet_pudding": "open_classic", "helmet_open_cream": "open_classic", "helmet_wayfarer": "open_touring",
	"helmet_bubble": "open_touring", "helmet_sprint": "full_classic", "helmet_stealth": "full_modern",
	"helmet_apex": "full_modern", "helmet_kestrel": "race",
}


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A helmet built on its own, unit size, in blue.
func _build(id: String, worn := {}) -> Node3D:
	var n := Node3D.new()
	t.add_child(n)
	HelmetModel.build(n, Vector3.ZERO, 1.0, id, Color(0.1, 0.3, 0.8), 1, worn)
	return n.get_node("Helmet") as Node3D


## Buys helmet `id` (if need be) and puts it on, as the Shop's Buy does. "" when worn.
static func _wear_lid(id: String) -> String:
	if not RiderGear.owns(id):
		var why := RiderGear.buy(id)
		if why != "":
			return why
	return RiderGear.wear(id)


## Every node under `root` whose name starts with `prefix`.
static func _named(root: Node, prefix: String) -> Array:
	return root.find_children(prefix + "*", "", true, false)


## Whether a ray from `from` along `dir` goes through any triangle of `mesh`.
static func _hits(mesh: Mesh, from: Vector3, dir: Vector3) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		if Geometry3D.ray_intersects_triangle(from, dir, v[idx[i]], v[idx[i + 1]], v[idx[i + 2]]) != null:
			return true
	return false


## The five kinds are on sale, and each one is a real shaped model with its own parts.
func test_models() -> void:
	var kinds := {}
	for id in RiderGear.by_slot("helmet"):
		kinds[RiderGear.helmet_model(id)] = true
	check(HelmetModel.MODELS.all(func(m): return kinds.has(m)),
		"the Shop sells all five kinds: open face classic and touring, classic and modern full face, race (%s)" % str(kinds.keys()))
	for id in KINDS:
		check(RiderGear.helmet_model(id) == KINDS[id], "the %s is a %s" % [RiderGear.ITEMS[id]["name"], HelmetModel.MODEL_NAMES[KINDS[id]]])
	for model in HelmetModel.MODELS:
		var m := HelmetModel.shell_meshes(model)
		var s: Dictionary = HelmetModel.SPECS[model]
		var shell: Mesh = m["shell"]
		var verts: PackedVector3Array = shell.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var near := INF
		var far := 0.0
		for p in verts:
			near = minf(near, p.length())
			far = maxf(far, p.length())
		check(verts.size() > 1000 and (m["liner"] as Mesh).get_surface_count() == 1 and (m["rim"] as Mesh).get_surface_count() == 1,
			"%s: a shell of %d points with a liner inside and a bead round its edges" % [model, verts.size()])
		check(far / near > 1.04, "%s: the shell is shaped, not a ball (%.2f to %.2f from the middle)" % [model, near, far])
		# Looking out: the eyes see through the face opening or the eyeport; the crown is covered.
		var eye := HelmetModel.HEAD_AT + Vector3(0.26, 0.17, -0.67)
		check(not _hits(shell, eye, Vector3.FORWARD) and not _hits(shell, eye * Vector3(-1, 1, 1), Vector3.FORWARD)
			and _hits(shell, Vector3(0.0, 0.1, 0.0), Vector3.UP) and _hits(shell, Vector3(0.0, 0.1, 0.0), Vector3.BACK),
			"%s: the eyes look out of an opening; the crown and the back are covered" % model)
		var mouth := HelmetModel.HEAD_AT + Vector3(0.0, -0.22, -0.6)
		var full := s.has("port")
		check(_hits(shell, mouth, Vector3.FORWARD) == full,
			"%s: %s" % [model, "a chin bar in front of the mouth" if full else "the face open down to the chin"])
		# It fits the head: hardly any of the liner inside the head.
		var liner: PackedVector3Array = (m["liner"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := 0
		for p in liner:
			if ((p - HelmetModel.HEAD_AT) / HelmetModel.HEAD_SIZE).length() < 0.97:
				inside += 1
		check(inside <= liner.size() / 50, "%s: the head fits inside the liner (%d of %d points in the head)" % [model, inside, liner.size()])
	# Each kind's own parts.
	var parts := {}
	for id in KINDS:
		var h := _build(id)
		var visor := h.get_node_or_null("Visor") as HelmetVisor
		parts[id] = {"visor": visor != null, "lenses": _named(h, "Lens").size(), "vents": _named(h, "Vent").size(),
			"spoiler": _named(h, "Spoiler").size(), "fins": _named(h, "Fin").size(), "tearoffs": _named(h, "TearOff").size(),
			"peak": _named(h, "Peak").size(), "band": _named(h, "GoggleBand").size(), "shell": h.get_node_or_null("Shell") != null,
			"rim": h.get_node_or_null("Rim") != null, "chrome": h.find_children("*", "MeshInstance3D", true, false).filter(func(mi):
				return (mi as MeshInstance3D).material_override == HelmetModel._mat("chrome")).size()}
		h.get_parent().queue_free()
	var p: Dictionary = parts["helmet_pudding"]
	check(p["visor"] and p["lenses"] == 2 and p["band"] == 1 and p["chrome"] >= 5,
		"classic open face: chrome snaps, a D-ring and round goggles (two lenses) on a strap (%s)" % str(p))
	p = parts["helmet_open_cream"]
	check(not p["visor"] and p["lenses"] == 0 and p["chrome"] >= 3 and p["shell"] and p["rim"], "without goggles it's just the lid, its snaps and strap (%s)" % str(p))
	p = parts["helmet_wayfarer"]
	check(p["visor"] and p["lenses"] == 1 and p["peak"] == 2, "touring open face: a half visor and a peak on snaps (%s)" % str(p))
	check(parts["helmet_bubble"]["visor"] and parts["helmet_bubble"]["peak"] == 0, "the bubble visor has no peak")
	check(parts["helmet_sprint"]["visor"] and parts["helmet_sprint"]["vents"] == 0 and parts["helmet_sprint"]["chrome"] >= 4,
		"classic full face: a flip-up shield on chrome snaps, no vents (%s)" % str(parts["helmet_sprint"]))
	p = parts["helmet_stealth"]
	check(p["visor"] and p["vents"] >= 4 and p["spoiler"] == 1 and p["tearoffs"] == 0, "modern full face: vents and a small spoiler (%s)" % str(p))
	p = parts["helmet_kestrel"]
	check(p["visor"] and p["vents"] >= 7 and p["spoiler"] == 1 and p["fins"] == 2 and p["tearoffs"] == 2,
		"race: an aero spoiler on two fins, vents all over and tear-off posts (%s)" % str(p))
	# The bubble comes further down and out than the half visor.
	var low := {}
	for id in ["helmet_wayfarer", "helmet_bubble"]:
		var h := _build(id)
		var lens := _named(h, "Lens")[0] as MeshInstance3D
		var box := lens.get_aabb()
		low[id] = [box.position.y, box.position.z]
		h.get_parent().queue_free()
	check(low["helmet_bubble"][0] < low["helmet_wayfarer"][0] - 0.1 and low["helmet_bubble"][1] < low["helmet_wayfarer"][1],
		"the bubble visor bulges further down and out than the half visor (%s)" % str(low))
	# Worn on foot and on the bike: the face shows in an open face and the helmet's on the head.
	var fig := RiderFigure.make({"helmet": "helmet_open_cream"}, Color.RED)
	t.add_child(fig)
	var head := fig.get_node("Head") as Node3D
	var lid := head.get_node("Helmet") as Node3D
	check(head.get_node_or_null("Face") != null and absf(lid.position.y - 0.03) < 0.001 and absf(lid.scale.x - 0.165) < 0.001,
		"on foot the helmet sits on the head, round the face")
	fig.queue_free()
	var bike := BikeModel.new()
	bike.rider_gear = RiderGear.clean_worn({"helmet": "helmet_bubble"})
	t.add_child(bike)
	bike.build_from(BikeBuild.new())
	var neck: Node3D = bike._rider_head
	var faces := _named(neck, "Face")
	var helmets := _named(neck, "Helmet")
	check(faces.size() == 1 and helmets.size() == 1 and faces[0].get_child_count() >= 6,
		"on the bike the helmet and a whole head (face, eyes, neck) nod together on the neck")
	var at: Vector3 = (helmets[0] as Node3D).position
	check(at.y > 0.05 and at.y < 0.2, "the helmet sits up on the neck (%.2f m above it)" % at.y)
	bike.queue_free()
	# The cap on a bike is a plain modern lid in your colour.
	var cap := _build("helmet_cap")
	check(cap.get_meta("model") == "full_modern" and cap.get_node_or_null("Visor") != null, "the cap is ridden in a plain full face with a visor")
	cap.get_parent().queue_free()
	await t.get_tree().process_frame


## Visors: clear, smoked and mirror-finish iridium, picked in the Shop; shell colours too.
func test_visors() -> void:
	for id in ["clear", "light", "dark"]:
		check(RiderGear.VISORS.has(id) and not RiderGear.VISORS[id].get("mirror", false), "a %s visor" % RiderGear.VISORS.get(id, {}).get("name", id))
	var mirrors: Array = RiderGear.VISOR_ORDER.filter(func(id): return RiderGear.VISORS[id].get("mirror", false))
	check(mirrors.size() >= 4 and mirrors.has("blue") and mirrors.has("gold") and mirrors.has("red") and mirrors.has("silver"),
		"iridium and mirror visors: %s" % str(mirrors))
	var a := [HelmetModel.visor_material("clear"), HelmetModel.visor_material("light"), HelmetModel.visor_material("dark")]
	check(a[0].albedo_color.a < a[1].albedo_color.a and a[1].albedo_color.a < a[2].albedo_color.a
		and a.all(func(m): return m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA),
		"clear, light and dark smoke let less and less through")
	var bad := mirrors.filter(func(id):
		var m := HelmetModel.visor_material(id)
		return m.metallic < 0.95 or m.roughness > 0.1 or m.metallic_specular < 0.9)
	check(bad.is_empty(), "mirror visors are a polished metal coat that reflects the world (%s)" % str(bad))
	# The visor on a helmet is the one chosen, else the one it comes with.
	var h := _build("helmet_kestrel")
	check(str((_named(h, "Lens")[0] as MeshInstance3D).material_override.get_meta("visor")) == "blue", "the race lid comes with its blue iridium visor")
	h.get_parent().queue_free()
	h = _build("helmet_kestrel", {"visor": "gold", "shell": "red"})
	var shell_mat := (h.get_node("Shell") as MeshInstance3D).material_override as StandardMaterial3D
	check(str((_named(h, "Lens")[0] as MeshInstance3D).material_override.get_meta("visor")) == "gold", "or the gold one, when picked")
	h.get_parent().queue_free()
	h = _build("helmet_stealth", {"shell": "red"})
	shell_mat = (h.get_node("Shell") as MeshInstance3D).material_override as StandardMaterial3D
	check(shell_mat.albedo_color.is_equal_approx(RiderGear.RED), "a plain shell painted the colour picked")
	h.get_parent().queue_free()
	h = _build("helmet_stealth", {"shell": "crew"})
	shell_mat = (h.get_node("Shell") as MeshInstance3D).material_override as StandardMaterial3D
	check(shell_mat.albedo_color.is_equal_approx(Color(0.1, 0.3, 0.8)), "or your crew colour")
	h.get_parent().queue_free()
	# Goggles off a classic open face that comes with them, and on one that doesn't.
	h = _build("helmet_pudding", {"goggles": false})
	check(h.get_node_or_null("Visor") == null and _named(h, "GoggleBand").is_empty(), "goggles can be left off")
	h.get_parent().queue_free()
	h = _build("helmet_chequer", {"goggles": true})
	check(_named(h, "Lens").size() == 2, "or put on an open face that comes without")
	h.get_parent().queue_free()
	await t.get_tree().process_frame


## The choices are kept with your gear, go out in your summary and are checked when they come in.
func test_choices_save() -> void:
	var real_path := Progress.path
	Progress.path = "user://profile_helmet_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Helmet Tester", 5)
	Progress.select("Helmet Tester")
	Progress.set_money(1000)
	check(_wear_lid("helmet_pudding") == "" and RiderGear.worn_of(Shed.me())["helmet"] == "helmet_pudding", "bought and wearing the pudding basin")
	var before := RiderGear.sig(RiderGear.worn_of(Shed.me()))
	RiderGear.set_helmet_option("shell", "green")
	RiderGear.set_helmet_option("visor", "red")
	RiderGear.set_helmet_option("goggles", false)
	var worn := RiderGear.worn_of(Shed.me())
	check(worn["shell"] == "green" and worn["visor"] == "red" and worn["goggles"] == false and RiderGear.sig(worn) != before,
		"shell colour, visor and goggles are set, and the rider is drawn again (%s)" % RiderGear.sig(worn))
	RiderGear.set_helmet_option("goggles", true)
	check(RiderGear.flick_visor() == "Goggles up" and RiderGear.visor_up(Shed.me()), "the goggles go up")
	check(RiderGear.sig(RiderGear.worn_of(Shed.me())) == RiderGear.sig(worn).replace("goggles=false", "goggles=true"),
		"flicking them isn't a change of gear (nothing's drawn again)")
	var summary: Dictionary = Progress.own_summary()["gear"]
	check(summary["shell"] == "green" and summary["visor"] == "red" and summary["visor_up"] == true, "they go out in your summary")
	Progress.save_profile()
	Progress.profile = {}
	Progress.select("Helmet Tester")
	worn = RiderGear.worn_of(Shed.me())
	check(worn["helmet"] == "helmet_pudding" and worn["shell"] == "green" and worn["visor"] == "red" and worn["goggles"] == true
		and RiderGear.visor_up(Shed.me()), "kept in your profile: the helmet, its colour, visor and goggles, and where you left them")
	# Changing helmet keeps the colour and visor.
	_wear_lid("helmet_kestrel")
	check(RiderGear.worn_of(Shed.me())["visor"] == "red" and RiderGear.worn_of(Shed.me())["shell"] == "green", "a new helmet keeps your colour and visor")
	# Back as it comes.
	RiderGear.set_helmet_option("shell", "")
	RiderGear.set_helmet_option("visor", "")
	worn = RiderGear.worn_of(Shed.me())
	check(not worn.has("shell") and not worn.has("visor") and RiderGear.visor_of(worn) == "blue", "and can go back as the helmet comes")
	# A summary from someone else is checked.
	var clean: Dictionary = Progress._clean_summary({"gear": {"helmet": "helmet_sprint", "shell": "plaid", "visor": 7, "goggles": "yes",
		"visor_up": "true", "jacket": "jacket_mx"}})["gear"]
	check(not clean.has("shell") and not clean.has("visor") and not clean.has("goggles") and not clean.has("visor_up")
		and clean["helmet"] == "helmet_sprint", "nonsense helmet options in a summary are dropped (%s)" % str(clean))
	clean = Progress._clean_summary({"gear": {"helmet": "helmet_sprint", "shell": "cream", "visor": "silver", "visor_up": true}})["gear"]
	check(clean["shell"] == "cream" and clean["visor"] == "silver" and clean["visor_up"] == true, "real ones are kept")
	Progress.save_profile()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)


## The visor button: a binding of its own, a short swing, everyone sees it, your own view stays.
func test_visor_toggle() -> void:
	var entry: Array = Settings.ACTIONS.filter(func(a): return a[0] == "visor")
	check(entry.size() == 1 and entry[0][2] == ["foot", "ride"] and InputMap.has_action("visor"), "the visor has a binding, on foot and riding")
	check(Settings.binding_text("visor", false) == "Apostrophe" and Controls.key("visor", false) == "'",
		"it comes on the apostrophe key, shown as ' (%s)" % Settings.binding_text("visor", false))
	check(Settings.clashes().filter(func(c): return c["a"] == "visor" or c["b"] == "visor").is_empty(), "and it clashes with nothing")
	var real_path := Progress.path
	Progress.path = "user://profile_helmet_test.json"
	DirAccess.remove_absolute(Progress.path)
	Shed.start_new("Visor Tester", 5)
	Progress.select("Visor Tester")
	Progress.set_money(1000)
	_wear_lid("helmet_open_cream")
	check(RiderGear.flick_visor() == "No visor on this helmet." and not RiderGear.visor_up(Shed.me()), "an open face without goggles has nothing to flick")
	_wear_lid("helmet_stealth")
	# Your own figure (the Shop's turntable, say) follows your visor.
	var fig := RiderFigure.make(RiderGear.worn_of(Shed.me()), Color.RED)
	t.add_child(fig)
	var visor := fig.get_node("Head/Helmet/Visor") as HelmetVisor
	check(visor != null and visor.peer == Shed.me() and visor.amount == 0.0, "the visor starts down")
	check(RiderGear.flick_visor() == "Visor up" and RiderGear.visor_up(Shed.me()) and Shed.visors.get(Shed.me()) == true,
		"the button flicks it up, and the host passes it round")
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	var mid := visor.amount
	for i in 40:
		await t.get_tree().process_frame
	check(mid > 0.0 and mid < 1.0 and visor.settled() and visor.amount == 1.0 and visor.rotation.x > 0.5,
		"it swings up over a moment, front edge first (%.2f part way, %.2f rad up)" % [mid, visor.rotation.x])
	RiderGear.flick_visor()
	for i in 40:
		await t.get_tree().process_frame
	check(visor.amount == 0.0 and absf(visor.rotation.x) < 0.001, "and back down")
	fig.queue_free()
	# Someone else's: through the host, as it happens, or from their summary for a late joiner.
	var peer := 4321
	Progress._summaries[peer] = {"name": "Visor Friend", "gear": RiderGear.clean_worn({"helmet": "helmet_kestrel"})}
	var rp := RemotePlayer.new()
	t.add_child(rp)
	rp.setup(peer, "Visor Friend", Color(0.2, 0.7, 0.3))
	var theirs := rp.find_children("Visor", "HelmetVisor", true, false)
	check(theirs.size() == 1 and (theirs[0] as HelmetVisor).peer == peer and not RiderGear.visor_up(peer), "another player's visor, down")
	Shed._apply(peer, {"a": "visor", "up": true})
	for i in 40:
		await t.get_tree().process_frame
	check(RiderGear.visor_up(peer) and (theirs[0] as HelmetVisor).amount == 1.0, "they flick it up: you see it go up")
	Shed._visor(peer, false)   # as a client hears it from the host
	for i in 40:
		await t.get_tree().process_frame
	check(not RiderGear.visor_up(peer) and (theirs[0] as HelmetVisor).amount == 0.0, "and down again, on a client too")
	Shed.visors.erase(peer)
	Progress._summaries[peer]["gear"]["visor_up"] = true
	check(RiderGear.visor_up(peer), "joining later, their summary says it's up")
	rp.queue_free()
	Progress._summaries.erase(peer)
	# Riding: the key flicks it; the first-person eye and what it leaves out don't change.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Progress.select("Visor Tester")
	_wear_lid("helmet_kestrel")
	var faithful: int = t._bike_named("Old Faithful")
	Shed.request({"a": "mount", "bike": faithful})
	for i in 5:
		await t.get_tree().physics_frame
	var bike: Bike = main.bike
	check(bike != null and bike.model.rider_gear["helmet"] == "helmet_kestrel", "riding in the race lid")
	var own := bike.model._rider.find_children("Visor", "HelmetVisor", true, false)
	check(own.size() == 1 and (own[0] as HelmetVisor).peer == Shed.me(), "your rider's visor follows yours")
	var lens := _named(own[0], "Lens")[0] as MeshInstance3D
	var eye: Vector3 = bike.model._eye
	var rider: Node3D = bike.model._rider
	var was := RiderGear.visor_up(Shed.me())
	t._press("visor")
	for i in 40:
		await t.get_tree().process_frame
	check(RiderGear.visor_up(Shed.me()) != was and (own[0] as HelmetVisor).settled() and main.hud._flash_raw.contains("Visor"),
		"the visor key flicks it on the bike (%s)" % main.hud._flash_raw)
	var pv := own[0] as HelmetVisor
	check(pv._rest.y > 0.01 and pv.position.is_equal_approx(pv._rest + pv.lift * (1.0 if pv.up else 0.0)),
		"it swings about its own pivots by the temples (%s)" % str(pv.position))
	check(bike.model._rider == rider and bike.model._eye == eye and lens.layers == 1 << (BikeModel.HELMET_LAYER - 1),
		"your first-person view doesn't change: the same eye, and the visor stays out of it")
	t._press("visor")
	for i in 40:
		await t.get_tree().process_frame
	check(RiderGear.visor_up(Shed.me()) == was, "and again puts it back")
	main._get_off()
	for i in 5:
		await t.get_tree().physics_frame
	main.queue_free()
	await t.get_tree().process_frame
	Progress.save_profile()
	DirAccess.remove_absolute(Progress.path)
	Progress.path = real_path
	Progress.select(Settings.player_name)
