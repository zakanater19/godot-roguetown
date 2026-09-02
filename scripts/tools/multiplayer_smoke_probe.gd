extends Node

## Small RPC endpoint used by the import smoke test. It exercises the same
## authority, reliable-RPC, and snapshot-correction path used by gameplay
## without loading a full world into the headless test process.

var state: Dictionary = {}
var authoritative_sequence: int = 0
var received_sequence: int = -1
var received_snapshots: int = 0
var accepted_inputs: int = 0
var rejected_inputs: int = 0
var detected_desyncs: int = 0
var corrected_desyncs: int = 0
var invalid_snapshots: int = 0
var last_received_checksum: String = ""
var _last_input_sequence_by_peer: Dictionary = {}


func configure(initial_state: Dictionary) -> void:
	state = initial_state.duplicate(true)
	authoritative_sequence = int(state.get("tick", 0))


func state_checksum() -> String:
	return checksum_for(state)


static func checksum_for(snapshot: Dictionary) -> String:
	var tile: Vector2i = snapshot.get("tile", Vector2i.ZERO)
	var inventory: Array = snapshot.get("inventory", [])
	var inventory_parts := PackedStringArray()
	for item: Variant in inventory:
		inventory_parts.append(str(item))
	var canonical := "%d|%d,%d|%d|%d|%s" % [
		int(snapshot.get("tick", 0)),
		tile.x,
		tile.y,
		int(snapshot.get("health", 0)),
		int(snapshot.get("active_hand", 0)),
		",".join(inventory_parts),
	]
	return canonical.sha256_text()


func request_move(request_sequence: int, delta: Vector2i) -> void:
	request_move_rpc.rpc_id(1, request_sequence, delta)


func broadcast_authoritative_state() -> void:
	if not multiplayer.is_server():
		return
	receive_authoritative_state.rpc(
		authoritative_sequence,
		state.duplicate(true),
		state_checksum()
	)


@rpc("any_peer", "call_remote", "reliable")
func request_move_rpc(request_sequence: int, delta: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		rejected_inputs += 1
		return
	var last_sequence := int(_last_input_sequence_by_peer.get(sender_id, -1))
	if request_sequence <= last_sequence:
		rejected_inputs += 1
		return
	_last_input_sequence_by_peer[sender_id] = request_sequence
	accepted_inputs += 1
	authoritative_sequence += 1
	state["tick"] = authoritative_sequence
	state["tile"] = Vector2i(state.get("tile", Vector2i.ZERO)) + delta
	broadcast_authoritative_state()


@rpc("authority", "call_remote", "reliable")
func receive_authoritative_state(sequence: int, snapshot: Dictionary, expected_checksum: String) -> void:
	if multiplayer.is_server() or sequence < received_sequence:
		return
	if checksum_for(snapshot) != expected_checksum:
		invalid_snapshots += 1
		return
	var checksum_before := state_checksum()
	var is_desync_correction := sequence == received_sequence and checksum_before != expected_checksum
	if is_desync_correction:
		detected_desyncs += 1
	state = snapshot.duplicate(true)
	received_sequence = sequence
	received_snapshots += 1
	last_received_checksum = state_checksum()
	if is_desync_correction:
		corrected_desyncs += 1
