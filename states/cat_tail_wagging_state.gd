class_name CatTailWaggingState
extends CatStateBase

## 甩尾状态

@export var wag_speed: float = 10.0
@export var wag_amplitude: float = 0.3
@export var wag_duration: float = 2.0

var _timer: float = 0.0
var _original_rotation: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("tail_wag")
	_timer = 0.0
	_original_rotation = cat.rotation

func update(delta: float) -> void:
	_timer += delta
	cat.rotation = sin(_timer * wag_speed) * wag_amplitude

	if _timer >= wag_duration:
		transition_to(CatStates.IDLE)

func exit() -> void:
	cat.rotation = _original_rotation
