class_name HabitProfileService
extends Node

## 根据上下文统计构建习惯标签

const MAX_SNAPSHOT_HISTORY := 720

var _snapshot_history: Array[Dictionary] = []
var _active_by_hour: Dictionary = {}

func ingest_snapshot(snapshot: Dictionary) -> void:
	_snapshot_history.append(snapshot.duplicate(true))
	if _snapshot_history.size() > MAX_SNAPSHOT_HISTORY:
		_snapshot_history.pop_front()

	var hour: int = int(snapshot.get("hour", 12))
	var active_seconds: float = float(snapshot.get("active_seconds", 0.0))
	if not _active_by_hour.has(hour):
		_active_by_hour[hour] = 0.0
	_active_by_hour[hour] = float(_active_by_hour[hour]) + active_seconds

func build_tags(snapshot: Dictionary, recent_events: Array[Dictionary]) -> Array[String]:
	var tags: Array[String] = []

	var typing_per_min: float = float(snapshot.get("typing_per_min", 0.0))
	var continuous_active: float = float(snapshot.get("continuous_active_seconds", 0.0))
	var idle_seconds: float = float(snapshot.get("idle_seconds", 0.0))

	if _is_night_owl():
		tags.append("night_owl")
	if typing_per_min >= 18.0:
		tags.append("coding_heavy")
	if continuous_active >= 1800.0:
		tags.append("deep_focus")
	if idle_seconds >= 600.0:
		tags.append("away_long")
	if _count_recent(recent_events, "typing_burst", 300) >= 3:
		tags.append("easily_distracted")
	if _count_recent(recent_events, "focus_milestone", 3600) >= 1:
		tags.append("achievement_driven")

	# 前台应用活动标签（感知数据；持续 10 分钟才贴，避免频繁切换抖动）
	var activity := String(snapshot.get("activity", ""))
	var activity_seconds := float(snapshot.get("activity_seconds", 0.0))
	if activity_seconds >= 600.0:
		match activity:
			"video":
				tags.append("watching_video")
			"coding":
				tags.append("coding_now")
			"browsing":
				tags.append("browsing_now")

	if tags.is_empty():
		tags.append("neutral")
	return tags

func build_memory_lines() -> Array[String]:
	## 从累计数据生成记忆反馈台词；数据不足返回空（不硬凑）
	var lines: Array[String] = []
	var summary := get_profile_summary()
	var active_by_hour: Dictionary = summary.get("active_by_hour", {})
	var total_active := 0.0
	var night_active := 0.0
	for hour_key in active_by_hour:
		var value := float(active_by_hour[hour_key])
		total_active += value
		var hour := int(hour_key)
		if hour >= 22 or hour < 6:
			night_active += value

	if total_active > 3600.0 and night_active / total_active > 0.6:
		lines.append("你最近总在深夜活跃，要注意休息呀。")

	if _snapshot_history.size() > 0:
		var latest: Dictionary = _snapshot_history[_snapshot_history.size() - 1]
		var totals: Dictionary = latest.get("activity_totals", {})
		var coding_secs := float(totals.get("coding", 0.0))
		var video_secs := float(totals.get("video", 0.0))
		if coding_secs > 7200.0:
			lines.append("你已经连续写了好久代码，辛苦啦。")
		elif video_secs > 3600.0:
			lines.append("最近看了不少视频呢，偶尔也要动一动哦。")

	return lines

func get_profile_summary() -> Dictionary:
	return {
		"total_snapshots": _snapshot_history.size(),
		"active_by_hour": _active_by_hour.duplicate(true)
	}

func _is_night_owl() -> bool:
	var night_total: float = 0.0
	var day_total: float = 0.0
	for hour_key in _active_by_hour:
		var hour: int = int(hour_key)
		var value: float = float(_active_by_hour[hour_key])
		if hour >= 22 or hour < 6:
			night_total += value
		else:
			day_total += value
	return night_total > day_total and night_total > 0.0

func _count_recent(events: Array[Dictionary], event_type: String, within_seconds: int) -> int:
	var now := Time.get_unix_time_from_system()
	var count := 0
	for event_data in events:
		var ts: int = int(event_data.get("t", 0))
		var event_name := String(event_data.get("type", ""))
		if event_name == event_type and now - ts <= within_seconds:
			count += 1
	return count
