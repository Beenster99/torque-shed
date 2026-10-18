class_name StateDiff
extends RefCounted
## What changed in the shed's state since it last went to the crew, so the host sends only that
## (see Shed._process). The whole shed is 100-200 KB once there are customers, staff and cafe
## visitors about, and it used to go to every player up to ten times a second whenever anything
## in it changed: close to a megabyte a second with two riding, more than a home connection
## sends, so the backlog grew until the game fell over.
##
## tree() keeps a hash of every value, split down through nested Dictionaries to MAX_DEPTH;
## diff() compares two trees and gives a patch holding only the values that changed (and the
## keys gone); apply() puts a patch onto the state it was made against, or any later one.

## How deep the hashes split Dictionaries: the shed (0), its sections (1), their entries (2),
## and each entry's fields (3) are compared one by one; anything deeper goes whole.
const MAX_DEPTH := 3
## Marks a patch, as against a plain Dictionary value sent whole.
const PATCH := "__patch__"


## The hashes of `v`: an int, or for a Dictionary split further {"h": int, "k": {key: tree}}.
static func tree(v, depth := 0):
	if v is Dictionary and depth < MAX_DEPTH and (v as Dictionary).size() > 1:
		var kids := {}
		var hs := PackedInt64Array()
		for k in v:
			var t = tree(v[k], depth + 1)
			kids[k] = t
			hs.append(hash(k))
			hs.append(int(t["h"]) if t is Dictionary else int(t))
		return {"h": hash(hs), "k": kids}
	return hash(v)


## [changed, patch]: what turns the state hashed as `before` into `v` (hashed as `now`).
static func diff(before, now, v) -> Array:
	var hb: int = int(before["h"]) if before is Dictionary else (int(before) if before != null else 0)
	var hn: int = int(now["h"]) if now is Dictionary else int(now)
	if before != null and hb == hn:
		return [false, null]
	if now is Dictionary and before is Dictionary:
		var set := {}
		var gone := []
		var kb: Dictionary = before["k"]
		var kn: Dictionary = now["k"]
		for k in kn:
			if not kb.has(k):
				set[k] = v[k]
			else:
				var r := diff(kb[k], kn[k], v[k])
				if r[0]:
					set[k] = r[1]
		for k in kb:
			if not kn.has(k):
				gone.append(k)
		return [true, {PATCH: true, "s": set, "d": gone}]
	return [true, v]


## `old` with `patch` put on it (changed in place when it's a Dictionary being patched).
static func apply(old, patch):
	if patch is Dictionary and (patch as Dictionary).has(PATCH):
		var base: Dictionary = old if old is Dictionary else {}
		var set: Dictionary = patch["s"]
		for k in set:
			base[k] = apply(base.get(k), set[k])
		for k in patch["d"]:
			base.erase(k)
		return base
	return patch
