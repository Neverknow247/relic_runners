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
const MERGE_RADIUS := 480.0
const MIN_PILE_SEPARATION := 384.0
const SEPARATION_ATTEMPTS := 8

func setup(_world) -> void:
	world = _world

# A killed enemy's loot (its type's ENEMY_LOOT_POOLS pool). "@weapon" resolves to
# the enemy's own weapon via weapon_override {type, element, forms}.
func roll_pool_loot(
	world_pos: Vector2, pool_id: String, rolls_min: int, rolls_max: int, weapon_override: Dictionary
) -> void:
	roll_loot_pool(world_pos, ItemData.ENEMY_LOOT_POOLS.get(pool_id, {}), rolls_min, rolls_max, weapon_override)

# A hand-placed container's loot (its CONTAINERS entry's pool + roll range).
# There's always some chance it just turns up empty (per-container "empty_chance",
# default 0.15) — it's still spent (looted) either way.
func roll_container_loot(world_pos: Vector2, container_type: String, context: Dictionary = {}) -> void:
	if !world.multiplayer.is_server():
		return
	# v1 (old-format) containers only — the new base types (crate/chest/mining_node/…)
	# go through spawn_loot with a LOOT_TABLES[type][tier] table instead (loot_container).
	var c: Dictionary = ItemData.CONTAINERS.get(container_type, {})
	if world.rng.randf() < c.get("empty_chance", 0.15):
		return
	roll_loot_pool(world_pos, c.get("loot", {}), c.get("rolls_min", 1), c.get("rolls_max", 2), {})

# The shared roller (server only): rolls_min..rolls_max independent rolls, each
# landing on a rarity tier (RARITY_DROP_WEIGHTS) then pulling a random item of
# that tier from `pool`. Everything that drops goes into one shared ground pile.
func roll_loot_pool(
	world_pos: Vector2, pool: Dictionary, rolls_min: int, rolls_max: int, weapon_override: Dictionary
) -> void:
	if !world.multiplayer.is_server():
		return
	if pool.is_empty():
		return
	var piles: Array = []
	for r in world.rng.randi_range(rolls_min, rolls_max):
		var rarity := _roll_rarity()
		var tier: Array = pool.get(rarity, [])
		if tier.is_empty():
			continue
		var item_type: String = tier[world.rng.randi_range(0, tier.size() - 1)]
		var qty_range := ItemData.get_drop_qty(item_type)
		var qty: int = world.rng.randi_range(qty_range[0], qty_range[1])
		if qty <= 0:
			continue
		var item := _make_loot_item(item_type, qty, weapon_override, rarity)
		if item != null:
			_place_spilling(piles, item, LOOT_PILE_SIZE)
	_spawn_piles(world_pos, piles)

# Per-entry-chance loot table (ItemData.LOOT_TABLES). Each entry is an independent
# roll; on a hit it resolves a group/item/@token to an item and drops it. `context`
# supplies the dead enemy's identity for the @tokens:
#   {"element": String, "weapon": {type,element,forms}, "rarity": String (tier rarity)}
# Chests pass {} (they use no @tokens). Server-only, like the rest of loot.
func roll_loot_table(world_pos: Vector2, table: Array, context: Dictionary, open_for_peer: int = 0) -> void:
	if !world.multiplayer.is_server():
		return
	if table.is_empty():
		return
	var piles: Array = []
	var chance_mult: float = float(context.get("chance_mult", 1.0))
	for entry in table:
		var chance := int(round(float(entry.get("chance", 100)) * chance_mult))
		if world.rng.randi_range(1, 100) > chance:
			continue
		var item := _resolve_entry(entry, context)
		if item != null:
			_place_spilling(piles, item, LOOT_PILE_SIZE)
	_spawn_piles(world_pos, piles, open_for_peer)

# Resolves one loot entry (group / specific item / @token) to a built Item, or null.
func _resolve_entry(entry: Dictionary, context: Dictionary) -> Item:
	var src: String = entry.get("src", "")
	var item_type := ""
	var weapon_override := {}
	var rarity := "common"
	match src:
		"@weapon":
			if (context.get("weapon", {}) as Dictionary).get("type", "") == "":
				return null
			item_type = "@weapon"
			weapon_override = context["weapon"]
			rarity = context.get("rarity", "common")
		"@crystal":
			var el: String = context.get("element", "")
			if el == "":
				return null
			item_type = "crystal_" + el
			rarity = ItemData.rarity_of_type(item_type)
		"@dust":
			var eld: String = context.get("element", "")
			if eld == "":
				return null
			item_type = eld + "_dust"
			rarity = ItemData.rarity_of_type(item_type)
		"@gear":
			var gear: Array = ItemData.GEAR_DROP_TYPES
			item_type = gear[world.rng.randi_range(0, gear.size() - 1)]
			rarity = context.get("rarity", "common")
		_:
			item_type = _pick_from_group(src) if ItemData.LOOT_GROUPS.has(src) else src
			if item_type == "" or not ItemData.ITEMS.has(item_type):
				return null
			rarity = ItemData.rarity_of_type(item_type)
	# Optional explicit rarity (chests use it to drop, e.g., a rare weapon since they
	# have no enemy tier to inherit). Only affects weapons/gear; ignored otherwise.
	if entry.has("rarity"):
		rarity = entry["rarity"]
	# Quantity: entry override, else the item's own drop range (@weapon is always 1).
	var qty := 1
	if entry.has("qty"):
		var band: Array = entry["qty"]
		qty = world.rng.randi_range(int(band[0]), int(band[1]))
	elif item_type != "@weapon":
		var dq := ItemData.get_drop_qty(item_type)
		qty = world.rng.randi_range(dq[0], dq[1])
	if qty <= 0:
		return null
	return _make_loot_item(item_type, qty, weapon_override, rarity)

# Weighted pick of one item from a named group — rarer items appear less often.
func _pick_from_group(group_name: String) -> String:
	var items: Array = ItemData.LOOT_GROUPS.get(group_name, [])
	if items.is_empty():
		return ""
	var total := 0
	for it in items:
		total += int(ItemData.RARITY_DROP_WEIGHTS.get(ItemData.rarity_of_type(it), 1))
	var roll: int = world.rng.randi_range(1, max(1, total))
	var cum := 0
	for it in items:
		cum += int(ItemData.RARITY_DROP_WEIGHTS.get(ItemData.rarity_of_type(it), 1))
		if roll <= cum:
			return it
	return items[0]

# Fishing: roll ONE catch from a spot's pool (server only). Returns
# {"type": String, "rarity": int} — the rarity index scales the reel minigame's
# difficulty — or {} if the spot has no loot at all. A rolled-but-empty tier
# falls to the nearest lower tier (then upward) so a cast always lands something.
func roll_fishing_catch(spot_type: String) -> Dictionary:
	if !world.multiplayer.is_server():
		return {}
	var pool: Dictionary = ItemData.FISHING_SPOTS.get(spot_type, {}).get("loot", {})
	if pool.is_empty():
		return {}
	var start: int = ItemData.RARITY_ORDER.find(_roll_rarity())
	for i in range(start, -1, -1):
		var picked := _pick_from_tier(pool, i)
		if picked != "":
			return {"type": picked, "rarity": i}
	for i in range(start + 1, ItemData.RARITY_ORDER.size()):
		var picked := _pick_from_tier(pool, i)
		if picked != "":
			return {"type": picked, "rarity": i}
	return {}

func _pick_from_tier(pool: Dictionary, tier_index: int) -> String:
	var tier: Array = pool.get(ItemData.RARITY_ORDER[tier_index], [])
	if tier.is_empty():
		return ""
	return tier[world.rng.randi_range(0, tier.size() - 1)]

# Spawn a single specific item into a ground pile here (server only) — used for a
# landed fishing catch, where the exact item was already rolled.
func spawn_single_item(world_pos: Vector2, item_type: String, qty: int) -> void:
	if !world.multiplayer.is_server():
		return
	var item := _make_loot_item(item_type, qty, {})
	if item == null:
		return
	var pile := Inventory.new(LOOT_PILE_SIZE.x, LOOT_PILE_SIZE.y)
	if !pile.try_stack_or_place(item):
		return
	_spawn_new_pile(world_pos, pile)

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
func _make_loot_item(item_type: String, qty: int, weapon_override: Dictionary, rarity := "common") -> Item:
	var item: Item
	if item_type == "@weapon":
		if weapon_override.get("type", "") == "":
			return null
		# The dropped weapon takes the tier it rolled from — that's what drives its
		# Attack + crit stats (see Weapon._init / ItemData.WEAPON_*_BY_RARITY).
		item = Item.create(weapon_override["type"], 1, rarity)
		if item.weapon != null:
			item.weapon.element = weapon_override.get("element", item.weapon.element)
			item.weapon.forms = (weapon_override.get("forms", []) as Array).duplicate()
	else:
		item = Item.create(item_type, qty, rarity)
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
func drop_item(world_pos: Vector2, item_dict: Dictionary) -> void:
	var item := Item.from_dict(item_dict)
	for pickup_id in active_pickups.keys():
		var entry: Dictionary = active_pickups[pickup_id]
		if entry["position"].distance_to(world_pos) > MERGE_RADIUS:
			continue
		if entry["inventory"].try_stack_or_place(item):
			world.broadcast_item_added.rpc(pickup_id, item.to_dict())
			return
	var piles: Array = []
	_place_spilling(piles, item, LOOT_PILE_SIZE)
	_spawn_piles(world_pos, piles)

# A dying player's whole backpack + contents, dropped as one dedicated pile
# — unlike drop_item(), this never tries to merge into some nearby unrelated
# pile; a death bag is always its own thing, right where they fell.
# A full loadout can need more than one bag's worth of cells, so extras spill into
# additional bags dropped beside it instead of being silently deleted.
func drop_death_bag(world_pos: Vector2, items: Array) -> void:
	var piles: Array = []
	for item_dict in items:
		_place_spilling(piles, Item.from_dict(item_dict), DEATH_BAG_SIZE)
	_spawn_piles(world_pos, piles)

# Puts `item` into the last pile in `piles`, opening a fresh pile of `size` when it
# doesn't fit — so a full pile never silently swallows an item. A stackable that only
# partly fits keeps its remainder in item.quantity (try_stack_or_place decrements as
# it stacks), and that remainder goes into the new pile.
func _place_spilling(piles: Array, item: Item, size: Vector2i) -> void:
	if !piles.is_empty() and piles[-1].try_stack_or_place(item):
		return
	# A huge stack can need several fresh piles: each one keeps whatever it took
	# (even when try_stack_or_place reports false for the leftover) and the rest
	# moves on to the next. Bounded so a bad item can't loop forever.
	for _attempt in 64:
		var pile := Inventory.new(size.x, size.y)
		var placed_all := pile.try_stack_or_place(item)
		if pile.placements.is_empty():
			push_warning("world_loot: item '%s' doesn't fit in an empty %s pile; dropped" % [item.type, size])
			return
		piles.append(pile)
		if placed_all:
			return
	push_warning("world_loot: gave up spilling '%s' (qty %d left)" % [item.type, item.quantity])

# Spawns every non-empty pile near world_pos (each nudged apart by
# _spawn_new_pile). Only the first auto-opens for open_for_peer.
func _spawn_piles(world_pos: Vector2, piles: Array, open_for_peer: int = 0) -> void:
	var first := true
	for pile in piles:
		if pile.placements.is_empty():
			continue
		_spawn_new_pile(world_pos, pile, open_for_peer if first else 0)
		first = false

func _spawn_new_pile(desired_position: Vector2, pile: Inventory, open_for_peer: int = 0) -> void:
	var spawn_pos := _find_non_overlapping_position(desired_position)
	var pickup_id := "%d_%d" % [Time.get_ticks_usec(), randi()]
	active_pickups[pickup_id] = {"inventory": pile, "position": spawn_pos}
	# open_for_peer (0 = nobody) auto-opens the new pile's panel for that peer — set by
	# a container open so one interact both spawns and opens its loot (enemy drops pass 0).
	world.broadcast_loot_pickup_spawned.rpc(pickup_id, spawn_pos, pile.to_dict(), open_for_peer)

# A pile landing on a door/portal traps the player: interacting there opens the
# bag instead of the door. So piles keep clear of interactables too, not just
# each other.
const DOOR_AVOID_RADIUS := 448.0

func _find_non_overlapping_position(desired: Vector2) -> Vector2:
	var doors := _interactable_positions()
	if !_position_blocked(desired, doors):
		return desired
	# Spiral outward at growing radii (far enough to clear a door) until a clear
	# spot is found; best-effort fallback if everything nearby is crowded.
	for attempt in SEPARATION_ATTEMPTS:
		var angle := TAU * attempt / float(SEPARATION_ATTEMPTS)
		var nudge := DOOR_AVOID_RADIUS + 128.0 + attempt * 128.0
		var candidate := desired + Vector2.RIGHT.rotated(angle) * nudge
		if !_position_blocked(candidate, doors):
			return candidate
	return desired + Vector2.RIGHT * (DOOR_AVOID_RADIUS + 128.0)

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

# Ends an expedition's ground loot (death bags, drops) but keeps piles players
# left lying around in the hub, which used to vanish whenever a run launched.
func clear_expedition_pickups() -> void:
	for pickup_id in active_pickups.keys():
		var key: String = world.world_rooms.room_key_at(active_pickups[pickup_id]["position"])
		if !key.begins_with("hub/"):
			active_pickups.erase(pickup_id)

# Server only: re-send every pile in room_key to peer_id. A peer frees its local
# pile nodes on every room change (world_rooms.load_location_locally), and piles
# are otherwise only broadcast once at drop time, so anything dropped before
# they arrived (a teammate's death bag) used to be invisible to them.
func send_room_pickups_to(peer_id: int, room_key: String) -> void:
	if !world.multiplayer.is_server():
		return
	for pickup_id in active_pickups:
		var entry: Dictionary = active_pickups[pickup_id]
		if world.world_rooms.room_key_at(entry["position"]) != room_key:
			continue
		if peer_id == world.multiplayer.get_unique_id():
			world.broadcast_loot_pickup_spawned(pickup_id, entry["position"], entry["inventory"].to_dict(), 0)
		else:
			world.broadcast_loot_pickup_spawned.rpc_id(peer_id, pickup_id, entry["position"], entry["inventory"].to_dict(), 0)
