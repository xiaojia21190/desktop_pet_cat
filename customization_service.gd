class_name CustomizationService
extends Node

## 个性化配置服务（首发：性格 + 提醒强度）

var personality: String = "tsundere"
var presence_level: int = 2  # 0安静 1低频 2中频 3高频 4智能
var smart_mode: bool = true
var llm_enabled: bool = false
var data_collection_level: String = "minimal"
var quiet_hours_start: int = 23
var quiet_hours_end: int = 8
var perception_enabled: bool = false
var perception_default_rules: bool = true
var llm_endpoint: String = "https://api.openai.com/v1/chat/completions"
var llm_model: String = "gpt-4o-mini"
var llm_api_key: String = ""
var llm_api_key_env: String = "OPENAI_API_KEY"
var llm_timeout_seconds: float = 45.0

func apply_settings(settings: Dictionary) -> void:
	smart_mode = bool(settings.get("smart_mode", smart_mode))
	llm_enabled = bool(settings.get("llm_enabled", llm_enabled))
	data_collection_level = String(settings.get("data_collection_level", data_collection_level))
	personality = String(settings.get("personality", personality))
	presence_level = clampi(int(settings.get("presence_level",
		_legacy_reminder_to_presence(settings))), 0, 4)
	quiet_hours_start = int(settings.get("quiet_hours_start", quiet_hours_start))
	quiet_hours_end = int(settings.get("quiet_hours_end", quiet_hours_end))
	perception_enabled = bool(settings.get("perception_enabled", perception_enabled))
	perception_default_rules = bool(settings.get("perception_default_rules", perception_default_rules))
	llm_endpoint = String(settings.get("llm_endpoint", llm_endpoint)).strip_edges()
	llm_model = String(settings.get("llm_model", llm_model)).strip_edges()
	llm_api_key = String(settings.get("llm_api_key", llm_api_key)).strip_edges()
	llm_api_key_env = String(settings.get("llm_api_key_env", llm_api_key_env)).strip_edges()
	llm_timeout_seconds = clampf(float(settings.get("llm_timeout_seconds", llm_timeout_seconds)), 1.0, 60.0)

## 旧 reminder_intensity 迁移映射（presence_level 缺失时兜底）
func _legacy_reminder_to_presence(settings: Dictionary) -> int:
	match String(settings.get("reminder_intensity", "medium")):
		"low":
			return 1
		"high":
			return 3
		_:
			return 2

func get_persona() -> Dictionary:
	return {
		"personality": personality,
		"presence_level": presence_level
	}

func to_settings_dict() -> Dictionary:
	return {
		"smart_mode": smart_mode,
		"llm_enabled": llm_enabled,
		"data_collection_level": data_collection_level,
		"personality": personality,
		"presence_level": presence_level,
		"quiet_hours_start": quiet_hours_start,
		"quiet_hours_end": quiet_hours_end,
		"perception_enabled": perception_enabled,
		"perception_default_rules": perception_default_rules,
		"llm_endpoint": llm_endpoint,
		"llm_model": llm_model,
		"llm_api_key": llm_api_key,
		"llm_api_key_env": llm_api_key_env,
		"llm_timeout_seconds": llm_timeout_seconds
	}

func get_llm_settings() -> Dictionary:
	return {
		"llm_enabled": llm_enabled,
		"llm_endpoint": llm_endpoint,
		"llm_model": llm_model,
		"llm_api_key": llm_api_key,
		"llm_api_key_env": llm_api_key_env,
		"llm_timeout_seconds": llm_timeout_seconds
	}
