class_name CatPouncingState
extends CatStateBase

## 扑击状态

@export var pounce_speed: float = 300.0
@export var prep_duration: float = 0.2
@export var jump_duration: float = 0.3
@export var attack_duration: float = 0.25
@export var land_duration: float = 0.2
@export var attack_arrive_distance_sq: float = 1600.0

var _timer: float = 0.0
var _target: Vector2
var _phase: int = 0

func enter(msg: Dictionary = {}) -> void:
	play_animation("pounce_ready")
	_timer = 0.0
	_phase = 0

	if msg.has("target"):
		_target = msg["target"]
	else:
		_target = get_mouse_position()

	face_toward(_target)

func physics_update(delta: float) -> void:
	_timer += delta

	if _phase == 0:
		if _timer >= prep_duration:
			_phase = 1
			_timer = 0.0
			play_animation("jump")
		return

	var direction := (_target - cat.global_position).normalized()
	cat.global_position += direction * pounce_speed * delta
	face_direction(direction.x)

	if _phase == 1:
		if _timer >= jump_duration:
			_phase = 2
			_timer = 0.0
			play_animation("pounce_attack")
		return

	if _phase == 2:
		var reached_target := cat.global_position.distance_squared_to(_target) <= attack_arrive_distance_sq
		if reached_target or _timer >= attack_duration:
			_phase = 3
			_timer = 0.0
			play_animation("land")
		return

	if _timer >= land_duration:
		transition_to(CatStates.IDLE)
