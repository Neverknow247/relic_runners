extends Projectile
class_name RainProjectile

# A stationary ground zone that ticks full form damage each second to anyone
# standing in it (its hitbox has auto_hit off, so this DoT is the only damage).
# Runs on every peer that spawned it, but take_hit -> _on_hurtbox_hurt only
# applies the health change on each target's own authority, so damage lands once.

const TICK_INTERVAL := 1.0
# First tick shortly after spawn (once the area's overlaps have registered a
# physics frame in), so someone already standing in it gets hit promptly.
var _tick_timer := 0.1

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_apply_tick()

func _apply_tick() -> void:
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
			continue
		area.take_hit(hitbox, hitbox.damage)
