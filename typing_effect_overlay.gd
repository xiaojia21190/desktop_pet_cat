class_name TypingEffectOverlay
extends CanvasLayer

const MAX_ACTIVE := 24
const GIBBERISH_POOL_SIZE := 14
const LINE_POOL_SIZE := 8
const PAW_POOL_SIZE := 8
const SPAWN_INTERVAL := 0.15
const HINT_DURATION := 3.0
const CHAR_SET := "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#$%&*?"
const TYPE_GIBBERISH := 0
const TYPE_DELETE := 1
const TYPE_PAW := 2

class EffectSlot:
	var node
	var velocity: Vector2 = Vector2.ZERO
	var time_left: float = 0.0
	var total_time: float = 0.0
	var fade_time: float = 0.0
	var kind: int = 0
	var rotation_speed: float = 0.0
	var line_target: float = 0.0
	var base_scale: float = 1.0

class PawPrint:
	extends Node2D

	var color: Color = Color(0.92, 0.58, 0.58, 0.9)

	func _draw() -> void:
		draw_circle(Vector2(0.0, 2.0), 6.5, color)
		draw_circle(Vector2(-6.0, -7.0), 3.0, color)
		draw_circle(Vector2(-2.0, -9.0), 3.2, color)
		draw_circle(Vector2(2.0, -9.0), 3.2, color)
		draw_circle(Vector2(6.0, -7.0), 3.0, color)

@onready var effect_root: Node2D = $EffectRoot
@onready var undo_hint: Label = $UndoHint

var _gibberish_pool: Array[Label] = []
var _line_pool: Array[Line2D] = []
var _paw_pool: Array[PawPrint] = []
var _active_effects: Array[EffectSlot] = []

var _origin_node: Node2D
var _active: bool = false
var _time_left: float = 0.0
var _spawn_timer: float = 0.0
var _hint_timer: float = 0.0

func _ready() -> void:
	randomize()
	_build_pools()
	_setup_hint()
	set_process(false)

func start_effect(duration: float, origin: Node2D) -> void:
	_origin_node = origin
	_active = true
	_time_left = maxf(duration, 0.1)
	_spawn_timer = 0.0
	_hint_timer = HINT_DURATION
	if undo_hint:
		undo_hint.text = "\u6309Ctrl+Z\u64a4\u9500"
		undo_hint.visible = true
		undo_hint.modulate = Color(1.0, 1.0, 1.0, 0.9)
	set_process(true)

func _process(delta: float) -> void:
	if _active:
		_time_left -= delta
		_spawn_timer -= delta
		while _spawn_timer <= 0.0:
			_spawn_random_effect()
			_spawn_timer += SPAWN_INTERVAL
		if _time_left <= 0.0:
			_active = false

	_update_effects(delta)
	_update_hint(delta)

	if not _active and _active_effects.is_empty() and _hint_timer <= 0.0:
		set_process(false)

func _update_hint(delta: float) -> void:
	if _hint_timer <= 0.0:
		return

	_hint_timer -= delta
	if not undo_hint:
		return

	if _hint_timer <= 0.0:
		undo_hint.visible = false
	elif _hint_timer < 0.6:
		var color: Color = undo_hint.modulate
		color.a = clamp(_hint_timer / 0.6, 0.0, 1.0)
		undo_hint.modulate = color

func _update_effects(delta: float) -> void:
	for i in range(_active_effects.size() - 1, -1, -1):
		var effect := _active_effects[i]
		effect.time_left -= delta
		var node: Node2D = effect.node as Node2D

		if node:
			node.position += effect.velocity * delta
			node.rotation += effect.rotation_speed * delta

			if effect.kind == TYPE_DELETE:
				var line := node as Line2D
				var progress: float = 1.0 - (effect.time_left / effect.total_time)
				var length: float = effect.line_target * clampf(progress, 0.0, 1.0)
				line.set_point_position(1, Vector2(length, 0.0))
			elif effect.kind == TYPE_PAW:
				var progress: float = 1.0 - (effect.time_left / effect.total_time)
				var scale_value: float = effect.base_scale * (0.85 + 0.25 * sin(progress * PI))
				node.scale = Vector2.ONE * scale_value

			if effect.time_left <= effect.fade_time:
				var alpha: float = clampf(effect.time_left / effect.fade_time, 0.0, 1.0)
				var color := node.modulate
				color.a = alpha
				node.modulate = color

		if effect.time_left <= 0.0:
			_recycle_effect(i)

func _recycle_effect(index: int) -> void:
	var effect := _active_effects[index]
	_active_effects.remove_at(index)

	if not effect.node:
		return

	effect.node.visible = false
	effect.node.modulate = Color(1.0, 1.0, 1.0, 1.0)

	match effect.kind:
		TYPE_GIBBERISH:
			_gibberish_pool.append(effect.node)
		TYPE_DELETE:
			_line_pool.append(effect.node)
		TYPE_PAW:
			_paw_pool.append(effect.node)

func _spawn_random_effect() -> void:
	if _active_effects.size() >= MAX_ACTIVE:
		return

	var roll := randf()
	if roll < 0.5:
		_spawn_gibberish()
	elif roll < 0.75:
		_spawn_delete_line()
	else:
		_spawn_paw_print()

func _spawn_gibberish() -> void:
	if _gibberish_pool.is_empty():
		return

	var label: Label = _gibberish_pool.pop_back()
	label.visible = true
	label.text = _random_gibberish()
	label.position = _get_origin_position() + Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 6.0))
	label.rotation = randf_range(-0.3, 0.3)
	label.modulate = Color(0.9, 0.95, 1.0, 1.0)

	var effect := EffectSlot.new()
	effect.node = label
	effect.velocity = Vector2(randf_range(-60.0, 60.0), randf_range(-120.0, -60.0))
	effect.time_left = randf_range(0.6, 1.1)
	effect.total_time = effect.time_left
	effect.fade_time = 0.25
	effect.kind = TYPE_GIBBERISH
	effect.rotation_speed = randf_range(-1.2, 1.2)
	_active_effects.append(effect)

func _spawn_delete_line() -> void:
	if _line_pool.is_empty():
		return

	var line: Line2D = _line_pool.pop_back()
	line.visible = true
	line.position = _get_origin_position()
	line.rotation = randf_range(-0.4, 0.4)
	line.modulate = Color(1.0, 0.3, 0.3, 1.0)
	line.set_point_position(0, Vector2.ZERO)
	line.set_point_position(1, Vector2(1.0, 0.0))

	var effect := EffectSlot.new()
	effect.node = line
	effect.velocity = Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 10.0))
	effect.time_left = randf_range(0.35, 0.6)
	effect.total_time = effect.time_left
	effect.fade_time = 0.2
	effect.kind = TYPE_DELETE
	effect.line_target = randf_range(60.0, 140.0)
	_active_effects.append(effect)

func _spawn_paw_print() -> void:
	if _paw_pool.is_empty():
		return

	var paw: PawPrint = _paw_pool.pop_back()
	paw.visible = true
	paw.position = _get_origin_position() + Vector2(randf_range(-50.0, 50.0), randf_range(-40.0, 30.0))
	paw.rotation = randf_range(-0.4, 0.4)
	paw.modulate = Color(1.0, 1.0, 1.0, 1.0)
	paw.queue_redraw()
	var base_scale := randf_range(0.8, 1.2)
	paw.scale = Vector2.ONE * base_scale

	var effect := EffectSlot.new()
	effect.node = paw
	effect.velocity = Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	effect.time_left = randf_range(0.5, 0.8)
	effect.total_time = effect.time_left
	effect.fade_time = 0.25
	effect.kind = TYPE_PAW
	effect.rotation_speed = randf_range(-0.5, 0.5)
	effect.base_scale = base_scale
	_active_effects.append(effect)

func _random_gibberish() -> String:
	var length := randi_range(1, 3)
	var text := ""
	for i in range(length):
		text += CHAR_SET[randi() % CHAR_SET.length()]
	return text

func _get_origin_position() -> Vector2:
	if _origin_node and is_instance_valid(_origin_node):
		return _origin_node.global_position
	var viewport := get_viewport()
	if viewport:
		return viewport.get_visible_rect().size / 2.0
	return Vector2.ZERO

func _build_pools() -> void:
	for i in range(GIBBERISH_POOL_SIZE):
		var label := Label.new()
		label.visible = false
		label.z_index = 10
		label.z_as_relative = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
		label.add_theme_font_size_override("font_size", 18)
		effect_root.add_child(label)
		_gibberish_pool.append(label)

	for i in range(LINE_POOL_SIZE):
		var line := Line2D.new()
		line.visible = false
		line.z_index = 11
		line.z_as_relative = false
		line.width = 3.0
		line.antialiased = true
		line.default_color = Color(1.0, 0.3, 0.3, 1.0)
		line.points = [Vector2.ZERO, Vector2.ONE]
		effect_root.add_child(line)
		_line_pool.append(line)

	for i in range(PAW_POOL_SIZE):
		var paw := PawPrint.new()
		paw.visible = false
		paw.z_index = 12
		paw.z_as_relative = false
		paw.queue_redraw()
		effect_root.add_child(paw)
		_paw_pool.append(paw)

func _setup_hint() -> void:
	if not undo_hint:
		return

	undo_hint.text = ""
	undo_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8, 0.85))
	undo_hint.add_theme_font_size_override("font_size", 16)
	undo_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	undo_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
