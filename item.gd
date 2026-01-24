extends Node2D

@export var item_type: String = ""

const DESPAWN_TIME = 10.0
const WAND_SIZE = Vector2i(80, 16)
const FOOD_DIAMETER = 36

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
	var sprite = $Sprite2D
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

func _on_timeout():
	queue_free()
