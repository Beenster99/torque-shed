class_name ShopTab
extends VBoxContainer
## The Esc menu's Shop tab: spend your own money on rider gear (helmets, jackets, trousers,
## boots and gloves, see RiderGear) and trinkets for the shed (see Trinkets). Pick a category,
## then an item: the turntable shows you wearing it (or the trinket), Buy pays for it out of your
## cash and puts it on, Wear changes into something you already own. Trinkets are delivered
## outside the roller door, then carried and placed like any other shed kit.
##
## Under Helmets the turntable comes in close on the head, and the helmet you wear can be had in
## any shell colour with any visor (and the classic open face with or without goggles), free:
## see RiderGear.set_helmet_option. A button flicks the visor up and down to see it move.

const CATEGORIES: Array[String] = ["helmet", "jacket", "trousers", "boots", "gloves", "trinket"]
const PREVIEW_SIZE := Vector2i(300, 280)

var category := "helmet"
var selected := ""
var _cat_btns := {}
var _list: VBoxContainer
var _money: Label
var _name: Label
var _desc: Label
var _price: Label
var _status: Label
var _buy: Button
var _wear: Button
var _viewport: SubViewport
var _turntable: Node3D
var _camera: Camera3D
var _preview_sig := ""
var _due := true
var _spin := 0.0
var _swing := false     # a wall trinket swings to and fro rather than showing its bare back
var _helmet_box: VBoxContainer   # the helmet's options, under Helmets
var _model: Label
var _shell: OptionButton
var _visor: OptionButton
var _visor_row: HBoxContainer
var _goggles: CheckBox
var _flick: Button


func _ready() -> void:
	name = "Shop"
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_child(UITheme.title("Rider shop", 24))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_money = UITheme.title("", 20, Color(0.55, 0.95, 0.6))
	head.add_child(_money)
	add_child(head)
	add_child(UITheme.label("Spend your own money on gear for your rider, and trinkets to brighten up the shed. What you wear goes with you to any shed; everyone sees it.",
		14, Color(1, 1, 1, 0.6)))
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 6)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = "Trinkets" if c == "trinket" else str(RiderGear.SLOT_NAMES[c])
		b.toggle_mode = true
		b.pressed.connect(show_category.bind(c))
		cats.add_child(b)
		_cat_btns[c] = b
	add_child(cats)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	add_child(cols)
	# The items scroll: there are more trinkets than fit.
	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.custom_minimum_size = Vector2(330, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	cols.add_child(detail)
	detail.add_child(_make_preview())
	# The name, price and Buy come straight under the turntable, before the description, so
	# Buy is always in sight however long the list or the text gets.
	_name = UITheme.title("", 19, Color.WHITE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_name)
	_price = UITheme.label("", 16, UITheme.ACCENT)
	detail.add_child(_price)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_buy = Button.new()
	_buy.pressed.connect(buy_selected)
	buttons.add_child(_buy)
	_wear = Button.new()
	_wear.text = "Wear"
	_wear.pressed.connect(wear_selected)
	buttons.add_child(_wear)
	detail.add_child(buttons)
	detail.add_child(_make_helmet_options())
	_status = UITheme.label("", 14, Color(1, 0.8, 0.6))
	detail.add_child(_status)
	_desc = UITheme.label("", 14, Color(1, 1, 1, 0.75))
	detail.add_child(_desc)
	Progress.changed.connect(func(): _due = true)
	visibility_changed.connect(func(): _due = true)
	show_category("helmet")


## The helmet's options: what kind it is, its shell colour, its visor, goggles, and a button to
## flick the visor.
func _make_helmet_options() -> Control:
	_helmet_box = VBoxContainer.new()
	_helmet_box.add_theme_constant_override("separation", 4)
	_model = UITheme.label("", 14, Color(1, 1, 1, 0.8))
	_helmet_box.add_child(_model)
	_shell = OptionButton.new()
	for id in RiderGear.SHELL_ORDER:
		_shell.add_item(str(RiderGear.SHELLS[id]["name"]))
	_shell.item_selected.connect(func(i: int):
		RiderGear.set_helmet_option("shell", RiderGear.SHELL_ORDER[i])
		_option_changed())
	_helmet_box.add_child(_option_row("Shell colour", _shell))
	_visor = OptionButton.new()
	_visor.add_item("As it comes")
	for id in RiderGear.VISOR_ORDER:
		_visor.add_item(str(RiderGear.VISORS[id]["name"]))
	_visor.item_selected.connect(func(i: int):
		RiderGear.set_helmet_option("visor", "" if i == 0 else RiderGear.VISOR_ORDER[i - 1])
		_option_changed())
	_visor_row = _option_row("Visor", _visor)
	_helmet_box.add_child(_visor_row)
	_goggles = CheckBox.new()
	_goggles.text = "Goggles"
	_goggles.toggled.connect(func(on: bool):
		RiderGear.set_helmet_option("goggles", on)
		_option_changed())
	_helmet_box.add_child(_goggles)
	_flick = Button.new()
	_flick.pressed.connect(func():
		_status.text = RiderGear.flick_visor())
	Controls.bind_text(_flick, "Flick the visor up / down ({visor})")
	_helmet_box.add_child(_flick)
	return _helmet_box


func _option_row(title: String, what: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UITheme.label(title, 14, Color(1, 1, 1, 0.7))
	l.custom_minimum_size.x = 100
	row.add_child(l)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(what)
	return row


func _option_changed() -> void:
	Sfx.play_ui("click", -10.0)
	_redress_my_bike()
	_due = true


## The helmet options as they stand, for the helmet you wear (they go with any helmet).
func _show_helmet_options() -> void:
	_helmet_box.visible = category == "helmet" and selected != ""
	if not _helmet_box.visible:
		return
	var worn: Dictionary = RiderGear.worn_of(Shed.me())
	var trying := worn.duplicate()
	trying["helmet"] = selected
	var model := RiderGear.helmet_model(selected)
	var cap := str(RiderGear.ITEMS[selected].get("shape", "")) == "cap"
	_model.text = "%s%s" % [HelmetModel.MODEL_NAMES.get(model, "Helmet"), "  ·  on the bike: a plain lid" if cap else ""]
	_shell.select(maxi(0, RiderGear.SHELL_ORDER.find(str(worn.get("shell", "")))))
	_visor.select(RiderGear.VISOR_ORDER.find(str(worn["visor"])) + 1 if worn.has("visor") else 0)
	_goggles.visible = model == "open_classic"
	_goggles.set_pressed_no_signal(RiderGear.goggles_on(trying))
	_visor_row.visible = RiderGear.can_flip(trying) or model == "mx"
	(_visor_row.get_child(0) as Label).text = "Lenses" if model in ["open_classic", "mx"] else "Visor"
	_flick.visible = RiderGear.wearing(selected) and RiderGear.can_flip(trying)


## The turntable: your rider (or a trinket) slowly turning in a little 3D view of its own.
func _make_preview() -> Control:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = Vector2(PREVIEW_SIZE)
	box.stretch = true
	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.12, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 0.8
	# Shiny things (an iridium visor, chrome) reflect a sky, though the background stays plain.
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.35, 0.5, 0.75)
	sky.sky_horizon_color = Color(0.75, 0.78, 0.82)
	sky.ground_bottom_color = Color(0.12, 0.12, 0.13)
	sky.ground_horizon_color = Color(0.45, 0.45, 0.47)
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = sky
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(200.0), 0.0)
	fill.light_energy = 0.5
	_viewport.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.6
	disc.height = 0.04
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.24)
	fm.roughness = 0.4
	floor_mi.material_override = fm
	floor_mi.position.y = -0.02
	_viewport.add_child(floor_mi)
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 1.25, -3.6), Vector3(0.0, 0.95, 0.0))
	return box


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _due:
		_due = false
		_refresh()
	_spin += delta * 0.6
	_turntable.rotation.y = sin(_spin) * 0.7 if _swing else _spin


## Shows a category: its items in the list, the first (or what you wear) picked.
func show_category(c: String) -> void:
	category = c
	for k in _cat_btns:
		_cat_btns[k].button_pressed = k == c
	var ids := items_of(c)
	selected = ids[0] if not ids.is_empty() else ""
	if c != "trinket":
		selected = str(RiderGear.worn_of(Shed.me())[c])
	_status.text = ""
	_refresh()


static func items_of(c: String) -> Array:
	return Trinkets.all() if c == "trinket" else RiderGear.by_slot(c)


func select(id: String) -> void:
	selected = id
	_status.text = ""
	_refresh()


func _refresh() -> void:
	_money.text = "Your money: %s" % TvChannels.money_text(Progress.money())
	for c in _list.get_children():
		c.queue_free()
	for id in items_of(category):
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var label := str(Trinkets.MODELS[id]["name"]) if category == "trinket" else str(RiderGear.ITEMS[id]["name"])
		var tag := TvChannels.money_text(Trinkets.price(id)) if category == "trinket" else RiderGear.status_text(id)
		b.text = "%s   ·   %s" % [label, tag]
		b.pressed.connect(select.bind(id))
		_list.add_child(b)
	if selected == "":
		return
	if category == "trinket":
		var t: Dictionary = Trinkets.MODELS[selected]
		_name.text = str(t["name"])
		_desc.text = Controls.hint(str(t["desc"]))
		_price.text = "%s  ·  for the shed: arrives outside the roller door" % TvChannels.money_text(int(t["price"]))
		_buy.text = "Buy (%s)" % TvChannels.money_text(int(t["price"]))
		_buy.disabled = false
		_wear.visible = false
	else:
		var item: Dictionary = RiderGear.ITEMS[selected]
		_name.text = str(item["name"])
		_desc.text = Controls.hint(str(item["desc"]))
		var owned := RiderGear.owns(selected)
		_price.text = RiderGear.status_text(selected) if owned else ("Free" if int(item["price"]) == 0 else TvChannels.money_text(int(item["price"])))
		_buy.text = "Owned" if owned else "Buy and wear (%s)" % TvChannels.money_text(int(item["price"]))
		_buy.disabled = owned
		_wear.visible = true
		_wear.disabled = not owned or RiderGear.wearing(selected)
		_wear.text = "Wearing" if RiderGear.wearing(selected) else "Wear"
	_show_helmet_options()
	_update_preview()


## The turntable shows you in what you wear with the picked item swapped in (try it on), or the
## picked trinket.
func _update_preview() -> void:
	var tint: Color = Shed.PAINTS[Net.local_slot() % Shed.PAINTS.size()]
	var gear := RiderGear.worn_of(Shed.me())
	if category != "trinket":
		gear[category] = selected
	var s := "%s|%s|%s" % [category, selected if category == "trinket" else RiderGear.sig(gear), tint.to_html()]
	if s == _preview_sig:
		return
	_preview_sig = s
	# Helmets close up on the head, everything else the whole rider.
	if category == "helmet":
		_camera.look_at_from_position(Vector3(0.0, 1.72, -1.25), Vector3(0.0, 1.62, 0.0))
	else:
		_camera.look_at_from_position(Vector3(0.0, 1.25, -3.6), Vector3(0.0, 0.95, 0.0))
	for c in _turntable.get_children():
		c.free()
	_swing = category == "trinket" and bool(Trinkets.MODELS[selected].get("wall", false))
	if category == "trinket":
		var holder := Node3D.new()
		var size: Vector3 = Trinkets.MODELS[selected]["size"]
		var wall := bool(Trinkets.MODELS[selected].get("wall", false))
		var big := maxf(size.x, maxf(size.y, size.z))
		holder.scale = Vector3.ONE * clampf(1.1 / big, 0.6, 5.0)
		holder.position = Vector3(0.0, 0.95 - size.y * 0.5 * holder.scale.y, 0.0) if wall else Vector3(0.0, 0.25, 0.0)
		holder.rotation.y = PI   # its front towards the camera
		if wall:
			holder.position.y = 0.95
		_turntable.add_child(holder)
		Trinkets.build(holder, selected)
	else:
		_turntable.add_child(RiderFigure.make(gear, tint))   # it faces -Z, at the camera


func buy_selected() -> void:
	if selected == "":
		return
	var why := Trinkets.buy(selected) if category == "trinket" else RiderGear.buy(selected)
	if why == "" and category != "trinket":
		why = RiderGear.wear(selected)
		_status.text = "Bought the %s and put it on." % RiderGear.ITEMS[selected]["name"] if why == "" else why
	elif why == "":
		_status.text = Controls.hint("Bought the %s. It's outside by the roller door: press {interact} on it to bring it in.") % \
			str(Trinkets.MODELS[selected]["name"]).to_lower()
	else:
		_status.text = Controls.hint(why)
	if why == "":
		Sfx.play_ui("clink", -6.0)
		_redress_my_bike()
	_due = true


func wear_selected() -> void:
	if selected == "" or category == "trinket":
		return
	var why := RiderGear.wear(selected)
	_status.text = "Wearing the %s." % RiderGear.ITEMS[selected]["name"] if why == "" else why
	_redress_my_bike()
	_due = true


## Changed gear mid-ride: the rider on your own bike changes too (others' follow their summary).
func _redress_my_bike() -> void:
	for b in get_tree().get_nodes_in_group("ridden_bike"):
		if b is Bike and (b as Bike).model:
			(b as Bike).rider_gear = RiderGear.worn_of(Shed.me())
			(b as Bike).model.redress((b as Bike).rider_gear)
