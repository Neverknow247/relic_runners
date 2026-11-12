extends WeaponMod
# Wand — Duelist: rolling through an enemy bullet loads a Riposte. The next basic is
# a fast piercing counter-shot at whoever fired it; a spell cast with Riposte loaded
# fires as normal and staggers what it hits.

func on_graze(player, weapon, bullet) -> void:
	var s := st(player, weapon)
	s["riposte"] = true
	var src = null
	if bullet != null and is_instance_valid(bullet):
		for e in player.get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e.name.hash() == bullet.hitbox.caster_id:
				src = e
				break
	s["dir"] = (src.global_position - player.global_position).normalized() if src != null else Vector2.ZERO
	Fx.flash(player.sprite, true, 2.5, 0.2)

func modify_basic(player, weapon, sd: Dictionary) -> void:
	var s := st(player, weapon)
	if !s.get("riposte", false):
		return
	sd["speed"] = float(sd.get("speed", 0.0)) * 1.8
	sd["damage_mult"] = float(sd.get("damage_mult", 1.0)) * 2.0
	sd["pierce_count"] = int(sd.get("pierce_count", 0)) + 3
	if s.get("dir", Vector2.ZERO) != Vector2.ZERO:
		sd["_aim_override"] = s["dir"]

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if !derived(cast):
		st(player, weapon)["riposte"] = false

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	var s := st(player, weapon)
	if derived(cast) or !s.get("riposte", false):
		return
	s["riposte"] = false
	var x: Dictionary = cast.get("x", {})
	x["riposte"] = 1
	cast["x"] = x

func on_hit_resolved(defender, hitbox, _damage: float, _adv: bool) -> void:
	if hitbox.cast.get("x", {}).get("riposte", 0):
		defender.fx_stagger(1.0)

func draw(player, weapon, canvas: CanvasItem) -> void:
	if st(player, weapon).get("riposte", false):
		canvas.draw_arc(Vector2.ZERO, 96.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.4, 0.8), 5.0)
