extends RefCounted
## Other riders drawn smoothly however their snapshots arrive (Simon, 30 Oct: "lag spikes ... enough to cause AI
## traffic & other players to teleport", "lack of smoothness when riding close to other players"). Run from
## tests/run_tests.gd (its _test_net_timeline_* functions hand over to these). A rider going steadily along at
## SPEED sends 30 snapshots a second; they arrive late, bunched, out of order or not at all, and the bike as
## NetTimeline places it each frame (144 a second, with hitches of our own) must glide: never back, never a jump.

var t: Node   # the test runner: check(), get_tree()

const SPEED := 25.0
const SEND := 1.0 / 30.0
const FRAME := 1.0 / 144.0


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A snapshot of a bike at `x` along the x axis going SPEED.
static func snap(x: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(28)
	s[0] = x
	s[6] = 1.0   # (its rotation: none)
	s[7] = SPEED
	return s


## Rides `seconds` of a steady rider whose packet k (sent at k x SEND on their clock) arrives at arrive.call(k) on
## ours (or never, for a negative), drawn at the frames `frames` gives (our clock, s). Returns how it was drawn:
## the most it moved back in a frame, the biggest jump beyond its speed in a frame, how far it ended from where the
## rider was (less the delay), and the delay it ended on.
func ride(seconds: float, arrive: Callable, frames: Array) -> Dictionary:
	var tl := NetTimeline.new()
	var arrivals := []
	for k in int(seconds / SEND):
		var at: float = arrive.call(k)
		if at >= 0.0:
			arrivals.append([at, k])
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var next := 0
	var last_x := NAN
	var last_now := 0.0
	var back := 0.0
	var jump := 0.0
	for now: float in frames:
		while next < arrivals.size() and float(arrivals[next][0]) <= now:
			var k: int = arrivals[next][1]
			tl.push(snap(SPEED * k * SEND), k * SEND, float(arrivals[next][0]))
			next += 1
		if tl.snaps.is_empty():
			continue
		var dt := now - last_now
		tl.step(dt)
		var x: float = (tl.place(now, dt)["pos"] as Vector3).x
		if not is_nan(last_x):
			back = maxf(back, last_x - x)
			jump = maxf(jump, absf((x - last_x) - SPEED * dt))
		last_x = x
		last_now = now
	var lag := (frames[-1] as float) - 0.05 - tl.delay   # (where the rider was a delay ago, at the base latency)
	return {"back": back, "jump": jump, "off": absf(last_x - SPEED * lag), "delay": tl.delay, "reordered": tl.reordered}


## Our frames: FRAME apart from `from` to `to`, with a hitch of `hitch` s at `at` (nothing drawn meanwhile).
static func frames(to: float, at := -1.0, hitch := 0.0) -> Array:
	var out := []
	var now := 0.0
	while now < to:
		out.append(now)
		now += FRAME
		if at >= 0.0 and now >= at and now - FRAME < at:
			now += hitch
	return out


## Bunched: their game hitches for 300 ms (nothing sent, then the snapshots of its catch-up all at once), ours for
## 200 ms, and the packets jitter by up to 30 ms on the way. The bike glides on through both.
func test_bunched() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var jitter := []
	for k in 400:
		jitter.append(rng.randf() * 0.03)
	var arrive := func(k: int) -> float:
		var sent := k * SEND
		if sent > 4.0 and sent < 4.3:
			return 4.3 + 0.05   # (their hitch: sent together once it's over)
		return sent + 0.05 + float(jitter[k])
	var got := ride(10.0, arrive, frames(10.0, 7.0, 0.2))
	print("    NET TIMELINE bunched: %s" % JSON.stringify(got))
	check(float(got["back"]) < 0.001, "a bike never drawn going backwards through the hitches (%.3f m)" % got["back"])
	# A frame's own movement is 25 m/s x 7 ms; after our 200 ms hitch the first frame covers that too.
	check(float(got["jump"]) < 1.5, "nor jumping on (the most beyond its speed in a frame %.2f m)" % got["jump"])
	check(float(got["off"]) < 1.0 and float(got["delay"]) < NetTimeline.MAX_DELAY + 0.001,
		"and drawn where the rider was a moment ago (%.2f m off, %.0f ms behind)" % [got["off"], float(got["delay"]) * 1000.0])


## Late and lost: a packet now and then overtaken by the next (out of order), and a run of eight lost. It's carried on
## along its speed over the gap and eased back onto the snapshots when they come again, without a jump.
func test_late() -> void:
	var arrive := func(k: int) -> float:
		if k >= 120 and k < 128:
			return -1.0   # (lost)
		if k % 17 == 0:
			return k * SEND + 0.05 + 0.06   # (late: after the next)
		return k * SEND + 0.05
	var got := ride(8.0, arrive, frames(8.0))
	print("    NET TIMELINE late: %s" % JSON.stringify(got))
	check(int(got["reordered"]) > 0, "a snapshot arriving after a newer one is put in its place (%d)" % got["reordered"])
	check(float(got["back"]) < 0.001 and float(got["jump"]) < 0.3,
		"the bike glides over lost and late packets (back %.3f m, the most beyond its speed in a frame %.2f m)" % [got["back"], got["jump"]])
	# The old way (each snapshot stamped with when it arrived, 100 ms behind): the same packets jumped it about.
	var old := _arrival_stamped(arrive, 8.0)
	print("    NET TIMELINE late, stamped on arrival as before: back %.2f m, jump %.2f m" % [old["back"], old["jump"]])
	check(float(old["jump"]) > float(got["jump"]) * 3.0, "where stamping them on arrival jumped it %.2f m" % old["jump"])


## How the bike was drawn before NetTimeline: each snapshot stamped with when it arrived, drawn 0.1 s behind, held
## on the newest when they run out.
func _arrival_stamped(arrive: Callable, seconds: float) -> Dictionary:
	var arrivals := []
	for k in int(seconds / SEND):
		var at: float = arrive.call(k)
		if at >= 0.0:
			arrivals.append([at, k])
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var snaps := []
	var next := 0
	var last_x := NAN
	var last_now := 0.0
	var back := 0.0
	var jump := 0.0
	for now: float in frames(seconds):
		while next < arrivals.size() and float(arrivals[next][0]) <= now:
			snaps.append([float(arrivals[next][0]), SPEED * int(arrivals[next][1]) * SEND])
			next += 1
		if snaps.is_empty():
			continue
		var rt := now - 0.1
		var a: Array = snaps[0]
		var b: Array = snaps[-1]
		for i in snaps.size() - 1:
			if float(snaps[i][0]) <= rt and float(snaps[i + 1][0]) >= rt:
				a = snaps[i]
				b = snaps[i + 1]
				break
		var span := float(b[0]) - float(a[0])
		var f := 1.0 if span <= 0.0 else clampf((rt - float(a[0])) / span, 0.0, 1.0)
		var x := lerpf(float(a[1]), float(b[1]), f)
		if not is_nan(last_x):
			back = maxf(back, last_x - x)
			jump = maxf(jump, absf((x - last_x) - SPEED * (now - last_now)))
		last_x = x
		last_now = now
	return {"back": back, "jump": jump}
