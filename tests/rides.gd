extends RefCounted
## Planned rides for the tests: every adventure is along a road the crew planned on a real map, so the tests ride the
## bundled regions' tours (AdventurePlans.TOURS) too. Use it as `const Rides := preload("res://tests/rides.gd")`.


## The shortest tour at least `km` long (Shodoshima's first, then the Dales'; planned once a run, then kept).
static func plan(km := 20.0) -> Dictionary:
	return AdventurePlans.sample(km)


## The road of plan(km).
static func pack(km := 20.0) -> RealPack:
	return AdventurePlans.pack_for(plan(km))


## The whole length of plan(km) (km): a ride Adventure.start begins is all of it.
static func full(km := 20.0) -> float:
	return pack(km).max_km()


## The route of a ride of `km` along pack(km), its stops laid out by `seed`.
static func route(km := 20.0, seed := 1) -> AdventureRoute:
	var r := AdventureRoute.new()
	r.plan_real(pack(km), seed, km)
	return r


## A world for a ride of `km` along pack(km), its stops laid out by `seed` (not yet in the tree).
static func world(km := 20.0, seed := 1) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(pack(km), seed, km)
	return w


## Has the host start the whole of plan(km) for the crew, its stops laid out by `seed`.
static func start(km := 20.0, seed := 1) -> void:
	Adventure.start(plan(km), seed)


## The host takes the main road at every fork of the adventure on (so the road's built all the way: it isn't built past
## a fork still open), and waits till `trip`'s road has them all.
static func take_main_roads(trip: AdventureTrip) -> void:
	var r := trip.world.route
	for f in r.forks.size():
		if AdventureForks.pick_of(f) < 0:
			Shed.request({"a": "adventure_vote", "fork": f, "way": 0})
	var end := Time.get_ticks_msec() + 10000
	while r.decided.size() < r.forks.size() and Time.get_ticks_msec() < end:
		await trip.get_tree().process_frame


## The road of the whole tour of `region_id` (AdventurePlans.TOURS).
static func tour_pack(region_id: String) -> RealPack:
	return AdventurePlans.pack_for(AdventurePlans.tour(region_id))


## The route of the whole tour of `region_id`, its stops laid out by `seed`.
static func tour_route(region_id: String, seed := 1) -> AdventureRoute:
	var r := AdventureRoute.new()
	var p := tour_pack(region_id)
	r.plan_real(p, seed, p.max_km())
	return r
