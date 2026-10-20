class_name DiaryShare
extends Node
## The crew's photos shared into everyone's Adventure Diary (Simon: "pictures i take don't get
## added to friends diary - all of our photos should be captured into the shared diary"). Every
## photo (and flipbook clip) any rider takes on an adventure goes to every other machine, through
## the host as everything else does: a rider's to the host, the host's (and each one it gets) on
## to everyone else. Each machine keeps it in its own copy of the diary, credited to who took it
## ("by", set by the host from the crew, not taken on trust). The films (MovieClip) stay on the
## machine that took them: a few megabytes each.
##
## What's sent is a smaller JPEG than the one kept (PhotoCapture makes it on its worker: at most
## SHARE_W wide), in CHUNK-byte pieces on an ENet channel of its own, at most RATE bytes a second,
## so the ride's own messages are never held up behind a photo. A rider joining (or coming back)
## part-way through an adventure is sent every photo of it the host has. Its node is the Shed
## autoload's child (/root/Shed/DiaryShare, the same on every game, for its RPCs).

const CHUNK := 16000
## The biggest photo taken in (bytes).
const MAX_PHOTO := 400000
## Bytes a second sent at most (to each machine and all told).
const RATE := 160000
## Photos part-way through arriving at once, from everyone.
const MAX_INCOMING := 24
## The shared photo's largest size, and its JPEG quality.
const SHARE_W := 800
const SHARE_H := 450
const SHARE_QUALITY := 0.75
## A photo's record: the fields sent with it.
const FIELDS := ["kind", "caption", "key", "who", "s", "hours", "day", "in_shot", "clip", "frames", "cols", "rows", "cell_w",
	"cell_h", "got", "w", "h", "at", "uid"]

## Photos that came in for a diary this machine hasn't begun yet (joining part-way): diary id ->
## [records], picked up by AdventurePhotos.begin.
static var pending := {}

## Photos received and kept here, and sent from here (the tests watch them).
var received := 0
var sent := 0
var _out: Array = []           # [{to, meta, data, i, n}] waiting to go, in order
var _in := {}                  # "from|uid" -> {n, parts: {i: bytes}} while one arrives
var _sent_to := {}             # host: peer -> {uid: true}, what each player has been sent
var _cache := {}               # host: uid -> the shared bytes, for players joining later
var _cache_diary := ""
var _budget := 0.0


func _ready() -> void:
	name = "DiaryShare"
	Net.player_joined.connect(_on_joined)
	Net.player_left.connect(_on_left)


## A photo just taken here (`rec` as the diary keeps it, `data` the JPEG to send) shared with the
## crew. Nothing happens playing alone.
func share(diary: String, rec: Dictionary, data: PackedByteArray) -> void:
	if not Net.is_online() or diary == "" or data.is_empty() or data.size() > MAX_PHOTO or str(rec.get("uid", "")) == "":
		return
	var meta := {"diary": diary, "rec": clean(rec)}
	meta["rec"]["by"] = str(rec.get("by", "")).left(24)
	if Shed.is_authority():
		_keep_cache(diary, str(rec["uid"]), data)
		for p in multiplayer.get_peers():
			_queue(p, meta, data)
	else:
		_queue(1, meta, data)


## Whether anything's still waiting to go.
func sending() -> bool:
	return not _out.is_empty()


## A record with only the fields that travel, each the right type and size.
static func clean(rec: Dictionary) -> Dictionary:
	var out := {}
	for k in FIELDS:
		if not rec.has(k):
			continue
		var v = rec[k]
		match k:
			"who", "in_shot":
				out[k] = (v as Array).slice(0, 8).map(func(x): return str(x).left(24)) if v is Array else []
			"caption":
				out[k] = str(v).left(120)
			"kind", "key":
				out[k] = str(v).left(48)
			"uid":
				out[k] = safe_uid(str(v))
			"clip":
				out[k] = bool(v)
			"s", "hours":
				out[k] = float(v)
			_:
				out[k] = int(v)
	return out


## A photo's id as a file name's safe part ("" for none).
static func safe_uid(uid: String) -> String:
	var out := ""
	for c in uid.left(40):
		if (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c == "-":
			out += c
	return out


## The records that came in for diary `id` before it was begun here (and forgets them).
static func take_pending(id: String) -> Array:
	var out: Array = pending.get(id, [])
	pending.erase(id)
	return out


# ---------------------------------------------------------------------------- sending

func _queue(to: int, meta: Dictionary, data: PackedByteArray) -> void:
	var uid := str(meta["rec"].get("uid", ""))
	if Shed.is_authority():
		if not _sent_to.has(to):
			_sent_to[to] = {}
		if _sent_to[to].has(uid):
			return
		_sent_to[to][uid] = true
	_out.append({"to": to, "meta": meta, "data": data, "i": 0, "n": maxi(1, ceili(data.size() / float(CHUNK)))})


func _process(delta: float) -> void:
	if _out.is_empty():
		_budget = 0.0
		return
	if not Net.is_online():
		_out.clear()
		return
	_budget = minf(_budget + RATE * delta, RATE * 0.25)
	var peers := multiplayer.get_peers()
	while not _out.is_empty() and _budget > 0.0:
		var o: Dictionary = _out[0]
		if not peers.has(int(o["to"])):
			_out.pop_front()
			continue
		var i := int(o["i"])
		var piece := (o["data"] as PackedByteArray).slice(i * CHUNK, (i + 1) * CHUNK)
		_chunk.rpc_id(int(o["to"]), o["meta"], i, int(o["n"]), piece)
		_budget -= piece.size()
		o["i"] = i + 1
		if i + 1 >= int(o["n"]):
			_out.pop_front()
			sent += 1


func _keep_cache(diary: String, uid: String, data: PackedByteArray) -> void:
	if diary != _cache_diary:
		_cache = {}
		_cache_diary = diary
	_cache[uid] = data


## Host: a player's joined (or come back) part-way through an adventure: every photo of it so far.
func _on_joined(id: int, _info: Dictionary) -> void:
	if not Shed.is_authority() or not Adventure.active():
		return
	var diary := str(Shed.adventure.get("diary", ""))
	if diary == "":
		return
	for rec in _photos_of(diary):
		var uid := str(rec.get("uid", ""))
		if uid == "" or bool(rec.get("movie", false)):
			continue
		var data: PackedByteArray = _cache.get(uid, PackedByteArray()) if _cache_diary == diary else PackedByteArray()
		if data.is_empty():
			data = FileAccess.get_file_as_bytes(AdventureDiary.folder(diary).path_join(str(rec.get("file", "")).get_file()))
		if data.is_empty() or data.size() > MAX_PHOTO:
			continue
		var r := clean(rec)
		r["by"] = str(rec.get("by", ""))
		_queue(id, {"diary": diary, "rec": r}, data)


func _on_left(id: int) -> void:
	_sent_to.erase(id)
	_out = _out.filter(func(o): return int(o["to"]) != id)
	for k in _in.keys():
		if str(k).begins_with("%d|" % id):
			_in.erase(k)


# ---------------------------------------------------------------------------- receiving

@rpc("any_peer", "call_remote", "reliable", 3)
func _chunk(meta: Dictionary, i: int, n: int, data: PackedByteArray) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not Shed.is_authority() and from != 1:
		return
	if n <= 0 or i < 0 or i >= n or data.size() > CHUNK or (n - 1) * CHUNK >= MAX_PHOTO or not (meta.get("rec") is Dictionary):
		return
	var uid := safe_uid(str((meta["rec"] as Dictionary).get("uid", "")))
	if uid == "":
		return
	var key := "%d|%s" % [from, uid]
	var inc: Dictionary = _in.get(key, {})
	if inc.is_empty() or int(inc["n"]) != n:
		if _in.size() >= MAX_INCOMING:
			_in.erase(_in.keys()[0])
		inc = {"n": n, "parts": {}}
		_in[key] = inc
	inc["parts"][i] = data
	if inc["parts"].size() < n:
		return
	var all := PackedByteArray()
	for k in n:
		all.append_array(inc["parts"][k])
	_in.erase(key)
	_arrived(from, meta, all)


## A whole photo's arrived from `from`: kept here, and from the host sent on to everyone else.
func _arrived(from: int, meta: Dictionary, data: PackedByteArray) -> void:
	if data.size() > MAX_PHOTO or data.size() < 4 or data[0] != 0xFF or data[1] != 0xD8:
		return   # not a JPEG
	var diary := str(meta.get("diary", "")).validate_filename()
	var rec := clean(meta["rec"])
	if Shed.is_authority():
		if diary != str(Shed.adventure.get("diary", "")) or not Adventure.active():
			return   # only the adventure on now's
		rec["by"] = str(Shed.crew.get(from, {}).get("name", "Someone")).left(24)
	else:
		rec["by"] = str((meta["rec"] as Dictionary).get("by", "Someone")).left(24)
	if diary == "" or not keep(diary, rec, data):
		return
	if Shed.is_authority():
		_keep_cache(diary, str(rec["uid"]), data)
		var on := {"diary": diary, "rec": rec}
		for p in multiplayer.get_peers():
			if p != from:
				_queue(p, on, data)
		if _sent_to.has(from):
			_sent_to[from][str(rec["uid"])] = true


## Keeps a crew mate's photo `rec` (its JPEG `data`) in this machine's diary `diary`: the file
## beside it, and the record in the diary being kept on the ride (or the one saved, or for later).
## False when it's here already.
func keep(diary: String, rec: Dictionary, data: PackedByteArray) -> bool:
	var uid := str(rec.get("uid", ""))
	if uid == "" or has_photo(diary, uid):
		return false
	var file := "x_%s.jpg" % uid
	DirAccess.make_dir_recursive_absolute(AdventureDiary.folder(diary))
	var f := FileAccess.open(AdventureDiary.folder(diary).path_join(file), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.close()
	var r := rec.duplicate()
	r["file"] = file
	r["shared"] = true
	var trip := AdventureTrip.current
	if trip and trip.photos and trip.photos.diary_id == diary:
		trip.photos.add_shared(r)
	elif FileAccess.file_exists(AdventureDiary.path_of(diary)):
		AdventureDiary.add_photo(diary, r)
	else:
		if not pending.has(diary):
			pending[diary] = []
		(pending[diary] as Array).append(r)
	received += 1
	return true


## Whether diary `diary` here has the photo `uid` already.
static func has_photo(diary: String, uid: String) -> bool:
	var lists: Array = [pending.get(diary, [])]
	var trip := AdventureTrip.current
	if trip and trip.photos and trip.photos.diary_id == diary:
		lists.append(trip.photos.photos)
	else:
		lists.append(AdventureDiary.load_diary(diary).get("photos", []))
	for l in lists:
		for p in l:
			if str(p.get("uid", "")) == uid:
				return true
	return false


## The photos of diary `diary` here: the ride's, or the one saved.
static func _photos_of(diary: String) -> Array:
	var trip := AdventureTrip.current
	if trip and trip.photos and trip.photos.diary_id == diary:
		return trip.photos.photos
	return AdventureDiary.load_diary(diary).get("photos", [])
