extends Projectile

func _ready() -> void:
	projectile_type = "ice_bomb"
	set_physics_process(false)
