class_name CatIdleState
extends CatStateBase

## 闲置状态

@export var watch_chance: float = 0.3  # 每次检测时注视鼠标的概率
@export var watch_check_interval: float = 1.0  # 检测间隔（秒）
@export var stretch_chance: float = 0.1
@export var yawn_chance: float = 0.08

var _watch_timer: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	if msg.has("animation"):
		play_animation(msg["animation"])
		_watch_timer = 0.0
		return
	var roll := randf()
	if roll < stretch_chance:
		play_animation("stretch")
	elif roll < stretch_chance + yawn_chance:
		play_animation("yawn")
	elif roll < 0.45:
		play_animation("idle_stand")
	elif roll < 0.55:
		play_animation("idle_active")
	elif roll < 0.8:
		play_animation("idle_sit")
	else:
		play_animation("idle_lie")
	_watch_timer = 0.0

func update(delta: float) -> void:
	_watch_timer += delta
	if _watch_timer >= watch_check_interval:
		_watch_timer = 0.0
		# 每秒检测一次，30% 概率注视鼠标
		if randf() < watch_chance:
			transition_to(CatStates.WATCHING)
