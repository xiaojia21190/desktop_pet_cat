class_name CatPouncingState
extends CatStateBase

## 扑击状态

@export var pounce_speed: float = 300.0
@export var pounce_duration: float = 1.0

var _timer: float = 0.0
var _target: Vector2

func enter(msg: Dictionary = {}) -> void:
	play_animation("idle_active")
	_timer = 0.0

	if msg.has("target"):
		_target = msg["target"]
	else:
		_target = get_mouse_position()

func physics_update(delta: float) -> void:
	_timer += delta

	var direction := (_target - cat.global_position).normalized()
	cat.global_position += direction * pounce_speed * delta

	if _timer >= pounce_duration:
		transition_to(CatStates.IDLE)
