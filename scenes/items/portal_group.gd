extends Node2D

# Attach to a Node2D whose children are ExitPortal instances (e.g. dungeon_
# main.tscn's "doors/portals"). Deterministically picks one of them as the
# party's arrival point for this expedition and excludes it from ever
# functioning as an exit — you can't leave out the same door you arrived
# through.
#
# No networking needed here: every peer independently loads the exact same
# static room scene, and Stats.expedition_seed is the same server-picked,
# broadcast value every peer already uses for enemy_spawner.gd's per-room
# randomization (see world.gd's broadcast_expedition_seed) — combining it
# with this room's own key (set by world_rooms.gd, same as enemy_spawner.gd's
# room_key) means every peer's local RNG lands on the identical child index.

var room_key := ""
var chosen_portal = null

func _ready() -> void:
	var portals: Array = []
	for child in get_children():
		if child is ExitPortal:
			portals.append(child)
	if portals.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Stats.expedition_seed ^ room_key.hash()
	chosen_portal = portals[rng.randi() % portals.size()]
	chosen_portal.mark_as_spawn_point()

func get_spawn_global_position() -> Vector2:
	if chosen_portal == null:
		return global_position
	return chosen_portal.global_position
