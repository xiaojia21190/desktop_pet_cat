class_name CatLickingState
extends CatStateBase

## Licking state
@export var lick_duration: float = 1.6
@export var lick_wobble_speed: float = 6.0
@export var lick_wobble_amplitude: float = 0.08

var _timer: float = 0.0
var _base_rotation: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("lick_groom")
	_timer = 0.0
	_base_rotation = cat.rotation

func update(delta: float) -> void:
	_timer += delta
	cat.rotation = _base_rotation + sin(_timer * lick_wobble_speed) * lick_wobble_amplitude

	if _timer >= lick_duration:
		transition_to(CatStates.IDLE)

func exit() -> void:
	cat.rotation = _base_rotation
