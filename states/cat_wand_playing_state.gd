class_name CatWandPlayingState
extends CatStateBase

## 逗猫棒玩耍状态：追逐被用户甩动的逗猫棒

@export var chase_speed: float = 380.0
@export var catch_distance: float = 55.0
@export var play_timeout: float = 12.0
@export var lose_interest_distance: float = 600.0

var _wand: Node2D = null
var _timer: float = 0.0
var _last_wand_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	if msg.has("item"):
		_wand = msg["item"]
	_last_wand_pos = _wand.global_position if _wand else cat.global_position
	_timer = 0.0
	_stuck_timer = 0.0
	play_animation("chasing")
	face_toward(_last_wand_pos)

func physics_update(delta: float) -> void:
	_timer += delta

	if not is_instance_valid(_wand):
		transition_to(CatStates.IDLE)
		return

	var wand_pos: Vector2 = _wand.global_position

	# 逗猫棒太久没动或超时 → 失去兴趣
	var _wand_moved := wand_pos.distance_to(_last_wand_pos)  # noqa: 位移量备用
	_last_wand_pos = wand_pos
	if _timer >= play_timeout:
		transition_to(CatStates.IDLE)
		return

	# 追逐逗猫棒
	var direction := (wand_pos - cat.global_position).normalized()
	cat.global_position += direction * chase_speed * delta
	face_direction(direction.x)
	play_animation("chasing")

	# 抓到逗猫棒 → 开心
	if cat.global_position.distance_to(wand_pos) <= catch_distance:
		play_animation("happy")
		_notify_play_success()
		transition_to(CatStates.TAIL_WAGGING)
		return

	# 距离过远放弃
	if cat.global_position.distance_to(wand_pos) > lose_interest_distance:
		transition_to(CatStates.IDLE)

func exit() -> void:
	_wand = null

func _notify_play_success() -> void:
	if cat and cat.get("behavior_system"):
		cat.behavior_system.record_interaction("wand_given")
		cat.behavior_system.modify_mood(8)
		cat.behavior_system.modify_energy(-8)
		cat.behavior_system.modify_affection(2)
		AudioManager.play_cat_sound()
