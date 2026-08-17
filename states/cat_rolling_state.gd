class_name CatRollingState
extends CatStateBase

## 翻滚状态

@export var roll_speed: float = 5.0
@export var roll_duration: float = 2.0

var _timer: float = 0.0
var _original_rotation: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("rolling")
	_timer = 0.0
	_original_rotation = cat.rotation

func update(delta: float) -> void:
	_timer += delta
	cat.rotation += delta * roll_speed

	if _timer >= roll_duration:
		transition_to(CatStates.IDLE)

func exit() -> void:
	cat.rotation = _original_rotation
