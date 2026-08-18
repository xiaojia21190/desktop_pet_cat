class_name CatChasingState
extends CatStateBase

## 追逐鼠标状态

@export var chase_speed: float = 300.0
@export var catch_distance_sq: float = 2500.0  # 50px
@export var pounce_chance: float = 0.8  # 追上后转入扑咬玩闹连招的概率

func enter(_msg: Dictionary = {}) -> void:
	play_animation("chasing")

func physics_update(delta: float) -> void:
	var mouse_pos := get_mouse_position()
	var direction := (mouse_pos - cat.global_position).normalized()

	cat.global_position += direction * chase_speed * delta
	face_direction(direction.x)

	if cat.global_position.distance_squared_to(mouse_pos) < catch_distance_sq:
		# 追上了:大概率兴奋扑咬玩闹(定睛→蓄力→扑→落地),否则满足回空闲
		if randf() < pounce_chance:
			transition_to(CatStates.POUNCING, {"target": mouse_pos})
		else:
			transition_to(CatStates.IDLE)
