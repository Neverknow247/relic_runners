class_name Combat

# Shared hit resolution (docs/combat_redesign_plan.md §4.6). Called only from the
# defender's hurt handler (player.gd / enemy.gd), never from projectile scripts —
# this references SpellData, and projectile scripts must not (preload cycle).

# Crit (attacker stats, +50/+50 on element advantage) then Defense DR.
# Returns {"damage", "is_crit", "advantage"}.
static func resolve_hit(hitbox, damage: float, defender_element: String, defense: float) -> Dictionary:
	var final_damage := damage
	var is_crit := false
	var advantage := false
	if hitbox != null and "attacker_element" in hitbox:
		advantage = SpellData.has_advantage(hitbox.attacker_element, defender_element)
		var crit_rate: float = hitbox.attacker_crit_rate + (50.0 if advantage else 0.0)
		var crit_damage: float = hitbox.attacker_crit_damage + (50.0 if advantage else 0.0)
		is_crit = randf() * 100.0 < crit_rate
		if is_crit:
			final_damage *= 1.0 + crit_damage / 100.0
	final_damage *= 1.0 - SpellData.damage_reduction(defense)
	return {"damage": final_damage, "is_crit": is_crit, "advantage": advantage}

# Status buildup is proportional to damage: units = damage / caster Attack, so a
# baseline basic is 1 unit, a fireball 6, a beam tick ~1.7 — equal DPS, equal
# buildup, whatever the shape. Element advantage multiplies units by 1.5.
static func hit_units(hitbox, pre_mitigation_damage: float, advantage: bool) -> float:
	var ref: float = hitbox.attack_ref if "attack_ref" in hitbox else 0.0
	if ref <= 0.0:
		ref = maxf(pre_mitigation_damage, 1.0)
	return pre_mitigation_damage / maxf(ref, 1.0) * (1.5 if advantage else 1.0)

# Element side effects of a hit. The defender implements
# receive_element_hit(element, units, is_spell, hitbox, pre_damage); this only
# gates and converts. Secondary hits (arcs, blooms, DoT ticks) never come here,
# so nothing can loop.
static func apply_on_hit(defender: Node, hitbox, pre_mitigation_damage: float, advantage: bool) -> void:
	if defender == null or hitbox == null or !is_instance_valid(hitbox):
		return
	if !("attacker_element" in hitbox):
		return
	var element: String = hitbox.attacker_element
	if element == "" or element == "default":
		return
	if !defender.has_method("receive_element_hit"):
		return
	var units := hit_units(hitbox, pre_mitigation_damage, advantage)
	var spell: bool = hitbox.is_spell if "is_spell" in hitbox else false
	# Attuned (trait): basics build their element 50% faster.
	if !spell and "cast" in hitbox and hitbox.cast.get("tr", []).has("attuned"):
		units *= 1.5
	defender.receive_element_hit(element, units, spell, hitbox, pre_mitigation_damage)
	# Mods' on_hit_resolved (subclasses / traits) on the defender's authority.
	var cast: Dictionary = hitbox.cast if "cast" in hitbox else {}
	if !cast.is_empty() and hitbox.from_player:
		for mod in WeaponMods.for_cast(cast):
			mod.on_hit_resolved(defender, hitbox, pre_mitigation_damage, advantage)
