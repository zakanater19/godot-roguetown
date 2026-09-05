# Client world streaming

`WorldStream` (`scripts/player/player_world_stream.gd`) is an autoload. The host
keeps the full map and simulation. Each client pulls a window extending 50 tiles
in each horizontal direction, including corners (101 by 101 tiles), on all five
floors. Change `RADIUS_TILES` there to adjust the loaded distance.

Clients free scenery, tree pieces/canopies and NPCs outside their window, and erase
terrain and grass cells that leave it. Re-entry reconstructs them from current
host state. Held items stay with their owners. Remote player scenes use Godot's
MultiplayerSpawner visibility filtering to despawn and respawn; full body and
inventory state is requested again on entry. Actor events travel through the
autoload so events for an unloaded actor don't address a missing node path.
Equipment dictionaries, stats and skills are included in player spawn state;
subsequent changes use reliable, host-authoritative WorldStream RPCs at most every
0.1 seconds. The receiver ignores updates for unloaded actor IDs, and re-entry
requests their full current state. These fields must not use native ON_CHANGE:
late delta packets otherwise target a synchronizer that has already despawned.
Movement and the other small state fields still use native continuous sync.
Reconnect changes only the player root's input authority. It leaves the existing
host-owned synchronizer registered with the same network ID, so other clients do
not receive cache paths for an actor they currently have outside their window.
NPC scenes contain no native MultiplayerSynchronizer: map-placed children enter
the tree before the map registers WorldStream, so disabling one in a later
configuration callback leaves its network path registered on the host.

Requests use the player's host-authoritative position. Terrain transfers only
entering strips; object transfers send new residents, removals and nearby NPC
updates. Initial terrain/object transfers are split across frames. A separate
spatial query limits local FOV and lighting groups to their presentation area.
Static scenery isn't scanned on every player step, and terrain slowdown is a
tile lookup on both the host and clients.

Restart the host and reconnect clients after changing these scripts so every peer
uses the same RPC definitions.

## Verification

Run commands from the project directory, substituting the Godot executable path:

```text
godot --headless --path . -- --validate-imports
godot --headless --path . res://scripts/tools/movement_performance_probe.tscn -- --benchmark-movement
```

Run these two commands in separate terminals (server first); the probe exits
automatically and supports `--stream-port=19145` to select another test port:

```text
godot --headless --path . res://scripts/tools/world_stream_probe.tscn -- --stream-probe=server
godot --headless --path . res://scripts/tools/world_stream_probe.tscn -- --stream-probe=client
```

The integration probe checks terrain, trees, canopy reconstruction, NPCs, remote
player despawn/re-entry, held inventory, host-only state changes while unloaded,
stump slowdown/collision, and full host residency. The movement probe also checks
transform tracking, Z changes, state changes, freeing and square-window bounds.

For actor delta regression coverage, run one host and **two** clients:

```text
godot --headless --path . res://scripts/tools/actor_stream_probe.tscn -- --stream-probe=server
godot --headless --path . res://scripts/tools/actor_stream_probe.tscn -- --stream-probe=client
godot --headless --path . res://scripts/tools/actor_stream_probe.tscn -- --stream-probe=client
```

This checks both sides of repeated radius crossings, changed terrain/tree state,
skill updates, nested equipment data changes, and delivery of a late actor delta
after despawn. Check all three process logs for errors as well as PASS markers.

Measured with Godot 4.7 headless, 441 local entities and 50,000 distant entities:

| Work | Median CPU time |
| --- | ---: |
| Previous full-world render-distance scan | 72.564 ms |
| Previous movement terrain scan | 60.720 ms |
| New local window query | 0.248 ms |
| New movement terrain lookup | 0.004 ms |

These measure the identified CPU paths, not complete rendered frames, network
latency or initial loading. The original 24 smoke sections and the streaming
integration probe pass. Dense local scenery still has a rendering cost.
