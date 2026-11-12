extends Node
class_name StatusHolder

# Per-character status state (docs/combat_redesign_plan.md §4.3). Lives as a child
# of an Enemy (server-authoritative) or a Player (own peer). Only the owner's
# authority mutates it; visuals on other peers read the synced status_mask that
# the owner writes from `changed`.
#
# Generic timed entries (`_timed`) cover everything that is just "on for N seconds"
# (soak, seed, staggered, frozen, buffs); burn and chill keep their own state.

signal dot_tick(amount: float, id: String, src_peer: int)
signal changed(mask: int)

var is_player := false
var tier := "bronze"            # enemies: drives CC scaling
var max_health_ref := 100.0      # players: softened burn is a % of max HP

const D := StatusEffects.DEFS

# burn (enemy): stacks, time left, tick timer, source attack/peer
var _burn_stacks := 0.0
var _burn_left := 0.0
var _burn_tick := 0.0
var _burn_attack := 0.0
var _burn_peer := 0
# burn (player, softened): one stack
var _pburn_left := 0.0
var _pburn_tick := 0.0

var _chill := 0.0
var _chill_since_hit := 0.0
var _freeze_immune := 0.0
var _stagger_immune := 0.0

# id -> seconds left; _values: id -> number (buff strength)
var _timed := {}
var _values := {}

var _mask := 0

# --- queries -------------------------------------------------------------------

func has(id: String) -> bool:
	match id:
		"burn":
			return _burn_left > 0.0 or _pburn_left > 0.0
		"chill":
			return _chill > 0.0 or _timed.has("p_chill")
	return _timed.has(id)

func amount(id: String) -> float:
	match id:
		"burn":
			return _burn_stacks if _burn_left > 0.0 else (1.0 if _pburn_left > 0.0 else 0.0)
		"chill":
			return _chill
	return float(_values.get(id, 1.0)) if _timed.has(id) else 0.0

func time_left(id: String) -> float:
	return float(_timed.get(id, 0.0))

func move_mult() -> float:
	var m := 1.0
	if is_player:
		var slow := 0.0
		if _timed.has("p_chill"):
			slow = D["p_chill"]["slow"]
		m = 1.0 - minf(slow, D["p_max_slow"])
		if _timed.has("haste"):
			m *= 1.0 + float(_values.get("haste", 0.2))
		return m
	if _timed.has("frozen") or _timed.has("staggered"):
		return 0.0
	var max_slow: float = D["chill"]["gold_max_slow"] if tier == "gold" else D["chill"]["max_slow"]
	m = 1.0 - max_slow * clampf(_chill / 100.0, 0.0, 1.0)
	if _timed.has("dirge"):
		m *= 1.0 - float(_values.get("dirge", 0.2))
	return maxf(m, 0.0)

func is_disabled() -> bool:
	return _timed.has("frozen") or _timed.has("staggered")

# Outgoing damage multiplier while soaked (enemy bullets / player basics).
func outgoing_mult() -> float:
	if is_player:
		return D["p_soak"]["basic_mult"] if _timed.has("p_soak") else 1.0
	return D["soak"]["damage_mult"] if _timed.has("soak") else 1.0

func bullet_speed_mult() -> float:
	return D["soak"]["bullet_speed_mult"] if (!is_player and _timed.has("soak")) else 1.0

func mask() -> int:
	return _mask

# --- mutation (authority only) ----------------------------------------------------

# src = {"peer": int, "attack": float, "spell": bool}
func apply(id: String, units: float, src: Dictionary) -> void:
	if units <= 0.0:
		return
	var spell: bool = src.get("spell", false)
	if is_player:
		_apply_player(id)
		return
	match id:
		"burn":
			var per: float = D["burn"]["spell_per_unit"] if spell else D["burn"]["basic_per_unit"]
			var cap: float = D["burn"]["spell_cap"] if spell else D["burn"]["basic_cap"]
			# Basics never push stacks past their cap, but don't strip a spell's stacks.
			_burn_stacks = maxf(_burn_stacks, minf(_burn_stacks + per * units, cap))
			_burn_left = D["burn"]["duration"]
			_burn_attack = maxf(_burn_attack, float(src.get("attack", 0.0)))
			_burn_peer = int(src.get("peer", _burn_peer))
		"chill":
			_chill_since_hit = 0.0
			if spell:
				_chill = minf(_chill + D["chill"]["spell_per_unit"] * units, 100.0)
				if _chill >= 100.0:
					freeze(D["chill"]["freeze_sec"])
			else:
				_chill = maxf(_chill, minf(_chill + D["chill"]["basic_per_unit"] * units, D["chill"]["basic_cap"]))
		"soak":
			var sec: float = D["soak"]["spell_sec"] if spell else minf(time_left("soak") + D["soak"]["basic_sec_per_unit"] * units, D["soak"]["basic_cap"])
			add_timed("soak", maxf(sec, time_left("soak")))
		"seed":
			add_timed("seed", maxf(D["seed"]["spell_sec"] if spell else D["seed"]["basic_sec"], time_left("seed")))
			if spell:
				add_timed("overgrown", D["seed"]["spell_sec"])
	_refresh_mask()

func _apply_player(id: String) -> void:
	match id:
		"burn":
			if _pburn_left <= 0.0:
				_pburn_tick = D["p_burn"]["tick_interval"]
			_pburn_left = D["p_burn"]["duration"]
		"chill":
			add_timed("p_chill", D["p_chill"]["duration"])
		"soak":
			add_timed("p_soak", D["p_soak"]["duration"])
	_refresh_mask()

# Hard CC with tier scaling + immunity windows. Returns true if it landed.
func freeze(sec: float) -> bool:
	if is_player or _freeze_immune > 0.0:
		return false
	var m: float = D["tier_cc_mult"].get(tier, 1.0)
	if m <= 0.0:
		return false
	add_timed("frozen", sec * m)
	_freeze_immune = sec * m + D["chill"]["freeze_immune_sec"]
	_chill = 0.0
	_refresh_mask()
	return true

# `force` (gold): only allowed while interrupting a wind-up, decided by the caller.
func stagger(sec: float, force: bool = false) -> bool:
	if is_player or _stagger_immune > 0.0:
		return false
	var m: float = D["tier_cc_mult"].get(tier, 1.0)
	if m <= 0.0:
		if !force:
			return false
		m = 0.6
	add_timed("staggered", sec * m)
	_stagger_immune = sec * m + D["sunder"]["stagger_immune_sec"]
	_refresh_mask()
	return true

func add_timed(id: String, sec: float, value: float = 1.0) -> void:
	_timed[id] = maxf(float(_timed.get(id, 0.0)), sec)
	_values[id] = value
	_refresh_mask()

func remove(id: String) -> void:
	if id == "burn":
		_burn_left = 0.0
		_burn_stacks = 0.0
		_pburn_left = 0.0
	elif id == "chill":
		_chill = 0.0
		_timed.erase("p_chill")
	else:
		_timed.erase(id)
		_values.erase(id)
	_refresh_mask()

func clear_all() -> void:
	_burn_left = 0.0
	_burn_stacks = 0.0
	_pburn_left = 0.0
	_chill = 0.0
	_timed.clear()
	_values.clear()
	_refresh_mask()

# Burn handed to a neighbour when its host dies (half the stacks).
func burn_state() -> Dictionary:
	if _burn_left <= 0.0:
		return {}
	return {"stacks": _burn_stacks, "attack": _burn_attack, "peer": _burn_peer}

func receive_burn(stacks: float, attack: float, peer: int) -> void:
	if is_player or stacks <= 0.0:
		return
	_burn_stacks = maxf(_burn_stacks, stacks)
	_burn_left = D["burn"]["duration"]
	_burn_attack = maxf(_burn_attack, attack)
	_burn_peer = peer
	_refresh_mask()

# --- tick (authority's _physics_process) -----------------------------------------

func tick(delta: float) -> void:
	_freeze_immune = maxf(_freeze_immune - delta, 0.0)
	_stagger_immune = maxf(_stagger_immune - delta, 0.0)
	if _burn_left > 0.0:
		_burn_left -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick += D["burn"]["tick_interval"]
			dot_tick.emit(_burn_stacks * D["burn"]["tick_frac"] * _burn_attack, "burn", _burn_peer)
		if _burn_left <= 0.0:
			_burn_stacks = 0.0
			_refresh_mask()
	if _pburn_left > 0.0:
		_pburn_left -= delta
		_pburn_tick -= delta
		if _pburn_tick <= 0.0:
			_pburn_tick += D["p_burn"]["tick_interval"]
			dot_tick.emit(D["p_burn"]["tick_frac_max_hp"] * max_health_ref, "burn", 0)
		if _pburn_left <= 0.0:
			_refresh_mask()
	if _chill > 0.0:
		_chill_since_hit += delta
		if _chill_since_hit > D["chill"]["decay_delay"]:
			_chill = maxf(_chill - D["chill"]["decay_per_sec"] * delta, 0.0)
			if _chill <= 0.0:
				_refresh_mask()
	if !_timed.is_empty():
		var expired := false
		for id in _timed.keys():
			var left: float = _timed[id] - delta
			if left <= 0.0:
				_timed.erase(id)
				_values.erase(id)
				expired = true
			else:
				_timed[id] = left
		if expired:
			_refresh_mask()

func _refresh_mask() -> void:
	var m := 0
	if _burn_left > 0.0 or _pburn_left > 0.0:
		m |= StatusEffects.bit("burn")
	if _chill > 0.0 or _timed.has("p_chill"):
		m |= StatusEffects.bit("chill")
	for id in _timed:
		var name_id: String = id
		if name_id.begins_with("p_"):
			name_id = name_id.substr(2)
		m |= StatusEffects.bit(name_id)
	if m != _mask:
		_mask = m
		changed.emit(m)
