extends RefCounted
class_name WeaponMod

# Base hook interface for subclasses and traits (docs/combat_redesign_plan.md §6.3).
# Mods are STATELESS singletons: caster state lives in player.mod_state[weapon
# instance id], projectile state on the projectile. Never reference SpellData here
# or in any mod script (preload cycle through the projectile scenes).

var id := ""

# --- caster's own peer ---------------------------------------------------------
# Rewrite the basic's spell_data (pellets/spread/cooldown/damage_mult/size...).
func modify_basic(_player, _weapon, _sd: Dictionary) -> void: pass
func on_basic_fire(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_spell_cast(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_roll(_player, _weapon, _phase: String) -> void: pass             # "start" / "end"
func on_graze(_player, _weapon) -> void: pass                            # rolled through an enemy bullet
func on_kill(_player, _weapon, _info: Dictionary) -> void: pass          # {"pos","element","archetype","status_mask","form","tag"}
func on_hurt(_player, _weapon, _amount: float) -> void: pass
func tick(_player, _weapon, _delta: float) -> void: pass
# Drawn on the player node (every peer that runs it locally only).
func draw(_player, _weapon, _canvas: CanvasItem) -> void: pass

# --- every peer that simulates the projectile --------------------------------------
func on_projectile_spawn(_proj, _cast: Dictionary) -> void: pass
func on_projectile_hit(_proj, _hurtbox, _cast: Dictionary) -> void: pass
func on_projectile_wall(_proj, _cast: Dictionary) -> void: pass
func on_projectile_expire(_proj, _pos: Vector2, _cast: Dictionary) -> void: pass

# --- defender's authority -------------------------------------------------------------
func on_hit_resolved(_defender, _hitbox, _damage: float, _advantage: bool) -> void: pass
