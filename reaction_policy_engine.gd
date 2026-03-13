class_name ReactionPolicyEngine
extends Node

## 规则优先的回应决策引擎

const ACTION_SLEEP_CURL := "sleep_curl"
const ACTION_GREET := "greet"
const ACTION_CELEBRATE := "celebrate"
const ACTION_COMFORT := "comfort"
const ACTION_BREAK_HINT := "break_hint"
const ACTION_RETREAT := "retreat"

const DEFAULT_COOLDOWN := {
	ACTION_SLEEP_CURL: 120,
	ACTION_GREET: 180,
	ACTION_CELEBRATE: 180,
	ACTION_COMFORT: 150,
	ACTION_BREAK_HINT: 900,
	ACTION_RETREAT: 120
}

var _last_trigger_time: Dictionary = {}

func evaluate(snapshot: Dictionary, tags: Array[String], recent_events: Array[Dictionary], persona: Dictionary) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var personality := String(persona.get("personality", "tsundere"))
	var reminder_intensity := String(persona.get("reminder_intensity", "medium"))

	if _is_quiet_hours(snapshot) or bool(snapshot.get("fullscreen", false)):
		return _decision_if_available(now, ACTION_SLEEP_CURL, "quiet_mode", _line_for("quiet_mode", personality))

	if _has_recent_event(recent_events, "session_resume", 120):
		return _decision_if_available(now, ACTION_GREET, "welcome_back", _line_for("welcome_back", personality))

	if _has_recent_event(recent_events, "focus_milestone", 180):
		return _decision_if_available(now, ACTION_CELEBRATE, "focus_milestone", _line_for("focus_milestone", personality))

	if _has_recent_event(recent_events, "build_fail_streak", 240):
		return _decision_if_available(now, ACTION_COMFORT, "build_fail_streak", _line_for("build_fail_streak", personality))
	if _has_recent_event(recent_events, "focus_failed", 180):
		return _decision_if_available(now, ACTION_COMFORT, "focus_failed", _line_for("focus_failed", personality))

	var active_threshold := 3600.0
	if reminder_intensity == "low":
		active_threshold = 5400.0
	elif reminder_intensity == "high":
		active_threshold = 2400.0
	var continuous_active: float = float(snapshot.get("continuous_active_seconds", 0.0))
	if continuous_active >= active_threshold:
		return _decision_if_available(now, ACTION_BREAK_HINT, "long_focus", _line_for("long_focus", personality))

	if _has_recent_event(recent_events, "user_busy", 180):
		return _decision_if_available(now, ACTION_RETREAT, "user_busy", _line_for("user_busy", personality))

	return {
		"react": false,
		"action_id": "",
		"policy_intent": "",
		"template_line": "",
		"cooldown_sec": 0
	}

func _decision_if_available(now: int, action_id: String, intent: String, line: String) -> Dictionary:
	var cooldown: int = int(DEFAULT_COOLDOWN.get(action_id, 120))
	var last_time: int = int(_last_trigger_time.get(action_id, 0))
	if now - last_time < cooldown:
		return {
			"react": false,
			"action_id": "",
			"policy_intent": "",
			"template_line": "",
			"cooldown_sec": cooldown
		}

	_last_trigger_time[action_id] = now
	return {
		"react": true,
		"action_id": action_id,
		"policy_intent": intent,
		"template_line": line,
		"cooldown_sec": cooldown
	}

func _has_recent_event(recent_events: Array[Dictionary], event_type: String, within_seconds: int) -> bool:
	var now := Time.get_unix_time_from_system()
	for event_data in recent_events:
		var name := String(event_data.get("type", ""))
		var ts: int = int(event_data.get("t", 0))
		if name == event_type and now - ts <= within_seconds:
			return true
	return false

func _is_quiet_hours(snapshot: Dictionary) -> bool:
	var hour: int = int(snapshot.get("hour", 12))
	var start_hour: int = int(snapshot.get("quiet_hours_start", 23))
	var end_hour: int = int(snapshot.get("quiet_hours_end", 8))
	if start_hour == end_hour:
		return false
	if start_hour < end_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour

func _line_for(intent: String, personality: String) -> String:
	match intent:
		"quiet_mode":
			return "先安静趴一会儿，不打扰你。"
		"welcome_back":
			if personality == "playful":
				return "你回来啦，快来摸摸我！"
			if personality == "gentle":
				return "欢迎回来，今天也辛苦了。"
			return "哼，终于想起我了。"
		"focus_milestone":
			return "做得很好，继续保持这个节奏。"
		"build_fail_streak":
			return "没关系，先深呼吸一下，我们再来一次。"
		"focus_failed":
			return "这轮不算失败，稍微休息一下继续。"
		"long_focus":
			return "已经专注很久了，起来活动一分钟吧。"
		"user_busy":
			return "我先退到一边，等你有空再玩。"
		_:
			return "我在这里陪着你。"
