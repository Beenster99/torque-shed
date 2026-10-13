class_name Mp3StreamDecoder
extends RefCounted
## Turns a live MP3 byte stream (internet radio) into continuous PCM. Godot only decodes whole
## MP3 files, so this cuts the stream into runs of whole frames and decodes each run as its own
## little file. Each run starts with a few frames already played, because an MP3 frame can lean
## on data from the frames before it (the bit reservoir) and the decoder's filters need a frame
## to settle; the audio from those lead-in frames is thrown away, so the joins are seamless.

const OVERLAP := 4            # frames of lead-in carried into each run
const MAX_BUFFER := 1 << 20   # drop data if a broken stream never syncs

var sample_rate := 0
var channels := 2
var out_rate := 44100.0
var frames_decoded := 0

var _buf := PackedByteArray()      # bytes not yet decoded, starting at a frame header once synced
var _carry: Array[PackedByteArray] = []  # the last OVERLAP frames already played
var _synced := false
var _src_played := 0   # source samples handed out so far
var _out_played := 0   # output samples handed out so far


func _init() -> void:
	# Godot resamples to the mixer's rate, so that's the rate the PCM comes back at.
	out_rate = AudioServer.get_mix_rate()


func reset() -> void:
	_buf = PackedByteArray()
	_carry.clear()
	_synced = false
	sample_rate = 0
	frames_decoded = 0
	_src_played = 0
	_out_played = 0


func feed(bytes: PackedByteArray) -> void:
	_buf.append_array(bytes)
	if _buf.size() > MAX_BUFFER:
		_buf = _buf.slice(_buf.size() - MAX_BUFFER / 2)
		_synced = false


## Seconds of audio waiting in the byte buffer, roughly.
func buffered_frames() -> int:
	return _buf.size() / 400


## Decodes once at least `min_frames` whole frames have arrived. Returns stereo PCM at
## `out_rate`, or an empty array when there isn't enough yet.
func decode(min_frames := 38) -> PackedVector2Array:
	if not _synced and not _sync():
		return PackedVector2Array()
	# Walk whole frames, leaving the last one in case it is still arriving.
	var ends: Array[int] = []
	var pos := 0
	while true:
		var info := frame_info(_buf, pos)
		if info.is_empty():
			if pos == 0 and _buf.size() >= 4:
				# Lost sync (a glitch or stray metadata): find the next good frame.
				_synced = false
				_carry.clear()
				_buf = _buf.slice(1)
				return PackedVector2Array()
			break
		var next: int = pos + int(info["length"])
		if next + 4 > _buf.size():
			break
		ends.append(next)
		pos = next
		if ends.size() >= 400:
			break
	# The last frame is decoded but not played: the resampler smears the end of every run, so
	# it plays at the start of the next run instead.
	if ends.size() < min_frames + 1:
		return PackedVector2Array()
	var first := frame_info(_buf, 0)
	var spf: int = first["samples"]
	sample_rate = first["rate"]
	channels = first["channels"]
	var lead := PackedByteArray()
	for f in _carry:
		lead.append_array(f)
	var lead_frames := _carry.size()
	var run := lead.duplicate()
	run.append_array(_buf.slice(0, ends[-1]))
	var played := ends.size() - 1
	var total := lead_frames + ends.size()
	var ratio := out_rate / float(sample_rate)
	var want := int(total * spf * ratio)
	var mp3 := AudioStreamMP3.new()
	mp3.data = run
	var pb := mp3.instantiate_playback()
	pb.start(0.0)
	var pcm := pb.mix_audio(1.0, want)
	# Frames the decoder couldn't use (no reservoir yet) are skipped, so the audio comes back
	# short (or padded with silence). Count the shortfall to find where the new frames start.
	var zeros := 0
	var i := pcm.size() - 1
	while i >= 0 and pcm[i] == Vector2.ZERO and zeros < int((OVERLAP + 2) * spf * ratio):
		zeros += 1
		i -= 1
	var skipped := clampi(roundi((want - pcm.size() + zeros) / (spf * ratio)), 0, lead_frames)
	var from := roundi((lead_frames - skipped) * spf * ratio)
	# Count output samples against the whole stream so rounding never drifts.
	var count := roundi((_src_played + played * spf) * ratio) - _out_played
	_src_played += played * spf
	_out_played += count
	var out := pcm.slice(from, mini(from + count, pcm.size()))
	# Keep the frames before the unplayed one as lead-in for the next run.
	var starts: Array[int] = [0]
	for e in ends:
		starts.append(e)
	_carry.clear()
	for k in range(maxi(0, played - OVERLAP), played):
		_carry.append(_buf.slice(starts[k], starts[k + 1]))
	_buf = _buf.slice(starts[played])
	frames_decoded += played
	return out


## Finds the first frame header followed by another valid header.
func _sync() -> bool:
	var i := 0
	while i < _buf.size() - 4:
		var a := frame_info(_buf, i)
		if not a.is_empty():
			var b := frame_info(_buf, i + int(a["length"]))
			if not b.is_empty() and b["rate"] == a["rate"]:
				# A file's first frame can be a silent Xing/Info tag; skip it, it isn't audio.
				var tag := _buf.slice(i + 4, i + 40).get_string_from_ascii()
				_buf = _buf.slice(i + int(a["length"]) if (tag.contains("Xing") or tag.contains("Info")) else i)
				_synced = true
				return true
		i += 1
	# Keep the tail; a header may be split across reads.
	if _buf.size() > 4:
		_buf = _buf.slice(_buf.size() - 4)
	return false


const _BITRATES_V1 := [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
const _BITRATES_V2 := [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
const _RATES := [44100, 48000, 32000]


## Reads an MPEG audio layer III frame header at `pos`: {length, samples, rate, channels},
## or {} when there isn't one.
static func frame_info(buf: PackedByteArray, pos: int) -> Dictionary:
	if pos < 0 or pos + 4 > buf.size():
		return {}
	var b0 := buf[pos]
	var b1 := buf[pos + 1]
	var b2 := buf[pos + 2]
	var b3 := buf[pos + 3]
	if b0 != 0xFF or (b1 & 0xE0) != 0xE0:
		return {}
	var version := (b1 >> 3) & 3      # 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
	var layer := (b1 >> 1) & 3        # 1 = layer III
	if version == 1 or layer != 1:
		return {}
	var br_index := (b2 >> 4) & 15
	var rate_index := (b2 >> 2) & 3
	if br_index == 0 or br_index == 15 or rate_index == 3:
		return {}
	var padding := (b2 >> 1) & 1
	var rate: int = _RATES[rate_index]
	if version == 2:
		rate /= 2
	elif version == 0:
		rate /= 4
	var mpeg1 := version == 3
	var bitrate: int = (_BITRATES_V1[br_index] if mpeg1 else _BITRATES_V2[br_index]) * 1000
	var length := (144 if mpeg1 else 72) * bitrate / rate + padding
	return {"length": length, "samples": 1152 if mpeg1 else 576, "rate": rate,
		"channels": 1 if ((b3 >> 6) & 3) == 3 else 2}
