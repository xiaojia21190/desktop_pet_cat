class_name ContextCollector
extends Node

## 采集最小上下文信息（不记录原始文本与按键内容）

signal event_recorded(event_type: String, payload: Dictionary)

const MAX_EVENT_HISTORY := 240

var _events: Array[Dictionary] = []
var _session_start_unix: int = 0
var _last_input_unix: int = 0
var _active_seconds: float = 0.0
var _continuous_active_seconds: float = 0.0
var _idle_seconds: float = 0.0
var _typing_count: int = 0
var _mouse_click_count: int = 0
var _item_use_count: int = 0
var _state_change_count: int = 0

# 前台应用感知（由外部喂入，collector 不持有 monitor）
var _fg_app := ""
var _fg_activity := ""
var _fg_last_update_unix: int = 0
var _activity_totals: Dictionary = {}  # activity -> 累计秒
var _last_interaction_unix := 0  # 最近一次用户互动（撸猫/道具/点击猫）

func _ready() -> void:
	var now := int(Time.get_unix_time_from_system())
	_session_start_unix = now
	_last_input_unix = now

const PAUSE_FULL_SEC := 300.0   # 停止输入超 5 分钟视为连续活跃中断
const PAUSE_DISCOUNT := 0.5     # 45s~5min 的思考间隙按 50% 折算

func update_context(delta: float) -> void:
	var now := int(Time.get_unix_time_from_system())
	_idle_seconds = float(now - _last_input_unix)
	if _idle_seconds <= 45.0:
		_active_seconds += delta
		_continuous_active_seconds += delta
	elif _idle_seconds <= PAUSE_FULL_SEC:
		# 思考间隙：半速折算，不打断连续活跃
		_continuous_active_seconds += delta * PAUSE_DISCOUNT
	else:
		_continuous_active_seconds = 0.0

func update_foreground(app_name: String, activity: String) -> void:
	## 由外部（main/monitor 接线）喂入前台应用感知数据；活动切换时累计用时
	var now := int(Time.get_unix_time_from_system())
	if not _fg_activity.is_empty() and activity != _fg_activity:
		var elapsed: int = now - _fg_last_update_unix
		if elapsed > 0:
			_activity_totals[_fg_activity] = float(_activity_totals.get(_fg_activity, 0.0)) + float(elapsed)
	_fg_app = app_name
	_fg_activity = activity
	_fg_last_update_unix = now

func record_event(event_type: String, payload: Dictionary = {}) -> void:
	var now := int(Time.get_unix_time_from_system())
	var event_payload: Dictionary = payload.duplicate(true)
	event_payload["type"] = event_type
	event_payload["t"] = now
	_events.append(event_payload)
	if _events.size() > MAX_EVENT_HISTORY:
		_events.pop_front()
	event_recorded.emit(event_type, event_payload)

func record_input(input_type: String) -> void:
	_last_input_unix = int(Time.get_unix_time_from_system())
	match input_type:
		"typing":
			_typing_count += 1
		"mouse_click":
			_mouse_click_count += 1
		_:
			pass

func record_interaction() -> void:
	## 用户主动互动（撸猫/道具/点击猫）——主动邀请意图的数据源
	_last_interaction_unix = int(Time.get_unix_time_from_system())

func record_item_use(item_type: String) -> void:
	_item_use_count += 1
	record_interaction()
	record_event("item_used", {"item_type": item_type})

func record_state_change(to_state: StringName) -> void:
	_state_change_count += 1
	record_event("state_changed", {"to_state": String(to_state)})

func get_recent_events(within_seconds: int = 300) -> Array[Dictionary]:
	var now := int(Time.get_unix_time_from_system())
	var result: Array[Dictionary] = []
	for event_data in _events:
		var ts: int = int(event_data.get("t", 0))
		if now - ts <= within_seconds:
			result.append(event_data)
	return result

func get_snapshot() -> Dictionary:
	var viewport := get_viewport()
	var screen_size := Vector2.ZERO
	if viewport:
		screen_size = viewport.get_visible_rect().size

	# 全屏/免打扰判定：宠物自身窗口是 borderless 全屏覆盖，
	# window_get_mode 永远报 fullscreen（会把所有决策拦死）。
	# 语义上应判断"用户是否在专注看片/游戏"→ 用前台 activity 分类代替。
	var is_fullscreen := _fg_activity == "game" or _fg_activity == "video"
	var now := int(Time.get_unix_time_from_system())
	var session_seconds: int = maxi(now - _session_start_unix, 1)
	var typing_per_min: float = (float(_typing_count) * 60.0) / float(session_seconds)
	var clicks_per_min: float = (float(_mouse_click_count) * 60.0) / float(session_seconds)

	return {
		"timestamp": now,
		"hour": int(Time.get_datetime_dict_from_system().hour),
		"os_name": OS.get_name(),
		"screen_size": screen_size,
		"fullscreen": is_fullscreen,
		"idle_seconds": _idle_seconds,
		"active_seconds": _active_seconds,
		"continuous_active_seconds": _continuous_active_seconds,
		"typing_per_min": typing_per_min,
		"clicks_per_min": clicks_per_min,
		"typing_count": _typing_count,
		"mouse_click_count": _mouse_click_count,
		"item_use_count": _item_use_count,
		"state_change_count": _state_change_count,
		"foreground_app": _fg_app,
		"activity": _fg_activity,
		"minutes_since_interaction": (float(now - _last_interaction_unix) / 60.0) if _last_interaction_unix > 0 else 9999.0,
		"activity_seconds": float(Time.get_unix_time_from_system() - _fg_last_update_unix) if not _fg_activity.is_empty() else 0.0,
		"activity_totals": _activity_totals.duplicate(true)
	}
