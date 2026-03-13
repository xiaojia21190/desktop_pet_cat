extends Node
class_name AnimationConfig

# 配置资源路径
const CONFIG_RESOURCE_PATH = "res://resources/cat_config.tres"

# 缓存的配置资源
static var _config_resource: CatConfigResource = null

# 缓存的 Dictionary 结果（避免每次调用都重新构建）
static var _cached_cat_types: Dictionary = {}
static var _cached_animations: Dictionary = {}

# 获取配置资源（优先加载 .tres 文件，否则使用默认值）
static func get_config() -> CatConfigResource:
	if _config_resource:
		return _config_resource

	# 尝试加载资源文件
	if ResourceLoader.exists(CONFIG_RESOURCE_PATH):
		_config_resource = load(CONFIG_RESOURCE_PATH) as CatConfigResource
		if _config_resource:
			print("已加载配置资源: ", CONFIG_RESOURCE_PATH)
			_rebuild_caches()
			return _config_resource

	# 使用默认配置
	_config_resource = CatConfigResource.create_default()
	print("使用默认配置")
	_rebuild_caches()
	return _config_resource

# 重建缓存
static func _rebuild_caches():
	_cached_cat_types.clear()
	_cached_animations.clear()

	if _config_resource:
		for cat in _config_resource.cat_types:
			_cached_cat_types[cat.cat_id] = cat.to_dict()
		for anim in _config_resource.animations:
			_cached_animations[anim.animation_name] = anim.to_dict()

# 精灵图帧配置（兼容旧代码）
static var FRAME_SIZE: Vector2:
	get:
		return get_config().frame_size

static var COLUMNS: int:
	get:
		return get_config().columns

# 猫咪类型配置（兼容旧代码）- 使用缓存
static var CAT_TYPES: Dictionary:
	get:
		if _cached_cat_types.is_empty():
			get_config()  # 确保缓存已构建
		return _cached_cat_types

# 动画定义（兼容旧代码）- 使用缓存
static var ANIMATIONS: Dictionary:
	get:
		if _cached_animations.is_empty():
			get_config()  # 确保缓存已构建
		return _cached_animations

# 状态到动画的映射（兼容旧代码）
static var STATE_ANIMATION_MAP: Dictionary:
	get:
		return get_config().state_animation_map

# 获取状态对应的动画名称
static func get_animation_for_state(state_name: String) -> String:
	return get_config().get_animation_for_state(state_name)

# 检查动画是否存在
static func has_animation(anim_name: String) -> bool:
	return get_config().get_animation(anim_name) != null

# 获取动画配置
static func get_animation_config(anim_name: String) -> Dictionary:
	var anim = get_config().get_animation(anim_name)
	if anim:
		return anim.to_dict()
	return {}

# 校验状态映射里引用的动画 key 是否在可用动作集合中
static func validate_state_animation_keys(available_actions: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var state_map = STATE_ANIMATION_MAP
	for state_key in state_map:
		var anims_raw = state_map[state_key]
		if typeof(anims_raw) != TYPE_ARRAY:
			continue
		var anims: Array = anims_raw as Array
		for anim_name_raw in anims:
			var anim_name := String(anim_name_raw)
			if anim_name.is_empty():
				continue
			if not available_actions.has(anim_name) and not missing.has(anim_name):
				missing.append(anim_name)
	return missing

# 重新加载配置
static func reload_config():
	_config_resource = null
	_cached_cat_types.clear()
	_cached_animations.clear()
	get_config()
