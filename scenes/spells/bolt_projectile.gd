extends Projectile
class_name BoltProjectile

func setup(_direction: Vector2, _projectile_type:= "lightning"):
	super.setup(_direction, _projectile_type)
	match projectile_type:
		"fire":
			speed = 220
			modulate = Color(1.0, 0.45, 0.2)
		"ice":
			speed = 180
			modulate = Color(0.5, 0.85, 1.0)
		"lightning":
			speed = 350
			modulate = Color(1.0, 1.0, 0.3)
