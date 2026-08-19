class_name CatChasingState
extends CatStateBase

## 追逐鼠标状态（P10 移动平滑：方向 lerp + 起步速度渐变）

@export var chase_speed: float = 300.0
@export var catch_distance_sq: float = 2500.0  # 50px
@export var pounce_chance: float = 0.8  # 追上后转入扑咬玩闹连招的概率

var _move_dir := Vector2.RIGHT  # P10 平滑方向
var _speed_ramp := 0.0          # P10 起步渐变 0→1

func enter(_msg: Dictionary = {}) -> void:
	play_animation("chasing")
	_move_dir = Vector2.RIGHT
	_speed_ramp = 0.0

func physics_update(delta: float) -> void:
	var mouse_pos := get_mouse_position()
	var target_dir := (mouse_pos - cat.global_position).normalized()

	# P10 平滑：方向 lerp（转向不折线）+ 速度 ramp（起步不突兀）
	_move_dir = _move_dir.lerp(target_dir, 0.15).normalized()
	_speed_ramp = minf(_speed_ramp + delta / 0.3, 1.0)
	cat.global_position += _move_dir * chase_speed * _speed_ramp * delta
	face_direction(target_dir.x)

	if cat.global_position.distance_squared_to(mouse_pos) < catch_distance_sq:
		# 追上了:大概率兴奋扑咬玩闹(定睛→蓄力→扑→落地),否则满足回空闲
		if randf() < pounce_chance:
			transition_to(CatStates.POUNCING, {"target": mouse_pos})
		else:
			transition_to(CatStates.IDLE)
