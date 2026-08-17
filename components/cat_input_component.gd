class_name CatInputComponent
extends Node

## 猫咪输入组件
## 处理拖拽、点击、缩放等输入

signal drag_started
signal drag_ended
signal clicked(part: String)
signal scale_changed(new_scale: float)

@export var click_distance_sq: float = 10000.0  # 100px 半径
@export var click_threshold_time: float = 0.2
@export var click_threshold_dist_sq: float = 100.0  # 10px

# 部位检测常量
@export var head_offset: Vector2 = Vector2(0, -40)
@export var tail_offset: Vector2 = Vector2(-50, 20)
@export var body_radius_sq: float = 2500.0
@export var head_radius_sq: float = 900.0
@export var tail_radius_sq: float = 625.0

var owner_node: Node2D
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var scale_factor: float = 1.0

var _click_start_pos: Vector2 = Vector2.ZERO
var _click_start_time: float = 0.0

func _ready() -> void:
	owner_node = get_parent() as Node2D

func _input(event: InputEvent) -> void:
	if not owner_node:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and is_dragging:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# 用事件坐标而非实时光标：注入事件/光标抖动时仍能正确命中
	var mouse_pos: Vector2 = event.global_position if event.global_position != Vector2.ZERO else owner_node.get_global_mouse_position()
	var distance_sq := owner_node.global_position.distance_squared_to(mouse_pos)

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and distance_sq < click_distance_sq:
			# 开始拖拽
			is_dragging = true
			drag_offset = owner_node.global_position - mouse_pos
			_click_start_pos = mouse_pos
			_click_start_time = Time.get_ticks_msec() / 1000.0
			drag_started.emit()

		elif not event.pressed and is_dragging:
			# 结束拖拽
			is_dragging = false
			var click_duration := Time.get_ticks_msec() / 1000.0 - _click_start_time
			var click_distance := mouse_pos.distance_squared_to(_click_start_pos)

			# 判断是点击还是拖拽
			if click_duration < click_threshold_time and click_distance < click_threshold_dist_sq:
				var part := _detect_click_part(mouse_pos)
				clicked.emit(part)
			else:
				drag_ended.emit()

	# 滚轮缩放
	if distance_sq < click_distance_sq:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_scale(0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_scale(-0.1)

func _handle_mouse_motion(_event: InputEventMouseMotion) -> void:
	var mouse_pos := owner_node.get_global_mouse_position()
	owner_node.global_position = mouse_pos + drag_offset

func _change_scale(delta: float) -> void:
	scale_factor = clampf(scale_factor + delta, 0.5, 2.0)
	owner_node.scale = Vector2(scale_factor, scale_factor)
	scale_changed.emit(scale_factor)

func _detect_click_part(click_pos: Vector2) -> String:
	var local_pos := click_pos - owner_node.global_position
	var sf := scale_factor

	# 检测头部
	var head_pos := head_offset * sf
	if local_pos.distance_squared_to(head_pos) < head_radius_sq * sf * sf:
		return "head"

	# 检测尾巴
	var tail_pos := tail_offset * sf
	if local_pos.distance_squared_to(tail_pos) < tail_radius_sq * sf * sf:
		return "tail"

	# 检测身体
	if local_pos.length_squared() < body_radius_sq * sf * sf:
		return "body"

	return ""

func set_scale_factor(value: float) -> void:
	scale_factor = clampf(value, 0.5, 2.0)
	if owner_node:
		owner_node.scale = Vector2(scale_factor, scale_factor)
