extends Node2D

@export var item_type: String = ""

const DESPAWN_TIME = 10.0
const WAND_SIZE = Vector2i(80, 16)
const FOOD_DIAMETER = 36
const WAND_DRAG_RADIUS := 40.0
const WAND_WIGGLE_INTERVAL := 0.15
const WAND_WIGGLE_AMP := 5.0

signal wand_moved(position: Vector2)
signal wand_grabbed
signal wand_released

var _dragging := false
var _wiggle_timer := 0.0
# var _wiggle_phase := 0.0（保留位）：后续摆动动画使用
var _last_position := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	add_to_group("items")
	_setup_sprite()
	var timer = $Timer
	if timer:
		timer.wait_time = DESPAWN_TIME
		timer.one_shot = true
		if not timer.timeout.is_connected(_on_timeout):
			timer.timeout.connect(_on_timeout)
		timer.start()

func _setup_sprite():
	if not sprite or sprite.texture:
		return
	if item_type == "food":
		sprite.texture = _make_circle_texture(FOOD_DIAMETER, Color(0.9, 0.6, 0.2))
	else:
		sprite.texture = _make_rect_texture(WAND_SIZE, Color(0.7, 0.5, 0.2))

func _make_rect_texture(size: Vector2i, color: Color) -> Texture2D:
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _make_circle_texture(diameter: int, color: Color) -> Texture2D:
	var img = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center = Vector2(diameter / 2.0, diameter / 2.0)
	var radius_sq = pow(diameter / 2.0, 2)
	for y in range(diameter):
		for x in range(diameter):
			var offset = Vector2(x + 0.5, y + 0.5) - center
			if offset.length_squared() <= radius_sq:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)

func _input(event: InputEvent) -> void:
	if item_type != "wand":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _hit_wand(get_global_mouse_position()):
			_dragging = true
			_stop_despawn_timer()
			wand_grabbed.emit()
		elif not event.pressed and _dragging:
			_dragging = false
			_restart_despawn_timer()
			wand_released.emit()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position()

func _process(delta: float) -> void:
	if not _dragging:
		return
	_wiggle_timer += delta
	if _wiggle_timer >= WAND_WIGGLE_INTERVAL:
		_wiggle_timer = 0.0
		# 甩动检测：位置变化幅度大时通知猫咪
		var moved := global_position.distance_to(_last_position)
		_last_position = global_position
		if moved > WAND_WIGGLE_AMP:
			wand_moved.emit(global_position)

func _hit_wand(mouse_pos: Vector2) -> bool:
	return global_position.distance_to(mouse_pos) <= WAND_DRAG_RADIUS

func _stop_despawn_timer() -> void:
	var timer = get_node_or_null("Timer") as Timer
	if timer:
		timer.stop()

func _restart_despawn_timer() -> void:
	var timer = get_node_or_null("Timer") as Timer
	if timer:
		timer.start()

func _on_timeout():
	queue_free()
