class_name PassthroughManager
extends Node

## 桌宠窗口鼠标穿透管理：按猫/道具/UI 状态计算捕获多边形。
## 依赖注入：经 main_node 读取 settings_panel/popup_menu/quick_action_menu/cat 等。

const CAT_HIT_RADIUS_MIN := 56.0
const CAT_HIT_RADIUS_MAX := 240.0

var _cache_hash: int = 0

func update(main_node: Node2D) -> void:
	if not DisplayServer.has_method("window_set_mouse_passthrough"):
		return
	var polygon := _build_capture_polygon(main_node)
	var hash_input := str(polygon)
	var new_hash := hash(hash_input)
	if new_hash == _cache_hash:
		return
	_cache_hash = new_hash
	# 单一权威路径：仅 DisplayServer（window.set 属性路径在 Windows 透明
	# 无边框下会被 Window 内部状态重置，导致捕获区丢失、点击穿透到桌面）
	DisplayServer.window_set_mouse_passthrough(polygon)

func _build_capture_polygon(main_node: Node2D) -> PackedVector2Array:
	if _should_capture_full_window(main_node):
		return _build_full_window_polygon(main_node)
	# 猫命中区 + 道具命中区（保证道具可点击/拖拽）
	var polygon := _build_cat_hit_polygon(main_node)
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if item is Node2D and is_instance_valid(item):
			polygon.append_array(_build_circle_polygon(item.global_position, 48.0, 8))
	return polygon

func _should_capture_full_window(main_node: Node2D) -> bool:
	if main_node.settings_panel and main_node.settings_panel.visible:
		return true
	if main_node.popup_menu and main_node.popup_menu.visible:
		return true
	if main_node.hover_panel_component and main_node.hover_panel_component.is_out:
		return true
	if main_node.quick_action_menu and main_node.quick_action_menu.visible:
		return true
	var input_component = main_node.cat.get_node_or_null("InputComponent")
	if input_component and bool(input_component.is_dragging):
		return true
	return false

func _build_full_window_polygon(main_node: Node2D) -> PackedVector2Array:
	var size: Vector2 = main_node._cached_screen_size
	if size == Vector2.ZERO:
		size = main_node.get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return PackedVector2Array()
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y)
	])

func _build_cat_hit_polygon(main_node: Node2D) -> PackedVector2Array:
	var cat = main_node.cat
	if not cat:
		return _build_full_window_polygon(main_node)
	var radius := 100.0
	var input_component = cat.get_node_or_null("InputComponent")
	if input_component and "click_distance_sq" in input_component:
		radius = sqrt(maxf(float(input_component.click_distance_sq), 1.0))
	if "scale_factor" in cat:
		radius *= float(cat.scale_factor)
	radius = clampf(radius, CAT_HIT_RADIUS_MIN, CAT_HIT_RADIUS_MAX)

	var center: Vector2 = cat.global_position
	return _build_circle_polygon(center, radius, 14)

func _build_circle_polygon(center: Vector2, radius: float, segments: int = 12) -> PackedVector2Array:
	var result := PackedVector2Array()
	var safe_segments := maxi(segments, 6)
	for i in range(safe_segments):
		var angle := (TAU * float(i)) / float(safe_segments)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result
