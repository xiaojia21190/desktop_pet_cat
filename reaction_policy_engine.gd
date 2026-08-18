class_name ReactionPolicyEngine
extends Node

## 规则优先的回应决策引擎

const ACTION_SLEEP_CURL := "sleep_curl"
const ACTION_GREET := "greet"
const ACTION_CELEBRATE := "celebrate"
const ACTION_COMFORT := "comfort"
const ACTION_BREAK_HINT := "break_hint"
const ACTION_RETREAT := "retreat"
const ACTION_IDLE_COMPANY := "idle"
const ACTION_TAIL_WAG := "tail_wag"

const DEFAULT_COOLDOWN := {
	ACTION_SLEEP_CURL: 120,
	ACTION_GREET: 180,
	ACTION_CELEBRATE: 180,
	ACTION_COMFORT: 150,
	ACTION_BREAK_HINT: 900,
	ACTION_RETREAT: 120,
	ACTION_IDLE_COMPANY: 1500,
	ACTION_TAIL_WAG: 1200
}

var _last_trigger_time: Dictionary = {}

@warning_ignore("unused_parameter")
func evaluate(snapshot: Dictionary, tags: Array[String], recent_events: Array[Dictionary], persona: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var personality := String(persona.get("personality", "tsundere"))
	var reminder_intensity := String(persona.get("reminder_intensity", "medium"))
	var psyche: Dictionary = snapshot.get("psyche", {})
	var energy: float = float(psyche.get("energy", 100.0))

	if _is_hard_quiet(snapshot) or bool(snapshot.get("fullscreen", false)):
		return _decide(now, ACTION_SLEEP_CURL, "quiet_mode", _line_for("quiet_mode", personality), energy)

	# —— P4：深夜关怀（软静音内放行，原 23-1 点窗口被静音全灭）——
	var hour: int = int(snapshot.get("hour", 12))
	var memory_lines: Array = snapshot.get("memory_lines", [])
	if _in_soft_quiet(snapshot) and continuous_active_precheck(snapshot, 1800.0):
		var care_line := "这么晚还在忙，记得早点休息。"
		if memory_lines.size() > 0:
			care_line = String(memory_lines[0])
		return _decide(now, ACTION_COMFORT, "night_owl_care", care_line, energy)

	if _has_recent_event(recent_events, "session_resume", 120):
		return _decide(now, ACTION_GREET, "welcome_back", _line_for("welcome_back", personality), energy)

	if _has_recent_event(recent_events, "focus_milestone", 180):
		return _decide(now, ACTION_CELEBRATE, "focus_milestone", _line_for("focus_milestone", personality), energy)

	if _has_recent_event(recent_events, "build_fail_streak", 240):
		return _decide(now, ACTION_COMFORT, "build_fail_streak", _line_for("build_fail_streak", personality), energy)
	if _has_recent_event(recent_events, "focus_failed", 180):
		return _decide(now, ACTION_COMFORT, "focus_failed", _line_for("focus_failed", personality), energy)

	var active_threshold := 3600.0
	if reminder_intensity == "low":
		active_threshold = 5400.0
	elif reminder_intensity == "high":
		active_threshold = 2400.0
	var continuous_active: float = float(snapshot.get("continuous_active_seconds", 0.0))
	if continuous_active >= active_threshold:
		return _decide(now, ACTION_BREAK_HINT, "long_focus", _line_for("long_focus", personality), energy)

	# —— P4 新意图：活动陪伴 ——
	if tags.has("watching_video"):
		return _decide(now, ACTION_IDLE_COMPANY, "video_companion", _line_for("video_companion", personality), energy)
	if tags.has("coding_now") and continuous_active_precheck(snapshot, 1800.0):
		return _decide(now, ACTION_TAIL_WAG, "coding_cheer", _line_for("coding_cheer", personality), energy)

	if _has_recent_event(recent_events, "user_busy", 180):
		return _decide(now, ACTION_RETREAT, "user_busy", _line_for("user_busy", personality), energy)

	return {
		"react": false,
		"action_id": "",
		"policy_intent": "",
		"template_line": "",
		"cooldown_sec": 0
	}

func _decide(now: int, action_id: String, intent: String, line: String, energy: float) -> Dictionary:
	# 心理调制：精力低的猫用安静动作代替欢快动作
	if energy < 30.0 and action_id in [ACTION_CELEBRATE, ACTION_GREET, ACTION_TAIL_WAG]:
		action_id = ACTION_SLEEP_CURL
	return _decision_if_available(now, action_id, intent, line)

func continuous_active_precheck(snapshot: Dictionary, threshold: float) -> bool:
	return float(snapshot.get("continuous_active_seconds", 0.0)) >= threshold

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
	var now := int(Time.get_unix_time_from_system())
	for event_data in recent_events:
		var event_name := String(event_data.get("type", ""))
		var ts: int = int(event_data.get("t", 0))
		if event_name == event_type and now - ts <= within_seconds:
			return true
	return false

const SOFT_QUIET_MINUTES := 60  # 静音时段前 60 分钟为软静音（进入缓冲）

## 硬静音：完全静默（quiet_mode 仅此处返回）
func _is_hard_quiet(snapshot: Dictionary) -> bool:
	if not _in_quiet_window(snapshot):
		return false
	return not _in_soft_quiet(snapshot)

## 软静音：静音时段前 60 分钟，允许轻关怀类意图
func _in_soft_quiet(snapshot: Dictionary) -> bool:
	if not _in_quiet_window(snapshot):
		return false
	var minute_of_day: int = int(snapshot.get("hour", 12)) * 60 + int(snapshot.get("minute", 0))
	var start_minute: int = int(snapshot.get("quiet_hours_start", 23)) * 60
	return minute_of_day >= start_minute and minute_of_day < start_minute + SOFT_QUIET_MINUTES

func _in_quiet_window(snapshot: Dictionary) -> bool:
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
			if personality == "playful":
				return "悄悄趴着，不打扰你哦～"
			if personality == "gentle":
				return "安静陪着你，专注加油。"
			return "先安静趴一会儿，不打扰你。"
		"welcome_back":
			if personality == "playful":
				return "你回来啦，快来摸摸我！"
			if personality == "gentle":
				return "欢迎回来，今天也辛苦了。"
			return "哼，终于想起我了。"
		"focus_milestone":
			if personality == "playful":
				return "哇，好厉害！继续冲冲冲！"
			if personality == "gentle":
				return "你做到了，慢慢来，节奏很好。"
			return "做得很好，继续保持这个节奏。"
		"build_fail_streak":
			if personality == "playful":
				return "失败是成功他妈，再来！"
			if personality == "gentle":
				return "没事的，深呼吸，一步一步来。"
			return "没关系，先深呼吸一下，我们再来一次。"
		"focus_failed":
			if personality == "playful":
				return "哎呀走神了？没事，重新来！"
			if personality == "gentle":
				return "这轮不算，休息一下再继续吧。"
			return "这轮不算失败，稍微休息一下继续。"
		"long_focus":
			if personality == "playful":
				return "起来动一动啦！久坐伤身体哦！"
			if personality == "gentle":
				return "已经专注很久了，起来喝口水吧。"
			return "已经专注很久了，起来活动一分钟吧。"
		"user_busy":
			if personality == "playful":
				return "好忙哦，我先玩一会儿，叫我！"
			if personality == "gentle":
				return "专心工作，我在旁边等你。"
			return "我先退到一边，等你有空再玩。"
		"video_companion":
			if personality == "playful":
				return "我也一起看！这个好看吗？"
			if personality == "gentle":
				return "我趴在这儿陪你一起看。"
			return "看吧看吧，我勉强陪你看一会儿。"
		"coding_cheer":
			if personality == "playful":
				return "写代码的样子最帅了！加油加油！"
			if personality == "gentle":
				return "你专注的样子真好，我在旁边给你加油。"
			return "哼，写得不赖嘛，继续保持。"
		_:
			return "我在这里陪着你。"
