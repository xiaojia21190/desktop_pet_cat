class_name CatTypingAttackState
extends CatStateBase

## 攻击键盘状态

signal typing_attack_started

@export var attack_speed: float = 300.0
@export var attack_duration: float = 1.5

var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("idle_active")
	_timer = 0.0
	typing_attack_started.emit()

func physics_update(delta: float) -> void:
	_timer += delta

	# 扑向屏幕中心（模拟攻击键盘）
	var screen_center := get_screen_size() / 2
	var direction := (screen_center - cat.global_position).normalized()
	cat.global_position += direction * attack_speed * delta

	if _timer >= attack_duration:
		transition_to(CatStates.IDLE)
