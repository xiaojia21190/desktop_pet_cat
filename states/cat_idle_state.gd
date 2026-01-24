class_name CatIdleState
extends CatStateBase

## 闲置状态

@export var watch_chance: float = 0.3  # 每次检测时注视鼠标的概率
@export var watch_check_interval: float = 1.0  # 检测间隔（秒）

var _watch_timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("idle_stand")
	_watch_timer = 0.0

func update(delta: float) -> void:
	_watch_timer += delta
	if _watch_timer >= watch_check_interval:
		_watch_timer = 0.0
		# 每秒检测一次，30% 概率注视鼠标
		if randf() < watch_chance:
			transition_to(CatStates.WATCHING)
