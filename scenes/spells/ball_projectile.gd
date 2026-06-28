extends Projectile
class_name BallProjectile

func setup(_direction: Vector2, _projectile_type := "fire"):
	super.setup(_direction,_projectile_type)
	match projectile_type:
		"fire":
			speed = 190
			scale = Vector2(1.2, 1.2)
			modulate = Color(1.0, 0.25, 0.1)
		"ice":
			speed = 160
			scale = Vector2(1.0, 1.0)
			modulate = Color(0.4, 0.8, 1.0)
