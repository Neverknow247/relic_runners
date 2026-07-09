extends Node

var world

# pickup_id -> { "inventory": Inventory, "position": Vector2 }. Server-side
# only — clients never read this directly, only the local display mirror
# each loot_pickup.gd node keeps. Position is tracked here (not just on the
# client-side node) so drop_item() can do proximity checks against every
# active pile without needing to ask any client where things are.
var active_pickups: Dictionary = {}

# 4x3 (matches the starter backpack's own size) rather than the old 3x2 —
# a cloak alone is a 2x3 footprint, so the old 6-cell pile could no longer
# even guarantee holding one gear drop by itself once gear joined the table.
const LOOT_PILE_SIZE := Vector2i(4, 3)

# A death bag needs room for the dropped backpack item itself (2x2) plus
# everything that was inside it (up to the backpack's own capacity), so it
# gets its own larger, fixed size rather than reusing LOOT_PILE_SIZE.
const DEATH_BAG_SIZE := Vector2i(6, 6)

# How close a drop has to land to an existing pile to merge into it instead
# of spawning a new one, and how far apart two separate piles must end up
# so their ground markers never fully overlap.
const MERGE_RADIUS := 120.0
const MIN_PILE_SEPARATION := 96.0
const SEPARATION_ATTEMPTS := 8

func setup(_world) -> void:
	world = _world

# Rolls a killed enemy's loot: rolls_min..rolls_max independent rolls, each
# landing on a rarity tier (RARITY_DROP_WEIGHTS) then pulling a random item of
# that tier from the enemy type's pool (ItemData.ENEMY_LOOT_POOLS[pool_id]).
# "@weapon" resolves to the enemy's own weapon via weapon_override
# {type, element, forms}. Everything that drops goes into one shared pile.
func roll_pool_loot(
	position: Vector2, pool_id: String, rolls_min: int, rolls_max: int, weapon_override: Dictionary
) -> void:
	if !world.multiplayer.is_server():
		return
	var pool: Dictionary = ItemData.ENEMY_LOOT_POOLS.get(pool_id, {})
	if pool.is_empty():
		return
	var pile := Inventory.new(LOOT_PILE_SIZE.x, LOOT_PILE_SIZE.y)
	var dropped_anything := false
	for r in world.rng.randi_range(rolls_min, rolls_max):
		var tier: Array = pool.get(_roll_rarity(), [])
		if tier.is_empty():
			continue
		var item_type: String = tier[world.rng.randi_range(0, tier.size() - 1)]
		var qty_range := ItemData.get_drop_qty(item_type)
		var qty: int = world.rng.randi_range(qty_range[0], qty_range[1])
		if qty <= 0:
			continue
		var item := _make_loot_item(item_type, qty, weapon_override)
		if item != null and pile.try_stack_or_place(item):
			dropped_anything = true
	if !dropped_anything:
		return
	_spawn_new_pile(position, pile)

# Picks one rarity tier by the weighted drop odds.
func _roll_rarity() -> String:
	var roll: int = world.rng.randi_range(1, 100)
	var cumulative := 0
	for rarity in ItemData.RARITY_ORDER:
		cumulative += ItemData.RARITY_DROP_WEIGHTS.get(rarity, 0)
		if roll <= cumulative:
			return rarity
	return "common"

# Builds a loot item, resolving the "@weapon" marker to the enemy's own weapon
# (its element/forms) and applying the random "worn" durability/mana looted gear
# and weapons come with. Returns null if a weapon was rolled but the enemy had
# none.
func _make_loot_item(item_type: String, qty: int, weapon_override: Dictionary) -> Item:
	var item: Item
	if item_type == "@weapon":
		if weapon_override.get("type", "") == "":
			return null
		item = Item.create(weapon_override["type"], 1)
		if item.weapon != null:
			item.weapon.element = weapon_override.get("element", item.weapon.element)
			item.weapon.forms = (weapon_override.get("forms", []) as Array).duplicate()
	else:
		item = Item.create(item_type, qty)
	# Looted weapons/gear come randomly worn, not pristine.
	if item.weapon != null:
		item.weapon.durability = world.rng.randf_range(0.2, 1.0) * item.weapon.max_durability
		item.weapon.mana = world.rng.randf_range(0.2, 1.0) * item.weapon.max_mana
	if item.max_durability > 0.0:
		item.durability = world.rng.randf_range(0.2, 1.0) * item.max_durability
	return item

# Called (server-side only, already gated by the caller in world.gd) when a
# player drops an item. Merges into whichever nearby pile has room first;
# if none does (or none exist nearby), spawns a fresh pile nudged away from
# any existing one so their ground markers don't land exactly on top of
# each other.
func drop_item(position: Vector2, item_dict: Dictionary) -> void:
	var item := Item.from_dict(item_dict)
	for pickup_id in active_pickups.keys():
		var entry: Dictionary = active_pickups[pickup_id]
		if entry["position"].distance_to(position) > MERGE_RADIUS:
			continue
		if entry["inventory"].try_stack_or_place(item):
			world.broadcast_item_added.rpc(pickup_id, item.to_dict())
			return
	var pile := Inventory.new(LOOT_PILE_SIZE.x, LOOT_PILE_SIZE.y)
	pile.try_stack_or_place(item)
	_spawn_new_pile(position, pile)

# A dying player's whole backpack + contents, dropped as one dedicated pile
# — unlike drop_item(), this never tries to merge into some nearby unrelated
# pile; a death bag is always its own thing, right where they fell.
func drop_death_bag(position: Vector2, items: Array) -> void:
	var pile := Inventory.new(DEATH_BAG_SIZE.x, DEATH_BAG_SIZE.y)
	for item_dict in items:
		pile.try_stack_or_place(Item.from_dict(item_dict))
	if pile.placements.is_empty():
		return
	_spawn_new_pile(position, pile)

func _spawn_new_pile(desired_position: Vector2, pile: Inventory) -> void:
	var spawn_pos := _find_non_overlapping_position(desired_position)
	var pickup_id := "%d_%d" % [Time.get_ticks_usec(), randi()]
	active_pickups[pickup_id] = {"inventory": pile, "position": spawn_pos}
	world.broadcast_loot_pickup_spawned.rpc(pickup_id, spawn_pos, pile.to_dict())

# A pile landing on a door/portal traps the player: interacting there opens the
# bag instead of the door. So piles keep clear of interactables too, not just
# each other.
const DOOR_AVOID_RADIUS := 112.0

func _find_non_overlapping_position(desired: Vector2) -> Vector2:
	var doors := _interactable_positions()
	if !_position_blocked(desired, doors):
		return desired
	# Spiral outward at growing radii (far enough to clear a door) until a clear
	# spot is found; best-effort fallback if everything nearby is crowded.
	for attempt in SEPARATION_ATTEMPTS:
		var angle := TAU * attempt / float(SEPARATION_ATTEMPTS)
		var nudge := DOOR_AVOID_RADIUS + 32.0 + attempt * 32.0
		var candidate := desired + Vector2.RIGHT.rotated(angle) * nudge
		if !_position_blocked(candidate, doors):
			return candidate
	return desired + Vector2.RIGHT * (DOOR_AVOID_RADIUS + 32.0)

func _position_blocked(candidate: Vector2, doors: Array) -> bool:
	for pickup_id in active_pickups.keys():
		if active_pickups[pickup_id]["position"].distance_to(candidate) < MIN_PILE_SEPARATION:
			return true
	for door_pos in doors:
		if candidate.distance_to(door_pos) < DOOR_AVOID_RADIUS:
			return true
	return false

# Global positions of every door/portal interactable across the server's loaded
# rooms (Area2D nodes under each room's "doors" node). Rooms in other locations
# are far away in world space, so only the pile's own room actually matters.
func _interactable_positions() -> Array:
	var positions: Array = []
	if world.world_rooms == null:
		return positions
	for room_key in world.world_rooms.loaded_rooms:
		var scene = world.world_rooms.loaded_rooms[room_key]["scene"]
		if scene == null or !is_instance_valid(scene):
			continue
		var doors = scene.get_node_or_null("doors")
		if doors != null:
			_collect_area_positions(doors, positions)
	return positions

func _collect_area_positions(node: Node, positions: Array) -> void:
	for child in node.get_children():
		if child is Area2D:
			positions.append(child.global_position)
		_collect_area_positions(child, positions)

# Removes the item from the server's pile model and reports it back to
# world.gd so it can broadcast the result. Returns null if the pile or item
# is already gone (lost a claim race, or the pile was cleared out from under
# it by an expedition/hub transition).
func claim_item(pickup_id: String, item_instance_id: String) -> Item:
	if !active_pickups.has(pickup_id):
		return null
	var pile: Inventory = active_pickups[pickup_id]["inventory"]
	var removed := pile.remove_item(item_instance_id)
	if removed != null and pile.placements.is_empty():
		active_pickups.erase(pickup_id)
	return removed

func clear_active_pickups() -> void:
	active_pickups.clear()
