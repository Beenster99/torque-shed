extends Node
## Multiplayer session over ENet. One player hosts (the server is also a player), others join by IP.
## Each player simulates themselves (on foot or riding) and streams their state; the server
## relays it to everyone. The shed itself is kept in step by the Shed autoload.

signal player_joined(id: int, info: Dictionary)
signal player_updated(id: int, info: Dictionary)
signal player_left(id: int)
signal state_received(id: int, state: PackedFloat32Array)
signal connected
signal connection_failed(reason: String)
signal disconnected
signal internet_status_changed
## The host's clock (hours, and hours per second it runs at), for Daylight on clients.
signal time_received(hours: float, rate: float)
## The host's weather (see Weather): the state it's heading for, the one it's leaving, how far
## the change has got (0..1) and how wet the roads are (0..1).
signal weather_received(state: String, from: String, blend: float, wet: float)
## The host's road traffic (see RoadTraffic.pack): the other bikers out on the roads.
signal traffic_received(state: PackedFloat32Array)

## Whether friends outside your network can reach your shed: "" (not hosting), "checking",
## "open" (the router opened the port for us via UPnP) or "closed" (it has to be forwarded by hand).
var internet_status := ""
var external_ip := ""
var _upnp: UPNP
var _upnp_thread: Thread
var _mapped_port := 0

const PORT := 24680
const MAX_PLAYERS := 8

var players := {}      # remote peer id -> info Dictionary {name, color}
var local_info := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Spawn slot for this player: the host takes slot 0, joiners spread over the rest.
func local_slot() -> int:
	if not is_online() or multiplayer.is_server():
		return 0
	return 1 + local_id() % (MAX_PLAYERS - 1)


func host(info: Dictionary, port := PORT) -> Error:
	leave()
	local_info = info
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_open_router_port(port)
	return OK


## Splits what a player typed into the join box into host and port. Takes "81.2.3.4",
## "81.2.3.4:24680", "[2a00::1]:24680", a bare IPv6 address or a host name.
static func parse_address(text: String) -> Dictionary:
	var host := text.strip_edges()
	var port := PORT
	for prefix in ["udp://", "http://", "https://"]:
		host = host.trim_prefix(prefix)
	host = host.trim_suffix("/")
	if host.begins_with("["):
		var close := host.find("]")
		if close > 0:
			var rest := host.substr(close + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				port = int(rest.substr(1))
			host = host.substr(1, close - 1)
	elif host.count(":") == 1:
		var parts := host.split(":")
		if parts[1].strip_edges().is_valid_int():
			port = int(parts[1])
		host = parts[0]
	host = host.strip_edges()
	if port <= 0 or port > 65535:
		port = PORT
	return {"host": host, "port": port}


func join(address: String, info: Dictionary, port := 0) -> Error:
	leave()
	local_info = info
	var where := parse_address(address)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(where["host"], port if port > 0 else int(where["port"]))
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	_close_router_port()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in players.keys():
		player_left.emit(id)
	players.clear()


## LAN addresses friends can join on.
func local_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


## Asks the home router to forward the port to this PC (UPnP), and finds the address friends
## outside the network should use. Runs on a thread because routers can take seconds to answer.
func _open_router_port(port: int) -> void:
	internet_status = "checking"
	external_ip = ""
	internet_status_changed.emit()
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-upnp"):
		_upnp_done.call_deferred(false, "", port)
		return
	_wait_upnp_thread()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(port: int) -> void:
	var upnp := UPNP.new()
	var ok := false
	var ip := ""
	if upnp.discover(2500, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
			and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		ip = upnp.query_external_address()
		ok = upnp.add_port_mapping(port, port, "Torque Shed", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
	_upnp = upnp if ok else null
	_upnp_done.call_deferred(ok, ip, port)


func _upnp_done(ok: bool, ip: String, port: int) -> void:
	_wait_upnp_thread()
	if not is_host():
		# Stopped hosting while the router was answering.
		if ok and _upnp:
			_upnp.delete_port_mapping(port, "UDP")
		_upnp = null
		return
	_mapped_port = port if ok else 0
	internet_status = "open" if ok else "closed"
	external_ip = ip if ip.is_valid_ip_address() and not _is_private(ip) else ""
	internet_status_changed.emit()
	if external_ip == "":
		_lookup_public_ip()


## Asks a public "what's my IP" service when the router didn't tell us.
func _lookup_public_ip() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, body: PackedByteArray):
		http.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address() and is_host():
			external_ip = ip
			internet_status_changed.emit())
	if http.request("https://api.ipify.org") != OK:
		http.queue_free()


static func _is_private(ip: String) -> bool:
	if ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("127.") or ip.begins_with("169.254."):
		return true
	if ip.begins_with("172."):
		var second := int(ip.split(".")[1])
		return second >= 16 and second <= 31
	if ip.begins_with("100."):
		# Carrier-grade NAT: the ISP shares one public address between many homes.
		var second := int(ip.split(".")[1])
		return second >= 64 and second <= 127
	return false


func _close_router_port() -> void:
	if _upnp and _mapped_port > 0:
		_upnp.delete_port_mapping(_mapped_port, "UDP")
	_upnp = null
	_mapped_port = 0
	internet_status = ""
	external_ip = ""


func _wait_upnp_thread() -> void:
	if _upnp_thread and _upnp_thread.is_started() and not _upnp_thread.is_alive():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null


func _exit_tree() -> void:
	_close_router_port()
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


## What to tell friends, for the pause menu and the hosting message.
func join_instructions() -> String:
	var lan := ", ".join(local_addresses())
	var lines := ["Friends on your home network join with: %s" % lan]
	match internet_status:
		"checking":
			lines.append("Checking whether friends over the internet can reach you...")
		"open":
			lines.append("Your router opened port %d for the game, so friends over the internet join with: %s" % [PORT,
				external_ip if external_ip != "" else "your public IP address"])
		"closed":
			lines.append("Your router didn't open the port automatically. For friends over the internet, forward UDP port %d on your router to %s, then they join with: %s" % [
				PORT, local_addresses()[0] if not local_addresses().is_empty() else "this PC",
				external_ip if external_ip != "" else "your public IP address"])
	return "\n".join(lines)


func update_local_info(info: Dictionary) -> void:
	local_info = info
	if is_online():
		_register.rpc(info)


func send_state(state: PackedFloat32Array) -> void:
	if is_online() and not players.is_empty():
		_state.rpc(state)


## Host only: tell everyone the time of day.
func send_time(hours: float, rate: float) -> void:
	if is_host() and not players.is_empty():
		_time.rpc(hours, rate)


func _on_peer_connected(id: int) -> void:
	_register.rpc_id(id, local_info)


func _on_peer_disconnected(id: int) -> void:
	if players.erase(id):
		player_left.emit(id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit("Could not reach the host. Check the address, that the host has forwarded UDP port %d on their router (the host's Esc menu says whether it's open), and that Windows Firewall lets Torque Shed through." % PORT)


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	var clean := {
		"name": str(info.get("name", "Rider")).left(24),
		"color": info.get("color", Color(0.8, 0.1, 0.1)),
	}
	var is_new := not players.has(id)
	players[id] = clean
	if is_new:
		player_joined.emit(id, clean)
	else:
		player_updated.emit(id, clean)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(state: PackedFloat32Array) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _time(hours: float, rate: float) -> void:
	time_received.emit(hours, rate)


## Host only: tell everyone the weather.
func send_weather(state: String, from: String, blend: float, wet: float) -> void:
	if is_host() and not players.is_empty():
		_weather.rpc(state, from, blend, wet)


@rpc("authority", "call_remote", "unreliable_ordered")
func _weather(state: String, from: String, blend: float, wet: float) -> void:
	weather_received.emit(state, from, blend, wet)


## Host only: where the other bikers on the roads are (see RoadTraffic), a few times a second.
func send_traffic(state: PackedFloat32Array) -> void:
	if is_host() and not players.is_empty():
		_traffic.rpc(state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _traffic(state: PackedFloat32Array) -> void:
	traffic_received.emit(state)
