class_name CustomizationService
extends Node

## 个性化配置服务（首发：性格 + 提醒强度）

var personality: String = "tsundere"
var reminder_intensity: String = "medium"
var smart_mode: bool = true
var llm_enabled: bool = false
var data_collection_level: String = "minimal"
var quiet_hours_start: int = 23
var quiet_hours_end: int = 8

func apply_settings(settings: Dictionary) -> void:
	smart_mode = bool(settings.get("smart_mode", smart_mode))
	llm_enabled = bool(settings.get("llm_enabled", llm_enabled))
	data_collection_level = String(settings.get("data_collection_level", data_collection_level))
	personality = String(settings.get("personality", personality))
	reminder_intensity = String(settings.get("reminder_intensity", reminder_intensity))
	quiet_hours_start = int(settings.get("quiet_hours_start", quiet_hours_start))
	quiet_hours_end = int(settings.get("quiet_hours_end", quiet_hours_end))

func get_persona() -> Dictionary:
	return {
		"personality": personality,
		"reminder_intensity": reminder_intensity
	}

func to_settings_dict() -> Dictionary:
	return {
		"smart_mode": smart_mode,
		"llm_enabled": llm_enabled,
		"data_collection_level": data_collection_level,
		"personality": personality,
		"reminder_intensity": reminder_intensity,
		"quiet_hours_start": quiet_hours_start,
		"quiet_hours_end": quiet_hours_end
	}
