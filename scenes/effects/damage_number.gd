extends Node2D

# Purely cosmetic — spawned independently (no networking) on every peer that
# has both the hitbox and hurtbox loaded, since the damage math it displays
# (SpellData.get_damage_multiplier(), applied before the authority check —
# see enemy.gd/player.gd's _on_hurtbox_hurt()) is deterministic from data
# every peer already has, same idea as build_spell_data() being recomputed
# per-peer rather than sent over the wire.

@onready var label: Label = $label

const RISE_DISTANCE := 240.0
const DURATION := 0.6

# effective = the attacker's element beats the defender's (the +50 crit bonus
# applied): shown as a cyan "EFFECTIVE" so players can learn the element wheel.
func setup(amount: float, color: Color, is_crit: bool = false, effective: bool = false) -> void:
	label.text = str(max(1, roundi(amount)))
	label.modulate = color
	if is_crit:
		label.text += "!"
		label.add_theme_font_size_override("font_size", 208)
	if effective:
		label.text += "
EFFECTIVE"
		label.modulate = Color(0.45, 1.0, 1.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, DURATION).set_delay(DURATION * 0.4)
	tween.tween_callback(queue_free)
