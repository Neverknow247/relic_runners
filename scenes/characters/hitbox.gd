extends Area2D
class_name Hitbox

@export var damage = 1
# When false, this hitbox never applies damage on area-enter — the owner drives
# damage itself instead (rain's per-second DoT ticks, ball's explosion). The
# projectile's own _on_hitbox_area_entered still fires for detection either way,
# since that's a separate signal connection.
@export var auto_hit := true
var caster_id: int = 0
var attacker_weapon: String = ""
var attacker_element: String = ""
# The attacker's Crit Rate / Crit Damage stats, carried here so the DEFENDER can
# resolve crit at hit time (adding +50 each on element advantage — see each
# _on_hurtbox_hurt). Crit is no longer rolled at cast; it's resolved per-hit on the
# defender's authority, so all peers agree via the defender's damage-number broadcast.
var attacker_crit_rate: float = 0.0
var attacker_crit_damage: float = 0.0
# Legacy field, no longer the source of truth (crit is resolved at the defender).
var is_crit: bool = false
# True when a PLAYER fired this (set from spell_data["from_enemy"] in
# projectile.setup_spell). Player shots never hurt players — no friendly fire.
var from_player := true
# True for an ENEMY's stationary zone (warder pulse, lobbed rain): those only ever
# hurt players, never the pack they're cast in. Enemy bullets still can (the AI
# avoids firing through allies instead).
var enemy_zone := false
# Status buildup inputs (combat_redesign_plan §4.2): the caster's Attack (units =
# damage / attack_ref), whether this is a stratagem (spell-strength effects), and
# the per-cast payload (subclass/traits/seed) for mod hooks.
var attack_ref: float = 0.0
var is_spell := false
var cast: Dictionary = {}

# The single source of truth for "should this hitbox damage that hurtbox?" — used
# by every damage path (this Area2D auto-hit, plus the DoT ticks in beam/rain/cone
# and the ball's explosion, which drive damage themselves). Skips the caster's OWN
# hurtbox, and any player hurtbox for a player-fired shot (friendly fire is off
# between players — 3-player co-op at this zoom/bullet speed was unreadable).
# (Enemies avoid hitting each other via AI — they hold fire
# when an ally is in their firing lane, see enemy._ally_in_firing_lane — rather than
# a bullet-level immunity, so a genuinely mis-aimed shot can still clip an ally.)
func can_hit(hurtbox: Hurtbox) -> bool:
	if caster_id != 0 and hurtbox.owner_id == caster_id:
		return false
	if from_player and hurtbox.is_player:
		return false
	if enemy_zone and not hurtbox.is_player:
		return false
	return true

func _on_area_entered(hurtbox: Area2D) -> void:
	if not auto_hit:
		return
	if not hurtbox is Hurtbox:
		return
	if not can_hit(hurtbox):
		return
	hurtbox.take_hit(self, damage)
