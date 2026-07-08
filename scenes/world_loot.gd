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

# loot_table: Array of {"type": String, "chance": float 0-1, "min": int, "max": int}.
# Each entry rolled independently; everything that hits goes into one shared
# pile (LOOT_PILE_SIZE has room for a handful of distinct stacks). Silently
# spawns nothing if every roll whiffs — no empty pickup left behind.
func roll_and_broadcast_loot(position: Vector2, loot_table: Array) -> void:
	if !world.multiplayer.is_server():
		return
	var pile := Inventory.new(LOOT_PILE_SIZE.x, LOOT_PILE_SIZE.y)
	var dropped_anything := false
	for entry in loot_table:
		if world.rng.randf() > entry["chance"]:
			continue
		var qty: int = world.rng.randi_range(entry["min"], entry["max"])
		if qty <= 0:
			continue
		var item := Item.create(entry["type"], qty)
		# Weapon.new() (inside Item.create()) always defaults element from
		# the generic per-type template (every type defaults to "fire") —
		# an "element" key on the loot entry (see enemy.gd's weapon-drop
		# roll) overrides it to whatever the actual source enemy had.
		if entry.has("element") and item.weapon != null:
			item.weapon.element = entry["element"]
		# Weapon.new() now starts form-less; a weapon-drop entry carries the
		# forms the source enemy actually had (see enemy.gd's die()) so the
		# dropped weapon isn't a blank slate.
		if entry.has("forms") and item.weapon != null:
			item.weapon.forms = (entry["forms"] as Array).duplicate()
		# Weapon.new() otherwise always starts pristine (full charge/
		# durability) — a looted weapon instead comes randomly worn, so it's
		# not a guaranteed like-new upgrade over whatever's already equipped.
		if item.weapon != null:
			item.weapon.durability = world.rng.randf_range(0.2, 1.0) * item.weapon.max_durability
			item.weapon.mana = world.rng.randf_range(0.2, 1.0) * item.weapon.max_mana
		# Gear (Item.create rolled a trait + full durability) — looted gear comes
		# randomly worn too, so a found piece isn't a guaranteed pristine trait.
		if item.max_durability > 0.0:
			item.durability = world.rng.randf_range(0.2, 1.0) * item.max_durability
		if pile.try_stack_or_place(item):
			dropped_anything = true
	if !dropped_anything:
		return
	_spawn_new_pile(position, pile)

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
