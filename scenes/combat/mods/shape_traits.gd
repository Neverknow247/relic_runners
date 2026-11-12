extends WeaponMod
# Shape traits (one per weapon). Theoretical basic DPS stays at the 2.857 x Attack
# baseline (combat_redesign_plan §7.5); `id` picks the shape.

func modify_basic(_player, _weapon, sd: Dictionary) -> void:
	match id:
		"split":
			sd["pellets"] = 3
			sd["spread_deg"] = 28.0
			sd["damage_mult"] = 0.42
			sd["attack_cooldown"] = 0.44
		"torrent":
			sd["damage_mult"] = 0.40
			sd["attack_cooldown"] = 0.14
			sd["size"] = float(sd.get("size", 1.0)) * 0.75
			sd["knockback_mult"] = 0.4
		"heavy":
			sd["damage_mult"] = 2.0
			sd["attack_cooldown"] = 0.70
			sd["size"] = float(sd.get("size", 1.0)) * 1.4
			sd["speed"] = float(sd.get("speed", 0.0)) * 0.6
			sd["pierce_count"] = int(sd.get("pierce_count", 0)) + 1
			sd["knockback_mult"] = 2.5
		"twin":
			sd["damage_mult"] = 0.5
			sd["attack_cooldown"] = 0.35

func on_basic_fire(_player, _weapon, _sd: Dictionary, cast: Dictionary) -> void:
	match id:
		"torrent":
			if !cast.has("off"):
				cast["off"] = PackedFloat32Array([deg_to_rad(randf_range(-3.0, 3.0))])
		"twin":
			cast["lat"] = PackedFloat32Array([-24.0, 24.0])
