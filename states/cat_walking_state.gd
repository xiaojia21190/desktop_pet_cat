class_name CatWalkingState
extends CatStateBase

## 行走状态

@export var walk_speed: float = 100.0

var target_position: Vector2 = Vector2.ZERO

func enter(msg: Dictionary = {}) -> void:
	if msg.has("target"):
		target_position = msg["target"]
	else:
		var screen_size := get_screen_size()
		target_position = Vector2(
			randf_range(50, screen_size.x - 50),
			randf_range(50, screen_size.y - 50)
		)

	var distance := cat.global_position.distance_to(target_position) if cat else 0.0
	if distance > 520.0:
		play_animation("run")
	elif distance > 240.0:
		play_animation("trot")
	else:
		play_animation("walk")

	face_toward(target_position)

func physics_update(delta: float) -> void:
	var direction := (target_position - cat.global_position).normalized()
	cat.global_position += direction * walk_speed * delta
	face_direction(direction.x)

	if cat.global_position.distance_squared_to(target_position) < 100:
		transition_to(CatStates.IDLE)
