extends Area2D
class_name LootContainer

# Hand-placed lootable container. Server-authoritative (Godot default authority
# = peer 1), same shape as exit_portal.gd: any player near it can interact; the
# server rolls its loot exactly once (into a ground pile at the container) and
# broadcasts the "looted" state to everyone in the room so it can't be opened
# again. container_type keys into ItemData.CONTAINERS for its label/color/pool.

@export var container_type := "wooden_crate"
# Loot tier for the NEW base types (crate/chest/weapon_case/mining_node/medic_box) —
# keys into ItemData.LOOT_TABLES[container_type][tier]. Old v1 container types ignore it.
@export var tier := "bronze"

const TIER_TINTS := {
	"bronze": Color(1, 1, 1),
	"silver": Color(0.8, 0.85, 0.95),
	"gold": Color(1.0, 0.85, 0.35),
}
func _tier_tint() -> Color:
	return TIER_TINTS.get(tier, Color(1, 1, 1))

var looted := false
var can_use := false
# Set once we've checked this expedition's looted record (needs the room loaded).
var _restored := false
# For "elemental" container types (mining nodes): the element this node rolled at
# spawn. Drives its color + the @dust/@crystal loot. "" = non-elemental container.
var element := ""

@onready var color_rect: ColorRect = $visual_root/color_rect
@onready var status_label: Label = $visual_root/status_label

func _ready() -> void:
	if _is_elemental():
		_roll_element()
	_update_visual()

func _is_elemental() -> bool:
	return ItemData.CONTAINERS.get(container_type, {}).get("elemental", false)

# Deterministic per-node element (seed = expedition seed ^ node name) so every peer
# rolls the same one — same pattern as the enemy spawner. Server drops match.
func _roll_element() -> void:
	var elements: Array = SpellData.ELEMENT_ORDER
	if elements.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Stats.expedition_seed ^ String(name).hash()
	element = elements[rng.randi() % elements.size()]

func _on_body_entered(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = false

func _process(_delta: float) -> void:
	# On first frame the room is loaded — restore this expedition's looted state
	# so a revisited container stays empty (cleared for a fresh expedition, see
	# Stats.expedition_looted_containers). Retries until the room resolves.
	if !_restored:
		var id := _container_id()
		if id != "":
			_restored = true
			if Stats.expedition_looted_containers.has(id):
				looted = true
				_update_visual()
	if !can_use or looted:
		return
	if Input.is_action_just_pressed("interact"):
		_request_open()

func _request_open() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		# Host opening its own container — it IS the local player, so auto-open for us.
		_do_open(multiplayer.get_unique_id())
	else:
		server_request_open.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_request_open() -> void:
	if !is_multiplayer_authority():
		return
	# A client asked to open — the loot pile auto-opens for THAT client.
	_do_open(multiplayer.get_remote_sender_id())

# Server only: roll the loot once into a pile here, then tell everyone it's spent.
# open_for_peer is the interacting player, so the pile auto-opens for them (one
# interact both opens the container and its loot — no second click on the pile).
func _do_open(open_for_peer: int = 0) -> void:
	if looted:
		return
	looted = true
	var world = get_tree().get_first_node_in_group("world")
	if world:
		var context := {}
		if _is_elemental() and element != "":
			context["element"] = element
		# New base types use the tiered per-entry table; old v1 types fall back.
		if ItemData.LOOT_TABLES.has(container_type):
			world.spawn_loot(global_position, ItemData.get_loot_table(container_type, tier), context, open_for_peer)
		else:
			world.spawn_container_loot(global_position, container_type, context)
	_broadcast_looted()

# Scope the looted flag to peers who actually have this room loaded (same reason
# as exit_portal — a blanket .rpc() would spam "node not found" at peers who left
# the room and freed it).
func _broadcast_looted() -> void:
	var world = get_tree().get_first_node_in_group("world")
	var room_key := _my_room_key(world)
	if world == null or room_key == "":
		set_looted.rpc()
		return
	var server_id := multiplayer.get_unique_id()
	var recipients := {server_id: true}
	for pid in world.peers_in_room(room_key):
		recipients[pid] = true
	for pid in recipients:
		if pid == server_id:
			set_looted()
		else:
			set_looted.rpc_id(pid)

@rpc("authority", "call_local", "reliable")
func set_looted() -> void:
	looted = true
	# Remember it so a revisit this expedition finds it already emptied. Recorded
	# on every peer (this RPC runs on all room peers), so each restores it locally.
	var id := _container_id()
	if id != "":
		Stats.expedition_looted_containers[id] = true
	_update_visual()

# Which loaded room this container sits in (it can be nested anywhere under the
# room scene), or "" if none — used to scope the looted broadcast.
func _my_room_key(world) -> String:
	if world == null:
		return ""
	for key in world.world_rooms.loaded_rooms:
		var scene = world.world_rooms.loaded_rooms[key].get("scene")
		if scene != null and is_instance_valid(scene) and scene.is_ancestor_of(self):
			return key
	return ""

# Stable per-expedition id: room + this container's node name (unique within a
# hand-placed room). "" until the room is resolvable.
func _container_id() -> String:
	var room_key := _my_room_key(get_tree().get_first_node_in_group("world"))
	return "%s/%s" % [room_key, name] if room_key != "" else ""

func _update_visual() -> void:
	var def: Dictionary = ItemData.CONTAINERS.get(container_type, {})
	if looted:
		color_rect.color = Color(0.22, 0.2, 0.18)
		status_label.text = "%s\n(looted)" % def.get("display_name", container_type)
	elif _is_elemental() and element != "":
		# Elemental node: the element's color + name (e.g. "Fire Mining Node").
		color_rect.color = SpellData.ELEMENTS.get(element, {}).get("color", def.get("color", Color(0.5, 0.4, 0.3)))
		status_label.text = "%s %s" % [element.capitalize(), def.get("display_name", container_type)]
	else:
		# Tier tints the crate (bronze plain, silver pale, gold golden) + labels it.
		color_rect.color = def.get("color", Color(0.5, 0.4, 0.3)) * _tier_tint()
		status_label.text = "%s %s" % [tier.capitalize(), def.get("display_name", container_type)] if ItemData.LOOT_TABLES.has(container_type) else def.get("display_name", container_type)
