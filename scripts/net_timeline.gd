class_name NetTimeline
extends RefCounted
## Another player's snapshots on a timeline of their own clock, so their bike is drawn smoothly however the packets
## arrive (Simon, 30 Oct: "lag spikes ... enough to cause other players to teleport", and the judder riding close).
##
## Each snapshot carries the time its sender's game had simulated up to when it was taken (Net.send_state's `sent`:
## physics ticks over ticks a second), not the time it happened to arrive. A hitch on either machine bunches the
## packets up or holds them back, but their sender times are still evenly spaced, so the bike is still drawn along
## them evenly. Their clock is mapped onto ours by the quickest any packet has come lately (`offset`: the packet that
## waited least on the way), and the bike is drawn `delay` behind that: enough to cover how much later than the
## quickest the packets have been coming lately (the jitter). The delay and the mapping only ever ease (EASE), so the
## bike is never seen to jump back or lurch on.
##
## When the packets stop for a moment (a hitch at their end, a lost packet or two) the bike carries on along its
## last speed for up to EXTRAPOLATE seconds, then waits there; when they come again it's eased back onto them
## rather than jumping (see place).

## The least and most the bike is drawn behind (s).
const MIN_DELAY := 0.06
const MAX_DELAY := 0.4
## How much more than the jitter it's drawn behind (s): a packet's gap at 30 a second, and a little.
const MARGIN := 0.045
## How long the quickest packet is remembered for the clock mapping (s): long enough to ride out a hitch, short
## enough to follow a clock that runs a little slow or fast.
const WINDOW := 3.0
## How long it carries on along its last speed with no new snapshot (s).
const EXTRAPOLATE := 0.25
## How quickly the delay and the clock mapping ease (s a second: drawn at most this much faster or slower than real
## time), and how quickly a jump in where it's drawn is eased out (per s).
const EASE := 0.08
## How quickly the delay grows when packets come later than it allows for (s a second): quicker, as till it has
## grown the bike is carried on along its speed.
const EASE_UP := 0.2
const BLEND_RATE := 10.0
## A jump in where it's drawn bigger than this (m) is taken at once (a respawn, a jump along the road).
const SNAP := 6.0
## Snapshots kept.
const KEEP := 40

## [{t (their clock, s), s (the snapshot)}], oldest first.
var snaps: Array = []
## Our clock minus theirs for the quickest packet lately (s), and the samples it's the least of: [[our t, ours - theirs]].
var offset := INF
var _samples: Array = []
var _least := INF
## How far behind it's drawn now (s), and the jitter it's aiming to cover (how much later than the quickest the
## packets have come lately).
var delay := 0.1
var jitter := 0.0
## How many came out of order (older than the newest) and were put in their place, and how many repeated a time.
var reordered := 0
var _target := Vector3.INF   # where the timeline had the bike last frame (see place)
var _err := Vector3.ZERO      # a jump in where it's drawn, still being eased out


## Adds snapshot `state` taken at `sent` on their clock, arriving at `now` on ours.
func push(state, sent: float, now: float) -> void:
	_samples.append([now, now - sent])
	while now - float(_samples[0][0]) > WINDOW:
		_samples.pop_front()
	_least = INF
	for p in _samples:
		_least = minf(_least, float(p[1]))
	if _least < offset:
		offset = _least   # (a quicker packet than any lately: their clock's nearer than we thought)
	jitter = 0.0
	for p in _samples:
		jitter = maxf(jitter, float(p[1]) - _least)
	var at := snaps.size()
	while at > 0 and float(snaps[at - 1]["t"]) >= sent:
		at -= 1
	if at < snaps.size():
		if float(snaps[at]["t"]) == sent:
			return   # (the same moment again)
		reordered += 1
	snaps.insert(at, {"t": sent, "s": state})
	while snaps.size() > KEEP:
		snaps.pop_front()


## Eases the clock mapping and the delay towards what the packets lately need (call once a frame with its `delta`):
## a little at a time, so the bike is never seen to jump, only to run a little slow or fast for a moment.
func step(delta: float) -> void:
	if _least != INF and _least > offset:
		offset = minf(_least, offset + EASE * delta)   # (their clock running slow, or a hitch they lost time to)
	var want := clampf(jitter + MARGIN, MIN_DELAY, MAX_DELAY)
	delay = move_toward(delay, want, (EASE_UP if want > delay else EASE) * delta)


## The moment on their clock to draw at `now` on ours.
func render_time(now: float) -> float:
	return now - offset - delay


## Where to draw at `now`: {a, b (the snapshots either side), f (0..1 between them), ahead (s past the newest, carried
## on along its speed), held (s past what it carries on for)}, or {} with none yet.
func sample(now: float) -> Dictionary:
	if snaps.is_empty():
		return {}
	var rt := render_time(now)
	if rt <= float(snaps[0]["t"]):
		return {"a": snaps[0]["s"], "b": snaps[0]["s"], "f": 0.0, "ahead": 0.0, "held": 0.0}
	var last: Dictionary = snaps[-1]
	if rt >= float(last["t"]):
		var past := rt - float(last["t"])
		return {"a": last["s"], "b": last["s"], "f": 1.0, "ahead": minf(past, EXTRAPOLATE), "held": maxf(0.0, past - EXTRAPOLATE)}
	var i := snaps.size() - 2
	while i > 0 and float(snaps[i]["t"]) > rt:
		i -= 1
	var a: Dictionary = snaps[i]
	var b: Dictionary = snaps[i + 1]
	var span := float(b["t"]) - float(a["t"])
	return {"a": a["s"], "b": b["s"], "f": clampf((rt - float(a["t"])) / span, 0.0, 1.0) if span > 0.0 else 1.0, "ahead": 0.0, "held": 0.0}


## Seconds since their newest snapshot was taken, as drawn now (0 while it's between two).
func behind_newest(now: float) -> float:
	return 0.0 if snaps.is_empty() else maxf(0.0, render_time(now) - float(snaps[-1]["t"]))


## Moves every snapshot's position by -`d` (the world's origin moved), for snapshots whose position is at [0..2].
func shift(d: Vector3) -> void:
	if _target != Vector3.INF:
		_target -= d
	for snap in snaps:
		var st: PackedFloat32Array = snap["s"]
		st[0] -= d.x
		st[1] -= d.y
		st[2] -= d.z
		snap["s"] = st


## Where to draw a bike at `now` on our clock, `delta` after the last frame: {a, b (the snapshots either side), f,
## pos, rot}, or {} with none yet. A snapshot has the bike's position at [0..2], its rotation at [3..6] and its
## velocity at [7..9] (Bike.get_net_state). Past the newest it's carried on along its speed (up to EXTRAPOLATE), and a
## jump in where the timeline has it beyond its own movement (back onto the snapshots after carrying on, or drawn
## further behind after a late packet) is eased out rather than seen.
func place(now: float, delta: float) -> Dictionary:
	var at := sample(now)
	if at.is_empty():
		return at
	var sa: PackedFloat32Array = at["a"]
	var sb: PackedFloat32Array = at["b"]
	var f: float = at["f"]
	var vel := Vector3(sb[7], sb[8], sb[9])
	var pos := Vector3(sa[0], sa[1], sa[2]).lerp(Vector3(sb[0], sb[1], sb[2]), f) + vel * float(at["ahead"])
	if _target != Vector3.INF:
		var jump := pos - _target - vel * delta
		if jump.length() > SNAP:
			_err = Vector3.ZERO   # (a respawn, a jump along the road: taken at once)
		else:
			if jump.length() > 0.05:
				_err -= jump
			_err *= exp(-BLEND_RATE * delta)
	_target = pos
	at["pos"] = pos + _err
	at["rot"] = Quaternion(sa[3], sa[4], sa[5], sa[6]).slerp(Quaternion(sb[3], sb[4], sb[5], sb[6]), f)
	return at
