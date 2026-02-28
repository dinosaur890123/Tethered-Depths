extends CharacterBody2D

const SPEED = 150.0

func _physics_process(delta):
	var direction_x = Input.get_axis("ui_left", "ui_right")
	var direction_y = Input.get_axis("ui_up", "ui_down")
	if direction_x != 0:
		direction_y = 0

	self.velocity = Vector2(direction_x, direction_y).normalized() * SPEED
	move_and_slide()
