class_name CatLeashWalkingState
extends CatStateBase

## 溜猫状态：猫咪佩戴牵引绳跟随鼠标散步，速度受牵引距离影响

@export var walk_speed: float = 160.0
@export var run_speed: float = 340.0
@export var leash_length: float = 120.0   # 牵引绳长度
@export var calm_distance: float = 60.0   # 小于该距离慢步跟随
@export var end_walk_duration: float = 1.5  # 停止移动多久后自动结束

const HANDLE_PATH := "res://assets/items/leash.png"
const NECK_OFFSET := Vector2(0, -18)
const LINE_WIDTH := 2.0
const LINE_COLOR := Color(0.55, 0.36, 0.22, 0.95)

var _timer: float = 0.0
var _idle_timer: float = 0.0
var _leash_line: Line2D
var _handle: Sprite2D

func enter(_msg: Dictionary = {}) -> void:
	_timer = 0.0
	_idle_timer = 0.0
	play_animation("walk")
	_ensure_leash_visual()

func exit() -> void:
	_clear_leash_visual()

func physics_update(delta: float) -> void:
	_timer += delta
	var mouse_pos := get_mouse_position()
	var dist := cat.global_position.distance_to(mouse_pos)
	_update_leash_visual(mouse_pos)

	# 距离近 → 慢步；被拉远 → 小跑跟上
	if dist > leash_length:
		_move(mouse_pos, run_speed, delta)
		play_animation("trot")
		_idle_timer = 0.0
	elif dist > calm_distance:
		_move(mouse_pos, walk_speed, delta)
		play_animation("walk")
		_idle_timer = 0.0
	else:
		# 贴近时停下摇尾巴
		play_animation("tail_wag")
		_idle_timer += delta
		if _idle_timer >= end_walk_duration:
			transition_to(CatStates.IDLE)

func _move(target: Vector2, speed: float, delta: float) -> void:
	var direction := (target - cat.global_position).normalized()
	cat.global_position += direction * speed * delta
	face_direction(direction.x)

func _ensure_leash_visual() -> void:
	if not cat:
		return
	if _leash_line == null:
		_leash_line = Line2D.new()
		_leash_line.width = LINE_WIDTH
		_leash_line.default_color = LINE_COLOR
		_leash_line.z_index = 20
		cat.add_child(_leash_line)
	if _handle == null:
		_handle = Sprite2D.new()
		_handle.z_index = 21
		if ResourceLoader.exists(HANDLE_PATH):
			_handle.texture = load(HANDLE_PATH) as Texture2D
		cat.add_child(_handle)

func _update_leash_visual(mouse_pos: Vector2) -> void:
	if not cat or _leash_line == null:
		return
	var start := NECK_OFFSET
	var end := cat.to_local(mouse_pos)
	_leash_line.points = PackedVector2Array([start, end])
	if _handle:
		_handle.position = end

func _clear_leash_visual() -> void:
	if is_instance_valid(_leash_line):
		_leash_line.queue_free()
	if is_instance_valid(_handle):
		_handle.queue_free()
	_leash_line = null
	_handle = null

