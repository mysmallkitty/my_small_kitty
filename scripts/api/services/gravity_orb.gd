extends Orb

func _orb_func(body:Player):
	body.up_direction = Vector2i(body.up_direction.x,body.up_direction.y * -1)
	body.scale.y = -1 * body.scale.y
