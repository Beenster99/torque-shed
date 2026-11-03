class_name RouteReady
extends RefCounted
## Tells you when the crew's road is planned (Simon: "when we are planning a route and it takes 10 minutes we often
## either make a bike or go for some jumps behind the shed: it would be great if all players got a notification for
## when the route is ready to ride on"). Every machine plans the crew's plan itself (AdventurePlans), so each one
## watches its own: when a plan it has seen being worked out for a while is done, a notice goes up on that player's
## screen wherever they are (a banner and a chime, see HUD.route_notice). A plan that was ready at once, or a quick one
## while you're stood at the planner, says nothing.

## A plan worked out in less than this (ms) is one you watched come: no notice.
const QUIET_MS := 15000
## How often the plan is looked at (s).
const EVERY := 0.5

## The plan being watched (its AdventurePlans.key), "" for none.
var watching := ""
## Whether that plan has been seen being worked out (and not told of yet), and since when (ms).
var pending_seen := false
var since := 0


## Looks at the crew's plan `plan` and where it has got to, `res` (AdventurePlans.result: {} while it's being worked
## out), at `now` (ms). Returns the notice to put up: {title, line, ok}, or {} for none.
func watch(plan: Dictionary, res: Dictionary, now: int) -> Dictionary:
	if plan.is_empty():
		watching = ""
		pending_seen = false
		return {}
	var k := AdventurePlans.key(plan)
	# (a plan that couldn't be made only for now, the map still being finished, is planned again: still on its way)
	var pending := res.is_empty() or bool(res.get("retry", false))
	if k != watching:
		watching = k
		pending_seen = pending
		since = now
		return {}
	if pending:
		if not pending_seen:
			pending_seen = true   # (planned afresh: the map was refreshed, say)
			since = now
		return {}
	if not pending_seen:
		return {}
	pending_seen = false
	var took := now - since
	if took < QUIET_MS:
		return {}
	return notice(plan, res)


## The notice for `plan`, planned with result `res`: {title, line, ok}.
static func notice(plan: Dictionary, res: Dictionary) -> Dictionary:
	var names: Array = plan.get("names", [])
	var to := str(names[-1]) if not names.is_empty() else ""
	if not bool(res.get("ok", false)):
		return {"title": "ROUTE COULDN'T BE PLANNED", "ok": false,
			"line": "%s Have another look on the route planner: {menu}, then Adventure ride." % str(res.get("error", ""))}
	var pack: RealPack = res.get("pack")
	var km := pack.max_km() if pack != null else 0.0
	var road := ("The road to %s is planned" % to) if to != "" else "The road is planned"
	if km > 0.0:
		road += ", %.1f km" % km
	var next := "Start the ride" if Shed.is_authority() else "Say you're in"
	if Shed.is_authority() and AdventureJourney.needs_crew():
		next = "Get the crew in and start the ride"
	return {"title": "ROUTE READY", "ok": true, "line": "%s. %s on the route planner: {menu}, then Adventure ride." % [road, next]}
