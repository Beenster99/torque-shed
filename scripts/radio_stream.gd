class_name RadioStream
extends Node
## Plays an internet radio station (an MP3 Icecast/Shoutcast stream) through an audio player.
## Speaks just enough HTTP itself (Godot's HTTPClient won't read a body that never ends, and
## some stations answer "ICY 200 OK"). Connects over HTTP or HTTPS, follows redirects, reads the "now playing" title from the
## stream's metadata, decodes the audio a second at a time and feeds it to a generator so it
## plays without gaps. If the station can't be reached it says so and the radio hisses.

signal status_changed(text: String)

const PREBUFFER := 1.5      # seconds of audio to have ready before playing
const TIMEOUT := 10.0       # seconds without data before giving up on a station
const RETRY := 15.0         # seconds before trying a dead station again

var player: AudioStreamPlayer3D
var url := ""
var status := ""
var title := ""             # the song playing, when the station sends it

enum State { IDLE, RESOLVING, CONNECTING, HANDSHAKE, HEADERS, BODY }

var _state := State.IDLE
var _tcp: StreamPeerTCP
var _tls: StreamPeerTLS
var _peer: StreamPeer
var _resolve_id := -1
var _tls_on := false
var _port := 80
var _head := PackedByteArray()
var _decoder := Mp3StreamDecoder.new()
var _gen: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback
var _pending := PackedVector2Array()
var _redirects := 0
var _host := ""
var _path := "/"
var _metaint := 0
var _audio_left := 0        # audio bytes until the next metadata block
var _meta_left := -1        # metadata bytes still to read, -2 for the length byte, -1 for audio
var _meta := PackedByteArray()
var _quiet := 0.0           # seconds since anything last happened
var _retry_in := 0.0
var _playing := false


func _ready() -> void:
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = AudioServer.get_mix_rate()
	_gen.buffer_length = 1.0


func tune(new_url: String) -> void:
	stop()
	url = new_url
	_redirects = 0
	_open(url)


func stop() -> void:
	_close()
	url = ""
	_decoder.reset()
	_pending = PackedVector2Array()
	_playing = false
	_retry_in = 0.0
	title = ""
	if player and player.stream == _gen:
		player.stop()
	_set_status("")


func is_live() -> bool:
	return _playing


func _close() -> void:
	if _tls:
		_tls.disconnect_from_stream()
	if _tcp:
		_tcp.disconnect_from_host()
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
	_tls = null
	_tcp = null
	_peer = null
	_resolve_id = -1
	_state = State.IDLE


func _open(target: String) -> void:
	_close()
	var m := RegEx.create_from_string("^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$").search(target)
	if m == null:
		_fail("Bad station address")
		return
	_tls_on = m.get_string(1) == "https"
	_host = m.get_string(2)
	_port = int(m.get_string(3)) if m.get_string(3) != "" else (443 if _tls_on else 80)
	_path = m.get_string(4) if m.get_string(4) != "" else "/"
	_metaint = 0
	_meta_left = -1
	_head = PackedByteArray()
	_quiet = 0.0
	if _host.is_valid_ip_address():
		_connect_to(_host)
	else:
		_resolve_id = IP.resolve_hostname_queue_item(_host)
		_state = State.RESOLVING
	_set_status("Tuning in...")


func _connect_to(ip: String) -> void:
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(ip, _port) != OK:
		_fail("No signal")
		return
	_state = State.CONNECTING


func _fail(why: String) -> void:
	_close()
	_playing = false
	_retry_in = RETRY
	_set_status(why)


func _set_status(text: String) -> void:
	if text != status:
		status = text
		status_changed.emit(text)


func _process(delta: float) -> void:
	if url == "":
		return
	if _state == State.IDLE:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_open(url)
		_feed_player()
		return
	_quiet += delta
	if _quiet > TIMEOUT:
		_fail("No signal")
		return
	match _state:
		State.RESOLVING:
			var st := IP.get_resolve_item_status(_resolve_id)
			if st == IP.RESOLVER_STATUS_DONE:
				var ip := IP.get_resolve_item_address(_resolve_id)
				IP.erase_resolve_item(_resolve_id)
				_resolve_id = -1
				if ip == "":
					_fail("No signal")
				else:
					_connect_to(ip)
			elif st != IP.RESOLVER_STATUS_WAITING:
				_fail("No signal")
		State.CONNECTING:
			_tcp.poll()
			match _tcp.get_status():
				StreamPeerTCP.STATUS_CONNECTED:
					if _tls_on:
						_tls = StreamPeerTLS.new()
						if _tls.connect_to_stream(_tcp, _host, TLSOptions.client()) != OK:
							_fail("No signal")
							return
						_state = State.HANDSHAKE
					else:
						_peer = _tcp
						_send_request()
				StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
					_fail("No signal")
		State.HANDSHAKE:
			_tls.poll()
			match _tls.get_status():
				StreamPeerTLS.STATUS_CONNECTED:
					_peer = _tls
					_send_request()
				StreamPeerTLS.STATUS_HANDSHAKING:
					pass
				_:
					_fail("No signal")
		State.HEADERS, State.BODY:
			_read()
	_feed_player()


func _send_request() -> void:
	var host := _host if _port in [80, 443] else "%s:%d" % [_host, _port]
	var req := "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: TorqueShed\r\nAccept: */*\r\nIcy-MetaData: 1\r\nConnection: close\r\n\r\n" % [_path, host]
	_peer.put_data(req.to_utf8_buffer())
	_state = State.HEADERS
	_quiet = 0.0


func _read() -> void:
	if _tls:
		_tls.poll()
	else:
		_tcp.poll()
	var connected := (_tls.get_status() == StreamPeerTLS.STATUS_CONNECTED) if _tls else (_tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	for i in 32:
		var got := _peer.get_partial_data(16384)
		if got[0] != OK:
			connected = false
			break
		var data: PackedByteArray = got[1]
		if data.is_empty():
			break
		_quiet = 0.0
		if _state == State.HEADERS:
			_head.append_array(data)
			var end := _find_header_end(_head)
			if end < 0:
				if _head.size() > 16384:
					_fail("No signal")
					return
				continue
			var body := _head.slice(end)
			if not _parse_headers(_head.slice(0, end).get_string_from_utf8()):
				return
			_state = State.BODY
			if not body.is_empty():
				_split(body)
		else:
			_split(data)
	var made := _decoder.decode()
	if not made.is_empty():
		_pending.append_array(made)
	if not connected:
		_fail("Signal lost")


func _find_header_end(buf: PackedByteArray) -> int:
	for i in range(3, buf.size()):
		if buf[i] == 10 and buf[i - 1] == 13 and buf[i - 2] == 10 and buf[i - 3] == 13:
			return i + 1
	return -1


## Reads the status line and headers. Follows redirects. Returns false if it gave up or moved.
func _parse_headers(text: String) -> bool:
	var lines := text.split("\r\n")
	var code := int(lines[0].get_slice(" ", 1)) if lines.size() > 0 else 0
	var headers := {}
	for line in lines.slice(1):
		var colon := line.find(":")
		if colon > 0:
			headers[line.left(colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	if code in [301, 302, 303, 307, 308]:
		_redirects += 1
		var to := str(headers.get("location", ""))
		if to == "" or _redirects > 5:
			_fail("No signal")
		else:
			_open(to)
		return false
	if code != 200:
		_fail("No signal")
		return false
	_metaint = int(headers.get("icy-metaint", "0"))
	_audio_left = _metaint
	_meta_left = -1
	return true


## Separates audio bytes from the ICY metadata blocks woven through them.
func _split(chunk: PackedByteArray) -> void:
	if _metaint <= 0:
		_decoder.feed(chunk)
		return
	var i := 0
	while i < chunk.size():
		if _meta_left == -1:
			var n := mini(_audio_left, chunk.size() - i)
			_decoder.feed(chunk.slice(i, i + n))
			i += n
			_audio_left -= n
			if _audio_left == 0:
				_meta_left = -2   # the next byte is the metadata length
		elif _meta_left == -2:
			_meta_left = chunk[i] * 16
			_meta = PackedByteArray()
			i += 1
			if _meta_left == 0:
				_meta_left = -1
				_audio_left = _metaint
		else:
			var n := mini(_meta_left, chunk.size() - i)
			_meta.append_array(chunk.slice(i, i + n))
			i += n
			_meta_left -= n
			if _meta_left == 0:
				_read_title(_meta.get_string_from_utf8())
				_meta_left = -1
				_audio_left = _metaint


func _read_title(meta: String) -> void:
	var m := RegEx.create_from_string("StreamTitle='(.*?)';").search(meta)
	if m:
		title = m.get_string(1).strip_edges()
		status_changed.emit(status)


func _feed_player() -> void:
	if player == null:
		return
	if not _playing:
		if _pending.size() < int(PREBUFFER * _gen.mix_rate):
			return
		player.stream = _gen
		player.play()
		_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
		_playing = true
		_set_status("On air")
	if _playback == null:
		return
	var room := _playback.get_frames_available()
	if room <= 0 or _pending.is_empty():
		return
	var n := mini(room, _pending.size())
	_playback.push_buffer(_pending.slice(0, n))
	_pending = _pending.slice(n)
