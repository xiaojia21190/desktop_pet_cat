class_name CatChasingState
extends CatStateBase

## 追逐鼠标状态

@export var chase_speed: float = 300.0
@export var catch_distance_sq: float = 2500.0  # 50px

func enter(_msg: Dictionary = {}) -> void:
	play_animation("idle_active")

func physics_update(delta: float) -> void:
	var mouse_pos := get_mouse_position()
	var direction := (mouse_pos - cat.global_position).normalized()

	cat.global_position += direction * chase_speed * delta
	cat.look_at(mouse_pos)

	# 追到鼠标
	if cat.global_position.distance_squared_to(mouse_pos) < catch_distance_sq:
		transition_to(CatStates.IDLE)
