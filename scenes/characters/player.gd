extends CharacterBody2D

var stats = Stats
var rand = RandomNumberGenerator.new()
var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

var spell_input_sequence: Array[int] = []

const DamageNumberScene := preload("res://scenes/effects/damage_number.tscn")

func _spawn_damage_number(amount: float, color: Color, is_crit: bool = false) -> void:
	var num = DamageNumberScene.instantiate()
	get_tree().current_scene.add_child(num)
	num.global_position = global_position + Vector2(0, -32)
	num.setup(amount, color, is_crit)

@onready var player_camera: Camera2D = $player_camera
@onready var spell_list_ui = $player_camera/spell_list_ui
@onready var visual_root: Node2D = $visual_root
@onready var legs: Sprite2D = $visual_root/legs
@onready var sprite: Sprite2D = $visual_root/sprite
@onready var legs_animation_player: AnimationPlayer = $legs_animation_player
@onready var body_animation_player: AnimationPlayer = $body_animation_player
@onready var hurtbox: Hurtbox = $hurtbox
@onready var health_ui = $player_camera/health_ui
@onready var mana_ui = $player_camera/mana_ui
@onready var inventory_ui = $player_camera/inventory_ui
@onready var downed_ui = $player_camera/downed_ui
@onready var quick_slot_hud = $player_camera/quick_slot_hud
@onready var workbench_ui = $player_camera/workbench_ui
@onready var crafting_ui = $player_camera/crafting_ui
@onready var expedition_kit_ui = $player_camera/expedition_kit_ui

# Legs and the upper body are animated and rotated completely
# independently: legs always reflect movement (walk/idle), even mid-attack,
# while the upper body (sprite) rotates to face aim and plays its own
# idle/attack animation. visual_root itself never rotates — it's just a
# grouping node — so each of its two children can spin on their own without
# affecting the other.
@export var network_anim := "idle"
@export var network_body_anim := "idle"
# Last replicated anim we actually applied on a REMOTE copy (see _process).
# Tracked separately from AnimationPlayer.current_animation because a
# non-looping anim (prone/dead/attack) clears current_animation to "" the
# moment it finishes — comparing against that made a held "prone" restart
# every frame (the remote-view prone flicker). Only replay when the commanded
# anim actually changes.
var _applied_legs_anim := ""
var _applied_body_anim := ""
@export var network_rotation := 0.0
@export var network_legs_rotation := 0.0
# Replicated combat identity (weapon type + element) — the matchup multiplier
# needs the DEFENDER's weapon/element, but a remote peer doesn't have this
# player's equipped Weapon (gear/weapons aren't networked). Set on the
# authority from the equipped weapon (see persist_weapon_slots) and read by
# _on_hurtbox_hurt so every peer computes the same damage number. "default"
# when unarmed (neutral, no matchup bonus — same as a broken weapon).
@export var network_weapon_type := "default"
@export var network_element := "default"
var aim_direction := Vector2.DOWN
var is_attacking := false

# Base health before gear traits. max_health is recomputed from this by
# _refresh_gear_effects() (belt_vitality adds +10%).
const BASE_MAX_HEALTH := 100.0
@export var max_health := 100.0
# Replicated cloak-stealth flags (see player.tscn's SceneReplicationConfig).
# Set on the authority from the equipped cloak's trait; the enemy AI (on the
# server) reads a target player's copy of these — gear itself isn't networked,
# so these two bits are how a remote player's cloak reaches the enemy.
@export var stealth_silent := false
@export var stealth_unseen_still := false
# Flat durability each equipped gear piece loses per hit taken.
const GEAR_DURABILITY_COST_PER_HIT := 4.0
var health := max_health:
	set(value):
		health = value
		if health_ui:
			health_ui.update_health(health, max_health, shield)
# Shield (from an equipped Blessed Band) absorbs damage before health. Each
# Blessed Band grants BLESSED_BAND_SHIELD; when the shield is fully spent the
# band(s) break into scrap (see take_damage / _break_blessed_bands).
var shield := 0.0:
	set(value):
		shield = value
		if health_ui:
			health_ui.update_health(health, max_health, shield)
var max_shield := 0.0
const BLESSED_BAND_SHIELD := 50.0
# ALIVE -> DOWNED (prone, 60s countdown, frozen) -> DYING (brief "dead" anim
# pause) -> back to ALIVE once _finish_death() resets everything and sends
# you to hub. Movement/attack input is ignored whenever this isn't ALIVE.
enum DeathState { ALIVE, DOWNED, DYING }
var death_state: DeathState = DeathState.ALIVE
var downed_timer := 0.0
const DOWNED_DURATION := 60.0
const DEATH_ANIM_DELAY := 1.0
# Holding "interact" while downed skips the rest of the 60s wait — fills over
# GIVE_UP_HOLD_DURATION seconds, then instantly forces downed_timer to 0
# (see _physics_process), reusing the exact same DOWNED -> DYING transition
# rather than a separate "instant kill" code path.
var give_up_hold_timer := 0.0
const GIVE_UP_HOLD_DURATION := 3.0

# Co-op revive: an ALIVE ally holds interact next to a DOWNED player to revive
# them. Base is a slow revive to a sliver of health; if the REVIVER is carrying
# Phoenix Ash it's consumed for a much faster revive to more health. The downed
# player can't revive themselves.
const REVIVE_RANGE := 120.0
const REVIVE_TIME_BASE := 5.0
const REVIVE_TIME_ASH := 1.5
const REVIVE_HP_BASE := 25.0
const REVIVE_HP_ASH := 50.0
var _revive_progress := 0.0

# Fresh characters start unarmed — a weapon is only ever granted by picking
# the Starter Kit at an expedition door (see apply_starter_kit()); Custom Kit
# can deliberately head out with both slots empty.
var weapon_slots: Array[Weapon] = [null, null]
var active_slot: int = 0
var open_loot_pickup = null
var open_chest = null
var open_workbench = null
var open_overflow_chest = null

# Personal hub stash — 3 tabs, 42 slots each (7x6). Purely local/per-player
# data, same as the rest of the inventory system: never shared, never
# networked, since it's tied to this player's own save file. Two players
# opening the "same" physical chest each just see their own stash, not a
# shared container.
const STASH_TAB_SIZE := Vector2i(7, 6)
const STASH_TAB_COUNT := 4
# Stash cells hold double a normal stack (see Inventory.stack_multiplier).
const STASH_STACK_MULTIPLIER := 2
var stash_tabs: Array[Inventory] = []

# Overflow chest — a per-player safety container for the "Starter Kit" bank
# (see apply_starter_kit()). When a kit-strip can't fit everything into the
# stash, the remainder lands here so nothing is ever lost. Sized larger than
# any possible single carry (backpack + gear + weapons + quick slots) so the
# bank always succeeds. Take-only in the UI (you can pull items out, never put
# them in — see inventory_grid.gd), and while it holds anything the overflow
# chest appears in the hub and the expedition doors refuse to start (see
# overflow_chest.gd / expedition_door.gd) — it exists purely so you deal with
# the overflow rather than accumulate it.
const OVERFLOW_SIZE := Vector2i(8, 8)
var overflow := Inventory.new(OVERFLOW_SIZE.x, OVERFLOW_SIZE.y)

# Crafting materials (element crystals + form stones), banked from the stash's
# Materials tab: a flat per-type count that stacks infinitely (no grid). The
# weapon workbench consumes from here first (see workbench_* / consume_material).
var materials: Dictionary = {}

# Backpack is unequippable now (like belt/cloak) — this is what you're left
# with when equipped_backpack is null (fresh character, unequipped, or after
# death), same "equip nothing" idea belt/cloak already had, just with a
# minimal-but-nonzero grid instead of literally zero slots.
const DEFAULT_INVENTORY_SIZE := Vector2i(4, 1)

# Inventory's width/height are instance properties (not baked into the
# class), so a bigger backpack is just a different Inventory.new(w, h)
# swapped in — see _resize_inventory_for_backpack(). 4x3 here is only a
# harmless fallback for the moment before _ready() derives the real size
# from whichever backpack ends up equipped.
var inventory := Inventory.new(4, 3)

# Gear: null means nothing equipped in that slot. equipped_backpack always
# gets defaulted to backpack_basic in _ready() for a fresh character — you
# can't functionally have zero backpack (nowhere to put anything, including
# a replacement backpack), so unequip-to-grid is deliberately not offered
# for it (see EquipmentSlot._get_drag_data) — only equip-a-different-one is.
var equipped_backpack: Item = null
var equipped_belt: Item = null
var equipped_body: Item = null
# Simple attribute-only gear slots beyond backpack/belt/cloak (which keep their
# own vars for their special mechanics — inventory size / quick slots). Stored
# generically as slot_type -> Item. ring_1 and ring_2 are two slots that both
# accept a "ring" item. No lootable items fill these yet — the slots exist in the
# equipment UI and persist, ready for gear to be added later.
const EXTRA_GEAR_SLOTS := ["hat", "necklace", "pants", "boots", "ring_1", "ring_2"]
var equipped_gear: Dictionary = {}

# Quick slots a belt provides — usable items only (health_potion,
# mana_crystal, ...), used with the quick_slot_1/quick_slot_2 keys without
# opening the inventory at all (see use_quick_slot()). Sized to whatever the
# currently-equipped belt grants (ItemData's provides_quick_slots — a common
# belt grants 1, a rarer future belt could grant more) — see
# _resize_quick_slots_for_belt(), called any time the belt changes.
var quick_slots: Array[Item] = []

var state = move_state
var has_dash = true
var dash_input_axis

var default_max_velocity = 300
var default_acceleration = 1500
var friction = 1500

var max_velocity = default_max_velocity
var acceleration = default_acceleration

var attack_locked := false
@export var attack_cooldown := 0.35
var attack_timer := 0.0

@export var controller_aim_deadzone := 0.25
var using_controller_aim := false

func check_weapon_swap():
	if Input.is_action_just_pressed("swap_weapon"):
		swap_to_weapon_slot(1 - active_slot)

func check_quick_slot_input():
	if Input.is_action_just_pressed("quick_slot_1"):
		use_quick_slot(0)
	elif Input.is_action_just_pressed("quick_slot_2"):
		use_quick_slot(1)

# Shared by the swap_weapon key and the inventory UI's clickable weapon
# equipment slots, so both stay in sync with a single source of truth.
func swap_to_weapon_slot(slot: int) -> void:
	if active_slot == slot:
		return
	active_slot = slot
	spell_input_sequence.clear()
	# Refresh the replicated combat identity for the newly-active weapon.
	persist_weapon_slots()
	refresh_spell_ui()
	refresh_mana_ui()
	inventory_ui.refresh()

# Weapon mana is per-weapon-instance, not per-player, so the HUD has to be
# re-pointed at whichever weapon is currently active every time that
# changes (swap, equip) or its mana changes (every cast) — there's no
# automatic setter-driven push the way player.health has, since Weapon is a
# plain RefCounted, not a Node property.
func refresh_mana_ui() -> void:
	var equipped := get_equipped_weapon()
	if equipped == null:
		mana_ui.update_mana(0.0, 0.0)
		return
	mana_ui.update_mana(equipped.mana, equipped.max_mana)

func check_inventory_toggle():
	if Input.is_action_just_pressed("toggle_inventory"):
		if inventory_ui.visible:
			close_inventory_if_open()
		else:
			inventory_ui.visible = true

# Shared by Tab (check_inventory_toggle above) and Esc (world.gd's
# _unhandled_input, which closes the inventory instead of opening the esc
# menu when it's the thing currently open) — both need the exact same
# teardown, not just flipping visibility off.
func close_inventory_if_open() -> bool:
	if !inventory_ui.visible:
		return false
	inventory_ui.visible = false
	# close_loot_panel() (not a raw inventory_ui.hide_loot_panel() call) so
	# open_loot_pickup and that pickup's own panel_open flag actually reset
	# too — otherwise the pickup thinks its panel is still open, and the
	# next interact press on it would try to close an already-closed panel
	# instead of reopening it.
	close_loot_panel()
	close_stash_panel()
	close_overflow_panel()
	# The workbench panel rides alongside the inventory (see
	# open_workbench_panel) — tear it (and the interactable's panel_open flag)
	# down too, same reasoning as close_stash_panel above.
	close_workbench_panel()
	close_crafting_panel()
	# CanvasLayer.visible only stops the whole layer from drawing — it
	# doesn't reset state on anything inside it, so a still-open right-click
	# context menu inside player_grid would otherwise silently persist and
	# reappear exactly as it was next time the panel opens. refresh()
	# already closes it as a side effect.
	inventory_ui.refresh()
	return true

func get_equipped_weapon() -> Weapon:
	return weapon_slots[active_slot]

# Used by world interactables (loot_pickup.gd, chest.gd) before opening a
# panel — check_inventory_toggle() (the only thing that can close a panel
# via Tab) stops running entirely once death_state leaves ALIVE, so without
# this guard a well-timed interact press right as you go down could open a
# panel with no way to ever close it again.
func is_alive() -> bool:
	return death_state == DeathState.ALIVE

# --- Expedition kit selection --------------------------------------------
# Interacting with an expedition door opens a Starter/Custom prompt (see
# expedition_door.gd -> prompt_expedition_kit()); the chosen kit is applied
# here, locally, right before the expedition actually starts. This replaces
# the old weapon-shrine + auto-grant-if-unarmed flow entirely — the kit choice
# now fully owns what loadout you walk in with.

# Which kit this player committed to at the door, applied only at travel time
# (apply_pending_kit, from world.gd's leaving-hub edge) so a cancelled start
# never reshuffles the loadout. "" = nothing pending.
var pending_kit := ""

func prompt_expedition_kit(expedition_id: String) -> void:
	expedition_kit_ui.open(self, expedition_id)

# Called by expedition_kit_ui when the player picks Starter/Custom. Records the
# choice and tells the server they've answered — but does NOT apply it yet (see
# apply_pending_kit, run at actual travel time).
func answer_expedition_kit(kit: String) -> void:
	pending_kit = kit
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.report_kit_answer()

# Player backed out — aborts the whole party start for everyone.
func cancel_expedition_kit() -> void:
	pending_kit = ""
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.report_kit_cancel()

# Server told everyone the start was cancelled — drop our choice and close the
# popup if it's still up.
func hide_kit_prompt() -> void:
	pending_kit = ""
	expedition_kit_ui.force_close()

# Applied at the moment of travel (world.gd's leaving-hub edge), not on click.
func apply_pending_kit() -> void:
	if pending_kit == "starter":
		apply_starter_kit()
	elif pending_kit == "custom":
		apply_custom_kit()
	pending_kit = ""

const STARTER_KIT_WEAPONS := ["tome", "orb", "wand"]
const STARTER_KIT_ELEMENTS := ["fire", "holy", "air"]

# Custom Kit: go in with exactly what's currently carried — even an empty
# weapon slot (attack_check() already no-ops when unarmed). Nothing to do.
func apply_custom_kit() -> void:
	pass

# Starter Kit: bank everything currently carried into the stash (overflow
# chest for the remainder), then set up a fixed fresh loadout — a random
# weapon (with its starter form + a random element), a common backpack, and
# 2 health potions + 2 mana crystals inside it.
func apply_starter_kit() -> void:
	# 1. Collect every carried item before touching anything.
	var carried: Array[Item] = []
	for entry in inventory.placements:
		carried.append(entry["item"])
	for weapon in weapon_slots:
		if weapon != null:
			carried.append(_wrap_weapon_as_item(weapon))
	for slot_type in (["backpack", "belt", "body"] + EXTRA_GEAR_SLOTS):
		var gear: Item = get_equipped(slot_type)
		if gear != null:
			carried.append(gear)
	for qs in quick_slots:
		if qs != null:
			carried.append(qs)

	# 2. Reset the loadout to empty (in-place so the typed arrays keep their
	# element types).
	weapon_slots[0] = null
	weapon_slots[1] = null
	equipped_backpack = null
	equipped_belt = null
	equipped_body = null
	equipped_gear.clear()
	quick_slots.clear()
	inventory = Inventory.new(DEFAULT_INVENTORY_SIZE.x, DEFAULT_INVENTORY_SIZE.y)

	# 3. Bank each collected item: stash first, overflow chest for the rest.
	for item in carried:
		if !_bank_item_to_stash(item, 0):
			overflow.try_stack_or_place(item)

	# 4. Build the fixed starter loadout.
	var backpack := Item.create("backpack_basic", 1)
	equipped_backpack = backpack
	_resize_inventory_for_backpack(backpack)
	inventory.try_stack_or_place(Item.new("health_potion", 2))
	inventory.try_stack_or_place(Item.new("mana_crystal", 2))
	var weapon_type: String = STARTER_KIT_WEAPONS.pick_random()
	var weapon := Weapon.new(weapon_type)
	weapon.attach_form(SpellData.get_starter_form(weapon_type))
	weapon.element = STARTER_KIT_ELEMENTS.pick_random()
	weapon_slots[active_slot] = weapon

	# 5. Persist the whole reshuffle.
	persist_weapon_slots()
	persist_equipment()
	persist_quick_slots()
	persist_inventory()
	persist_stash()
	persist_overflow()
	# equipped_backpack was set by direct assignment (not set_equipped) — and
	# belt/cloak were cleared — so recompute gear-derived state.
	_refresh_gear_effects()
	refresh_mana_ui()
	refresh_spell_ui()
	inventory_ui.refresh()

# Tries to place `item` into the stash, starting at preferred_tab and spilling
# into the other tabs as needed. Returns false only if no tab has room at all.
# Shared by move_all_to_stash() and apply_starter_kit()'s bank step.
func _bank_item_to_stash(item: Item, preferred_tab: int) -> bool:
	if preferred_tab >= 0 and preferred_tab < stash_tabs.size():
		if stash_tabs[preferred_tab].try_stack_or_place(item):
			return true
	for i in stash_tabs.size():
		if i == preferred_tab:
			continue
		if stash_tabs[i].try_stack_or_place(item):
			return true
	return false

# "Move All" button in the stash panel — sweeps the whole backpack grid into
# the stash (preferred_tab first, spilling to others). Quick slots and equipped
# gear are deliberately untouched. Items that don't fit anywhere stay in the
# bag rather than being forced into the overflow chest (that's Starter-Kit-
# only) — so this is always a safe, reversible sweep.
func move_all_to_stash(preferred_tab: int) -> void:
	for entry in inventory.placements.duplicate():
		var item: Item = entry["item"]
		# Crystals/form stones always go to the Materials tab, no matter which
		# stash tab is showing. bank_material removes them from the bag itself.
		if ItemData.is_material(item.type):
			bank_material(item, "player")
			continue
		# Everything else fills the tab you're looking at first, spilling into the
		# others in order (see _bank_item_to_stash). Anything that fits nowhere
		# stays in the bag rather than being lost.
		if _bank_item_to_stash(item, preferred_tab):
			inventory.remove_item(item.instance_id)
	persist_inventory()
	persist_stash()
	persist_materials()
	inventory_ui.refresh()

func persist_weapon_slots() -> void:
	stats.save_data["weapons"] = weapon_slots.map(func(w): return w.to_dict() if w != null else null)
	# Which slot is in-hand vs holstered is part of the loadout — without this,
	# a load always snaps back to slot 0, so a weapon you'd swapped into your
	# hand reverts to the holster.
	stats.save_data["active_slot"] = active_slot
	# Keep the replicated combat identity in sync with the active weapon so
	# other peers compute the same matchup damage against us. "default" =
	# unarmed/neutral.
	var equipped := get_equipped_weapon()
	network_weapon_type = equipped.type if equipped != null else "default"
	network_element = equipped.element if equipped != null else "default"

func persist_inventory() -> void:
	stats.save_data["items"] = inventory.to_dict()

# Persist whichever own-storage container a UI just mutated in place.
func persist_container(container_id: String) -> void:
	if container_id == "player":
		persist_inventory()
	elif container_id.begins_with("stash_"):
		persist_stash()
	elif container_id == "overflow":
		persist_overflow()

func persist_stash() -> void:
	stats.save_data["stash"] = stash_tabs.map(func(inv): return inv.to_dict())

# "player" or "stash_<index>" -> the actual Inventory it refers to. Used by
# InventoryGrid to move items between the player's own containers (backpack
# <-> a stash tab) without going through the ground-pile claim/RPC machinery
# — this is all still just the local player's own data either way.
func get_container_by_id(container_id: String) -> Inventory:
	if container_id == "player":
		return inventory
	if container_id.begins_with("stash_"):
		var idx := int(container_id.trim_prefix("stash_"))
		if idx >= 0 and idx < stash_tabs.size():
			return stash_tabs[idx]
	if container_id == "overflow":
		return overflow
	return null

func persist_overflow() -> void:
	stats.save_data["overflow"] = overflow.to_dict()

func overflow_has_items() -> bool:
	return !overflow.placements.is_empty()

# --- Crafting materials (stash Materials tab) -----------------------------
func persist_materials() -> void:
	stats.save_data["materials"] = materials.duplicate()

func material_count(type: String) -> int:
	return materials.get(type, 0)

# Consume `n` of a banked material. Returns false (unchanged) if not enough.
func consume_material(type: String, n: int = 1) -> bool:
	if materials.get(type, 0) < n:
		return false
	materials[type] -= n
	if materials[type] <= 0:
		materials.erase(type)
	persist_materials()
	return true

# Drag-in banking: pull the whole material stack out of its own-storage origin
# and fold its quantity into the infinite per-type materials store.
func bank_material(item: Item, origin_container_id: String) -> void:
	if !ItemData.is_material(item.type):
		return
	var origin := get_container_by_id(origin_container_id)
	if origin == null:
		return
	var removed := origin.remove_item(item.instance_id)
	if removed == null:
		return
	materials[removed.type] = materials.get(removed.type, 0) + removed.quantity
	persist_materials()
	persist_container(origin_container_id)
	inventory_ui.refresh()

func move_between_own_containers(origin_id: String, item_instance_id: String, dest_id: String, x: int, y: int) -> void:
	var origin_inv := get_container_by_id(origin_id)
	var dest_inv := get_container_by_id(dest_id)
	if origin_inv == null or dest_inv == null:
		return
	var item := origin_inv.remove_item(item_instance_id)
	if item == null:
		return
	var placed := false
	if dest_inv.can_place_at(item, x, y):
		placed = dest_inv.place_item(item, x, y)
	if !placed:
		placed = dest_inv.try_stack_or_place(item)
	if !placed:
		# No room over there at all — put it back where it came from rather
		# than losing it.
		origin_inv.try_stack_or_place(item)
		return
	persist_inventory()
	persist_stash()
	# One of these two containers may be the overflow chest (dragging items
	# back out of it into the bag/stash) — persist it too so an emptied
	# overflow actually stays emptied on disk.
	if origin_id == "overflow" or dest_id == "overflow":
		persist_overflow()
	inventory_ui.refresh()

# Drop target for a stash TAB BUTTON, not its grid — there's no specific
# cell to aim at, just "put it in this tab if it fits". Mirrors the same
# origin dispatch InventoryGrid._drop_data does (own-storage move, gear/
# weapon/quick-slot unequip, ground-pile claim), just handing (-1,-1) to the
# cell-based versions so their existing can_place_at-fails-then-try_stack_
# or_place fallback does the auto-placement for free.
func drop_item_into_stash_tab(tab_index: int, item: Item, origin_container: String) -> void:
	var dest_id := "stash_%d" % tab_index
	if get_container_by_id(dest_id) == null or origin_container == dest_id:
		return
	if origin_container.begins_with("equip_"):
		unequip_to_grid(origin_container.trim_prefix("equip_"), dest_id, -1, -1)
	elif origin_container.begins_with("quick_"):
		unequip_quick_slot_to_grid(int(origin_container.trim_prefix("quick_")), dest_id, -1, -1)
	elif origin_container == "player" or origin_container.begins_with("stash_") or origin_container == "overflow":
		move_between_own_containers(origin_container, item.instance_id, dest_id, -1, -1)
	else:
		request_claim(origin_container, item.instance_id, dest_id)

func open_stash_panel(chest = null) -> void:
	# Same reasoning as open_loot_panel()'s close_stash_panel() call, in
	# reverse — reset the loot-pickup side too if one was open.
	close_loot_panel()
	close_overflow_panel()
	if open_chest != null and open_chest != chest:
		open_chest.panel_open = false
	open_chest = chest
	inventory_ui.visible = true
	inventory_ui.show_stash_panel()

func close_stash_panel() -> void:
	if open_chest != null:
		open_chest.panel_open = false
		open_chest = null
	inventory_ui.hide_stash_panel()

# The overflow chest — a take-only view of the `overflow` container, shown in
# the same single "other" panel slot the stash/loot use. Drag items out into
# your bag or stash to empty it (dropping INTO it is blocked in
# inventory_grid.gd). Mirrors the stash panel open/close pair.
func open_overflow_panel(chest = null) -> void:
	close_loot_panel()
	close_stash_panel()
	if open_overflow_chest != null and open_overflow_chest != chest:
		open_overflow_chest.panel_open = false
	open_overflow_chest = chest
	inventory_ui.visible = true
	inventory_ui.show_overflow_panel(overflow)

func close_overflow_panel() -> void:
	if open_overflow_chest != null:
		open_overflow_chest.panel_open = false
		open_overflow_chest = null
	inventory_ui.hide_overflow_panel()

# The weapon workbench — a hub interactable that opens a modification panel
# for the player's own weapons (swap element with a crystal, attach/detach
# Form Stones). Purely local, same as the stash: weapons live in this
# player's save data, and multiplayer reads element/form as strings at cast
# time, so nothing here needs networking. Opens alongside the inventory so the
# player can see (and pull from) their crystals/stones while crafting.
func open_workbench_panel(workbench = null) -> void:
	open_workbench = workbench
	inventory_ui.visible = true
	inventory_ui.refresh()
	workbench_ui.visible = true
	workbench_ui.setup(self)

func close_workbench_panel() -> void:
	if open_workbench != null:
		open_workbench.panel_open = false
		open_workbench = null
	workbench_ui.visible = false

# The crafting bench — a hub interactable that opens the crafting panel (turn
# recipe ingredients from your bag/Materials tab into their output). Local like
# the workbench; opens alongside the inventory so you can see your materials.
var open_crafting_bench = null

func open_crafting_panel(bench = null) -> void:
	open_crafting_bench = bench
	inventory_ui.visible = true
	inventory_ui.refresh()
	crafting_ui.visible = true
	crafting_ui.setup(self)

func close_crafting_panel() -> void:
	if open_crafting_bench != null:
		open_crafting_bench.panel_open = false
		open_crafting_bench = null
	crafting_ui.visible = false

# --- Crafting (called by crafting_ui.gd) ----------------------------------
# How many of an item the player has across the bag AND the Materials tab.
func item_available(item_type: String) -> int:
	var total := material_count(item_type)
	for entry in inventory.placements:
		var it: Item = entry["item"]
		if it.type == item_type:
			total += it.quantity
	return total

# How many items satisfying a recipe ingredient (a wildcard like
# "@element_crystal" sums across every type it accepts).
func ingredient_available(ingredient: String) -> int:
	var total := 0
	for t in ItemData.CRAFTING_WILDCARDS.get(ingredient, [ingredient]):
		total += item_available(t)
	return total

func can_craft(recipe: Dictionary) -> bool:
	for pair in recipe["inputs"]:
		if ingredient_available(pair[0]) < pair[1]:
			return false
	return true

# Consume `count` of an ingredient — Materials tab first, then loose from the bag.
func _consume_ingredient(ingredient: String, count: int) -> void:
	var remaining := count
	for t in ItemData.CRAFTING_WILDCARDS.get(ingredient, [ingredient]):
		var from_mat: int = mini(remaining, material_count(t))
		if from_mat > 0:
			consume_material(t, from_mat)
			remaining -= from_mat
		while remaining > 0 and _consume_one_of_type(t):
			remaining -= 1
		if remaining <= 0:
			return

func craft(recipe_index: int) -> bool:
	if recipe_index < 0 or recipe_index >= ItemData.CRAFTING_RECIPES.size():
		return false
	var recipe: Dictionary = ItemData.CRAFTING_RECIPES[recipe_index]
	if not can_craft(recipe):
		return false
	# Consuming inputs (which include bag items) frees grid cells, so the single
	# output item reliably fits afterward.
	for pair in recipe["inputs"]:
		_consume_ingredient(pair[0], pair[1])
	var out: Array = recipe["output"]
	inventory.try_stack_or_place(Item.create(out[0], out[1]))
	persist_inventory()
	persist_materials()
	inventory_ui.refresh()
	return true

# --- Workbench operations (called by workbench_ui.gd) ---------------------
# All three keep inventory access, save persistence and UI refresh in one
# place so the UI just calls and re-reads. They mutate the Weapon in the given
# weapon_slots index (the workbench UI's selected Hand/Holster slot). Return
# false (a clean no-op) rather than ever destroying an item on failure, per
# the project's abort-safely-rather-than-lose-an-item rule.

# Consumes one of `type` from the player's own backpack (decrementing a stack,
# removing the placement at 0), mirroring use_item()'s decrement. Returns
# false if none is held.
func _consume_one_of_type(type: String) -> bool:
	for entry in inventory.placements:
		var item: Item = entry["item"]
		if item.type != type:
			continue
		item.quantity -= 1
		if item.quantity <= 0:
			inventory.remove_item(item.instance_id)
		persist_inventory()
		return true
	return false

func workbench_set_element(slot: int, element: String) -> bool:
	var weapon: Weapon = weapon_slots[slot] if slot >= 0 and slot < weapon_slots.size() else null
	if weapon == null or weapon.element == element:
		return false
	# Element crystals are named crystal_fire / crystal_holy / crystal_air —
	# consume the one matching the target element, from the banked Materials tab
	# first, then any loose one in the backpack.
	var crystal := "crystal_" + element
	if !consume_material(crystal) and !_consume_one_of_type(crystal):
		return false
	weapon.element = element
	persist_weapon_slots()
	_refresh_after_workbench_change()
	return true

func workbench_attach_form(slot: int, form: String) -> bool:
	var weapon: Weapon = weapon_slots[slot] if slot >= 0 and slot < weapon_slots.size() else null
	if weapon == null or !weapon.can_hold_form(form):
		return false
	var stone := ItemData.stone_for_form(form)
	# Materials tab first, then a loose one in the backpack.
	if !consume_material(stone) and !_consume_one_of_type(stone):
		return false
	weapon.attach_form(form)
	persist_weapon_slots()
	_refresh_after_workbench_change()
	return true

func workbench_detach_form(slot: int, form: String) -> bool:
	var weapon: Weapon = weapon_slots[slot] if slot >= 0 and slot < weapon_slots.size() else null
	if weapon == null or !weapon.forms.has(form):
		return false
	weapon.detach_form(form)
	# The freed stone banks straight into the Materials tab (infinite per-type
	# store), so this always succeeds — no grid-full abort needed.
	var stone := ItemData.stone_for_form(form)
	materials[stone] = materials.get(stone, 0) + 1
	persist_materials()
	persist_weapon_slots()
	_refresh_after_workbench_change()
	return true

func _refresh_after_workbench_change() -> void:
	refresh_mana_ui()
	refresh_spell_ui()
	inventory_ui.refresh()
	if workbench_ui.visible:
		workbench_ui.refresh()

# Applies whatever effect an item type has. Only health_potion/mana_crystal
# have one right now. Shared by use_item() (main-grid items) and
# use_quick_slot() (belt quick-slot items) — the effect itself doesn't care
# which container the item came from, only the removal/decrement after does.
func _apply_item_effect(item: Item, potency := 1.0) -> void:
	# Data-driven: any item with heal_amount heals; any with mana_restore charges
	# the held weapon (or both weapons if mana_both_weapons). Lets new consumables
	# work by just declaring those fields in ItemData, no new cases here.
	var def := ItemData.get_def(item.type)
	if def.has("heal_amount"):
		health = clamp(health + def["heal_amount"] * potency, 0.0, max_health)
	if def.has("mana_restore"):
		var amount: float = def["mana_restore"] * potency
		if def.get("mana_both_weapons", false):
			for w in weapon_slots:
				if w != null:
					w.restore_mana(amount)
		else:
			var equipped := get_equipped_weapon()
			if equipped != null:
				equipped.restore_mana(amount)
		persist_weapon_slots()
		refresh_mana_ui()
		refresh_spell_ui()

# Consumes one from the stack (removing the placement entirely once it hits
# 0) and applies whatever effect that item type has. Unusable types just
# no-op (the context menu shouldn't even offer Use for those, but this stays
# safe if it's ever called directly).
func use_item(item: Item, container_id: String = "player") -> void:
	if !ItemData.is_usable(item.type):
		return
	var container := get_container_by_id(container_id)
	if container == null:
		return
	_apply_item_effect(item)
	item.quantity -= 1
	if item.quantity <= 0:
		container.remove_item(item.instance_id)
	if container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# Number-key (quick_slot_1/quick_slot_2) usage — same effect/decrement idea
# as use_item(), but the item lives in quick_slots, not the main grid, and
# only works while a belt is actually equipped (see grant/assign/unequip
# below — quick_slots only ever holds anything while equipped_belt != null).
func use_quick_slot(slot_index: int) -> void:
	if equipped_belt == null or death_state != DeathState.ALIVE:
		return
	if slot_index < 0 or slot_index >= quick_slots.size():
		return
	var item: Item = quick_slots[slot_index]
	if item == null or !ItemData.is_usable(item.type):
		return
	# belt_potency: quick-slot items are 10% stronger.
	var potency := 1.1 if has_gear_attribute("belt_potency") else 1.0
	_apply_item_effect(item, potency)
	item.quantity -= 1
	if item.quantity <= 0:
		quick_slots[slot_index] = null
		# belt_autoreplace: refill the emptied slot from the bag if we have more.
		if has_gear_attribute("belt_autoreplace"):
			_refill_quick_slot(slot_index, item.type)
	persist_quick_slots()
	inventory_ui.refresh()

# Pulls one of `type` out of the backpack into the (now empty) quick slot. No-op
# if the bag has none. See belt_autoreplace.
func _refill_quick_slot(slot_index: int, type: String) -> void:
	for entry in inventory.placements:
		var inv_item: Item = entry["item"]
		if inv_item.type != type or inv_item.quantity <= 0:
			continue
		inv_item.quantity -= 1
		if inv_item.quantity <= 0:
			inventory.remove_item(inv_item.instance_id)
		quick_slots[slot_index] = Item.new(type, 1)
		persist_inventory()
		return

func persist_quick_slots() -> void:
	stats.save_data["quick_slots"] = quick_slots.map(func(i): return i.to_dict() if i != null else null)
	# This is the one choke point every quick_slots mutation goes through
	# (assign/unequip/use/resize), so it doubles as "the HUD is now stale,
	# refresh it" rather than needing a separate call at every call site.
	quick_slot_hud.update(quick_slots)

# Called by a QuickSlotButton when a usable item is dropped on it from the
# player's own grid. Whatever was previously in that slot goes back into the
# grid, same no-room-means-abort safety as equip_item().
func assign_quick_slot(slot_index: int, item: Item) -> void:
	if equipped_belt == null or slot_index < 0 or slot_index >= quick_slots.size():
		return
	var previous: Item = quick_slots[slot_index]
	# Same stackable type already in the slot -> merge onto it (up to max_stack)
	# instead of swapping. (Dropping a 2nd potion onto a 1-potion slot used to
	# swap them, forcing you to pull it out to stack.)
	if previous != null and previous.type == item.type and ItemData.is_stackable(item.type):
		if inventory.remove_item(item.instance_id) == null:
			return
		var room: int = ItemData.get_max_stack(item.type) - previous.quantity
		var transfer: int = min(room, item.quantity)
		previous.quantity += transfer
		item.quantity -= transfer
		if item.quantity > 0:
			inventory.try_stack_or_place(item)  # remainder over the cap stays in the bag
		persist_quick_slots()
		persist_inventory()
		inventory_ui.refresh()
		return
	if inventory.remove_item(item.instance_id) == null:
		return
	if previous != null and !inventory.try_stack_or_place(previous):
		inventory.try_stack_or_place(item)
		return
	quick_slots[slot_index] = item
	persist_quick_slots()
	persist_inventory()
	inventory_ui.refresh()

# Drags a quick-slot item OUT and back into the grid (or a stash tab — see
# unequip_to_grid()'s dest_container_id convention), leaving the slot empty.
# (Previously always targeted `inventory` directly and never persisted the
# destination — a stash drop silently failed, and even a main-grid drop
# never actually got saved to disk. Fixed as part of generalizing this.)
func unequip_quick_slot_to_grid(slot_index: int, dest_container_id: String, x: int, y: int) -> void:
	if slot_index < 0 or slot_index >= quick_slots.size():
		return
	var item: Item = quick_slots[slot_index]
	if item == null:
		return
	var dest := get_container_by_id(dest_container_id)
	if dest == null:
		return
	if dest.can_place_at(item, x, y):
		dest.place_item(item, x, y)
	elif !dest.try_stack_or_place(item):
		return
	quick_slots[slot_index] = null
	persist_quick_slots()
	if dest_container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# True if every quick slot beyond new_count (i.e. the ones that would stop
# existing) has somewhere to go in the main grid — checked against a scratch
# copy (not the real inventory) so a successful placement for one
# overflowing item can't be mistaken for freeing room another one also
# needs. Belt removal/swap checks this FIRST, before touching anything, and
# aborts entirely if it comes back false — conservative on purpose: safe to
# occasionally refuse a swap that might technically have fit once earlier
# placements cascaded space free, never safe to actually lose a quick-slot
# item because the grid turned out to be full.
func _can_resize_quick_slots(new_count: int) -> bool:
	var scratch := Inventory.from_dict(inventory.to_dict())
	for i in range(new_count, quick_slots.size()):
		var item: Item = quick_slots[i]
		if item != null and !scratch.try_stack_or_place(Item.from_dict(item.to_dict())):
			return false
	return true

# Resizes quick_slots to match new_belt's provides_quick_slots (0 if
# new_belt is null, i.e. the belt slot is now empty) — existing items in
# slots that still exist carry over untouched; anything in a slot that no
# longer exists gets bumped back into the main grid instead of lost. Callers
# check _can_resize_quick_slots() first so that bump is always guaranteed to
# succeed.
func _resize_quick_slots_for_belt(new_belt: Item) -> void:
	var new_count := ItemData.get_provides_quick_slots(new_belt.type) if new_belt != null else 0
	var new_slots: Array[Item] = []
	new_slots.resize(new_count)
	for i in min(new_count, quick_slots.size()):
		new_slots[i] = quick_slots[i]
	for i in range(new_count, quick_slots.size()):
		if quick_slots[i] != null:
			inventory.try_stack_or_place(quick_slots[i])
	quick_slots = new_slots
	persist_quick_slots()

# Dropping is entirely the dropper's own call (no race to lose, unlike
# claiming), so this removes locally right away rather than waiting on a
# server round-trip — the RPC just tells the world to actually place it.
# container_id is whichever of the player's own containers the item was
# actually sitting in ("player" or "stash_N") — previously hardcoded to the
# main grid, so right-clicking Drop on a stash item silently did nothing.
func drop_item(item: Item, container_id: String = "player") -> void:
	var container := get_container_by_id(container_id)
	if container == null or container.remove_item(item.instance_id) == null:
		return
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		container.try_stack_or_place(item)
		return
	world.request_drop_item(global_position, item.to_dict())
	if container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# Gone for good — no ground pickup, nothing to reclaim. For when you don't
# want to bother walking back for something (unlike drop_item()). Same
# container_id fix as drop_item() above — Trash on a stash item used to
# silently no-op.
func trash_item(item: Item, container_id: String = "player") -> void:
	var container := get_container_by_id(container_id)
	if container == null or container.remove_item(item.instance_id) == null:
		return
	if container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# Splits a stack in half (rounded down for the piece that stays put),
# placing the new half-stack in the nearest free cell of the SAME
# container. No-ops if the stack can't actually be split (quantity 1, not
# stackable) or there's nowhere for the new stack to go.
func split_item(item: Item, container_id: String = "player") -> void:
	if item.quantity <= 1 or !ItemData.is_stackable(item.type):
		return
	var container := get_container_by_id(container_id)
	if container == null:
		return
	var half := item.quantity / 2
	if half <= 0:
		return
	var footprint := ItemData.get_footprint(item.type)
	var pos := container.find_free_position(footprint.x, footprint.y)
	if pos == Vector2i(-1, -1):
		return
	item.quantity -= half
	container.place_item(Item.new(item.type, half), pos.x, pos.y)
	if container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

func get_equipped(slot_type: String) -> Item:
	match slot_type:
		"backpack": return equipped_backpack
		"belt": return equipped_belt
		"body": return equipped_body
	return equipped_gear.get(slot_type)

func set_equipped(slot_type: String, item) -> void:
	match slot_type:
		"backpack": equipped_backpack = item
		"belt": equipped_belt = item
		"body": equipped_body = item
		_:
			# One of the EXTRA_GEAR_SLOTS — erase rather than store null so the
			# dict only ever holds real items.
			if item == null:
				equipped_gear.erase(slot_type)
			else:
				equipped_gear[slot_type] = item
	# Equipping/unequipping gear can change max health and the cloak-stealth
	# flags — recompute from the new loadout. (Direct assignments that bypass
	# this — _ready load, apply_starter_kit — call _refresh_gear_effects too.)
	_refresh_gear_effects()

# Every equipped gear piece (the three special-var slots + the generic ones),
# for the trait scans and durability drain that don't care which slot is which.
func _all_gear() -> Array:
	var list: Array = [equipped_body, equipped_belt, equipped_backpack]
	list.append_array(equipped_gear.values())
	return list

# --- Gear traits ----------------------------------------------------------
# True only if the piece carrying this trait is equipped AND unbroken. Only one
# slot can ever hold a given trait, so scanning all three is unambiguous. On a
# remote copy of a player these are all null (gear loads only on the authority),
# so this correctly returns false there — the two stealth traits reach enemies
# via the replicated flags instead (see _refresh_gear_effects).
func has_gear_attribute(attr_id: String) -> bool:
	for gear in _all_gear():
		if gear != null and gear.durability > 0.0 and gear.attributes.has(attr_id):
			return true
	return false

# Recomputes everything derived from gear traits: max health (belt_vitality),
# the replicated cloak-stealth flags, and refreshes health UI. Called after any
# gear equip/unequip and after durability drain. Authority-only work (gear only
# lives on the authority); harmless if called elsewhere.
func _refresh_gear_effects() -> void:
	var vitality := 1.1 if has_gear_attribute("belt_vitality") else 1.0
	max_health = BASE_MAX_HEALTH * vitality
	# Re-assigning health fires its setter, which refreshes the health bar with
	# the new max (clamped down if vitality was just lost).
	health = min(health, max_health)
	# Blessed Band shield capacity = BLESSED_BAND_SHIELD per equipped band. When a
	# band is newly equipped (capacity just went up) grant that fresh buffer; the
	# shield otherwise only ever goes DOWN via damage, so it isn't refilled here.
	var new_max_shield := BLESSED_BAND_SHIELD * _count_equipped_blessed_bands()
	if new_max_shield > max_shield:
		shield += new_max_shield - max_shield
	max_shield = new_max_shield
	shield = minf(shield, max_shield)
	stealth_silent = has_gear_attribute("cloak_silent")
	stealth_unseen_still = has_gear_attribute("cloak_unseen_still")

func _count_equipped_blessed_bands() -> int:
	var n := 0
	for slot in ["ring_1", "ring_2"]:
		var g: Item = get_equipped(slot)
		if g != null and g.type == "blessed_band":
			n += 1
	return n

# Called when the shield is fully spent: every equipped Blessed Band breaks into
# 1 scrap dropped into the bag, freeing its ring slot (which drops max_shield to
# 0 via _refresh_gear_effects inside set_equipped).
func _break_blessed_bands() -> void:
	var broke := false
	for slot in ["ring_1", "ring_2"]:
		var g: Item = get_equipped(slot)
		if g != null and g.type == "blessed_band":
			set_equipped(slot, null)
			inventory.try_stack_or_place(Item.create("scrap", 1))
			broke = true
	if broke:
		persist_equipment()
		persist_inventory()
		inventory_ui.refresh()

# Sequence-spell mana cost after cloak_efficient (10% off, rounded up). Used by
# both the affordability pre-check and the actual deduction so they agree.
func effective_mana_cost(spell_data: Dictionary) -> float:
	var cost: float = spell_data.get("mana_cost", 0.0)
	if cost > 0.0 and has_gear_attribute("cloak_efficient"):
		cost = ceil(cost * 0.9)
	return cost

# Every equipped piece loses a little durability when the wearer is hit; a piece
# hitting 0 stops granting its trait (has_gear_attribute checks durability).
func _drain_gear_durability() -> void:
	var changed := false
	for gear in _all_gear():
		if gear != null and gear.durability > 0.0:
			gear.durability = max(gear.durability - GEAR_DURABILITY_COST_PER_HIT, 0.0)
			changed = true
	if changed:
		persist_equipment()
		_refresh_gear_effects()
		inventory_ui.refresh()

func persist_equipment() -> void:
	var data := {
		"backpack": equipped_backpack.to_dict() if equipped_backpack != null else null,
		"belt": equipped_belt.to_dict() if equipped_belt != null else null,
		"body": equipped_body.to_dict() if equipped_body != null else null,
	}
	for slot in EXTRA_GEAR_SLOTS:
		var g = equipped_gear.get(slot)
		data[slot] = g.to_dict() if g != null else null
	stats.save_data["equipment"] = data

# Called by an EquipmentSlot when an eligible item is dropped on it from the
# player's OWN grid (never a ground pile — see EquipmentSlot._can_drop_data).
# Whatever was previously in that slot goes back into the grid; if there's
# no room for it, the whole swap is aborted (item never actually left the
# grid until this succeeds, so nothing is lost either way).
func equip_item(slot_type: String, item: Item) -> void:
	# Swapping out an already-equipped belt for a different one (possibly
	# with fewer quick slots) — checked first, before anything else moves,
	# so a swap that can't also relocate any now-overflowing quick-slot
	# contents aborts cleanly rather than losing them.
	if slot_type == "belt" and equipped_belt != null:
		if !_can_resize_quick_slots(ItemData.get_provides_quick_slots(item.type)):
			return
	if inventory.remove_item(item.instance_id) == null:
		return
	var previous: Item = get_equipped(slot_type)
	if previous != null and !inventory.try_stack_or_place(previous):
		inventory.try_stack_or_place(item)
		return
	set_equipped(slot_type, item)
	if slot_type == "backpack":
		_resize_inventory_for_backpack(item)
	elif slot_type == "belt":
		_resize_quick_slots_for_belt(item)
	persist_equipment()
	persist_inventory()
	inventory_ui.refresh()

# Belt/cloak/backpack call this directly; "hand"/"holster" (from
# WeaponSlotButton's drag payload — see its origin_container convention)
# route to the weapon-specific version below instead, since weapon slots
# aren't Item fields on the player the way gear is. dest_container_id is
# whichever of the player's own containers ("player" or "stash_N") the drag
# was actually dropped onto — resolved via get_container_by_id() so
# unequipping straight into a stash tab works the same as into the main grid.
func unequip_to_grid(slot_type: String, dest_container_id: String, x: int, y: int) -> void:
	if slot_type == "hand" or slot_type == "holster":
		var slot_index := active_slot if slot_type == "hand" else 1 - active_slot
		unequip_weapon_to_grid(slot_index, dest_container_id, x, y)
		return
	if slot_type == "backpack":
		# The inventory ITSELF is about to shrink to DEFAULT_INVENTORY_SIZE
		# — a different enough operation (the destination for "player" is
		# the very grid being resized out from under it) that it gets its
		# own function rather than shoehorning into the generic path below.
		unequip_backpack_to_grid(dest_container_id, x, y)
		return
	if slot_type == "belt" and !_can_resize_quick_slots(0):
		return
	var dest := get_container_by_id(dest_container_id)
	if dest == null:
		return
	var item: Item = get_equipped(slot_type)
	if item == null:
		return
	if dest.can_place_at(item, x, y):
		dest.place_item(item, x, y)
	elif !dest.try_stack_or_place(item):
		return
	if slot_type == "belt":
		_resize_quick_slots_for_belt(null)
	set_equipped(slot_type, null)
	persist_equipment()
	if dest_container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# Backpack unequip is its own function (not folded into unequip_to_grid()
# above) because the destination for "player" IS the inventory that's about
# to shrink to DEFAULT_INVENTORY_SIZE — placing the backpack item into it
# has to be resolved against that future (smaller) size, not the current
# one. A real backpack (2x2+) can never actually fit back into a 4x1 grid,
# so dropping it into a stash tab is the only destination this realistically
# ever succeeds for — dropping it into your own remaining inventory just
# no-ops, same as any other "doesn't fit anywhere" case elsewhere.
func unequip_backpack_to_grid(dest_container_id: String, x: int, y: int) -> void:
	var item: Item = equipped_backpack
	if item == null:
		return
	var dest := get_container_by_id(dest_container_id)
	if dest == null:
		return
	if dest_container_id != "player":
		# Shrink the bag to the bagless size FIRST. If the current items won't
		# fit that smaller grid, refuse the whole unequip (re-equip, don't move)
		# — otherwise the backpack would leave but the grid stay large, leaving
		# it "acting like a backpack is equipped" with none actually on.
		equipped_backpack = null
		if !_resize_inventory_for_backpack(null):
			equipped_backpack = item
			return
		# Now stash the backpack; if the stash can't take it, revert everything.
		if dest.can_place_at(item, x, y):
			dest.place_item(item, x, y)
		elif !dest.try_stack_or_place(item):
			equipped_backpack = item
			_resize_inventory_for_backpack(item)
			return
		persist_equipment()
		persist_stash()
		persist_inventory()
		inventory_ui.refresh()
		return
	equipped_backpack = null
	if !_resize_inventory_for_backpack(null):
		equipped_backpack = item
		return
	if !inventory.try_stack_or_place(item):
		# No room in the new tiny inventory (the realistic outcome for any
		# backpack with a footprint taller than 1 cell) — restore exactly
		# the prior state rather than leaving the player both bagless and
		# missing the backpack itself.
		equipped_backpack = item
		_resize_inventory_for_backpack(item)
		return
	persist_equipment()
	persist_inventory()
	inventory_ui.refresh()

# Wraps a live Weapon instance (mana/durability/instance_id preserved) as an
# Item, exactly the shape the inventory grid expects — shared by equip/
# unequip/death-bag-drop so they all treat "a weapon sitting in the grid or
# on the ground" the same way.
func _wrap_weapon_as_item(weapon: Weapon) -> Item:
	var item := Item.new(weapon.type, 1)
	item.instance_id = weapon.instance_id
	item.weapon = weapon
	return item

# Called by a WeaponSlotButton when a weapon item is dropped on it from the
# player's own grid. Whatever was previously in that slot (if anything —
# slots can be empty now, see unequip_weapon_to_grid()) goes back into the
# grid as an item, same no-room-means-abort safety as equip_item().
func equip_weapon_item(slot_index: int, item: Item) -> void:
	if inventory.remove_item(item.instance_id) == null:
		return
	var previous: Weapon = weapon_slots[slot_index]
	if previous != null and !inventory.try_stack_or_place(_wrap_weapon_as_item(previous)):
		inventory.try_stack_or_place(item)
		return
	weapon_slots[slot_index] = item.weapon if item.weapon != null else Weapon.new(item.type)
	persist_weapon_slots()
	persist_inventory()
	refresh_mana_ui()
	refresh_spell_ui()
	inventory_ui.refresh()

# Drags a weapon OUT of hand/holster and into the grid (or a stash tab —
# dest_container_id, same convention as unequip_to_grid() above), leaving
# that slot genuinely empty (get_equipped_weapon() can return null — see its
# callers' null guards) rather than requiring some "unarmed" placeholder
# weapon.
func unequip_weapon_to_grid(slot_index: int, dest_container_id: String, x: int, y: int) -> void:
	var weapon: Weapon = weapon_slots[slot_index]
	if weapon == null:
		return
	var dest := get_container_by_id(dest_container_id)
	if dest == null:
		return
	var item := _wrap_weapon_as_item(weapon)
	if dest.can_place_at(item, x, y):
		dest.place_item(item, x, y)
	elif !dest.try_stack_or_place(item):
		return
	weapon_slots[slot_index] = null
	persist_weapon_slots()
	refresh_mana_ui()
	refresh_spell_ui()
	if dest_container_id == "player":
		persist_inventory()
	else:
		persist_stash()
	inventory_ui.refresh()

# Rebuilds `inventory` at the new backpack's capacity, carrying every
# currently-placed item over (preferring its old cell if it still fits).
# Refuses the resize entirely (leaves the old grid untouched) if even one
# item genuinely has nowhere to go in the new size — a backpack swap should
# never be the thing that loses your stuff.
# new_backpack may be null now (unequipping entirely) — falls back to
# DEFAULT_INVENTORY_SIZE, same abort-if-anything-doesn't-fit safety either
# way.
# Returns false (leaving the current inventory untouched) if even one item
# has nowhere to go in the new size — callers use that to abort abort-safely.
func _resize_inventory_for_backpack(new_backpack: Item) -> bool:
	var capacity := ItemData.get_provides_capacity(new_backpack.type) if new_backpack != null else DEFAULT_INVENTORY_SIZE
	var new_inventory := Inventory.new(capacity.x, capacity.y)
	for entry in inventory.placements:
		var existing_item: Item = entry["item"]
		if new_inventory.can_place_at(existing_item, entry["x"], entry["y"]):
			new_inventory.place_item(existing_item, entry["x"], entry["y"])
			continue
		var footprint := ItemData.get_footprint(existing_item.type)
		var pos := new_inventory.find_free_position(footprint.x, footprint.y)
		if pos == Vector2i(-1, -1):
			return false
		new_inventory.place_item(existing_item, pos.x, pos.y)
	inventory = new_inventory
	# Re-pointing player_grid at this new object happens generically in
	# inventory_ui.refresh() (called right after this by equip_item()).
	return true

func open_loot_panel(pickup) -> void:
	# A chest and a ground pile showing at once would be confusing, and
	# leaving the chest's own panel_open flag stuck true would cause the
	# exact same desync the pickup-vs-pickup case below guards against — so
	# close_stash_panel() first to reset that side of things too.
	close_stash_panel()
	close_overflow_panel()
	# Closing whatever was previously open (rather than just overwriting the
	# reference) keeps that pickup's own panel_open flag in sync — otherwise
	# walking away from it later would still think its panel needs closing
	# and wrongly tear down whatever's open now instead.
	if open_loot_pickup != null and open_loot_pickup != pickup:
		open_loot_pickup.panel_open = false
	open_loot_pickup = pickup
	inventory_ui.visible = true
	inventory_ui.show_loot_panel(pickup.inventory, pickup.pickup_id)

func close_loot_panel() -> void:
	# Covers the Tab-close path too (not just the pickup walking-away/
	# re-pressing-interact path) — otherwise the pickup's own panel_open
	# flag would stay stuck true after Tab hid the UI out from under it.
	if open_loot_pickup != null:
		open_loot_pickup.panel_open = false
		open_loot_pickup = null
	_pending_claim_cells.clear()
	inventory_ui.hide_loot_panel()

# "Take All" button — claims every item currently in the open ground pile
# one at a time, same server-arbitrated request_claim() a manual drag would
# use (so it still can't ever double-claim against another player racing the
# same pile). Snapshotting the placements first since a claim's eventual
# broadcast_item_claimed response is what actually mutates the pile's local
# placements list (see loot_pickup.gd's remove_item_locally()), not this
# loop itself — iterating the live array while that lands mid-loop would be
# unsafe.
# Shift-click quick-transfer (see inventory_grid.gd's _gui_input). Moves `item`
# from the grid it was clicked in to whichever other panel is open, auto-placed.
func quick_transfer_item(item: Item, from_container: String) -> void:
	var dest: String = inventory_ui.other_open_container_id(from_container)
	_quick_transfer(item, from_container, dest)

func _is_own_storage_id(cid: String) -> bool:
	return cid == "player" or cid.begins_with("stash_") or cid == "overflow"

func _quick_transfer(item: Item, origin: String, dest: String) -> void:
	if dest == "" or origin == dest:
		return
	# The overflow chest is take-only — never a shift-click destination.
	if dest == "overflow":
		return
	# The Materials tab only accepts crystals/form stones; shift-clicking one
	# banks it, and a non-material simply has nowhere to go here.
	if dest == "materials":
		if ItemData.is_material(item.type):
			bank_material(item, origin)
		return
	if _is_own_storage_id(origin) and _is_own_storage_id(dest):
		# Backpack <-> stash tab <-> overflow (out) — a plain local move.
		move_between_own_containers(origin, item.instance_id, dest, -1, -1)
		return
	if _is_own_storage_id(origin):
		# Own storage -> a ground pile: drop it, which merges into the nearby
		# pile you're looting (you're standing on it). player->ground-pile isn't
		# a direct move, but drop_item gets the same result.
		drop_item(item, origin)
		return
	# A ground pile -> own storage: claim it (auto-placed, no target cell).
	var claim_dest: String = "inventory" if dest == "player" else dest
	request_claim(origin, item.instance_id, claim_dest)

func take_all_from_loot() -> void:
	if open_loot_pickup == null:
		return
	for entry in open_loot_pickup.inventory.placements.duplicate():
		request_claim(open_loot_pickup.pickup_id, entry["item"].instance_id)
	# Close the whole inventory screen once everything's been claimed — the
	# claims resolve asynchronously and still land even with the UI hidden.
	close_inventory_if_open()

# item_instance_id -> the exact grid cell the player dragged a ground-pile item
# onto, so receive_claimed_item() can honor it instead of always auto-placing.
# Local to the claiming peer (the target cell is only meaningful to them); the
# claim RPC itself is unchanged. A lost claim race just leaves a stale entry,
# cleared on close_loot_panel().
var _pending_claim_cells: Dictionary = {}

func request_claim(pickup_id: String, item_instance_id: String, destination: String = "inventory", target_x: int = -1, target_y: int = -1) -> void:
	if target_x >= 0 and target_y >= 0:
		_pending_claim_cells[item_instance_id] = Vector2i(target_x, target_y)
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.request_claim_item(pickup_id, item_instance_id, destination)

# Called by world.gd once the server confirms we won the claim race — the UI
# never places a dragged-from-ground item optimistically, only once this
# actually lands, so a lost race just never shows up rather than needing to
# be un-placed. destination != "inventory" means this claim was dragged
# straight onto an equip/quick slot (see equip_from()) — the item still
# lands in the main grid first either way (so a lost equip attempt, e.g. no
# room for whatever it would've swapped out, still leaves it somewhere
# real), then _auto_equip_to_destination() tries to finish the job.
func receive_claimed_item(item_dict: Dictionary, destination: String = "inventory") -> void:
	var item := Item.from_dict(item_dict)
	# Equip/weapon/quick destinations equip DIRECTLY from the claimed item —
	# never forced through the backpack grid first. A bagless player's default
	# grid is 4x1, which can't hold a 2x2 weapon (or any gear) at all, so the
	# old "stuff it in the grid, then equip" path failed try_stack_or_place and
	# destroyed the item. Direct-equip into an empty slot needs no grid room.
	if destination != "inventory" and !destination.begins_with("stash_"):
		if _equip_claimed_to_destination(destination, item):
			return
		# Equip couldn't complete (occupied slot with no room for the displaced
		# item, no belt for a quick slot, etc.) — fall through and at least keep
		# the item somewhere real rather than losing it.
	if destination.begins_with("stash_"):
		var stash := get_container_by_id(destination)
		if stash != null and stash.try_stack_or_place(item):
			persist_stash()
			inventory_ui.refresh()
			return
		# Bad tab index or that tab's genuinely full — fall through to the
		# main grid below rather than losing the item outright.
	# Honor the exact cell the item was dragged onto (specific-slot drop), if it
	# still fits when the claim resolves; otherwise auto-place. Only for the main
	# grid ("inventory") — stash/equip claims don't carry a cell.
	var target: Vector2i = _pending_claim_cells.get(item.instance_id, Vector2i(-1, -1))
	_pending_claim_cells.erase(item.instance_id)
	var placed := false
	if destination == "inventory" and target.x >= 0 and inventory.can_place_at(item, target.x, target.y):
		placed = inventory.place_item(item, target.x, target.y)
	if !placed:
		placed = inventory.try_stack_or_place(item)
	if !placed:
		# Genuinely nowhere to put it — return it to the ground at our feet
		# rather than deleting it (abort-safely). Never silently destroy loot.
		var world = get_tree().get_first_node_in_group("world")
		if world != null:
			world.request_drop_item(global_position, item.to_dict())
		inventory_ui.refresh()
		return
	persist_inventory()
	inventory_ui.refresh()

# Single entry point for "equip/assign this item to <destination>"
# (destination is a slot_type string — "backpack"/"belt"/"body"/"hand"/
# "holster"/"quick_N" — see unequip_to_grid()'s matching vocabulary),
# regardless of where the item is currently sitting: the player's own grid
# (already there, equips directly), a stash tab (moved into the grid first,
# then equipped the normal way), or an unclaimed ground pile (claimed
# through the server first — receive_claimed_item() finishes the equip once
# that resolves, since claiming can race and can't be done optimistically).
func equip_from(origin_container: String, item: Item, destination: String) -> void:
	if origin_container == "player":
		_auto_equip_to_destination(destination, item)
		return
	if origin_container.begins_with("stash_") or origin_container == "overflow":
		# Pull it out of the stash/overflow and equip DIRECTLY (not via the
		# grid) — same reason as receive_claimed_item(): a weapon/gear item
		# won't fit a bagless 4x1 grid, so routing through it would fail
		# silently and the equip would just no-op.
		var origin_inv := get_container_by_id(origin_container)
		if origin_inv == null:
			return
		var removed := origin_inv.remove_item(item.instance_id)
		if removed == null:
			return
		if !_equip_claimed_to_destination(destination, removed):
			# Couldn't equip — put it back exactly where it came from.
			origin_inv.try_stack_or_place(removed)
			return
		persist_stash()
		if origin_container == "overflow":
			persist_overflow()
		return
	request_claim(origin_container, item.instance_id, destination)

# In-grid equip (item is currently sitting in the main backpack grid) — the
# equip_*_item helpers remove it from there first. Used only for "player"
# origin; stash/overflow/ground origins go through _equip_claimed_to_
# destination() instead, which sources from the passed item directly.
func _auto_equip_to_destination(destination: String, item: Item) -> void:
	match destination:
		"backpack", "belt", "body", "hat", "necklace", "pants", "boots", "ring_1", "ring_2":
			equip_item(destination, item)
		"hand":
			equip_weapon_item(active_slot, item)
		"holster":
			equip_weapon_item(1 - active_slot, item)
		_:
			if destination.begins_with("quick_"):
				assign_quick_slot(int(destination.trim_prefix("quick_")), item)

# Equips the given item (NOT assumed to be in the grid — it's the claimed/
# stashed item itself) straight into its destination slot. Returns false, with
# nothing mutated, if the equip can't complete (occupied slot whose displaced
# item has no grid room, no belt for a quick slot, etc.) so the caller can keep
# the item somewhere safe instead. This is what makes equipping a looted weapon
# work while bagless — an empty slot needs no grid room at all.
func _equip_claimed_to_destination(destination: String, item: Item) -> bool:
	match destination:
		"hand":
			return _equip_claimed_weapon(active_slot, item)
		"holster":
			return _equip_claimed_weapon(1 - active_slot, item)
		"backpack", "belt", "body", "hat", "necklace", "pants", "boots", "ring_1", "ring_2":
			return _equip_claimed_gear(destination, item)
		_:
			if destination.begins_with("quick_"):
				return _assign_claimed_quick_slot(int(destination.trim_prefix("quick_")), item)
	return false

func _equip_claimed_weapon(slot_index: int, item: Item) -> bool:
	var weapon: Weapon = item.weapon if item.weapon != null else Weapon.new(item.type)
	var previous: Weapon = weapon_slots[slot_index]
	# Occupied slot: the displaced weapon must land in the grid; if there's no
	# room, abort (nothing mutated) so neither weapon is lost.
	if previous != null and !inventory.try_stack_or_place(_wrap_weapon_as_item(previous)):
		return false
	weapon_slots[slot_index] = weapon
	persist_weapon_slots()
	persist_inventory()
	refresh_mana_ui()
	refresh_spell_ui()
	inventory_ui.refresh()
	return true

func _equip_claimed_gear(slot_type: String, item: Item) -> bool:
	if slot_type == "belt" and equipped_belt != null:
		if !_can_resize_quick_slots(ItemData.get_provides_quick_slots(item.type)):
			return false
	var previous: Item = get_equipped(slot_type)
	if previous != null and !inventory.try_stack_or_place(previous):
		return false
	set_equipped(slot_type, item)
	if slot_type == "backpack":
		_resize_inventory_for_backpack(item)
	elif slot_type == "belt":
		_resize_quick_slots_for_belt(item)
	persist_equipment()
	persist_inventory()
	inventory_ui.refresh()
	return true

func _assign_claimed_quick_slot(slot_index: int, item: Item) -> bool:
	if equipped_belt == null or slot_index < 0 or slot_index >= quick_slots.size():
		return false
	var previous: Item = quick_slots[slot_index]
	# Merge onto a same-type stackable already in the slot (up to max_stack).
	if previous != null and previous.type == item.type and ItemData.is_stackable(item.type):
		var room: int = ItemData.get_max_stack(item.type) - previous.quantity
		var transfer: int = min(room, item.quantity)
		previous.quantity += transfer
		item.quantity -= transfer
		if item.quantity > 0:
			inventory.try_stack_or_place(item)
		persist_quick_slots()
		persist_inventory()
		inventory_ui.refresh()
		return true
	if previous != null and !inventory.try_stack_or_place(previous):
		return false
	quick_slots[slot_index] = item
	persist_quick_slots()
	persist_inventory()
	inventory_ui.refresh()
	return true

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int(), false)

func _ready() -> void:
	hurtbox.owner_id = name.to_int()
	hurtbox.hurt.connect(_on_hurtbox_hurt)
	if is_multiplayer_authority():
		player_camera.make_current()
		spell_list_ui.visible = true
		spell_list_ui.setup(self)
		health_ui.visible = true
		health_ui.update_health(health, max_health)
		# CanvasLayer defaults to visible — only die() (and _finish_death()
		# hiding it again) should ever show this, not "exists at all".
		downed_ui.visible = false
		var saved: Array = stats.save_data.get("weapons", [])
		if saved.is_empty():
			persist_weapon_slots()
		else:
			weapon_slots.assign(saved.map(func(w): return Weapon.from_dict(w) if w != null else null))
			# Restore which slot was in-hand BEFORE persisting (persist reads the
			# active weapon for the replicated combat identity) — otherwise the
			# hand/holster choice is lost on load.
			active_slot = clampi(int(stats.save_data.get("active_slot", 0)), 0, weapon_slots.size() - 1)
			# Sync the replicated combat identity to the loaded weapon (persist_
			# weapon_slots wasn't called on this branch).
			persist_weapon_slots()
		# The spell list was set up above BEFORE weapons loaded, so it's showing
		# the wrong (empty/default) weapon's spells until refreshed here.
		refresh_spell_ui()
		mana_ui.visible = true
		refresh_mana_ui()
		# Equipment loads before inventory contents, since inventory's grid
		# size is derived from whichever backpack is equipped — and
		# inventory_ui.setup() below needs the final, correctly-sized
		# inventory already in place (reassigning `inventory` to a new
		# object AFTER handing this same reference to player_grid would
		# leave the grid widget pointing at an abandoned one).
		var saved_equipment: Dictionary = stats.save_data.get("equipment", {})
		# No auto-grant anymore — backpack is unequippable like belt/cloak
		# now, so a fresh character (or one who died/unequipped) simply
		# starts bagless at DEFAULT_INVENTORY_SIZE until they equip one.
		if saved_equipment.get("backpack") != null:
			equipped_backpack = Item.from_dict(saved_equipment["backpack"])
		if saved_equipment.get("belt") != null:
			equipped_belt = Item.from_dict(saved_equipment["belt"])
		# "body" is the current key; fall back to the old "cloak" key so saves
		# made before the rename keep their equipped robe/cloak.
		var saved_body = saved_equipment.get("body", saved_equipment.get("cloak"))
		if saved_body != null:
			equipped_body = Item.from_dict(saved_body)
		for slot in EXTRA_GEAR_SLOTS:
			if saved_equipment.get(slot) != null:
				equipped_gear[slot] = Item.from_dict(saved_equipment[slot])
		if saved_equipment.is_empty():
			persist_equipment()
		var saved_quick_slots: Array = stats.save_data.get("quick_slots", [])
		quick_slots.assign(saved_quick_slots.map(func(d): return Item.from_dict(d) if d != null else null))
		var saved_items: Dictionary = stats.save_data.get("items", {})
		if saved_items.is_empty():
			var capacity := ItemData.get_provides_capacity(equipped_backpack.type) if equipped_backpack != null else DEFAULT_INVENTORY_SIZE
			inventory = Inventory.new(capacity.x, capacity.y)
			persist_inventory()
		else:
			inventory = Inventory.from_dict(saved_items)
		# Reconciles quick_slots' size against whatever the loaded belt
		# actually grants right now — covers a fresh character (no belt,
		# resizes to 0), and a stale save whose slot count doesn't match the
		# belt's current definition (e.g. this feature didn't exist yet when
		# it was saved), bumping any now-overflowing item into inventory
		# (already loaded above, so there's somewhere for it to land).
		_resize_quick_slots_for_belt(equipped_belt)
		var saved_stash: Array = stats.save_data.get("stash", [])
		# Always end up with exactly STASH_TAB_COUNT tabs (pad if an older save
		# had fewer — e.g. before Tab 4 existed) and give each the stash stack
		# multiplier so cells hold double.
		stash_tabs.clear()
		for i in STASH_TAB_COUNT:
			var tab: Inventory
			if i < saved_stash.size():
				tab = Inventory.from_dict(saved_stash[i])
			else:
				tab = Inventory.new(STASH_TAB_SIZE.x, STASH_TAB_SIZE.y)
			tab.stack_multiplier = STASH_STACK_MULTIPLIER
			stash_tabs.append(tab)
		if saved_stash.size() != STASH_TAB_COUNT:
			persist_stash()
		var saved_overflow: Dictionary = stats.save_data.get("overflow", {})
		if saved_overflow.is_empty():
			overflow = Inventory.new(OVERFLOW_SIZE.x, OVERFLOW_SIZE.y)
			persist_overflow()
		else:
			overflow = Inventory.from_dict(saved_overflow)
		materials = stats.save_data.get("materials", {}).duplicate()
		inventory_ui.visible = false
		inventory_ui.setup(self)
		# Gear was loaded by direct assignment above (not set_equipped), so
		# derive max health + stealth flags from it now.
		_refresh_gear_effects()
	else:
		spell_list_ui.visible = false
		health_ui.visible = false
		mana_ui.visible = false
		inventory_ui.visible = false
		downed_ui.visible = false
		quick_slot_hud.visible = false

func _on_hurtbox_hurt(hitbox, damage) -> void:
	# The damage NUMBER is authoritative: only our own authority computes it and
	# then broadcasts it to everyone. Our own authority is the only peer that has
	# BOTH our real equipped gear (cloak_armor) and a guaranteed-current combat
	# identity, so recomputing it per-peer from replicated data made screens
	# disagree (e.g. one shows 26, another 28).
	if !is_multiplayer_authority():
		return
	var final_damage: float = damage
	if hitbox != null and "attacker_weapon" in hitbox and "attacker_element" in hitbox:
		var multiplier := SpellData.get_damage_multiplier(
			hitbox.attacker_weapon,
			hitbox.attacker_element,
			network_weapon_type,
			network_element
		)
		final_damage = damage * multiplier
	# Cloak/robe armor trait: 5% less damage.
	if has_gear_attribute("cloak_armor"):
		final_damage *= 0.95
	_broadcast_damage_number.rpc(final_damage, hitbox != null and hitbox.is_crit)
	take_damage(final_damage)
	# Getting hit wears down equipped gear; a piece that breaks loses its trait.
	_drain_gear_durability()

# Shows the authoritative damage number on every peer (call_local so our own
# screen shows it too) — the one place the number is spawned now, so all peers
# agree.
@rpc("authority", "call_local", "unreliable")
func _broadcast_damage_number(amount: float, is_crit: bool) -> void:
	_spawn_damage_number(amount, Color(1, 0.3, 0.25), is_crit)

func take_damage(amount: float) -> void:
	if death_state != DeathState.ALIVE:
		return
	# No hostile source ever exists in the hub, so blocking all incoming
	# damage to a player standing there is exactly "friendly fire off" in
	# effect, with no separate attacker-type check needed.
	if _is_in_hub():
		return
	# Shield soaks damage first; if it empties, the Blessed Band(s) providing it
	# break, and any leftover damage carries through to health.
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		if shield <= 0.0:
			_break_blessed_bands()
	if amount <= 0.0:
		return
	health = clamp(health - amount, 0.0, max_health)
	if health <= 0.0:
		die()

func _is_in_hub() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	return world != null and world.my_zone == "hub"

# --- Co-op revive ---------------------------------------------------------
# Run each frame while alive (see _physics_process). If we're holding interact
# next to a downed ally, fill the revive; on completion, revive them (consuming
# Phoenix Ash from OUR bag for the faster/stronger version if we have one).
func _check_revive(delta: float) -> void:
	var target = _nearest_downed_ally()
	if target == null or not Input.is_action_pressed("interact"):
		_revive_progress = 0.0
		return
	var has_ash := _has_item("phoenix_ash")
	var duration: float = REVIVE_TIME_ASH if has_ash else REVIVE_TIME_BASE
	_revive_progress += delta
	if _revive_progress < duration:
		return
	_revive_progress = 0.0
	if has_ash:
		_consume_one_of_type("phoenix_ash")
	target.request_revive.rpc(REVIVE_HP_ASH if has_ash else REVIVE_HP_BASE)

# Closest OTHER player showing the replicated downed (prone) anim, within range.
# death_state isn't replicated, so network_body_anim is how we spot a downed ally.
func _nearest_downed_ally():
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.players == null:
		return null
	var best = null
	var best_dist := REVIVE_RANGE
	for p in world.players.get_children():
		if p == self or not ("network_body_anim" in p) or p.network_body_anim != "prone":
			continue
		var d := global_position.distance_to(p.global_position)
		if d <= best_dist:
			best_dist = d
			best = p
	return best

func _has_item(item_type: String) -> bool:
	for entry in inventory.placements:
		if entry["item"].type == item_type and entry["item"].quantity > 0:
			return true
	return false

# Revive request sent by a reviving ally; only the downed player's own authority
# actually performs it, and only if still genuinely downed.
@rpc("any_peer", "call_local", "reliable")
func request_revive(health_amount: float) -> void:
	if !is_multiplayer_authority() or death_state != DeathState.DOWNED:
		return
	downed_ui.visible = false
	give_up_hold_timer = 0.0
	death_state = DeathState.ALIVE
	hurtbox.is_invincible = false
	health = clampf(health_amount, 0.0, max_health)
	play_legs_anim("idle")
	play_body_anim("idle")

func die() -> void:
	death_state = DeathState.DOWNED
	downed_timer = DOWNED_DURATION
	give_up_hold_timer = 0.0
	downed_ui.visible = true
	downed_ui.update(downed_timer, DOWNED_DURATION, give_up_hold_timer, GIVE_UP_HOLD_DURATION)
	hurtbox.is_invincible = true
	velocity = Vector2.ZERO
	is_attacking = false
	state = move_state
	# Close the inventory if it happened to be open — otherwise the prone
	# collapse plays out invisibly behind the panel, and check_inventory_
	# toggle() stops running the moment death_state leaves ALIVE anyway, so
	# Tab wouldn't be able to close it later either.
	if inventory_ui.visible:
		inventory_ui.visible = false
		close_loot_panel()
		close_stash_panel()
		inventory_ui.refresh()
	# Legs are a separate AnimationPlayer that just keeps looping whatever
	# it was last told to play (e.g. "walk") — nothing stops it on its own,
	# so it has to be explicitly told to switch here too.
	play_legs_anim("prone")
	play_body_anim("prone")

# Called once the 60s downed countdown runs out (from _physics_process).
# Plays the death animation briefly, then drops the backpack + everything
# in it as a lootable pile right where the player fell, resets equipment
# and inventory back to fresh-character defaults (weapons are NOT reset —
# only the backpack/belt/cloak/inventory "gear" is lost), and sends the
# player back to the hub to wait out the rest of the expedition.
func _finish_death() -> void:
	downed_ui.visible = false
	play_body_anim("dead")
	if is_inside_tree():
		await get_tree().create_timer(DEATH_ANIM_DELAY).timeout
	if !is_inside_tree():
		return
	_drop_death_bag_and_reset_gear()
	health = max_health
	hurtbox.is_invincible = false
	death_state = DeathState.ALIVE
	play_legs_anim("idle")
	play_body_anim("idle")
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.request_location_changes("hub", "main", "default")

# The actual "lose your gear" consequence, factored out so quitting mid-
# expedition (see lose_everything_if_in_expedition()) can apply it
# immediately without the 60s wait or the teleport-to-hub — you're leaving
# either way.
func _drop_death_bag_and_reset_gear() -> void:
	var dropped_items: Array = []
	if equipped_backpack != null:
		dropped_items.append(equipped_backpack.to_dict())
	# Belt/cloak were previously just reset to null here with nothing ever
	# added to dropped_items — they silently vanished instead of actually
	# ending up in the death bag like the backpack and its contents did.
	if equipped_belt != null:
		dropped_items.append(equipped_belt.to_dict())
	if equipped_body != null:
		dropped_items.append(equipped_body.to_dict())
	for slot_item in quick_slots:
		if slot_item != null:
			dropped_items.append(slot_item.to_dict())
	for entry in inventory.placements:
		dropped_items.append(entry["item"].to_dict())
	# Weapons are lost on death too now — "you lose everything you have on
	# you" — rather than the earlier deliberate scoping decision to spare
	# them. Reset to fully unarmed (not the old tome/wand starter kit) — the
	# Starter Kit at an expedition door is what hands a weapon back, the next
	# time this player heads out of the hub.
	for weapon in weapon_slots:
		if weapon != null:
			dropped_items.append(_wrap_weapon_as_item(weapon).to_dict())
	var world = get_tree().get_first_node_in_group("world")
	if world != null and !dropped_items.is_empty():
		world.request_drop_death_bag(global_position, dropped_items)
	# Backpack is lost too now, same as belt/cloak/weapons — you're left with
	# DEFAULT_INVENTORY_SIZE until you find/equip a new one.
	equipped_backpack = null
	equipped_belt = null
	equipped_body = null
	quick_slots = []
	weapon_slots = [null, null]
	active_slot = 0
	inventory = Inventory.new(DEFAULT_INVENTORY_SIZE.x, DEFAULT_INVENTORY_SIZE.y)
	persist_equipment()
	persist_inventory()
	persist_quick_slots()
	persist_weapon_slots()
	refresh_mana_ui()
	refresh_spell_ui()
	inventory_ui.refresh()

# Same penalty as actually dying, minus the wait and the teleport — used by
# the ESC menu's quit/leave-lobby buttons when they're used mid-expedition.
# Returns whether the penalty actually applied (i.e. whether we were in an
# expedition at all), so the caller knows whether to wait for the drop
# request to actually reach the server before tearing down the connection.
func lose_everything_if_in_expedition() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.my_zone == "hub":
		return false
	_drop_death_bag_and_reset_gear()
	return true

func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_multiplayer_authority():
		if !inventory_ui.visible and death_state == DeathState.ALIVE:
			update_aim()
		network_rotation = sprite.rotation
		network_legs_rotation = legs.rotation
		_update_rain_marker()
		return
	if network_anim != _applied_legs_anim:
		legs_animation_player.play(network_anim)
		_applied_legs_anim = network_anim
	if network_body_anim != _applied_body_anim:
		body_animation_player.play(network_body_anim)
		_applied_body_anim = network_body_anim
	sprite.rotation = network_rotation
	legs.rotation = network_legs_rotation
	# death_state/hurtbox.is_invincible are never replicated (they're local-
	# only on the authority), so a remote peer's own copy of this hurtbox
	# never learns a downed player should stop taking hits — their own
	# locally-simulated projectiles were still colliding with (and
	# destroying themselves against) a prone/dead player's hurtbox even
	# though no damage ever actually applied. network_body_anim IS
	# replicated and only ever reads "prone"/"dead" while genuinely downed,
	# so it doubles as a cheap, already-synced proxy for that state.
	hurtbox.is_invincible = network_body_anim == "prone" or network_body_anim == "dead"

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if !is_multiplayer_authority():
		return
	if death_state != DeathState.ALIVE:
		# Downed or mid-death-sequence — frozen in place, no input reaches
		# the world at all, until _finish_death() resets death_state.
		velocity = Vector2.ZERO
		move_and_slide()
		if death_state == DeathState.DOWNED:
			downed_timer -= delta
			if Input.is_action_pressed("interact"):
				give_up_hold_timer += delta
				if give_up_hold_timer >= GIVE_UP_HOLD_DURATION:
					# Skip straight to the DYING transition below instead of a
					# separate instant-kill path — same death flow either way.
					downed_timer = 0.0
			else:
				give_up_hold_timer = 0.0
			downed_ui.update(max(downed_timer, 0.0), DOWNED_DURATION, give_up_hold_timer, GIVE_UP_HOLD_DURATION)
			if downed_timer <= 0.0:
				death_state = DeathState.DYING
				_finish_death()
	else:
		check_inventory_toggle()
		attack_timer = max(attack_timer - delta, 0.0)
		if inventory_ui.visible:
			# Menu is up — no movement, no aiming, no attack input should
			# reach the world (a click to place an item shouldn't also fire
			# a spell).
			apply_friction(delta)
			move_and_slide()
		else:
			check_weapon_swap()
			check_quick_slot_input()
			_check_revive(delta)
			state.call(delta)
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	if world.shutting_down:
		return
	if !world.can_send_rpc():
		return
	world.server_send_player_state.rpc(global_position, network_anim, network_rotation)

func update_aim() -> void:
	var controller_aim := get_controller_aim_direction()
	if controller_aim != Vector2.ZERO:
		aim_direction = controller_aim
		using_controller_aim = true
	else:
		var mouse_pos := get_global_mouse_position()
		var mouse_direction := global_position.direction_to(mouse_pos)
		if mouse_direction.length() <= 0.01:
			return
		aim_direction = mouse_direction
		using_controller_aim = false
	sprite.rotation = aim_direction.angle() + PI / 2

func get_controller_aim_direction() -> Vector2:
	var aim_vector := Vector2(
		Input.get_axis("aim_left", "aim_right"),
		Input.get_axis("aim_up", "aim_down")
	)
	if aim_vector.length() < controller_aim_deadzone:
		return Vector2.ZERO
	return aim_vector.normalized()

func record_attack_direction(input_num: int):
	spell_input_sequence.append(input_num)
	if spell_input_sequence.size() > 6:
		spell_input_sequence.clear()
		refresh_spell_ui()
		return
	if !has_relevant_spell_prefix(spell_input_sequence):
		spell_input_sequence.clear()
	refresh_spell_ui()

func move_state(delta):
	if Input.is_action_pressed("spell_mode_1"):
		apply_friction(delta)
		check_spell_mode_1_input()
		update_animations(Vector2.ZERO)
		attack_check()
		move_and_slide()
		return
	var raw_input = Vector2(Input.get_axis("left","right"), Input.get_axis("up","down"))
	var input_axis = snap_to_8_directions(raw_input)
	if is_moving(input_axis):
		apply_acceleration(delta, input_axis)
	else:
		apply_friction(delta)
	update_legs_rotation(input_axis)
	if Input.is_action_pressed("spell_mode_2"):
		check_spell_mode_2_input()
	update_animations(input_axis)
	attack_check()
	move_and_slide()

# Legs face whichever direction you're actually walking, independent of
# where visual_root/the body is aiming — only updates while moving, so
# they just stay put facing the last walked direction once you stop.
func update_legs_rotation(input_axis: Vector2) -> void:
	if input_axis != Vector2.ZERO:
		legs.rotation = input_axis.angle() + PI / 2

func snap_to_8_directions(direction: Vector2) -> Vector2:
	if direction.length() < 0.2:
		return Vector2.ZERO
	var x := direction.x
	var y := direction.y
	if abs(x) < 0.35:
		x = 0.0
	if abs(y) < 0.35:
		y = 0.0
	if x == 0.0 and y == 0.0:
		return Vector2.ZERO
	return Vector2(sign(x), sign(y)).normalized()

func is_moving(_input_axis):
	return _input_axis != Vector2.ZERO

func apply_acceleration(delta, _input_axis):
	velocity = velocity.move_toward(_input_axis.normalized()*max_velocity,acceleration*delta)

func apply_friction(delta):
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func update_animations(input_vector: Vector2) -> void:
	# Legs always reflect movement, even mid-attack — only the upper body's
	# animation is gated by is_attacking (see play_body_anim/attack_check).
	if input_vector != Vector2.ZERO:
		play_legs_anim("walk")
	else:
		play_legs_anim("idle")

func play_legs_anim(anim_name: String):
	if legs_animation_player.current_animation != anim_name:
		legs_animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_anim = anim_name

func play_body_anim(anim_name: String):
	if body_animation_player.current_animation != anim_name:
		body_animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_body_anim = anim_name

func equip_weapon(weapon: Weapon, slot: int) -> void:
	weapon_slots[slot] = weapon
	persist_weapon_slots()
	if slot == active_slot:
		refresh_mana_ui()

func check_spell_mode_1_input():
	if Input.is_action_just_pressed("left"):
		record_attack_direction(0)
	if Input.is_action_just_pressed("up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("down"):
		record_attack_direction(3)

func check_spell_mode_2_input():
	if Input.is_action_just_pressed("spell_mode_2_left"):
		record_attack_direction(0)
	if Input.is_action_just_pressed("spell_mode_2_up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("spell_mode_2_right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("spell_mode_2_down"):
		record_attack_direction(3)

func get_default_spell_data():
	var equipped := get_equipped_weapon()
	if equipped.durability <= 0.0:
		return all_spell_data.build_spell_data("default", "default", "default")
	return all_spell_data.build_spell_data(
		equipped.type,
		equipped.element,
		"default",
		equipped.rarity
	)

func get_spell_data():
	print(spell_input_sequence)
	var equipped := get_equipped_weapon()
	# A weapon at 0 durability can't cast sequence spells at all (regardless
	# of mana), and whatever it does still cast gets none of its normal
	# weapon/elemental bonuses — reusing "default"/"default" gets both for
	# free (see spell_data.gd's ELEMENTS["default"] comment). has_relevant_
	# spell_prefix() (via can_afford_recipe()) already stops a sequence from
	# ever being held while broken, so spell_input_sequence should already be
	# empty by the time this runs — this is just the guaranteed backstop.
	if equipped.durability <= 0.0:
		return all_spell_data.build_spell_data("default", "default", "default")
	var weapon_id: String = equipped.type
	var weapon_element: String = equipped.element
	var weapon_forms: Array = equipped.forms
	if spell_input_sequence.is_empty():
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default",
			equipped.rarity
		)
	var recipe := all_spell_recipes.get_spell_recipe_from_sequence(spell_input_sequence)
	if recipe.is_empty():
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default",
			equipped.rarity
		)
	var recipe_element: String = recipe["element"]
	var recipe_form: String = recipe["form"]
	if recipe_element != weapon_element:
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default",
			equipped.rarity
		)
	if !weapon_forms.has(recipe_form):
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default",
			equipped.rarity
		)
	return all_spell_data.build_spell_data(
		weapon_id,
		recipe_element,
		recipe_form,
		equipped.rarity
	)

#func cast_spell(spell_data: Dictionary):
	#var direction = get_facing_direction()
	#var spawn_position = global_position + direction * spell_data["spawn_offset"]
	#spawn_spell.rpc(
		#spawn_position,
		#direction,
		#spell_data["weapon"],
		#spell_data["element"],
		#spell_data["form"]
	#)
	#spell_input_sequence.clear()
	#refresh_spell_ui()

const DURABILITY_COST_PER_CAST := 0.1

var _beam_active_until := 0.0

func cast_spell(spell_data: Dictionary, reset_sequence: bool = true):
	# A beam is a single channeled cast — don't let another beam spawn until the
	# current one has run its full lifetime. This ties the beam's on-screen
	# duration directly to its lifetime (re-casting was previously stacking new
	# beams every 0.15s, so it looked endless and lifetime changes did nothing).
	if spell_data.get("form", "") == "beam":
		var now := Time.get_ticks_msec() / 1000.0
		if now < _beam_active_until:
			return
		_beam_active_until = now + spell_data.get("lifetime", 0.0)
	var direction = get_facing_direction()
	var spawn_position: Vector2
	if spell_data.get("targeted", false):
		# Targeted forms (rain) drop at the mouse, clamped to the form's max range
		# (spawn_offset). rain_projectile.gd then LOS-clamps to a wall if one's
		# between you and that spot.
		var to_mouse := _targeted_cast_offset(spell_data["spawn_offset"])
		spawn_position = global_position + to_mouse
		if to_mouse.length() > 0.001:
			direction = to_mouse.normalized()
	else:
		spawn_position = global_position + direction * spell_data["spawn_offset"]
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	if world.shutting_down:
		return
	if !world.can_send_rpc():
		return
	var equipped := get_equipped_weapon()
	# Free practice in the hub — no durability wear, no mana cost, so players
	# can freely try out sequences without eating into what they'll actually
	# need in the field.
	if !_is_in_hub():
		equipped.use_durability(DURABILITY_COST_PER_CAST)
		# Every spell costs mana now (not just sequences) — attack_check()
		# already verified the weapon can afford this before ever calling in
		# here, so this is just the actual deduction (cloak_efficient discount
		# applied via effective_mana_cost, matching the pre-check).
		equipped.use_mana(effective_mana_cost(spell_data))
		persist_weapon_slots()
	refresh_mana_ui()
	# Mana just changed, so the spell list's affordability grayout needs to
	# refresh too — not just on the reset_sequence path below, since a
	# sequence cast (reset_sequence=false) drains mana just the same.
	refresh_spell_ui()
	# Rolled once here (cast_spell() only ever runs on the casting player's
	# own machine — see attack_check()'s authority-gated caller) and sent as
	# a plain bool below, same reasoning as enemy.gd's fire_spell(): every
	# peer has to apply the identical crit result, not re-roll their own.
	var is_crit := SpellData.roll_crit(spell_data["weapon"])
	if multiplayer.is_server():
		world.server_request_spawn_spell(
			spawn_position,
			direction,
			spell_data["weapon"],
			spell_data["element"],
			spell_data["form"],
			is_crit,
			spell_data.get("rarity", "common")
		)
	else:
		world.server_request_spawn_spell.rpc(
			spawn_position,
			direction,
			spell_data["weapon"],
			spell_data["element"],
			spell_data["form"],
			is_crit,
			spell_data.get("rarity", "common")
		)
	if reset_sequence:
		spell_input_sequence.clear()
		refresh_spell_ui()

#@rpc("any_peer", "call_local", "reliable")
func spawn_spell_local(
	origin_position: Vector2,
	direction: Vector2,
	weapon: String,
	element: String,
	form: String,
	caster_id: int = -1,
	is_crit: bool = false,
	rarity: String = "common"
) -> void:
	if caster_id == -1:
		caster_id = name.to_int()
	var spell_data = all_spell_data.build_spell_data(
		weapon,
		element,
		form,
		rarity
	)
	# Dot forms (rain/beam) roll crit per-tick in their own scripts, so their base
	# damage is left un-crit here; everything else bakes the one cast-time roll in.
	if is_crit and not spell_data.get("dot", false):
		spell_data["damage"] *= SpellData.CRIT_MULTIPLIER
	var projectile = spell_data["scene"].instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin_position
	projectile.setup_spell(direction.normalized(), spell_data, caster_id, is_crit)

func refresh_spell_ui() -> void:
	if !is_multiplayer_authority():
		return
	if has_node("player_camera/spell_list_ui"):
		spell_list_ui.refresh()

func can_afford_recipe(recipe: Dictionary, equipped: Weapon) -> bool:
	# A weapon at 0 durability can't cast sequence spells at all, regardless
	# of zone or mana — checked before the hub free-cast shortcut below since
	# durability is a property of the weapon itself, not something the hub
	# waives. has_relevant_spell_prefix() calls this per-recipe, so returning
	# false here for every recipe is also what stops a sequence from ever
	# being held in the first place while broken.
	if equipped.durability <= 0.0:
		return false
	if _is_in_hub():
		return true
	var mana_cost: float = SpellData.FORMS.get(recipe["form"], {}).get("mana_cost", 0.0)
	# Match the cloak_efficient discount applied at cast time so the spell list's
	# affordability grayout doesn't disagree with what actually casts.
	if mana_cost > 0.0 and has_gear_attribute("cloak_efficient"):
		mana_cost = ceil(mana_cost * 0.9)
	return equipped.mana >= mana_cost

# Recipes the weapon can't currently afford are excluded before the prefix
# check even runs — so typing toward a sequence that could ONLY complete an
# unaffordable spell auto-clears immediately (same as typing an outright
# wrong input), instead of letting you finish typing it and then discovering
# at cast time that nothing happens and you're stuck. If a prefix still has
# at least one affordable completion, it's still considered valid.
func has_relevant_spell_prefix(sequence: Array) -> bool:
	var equipped := get_equipped_weapon()
	if equipped == null:
		return false
	var element: String = equipped.element
	var forms: Array = equipped.forms
	var recipes: Array = all_spell_recipes.get_available_recipes(element, forms)
	for recipe in recipes:
		if !can_afford_recipe(recipe, equipped):
			continue
		var recipe_sequence: Array = recipe["sequence"]
		if sequence.size() > recipe_sequence.size():
			continue
		var matches := true
		for i in sequence.size():
			if sequence[i] != recipe_sequence[i]:
				matches = false
				break
		if matches:
			return true
	return false

func get_facing_direction() -> Vector2:
	return aim_direction.normalized()

# Clamped mouse offset for a targeted cast (rain): vector from the player to the
# mouse, capped at max_range. Shared by cast_spell and the rain preview marker so
# the marker always shows exactly where the cast will land.
func _targeted_cast_offset(max_range: float) -> Vector2:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > max_range:
		to_mouse = to_mouse.normalized() * max_range
	return to_mouse

# Aim direction usable on ANY peer: live on our own authority, otherwise derived
# from the replicated sprite rotation (network_rotation) — sprite.rotation is
# aim.angle()+PI/2 (see update_aim). Used by a following beam so it tracks this
# player's aim on every peer, not just their own.
func get_networked_aim() -> Vector2:
	if is_multiplayer_authority():
		return aim_direction.normalized()
	return Vector2.from_angle(sprite.rotation - PI / 2.0)

# Ground preview circle showing where a queued Rain will land — rain spawns far
# in front of the caster (spawn_offset), so this makes it aimable. Only shown
# on the local (authority) player while a full rain sequence is queued; follows
# the aim and matches the rain's real spawn offset + radius (built from the same
# spell_data), so it stays correct as those get tuned.
var _rain_marker: Polygon2D = null

func _update_rain_marker() -> void:
	if _rain_marker == null:
		_rain_marker = Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			# Base radius 8 matches the projectile's circle; scale applies size.
			pts.append(Vector2(cos(a), sin(a)) * 8.0)
		_rain_marker.polygon = pts
		_rain_marker.z_index = -1
		_rain_marker.visible = false
		add_child(_rain_marker)
	if inventory_ui.visible or death_state != DeathState.ALIVE:
		_rain_marker.visible = false
		return
	var equipped := get_equipped_weapon()
	var show_marker := false
	if equipped != null and equipped.durability > 0.0 and equipped.forms.has("rain") and not spell_input_sequence.is_empty():
		var recipe := all_spell_recipes.get_spell_recipe_from_sequence(spell_input_sequence)
		if not recipe.is_empty() and recipe.get("form", "") == "rain" and recipe.get("element", "") == equipped.element:
			var sd := all_spell_data.build_spell_data(equipped.type, equipped.element, "rain", equipped.rarity)
			# Follows the mouse (clamped to range), matching where cast_spell drops
			# the zone — not a fixed point ahead.
			_rain_marker.position = _targeted_cast_offset(sd["spawn_offset"])
			_rain_marker.scale = Vector2.ONE * sd["size"]
			_rain_marker.color = Color(sd["color"], 0.25)
			show_marker = true
	_rain_marker.visible = show_marker

func attack_check():
	if get_equipped_weapon() == null:
		return
	var holding_spell_mode := Input.is_action_pressed("spell_mode_1") or Input.is_action_pressed("spell_mode_2")
	if Input.is_action_pressed("attack") and attack_timer <= 0.0:
		var spell_data = get_default_spell_data() if holding_spell_mode else get_spell_data()
		# Not enough mana — the cast just fizzles (no cooldown, no
		# durability, no projectile) rather than firing anyway, since mana
		# is meant to actually gate how often sequences can be thrown out.
		# has_relevant_spell_prefix() already keeps a sequence from reaching
		# this state in the normal case (it auto-clears the moment every
		# remaining valid completion becomes unaffordable), but this is the
		# backstop for the rare edge case where mana dropped out from under
		# an already-completed sequence (e.g. a spell_mode default cast in
		# between) — clearing here guarantees you're never stuck holding a
		# sequence you can only escape by deliberately fumbling it.
		if !_is_in_hub() and get_equipped_weapon().mana < effective_mana_cost(spell_data):
			if !holding_spell_mode:
				spell_input_sequence.clear()
				refresh_spell_ui()
			return
		cast_spell(spell_data, !holding_spell_mode)
		attack_timer = spell_data["attack_cooldown"]
		is_attacking = true
		play_body_anim("attack")
		state = attack_state

func attack_state(delta):
	# Legs keep walking/idling off actual movement the whole time — only
	# the upper body is doing the "attack" animation here.
	if Input.is_action_pressed("spell_mode_1"):
		apply_friction(delta)
		check_spell_mode_1_input()
		update_animations(Vector2.ZERO)
	else:
		var raw_input = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		var input_axis = snap_to_8_directions(raw_input)
		if is_moving(input_axis):
			apply_acceleration(delta, input_axis)
		else:
			apply_friction(delta)
		update_legs_rotation(input_axis)
		update_animations(input_axis)
		if Input.is_action_pressed("spell_mode_2"):
			check_spell_mode_2_input()
	update_aim()
	attack_check()
	move_and_slide()
	if !Input.is_action_pressed("attack"):
		is_attacking = false
		play_body_anim("idle")
		state = move_state

func _on_roof_sense_body_entered(body: Node2D) -> void:
	body.make_translucent(self, true)

func _on_roof_sense_body_exited(body: Node2D) -> void:
	body.make_translucent(self, false)
