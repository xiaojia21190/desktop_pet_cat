extends Node
class_name SpriteFramesGenerator

# 从精灵图动态生成 SpriteFrames 资源
# 使用方法：
#   var generator = SpriteFramesGenerator.new()
#   var sprite_frames = generator.generate("orange_tabby")
#   animated_sprite.sprite_frames = sprite_frames

# 缓存已生成的 SpriteFrames
static var _cache: Dictionary = {}

# 生成指定猫咪类型的 SpriteFrames
static func generate(cat_type: String) -> SpriteFrames:
	# 检查缓存
	if _cache.has(cat_type):
		return _cache[cat_type]

	# 获取猫咪配置
	if not AnimationConfig.CAT_TYPES.has(cat_type):
		push_error("未知的猫咪类型: " + cat_type)
		return null

	var cat_config = AnimationConfig.CAT_TYPES[cat_type]
	var texture = load(cat_config.sprite_path) as Texture2D

	if not texture:
		push_error("无法加载精灵图: " + cat_config.sprite_path)
		return null

	# 创建 SpriteFrames
	var sprite_frames = _create_sprite_frames(texture)

	# 缓存结果
	_cache[cat_type] = sprite_frames

	print("已生成 SpriteFrames: ", cat_type, " (", AnimationConfig.ANIMATIONS.size(), " 个动画)")
	return sprite_frames

# 从纹理创建 SpriteFrames
static func _create_sprite_frames(texture: Texture2D) -> SpriteFrames:
	var sf = SpriteFrames.new()

	# 移除默认动画
	if sf.has_animation("default"):
		sf.remove_animation("default")

	# 遍历所有动画配置
	for anim_name in AnimationConfig.ANIMATIONS:
		var config = AnimationConfig.ANIMATIONS[anim_name]
		_add_animation(sf, texture, anim_name, config)

	return sf

# 添加单个动画
static func _add_animation(sf: SpriteFrames, texture: Texture2D, anim_name: String, config: Dictionary):
	var row = config.get("row", 0)
	var frames = config.get("frames", 1)
	var speed = config.get("speed", 5.0)
	var loop = config.get("loop", true)
	var col_start = config.get("col_start", 0)

	# 添加动画
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, speed)
	sf.set_animation_loop(anim_name, loop)

	# 添加帧
	for i in range(frames):
		var col = col_start + i

		# 如果超出当前行，换到下一行
		var actual_row = row + (col / AnimationConfig.COLUMNS)
		var actual_col = col % AnimationConfig.COLUMNS

		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			actual_col * AnimationConfig.FRAME_SIZE.x,
			actual_row * AnimationConfig.FRAME_SIZE.y,
			AnimationConfig.FRAME_SIZE.x,
			AnimationConfig.FRAME_SIZE.y
		)

		sf.add_frame(anim_name, atlas)

# 清除缓存
static func clear_cache():
	_cache.clear()

# 获取所有可用的猫咪类型
static func get_available_cat_types() -> Array:
	return AnimationConfig.CAT_TYPES.keys()

# 预加载所有猫咪的 SpriteFrames
static func preload_all():
	for cat_type in AnimationConfig.CAT_TYPES:
		generate(cat_type)
	print("已预加载所有猫咪动画")
