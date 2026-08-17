extends Node
class_name SpriteFramesGenerator

## 从 sprite_manifest.json 动态生成 SpriteFrames 资源（单动作单图模式）
## 使用方法：
##   var sprite_frames = SpriteFramesGenerator.generate("orange_tabby")
##   animated_sprite.sprite_frames = sprite_frames

# 缓存已生成的 SpriteFrames
static var _cache: Dictionary = {}
static var _manifest_cache: Dictionary = {}
static var _manifest_mtime: int = -1

const SPRITE_MANIFEST_PATH := "res://resources/sprite_manifest.json"

# 生成指定猫咪类型的 SpriteFrames
static func generate(cat_type: String) -> SpriteFrames:
	_ensure_manifest_loaded()

	# 检查缓存
	if _cache.has(cat_type):
		return _cache[cat_type]

	var cat_actions := _build_cat_actions(cat_type)
	if cat_actions.is_empty():
		push_error("未找到猫咪动作配置: " + cat_type)
		return null
	var missing_state_keys := AnimationConfig.validate_state_animation_keys(cat_actions)
	if not missing_state_keys.is_empty():
		push_warning("状态映射缺少动画 key: " + ", ".join(missing_state_keys))

	# 创建 SpriteFrames
	var sprite_frames := _create_sprite_frames(cat_actions)
	if sprite_frames == null:
		return null

	# 缓存结果
	_cache[cat_type] = sprite_frames

	print("已生成 SpriteFrames: ", cat_type, " (", cat_actions.size(), " 个动画)")
	return sprite_frames

static func _ensure_manifest_loaded() -> void:
	var mtime := int(FileAccess.get_modified_time(SPRITE_MANIFEST_PATH))
	if _manifest_cache.is_empty():
		_load_manifest(mtime)
		return

	if mtime != _manifest_mtime:
		clear_cache()
		_load_manifest(mtime)

static func _load_manifest(mtime: int) -> void:
	_manifest_cache.clear()
	_manifest_mtime = mtime

	if not FileAccess.file_exists(SPRITE_MANIFEST_PATH):
		push_error("sprite manifest 不存在: " + SPRITE_MANIFEST_PATH)
		return

	var file := FileAccess.open(SPRITE_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取 sprite manifest: " + SPRITE_MANIFEST_PATH)
		return

	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("sprite manifest JSON 格式无效: " + SPRITE_MANIFEST_PATH)
		return

	_manifest_cache = parsed as Dictionary

static func _build_cat_actions(cat_type: String) -> Dictionary:
	if _manifest_cache.is_empty():
		return {}

	var cats_raw = _manifest_cache.get("cats", {})
	if typeof(cats_raw) != TYPE_DICTIONARY:
		return {}
	var cats := cats_raw as Dictionary

	if not cats.has(cat_type):
		return {}
	var cat_entry_raw = cats.get(cat_type, {})
	if typeof(cat_entry_raw) != TYPE_DICTIONARY:
		return {}
	var cat_entry := cat_entry_raw as Dictionary

	var global_actions_raw = _manifest_cache.get("actions", {})
	if typeof(global_actions_raw) != TYPE_DICTIONARY:
		return {}
	var global_actions := global_actions_raw as Dictionary

	var defaults_raw = _manifest_cache.get("defaults", {})
	var defaults: Dictionary = {}
	if typeof(defaults_raw) == TYPE_DICTIONARY:
		defaults = defaults_raw as Dictionary
	var cat_defaults_raw = cat_entry.get("defaults", {})
	var cat_defaults: Dictionary = {}
	if typeof(cat_defaults_raw) == TYPE_DICTIONARY:
		cat_defaults = cat_defaults_raw as Dictionary

	var sheet_path := String(cat_entry.get("sheet_path", ""))
	var action_path_template := String(cat_entry.get("action_path_template", ""))
	var require_action_files := bool(_manifest_cache.get("require_action_files", false))
	if cat_entry.has("require_action_files"):
		require_action_files = bool(cat_entry.get("require_action_files", require_action_files))
	var action_overrides_raw = cat_entry.get("actions", {})
	var action_overrides: Dictionary = {}
	if typeof(action_overrides_raw) == TYPE_DICTIONARY:
		action_overrides = action_overrides_raw as Dictionary

	var result: Dictionary = {}
	var missing_actions: Array[String] = []
	for action_key in global_actions:
		var action_name := String(action_key)
		var spec_raw = global_actions[action_key]
		if typeof(spec_raw) != TYPE_DICTIONARY:
			continue
		var spec := (spec_raw as Dictionary).duplicate(true)

		if not spec.has("columns"):
			spec["columns"] = int(cat_defaults.get("columns", defaults.get("columns", AnimationConfig.COLUMNS)))
		if not spec.has("frame_width"):
			spec["frame_width"] = int(cat_defaults.get("frame_width", defaults.get("frame_width", int(AnimationConfig.FRAME_SIZE.x))))
		if not spec.has("frame_height"):
			spec["frame_height"] = int(cat_defaults.get("frame_height", defaults.get("frame_height", int(AnimationConfig.FRAME_SIZE.y))))

		var override_raw = _find_dict_value_by_string_key(action_overrides, action_name)
		if typeof(override_raw) == TYPE_DICTIONARY:
			spec.merge(override_raw as Dictionary, true)

		var resolved_path := String(spec.get("path", "")).strip_edges()
		if resolved_path.is_empty():
			resolved_path = _resolve_action_path(action_path_template, cat_type, action_name)

		if not resolved_path.is_empty() and ResourceLoader.exists(resolved_path):
			spec["path"] = resolved_path
		elif not require_action_files and not sheet_path.is_empty() and ResourceLoader.exists(sheet_path):
			spec["path"] = sheet_path
		else:
			missing_actions.append(action_name)
			var mode_hint := "严格模式" if require_action_files else "缺少回退资源"
			push_warning("%s: %s/%s 未找到动作图，模板=%s，sheet=%s" % [mode_hint, cat_type, action_name, action_path_template, sheet_path])

		result[action_name] = spec

	if require_action_files and not missing_actions.is_empty():
		push_error("猫咪 %s 缺少动作图: %s" % [cat_type, ", ".join(missing_actions)])
		return {}

	return result

static func _resolve_action_path(template: String, cat_type: String, action_name: String) -> String:
	if template.is_empty():
		return ""
	return template.replace("{cat_id}", cat_type).replace("{action_key}", action_name)

static func _find_dict_value_by_string_key(dict_data: Dictionary, target_key: String):
	if dict_data.has(target_key):
		return dict_data[target_key]
	for dict_key in dict_data.keys():
		if String(dict_key) == target_key:
			return dict_data[dict_key]
	return null

# 从动作配置创建 SpriteFrames
static func _create_sprite_frames(cat_actions: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()

	# 移除默认动画
	if sf.has_animation("default"):
		sf.remove_animation("default")

	for action_key in cat_actions:
		var anim_name := String(action_key)
		var config_raw = cat_actions[action_key]
		if typeof(config_raw) != TYPE_DICTIONARY:
			continue
		_add_animation(sf, anim_name, config_raw as Dictionary)

	# 最少保证有一个可播放动作，避免后续播放报错。
	if sf.get_animation_names().is_empty():
		return null

	return sf

# 添加单个动画
static func _add_animation(sf: SpriteFrames, anim_name: String, config: Dictionary) -> void:
	var texture_path := String(config.get("path", ""))
	if texture_path.is_empty():
		return

	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("动画纹理加载失败: %s (%s)" % [anim_name, texture_path])
		return

	var row: int = int(config.get("row", 0))
	var frames: int = int(config.get("frames", 1))
	var speed: float = float(config.get("speed", 5.0))
	var loop: bool = bool(config.get("loop", true))
	var col_start: int = int(config.get("col_start", 0))
	var col_pixel_start: int = int(config.get("col_pixel_start", 0))
	var row_pixel: int = int(config.get("row_pixel", -1))
	var columns: int = max(1, int(config.get("columns", AnimationConfig.COLUMNS)))
	var frame_width: int = max(1, int(config.get("frame_width", int(AnimationConfig.FRAME_SIZE.x))))
	var frame_height: int = max(1, int(config.get("frame_height", int(AnimationConfig.FRAME_SIZE.y))))

	# 添加动画
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, speed)
	sf.set_animation_loop(anim_name, loop)

	# 添加帧
	for i in range(frames):
		var col: int = col_start + i

		# 如果超出当前行，换到下一行
		@warning_ignore("integer_division")
		var actual_row: int = row + col / columns
		var actual_col: int = col % columns

		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		var pixel_x: float = float(col_pixel_start + actual_col * frame_width)
		var pixel_y: float = float(actual_row * frame_height)
		if row_pixel >= 0:
			@warning_ignore("integer_division")
			pixel_y = float(row_pixel + (col / columns) * frame_height)
		atlas.region = Rect2(
			pixel_x,
			pixel_y,
			float(frame_width),
			float(frame_height)
		)

		sf.add_frame(anim_name, atlas)

# 清除缓存
static func clear_cache() -> void:
	_cache.clear()

# 获取所有可用的猫咪类型
static func get_available_cat_types() -> Array:
	_ensure_manifest_loaded()
	if not _manifest_cache.is_empty():
		var cats_raw = _manifest_cache.get("cats", {})
		if typeof(cats_raw) == TYPE_DICTIONARY:
			return (cats_raw as Dictionary).keys()
	return AnimationConfig.CAT_TYPES.keys()

# 预加载所有猫咪的 SpriteFrames
static func preload_all() -> void:
	for cat_type in get_available_cat_types():
		generate(String(cat_type))
	print("已预加载所有猫咪动画")
