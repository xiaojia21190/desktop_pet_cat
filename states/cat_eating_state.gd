class_name CatEatingState
extends CatStateBase

## 吃东西状态

@export var walk_speed: float = 100.0
@export var eat_duration: float = 2.0
@export var interact_distance_sq: float = 1600.0  # 40px

var _timer: float = 0.0
var _target_item: Node2D = null

func enter(msg: Dictionary = {}) -> void:
	play_animation("idle_active")
	_timer = 0.0

	if msg.has("item"):
		_target_item = msg["item"]

func physics_update(delta: float) -> void:
	if not is_instance_valid(_target_item):
		_target_item = null
		transition_to(CatStates.IDLE)
		return

	var item_pos := _target_item.global_position
	var dist_sq := cat.global_position.distance_squared_to(item_pos)

	# 还没到达道具，继续走
	if dist_sq > interact_distance_sq:
		var direction := (item_pos - cat.global_position).normalized()
		cat.global_position += direction * walk_speed * delta
		return

	# 正在吃
	_timer += delta
	if _timer >= eat_duration:
		_target_item.queue_free()
		_target_item = null
		transition_to(CatStates.IDLE)

func exit() -> void:
	_target_item = null
