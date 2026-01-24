class_name CatBlockingState
extends CatStateBase

@export var pounce_speed: float = 420.0
@export var follow_speed: float = 220.0
@export var leave_speed: float = 160.0
@export var arrive_distance: float = 12.0
@export var follow_distance: float = 24.0
@export var follow_duration: float = 0.4
@export var block_duration_min: float = 1.0
@export var block_duration_max: float = 3.0
@export var leave_distance: float = 160.0
@export var leave_arrive_distance: float = 16.0
@export var leave_wag_speed: float = 10.0
@export var leave_wag_amplitude: float = 0.2
@export var show_paw_overlay: bool = true
@export var paw_overlay_size: int = 36
@export var paw_overlay_alpha: float = 0.25
@export var paw_overlay_offset: Vector2 = Vector2(0, 24)

enum Phase { POUNCE, BLOCK, LEAVE }

var _phase: Phase = Phase.POUNCE
var _target: Vector2 = Vector2.ZERO
var _block_timer: float = 0.0
var _block_duration: float = 0.0
var _follow_timer: float = 0.0
var _leave_target: Vector2 = Vector2.ZERO
var _leave_timer: float = 0.0
var _overlay: Sprite2D
var _original_rotation: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	_original_rotation = cat.rotation if cat else 0.0
	_phase = Phase.POUNCE
	_block_timer = 0.0
	_follow_timer = 0.0
	_leave_timer = 0.0
	_block_duration = randf_range(block_duration_min, block_duration_max)
	if msg.has("target"):
		_target = msg["target"]
	else:
		_target = get_mouse_position()
	play_animation("idle_active")
	_hide_overlay()

func physics_update(delta: float) -> void:
	if not cat:
		return

	match _phase:
		Phase.POUNCE:
			_move_toward(_target, pounce_speed, delta)
			if cat.global_position.distance_squared_to(_target) <= arrive_distance * arrive_distance:
				_start_blocking()
		Phase.BLOCK:
			_block_timer += delta
			_update_follow(delta)
			if _block_timer >= _block_duration:
				_start_leave()
		Phase.LEAVE:
			_leave_timer += delta
			cat.rotation = sin(_leave_timer * leave_wag_speed) * leave_wag_amplitude
			_move_toward(_leave_target, leave_speed, delta)
			if cat.global_position.distance_squared_to(_leave_target) <= leave_arrive_distance * leave_arrive_distance:
				transition_to(CatStates.IDLE)

func exit() -> void:
	_hide_overlay()
	if cat:
		cat.rotation = _original_rotation

func _start_blocking() -> void:
	_phase = Phase.BLOCK
	_block_timer = 0.0
	_target = cat.global_position
	play_animation("idle_sit")
	_show_overlay()

func _start_leave() -> void:
	_phase = Phase.LEAVE
	_leave_timer = 0.0
	_hide_overlay()
	_leave_target = _get_leave_target()
	play_animation("idle_active")

func _update_follow(delta: float) -> void:
	var mouse_pos := get_mouse_position()
	if mouse_pos.distance_squared_to(_target) > follow_distance * follow_distance:
		_target = mouse_pos
		_follow_timer = follow_duration

	if _follow_timer > 0.0:
		_follow_timer = maxf(_follow_timer - delta, 0.0)
		_move_toward(_target, follow_speed, delta)

func _move_toward(target: Vector2, speed: float, delta: float) -> void:
	if not cat:
		return
	cat.global_position = cat.global_position.move_toward(target, speed * delta)

func _get_leave_target() -> Vector2:
	var mouse_pos := get_mouse_position()
	var direction := cat.global_position - mouse_pos
	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT.rotated(randf() * TAU)
	var target := cat.global_position + direction.normalized() * leave_distance

	var screen_size := get_screen_size()
	target.x = clampf(target.x, 40.0, screen_size.x - 40.0)
	target.y = clampf(target.y, 40.0, screen_size.y - 40.0)
	return target

func _show_overlay() -> void:
	if not show_paw_overlay or not cat:
		return
	if not _overlay:
		_overlay = Sprite2D.new()
		_overlay.name = "PawOverlay"
		_overlay.texture = _create_paw_texture(paw_overlay_size, paw_overlay_alpha)
		_overlay.z_index = 5
		_overlay.position = paw_overlay_offset
		cat.add_child(_overlay)
	_overlay.visible = true

func _hide_overlay() -> void:
	if _overlay:
		_overlay.visible = false

func _create_paw_texture(size: int, alpha: float) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var color := Color(1, 1, 1, alpha)
	var main_radius := float(size) * 0.22
	var toe_radius := float(size) * 0.12
	var center := Vector2(size * 0.5, size * 0.6)
	var toe_y := size * 0.32
	_draw_circle(image, center, main_radius, color)
	_draw_circle(image, Vector2(size * 0.32, toe_y), toe_radius, color)
	_draw_circle(image, Vector2(size * 0.5, toe_y - size * 0.02), toe_radius, color)
	_draw_circle(image, Vector2(size * 0.68, toe_y), toe_radius, color)
	return ImageTexture.create_from_image(image)

func _draw_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var radius_sq := radius * radius
	var min_x := int(center.x - radius)
	var max_x := int(center.x + radius)
	var min_y := int(center.y - radius)
	var max_y := int(center.y + radius)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			if dx * dx + dy * dy <= radius_sq:
				if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
					image.set_pixel(x, y, color)
