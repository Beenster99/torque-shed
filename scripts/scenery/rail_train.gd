extends Node3D
## The trains on a block's railways and its level crossings' barriers (Ride Anywhere v2, phase D round 1, D2; rail.gd
## lays the track and hands each block's share of its lines to one of these).
##
## Every line has its timetable from the line alone (timetable_of: its kind, its region's stock and its id), and where
## each train is comes from that and the time of day the crew shares (Daylight's, the host's on a co-op ride: clock), so
## every machine sees the same train in the same place without a word between them. A single line has one train going
## back and forth, waiting at each end; a double track mapped as two lines has trains one way on each, every headway.
## A cycle is stretched to divide the day exactly, so midnight's wrap moves no train.
##
## A block draws the cars whose middles are in its own stretch of the line (its neighbours draw the rest), one MultiMesh
## for the stock's cab ends and one for its cars, and nothing in a tunnel. No collision: a train is something to watch.
## A crossing's barriers come down while a train is within CLOSE_M of it (or on it), its red lamps flashing and its
## bell ringing.

const Geo := preload("res://scripts/scenery/rail_geo.gd")

## A train speeds up and slows down at this (m/s/s).
const ACCEL := 0.45
## A shuttle waits this long at each end (s).
const DWELL := 50.0
## A crossing's barriers come down for a train within this far of it (m), and go up once it's this far past.
const CLOSE_M := 550.0
const CLEAR_M := 12.0
## How fast a barrier arm swings (radians a second), and how high it stands up.
const ARM_SPEED := 0.35
const ARM_UP := deg_to_rad(84.0)
## The bell's ring, every so often while the barriers are down or moving (s), and how far it's heard (m).
const BELL_EVERY := 0.55
const BELL_FAR := 140.0

static var _stock_meshes := {}
static var _night_frame := -1
## A time to hold every train at (s into the day), for a picture; NAN for the crew's clock.
static var held := NAN

var portions: Array = []   # rail.gd's _portion: one a line here
var gates: Array = []      # rail.gd's _lay_crossing
var reach := 2500.0
var _multis := {}          # stock key -> [cab MultiMesh, car MultiMesh]
var _arms: MultiMesh
var _lamps: MultiMesh
var _arm_angle := PackedFloat32Array()
var _bells: Array = []
var _bell_t := PackedFloat32Array()
var _flash := 0.0


func setup(p: Array, g: Array, r: float) -> void:
	portions = p
	gates = g
	reach = r
	for pr: Dictionary in portions:
		var key := stock_key(pr["stock"], str(pr["kind"]))
		if _multis.has(key):
			continue
		var pair: Array = []
		for part in ["cab", "car"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = stock_mesh(pr["stock"], str(pr["kind"]), part)
			mm.instance_count = 64
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [part, key.left(8)]
			mmi.multimesh = mm
			AdventureChunk._range(mmi, reach)
			add_child(mmi)
			pair.append(mm)
		_multis[key] = pair
	var arms := 0
	var lamps := 0
	for gt: Dictionary in gates:
		arms += (gt["arms"] as Array).size()
		lamps += (gt["lamps"] as Array).size()
	if arms > 0:
		_arms = MultiMesh.new()
		_arms.transform_format = MultiMesh.TRANSFORM_3D
		_arms.mesh = arm_mesh()
		_arms.instance_count = arms
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Barriers"
		mmi.multimesh = _arms
		AdventureChunk._range(mmi, 600.0)
		add_child(mmi)
	if lamps > 0:
		_lamps = MultiMesh.new()
		_lamps.transform_format = MultiMesh.TRANSFORM_3D
		_lamps.mesh = lamp_mesh()
		_lamps.instance_count = lamps
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "CrossingLamps"
		mmi.multimesh = _lamps
		AdventureChunk._range(mmi, 600.0)
		add_child(mmi)
	_arm_angle.resize(gates.size())
	_arm_angle.fill(ARM_UP)
	_bell_t.resize(gates.size())
	for gt: Dictionary in gates:
		var b := AudioStreamPlayer3D.new()
		b.stream = bell()
		b.bus = "SFX"
		b.unit_size = 6.0
		b.max_distance = BELL_FAR
		b.volume_db = -6.0
		var arms_of: Array = gt["arms"]
		if not arms_of.is_empty():
			b.position = (arms_of[0] as Transform3D).origin
		add_child(b)
		_bells.append(b)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


## Moves every train and barrier to where they are now (and, every so often, rings the bells).
func _update(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame != _night_frame:
		_night_frame = frame
		Geo.night(Daylight.current.lamps if Daylight.current else 0.0)
	var now := clock()
	var t := now.x
	var day := now.y
	var used := {}
	for key in _multis:
		used[key] = [0, 0]
	var want := {}   # stock key -> [[cab transforms], [car transforms]]
	for pr: Dictionary in portions:
		var key := stock_key(pr["stock"], str(pr["kind"]))
		if not want.has(key):
			want[key] = [[], []]
		cars_in(pr, t, day, want[key])
	for key in _multis:
		var mms: Array = _multis[key]
		var got: Array = want.get(key, [[], []])
		for part in 2:
			var mm: MultiMesh = mms[part]
			var list: Array = got[part]
			if list.size() > mm.instance_count:
				mm.instance_count = list.size() + 16
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			mm.visible_instance_count = list.size()
	if gates.is_empty():
		return
	_flash += delta
	var on := fmod(_flash, 1.0) < 0.5
	var ai := 0
	var li := 0
	for g in gates.size():
		var gt: Dictionary = gates[g]
		var closed := gate_closed(gt, portions, t, day)
		var target := 0.0 if closed else ARM_UP
		_arm_angle[g] = move_toward(_arm_angle[g], target, ARM_SPEED * delta) if delta > 0.0 else target
		var busy := closed or _arm_angle[g] < ARM_UP - 0.01
		for pivot: Transform3D in gt["arms"]:
			var b := Basis(Vector3.BACK, _arm_angle[g]) * Basis.from_scale(Vector3(float(gt["length"]), 1.0, 1.0))
			_arms.set_instance_transform(ai, pivot * Transform3D(b, Vector3.ZERO))
			ai += 1
		var lamps: Array = gt["lamps"]
		for k in lamps.size():
			var lit := busy and ((k % 2 == 0) == on)
			var xf: Transform3D = lamps[k]
			_lamps.set_instance_transform(li, xf if lit else Transform3D(Basis.from_scale(Vector3.ONE * 0.001), xf.origin))
			li += 1
		if busy and delta > 0.0:
			_bell_t[g] -= delta
			if _bell_t[g] <= 0.0:
				_bell_t[g] = BELL_EVERY
				var p: AudioStreamPlayer3D = _bells[g]
				if p.is_inside_tree():
					p.play()


# ---------------------------------------------------------------------------- the timetable (pure)

## The shared clock: Vector2(seconds into the day, a day's length in seconds), by the crew's time of day (Daylight: the
## host's on a co-op ride); with the day standing still, this machine's own seconds and 0.
static func clock() -> Vector2:
	var rate := Daylight.local_rate()
	if not is_nan(held):
		return Vector2(held, 24.0 / rate if rate > 0.0 else 0.0)
	if Daylight.current != null and rate > 0.0:
		return Vector2(Daylight.current.hours / rate, 24.0 / rate)
	return Vector2(Time.get_ticks_msec() / 1000.0, 0.0)


## Run `r`'s timetable (rail.gd's runs): {} for no train (a siding, a viaduct with no line on it), else {mode: "shuttle"
## (one train back and forth) or "oneway" (one way every headway), dir, cars, car_len, speed, headway, offset}, from
## its kind, its kit's stock and its id.
static func timetable_of(r: Dictionary) -> Dictionary:
	if not r.get("track", true) or float(r["len"]) < 600.0:
		return {}
	var k: Dictionary = r["kit"]
	var kind := str(r["kind"])
	var cars := int(k.get("cars", 4))
	var car_len := float(k.get("car_len", 20.0))
	if cars * car_len > float(r["len"]) * 0.5:
		cars = maxi(1, int(float(r["len"]) * 0.5 / car_len))
	var pair := int(r.get("pair", 0))
	var dir := pair * (-1 if str(k.get("running", "left")) == "right" else 1)
	var offset := float(absi(str(r["id"]).hash()) % 86400)
	return {"mode": "oneway" if pair != 0 else "shuttle", "dir": dir if pair != 0 else 1, "cars": cars,
		"car_len": car_len, "speed": float(k.get("speed", 30.0)), "headway": float(k.get("headway", 480.0)),
		"offset": offset, "kind": kind}


## A trip of `travel` m at up to `v` m/s: [its time (s), how far along it is `tau` s in] (speeding up and slowing at ACCEL).
static func trip(travel: float, v: float, tau: float) -> Vector2:
	var ta := v / ACCEL
	var da := 0.5 * ACCEL * ta * ta
	if 2.0 * da > travel:
		v = sqrt(ACCEL * travel)
		ta = v / ACCEL
		da = travel * 0.5
	var leg := 2.0 * ta + (travel - 2.0 * da) / v
	var x := 0.0
	if tau <= 0.0:
		x = 0.0
	elif tau < ta:
		x = 0.5 * ACCEL * tau * tau
	elif tau < leg - ta:
		x = da + v * (tau - ta)
	elif tau < leg:
		x = travel - 0.5 * ACCEL * (leg - tau) * (leg - tau)
	else:
		x = travel
	return Vector2(leg, x)


## The trains on a line `length` m long with timetable `tt` at time `t` (s; `day` the day's length, 0 for none):
## [[front's s, dir], ...]. A train going +1 runs from its front back to front - its length; going -1, from its front on.
static func trains_on(tt: Dictionary, length: float, t: float, day := 0.0) -> Array:
	if tt.is_empty():
		return []
	var long := int(tt["cars"]) * float(tt["car_len"])
	var travel := length - long
	if travel < 50.0:
		return []
	var v := float(tt["speed"])
	var leg := trip(travel, v, 0.0).x
	var out: Array = []
	if tt["mode"] == "shuttle":
		var cycle := 2.0 * (leg + DWELL)
		var stretch := 1.0
		if day > 0.0:
			var fit := day / maxf(1.0, roundf(day / cycle))
			stretch = fit / cycle
			cycle = fit
		var ph := fposmod(t + float(tt["offset"]), cycle) / stretch
		if ph < DWELL:
			out.append([long, 1])
		elif ph < DWELL + leg:
			out.append([long + trip(travel, v, ph - DWELL).y, 1])
		elif ph < 2.0 * DWELL + leg:
			out.append([length, 1])
		else:
			out.append([length - long - trip(travel, v, ph - 2.0 * DWELL - leg).y, -1])
	else:
		var h := maxf(float(tt["headway"]), 60.0)
		var stretch := 1.0
		if day > 0.0:
			var fit := day / maxf(1.0, roundf(day / h))
			stretch = fit / h
			h = fit
		var age := fposmod(t + float(tt["offset"]), h)
		while age / stretch < leg:
			var x := trip(travel, v, age / stretch).y
			if int(tt["dir"]) >= 0:
				out.append([long + x, 1])
			else:
				out.append([length - long - x, -1])
			age += h
	return out


## Where portion `pr`'s (rail.gd's _portion) trains' cars are at `t`: their transforms appended to `into` ([[cabs], [cars]]),
## each in the block's frame, only those whose middles are in the portion's own stretch and not in a tunnel.
static func cars_in(pr: Dictionary, t: float, day: float, into: Array) -> void:
	var tt: Dictionary = pr["timetable"]
	var cars := int(tt.get("cars", 0))
	var car_len := float(tt.get("car_len", 20.0))
	var cab_both := str(pr["stock"].get("nose", "unit")) in ["unit", "round", "tram"]
	for tr: Array in trains_on(tt, float(pr["len"]), t, day):
		var front := float(tr[0])
		var dir := int(tr[1])
		for c in cars:
			var mid := front - dir * (c + 0.5) * car_len
			if not _mine(pr, mid):
				continue
			var xf := car_at(pr, mid, car_len, dir)
			if xf == Transform3D():
				continue
			var cab := c == 0 or (cab_both and c == cars - 1)
			if cab and c == cars - 1 and c != 0:
				xf.basis = xf.basis.rotated(xf.basis.y.normalized(), PI)
			(into[0 if cab else 1] as Array).append(xf)


static func _mine(pr: Dictionary, s: float) -> bool:
	for m: Array in pr["mine"]:
		if s >= float(m[0]) and s < float(m[1]):
			return true
	return false


## A car `car_len` long with its middle `mid` m along portion `pr`, facing `dir`: its bogies on the rails at mid either
## side. Transform3D() where it's off the portion's samples or in a tunnel.
static func car_at(pr: Dictionary, mid: float, car_len: float, dir: int) -> Transform3D:
	var f := _pos(pr, mid + dir * car_len * 0.35)
	var b := _pos(pr, mid - dir * car_len * 0.35)
	if is_nan(f.x) or is_nan(b.x):
		return Transform3D()
	var fwd := (f - b)
	if fwd.length_squared() < 1e-6:
		return Transform3D()
	fwd = fwd.normalized()
	var x := Vector3.UP.cross(-fwd).normalized()
	var y := (-fwd).cross(x).normalized()
	return Transform3D(Basis(x, y, -fwd), (f + b) * 0.5)


## The rail top `s` m along portion `pr` (block frame); NAN off its samples or in a tunnel.
static func _pos(pr: Dictionary, s: float) -> Vector3:
	var ss: PackedFloat32Array = pr["s"]
	if s < ss[0] or s > ss[ss.size() - 1]:
		return Vector3(NAN, NAN, NAN)
	var k := clampi(ss.bsearch(s, true), 1, ss.size() - 1)
	if pr["hide"][k] or pr["hide"][k - 1]:
		return Vector3(NAN, NAN, NAN)
	var t := clampf((s - ss[k - 1]) / maxf(ss[k] - ss[k - 1], 0.001), 0.0, 1.0)
	return (pr["pos"][k - 1] as Vector3).lerp(pr["pos"][k], t)


## Whether crossing `gt`'s barriers are down at `t`: a train on any of its lines within CLOSE_M of it coming, on it, or
## not yet CLEAR_M past.
static func gate_closed(gt: Dictionary, all: Array, t: float, day: float) -> bool:
	var runs: Array = gt["runs"]
	for pr: Dictionary in all:
		var i := runs.find(int(pr["run"]))
		if i < 0:
			continue
		var at := float(gt["s"][i])
		var tt: Dictionary = pr["timetable"]
		var long := int(tt.get("cars", 0)) * float(tt.get("car_len", 20.0))
		for tr: Array in trains_on(tt, float(pr["len"]), t, day):
			var x := int(tr[1]) * (at - float(tr[0]))   # (how far the crossing is ahead of its front)
			if x < CLOSE_M and x > -long - CLEAR_M:
				return true
	return false


# ---------------------------------------------------------------------------- the stock's meshes

static func stock_key(stock: Dictionary, kind: String) -> String:
	return ("%s|%s|%s|%s|%s|%s|%s" % [kind, stock.get("nose", "unit"), stock.get("body", ""), stock.get("stripe", ""),
		stock.get("cab", ""), stock.get("car_len", 20), stock.get("roof", "")]).md5_text()


static func _col(stock: Dictionary, field: String, fallback: Color) -> Color:
	return Color.from_string(str(stock.get(field, "")), fallback)


## A car of stock `stock` (a kit row: nose "unit", "round", "loco", "freight" or "tram", colours body, stripe, cab,
## roof; car_len) for a line of kind `kind`: `part` "cab" (the leading end: a cab or a locomotive, facing -z) or "car".
## Its middle on the rails' top, -z forward.
static func stock_mesh(stock: Dictionary, kind: String, part: String) -> Mesh:
	var key := stock_key(stock, kind) + part
	if _stock_meshes.has(key):
		return _stock_meshes[key]
	var nose := str(stock.get("nose", "unit"))
	var body := _col(stock, "body", Color(0.85, 0.85, 0.82))
	var stripe := _col(stock, "stripe", Color(0.15, 0.3, 0.6))
	var cab_c := _col(stock, "cab", body)
	var roof := _col(stock, "roof", Color(0.35, 0.36, 0.38))
	var half_l := float(stock.get("car_len", 20.0)) * 0.5 - 0.45
	var small := kind in ["narrow_gauge", "funicular"]
	var w := 1.15 if small else 1.42
	var floor_y := 0.45 if nose == "tram" else (0.95 if not small else 0.7)
	var top := 3.5 if nose == "tram" else (3.85 if not small else 3.0)
	var geo := Geo.new()
	var freight := nose == "freight" or (nose == "loco" and part == "car" and str(stock.get("wagons", "")) == "freight")
	var colour := cab_c if part == "cab" and nose in ["loco", "freight"] else body
	if freight and part == "car":
		colour = body
		top = 3.6
	# The body, its roof and its underframe.
	geo.box("matte", Vector3(0.0, (floor_y + top) * 0.5, 0.0), Vector3(w, (top - floor_y) * 0.5, half_l), colour)
	geo.box("matte", Vector3(0.0, top + 0.12, 0.0), Vector3(w - 0.2, 0.12, half_l - 0.2), roof)
	geo.box("matte", Vector3(0.0, floor_y - 0.12, 0.0), Vector3(w - 0.25, 0.12, half_l - 0.4), Color(0.08, 0.08, 0.09))
	if nose != "tram":
		for z: float in [-1.0, 1.0]:
			geo.box("matte", Vector3(0.0, 0.5, z * (half_l - 2.6)), Vector3(1.0, 0.35, 1.3), Color(0.07, 0.07, 0.08))
	# Its stripe and windows down both sides (a freight wagon has neither; a locomotive only its cab's).
	var win_lo := floor_y + (1.0 if nose != "tram" else 0.8)
	var win_hi := top - 0.55
	for side: float in [-1.0, 1.0]:
		var x: float = side * (w + 0.012)
		if not (freight and part == "car"):
			geo.quad("matte", Vector3(x, win_lo - 0.45, -half_l), Vector3(x, win_lo - 0.45, half_l),
				Vector3(x, win_lo - 0.15, half_l), Vector3(x, win_lo - 0.15, -half_l), stripe)
		if part == "cab" and nose in ["loco", "freight"]:
			geo.quad("window", Vector3(x, win_lo, -half_l + 0.6), Vector3(x, win_lo, -half_l + 2.6),
				Vector3(x, win_hi, -half_l + 2.6), Vector3(x, win_hi, -half_l + 0.6), Color(0.1, 0.12, 0.14))
		elif not freight:
			var z := -half_l + 1.2
			while z + 1.4 < half_l - 0.8:
				geo.quad("window", Vector3(x, win_lo, z), Vector3(x, win_lo, z + 1.4), Vector3(x, win_hi, z + 1.4),
					Vector3(x, win_hi, z), Color(0.1, 0.12, 0.14))
				z += 2.0
	if part == "cab":
		# The cab's front: its windscreen, its lamps, and on a "round" nose a long tapered snout.
		var zf := -half_l - 0.012
		if nose == "round":
			var tip := -half_l - 4.5
			var mid_y := floor_y + 1.0
			for side: float in [-1.0, 1.0]:
				geo.quad("matte", Vector3(side * w, floor_y, -half_l), Vector3(side * w, top, -half_l),
					Vector3(side * 0.35, mid_y + 0.4, tip), Vector3(side * 0.6, floor_y, tip + 0.3), colour)
			geo.quad("matte", Vector3(-w, top, -half_l), Vector3(w, top, -half_l), Vector3(0.35, mid_y + 0.4, tip),
				Vector3(-0.35, mid_y + 0.4, tip), colour)
			geo.quad("window", Vector3(-w + 0.3, top - 0.1, -half_l - 0.4), Vector3(w - 0.3, top - 0.1, -half_l - 0.4),
				Vector3(0.7, top - 0.7, -half_l - 1.8), Vector3(-0.7, top - 0.7, -half_l - 1.8), Color(0.05, 0.06, 0.08))
		else:
			geo.quad("window", Vector3(-w + 0.2, win_lo + 0.2, zf), Vector3(w - 0.2, win_lo + 0.2, zf),
				Vector3(w - 0.2, win_hi, zf), Vector3(-w + 0.2, win_hi, zf), Color(0.05, 0.06, 0.08))
			geo.quad("matte", Vector3(-w, floor_y, zf), Vector3(w, floor_y, zf), Vector3(w, win_lo - 0.1, zf),
				Vector3(-w, win_lo - 0.1, zf), stripe if nose == "unit" else colour.darkened(0.1))
			if nose == "unit" or nose == "tram":
				geo.quad("matte", Vector3(-w, win_lo - 0.6, zf - 0.01), Vector3(w, win_lo - 0.6, zf - 0.01),
					Vector3(w, win_lo - 0.1, zf - 0.01), Vector3(-w, win_lo - 0.1, zf - 0.01), Color(0.95, 0.8, 0.1))
			for x: float in [-w + 0.4, w - 0.4]:
				geo.box("glow", Vector3(x, floor_y + 0.35, zf - 0.03), Vector3(0.14, 0.09, 0.03), Color(1.0, 0.95, 0.85))
	if kind in ["tram", "light_rail"]:
		# (the pantograph up to the wire)
		geo.box("steel", Vector3(0.0, top + 0.6, 0.0), Vector3(0.05, 0.5, 0.05), Color(0.2, 0.2, 0.2))
		geo.box("steel", Vector3(0.0, top + 1.1, 0.0), Vector3(0.7, 0.03, 0.08), Color(0.2, 0.2, 0.2))
	var m := geo.mesh()
	_stock_meshes[key] = m
	return m


## A barrier arm a metre long out along +x from its pivot, red and white (scaled to the road's width).
static func arm_mesh() -> Mesh:
	if _stock_meshes.has("arm"):
		return _stock_meshes["arm"]
	var geo := Geo.new()
	for k in 6:
		var x0 := k / 6.0
		var x1 := (k + 1) / 6.0
		geo.box("matte", Vector3((x0 + x1) * 0.5, 0.0, 0.0), Vector3((x1 - x0) * 0.5, 0.06, 0.04),
			Color(0.75, 0.08, 0.06) if k % 2 == 0 else Color(0.92, 0.92, 0.9))
	var m := geo.mesh()
	_stock_meshes["arm"] = m
	return m


## A crossing's lit red lamp.
static func lamp_mesh() -> Mesh:
	if _stock_meshes.has("lamp"):
		return _stock_meshes["lamp"]
	var geo := Geo.new()
	geo.box("lamp_red", Vector3.ZERO, Vector3(0.13, 0.13, 0.03), Color(1.0, 0.15, 0.08))
	var m := geo.mesh()
	_stock_meshes["lamp"] = m
	return m


## The crossing's bell: one ring of it, made once.
static func bell() -> AudioStreamWAV:
	if _stock_meshes.has("bell"):
		return _stock_meshes["bell"]
	var rate := 22050
	var n := int(rate * 0.42)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * 1320.0 * t) * exp(-t * 9.0) * 0.55 + sin(TAU * 2790.0 * t) * exp(-t * 14.0) * 0.25
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_stock_meshes["bell"] = w
	return w
