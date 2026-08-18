class_name CatInputComponent
extends Node

## 猫咪输入组件:统一判定点击 / 拖拽 / 撸猫三种按住意图
## - 快速点按( <0.2s 且没动 ) → clicked
## - 按住并移动( >10px )      → 拖拽跟手
## - 按住不动 0.6s             → 撸猫(漂移 20px 内有效)

signal drag_started
signal drag_ended
signal clicked(part: String)
signal scale_changed(new_scale: float)
signal petting_started(part: String)        # 开始撸猫
signal petting_tick(part: String)           # 撸猫中(每 0.5s,累计好感)
signal petting_ended(pet_seconds: float)    # 松手(撸了多久)

enum HoldIntent { NONE, PENDING, DRAG, PET }

@export var click_distance_sq: float = 10000.0   # 100px 命中半径
@export var click_threshold_time: float = 0.2
@export var drag_start_dist_sq: float = 100.0    # 移动 10px 确认拖拽
@export var pet_start_delay: float = 0.6         # 按住多久算撸猫
@export var pet_max_drift_sq: float = 400.0      # 撸猫允许漂移 20px,超出升级拖拽

# 部位检测常量
@export var head_offset: Vector2 = Vector2(0, -40)
@export var tail_offset: Vector2 = Vector2(-50, 20)
@export var body_radius_sq: float = 2500.0
@export var head_radius_sq: float = 900.0
@export var tail_radius_sq: float = 625.0

var owner_node: Node2D
var is_dragging: bool = false   # 兼容外部读取(托盘穿透判定用)
var drag_offset: Vector2 = Vector2.ZERO
var scale_factor: float = 1.0

var _click_start_pos: Vector2 = Vector2.ZERO
var _click_start_time: float = 0.0
var _intent: int = HoldIntent.NONE
var _pet_part := ""
var _pet_hold_timer: float = 0.0
var _pet_tick_timer: float = 0.0
var _pet_total_time: float = 0.0

func _ready() -> void:
	owner_node = get_parent() as Node2D

func _process(delta: float) -> void:
	if _intent != HoldIntent.PENDING:
		return
	_pet_hold_timer += delta
	if _pet_hold_timer >= pet_start_delay:
		_begin_petting()

func _input(event: InputEvent) -> void:
	if not owner_node:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _intent != HoldIntent.NONE:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var mouse_pos: Vector2 = event.global_position if event.global_position != Vector2.ZERO else owner_node.get_global_mouse_position()
	var distance_sq := owner_node.global_position.distance_squared_to(mouse_pos)

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and distance_sq < click_distance_sq:
			_intent = HoldIntent.PENDING
			is_dragging = false
			_pet_hold_timer = 0.0
			_pet_total_time = 0.0
			_pet_tick_timer = 0.0
			drag_offset = owner_node.global_position - mouse_pos
			_click_start_pos = mouse_pos
			_click_start_time = Time.get_ticks_msec() / 1000.0

		elif not event.pressed and _intent != HoldIntent.NONE:
			_release(mouse_pos)

	# 滚轮缩放
	if distance_sq < click_distance_sq:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_scale(0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_scale(-0.1)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	match _intent:
		HoldIntent.DRAG:
			owner_node.global_position = owner_node.get_global_mouse_position() + drag_offset
		HoldIntent.PENDING:
			# 移动超阈值:确认为拖拽
			if event.position.distance_squared_to(_click_start_pos) > drag_start_dist_sq:
				_intent = HoldIntent.DRAG
				is_dragging = true
				drag_started.emit()
		HoldIntent.PET:
			# 撸猫漂移过大:升级为拖拽(猫被拎走)
			if event.position.distance_squared_to(_click_start_pos) > pet_max_drift_sq:
				_end_petting()
				_intent = HoldIntent.DRAG
				is_dragging = true
				drag_started.emit()

func _begin_petting() -> void:
	_intent = HoldIntent.PET
	is_dragging = false
	_pet_part = _detect_click_part(_click_start_pos)
	_pet_total_time = 0.0
	_pet_tick_timer = 0.5  # 立即发首 tick
	petting_started.emit(_pet_part)

func _end_petting() -> void:
	petting_ended.emit(_pet_total_time)

func _release(mouse_pos: Vector2) -> void:
	match _intent:
		HoldIntent.PET:
			_end_petting()
		HoldIntent.DRAG:
			is_dragging = false
			drag_ended.emit()
		HoldIntent.PENDING:
			# 快速点按:点击判定
			var click_duration := Time.get_ticks_msec() / 1000.0 - _click_start_time
			var click_dist_sq := mouse_pos.distance_squared_to(_click_start_pos)
			if click_duration < click_threshold_time and click_dist_sq < drag_start_dist_sq:
				clicked.emit(_detect_click_part(mouse_pos))
			else:
				drag_ended.emit()
	_intent = HoldIntent.NONE
	is_dragging = false

# 撸猫 tick 在 _process 的 PET 分支外独立累计
func _physics_process(delta: float) -> void:
	if _intent != HoldIntent.PET:
		return
	_pet_total_time += delta
	_pet_tick_timer += delta
	if _pet_tick_timer >= 0.5:
		_pet_tick_timer = 0.0
		petting_tick.emit(_pet_part)

func _change_scale(delta: float) -> void:
	scale_factor = clampf(scale_factor + delta, 0.5, 2.0)
	owner_node.scale = Vector2(scale_factor, scale_factor)
	scale_changed.emit(scale_factor)

func _detect_click_part(click_pos: Vector2) -> String:
	var local_pos := click_pos - owner_node.global_position
	var sf := scale_factor

	var head_pos := head_offset * sf
	if local_pos.distance_squared_to(head_pos) < head_radius_sq * sf * sf:
		return "head"

	var tail_pos := tail_offset * sf
	if local_pos.distance_squared_to(tail_pos) < tail_radius_sq * sf * sf:
		return "tail"

	if local_pos.length_squared() < body_radius_sq * sf * sf:
		return "body"

	return ""

func set_scale_factor(value: float) -> void:
	scale_factor = clampf(value, 0.5, 2.0)
	if owner_node:
		owner_node.scale = Vector2(scale_factor, scale_factor)
