class_name MultiplayerSession
extends RefCounted

## True only while gameplay has a real, fully connected multiplayer peer.
## Simulation callers stop at this boundary during startup and teardown.
static func is_active(multiplayer_api: MultiplayerAPI) -> bool:
	if multiplayer_api == null or not multiplayer_api.has_multiplayer_peer():
		return false
	var peer := multiplayer_api.multiplayer_peer
	return (
		peer != null
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)
