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
	return OK


func join(ip: String, info: Dictionary, port := PORT) -> Error:
	leave()
	local_info = info
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
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


func update_local_info(info: Dictionary) -> void:
	local_info = info
	if is_online():
		_register.rpc(info)


func send_state(state: PackedFloat32Array) -> void:
	if is_online() and not players.is_empty():
		_state.rpc(state)


func _on_peer_connected(id: int) -> void:
	_register.rpc_id(id, local_info)


func _on_peer_disconnected(id: int) -> void:
	if players.erase(id):
		player_left.emit(id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit("Could not reach the host.")


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
