class_name CatCarryingState
extends CatStateBase

## 叼走道具状态

@export var carry_speed: float = 140.0
@export var carry_duration: float = 3.0
@export var carry_offset: Vector2 = Vector2(20, -20)

var _timer: float = 0.0
var _carried_item: Node2D = null
var _carry_target: Vector2 = Vector2.ZERO

func enter(msg: Dictionary = {}) -> void:
	play_animation("idle_active")
	_timer = 0.0

	if msg.has("item"):
		_carried_item = msg["item"]

	# 随机目标位置
	_carry_target = cat.global_position + Vector2(
		randf_range(-200, 200),
		randf_range(-200, 200)
	)

func physics_update(delta: float) -> void:
	if not is_instance_valid(_carried_item):
		_carried_item = null
		transition_to(CatStates.IDLE)
		return

	_timer += delta

	# 移动
	var direction := (_carry_target - cat.global_position).normalized()
	cat.global_position += direction * carry_speed * delta

	# 道具跟随
	_carried_item.global_position = cat.global_position + carry_offset

	# 到达目标或超时
	var arrived := cat.global_position.distance_squared_to(_carry_target) < 400
	if arrived or _timer >= carry_duration:
		_carried_item.queue_free()
		_carried_item = null
		transition_to(CatStates.IDLE)

func exit() -> void:
	_carried_item = null
