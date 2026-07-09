class_name Inventory
extends RefCounted

# width/height are instance properties, not constants, so a bigger backpack
# later is just a different Inventory.new(w, h) swapped in on the player —
# no redesign of this class needed when that ships.
var width: int
var height: int
# Each entry: { "item": Item, "x": int, "y": int } (x,y = top-left cell)
var placements: Array = []
# Multiplies each item type's base max_stack for this container — the stash
# uses 2 so it holds double per cell (see player.gd). 1 = normal.
var stack_multiplier := 1

func _init(_width: int, _height: int) -> void:
	width = _width
	height = _height

func effective_max_stack(type: String) -> int:
	return ItemData.get_max_stack(type) * stack_multiplier

func is_area_free(x: int, y: int, w: int, h: int, ignore_instance_id := "") -> bool:
	if x < 0 or y < 0 or x + w > width or y + h > height:
		return false
	for entry in placements:
		var other: Item = entry["item"]
		if ignore_instance_id != "" and other.instance_id == ignore_instance_id:
			continue
		var other_footprint := ItemData.get_footprint(other.type)
		if _rects_overlap(x, y, w, h, entry["x"], entry["y"], other_footprint.x, other_footprint.y):
			return false
	return true

func _rects_overlap(ax: int, ay: int, aw: int, ah: int, bx: int, by: int, bw: int, bh: int) -> bool:
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by

func find_free_position(w: int, h: int) -> Vector2i:
	for y in range(height - h + 1):
		for x in range(width - w + 1):
			if is_area_free(x, y, w, h):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func can_place_at(item: Item, x: int, y: int) -> bool:
	var footprint := ItemData.get_footprint(item.type)
	return is_area_free(x, y, footprint.x, footprint.y, item.instance_id)

func place_item(item: Item, x: int, y: int) -> bool:
	if !can_place_at(item, x, y):
		return false
	placements.append({"item": item, "x": x, "y": y})
	return true

func move_item(instance_id: String, new_x: int, new_y: int) -> bool:
	for entry in placements:
		if entry["item"].instance_id != instance_id:
			continue
		var footprint := ItemData.get_footprint(entry["item"].type)
		if !is_area_free(new_x, new_y, footprint.x, footprint.y, instance_id):
			return false
		entry["x"] = new_x
		entry["y"] = new_y
		return true
	return false

# Drop within this same container: if the target cell holds a different
# same-type stackable, merge into it (up to the effective max); otherwise just
# move. This is what lets stacks combine when both are already in the stash
# (previously move_item just failed on the occupied cell). Stackables are 1x1,
# so an exact top-left cell match identifies the target stack.
func combine_or_move(instance_id: String, new_x: int, new_y: int) -> bool:
	var dragged: Item = null
	for entry in placements:
		if entry["item"].instance_id == instance_id:
			dragged = entry["item"]
			break
	if dragged == null:
		return false
	if ItemData.is_stackable(dragged.type):
		for entry in placements:
			if entry["item"].instance_id == instance_id:
				continue
			if entry["x"] == new_x and entry["y"] == new_y and entry["item"].type == dragged.type:
				var room: int = effective_max_stack(dragged.type) - entry["item"].quantity
				if room <= 0:
					return false  # target stack full — leave the dragged one put
				var transfer: int = min(room, dragged.quantity)
				entry["item"].quantity += transfer
				dragged.quantity -= transfer
				if dragged.quantity <= 0:
					remove_item(instance_id)
				return true
	return move_item(instance_id, new_x, new_y)

func remove_item(instance_id: String) -> Item:
	for i in placements.size():
		if placements[i]["item"].instance_id == instance_id:
			var item: Item = placements[i]["item"]
			placements.remove_at(i)
			return item
	return null

# Stackable items top up existing same-type stacks with room first, then
# place any remainder in new cells (possibly split across several if the
# remainder is bigger than one stack's max). Non-stackable items just look
# for one free spot. Returns false only once the grid is genuinely full and
# some quantity couldn't be placed anywhere.
func try_stack_or_place(item: Item) -> bool:
	if ItemData.is_stackable(item.type):
		var max_stack: int = effective_max_stack(item.type)
		for entry in placements:
			if item.quantity <= 0:
				break
			var existing: Item = entry["item"]
			if existing.type != item.type:
				continue
			var room: int = max_stack - existing.quantity
			if room <= 0:
				continue
			var transfer: int = min(room, item.quantity)
			existing.quantity += transfer
			item.quantity -= transfer
		while item.quantity > 0:
			var footprint := ItemData.get_footprint(item.type)
			var pos := find_free_position(footprint.x, footprint.y)
			if pos == Vector2i(-1, -1):
				return false
			var place_qty: int = min(item.quantity, max_stack)
			place_item(Item.new(item.type, place_qty), pos.x, pos.y)
			item.quantity -= place_qty
		return true
	var footprint := ItemData.get_footprint(item.type)
	var pos := find_free_position(footprint.x, footprint.y)
	if pos == Vector2i(-1, -1):
		return false
	return place_item(item, pos.x, pos.y)

func to_dict() -> Dictionary:
	var placement_dicts := []
	for entry in placements:
		placement_dicts.append({"x": entry["x"], "y": entry["y"], "item": entry["item"].to_dict()})
	return {"width": width, "height": height, "stack_multiplier": stack_multiplier, "placements": placement_dicts}

static func from_dict(data: Dictionary) -> Inventory:
	var inv := Inventory.new(data.get("width", 4), data.get("height", 3))
	inv.stack_multiplier = data.get("stack_multiplier", 1)
	for p in data.get("placements", []):
		inv.placements.append({"x": p["x"], "y": p["y"], "item": Item.from_dict(p["item"])})
	return inv
