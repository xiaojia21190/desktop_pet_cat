extends Node

const SAVE_PATH = "user://save_data.cfg"
const SAVE_VERSION = 1
const EXPORT_EXTENSION = ".catpet"
const MAX_IMPORT_FILE_SIZE = 30 * 1024 * 1024  # 30MB 最大导入文件大小

# 节点提供者（由 main.gd 注册注入，避免反向抓取场景树）
var _main_provider: Callable
var _cat_provider: Callable
var _panel_provider: Callable
var _smart_controller_provider: Callable

func _get_default_data() -> Dictionary:
	return {
		"meta": {
			"saved_at": 0,
			"version": SAVE_VERSION
		},
		"cat": {
			"scale_factor": 1.0,
			"position": Vector2.ZERO,
			"cat_type": "orange_tabby"
		},
		"settings": {
			"opacity": 1.0,
			"always_on_top": true,
			"intensity": 1,
			"sound_enabled": true,
			"bgm_enabled": true,
			"volume": 1.0,
			"timed_hide_option": 0,
			"timed_hide_end_time": 0,
			"smart_mode": true,
			"llm_enabled": false,
			"llm_endpoint": "https://api.openai.com/v1/chat/completions",
			"llm_model": "gpt-4o-mini",
			"llm_api_key": "",
			"llm_api_key_env": "OPENAI_API_KEY",
			"llm_timeout_seconds": 10.0,
			"data_collection_level": "minimal",
			"quiet_hours_start": 23,
			"quiet_hours_end": 8,
			"personality": "tsundere",
			"reminder_intensity": "medium",
			"perception_enabled": false,
			"perception_default_rules": true,
			"focus_duration_index": 1
		},
		"behavior": {}
	}

func _build_snapshot_data() -> Dictionary:
	var data = _gather_current_data()
	var meta = data.get("meta", {})
	meta["saved_at"] = Time.get_unix_time_from_system()
	meta["version"] = SAVE_VERSION
	data["meta"] = meta
	return data

func _write_config(data: Dictionary) -> int:
	var config = ConfigFile.new()
	var cat_data = data.get("cat", {})
	var settings = data.get("settings", {})
	var meta = data.get("meta", {})

	config.set_value("cat", "scale_factor", cat_data.get("scale_factor", 1.0))
	config.set_value("cat", "position", cat_data.get("position", Vector2.ZERO))
	config.set_value("cat", "cat_type", cat_data.get("cat_type", "orange_tabby"))

	config.set_value("settings", "opacity", settings.get("opacity", 1.0))
	config.set_value("settings", "always_on_top", settings.get("always_on_top", true))
	config.set_value("settings", "intensity", settings.get("intensity", 1))
	config.set_value("settings", "sound_enabled", settings.get("sound_enabled", true))
	config.set_value("settings", "bgm_enabled", settings.get("bgm_enabled", true))
	config.set_value("settings", "volume", settings.get("volume", 1.0))
	config.set_value("settings", "timed_hide_option", settings.get("timed_hide_option", 0))
	config.set_value("settings", "timed_hide_end_time", settings.get("timed_hide_end_time", 0))
	config.set_value("settings", "smart_mode", settings.get("smart_mode", true))
	config.set_value("settings", "llm_enabled", settings.get("llm_enabled", false))
	config.set_value("settings", "llm_endpoint", settings.get("llm_endpoint", "https://api.openai.com/v1/chat/completions"))
	config.set_value("settings", "llm_model", settings.get("llm_model", "gpt-4o-mini"))
	config.set_value("settings", "llm_api_key", settings.get("llm_api_key", ""))
	config.set_value("settings", "llm_api_key_env", settings.get("llm_api_key_env", "OPENAI_API_KEY"))
	config.set_value("settings", "llm_timeout_seconds", settings.get("llm_timeout_seconds", 10.0))
	config.set_value("settings", "data_collection_level", settings.get("data_collection_level", "minimal"))
	config.set_value("settings", "quiet_hours_start", settings.get("quiet_hours_start", 23))
	config.set_value("settings", "quiet_hours_end", settings.get("quiet_hours_end", 8))
	config.set_value("settings", "perception_enabled", settings.get("perception_enabled", false))
	config.set_value("settings", "perception_default_rules", settings.get("perception_default_rules", true))
	config.set_value("settings", "focus_duration_index", int(settings.get("focus_duration_index", 1)))
	config.set_value("settings", "personality", settings.get("personality", "tsundere"))
	config.set_value("settings", "reminder_intensity", settings.get("reminder_intensity", "medium"))

	config.set_value("meta", "saved_at", meta.get("saved_at", 0))
	config.set_value("meta", "version", meta.get("version", SAVE_VERSION))

	var behavior_data = data.get("behavior", {})
	for key in behavior_data:
		config.set_value("behavior", key, behavior_data[key])

	return config.save(SAVE_PATH)

func save_data():
	var data = _build_snapshot_data()
	var err = _write_config(data)
	if err != OK:
		push_error("Save data failed: " + str(err))

func load_data() -> Dictionary:
	var data = _get_default_data()
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return data

	var cat_data = data["cat"]
	cat_data["scale_factor"] = config.get_value("cat", "scale_factor", cat_data["scale_factor"])
	cat_data["position"] = config.get_value("cat", "position", cat_data["position"])
	cat_data["cat_type"] = config.get_value("cat", "cat_type", cat_data["cat_type"])

	var settings = data["settings"]
	settings["opacity"] = config.get_value("settings", "opacity", settings["opacity"])
	settings["always_on_top"] = config.get_value("settings", "always_on_top", settings["always_on_top"])
	settings["intensity"] = config.get_value("settings", "intensity", settings["intensity"])
	settings["sound_enabled"] = config.get_value("settings", "sound_enabled", settings["sound_enabled"])
	settings["bgm_enabled"] = config.get_value("settings", "bgm_enabled", settings["bgm_enabled"])
	settings["volume"] = config.get_value("settings", "volume", settings["volume"])
	settings["timed_hide_option"] = config.get_value("settings", "timed_hide_option", settings["timed_hide_option"])
	settings["timed_hide_end_time"] = config.get_value("settings", "timed_hide_end_time", settings["timed_hide_end_time"])
	settings["smart_mode"] = config.get_value("settings", "smart_mode", settings["smart_mode"])
	settings["llm_enabled"] = config.get_value("settings", "llm_enabled", settings["llm_enabled"])
	settings["llm_endpoint"] = config.get_value("settings", "llm_endpoint", settings["llm_endpoint"])
	settings["llm_model"] = config.get_value("settings", "llm_model", settings["llm_model"])
	settings["llm_api_key"] = config.get_value("settings", "llm_api_key", settings["llm_api_key"])
	settings["llm_api_key_env"] = config.get_value("settings", "llm_api_key_env", settings["llm_api_key_env"])
	settings["llm_timeout_seconds"] = config.get_value("settings", "llm_timeout_seconds", settings["llm_timeout_seconds"])
	settings["data_collection_level"] = config.get_value("settings", "data_collection_level", settings["data_collection_level"])
	settings["quiet_hours_start"] = config.get_value("settings", "quiet_hours_start", settings["quiet_hours_start"])
	settings["quiet_hours_end"] = config.get_value("settings", "quiet_hours_end", settings["quiet_hours_end"])
	settings["personality"] = config.get_value("settings", "personality", settings["personality"])
	settings["reminder_intensity"] = config.get_value("settings", "reminder_intensity", settings["reminder_intensity"])
	settings["perception_enabled"] = config.get_value("settings", "perception_enabled", settings.get("perception_enabled", false))
	settings["perception_default_rules"] = config.get_value("settings", "perception_default_rules", settings.get("perception_default_rules", true))
	settings["focus_duration_index"] = int(config.get_value("settings", "focus_duration_index", settings.get("focus_duration_index", 1)))

	if settings.get("timed_hide_end_time", 0) <= Time.get_unix_time_from_system():
		settings["timed_hide_end_time"] = 0
		settings["timed_hide_option"] = 0

	var meta = data["meta"]
	meta["saved_at"] = config.get_value("meta", "saved_at", meta["saved_at"])
	meta["version"] = config.get_value("meta", "version", meta["version"])

	# 加载行为系统数据
	var behavior_data = {}
	if config.has_section("behavior"):
		for key in config.get_section_keys("behavior"):
			behavior_data[key] = config.get_value("behavior", key)
	data["behavior"] = behavior_data

	return data

func apply_settings(data: Dictionary = {}):
	if data.is_empty():
		data = load_data()

	var settings: Dictionary = data.get("settings", {})
	var opacity = settings.get("opacity", 1.0)
	var main = _main_provider.call() if _main_provider else null
	if main and main is CanvasItem:
		var color = main.modulate
		color.a = opacity
		main.modulate = color

	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,
		settings.get("always_on_top", true)
	)

	if AudioManager:
		AudioManager.sound_enabled = settings.get("sound_enabled", AudioManager.sound_enabled)
		AudioManager.bgm_enabled = settings.get("bgm_enabled", AudioManager.bgm_enabled)
		AudioManager.set_volume(settings.get("volume", AudioManager.volume))
		if AudioManager.bgm_player:
			if AudioManager.bgm_enabled:
				if AudioManager.bgm_player.stream and not AudioManager.bgm_player.playing:
					AudioManager.bgm_player.play()
			else:
				AudioManager.bgm_player.stop()

	var cat = _cat_provider.call() if _cat_provider else null
	if cat:
		cat.state_change_interval = _intensity_to_interval(settings.get("intensity", 1))

	if main and main.has_method("apply_timed_hide_settings"):
		main.apply_timed_hide_settings(settings)

	var smart_controller = _smart_controller_provider.call() if _smart_controller_provider else null
	if smart_controller and smart_controller.has_method("configure"):
		smart_controller.configure(settings)

func _gather_current_data() -> Dictionary:
	var data = _get_default_data()
	var settings = data["settings"]
	var cat_data = data["cat"]
	var behavior_data = data["behavior"]

	var main = _main_provider.call() if _main_provider else null
	if main and main is CanvasItem:
		settings["opacity"] = main.modulate.a

	var cat = _cat_provider.call() if _cat_provider else null
	if cat:
		cat_data["scale_factor"] = cat.scale_factor
		cat_data["position"] = cat.position
		cat_data["cat_type"] = cat.current_cat_type
		settings["intensity"] = _interval_to_intensity(cat.state_change_interval)

		# 获取行为系统数据
		if cat.behavior_system:
			behavior_data = cat.behavior_system.get_save_data()

	# 面板设置项：由面板自身 collect_settings() 提供（旧实现路径错误导致全部 null）
	var panel = _panel_provider.call() if _panel_provider else null
	if panel and panel.has_method("collect_settings"):
		settings.merge(panel.collect_settings(), true)
	elif AudioManager:
		settings["sound_enabled"] = AudioManager.sound_enabled
		settings["bgm_enabled"] = AudioManager.bgm_enabled
		settings["volume"] = AudioManager.volume

	if main and main.has_method("get_timed_hide_save_data"):
		var timed_hide_data: Dictionary = main.get_timed_hide_save_data()
		if timed_hide_data.has("timed_hide_option"):
			settings["timed_hide_option"] = timed_hide_data["timed_hide_option"]
		if timed_hide_data.has("timed_hide_end_time"):
			settings["timed_hide_end_time"] = timed_hide_data["timed_hide_end_time"]

	var smart_controller = _smart_controller_provider.call() if _smart_controller_provider else null
	if smart_controller and smart_controller.has_method("get_settings_snapshot"):
		var smart_settings = smart_controller.get_settings_snapshot()
		if smart_settings is Dictionary:
			settings.merge(smart_settings, true)

	data["cat"] = cat_data
	data["settings"] = settings
	data["behavior"] = behavior_data
	return data

## 注册节点提供者（依赖注入，替代 get_tree() 反向抓取）
## main.gd 在 _ready 中调用，防止字段重命名后静默存空数据
func register_providers(main_provider: Callable, cat_provider: Callable,
		panel_provider: Callable, smart_controller_provider: Callable) -> void:
	_main_provider = main_provider
	_cat_provider = cat_provider
	_panel_provider = panel_provider
	_smart_controller_provider = smart_controller_provider

func _intensity_to_interval(intensity: int) -> float:
	# 间隔调长:让动画有存在感(原 5/3/1.5 太快,动画常被打断)
	match intensity:
		0:
			return 9.0
		2:
			return 4.0
		_:
			return 6.5

func _interval_to_intensity(interval: float) -> int:
	if interval <= 1.6:
		return 2
	if interval <= 3.1:
		return 1
	return 0

func set_cat_intensity(intensity: int):
	var cat = _cat_provider.call() if _cat_provider else null
	if cat:
		cat.state_change_interval = _intensity_to_interval(intensity)

func set_timed_hide_option(option_index: int):
	var main = _main_provider.call() if _main_provider else null
	if main and main.has_method("set_timed_hide_option"):
		main.set_timed_hide_option(option_index)

func export_to_file(path: String) -> bool:
	var final_path = _ensure_export_extension(path)
	var data = _build_snapshot_data()
	var serialized = _serialize_data(data)
	var json = JSON.stringify(serialized)
	var file = FileAccess.open(final_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to export save file: " + final_path)
		return false
	file.store_string(json)
	file.close()
	return true

func import_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Save file not found: " + path)
		return false

	# 检查文件大小
	var file_size = FileAccess.open(path, FileAccess.READ)
	if file_size == null:
		push_error("Failed to open save file: " + path)
		return false
	var size = file_size.get_length()
	file_size.close()
	if size > MAX_IMPORT_FILE_SIZE:
		push_error("Save file too large: " + str(size) + " bytes (max: " + str(MAX_IMPORT_FILE_SIZE) + ")")
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: " + path)
		return false
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid save file: " + path)
		return false
	var data = _normalize_import_data(parsed)
	apply_save_data(data)
	save_data()
	return true

func reset_data() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	apply_save_data(_get_default_data())
	save_data()

func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var normalized = _normalize_import_data(data)
	apply_settings(normalized)
	_apply_cat_data(normalized.get("cat", {}))
	_apply_behavior_data(normalized.get("behavior", {}))
	_apply_settings_panel(normalized.get("settings", {}))

func _apply_cat_data(cat_data: Dictionary) -> void:
	var cat = _cat_provider.call() if _cat_provider else null
	if not cat:
		return
	if cat_data.has("scale_factor"):
		cat.scale_factor = float(cat_data["scale_factor"])
	if cat_data.has("position"):
		cat.position = _parse_vector2(cat_data["position"])
	var cat_type = str(cat_data.get("cat_type", ""))
	if not cat_type.is_empty():
		var animation_component = cat.get_node_or_null("AnimationComponent")
		if animation_component and animation_component.has_method("switch_cat_type"):
			animation_component.switch_cat_type(cat_type)

func _apply_behavior_data(behavior_data: Dictionary) -> void:
	var cat = _cat_provider.call() if _cat_provider else null
	if cat and cat.behavior_system:
		cat.behavior_system.load_save_data(behavior_data)

func _apply_settings_panel(settings: Dictionary) -> void:
	var panel = _panel_provider.call() if _panel_provider else null
	if panel and panel.has_method("apply_settings"):
		panel.apply_settings(settings)

func _normalize_import_data(data: Dictionary) -> Dictionary:
	var normalized = _get_default_data()
	if data.has("settings") and data["settings"] is Dictionary:
		normalized["settings"].merge(data["settings"], true)
	if data.has("cat") and data["cat"] is Dictionary:
		normalized["cat"].merge(data["cat"], true)
	if data.has("behavior") and data["behavior"] is Dictionary:
		normalized["behavior"] = data["behavior"]
	if data.has("meta") and data["meta"] is Dictionary:
		normalized["meta"].merge(data["meta"], true)
	normalized["cat"]["position"] = _parse_vector2(normalized["cat"].get("position", Vector2.ZERO))
	return normalized

func _serialize_data(data: Dictionary) -> Dictionary:
	var serialized = data.duplicate(true)
	var cat_data = serialized.get("cat", {})
	if cat_data.has("position"):
		cat_data["position"] = _vector2_to_dict(cat_data["position"])
	serialized["cat"] = cat_data
	return serialized

func _parse_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value.x, value.y)
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

func _vector2_to_dict(value) -> Dictionary:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Dictionary and value.has("x") and value.has("y"):
		return {"x": float(value["x"]), "y": float(value["y"])}
	if value is Array and value.size() >= 2:
		return {"x": float(value[0]), "y": float(value[1])}
	return {"x": 0.0, "y": 0.0}

func _ensure_export_extension(path: String) -> String:
	if path.to_lower().ends_with(EXPORT_EXTENSION):
		return path
	return path + EXPORT_EXTENSION
