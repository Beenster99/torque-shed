class_name DebugTab
extends ScrollContainer
## The Esc menu's Debug tab, for trying things out: reset or max out your XP and money, reset
## everyone's XP (the host tells every player's game), empty the garage's account or give it
## a million pounds or pay tonight's bills now (host), and start any kind of contract there and then for testing (host):
## a customer arriving at reception, or the job taken on at once, at a chosen difficulty, and
## the recovery jobs with the truck granted if the garage hasn't got it. Puncture a tyre, or fix
## a bike up (now, or by itself whenever it needs it, to keep a long test ride going). The
## performance profiler and its recording (see PerfOverlay). Every reset asks first.

## How often (seconds) the automatic fix looks the bike you're riding over.
const AUTO_FIX_EVERY := 3.0
## The automatic fix tops the tanks up once they're down to this share of full.
const AUTO_FIX_FUEL := 0.3
## ...and mends the bike once a part has worn this far.
const AUTO_FIX_WEAR := 0.2

var _info: Label
var _all_xp: Button
var _garage: Button
var _grant: Button
var _night: Button
var _tier: OptionButton
var _host_only: Array[Control] = []    # the contract buttons, for the host only
var _confirm: ConfirmationDialog
var _pending := Callable()
var _tyre_note: Label
## Whether the bike you're riding is fixed up by itself whenever it needs it (see auto_fix_tick).
var auto_fix := false
var _auto_fix_toggle: CheckButton
var _auto_fix_t := 0.0
var _fix_note: Label
var _perf_toggle: CheckButton
var _perf_note: Label
var _adv_seed: SpinBox
var _adv_km: SpinBox
var _adv_note: Label


func _ready() -> void:
	name = "Debug"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UITheme.title("Debug", 26))
	box.add_child(UITheme.label("Testing helpers. Resets can't be undone.", 15, Color(1, 1, 1, 0.6)))
	_info = UITheme.label("", 16, UITheme.ACCENT)
	box.add_child(_info)

	box.add_child(UITheme.label("XP", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Reset my XP", func(): _ask("Reset your XP?",
			"You go back to level 1 with no XP, tool upgrades, skills or goals.", "Reset my XP", reset_my_xp)),
		_button("Max my XP", max_my_xp),
	]))
	_all_xp = _button("Reset everyone's XP", func(): _ask("Reset everyone's XP?",
		"Every player in the shed goes back to level 1 with no XP, tool upgrades, skills or goals.",
		"Reset everyone", reset_all_xp))
	box.add_child(_row([_all_xp]))

	box.add_child(UITheme.label("Money", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Reset my money", func(): _ask("Reset your money?", "Your cash goes back to nothing.", "Reset my money",
			reset_my_money)),
		_button("Max my money", max_my_money),
	]))
	_garage = _button("Reset garage money", func(): _ask("Reset the garage money?",
		"The shed's own account goes back to nothing, for everyone.", "Reset garage money", reset_garage_money))
	_grant = _button("Give the garage £1,000,000", give_garage_million)
	# Midnight now: the night's running costs and loan repayments come out (see Money.new_day).
	_night = _button("Pay tonight's bills now", func(): Shed.money_new_day())
	box.add_child(_row([_garage, _grant, _night]))

	box.add_child(UITheme.label("Contracts (host)", 15, UITheme.ACCENT))
	box.add_child(UITheme.label("Any kind of job, whatever the reputation or level: a customer arriving at reception, or the job taken on there and then.",
		14, Color(1, 1, 1, 0.6)))
	_tier = OptionButton.new()
	_tier.add_item("As usual")
	for t in Contracts.TIERS:
		_tier.add_item(t)
	_tier.tooltip_text = "How big a job: the number of service tasks, MOT faults, batch size or test ride length; detailing: a wash, a wash and polish, or the full detail."
	var top := _row([_button("Send a customer", func(): Shed.request({"a": "contract_spawn"})),
		_button("Reputation +5", func(): Shed.request({"a": "contract_rep", "value": Contracts.reputation() + 5}))])
	var tier_label := UITheme.label("Difficulty", 15)
	tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tier_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(tier_label)
	top.add_child(_tier)
	box.add_child(top)
	for c in top.get_children():
		if c is Button and c != _tier:
			_host_only.append(c)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for kind in Contracts.KINDS:
		var k: String = kind
		var name_label := UITheme.label("%s  (rep %d)" % [Contracts.KIND_NAMES[k], int(Contracts.UNLOCK.get(k, 0))], 15)
		name_label.custom_minimum_size.x = 260.0
		grid.add_child(name_label)
		var send := _button("Customer arrives", func(): send_contract(k))
		send.name = "send_" + k
		var start := _button("Start the job now", func(): start_contract(k))
		start.name = "start_" + k
		for b in [send, start]:
			grid.add_child(b)
			_host_only.append(b)
	for kind in Recovery.KIND_NAMES:
		var k: String = kind
		grid.add_child(UITheme.label("%s  (recovery truck)" % Recovery.KIND_NAMES[k], 15))
		var offer := _button("Phone offer", func(): send_recovery(k))
		offer.name = "send_" + k
		var start := _button("Start the job now", func(): start_recovery(k))
		start.name = "start_" + k
		for b in [offer, start]:
			grid.add_child(b)
			_host_only.append(b)
	var truck := _button("Grant the recovery truck", func(): Shed.request({"a": "recovery_grant"}))
	box.add_child(_row([truck]))
	_host_only.append(truck)

	box.add_child(UITheme.label("Tyres: the bike you're riding, or the one nearest you", 15, UITheme.ACCENT))
	box.add_child(_row([
		_button("Slow puncture, front", func(): puncture("front", "slow")),
		_button("Slow puncture, rear", func(): puncture("rear", "slow")),
		_button("Fast puncture, front", func(): puncture("front", "fast")),
		_button("Fast puncture, rear", func(): puncture("rear", "fast")),
	]))
	_tyre_note = UITheme.label("", 14, Color(1, 1, 1, 0.6))
	box.add_child(_tyre_note)

	# Fixing a bike up (see Shed.debug_fix_bike): wear, rust, punctures, faults, fuel and fluids.
	box.add_child(UITheme.label("Bike: the one you're riding, or the one nearest you", 15, UITheme.ACCENT))
	_auto_fix_toggle = CheckButton.new()
	_auto_fix_toggle.text = "Automatically fix my bike while I ride (for long test rides)"
	_auto_fix_toggle.toggled.connect(func(on): auto_fix = on)
	box.add_child(_row([_button("Fix my bike now", fix_bike), _auto_fix_toggle]))
	_fix_note = UITheme.label("", 14, Color(1, 1, 1, 0.6))
	box.add_child(_fix_note)

	# Staff (see Staff): a full payroll at once, whatever the level, and everyone off sick or back.
	box.add_child(UITheme.label("Staff (host)", 15, UITheme.ACCENT))
	var staff_row := _row([
		_button("Hire one of each", func(): Shed.request({"a": "staff_debug_hire_all"})),
		_button("Make everyone sick", func(): Shed.request({"a": "staff_debug_sick", "sick": true})),
		_button("Make everyone well", func(): Shed.request({"a": "staff_debug_sick", "sick": false})),
	])
	box.add_child(staff_row)
	for b in staff_row.get_children():
		_host_only.append(b)

	# Adventure rides (see Adventure): start a tour of a bundled region about a chosen length, end it, or skip along.
	box.add_child(UITheme.label("Adventure (host)", 15, UITheme.ACCENT))
	_adv_seed = SpinBox.new()
	_adv_seed.min_value = 1
	_adv_seed.max_value = 999999
	_adv_seed.value = 1
	_adv_seed.prefix = "Seed"
	_adv_km = SpinBox.new()
	_adv_km.min_value = Adventure.MIN_KM
	_adv_km.max_value = Adventure.MAX_KM
	_adv_km.value = 40.0
	_adv_km.suffix = "km"
	var adv_start := _button("Start adventure", func(): Adventure.start(AdventurePlans.sample(_adv_km.value), int(_adv_seed.value)))
	var adv_end := _button("End adventure", func(): Shed.request({"a": "adventure_end"}))
	box.add_child(_row([_adv_seed, _adv_km, adv_start, adv_end]))
	_host_only.append(adv_start)
	_host_only.append(adv_end)
	box.add_child(_row([
		_button("Skip 1 km ahead", func(): if AdventureTrip.current: AdventureTrip.current.jump(1000.0)),
		_button("Skip 10 km ahead", func(): if AdventureTrip.current: AdventureTrip.current.jump(10000.0)),
	]))
	# Ride Anywhere v2's road network (see AdventureWorld.network): this machine's next ride streams every road round you.
	var net_toggle := CheckButton.new()
	net_toggle.name = "RoadNetworkToggle"
	net_toggle.text = "Road network (test): my next ride builds every road and junction round me, plan or no plan"
	net_toggle.button_pressed = AdventureWorld.network
	net_toggle.toggled.connect(func(on): AdventureWorld.network = on)
	box.add_child(net_toggle)
	_adv_note = UITheme.label("", 14, Color(1, 1, 1, 0.6))
	_adv_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_adv_note)

	# The performance profiler (see PerfOverlay): the panel, and a recording to send in.
	box.add_child(UITheme.label("Performance", 15, UITheme.ACCENT))
	var perf_note := UITheme.label("", 14, Color(1, 1, 1, 0.6))
	Controls.bind_text(perf_note, "The profiler panel shows the frame rate and where each frame's time goes ({perf_overlay}). " +
		"Record writes 60 seconds of it to a file to send in ({perf_record}).")
	perf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(perf_note)
	_perf_toggle = CheckButton.new()
	_perf_toggle.text = "Show the performance profiler"
	_perf_toggle.toggled.connect(func(on): if Settings.perf: Settings.perf.toggle(on))
	_perf_note = UITheme.label("", 14, UITheme.ACCENT)
	_perf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_row([_perf_toggle, _button("Record 60 s", func(): if Settings.perf: Settings.perf.record())]))
	box.add_child(_perf_note)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func():
		if _pending.is_valid():
			_pending.call()
		_pending = Callable())
	_confirm.canceled.connect(func(): _pending = Callable())
	add_child(_confirm)


func _process(delta: float) -> void:
	auto_fix_tick(delta)
	if not is_visible_in_tree():
		return
	_auto_fix_toggle.set_pressed_no_signal(auto_fix)
	var host := Shed.is_authority()
	var trip := AdventureTrip.current
	_adv_note.text = "Out on an adventure. Road streaming: %s" % trip.world.timing_text() if trip and trip.on_trip() \
		else "Not on an adventure."
	_all_xp.disabled = not host
	_all_xp.tooltip_text = "" if host else "Only the host can reset everyone's XP."
	for b in [_garage, _grant, _night]:
		b.disabled = not host
		b.tooltip_text = "" if host else "Only the host can change the garage's money."
	for c in _host_only:
		(c as BaseButton).disabled = not host
		c.tooltip_text = "" if host else "Only the host can start contracts."
	_tier.disabled = not host
	if Settings.perf:
		_perf_toggle.set_pressed_no_signal(Settings.perf.shown)
		_perf_note.text = ("Recording... %d s left" % ceili(Settings.perf.record_left)) if Settings.perf.recording() \
			else ("Last recording: %s" % Settings.perf.last_file if Settings.perf.last_file != "" else "")
	_info.text = "You: level %d, %d XP, %s     Garage: %s" % [Progress.level(), int(Progress.profile.get("xp", 0)),
		TvChannels.money_text(Progress.money()), TvChannels.money_text(Shed.garage_money)]


## Asks before doing `then`.
func _ask(title: String, text: String, ok: String, then: Callable) -> void:
	_pending = then
	_confirm.title = title
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok
	_confirm.popup_centered()


## Whether a reset is waiting on its confirm dialog (for tests).
func asking() -> bool:
	return _confirm.visible and _pending.is_valid()


## Answers the open confirm dialog, as its OK (true) or Cancel button would.
func answer(yes: bool) -> void:
	if yes:
		_confirm.confirmed.emit()
	else:
		_confirm.canceled.emit()
	_confirm.hide()


func reset_my_xp() -> void:
	Progress.debug_reset_xp()


func max_my_xp() -> void:
	Progress.debug_max_xp()


func reset_all_xp() -> void:
	Progress.debug_reset_all_xp()


func reset_my_money() -> void:
	Progress.spend(Progress.money(), "Debug: money reset")


func max_my_money() -> void:
	Progress.earn(Progress.MAX_MONEY - Progress.money(), "Debug: maxed out")


func reset_garage_money() -> void:
	Shed.request({"a": "garage_money", "value": 0})


## Host: a million pounds into the business's account (see Money.DEBUG_GRANT).
func give_garage_million() -> void:
	Shed.request({"a": "money_debug_grant"})


## The difficulty chosen for the contract buttons: -1 as usual, else an index into Contracts.TIERS.
func tier() -> int:
	return _tier.selected - 1 if _tier.selected > 0 else -1


## Picks the difficulty (-1 as usual, else an index into Contracts.TIERS).
func set_tier(t: int) -> void:
	_tier.select(clampi(t + 1, 0, _tier.item_count - 1))


## Host: a customer for `kind` (see Contracts.KINDS) arrives at reception.
func send_contract(kind: String) -> void:
	Shed.request({"a": "contract_spawn", "kind": kind, "tier": tier()})


## Host: a `kind` job is taken on there and then, the bike in the car park or on a bay.
func start_contract(kind: String) -> void:
	Shed.request({"a": "contract_start", "kind": kind, "tier": tier()})


## Host: a barn find or crash rescue offer rings in (the truck too if the garage hasn't got one).
func send_recovery(kind: String) -> void:
	if not Recovery.owned():
		Shed.request({"a": "recovery_grant"})
	Shed.request({"a": "recovery_spawn", "kind": kind})


## Host: a barn find or crash rescue taken on there and then, the truck granted if need be.
func start_recovery(kind: String) -> void:
	Shed.request({"a": "recovery_start", "kind": kind})


## Presses the button named `node_name` (the contract buttons: "start_mot", "send_barn"...; for tests).
func press_named(node_name: String) -> void:
	var b := find_child(node_name, true, false) as Button
	if b and not b.disabled:
		b.pressed.emit()


## Punctures a tyre for testing (see Puncture): on the bike you're riding, else the bike nearest you.
func puncture(side: String, kind: String) -> void:
	var bike := puncture_target()
	if bike == 0:
		_tyre_note.text = "No bike near you to puncture."
		return
	Shed.request({"a": "puncture", "bike": bike, "side": side, "kind": kind, "debug": true})
	_tyre_note.text = "Punctured the %s tyre on %s (%s)." % [side, str(Shed.bikes[bike]["name"]), kind]


## Fixes up the bike you're riding, or the nearest one (see Shed.debug_fix_bike).
func fix_bike() -> void:
	var bike := puncture_target()
	if bike == 0:
		_fix_note.text = "No bike near you to fix."
		return
	Shed.request({"a": "debug_fix_bike", "bike": bike})
	_fix_note.text = "Fixed up %s." % str(Shed.bikes[bike]["name"])


## With the automatic fix on, now and then: the bike you're riding is fixed up once it needs it.
func auto_fix_tick(delta: float) -> void:
	if not auto_fix:
		return
	_auto_fix_t -= delta
	if _auto_fix_t > 0.0:
		return
	_auto_fix_t = AUTO_FIX_EVERY
	var bike := Shed.riding(Shed.me())
	if bike != 0 and needs_fix(bike):
		Shed.request({"a": "debug_fix_bike", "bike": bike})


## Whether a bike needs the automatic fix: a fault, a worn part or low on fuel.
static func needs_fix(bike_id: int) -> bool:
	if not Shed.bikes.has(bike_id):
		return false
	if not Roadside.active(bike_id).is_empty():
		return true
	var cap := 0.0
	for slot in ["tank", "aux_tank"]:
		var id := Shed.item_on(bike_id, slot)
		if id != 0:
			cap += PartsDB.fluid_capacity(str(Shed.items[id]["part"]))
	if cap > 0.0 and cap - Shed.fuel_space(bike_id) < cap * AUTO_FIX_FUEL:
		return true
	for id in Shed.bikes[bike_id].get("slots", {}).values():
		if Shed.items.has(int(id)) and float(Shed.items[int(id)]["wear"]) >= AUTO_FIX_WEAR:
			return true
	return false


## The bike a debug puncture goes in: the one you're riding, or the nearest within 10 m of you.
func puncture_target() -> int:
	var riding := Shed.riding(Shed.me())
	if riding != 0:
		return riding
	var walker := get_tree().get_first_node_in_group("local_walker") as Node3D
	if walker == null:
		return 0
	var best := 0
	var best_d := 10.0
	for id in Shed.bikes:
		var d := (Shed.bikes[id]["xf"] as Transform3D).origin.distance_to(walker.global_position)
		if d < best_d:
			best_d = d
			best = int(id)
	return best


## Presses the button labelled `text` (for tests).
func press(text: String) -> void:
	for b in find_children("*", "Button", true, false):
		if (b as Button).text == text and not (b as Button).disabled and not _confirm.is_ancestor_of(b):
			(b as Button).pressed.emit()
			return


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for b in buttons:
		row.add_child(b)
	return row


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
