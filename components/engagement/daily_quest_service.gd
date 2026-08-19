class_name DailyQuestService
extends Node

## P6 每日任务/隐式签到：全自动好习惯任务 + 开机签到
## 数据源：context_collector.event_recorded 信号 + main 分钟级快照轮询
## 原则：不催不领不挽损——完成才庆贺，次日自动刷新

signal quest_completed(quest_id: String, reward_bond: float)
signal checkin_done(streak_days: int, reward_bond: float)
signal weekly_quest_completed(quest_id: String, reward_bond: float)

const AchDefsScript = preload("res://components/engagement/achievement_defs.gd")

## 签到奖励：min(10 + streak × 2, 30)
const CHECKIN_BASE := 10.0
const CHECKIN_STEP := 2.0
const CHECKIN_CAP := 30.0

## 任务定义：id → {title, reward}；判定逻辑在 notify_event/poll_snapshot 内联
const QUEST_DEFS := {
	"focus_session": {"title": "专注一刻", "reward": 15.0},
	"stand_up": {"title": "起来动动", "reward": 10.0},
	"meal_on_time": {"title": "按时吃饭", "reward": 10.0},
	"interact_once": {"title": "摸摸我吧", "reward": 8.0},
}

## 互动类事件 → interact_once
const INTERACT_EVENTS := ["item_used", "petting_started", "cat_clicked"]

## 提醒→响应窗口：intent → [任务id, 窗口秒, 需闲置秒]
const WINDOW_QUESTS := {
	"long_focus": {"quest": "stand_up", "window": 300.0, "need_idle": 120.0},
	"meal_hint": {"quest": "meal_on_time", "window": 1800.0, "need_idle": 300.0},
}
var _window_deadline: Dictionary = {}  # quest_id -> unix 截止时间

var streak_days: int = 0
var today_checked_in: bool = false
var _today_key := ""
var _last_checkin_key := ""
var _completed: Dictionary = {}   # quest_id -> true（当日已完成）
var _current_week := ""           # P8 当前周标识（周一日期键）
var _week_counts: Dictionary = {}      # P8 每日任务id -> 本周次数
var _week_quests_done: Dictionary = {} # P8 周任务id -> true（本周已发）

## 注意：_ready 不签到——签到结算只在 load_from_save 驱动。
## 若 _ready 先 roll，挂载即用空状态签到（streak=1、today_key=今天），
## 随后 load_from_save 的跨天分支会因"今日已签"直接 return，吞掉昨日档的 streak+1。

func load_from_save(data: Dictionary) -> void:
	## 读档注入 + 签到结算（每日首次启动即签到）
	## 实例状态全量重置（防复用残留：上次 load 的 today_key/签到标记会干扰本次结算）
	_last_checkin_key = String(data.get("last_checkin_key", ""))
	streak_days = 0
	today_checked_in = false
	_today_key = ""
	_completed = {}
	var saved_streak := 0
	var raw_streak = data.get("streak_days", 0)
	if typeof(raw_streak) == TYPE_INT or typeof(raw_streak) == TYPE_FLOAT:
		saved_streak = int(raw_streak)
	var saved_today := String(data.get("today_key", ""))
	var saved_completed_raw = data.get("completed", [])
	if typeof(saved_completed_raw) == TYPE_ARRAY:
		for q in saved_completed_raw:
			_completed[String(q)] = true
	# P8 周状态恢复 + 跨周清零
	_current_week = String(data.get("week_key", ""))
	var saved_week_counts_raw = data.get("week_counts", {})
	if typeof(saved_week_counts_raw) == TYPE_DICTIONARY:
		_week_counts = saved_week_counts_raw.duplicate(true)
	var saved_weekly_done_raw = data.get("weekly_done", [])
	if typeof(saved_weekly_done_raw) == TYPE_ARRAY:
		for w in saved_weekly_done_raw:
			_week_quests_done[String(w)] = true
	_roll_week_if_needed()
	if saved_today == _date_key():
		# 同日重启：恢复状态不重复签到
		streak_days = saved_streak
		today_checked_in = true
		_today_key = saved_today
		return
	streak_days = saved_streak
	_roll_day()

func _roll_day() -> void:
	## 跨天/首启：刷新任务 + 结算签到
	var key := _date_key()
	if key == _today_key and today_checked_in:
		return
	_today_key = key
	_completed = {}
	today_checked_in = true
	if _last_checkin_key == _shift_date_key(-1):
		streak_days += 1
	else:
		streak_days = 1
	_last_checkin_key = key
	checkin_done.emit(streak_days, _checkin_reward(streak_days))

func _checkin_reward(streak: int) -> float:
	return minf(CHECKIN_BASE + float(streak) * CHECKIN_STEP, CHECKIN_CAP)

func is_completed(quest_id: String) -> bool:
	return bool(_completed.get(quest_id, false))

func notify_event(event_type: String, payload: Dictionary = {}) -> void:
	## 事件驱动判定（main 连接 context_collector.event_recorded 后自动喂入）
	## P8：周计数在完成判定前累计（当日任务全完成后仍要喂周任务数据）
	_roll_week_if_needed()
	var all_done := true
	for qid in QUEST_DEFS:
		if not is_completed(qid):
			all_done = false
			break
	if event_type == "smart_decision" and not all_done:
		var intent := String(payload.get("intent", ""))
		if WINDOW_QUESTS.has(intent):
			var quest_id: String = WINDOW_QUESTS[intent]["quest"]
			if not is_completed(quest_id):
				_window_deadline[quest_id] = int(Time.get_unix_time_from_system() + float(WINDOW_QUESTS[intent]["window"]))
		return
	if event_type == "focus_milestone":
		_count_weekly("focus_session")
		if not all_done:
			_complete("focus_session", float(QUEST_DEFS["focus_session"]["reward"]))
	elif event_type in INTERACT_EVENTS:
		_count_weekly("interact_once", event_type)
		if not all_done:
			_complete("interact_once", float(QUEST_DEFS["interact_once"]["reward"]))

func poll_snapshot(snapshot: Dictionary) -> void:
	## main 每分钟调用：窗口内闲置达标即完成；过期静默清除
	if _window_deadline.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var idle := float(snapshot.get("idle_seconds", 0.0))
	var expired_or_done: Array = []
	for quest_id in _window_deadline.keys():
		if is_completed(String(quest_id)) or now > int(_window_deadline[quest_id]):
			expired_or_done.append(quest_id)
			continue
		var need := 0.0
		for intent in WINDOW_QUESTS:
			if String(WINDOW_QUESTS[intent]["quest"]) == String(quest_id):
				need = float(WINDOW_QUESTS[intent]["need_idle"])
		if idle >= need:
			expired_or_done.append(quest_id)
			_complete(String(quest_id), float(QUEST_DEFS[quest_id]["reward"]))
	for quest_id in expired_or_done:
		_window_deadline.erase(quest_id)

func _complete(quest_id: String, reward: float, _source_event: String = "") -> void:
	## 任务完成唯一入口：拦截重复、发信号（bond 发放在 main 侧）
	if _completed.has(quest_id):
		return
	_completed[quest_id] = true
	quest_completed.emit(quest_id, reward)

func _count_weekly(quest_id: String, source_event: String = "") -> void:
	## P8 周计数（无论当日任务是否已完成都累计——周任务数据源）
	_roll_week_if_needed()
	_week_counts[quest_id] = int(_week_counts.get(quest_id, 0)) + 1
	_check_weekly_quests()

func _check_weekly_quests() -> void:
	for wid in AchDefsScript.WEEKLY_QUESTS:
		if _week_quests_done.has(wid):
			continue
		var w: Dictionary = AchDefsScript.WEEKLY_QUESTS[wid]
		var count := int(_week_counts.get(String(w["quest_id"]), 0))
		if count >= int(w["target"]):
			_week_quests_done[wid] = true
			weekly_quest_completed.emit(String(wid), float(w["reward"]))

func get_save_data() -> Dictionary:
	var completed: Array = []
	for q in _completed.keys():
		completed.append(q)
	var weekly_done: Array = []
	for w in _week_quests_done.keys():
		weekly_done.append(w)
	return {
		"today_key": _today_key,
		"completed": completed,
		"streak_days": streak_days,
		"last_checkin_key": _last_checkin_key,
		"week_key": _current_week,
		"week_counts": _week_counts.duplicate(true),
		"weekly_done": weekly_done,
	}

func get_today_summary() -> Dictionary:
	## 面板渲染数据：任务列表（按定义顺序）+ 签到天数
	var quests: Array = []
	for qid in QUEST_DEFS:
		quests.append({
			"id": qid,
			"title": String(QUEST_DEFS[qid]["title"]),
			"completed": is_completed(qid),
		})
	return {"quests": quests, "streak_days": streak_days}

func _date_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]

func _week_key() -> String:
	## P8 当前周一的日期键（周一为一周之始；unix 秒算法不依赖日历库）
	var now_unix := int(Time.get_unix_time_from_system())
	var d := Time.get_datetime_dict_from_unix_time(now_unix)
	# Time 的 weekday：0=周日..6=周六 → 转"周一为0"偏移
	var weekday_from_monday := (int(d["weekday"]) + 6) % 7
	var monday_unix := now_unix - weekday_from_monday * 86400 \
		- int(d["hour"]) * 3600 - int(d["minute"]) * 60 - int(d["second"])
	var md := Time.get_datetime_dict_from_unix_time(monday_unix)
	return "%04d%02d%02d" % [md["year"], md["month"], md["day"]]

func _roll_week_if_needed() -> void:
	var key := _week_key()
	if key != _current_week:
		_current_week = key
		_week_counts = {}
		_week_quests_done = {}

func _shift_date_key(days: int) -> String:
	## 相对今天的日期键（测试与断签判定用；用 unix 秒偏移避免日历库）
	var offset_unix: int = int(Time.get_unix_time_from_system()) + days * 86400
	var d := Time.get_datetime_dict_from_unix_time(offset_unix)
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]
