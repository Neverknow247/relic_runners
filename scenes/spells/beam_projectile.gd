extends Projectile
class_name BeamProjectile

# A channeled beam that follows its caster (snaps to their position and rotates
# to their aim every frame, so you can sweep it around), deals damage over time
# (hitbox auto_hit off; ticks like rain), and is CUT OFF by the first wall or
# enemy along its path — it doesn't fire through them. Each frame a ray finds
# the nearest obstacle and the beam's hitbox + visual are shortened to it.
# Runs on every peer; only each target's own authority applies the health hit.

const TICK_INTERVAL := 0.2
# Almost the screen's vertical half-height (~360), so a beam reaches near the top/
# bottom edge but never off-screen.
const MAX_LENGTH := 340.0
const BEAM_WIDTH := 24.0
# Walls (layer 1) + enemy bodies (layer 32) stop the beam.
const CUTOFF_MASK := 1 | 32

var _tick_timer := 0.05
var _caster: Node2D = null
@onready var _shape: CollisionShape2D = $hitbox/collision_shape_2d
@onready var _visual: Polygon2D = $beam_visual

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	super.setup_spell(_direction, _spell_data, caster_id, crit)
	# The beam manages its own length/width directly (in global units), so don't
	# let the generic size-scale stretch it.
	scale = Vector2.ONE
	# Own copy of the rect so resizing this beam doesn't touch other instances.
	if _shape != null and _shape.shape != null:
		_shape.shape = _shape.shape.duplicate()
	# Resolve the caster node so the beam follows it and its own body is excluded
	# from the wall/enemy cutoff ray. Works for players AND enemies (see
	# _resolve_caster) — without it an enemy-cast beam had no caster, so it never
	# excluded the caster and, following nothing, fired straight through walls.
	_caster = _resolve_caster()
	if _caster != null and is_instance_valid(_caster):
		global_position = _caster.global_position
	# Size the beam to its real (wall-cut) length NOW, before the first frame is
	# drawn — otherwise it renders one frame at the scene's default full length
	# and then snaps down, which reads as a big flicker.
	_update_length()

func _physics_process(delta: float) -> void:
	if _caster != null and is_instance_valid(_caster):
		global_position = _caster.global_position
		# Players sweep the beam with their live mouse aim; enemies have no such
		# aim to replicate, so their beam keeps the fixed direction it was cast in.
		if _caster.has_method("get_networked_aim"):
			rotation = _caster.get_networked_aim().angle()
	_update_length()
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_apply_tick()

# Raycast forward from the caster and shorten the beam to the first wall/enemy.
func _update_length() -> void:
	var space := get_world_2d().direct_space_state
	var forward := Vector2.RIGHT.rotated(rotation)
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + forward * MAX_LENGTH)
	query.collision_mask = CUTOFF_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _caster != null and is_instance_valid(_caster):
		query.exclude = [_caster.get_rid()]
	var hit := space.intersect_ray(query)
	var length: float = MAX_LENGTH
	if not hit.is_empty():
		length = global_position.distance_to(hit["position"])
	if _shape != null and _shape.shape != null:
		_shape.shape.size = Vector2(length, BEAM_WIDTH)
		_shape.position = Vector2(length / 2.0, 0.0)
	if _visual != null:
		var hw := BEAM_WIDTH / 2.0
		_visual.polygon = PackedVector2Array([
			Vector2(0, -hw), Vector2(length, -hw), Vector2(length, hw), Vector2(0, hw)
		])

func _apply_tick() -> void:
	# Full computed damage spread across the lifetime's ticks (so the whole amount
	# only lands on a target the beam stays on the entire time), with crit rolled
	# per tick (dot forms don't bake crit at spawn — see spell_data.gd).
	var tick_base: float = hitbox.damage * TICK_INTERVAL / lifetime
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
			continue
		var dmg := tick_base
		hitbox.is_crit = randf() * 100.0 < spell_data.get("crit_chance", 0.0)
		if hitbox.is_crit:
			dmg *= spell_data.get("crit_multiplier", 1.0)
		area.take_hit(hitbox, dmg)
