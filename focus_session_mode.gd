class_name FocusSessionMode
extends CanvasLayer

signal session_finished(result: String, summary: Dictionary)
@warning_ignore("unused_signal")
signal recording_script_finished(output_path: String, summary: Dictionary)

const MAX_VALUE := 100.0
const MIN_VALUE := 0.0
const RESULT_VICTORY := "victory"
const RESULT_FAILURE := "failure"


@export var session_duration_seconds: int = 30 * 60
@export var focus_start: float = 85.0
@export var affection_start: float = 45.0
@export var chaos_start: float = 20.0
@export var objective_interval_seconds: int = 45
@export var show_tutorial_on_start: bool = true
@export var auto_start_session: bool = false
@export var demo_script_mode: bool = false
@export var recording_default_duration_seconds: int = 120
@export var recording_auto_export: bool = true
@export var trash_purge_old_default_days: int = 30
@export var recording_ops_tail_preview_size: int = 5
@export var recording_ops_panel_preview_size: int = 20

var focus_value: float = 0.0  # 会话表现分：不写回行为系统（一局的成绩，不是猫的长期心理）

var _behavior  # CatBehaviorSystem 引用，由 bind_behavior() 注入；为空时数值本地兜底
var _local_affection: float = 45.0
var _local_chaos: float = 20.0

var affection_value: float:
	get:
		return _behavior.affection if _behavior else _local_affection
	set(value):
		if _behavior:
			_behavior.affection = clampf(value, 0.0, 100.0)
		else:
			_local_affection = clampf(value, 0.0, 100.0)

var chaos_value: float:
	get:
		return _behavior.chaos if _behavior else _local_chaos
	set(value):
		if _behavior:
			_behavior.chaos = clampf(value, 0.0, 100.0)
		else:
			_local_chaos = clampf(value, 0.0, 100.0)

var _remaining_seconds: int = 0
var _elapsed_seconds: int = 0
var _running: bool = false
var _finished: bool = false
var _time_accumulator: float = 0.0
var _objective_timer: float = 0.0
var _last_state_impact_ms: Dictionary = {}

var _objective_system: FocusObjectiveSystem
var _hud: FocusHud
var _debug_recorder
var _demo_events: Array[Dictionary] = []
var _demo_cursor: int = 0
var _demo_paused: bool = false
var _current_objective_tier: int = 1

var _recording_mode: bool = false
var _recording_target_seconds: int = 0
@warning_ignore("unused_private_class_variable")
var _recording_output_path: String = ""
var _recording_events: Array[Dictionary] = []
var _replay_mode: bool = false
var _replay_source_path: String = ""
@warning_ignore("unused_private_class_variable")
var _recording_files: Array[String] = []
@warning_ignore("unused_private_class_variable")
var _selected_recording_path: String = ""
@warning_ignore("unused_private_class_variable")
var _trash_files: Array[String] = []
@warning_ignore("unused_private_class_variable")
var _selected_trash_path: String = ""
var _demo_playback_speed: float = 1.0
@warning_ignore("unused_private_class_variable")
var _demo_speed_options: Array[float] = [0.5, 1.0, 2.0]
@warning_ignore("unused_private_class_variable")
var _delete_confirm_path: String = ""
@warning_ignore("unused_private_class_variable")
var _delete_confirm_until: int = 0
@warning_ignore("unused_private_class_variable")
var _purge_confirm_path: String = ""
@warning_ignore("unused_private_class_variable")
var _purge_confirm_until: int = 0
@warning_ignore("unused_private_class_variable")
var _purge_old_confirm_days: int = 0
@warning_ignore("unused_private_class_variable")
var _purge_old_confirm_until: int = 0
@warning_ignore("unused_private_class_variable")
var _last_deleted_original_path: String = ""
@warning_ignore("unused_private_class_variable")
var _last_deleted_trash_path: String = ""
@warning_ignore("unused_private_class_variable")
var _ops_panel_visible: bool = false

var _tutorial: FocusTutorialController
var _charge_engine := FocusChargeEngine.new()
var _work_signal_buffer := {"typing": 0, "clicks": 0, "focus_activity": false}


func _ready() -> void:
	_hud = FocusHud.new()
	_hud.name = "FocusHud"
	add_child(_hud)
	_objective_system = FocusObjectiveSystem.new()
	_objective_system.name = "ObjectiveSystem"
	add_child(_objective_system)
	_objective_system.set_cards(FocusObjectiveSystem.default_cards())
	_objective_system.objective_completed.connect(_on_objective_completed)
	_objective_system.objective_failed.connect(_on_objective_failed)
	_demo_events = _build_default_demo_events()
	_tutorial = FocusTutorialController.new()
	_tutorial.name = "TutorialController"
	add_child(_tutorial)
	_tutorial.setup(FocusTutorialController.default_steps(), func(text: String): _hud.set_hint(text))
	# 默认不自动开启专注会话，避免桌宠启动约 1 分钟后必然弹出失败面板
	if auto_start_session:
		start_session()

func _process(delta: float) -> void:
	if not _running:
		return

	_tutorial.update(delta)

	_time_accumulator += delta
	_objective_timer -= delta

	while _time_accumulator >= 1.0:
		_time_accumulator -= 1.0
		_tick_one_second()
		if not _running:
			break

	_update_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_F5:
		start_session()
		return

	if key_event.keycode == KEY_F1 and _tutorial.active:
		_tutorial.skip()
		return


func bind_behavior(behavior) -> void:
	# 心理统一：注入 CatBehaviorSystem，会话的 affection/chaos 直接读写行为系统
	_behavior = behavior

func bind_debug_recorder(recorder) -> void:
	# 挂载调试设施（录制/回放/垃圾桶/ops 面板）。正常运行不挂载。
	_debug_recorder = recorder
	recorder.bind_session(self)

func _notify_debug_refresh() -> void:
	if _debug_recorder:
		_debug_recorder._refresh_demo_control_ui()

func start_session() -> void:
	focus_value = focus_start
	# affection/chaos 不再重置：行为统一后延续猫的当前心理状态（行为变更例外，已记录在 P1 文档）
	if not _behavior:
		affection_value = affection_start
		chaos_value = chaos_start

	_remaining_seconds = session_duration_seconds
	_elapsed_seconds = 0
	_running = true
	_finished = false
	_time_accumulator = 0.0
	_last_state_impact_ms.clear()
	_hud.hide_result()
	_hud.show_hud()
	_demo_cursor = 0
	_objective_system.reset_demo_cursor()
	_demo_paused = false
	_current_objective_tier = 1
	_hud.set_hint("Session started. Keep focus until time runs out.")
	_hud.set_help(_build_help_text())
	_notify_debug_refresh()
	_record_event("session_start", {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value
	})

	_tutorial.start(show_tutorial_on_start)
	_roll_objective()
	_update_ui()

func stop_session(reason: String = "manual_stop") -> void:
	## 手动结束会话：按当前状态给出结算，不发 failure 事件
	if not _running:
		return
	var summary := {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds,
		"stopped_reason": reason
	}
	_running = false
	_finished = true
	_hud.hide_hud()
	_hud.show_result("Session Paused", "Keep it up! F5 restart | tray to resume.")
	_record_event("session_stopped", summary)

func record_work_input(work_signal: Dictionary) -> void:
	## main 从键盘/鼠标/感知接线喂入；会话未运行时忽略
	if not _running:
		return
	_work_signal_buffer["typing"] = int(work_signal.get("typing", 0))
	_work_signal_buffer["clicks"] = int(work_signal.get("clicks", 0))
	_work_signal_buffer["focus_activity"] = bool(work_signal.get("focus_activity", false))

func _tick_one_second() -> void:
	## 每秒核心滴答：抽自 _process 便于测试单步驱动
	_elapsed_seconds += 1
	_remaining_seconds = max(_remaining_seconds - 1, 0)
	_current_objective_tier = _current_difficulty_tier()
	_apply_passive_changes()
	_consume_demo_events()
	if _objective_system.check_timeout(_objective_timer, focus_value, affection_value, chaos_value):
		_apply_delta(-4.0, -3.0, 6.0, "Objective failed. Penalty applied.")
		_record_event("objective_failed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()
	_check_recording_target()
	# 用完清零，等待下一秒新信号
	_work_signal_buffer["typing"] = 0
	_work_signal_buffer["clicks"] = 0

func set_objective_cards(cards: Array[Dictionary]) -> void:
	_objective_system.set_cards(cards)
	_roll_objective()
	_update_ui()

func set_demo_events(events: Array[Dictionary]) -> void:
	var normalized: Array[Dictionary] = []
	for event in events:
		if not event.has("type"):
			continue
		normalized.append({
			"at": int(event.get("at", 0)),
			"type": String(event.get("type", "")),
			"value": event.get("value", "")
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("at", 0)) < int(b.get("at", 0))
	)
	_demo_events = normalized
	_demo_cursor = 0

func set_demo_script_enabled(enabled: bool, restart_session: bool = false) -> void:
	demo_script_mode = enabled
	_objective_system.set_demo_mode(enabled)
	_demo_paused = false
	if not enabled:
		_replay_mode = false
		_replay_source_path = ""
	if restart_session:
		start_session()
	_notify_debug_refresh()

func start_demo() -> void:
	if not demo_script_mode:
		set_demo_script_enabled(true, false)
	_demo_paused = false
	if not _running:
		start_session()
	_notify_debug_refresh()

func pause_demo(paused: bool = true) -> void:
	_demo_paused = paused
	_notify_debug_refresh()

func trigger_next_demo_event() -> bool:
	if _demo_events.is_empty():
		return false
	if _demo_cursor >= _demo_events.size():
		return false
	var event := _demo_events[_demo_cursor]
	_demo_cursor += 1
	_apply_demo_event(event)
	_notify_debug_refresh()
	return true

func on_typing_attack() -> void:
	if not _running:
		return
	# P3：打字本身是工作，不该惩罚——改为小幅度 chaos 波动
	_apply_delta(0.0, -0.5, 3.0, "Cat pounced on your keyboard!")
	_record_event("typing_attack")
	_check_end_condition()

func on_item_used(item_type: String) -> void:
	if not _running:
		return

	match item_type:
		"food":
			_apply_delta(4.0, 8.0, -14.0, "Food used. Cat calmed down.")
		"wand":
			_apply_delta(3.0, 5.0, -9.0, "Wand used. Cat attention redirected.")
		_:
			return

	_record_event("item_used", {"item_type": item_type})
	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()

func on_cat_state_changed(to_state: StringName) -> void:
	if not _running:
		return

	var key := String(to_state)
	var now := Time.get_ticks_msec()
	var last_ms := int(_last_state_impact_ms.get(key, 0))
	if now - last_ms < 1200:
		return
	_last_state_impact_ms[key] = now

	match to_state:
		&"Blocking":
			_apply_delta(-1.2, -0.3, 2.5, "Blocking state triggered.")
		&"Chasing":
			_apply_delta(-1.0, 0.0, 2.0, "Chasing state triggered.")
		&"Pouncing":
			_apply_delta(-0.8, 0.0, 1.8, "Pouncing state triggered.")
		&"TailWagging":
			_apply_delta(0.5, 1.0, -1.0, "Tail wagging improved mood.")
		&"Watching":
			_apply_delta(-0.3, 0.3, 0.5, "Cat is watching your cursor.")
		_:
			return

	_record_event("state_impact", {"state": String(to_state)})
	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()

func get_snapshot() -> Dictionary:
	return {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds,
		"running": _running,
		"objective": _objective_system.get_objective_key()
	}

func _apply_passive_changes() -> void:
	# P3 玩法反转：真实工作信号充能，闲置慢衰
	var focus_delta := _charge_engine.compute_focus_delta(_work_signal_buffer)
	focus_value = clampf(focus_value + focus_delta, MIN_VALUE, MAX_VALUE)
	# chaos 慢慢自然回落；affection 随工作缓慢增长（猫喜欢陪你干活）
	chaos_value = clampf(chaos_value - 0.5, MIN_VALUE, MAX_VALUE)
	var affection_shift := 0.1
	if focus_delta > 0.0:
		affection_shift = 0.2
	affection_value = clampf(affection_value + affection_shift, MIN_VALUE, MAX_VALUE)

	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()

func _apply_delta(focus_delta: float, affection_delta: float, chaos_delta: float, hint: String = "") -> void:
	focus_value = clampf(focus_value + focus_delta, MIN_VALUE, MAX_VALUE)
	affection_value = clampf(affection_value + affection_delta, MIN_VALUE, MAX_VALUE)
	chaos_value = clampf(chaos_value + chaos_delta, MIN_VALUE, MAX_VALUE)
	if not hint.is_empty():
		_hud.set_hint(hint)

func _roll_objective() -> void:
	_objective_timer = float(objective_interval_seconds)
	_objective_system.roll_new_objective(_current_difficulty_tier(), focus_value, affection_value, chaos_value)
	_record_event("objective_roll", {
		"id": _objective_system.get_objective_key(),
		"target": _objective_system.get_objective_target(),
		"tier": _current_difficulty_tier()
	})

func _current_difficulty_tier() -> int:
	var ratio := 0.0
	if session_duration_seconds > 0:
		ratio = clampf(float(_elapsed_seconds) / float(session_duration_seconds), 0.0, 1.0)
	if ratio < 0.34:
		return 1
	if ratio < 0.67:
		return 2
	return 3

func _on_objective_completed(_objective_id: String, _target: float) -> void:
	pass  # 奖励在调用点就地应用，信号仅作外部观测

func _on_objective_failed(_objective_id: String, _target: float) -> void:
	pass  # 惩罚在调用点就地应用，信号仅作外部观测

func _check_end_condition() -> void:
	if focus_value <= 0.0 or chaos_value >= 100.0:
		_finish_session(RESULT_FAILURE)
		return
	if _remaining_seconds <= 0:
		_finish_session(RESULT_VICTORY)

func _finish_session(result: String) -> void:
	if _finished:
		return

	_running = false
	_finished = true

	if result == RESULT_VICTORY:
		_hud.show_result("Session Complete", "You stayed productive for 30 minutes.\nF5 restart | F9 toggle demo mode.")
	else:
		_hud.show_result("Session Failed", "Focus collapsed.\nF5 restart | F9 toggle demo mode.")

	session_finished.emit(result, {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds
	})
	_record_event("session_finished", {"result": result})
	if _recording_mode and _debug_recorder:
		_debug_recorder._finalize_recording("session_finished")

func _consume_demo_events() -> void:
	if not demo_script_mode:
		return
	if _demo_paused:
		return
	var timeline_seconds := _elapsed_seconds
	if _replay_mode:
		timeline_seconds = int(floor(float(_elapsed_seconds) * _demo_playback_speed))
	while _demo_cursor < _demo_events.size():
		var event := _demo_events[_demo_cursor]
		var at_second := int(event.get("at", -1))
		if at_second > timeline_seconds:
			return
		_demo_cursor += 1
		_apply_demo_event(event)

func _apply_demo_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	_record_event("demo_event", {
		"type": event_type,
		"value": event.get("value", ""),
		"at": int(event.get("at", -1))
	})
	match event_type:
		"typing":
			on_typing_attack()
		"item_food":
			on_item_used("food")
		"item_wand":
			on_item_used("wand")
		"state":
			var state_name := StringName(event.get("value", "Watching"))
			on_cat_state_changed(state_name)
		"hint":
			_hud.set_hint(String(event.get("value", "")))
		_:
			pass

func _check_recording_target() -> void:
	if not _recording_mode:
		return
	if _elapsed_seconds < _recording_target_seconds:
		return
	_record_event("recording_target_reached")
	if _running and not _finished:
		_finish_session(RESULT_VICTORY)

func _record_event(event_name: String, extra: Dictionary = {}) -> void:
	if not _recording_mode:
		return
	var payload := {
		"t": _elapsed_seconds,
		"event": event_name,
		"focus": round(focus_value * 10.0) / 10.0,
		"affection": round(affection_value * 10.0) / 10.0,
		"chaos": round(chaos_value * 10.0) / 10.0,
		"objective": _objective_system.get_objective_key()
	}
	for key in extra.keys():
		payload[key] = extra[key]
	_recording_events.append(payload)


func _update_ui() -> void:
	_hud.update_metrics({
		"remaining_text": _format_seconds(_remaining_seconds),
		"objective_title": _objective_title_text(),
		"objective_detail": "Tier " + str(_current_objective_tier) + " | Target " + _objective_target_text() + " | Left " + str(int(ceil(_objective_timer))) + "s",
		"objective_progress": _objective_system.progress(focus_value, affection_value, chaos_value),
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"help_text": _build_help_text()
	})
	_notify_debug_refresh()

func _objective_title_text() -> String:
	match _objective_system.get_objective_key():
		FocusObjectiveSystem.OBJECTIVE_KEEP_FOCUS:
			return "Keep Focus"
		FocusObjectiveSystem.OBJECTIVE_REDUCE_CHAOS:
			return "Reduce Chaos"
		FocusObjectiveSystem.OBJECTIVE_BUILD_AFFECTION:
			return "Build Affection"
		_:
			return "-"

func _objective_target_text() -> String:
	match _objective_system.get_objective_key():
		FocusObjectiveSystem.OBJECTIVE_KEEP_FOCUS:
			return "Focus >= " + str(int(round(_objective_system.get_objective_target())))
		FocusObjectiveSystem.OBJECTIVE_REDUCE_CHAOS:
			return "Chaos <= " + str(int(round(_objective_system.get_objective_target())))
		FocusObjectiveSystem.OBJECTIVE_BUILD_AFFECTION:
			return "Affection >= " + str(int(round(_objective_system.get_objective_target())))
		_:
			return "-"

func _format_seconds(total_seconds: int) -> String:
	var safe_seconds: int = maxi(total_seconds, 0)
	@warning_ignore("integer_division")
	var minutes: int = safe_seconds / 60
	var seconds: int = safe_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _build_help_text() -> String:
	return "F5 restart | F1 skip tutorial | F2 ops-panel | F3 log | F4 purge-old | F6 purge | F7 restore | F8 delete | F9 demo | F10 record | F11 replay | F12 speed"

func _build_default_demo_events() -> Array[Dictionary]:
	return [
		{"at": 3, "type": "hint", "value": "Demo event: cat starts disturbing."},
		{"at": 5, "type": "typing"},
		{"at": 8, "type": "state", "value": "Blocking"},
		{"at": 12, "type": "item_wand"},
		{"at": 18, "type": "typing"},
		{"at": 22, "type": "item_food"},
		{"at": 28, "type": "state", "value": "TailWagging"},
		{"at": 35, "type": "hint", "value": "Demo event: objective should be near completion."}
	]
