class_name CatEatingState
extends CatStateBase

## 吃东西状态(带仪式感):注意到食物→定睛闻闻→走近→开吃→满足舔嘴

@export var walk_speed: float = 100.0
@export var eat_duration: float = 2.0
@export var interact_distance_sq: float = 1600.0  # 40px
@export var sniff_duration: float = 0.7   # 定睛闻闻
@export var purr_duration: float = 1.2    # 饭后舔嘴

var _timer: float = 0.0
var _target_item: Node2D = null
var _phase := 0  # 0=闻 1=走 2=吃 3=舔嘴
var _move_dir := Vector2.RIGHT  # P10 平滑方向
var _speed_ramp := 0.0          # P10 起步渐变

func enter(msg: Dictionary = {}) -> void:
	_timer = 0.0
	_phase = 0
	_move_dir = Vector2.RIGHT
	_speed_ramp = 0.0
	if msg.has("item"):
		_target_item = msg["item"]
	# 开场:先定睛注意食物(不是直愣愣冲过去)
	play_animation("watch_focus")
	face_toward(_target_item.global_position if is_instance_valid(_target_item) else cat.global_position)

func physics_update(delta: float) -> void:
	if not is_instance_valid(_target_item):
		_target_item = null
		transition_to(CatStates.IDLE)
		return

	var item_pos := _target_item.global_position
	var dist_sq := cat.global_position.distance_squared_to(item_pos)

	match _phase:
		0:  # 闻闻:定睛打量食物
			_timer += delta
			if _timer >= sniff_duration:
				_phase = 1
				_timer = 0.0
				play_animation("walk")
			return
		1:  # 走过去（P10：方向 lerp + 起步渐变）
			if dist_sq > interact_distance_sq:
				var direction := (item_pos - cat.global_position).normalized()
				_move_dir = _move_dir.lerp(direction, 0.15).normalized()
				_speed_ramp = minf(_speed_ramp + delta / 0.3, 1.0)
				cat.global_position += _move_dir * walk_speed * _speed_ramp * delta
				face_direction(direction.x)
				return
			_phase = 2
			_timer = 0.0
			play_animation("eat")
			return
		2:  # 吃
			_timer += delta
			if _timer >= eat_duration:
				_target_item.queue_free()
				_target_item = null
				_phase = 3
				_timer = 0.0
				play_animation("lick_groom")  # 饭后舔嘴满足
			return
		3:  # 舔嘴
			_timer += delta
			if _timer >= purr_duration:
				transition_to(CatStates.IDLE)
			return

func exit() -> void:
	_target_item = null
