extends Node2D

# Hand-placed loot-container spawner — the container analogue of enemy_spawner.gd.
# Attach to a Node2D whose Marker2D children are POSSIBLE container spawn points. Each
# point independently and DETERMINISTICALLY (seeded from Stats.expedition_seed ^ the
# marker name, exactly like the enemy spawner) rolls whether a container spawns there,
# its base TYPE (weighted), and its TIER — so every peer in the party spawns the same
# layout with no networked spawning. GOLD tier is never rolled here (it's location-based
# for future locked areas). The spawned loot_container handles its own per-expedition
# looted persistence, so this needs no save/restore of its own.

const ContainerScene := preload("res://scenes/items/loot_container.tscn")

@export var spawn_chance := 0.6
# Weighted base types this spawner may roll — edit per spawner for themed rooms (e.g. a
# mine room = mostly mining_node, a med bay = medic_box). Keys are LOOT_TABLES types.
@export var type_weights: Dictionary = {
	"crate": 40, "chest": 15, "mining_node": 20, "medic_box": 15, "weapon_case": 10,
}
const SILVER_CHANCE := 0.12  # else bronze; gold is never rolled (locked-area only)

func _ready() -> void:
	for child in get_children():
		if child is Marker2D:
			_try_spawn(child)

func _try_spawn(point: Marker2D) -> void:
	var rng := RandomNumberGenerator.new()
	# Salt with the room scene too: every level names its markers container_1..N,
	# so seeding by marker name alone gave identical rolls in every room/map.
	var room_salt: String = owner.scene_file_path if owner != null else ""
	rng.seed = Stats.expedition_seed ^ (room_salt + "/" + String(point.name)).hash()
	if rng.randf() >= spawn_chance:
		return
	var ctype := _pick_type(rng)
	if ctype == "":
		return
	var container := ContainerScene.instantiate()
	# Stable name so the container's looted state persists across a revisit.
	container.name = "%s_container" % point.name
	container.container_type = ctype
	container.tier = "silver" if rng.randf() < SILVER_CHANCE else "bronze"
	container.position = point.position
	add_child(container)

func _pick_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for w in type_weights.values():
		total += int(w)
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	var cum := 0
	for t in type_weights:
		cum += int(type_weights[t])
		if roll <= cum:
			return t
	return ""
