# res://serverbrowser.gd
extends Node

signal server_found(ip: String, port: int)

const DISCOVERY_PORT: int = 9905
const BROADCAST_INTERVAL: float = 1.0

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer: float = 0.0

func start_broadcasting() -> void:
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	# Changed bind from DISCOVERY_PORT to 0 to allow the broadcaster 
	# to use an ephemeral port, preventing binding conflicts on localhost.
	_broadcaster.bind(0)

func stop_broadcasting() -> void:
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null

func start_listening() -> void:
	_listener = PacketPeerUDP.new()
	_listener.bind(DISCOVERY_PORT)

func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null

func _process(delta: float) -> void:
	# BROADCASTER LOGIC
	if _broadcaster:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_broadcaster.put_packet("ROGUETOWN_SERVER:9904".to_utf8_buffer())

	# LISTENER LOGIC
	if _listener and _listener.get_available_packet_count() > 0:
		var packet = _listener.get_packet()
		var msg = packet.get_string_from_utf8()
		if msg.begins_with("ROGUETOWN_SERVER"):
			var port = int(msg.split(":")[1])
			server_found.emit("127.0.0.1", port)