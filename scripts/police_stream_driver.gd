class_name PoliceStreamDriver
extends PoliceDriver
## The police cars driven as part of the adventure's traffic (AdventureTraffic's TrafficStream)
## instead of on their own: each is a "police" vehicle spawned into the stream and taken over
## (TrafficStream.take), so the stream draws it, the crew get it with the rest of the traffic,
## the other traffic queues behind it in its lane, and the police's chase can see the traffic to
## get round. The driving itself is PoliceDriver's (the same speeds, bends and lanes); each tick
## the car's s, v, dir, lat (metres right of the centre line) and aux (lights and siren, see
## AUX_*) are written into its stream entry. Gone off the police (remove) it's taken off the road.
##
## On the crew's machines the stream brings the cars; the police's own updates (AdventurePolice
## pack) say which stream vehicle each car is (attach).

## aux bits: blue lights going, siren on.
const AUX_LIGHTS := 1
const AUX_SIREN := 2

var stream: TrafficStream
## Police car id -> its stream vehicle's id.
var sid := {}


func add(id: int, s: float, dir: int, v: float, lane := NAN) -> void:
	if cars.has(id) or not host or stream == null:
		return
	var at := lane if not is_nan(lane) else own_lane(s)
	var k := stream.spawn_at("police", s, dir, v, {"lat": -dir * at})
	if k < 0:
		return   # the road's full just now (or past its ends)
	var entry := stream.take(k)
	sid[id] = k
	cars[id] = {"s": s, "dir": dir, "v": v, "lane": at, "want": v, "accel": 2.0, "brake": 3.0, "lane_want": at,
		"bend": INF, "bend_t": 0.0, "body": entry["body"], "last_v": v, "slowing": 0.0, "aux": 0}


## Client: police car `id` is stream vehicle `stream_id` (once the stream has it).
func attach(id: int, stream_id: int) -> void:
	sid[id] = stream_id
	if not cars.has(id):
		cars[id] = {"s": 0.0, "dir": 1, "v": 0.0, "lane": 0.0, "lane_want": 0.0, "aux": 0}


func remove(id: int) -> void:
	if sid.has(id) and stream and host:
		stream.remove_id(int(sid[id]))
	sid.erase(id)
	cars.erase(id)


func has(id: int) -> bool:
	return cars.has(id)


func stream_id(id: int) -> int:
	return int(sid.get(id, -1))


func state(id: int) -> Dictionary:
	if not cars.has(id):
		return {}
	if host:
		return super(id)
	var sl := stream.slot(int(sid.get(id, -1))) if stream else {}
	if sl.is_empty():
		return {}
	return {"s": float(sl["s"]), "dir": int(sl["dir"]), "v": float(sl["v"]), "lane": -float(sl["lat"]) * int(sl["dir"])}


func body(id: int) -> TrafficVehicle:
	if stream == null or not sid.has(id):
		return null
	var d := stream.find(int(sid[id]))
	return d.get("body") if not d.is_empty() else null


func set_aux(id: int, aux: int) -> void:
	if cars.has(id):
		cars[id]["aux"] = aux


## The rest of the traffic (not the police).
func traffic() -> Array:
	var out := []
	if stream == null:
		return out
	var ours := sid.values()
	for d in stream.vehicles:
		if not ours.has(int(d["seed"])):
			out.append({"s": float(d["s"]), "dir": int(d["dir"]), "v": float(d["v"]),
				"half": TrafficVehicle.half_length_of(str(d["kind"]))})
	return out


## Host: drives each car on and writes it into its stream entry (the stream draws it). A car
## the stream has lost (the road cleared) is dropped.
func step(delta: float) -> void:
	if not host or stream == null:
		return
	for id in cars.keys():
		var c: Dictionary = cars[id]
		var d := stream.find(int(sid.get(id, -1)))
		if d.is_empty():
			sid.erase(id)
			cars.erase(id)
			continue
		if not d.get("scripted", false):
			stream.take(int(sid[id]))
		_drive(c, delta)
		d["s"] = float(c["s"])
		d["v"] = float(c["v"])
		d["dir"] = int(c["dir"])
		d["lat"] = -int(c["dir"]) * float(c["lane"])
		d["aux"] = int(c.get("aux", 0))
		c["body"] = d["body"]
