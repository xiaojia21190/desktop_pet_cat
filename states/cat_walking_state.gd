class_name CatWalkingState
extends CatStateBase

## 行走状态（P10 移动平滑：方向 lerp + 起步速度渐变）

@export var walk_speed: float = 100.0

var target_position: Vector2 = Vector2.ZERO
var _move_dir := Vector2.ZERO   # P10 平滑方向
var _speed_ramp := 0.0          # P10 起步渐变 0→1

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
	# P10：初始方向直接朝目标（首帧无折线），速度从 0 渐起
	_move_dir = (target_position - cat.global_position).normalized() if cat else Vector2.RIGHT
	_speed_ramp = 0.0

func physics_update(delta: float) -> void:
	var direction := (target_position - cat.global_position).normalized()
	# P10 平滑：方向 lerp（微调不折线）+ 速度 ramp（起步不突兀）
	_move_dir = _move_dir.lerp(direction, 0.15).normalized()
	_speed_ramp = minf(_speed_ramp + delta / 0.3, 1.0)
	cat.global_position += _move_dir * walk_speed * _speed_ramp * delta
	face_direction(direction.x)

	if cat.global_position.distance_squared_to(target_position) < 100:
		transition_to(CatStates.IDLE)
