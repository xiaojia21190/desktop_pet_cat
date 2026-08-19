class_name DailyQuestService
extends Node

## P6 每日任务/隐式签到：全自动好习惯任务 + 开机签到
## 数据源：context_collector.event_recorded 信号 + main 分钟级快照轮询
## 原则：不催不领不挽损——完成才庆贺，次日自动刷新

signal quest_completed(quest_id: String, reward_bond: float)
signal checkin_done(streak_days: int, reward_bond: float)

## 签到奖励：min(10 + streak × 2, 30)
const CHECKIN_BASE := 10.0
const CHECKIN_STEP := 2.0
const CHECKIN_CAP := 30.0

var streak_days: int = 0
var today_checked_in: bool = false
var _today_key := ""
var _last_checkin_key := ""
var _completed: Dictionary = {}   # quest_id -> true（当日已完成）

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
	var saved_streak := int(data.get("streak_days", 0))
	var saved_today := String(data.get("today_key", ""))
	var saved_completed: Array = data.get("completed", [])
	for q in saved_completed:
		_completed[String(q)] = true
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

func _complete(quest_id: String, reward: float) -> void:
	## 任务完成唯一入口：拦截重复、发信号（bond 发放在 main 侧）
	if _completed.has(quest_id):
		return
	_completed[quest_id] = true
	quest_completed.emit(quest_id, reward)

func get_save_data() -> Dictionary:
	var completed: Array = []
	for q in _completed.keys():
		completed.append(q)
	return {
		"today_key": _today_key,
		"completed": completed,
		"streak_days": streak_days,
		"last_checkin_key": _last_checkin_key,
	}

func _date_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]

func _shift_date_key(days: int) -> String:
	## 相对今天的日期键（测试与断签判定用；用 unix 秒偏移避免日历库）
	var offset_unix: int = int(Time.get_unix_time_from_system()) + days * 86400
	var d := Time.get_datetime_dict_from_unix_time(offset_unix)
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]
