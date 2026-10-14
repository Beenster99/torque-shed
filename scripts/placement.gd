class_name Placement
extends RefCounted
## Snapping for equipment you carry about the shed (Settings.snap_placement, on by default; R or
## right mouse toggles it while carrying). It turns square to the walls in quarter turns, and when
## a side comes within SNAP_REACH of a wall (or another piece of equipment) it slides flush
## against it: two sides at once puts it tight in a corner.

const SNAP_REACH := 0.4    # a wall this close to a side pulls it flush
const GAP := 0.01          # left between it and the wall
const HEIGHTS := [0.25, 0.8]   # looks for walls this high off the floor


## A heading turned to the nearest quarter turn.
static func snap_yaw(yaw: float) -> float:
	return roundf(yaw / (PI * 0.5)) * PI * 0.5


## Snaps equipment `size` (width, height, depth) put down at `xf`: {xf: where it goes, walls: the
## normal of each wall it now sits against (none, one, or two for a corner)}. `exclude` is
## what not to snap to (the equipment itself and whoever carries it).
static func snap(space: PhysicsDirectSpaceState3D, xf: Transform3D, size: Vector3, exclude: Array[RID]) -> Dictionary:
	var b := Basis(Vector3.UP, snap_yaw(xf.basis.get_euler().y))
	var at := xf.origin
	var walls := []
	for axis in 2:
		var dir_axis: Vector3 = b.x if axis == 0 else b.z
		var half: float = size.x * 0.5 if axis == 0 else size.z * 0.5
		var best := INF
		var best_dir := Vector3.ZERO
		for dir in [dir_axis, -dir_axis]:
			for h in HEIGHTS:
				if h > size.y + 0.05:
					continue
				var from: Vector3 = at + Vector3.UP * h
				var q := PhysicsRayQueryParameters3D.create(from, from + dir * (half + SNAP_REACH), 1)
				q.exclude = exclude
				var hit := space.intersect_ray(q)
				if hit and absf((hit["normal"] as Vector3).y) < 0.5:
					var d := from.distance_to(hit["position"])
					if d < best:
						best = d
						best_dir = dir
		if best < INF:
			at += best_dir * (best - half - GAP)
			walls.append(-best_dir)
	return {"xf": Transform3D(b, at), "walls": walls}
