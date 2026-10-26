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


## The road of the whole tour of `region_id` (AdventurePlans.TOURS).
static func tour_pack(region_id: String) -> RealPack:
	return AdventurePlans.pack_for(AdventurePlans.tour(region_id))


## The route of the whole tour of `region_id`, its stops laid out by `seed`.
static func tour_route(region_id: String, seed := 1) -> AdventureRoute:
	var r := AdventureRoute.new()
	var p := tour_pack(region_id)
	r.plan_real(p, seed, p.max_km())
	return r
