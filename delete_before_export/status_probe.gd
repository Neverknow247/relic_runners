extends Node2D
# Dev-only: hits enemies with fake player hitboxes of each element and prints status results.
var es := preload("res://scenes/enemies/enemy.tscn")
func mk(n: String, pos: Vector2, arch := "pentagon") -> Enemy:
	var e: Enemy = es.instantiate(); e.archetype = arch; e.name = n; e.position = pos; add_child(e); return e
func hb(element: String, dmg := 100.0, spell := false) -> Hitbox:
	var h: Hitbox = preload("res://scenes/characters/hitbox.tscn").instantiate()
	add_child(h)
	h.attacker_element = element; h.attack_ref = 100.0; h.damage = dmg; h.is_spell = spell
	h.from_player = true; h.caster_id = 777; h.global_position = Vector2(-500, 0)
	return h
func _ready() -> void:
	var a := mk("a", Vector2(0, 0)); var b := mk("b", Vector2(200, 0)); var c := mk("c", Vector2(2000, 0))
	await get_tree().physics_frame
	a.shield_up = false; b.shield_up = false
	var hp0 := b.health
	a.hurtbox.take_hit(hb("lightning"), 100.0)
	print("STAT chain: b lost ", hp0 - b.health, " (expect ~20 minus DR)")
	a.hurtbox.take_hit(hb("fire"), 100.0); a.hurtbox.take_hit(hb("fire"), 100.0); a.hurtbox.take_hit(hb("fire"), 100.0)
	print("STAT burn stacks=", a.status.amount("burn"), " mask=", a.status_mask)
	var hpa := a.health
	for i in 60: await get_tree().physics_frame
	print("STAT burn 1s dmg=", hpa - a.health)
	c.max_health = 1e7; c.health = 1e7
	c.hurtbox.take_hit(hb("ice"), 100.0)
	for i in 20: c.hurtbox.take_hit(hb("ice"), 100.0)
	print("STAT chill meter=", c.status.amount("chill"), " move_mult=", c.status.move_mult(), " frozen=", c.status.is_disabled())
	c.hurtbox.take_hit(hb("ice", 600.0, true), 600.0)
	print("STAT spell ice frozen=", c.status.is_disabled())
	var sq := mk("sq", Vector2(-2000, 0), "square")
	await get_tree().physics_frame
	sq._windup_left = 0.6
	sq.hurtbox.take_hit(hb("earth"), 100.0)
	print("STAT sunder 1 hit windup=", sq._windup_left)
	sq.hurtbox.take_hit(hb("earth"), 100.0)
	print("STAT sunder 2 hits windup=", sq._windup_left, " staggered=", sq.status.is_disabled())
	b.hurtbox.take_hit(hb("water"), 100.0)
	print("STAT soak out=", b.status.outgoing_mult(), " bspeed=", b.status.bullet_speed_mult())
	b.hurtbox.take_hit(hb("nature"), 100.0)
	print("STAT seed=", b.status.has("seed"))
	# kill a (burning) next to b -> burn jumps
	a.take_damage(99999.0)
	print("STAT a dead=", a.is_dead, " b burn after jump=", b.status.amount("burn"))
	b.take_damage(99999.0)
	print("STAT b dead (seeded -> bloom spawned) ok")
	get_tree().quit()
