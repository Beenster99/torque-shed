class_name PoolGame
extends RefCounted
## The pool table in the crew lounge, as a game: eight-ball for one (practice) or two. Walk up
## and press F to rack them up, join a mate's game, or take your shot (see PoolView for the
## table, the cue and the aiming).
##
## The game is host-authoritative shed state in Shed.pool: where the balls lie, who's playing,
## whose shot it is, who has which group. A shot goes to the host as
## Shed.request({"a": "pool_shot", "angle", "power"}); the host runs the whole shot through the
## simulation below, to the moment every ball stops, and keeps the result. The shot itself (the
## balls as they lay, the angle and the power) goes out with it, and every player's table plays
## it out by running the same simulation, then settles on the host's result. The simulation is
## a plain fixed-step 2D one, the same sums in the same order everywhere.
##
## Rules, kept simple: the table's open until someone pots a ball off the break; the group of
## the first ball they pot is theirs. Pot one of yours and you go again. A foul (the cue ball
## goes in, it hits nothing, or it hits the other group or the black first) gives the table to
## the other player, with the cue ball back on the spot if it went in. Clear your group, then
## pot the black to win; pot the black early, or foul on it, and you lose.

## Table space: metres from the middle of the felt, x across it and z along it, the head
## (where the cue ball starts) at +z and the foot (where the rack goes) at -z.
const R := 0.028                 # a ball's radius
const HX := 0.55                 # the cushions' faces
const HZ := 1.10
## The pockets: the four corners and the middle of each long side, and how near a ball's middle
## must come to one to drop.
const POCKETS: Array[Vector2] = [Vector2(-0.56, -1.11), Vector2(0.56, -1.11), Vector2(-0.575, 0.0), Vector2(0.575, 0.0),
	Vector2(-0.56, 1.11), Vector2(0.56, 1.11)]
const POCKET_R: Array[float] = [0.068, 0.068, 0.058, 0.058, 0.068, 0.068]
## Within this of a corner along a cushion, or of the middle of a long side, the cushion's cut
## away for the pocket's mouth: a ball there goes on into the pocket instead of bouncing.
const CORNER_MOUTH := 0.075
const SIDE_MOUTH := 0.05
const DT := 1.0 / 240.0
const DECEL := 0.18              # m/s^2 of rolling resistance
const DAMP := 0.2                 # and a little more the faster it goes (1/s)
const BALL_E := 0.95             # how much bounce there is between balls
const CUSHION_E := 0.75          # and off a cushion
const STOP := 0.006              # slower than this (m/s) and a ball has stopped
const MIN_SPEED := 0.25          # the cue ball's speed off the tip at no power and full power
const MAX_SPEED := 4.2
const MAX_TIME := 25.0           # a shot's over by this many seconds, whatever's still rolling
const HEAD := Vector2(0.0, 0.55)
const FOOT := Vector2(0.0, -0.55)
## The rack, apex first: the black in the middle, a solid and a stripe in the back corners.
const RACK := [[1], [9, 2], [10, 8, 3], [11, 4, 12, 5], [6, 13, 14, 7, 15]]
const MAX_PLAYERS := 2
## The table in the lounge (WorkshopUpgrades builds it there): the middle of its felt, in the shed.
const TABLE_AT := Vector3(1.6, GarageUpgrades.LOFT_FLOOR + 0.85, 65.0)

## The host's clock: no shot is taken until the last one has finished rolling.
static var _busy_until := 0


## No game on: no balls out, nobody playing.
##   balls    16 [x, z, on the table] in table space, the cue ball first, or [] before a rack
##   players  peer ids, the one who racked first; turn is an index into it
##   solids   the index of the player with the solids (1-7), the other has the stripes (9-15);
##            -1 while the table's open
##   shots    shots taken this game; last: the last shot {n, from (the balls before it), angle,
##            power, by, time (seconds it rolled)}, which every table plays out
##   game     racks so far (each rack's tiny nudges come from it); msg: what just happened
##   over     the game's done; winner: who won it (0 for none: lost a game of practice)
static func empty() -> Dictionary:
	return {"balls": [], "players": [], "turn": 0, "solids": -1, "shots": 0, "last": {}, "game": 0, "msg": "",
		"over": false, "winner": 0}


## Saved or synced pool made safe: anything missing gets its default, and balls that don't add
## up (or were mid-roll in a save) come off the table.
static func sanitize(s) -> Dictionary:
	var out := empty()
	if not (s is Dictionary):
		return out
	for key in out:
		if s.has(key) and typeof(s[key]) == typeof(out[key]):
			out[key] = s[key]
	var balls: Array = out["balls"]
	if balls.size() != 16 or not balls.all(func(b): return b is Array and (b as Array).size() == 3):
		out["balls"] = []
	return out


static func _st() -> Dictionary:
	return Shed.pool


## Whether a game's on: balls racked and nobody's won yet.
static func playing() -> bool:
	return not _st()["balls"].is_empty() and not bool(_st()["over"])


## Whose shot it is, or 0.
static func shooter() -> int:
	var players: Array = _st()["players"]
	if players.is_empty() or not playing():
		return 0
	return int(players[clampi(int(_st()["turn"]), 0, players.size() - 1)])


static func player_name(peer: int) -> String:
	return str(Shed.crew.get(peer, {}).get("name", "Someone"))


## "solids", "stripes" or "" (the table's open) for the player at `index`.
static func group_of_player(index: int) -> String:
	var solids := int(_st()["solids"])
	if solids < 0:
		return ""
	return "solids" if solids == index else "stripes"


## Ball `i`'s group: "cue", "solids", "eight" or "stripes".
static func group_of_ball(i: int) -> String:
	if i == 0:
		return "cue"
	if i == 8:
		return "eight"
	return "solids" if i < 8 else "stripes"


## How many of `group` are still on the table in `balls`.
static func left_of(balls: Array, group: String) -> int:
	var n := 0
	for i in balls.size():
		if group_of_ball(i) == group and bool(balls[i][2]):
			n += 1
	return n


## A fresh rack: the cue ball on the head spot and the triangle on the foot spot, each ball
## nudged a hair (by `game`, so the break isn't the same every time, but is on every table).
static func rack(game: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (game + 1)
	var balls := []
	balls.resize(16)
	balls[0] = [HEAD.x, HEAD.y, true]
	var gap := R * 2.0 + 0.0008
	for row in RACK.size():
		for k in (RACK[row] as Array).size():
			var x := (k - row * 0.5) * gap + rng.randf_range(-0.0004, 0.0004)
			var z := FOOT.y - row * gap * 0.866 + rng.randf_range(-0.0004, 0.0004)
			balls[int(RACK[row][k])] = [x, z, true]
	return balls


## Which way a shot at `angle` sends the cue ball, in table space: 0 is towards the foot (-z).
static func aim_dir(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


# ---------------------------------------------------------------------------- the simulation

## A shot under way from `balls`: {p, v (per ball), on, first (the first ball the cue ball hit,
## or -1), potted (balls in the order they went in), hits (ball-on-ball knocks), t}.
static func sim_from(balls: Array) -> Dictionary:
	var p := PackedVector2Array()
	var v := PackedVector2Array()
	var on := []
	for b in balls:
		p.append(Vector2(float(b[0]), float(b[1])))
		v.append(Vector2.ZERO)
		on.append(bool(b[2]))
	return {"p": p, "v": v, "on": on, "first": -1, "potted": [], "hits": 0, "rails": 0, "t": 0.0}


## The cue strikes the cue ball at `angle` with `power` (0..1).
static func strike(sim: Dictionary, angle: float, power: float) -> void:
	var v: PackedVector2Array = sim["v"]
	v[0] = aim_dir(angle) * lerpf(MIN_SPEED, MAX_SPEED, clampf(power, 0.0, 1.0))
	sim["v"] = v


## Whether anything's still rolling.
static func moving(sim: Dictionary) -> bool:
	var v: PackedVector2Array = sim["v"]
	for i in v.size():
		if v[i] != Vector2.ZERO:
			return true
	return false


## One fixed step of the shot: friction, ball on ball, cushions and pockets.
static func step(sim: Dictionary) -> void:
	var p: PackedVector2Array = sim["p"]
	var v: PackedVector2Array = sim["v"]
	var on: Array = sim["on"]
	var n := p.size()
	for i in n:
		if not on[i] or v[i] == Vector2.ZERO:
			continue
		var speed := v[i].length()
		var slower := speed - (DECEL + DAMP * speed) * DT
		if slower <= STOP:
			v[i] = Vector2.ZERO
			continue
		v[i] = v[i] * (slower / speed)
		p[i] = p[i] + v[i] * DT
	# Ball on ball: equal masses, so the knock is shared along the line between their middles.
	for i in n:
		if not on[i]:
			continue
		for j in range(i + 1, n):
			if not on[j]:
				continue
			var d := p[j] - p[i]
			var dist := d.length()
			if dist >= R * 2.0 or dist < 0.000001:
				continue
			var nrm := d / dist
			var push := (R * 2.0 - dist) * 0.5
			p[i] = p[i] - nrm * push
			p[j] = p[j] + nrm * push
			var closing := (v[i] - v[j]).dot(nrm)
			if closing <= 0.0:
				continue
			var j_imp := closing * (1.0 + BALL_E) * 0.5
			v[i] = v[i] - nrm * j_imp
			v[j] = v[j] + nrm * j_imp
			sim["hits"] = int(sim["hits"]) + 1
			if i == 0 and int(sim["first"]) < 0:
				sim["first"] = j
	# Cushions, cut away at the pockets' mouths; and the pockets.
	var potted: Array = sim["potted"]
	for i in n:
		if not on[i]:
			continue
		var q := p[i]
		var u := v[i]
		var side_mouth := absf(q.y) < SIDE_MOUTH
		var corner_x := absf(q.y) > HZ - CORNER_MOUTH
		var corner_z := absf(q.x) > HX - CORNER_MOUTH
		if absf(q.x) > HX - R and not side_mouth and not corner_x and u.x * q.x > 0.0:
			q.x = signf(q.x) * (HX - R) * 2.0 - q.x
			u.x = -u.x * CUSHION_E
			u.y *= 0.95
			sim["rails"] = int(sim["rails"]) + 1
		if absf(q.y) > HZ - R and not corner_z and u.y * q.y > 0.0:
			q.y = signf(q.y) * (HZ - R) * 2.0 - q.y
			u.y = -u.y * CUSHION_E
			u.x *= 0.95
			sim["rails"] = int(sim["rails"]) + 1
		p[i] = q
		v[i] = u
		var drop := absf(q.x) > HX + R * 0.5 or absf(q.y) > HZ + R * 0.5
		for k in POCKETS.size():
			if q.distance_to(POCKETS[k]) < POCKET_R[k]:
				drop = true
		if drop:
			on[i] = false
			v[i] = Vector2.ZERO
			potted.append(i)
	sim["p"] = p
	sim["v"] = v
	sim["t"] = float(sim["t"]) + DT


## The balls as they lie in `sim`, the way Shed.pool keeps them.
static func balls_of(sim: Dictionary) -> Array:
	var out := []
	var p: PackedVector2Array = sim["p"]
	for i in p.size():
		out.append([p[i].x, p[i].y, bool(sim["on"][i])] if sim["on"][i] else [0.0, 0.0, false])
	return out


## The whole shot from `balls`, played out until every ball stops (or MAX_TIME).
static func simulate(balls: Array, angle: float, power: float) -> Dictionary:
	var sim := sim_from(balls)
	strike(sim, angle, power)
	while moving(sim) and float(sim["t"]) < MAX_TIME:
		step(sim)
	return sim


## The cue ball's spot after it's gone in: the head spot, or along from it until it's clear.
static func respot(balls: Array) -> Vector2:
	var at := HEAD
	for tries in 40:
		var clear := true
		for i in range(1, balls.size()):
			if bool(balls[i][2]) and Vector2(float(balls[i][0]), float(balls[i][1])).distance_to(at) < R * 2.2:
				clear = false
		if clear:
			return at
		at = HEAD + Vector2(0.0, (tries / 2 + 1) * R * 2.2 * (1.0 if tries % 2 == 0 else -1.0))
	return at


# ---------------------------------------------------------------------------- requests

## Why `peer` can't do a "pool_*" action now, or "".
static func check(peer: int, action: Dictionary) -> String:
	if not GarageUpgrades.owned("lounge"):
		return "There's no pool table: the crew lounge comes with one."
	var st := _st()
	var players: Array = st["players"]
	match str(action.get("a", "")):
		"pool_rack":
			if Time.get_ticks_msec() < _busy_until:
				return "Wait for the balls to stop."
			if playing() and not players.has(peer) and players.any(func(p): return Shed.crew.has(int(p))):
				return "There's a game on: %s." % " and ".join(players.map(func(p): return player_name(int(p))))
		"pool_join":
			if not playing():
				return "No game on: rack them up first."
			if players.has(peer):
				return "You're already playing."
			if players.size() >= MAX_PLAYERS:
				return "%s are playing. Wait for the game to finish." % " and ".join(players.map(func(p): return player_name(int(p))))
		"pool_leave":
			if not players.has(peer):
				return "You're not playing."
		"pool_shot":
			if not playing():
				return "No game on: rack them up first."
			if shooter() != peer:
				return "It's %s's shot." % player_name(shooter()) if shooter() != 0 else "It's not your shot."
			if Time.get_ticks_msec() < _busy_until:
				return "Wait for the balls to stop."
			var angle = action.get("angle", 0.0)
			var power = action.get("power", 0.0)
			if not (angle is float or angle is int) or not (power is float or power is int) or is_nan(float(angle)) \
					or is_inf(float(angle)) or is_nan(float(power)):
				return "That's not a shot."
		_:
			return "Unknown pool action."
	return ""


## Does a checked "pool_*" action. Returns what to tell the player, or "".
static func apply(peer: int, action: Dictionary) -> String:
	var st := _st()
	var players: Array = st["players"]
	match str(action.get("a", "")):
		"pool_rack":
			st["game"] = int(st["game"]) + 1
			st["balls"] = rack(int(st["game"]))
			st["players"] = [peer]
			st["turn"] = 0
			st["solids"] = -1
			st["shots"] = 0
			st["last"] = {}
			st["over"] = false
			st["winner"] = 0
			st["msg"] = "%s racked them up. %s to break." % [player_name(peer), player_name(peer)]
			return "Racked up. Walk up to the table and press {interact} to break; a mate can press {interact} to join."
		"pool_join":
			players.append(peer)
			st["msg"] = "%s joined the game." % player_name(peer)
			return "You're in. Wait for your shot."
		"pool_leave":
			var at := players.find(peer)
			players.remove_at(at)
			if int(st["turn"]) >= at and int(st["turn"]) > 0:
				st["turn"] = int(st["turn"]) - 1
			if int(st["solids"]) >= 0 and players.size() <= 1:
				# Whoever's left keeps their own group.
				var kept := group_of_player(0 if at == 1 else 1)
				st["solids"] = -1 if players.is_empty() else (0 if kept == "solids" else 1)
			st["turn"] = clampi(int(st["turn"]), 0, maxi(0, players.size() - 1))
			st["msg"] = "%s left the game." % player_name(peer)
			if players.is_empty():
				st["over"] = true
			return "You left the game."
		"pool_shot":
			return _shoot(peer, clampf(float(action["angle"]), -TAU * 4.0, TAU * 4.0), clampf(float(action["power"]), 0.0, 1.0))
	return ""


## The host plays a shot out and works out what it means.
static func _shoot(peer: int, angle: float, power: float) -> String:
	var st := _st()
	var players: Array = st["players"]
	var turn := int(st["turn"])
	var before: Array = st["balls"].duplicate(true)
	var sim := simulate(before, angle, power)
	var after := balls_of(sim)
	var potted: Array = sim["potted"]
	var first := int(sim["first"])
	var breaking := int(st["shots"]) == 0
	var mine := group_of_player(turn)
	var on_black := mine != "" and left_of(before, mine) == 0
	var name := player_name(peer)
	# Fouls.
	var foul := ""
	if potted.has(0):
		foul = "the cue ball went in"
	elif first < 0:
		foul = "the cue ball didn't hit anything"
	elif not breaking:
		var hit := group_of_ball(first)
		if mine == "" and hit == "eight":
			foul = "the black was hit first"
		elif mine != "" and hit != (("eight" if on_black else mine)):
			foul = "the %s was hit first" % ("black" if hit == "eight" else "wrong group (%s)" % hit)
	# The black.
	if potted.has(8) and not breaking:
		var won := on_black and foul == ""
		st["over"] = true
		st["winner"] = peer if won else (int(players[(turn + 1) % players.size()]) if players.size() > 1 else 0)
		if won:
			st["msg"] = "%s potted the black and won!" % name
		elif players.size() > 1:
			st["msg"] = "%s potted the black %s: %s wins." % [name, "too early" if not on_black else "on a foul", player_name(int(st["winner"]))]
		else:
			st["msg"] = "The black went in %s: game over. Press {interact} to rack again." % ("too early" if not on_black else "on a foul")
		_finish(st, sim, after, before, angle, power, peer)
		return str(st["msg"])
	if potted.has(8) and breaking:
		# The black on the break comes back to the foot spot.
		after[8] = [FOOT.x, FOOT.y, true]
	# Groups: the first ball potted after the break (on a fair shot) settles them.
	var object_potted := potted.filter(func(i): return int(i) != 0 and int(i) != 8)
	if mine == "" and not breaking and foul == "" and not object_potted.is_empty():
		mine = group_of_ball(int(object_potted[0]))
		st["solids"] = turn if mine == "solids" else 1 - turn
	var again := false
	if foul == "":
		for i in object_potted:
			if mine == "" or group_of_ball(int(i)) == mine:
				again = true
	if foul != "" and potted.has(0):
		var spot := respot(after)
		after[0] = [spot.x, spot.y, true]
	var said := []
	if not object_potted.is_empty():
		said.append("%s potted %s" % [name, ", ".join(object_potted.map(func(i): return str(i)))])
	if foul != "":
		said.append("Foul: %s" % foul)
	if not again and players.size() > 1:
		st["turn"] = (turn + 1) % players.size()
	if again and mine != "" and left_of(after, mine) == 0:
		said.append("%s is on the black" % name)
	if players.size() > 1:
		said.append("%s's shot" % player_name(int(players[int(st["turn"])])))
	elif said.is_empty():
		said.append("Nothing went in")
	st["msg"] = ". ".join(said) + "."
	_finish(st, sim, after, before, angle, power, peer)
	return ""


static func _finish(st: Dictionary, sim: Dictionary, after: Array, before: Array, angle: float, power: float, peer: int) -> void:
	st["balls"] = after
	st["last"] = {"n": int(st["shots"]), "from": before, "angle": angle, "power": power, "by": peer, "time": float(sim["t"])}
	st["shots"] = int(st["shots"]) + 1
	_busy_until = Time.get_ticks_msec() + int(float(sim["t"]) * 1000.0) + 300


## Host, every frame: players who've left the session leave the game.
static func process(_delta: float) -> void:
	var players: Array = _st().get("players", [])
	for p in players:
		if not Shed.crew.has(int(p)):
			apply(int(p), {"a": "pool_leave"})
			Shed._mark_dirty()
			Shed.changed.emit()
			return
