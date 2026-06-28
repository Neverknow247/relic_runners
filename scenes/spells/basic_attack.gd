extends Projectile
class_name BasicAttack

func setup(_direction: Vector2, _projectile_type := "basic"):
	super.setup(_direction, _projectile_type)
	speed = 250
