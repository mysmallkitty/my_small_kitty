extends Orb

func _orb_func(body:Player):
	if global_rotation_degrees < 45 and global_rotation_degrees > -45:
		body._vel = Vector2(0,-200)
	elif global_rotation_degrees < 180 and global_rotation_degrees > 10:
		body._vel = Vector2(300,0)
	elif global_rotation_degrees < 0 and global_rotation_degrees > -170:
		body._vel = Vector2(-300,0)
	else:
		body._vel = Vector2(0,200)
