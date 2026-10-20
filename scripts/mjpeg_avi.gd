class_name MjpegAvi
extends RefCounted
## Writes a film as an AVI file of JPEG frames (Motion JPEG), which Windows' own Films & TV and
## Media Player play, as do VLC and the rest: Godot's MovieWriter only runs from the command line,
## so the movie clips (MovieClip) are put together here, from frames already turned into JPEGs.
##
## The file is one RIFF "AVI " chunk: a header list (the main header, then one video stream's
## header and its picture format), a "movi" list of the frames ("00dc" chunks, each a whole JPEG)
## and an "idx1" index of where each frame is, every one a key frame. No sound.

const AVIF_HASINDEX := 0x10
const AVIIF_KEYFRAME := 0x10


## The AVI of `frames` (each a JPEG's bytes, `w` x `h`) at `fps` frames a second.
static func build(frames: Array, w: int, h: int, fps: int) -> PackedByteArray:
	var biggest := 0
	var total := 0
	for f in frames:
		biggest = maxi(biggest, (f as PackedByteArray).size())
		total += (f as PackedByteArray).size()
	var n := frames.size()
	var secs := maxf(float(n) / maxf(1.0, float(fps)), 0.001)
	# The main header.
	var avih := _Buf.new()
	avih.u32(roundi(1000000.0 / maxf(1.0, float(fps))))   # microseconds a frame
	avih.u32(int(total / secs))                            # bytes a second, about
	avih.u32(0)                                            # padding granularity
	avih.u32(AVIF_HASINDEX)
	avih.u32(n)                                            # frames
	avih.u32(0)                                            # initial frames
	avih.u32(1)                                            # streams
	avih.u32(biggest + 8)                                  # suggested buffer size
	avih.u32(w)
	avih.u32(h)
	for i in 4:
		avih.u32(0)
	# The video stream's header.
	var strh := _Buf.new()
	strh.fourcc("vids")
	strh.fourcc("MJPG")
	strh.u32(0)        # flags
	strh.u16(0)        # priority
	strh.u16(0)        # language
	strh.u32(0)        # initial frames
	strh.u32(1)        # scale: rate / scale is the frames a second
	strh.u32(fps)
	strh.u32(0)        # start
	strh.u32(n)        # length, in frames
	strh.u32(biggest + 8)
	strh.u32(0xFFFFFFFF)   # quality: the default
	strh.u32(0)        # sample size: each frame its own size
	strh.u16(0)
	strh.u16(0)
	strh.u16(w)
	strh.u16(h)
	# Its picture format (a BITMAPINFOHEADER).
	var strf := _Buf.new()
	strf.u32(40)
	strf.u32(w)
	strf.u32(h)
	strf.u16(1)        # planes
	strf.u16(24)       # bits a pixel
	strf.fourcc("MJPG")
	strf.u32(w * h * 3)
	strf.u32(0)
	strf.u32(0)
	strf.u32(0)
	strf.u32(0)
	var strl := _Buf.new()
	strl.fourcc("strl")
	strl.chunk("strh", strh.data)
	strl.chunk("strf", strf.data)
	var hdrl := _Buf.new()
	hdrl.fourcc("hdrl")
	hdrl.chunk("avih", avih.data)
	hdrl.chunk("LIST", strl.data)
	# The frames, and where each is (from the "movi" mark).
	var movi := _Buf.new()
	movi.fourcc("movi")
	var idx := _Buf.new()
	for f in frames:
		var bytes: PackedByteArray = f
		idx.fourcc("00dc")
		idx.u32(AVIIF_KEYFRAME)
		idx.u32(movi.data.size())
		idx.u32(bytes.size())
		movi.chunk("00dc", bytes)
	var body := _Buf.new()
	body.fourcc("AVI ")
	body.chunk("LIST", hdrl.data)
	body.chunk("LIST", movi.data)
	body.chunk("idx1", idx.data)
	var out := _Buf.new()
	out.chunk("RIFF", body.data)
	return out.data


## Reads an AVI back, for the tests and to check a file: {ok, w, h, fps, frames (the count the
## header says), jpegs [the frames' bytes, from the "movi" list], index (idx1's count), index_ok
## (every index entry points at its frame)}. ok false when it isn't one.
static func parse(data: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "w": 0, "h": 0, "fps": 0, "frames": 0, "jpegs": [], "index": 0, "index_ok": false, "handler": ""}
	if data.size() < 12 or _cc(data, 0) != "RIFF" or _cc(data, 8) != "AVI " or data.decode_u32(4) + 8 > data.size():
		return out
	var movi_at := -1
	var idx_at := -1
	var idx_len := 0
	var p := 12
	var end := 8 + int(data.decode_u32(4))
	while p + 8 <= end:
		var id := _cc(data, p)
		var ln := int(data.decode_u32(p + 4))
		if id == "LIST" and _cc(data, p + 8) == "hdrl":
			_read_hdrl(data, p + 12, p + 8 + ln, out)
		elif id == "LIST" and _cc(data, p + 8) == "movi":
			movi_at = p + 8
			var q := p + 12
			while q + 8 <= p + 8 + ln:
				var cl := int(data.decode_u32(q + 4))
				if _cc(data, q) == "00dc":
					(out["jpegs"] as Array).append(data.slice(q + 8, q + 8 + cl))
				q += 8 + cl + (cl & 1)
		elif id == "idx1":
			idx_at = p + 8
			idx_len = ln
		p += 8 + ln + (ln & 1)
	if idx_at >= 0 and movi_at >= 0:
		out["index"] = idx_len / 16
		var good := true
		for k in idx_len / 16:
			var e := idx_at + k * 16
			var at := movi_at + int(data.decode_u32(e + 8))
			var size := int(data.decode_u32(e + 12))
			if _cc(data, e) != "00dc" or at + 8 > data.size() or _cc(data, at) != "00dc" or int(data.decode_u32(at + 4)) != size:
				good = false
				break
		out["index_ok"] = good and int(out["index"]) == (out["jpegs"] as Array).size()
	out["ok"] = movi_at >= 0 and int(out["w"]) > 0
	return out


static func _read_hdrl(data: PackedByteArray, from: int, to: int, out: Dictionary) -> void:
	var p := from
	while p + 8 <= to:
		var id := _cc(data, p)
		var ln := int(data.decode_u32(p + 4))
		if id == "avih":
			out["frames"] = int(data.decode_u32(p + 8 + 16))
			out["w"] = int(data.decode_u32(p + 8 + 32))
			out["h"] = int(data.decode_u32(p + 8 + 36))
		elif id == "LIST" and _cc(data, p + 8) == "strl":
			_read_hdrl(data, p + 12, p + 8 + ln, out)
		elif id == "strh":
			out["handler"] = _cc(data, p + 12)
			var scale := maxi(1, int(data.decode_u32(p + 8 + 20)))
			out["fps"] = int(data.decode_u32(p + 8 + 24)) / scale
		p += 8 + ln + (ln & 1)


static func _cc(data: PackedByteArray, at: int) -> String:
	if at + 4 > data.size():
		return ""
	return data.slice(at, at + 4).get_string_from_ascii()


## Little-endian bytes, built up.
class _Buf extends RefCounted:
	var data := PackedByteArray()

	func u32(v: int) -> void:
		var at := data.size()
		data.resize(at + 4)
		data.encode_u32(at, v & 0xFFFFFFFF)

	func u16(v: int) -> void:
		var at := data.size()
		data.resize(at + 2)
		data.encode_u16(at, v & 0xFFFF)

	func fourcc(s: String) -> void:
		data.append_array(s.to_ascii_buffer())

	## A chunk: its id, its length, the bytes, and a byte of padding to an even length.
	func chunk(id: String, bytes: PackedByteArray) -> void:
		fourcc(id)
		u32(bytes.size())
		data.append_array(bytes)
		if bytes.size() % 2 == 1:
			data.append(0)
