class_name SmartPetController
extends Node

## 智能萌宠控制器：Context -> Profile -> Policy -> (LLM 可选)

signal smart_action_requested(action_id: String, decision: Dictionary)
signal smart_line_generated(line: String, source: String)

const ContextCollectorScript = preload("res://context_collector.gd")
const HabitProfileServiceScript = preload("res://habit_profile_service.gd")
const ReactionPolicyEngineScript = preload("res://reaction_policy_engine.gd")
const LLMAdapterScript = preload("res://llm_adapter.gd")
const CustomizationServiceScript = preload("res://customization_service.gd")

@export var policy_tick_interval: float = 3.0
@export var llm_tick_interval: float = 45.0  ## LLM 全上下文决策周期下限（秒）

## 档位 → LLM 自主决策周期（秒）
const PRESENCE_LLM_TICK := {0: 180.0, 1: 90.0, 2: 45.0, 3: 20.0, 4: 45.0}

var _main_node: Node
var _cat_node: Node2D
var _timer: float = 0.0
var _llm_timer: float = 0.0
var _silent_streak: int = 0
var _polish_deadline_ms: int = 0
var _last_snapshot: Dictionary = {}
var _recent_events: Array[Dictionary] = []

var _context_collector
var _profile_service
var _policy_engine
var _llm_adapter
var _customization_service
var _behavior  # CatBehaviorSystem 引用（心理唯一源）

func _ready() -> void:
	_context_collector = ContextCollectorScript.new()
	_profile_service = HabitProfileServiceScript.new()
	_policy_engine = ReactionPolicyEngineScript.new()
	_llm_adapter = LLMAdapterScript.new()
	_customization_service = CustomizationServiceScript.new()

	_context_collector.name = "ContextCollector"
	_profile_service.name = "HabitProfileService"
	_policy_engine.name = "ReactionPolicyEngine"
	_llm_adapter.name = "LLMAdapter"
	_customization_service.name = "CustomizationService"

	add_child(_context_collector)
	add_child(_profile_service)
	add_child(_policy_engine)
	add_child(_llm_adapter)
	add_child(_customization_service)

	_llm_adapter.line_ready.connect(_on_llm_line_ready)
	_llm_adapter.decision_ready.connect(_on_llm_decision_ready)
	_llm_adapter.no_reaction.connect(_on_llm_no_reaction)

func bind_nodes(main_node: Node, cat_node: Node2D) -> void:
	_main_node = main_node
	_cat_node = cat_node

func bind_behavior(behavior) -> void:
	# 心理注入：决策时读取猫的当前心理状态
	_behavior = behavior

func _inject_psyche(snapshot: Dictionary) -> void:
	if _behavior:
		snapshot["psyche"] = {
			"mood": _behavior.mood,
			"energy": _behavior.energy,
			"affection": _behavior.affection,
			"chaos": _behavior.chaos
		}

func configure(settings: Dictionary) -> void:
	_customization_service.apply_settings(settings)
	_llm_adapter.configure(_customization_service.get_llm_settings())

func get_settings_snapshot() -> Dictionary:
	return _customization_service.to_settings_dict()

func record_event(event_type: String, payload: Dictionary = {}) -> void:
	_context_collector.record_event(event_type, payload)
	var event_payload: Dictionary = payload.duplicate(true)
	event_payload["type"] = event_type
	event_payload["t"] = Time.get_unix_time_from_system()
	_recent_events.append(event_payload)
	if _recent_events.size() > 160:
		_recent_events.pop_front()

func record_typing() -> void:
	_context_collector.record_input("typing")

func record_mouse_click() -> void:
	_context_collector.record_input("mouse_click")

func record_item_use(item_type: String) -> void:
	_context_collector.record_item_use(item_type)

func record_state_change(to_state: StringName) -> void:
	_context_collector.record_state_change(to_state)

func _process(delta: float) -> void:
	if not _customization_service.smart_mode:
		return

	_context_collector.update_context(delta)
	_timer += delta
	if _timer < policy_tick_interval:
		_llm_timer += delta
		_maybe_llm_tick(delta)
		return
	_timer = 0.0
	# 轨道A：规则引擎按固定节奏独立判定（LLM 开启也不停摆——保底心跳）
	var decision := _build_decision()
	if bool(decision.get("react", false)):
		_rule_track_fire(decision)
	_llm_timer += 0.0
	_maybe_llm_tick(0.0)

func _maybe_llm_tick(_delta: float) -> void:
	# 轨道B：LLM 自主决策（按档位周期；关闭时跳过）
	if not _customization_service.llm_enabled:
		return
	var llm_interval: float = PRESENCE_LLM_TICK.get(_customization_service.presence_level, 45.0)
	if _llm_timer < llm_interval:
		return
	_llm_timer = 0.0
	_llm_track_ask()

var _last_tags: Array[String] = []
var _last_snapshot_key: String = ""

## 组装决策快照（轨道A/B 共用）：快照 + tags + persona + 规则引擎判定
func _build_decision() -> Dictionary:
	var snapshot_raw = _context_collector.get_snapshot()
	var snapshot: Dictionary = {}
	if typeof(snapshot_raw) == TYPE_DICTIONARY:
		snapshot = snapshot_raw as Dictionary
	snapshot["quiet_hours_start"] = _customization_service.quiet_hours_start
	snapshot["quiet_hours_end"] = _customization_service.quiet_hours_end
	snapshot["presence_level"] = _customization_service.presence_level
	_inject_psyche(snapshot)
	# 作息记忆线进决策上下文（深夜关怀等意图消费）
	var memory_raw = _profile_service.build_memory_lines()
	var memory_lines: Array = []
	if typeof(memory_raw) == TYPE_ARRAY:
		for line_value in memory_raw:
			memory_lines.append(String(line_value))
	snapshot["memory_lines"] = memory_lines

	var recent_raw = _context_collector.get_recent_events(600)
	var recent_events: Array[Dictionary] = []
	if typeof(recent_raw) == TYPE_ARRAY:
		for item in recent_raw:
			if typeof(item) == TYPE_DICTIONARY:
				recent_events.append(item as Dictionary)

	# 生成快照特征 key，相同时复用上次 tags 跳过 ingest
	var snap_key := "%s|%s|%s" % [
		str(snapshot.get("typing_rate", 0.0)).left(4),
		str(snapshot.get("idle_duration", 0)).left(4),
		str(snapshot.get("hour", 0))
	]
	var tags: Array[String] = _last_tags
	if snap_key != _last_snapshot_key:
		_last_snapshot_key = snap_key
		_profile_service.ingest_snapshot(snapshot)
		var tags_raw = _profile_service.build_tags(snapshot, recent_events)
		tags = []
		if typeof(tags_raw) == TYPE_ARRAY:
			for tag_value in tags_raw:
				tags.append(String(tag_value))
		_last_tags = tags

	var persona_raw = _customization_service.get_persona()
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary

	_last_snapshot = snapshot
	var decision_raw = _policy_engine.evaluate(snapshot, tags, recent_events, persona)
	var decision: Dictionary = {}
	if typeof(decision_raw) == TYPE_DICTIONARY:
		decision = decision_raw as Dictionary
	decision["recent_events"] = recent_events
	decision["tags"] = tags
	decision["persona"] = persona
	return decision

## 轨道A：保底心跳——动作+模板台词立即上，不等 LLM；LLM 开启时异步润色
func _rule_track_fire(decision: Dictionary) -> void:
	var action_id := String(decision.get("action_id", ""))
	if action_id.is_empty():
		return
	var fallback_line := String(decision.get("template_line", ""))
	record_event("smart_decision", {"action_id": action_id, "intent": String(decision.get("policy_intent", ""))})
	smart_action_requested.emit(action_id, decision)
	smart_line_generated.emit(fallback_line, "policy")
	# 异步润色：5s 内回来且气泡仍在显示则替换
	if _customization_service.llm_enabled:
		_polish_deadline_ms = Time.get_ticks_msec() + 5000
		_llm_adapter.generate_polish_async(
			{"persona": _customization_service.get_persona()}, fallback_line)

## 轨道B：LLM 自主全上下文决策（硬静音/全屏不问；软静音放行）
func _llm_track_ask() -> void:
	var decision := _build_decision()
	var snapshot: Dictionary = _last_snapshot
	if _policy_engine._is_hard_quiet(snapshot) or bool(snapshot.get("fullscreen", false)):
		return
	var fg_app := String(snapshot.get("foreground_app", ""))
	var llm_context := {
		"hour": int(snapshot.get("hour", 12)),
		"foreground_app": fg_app,
		"activity": String(snapshot.get("activity", "")),
		"continuous_active_seconds": float(snapshot.get("continuous_active_seconds", 0.0)),
		"idle_seconds": float(snapshot.get("idle_seconds", 0.0)),
		"typing_per_min": float(snapshot.get("typing_per_min", 0.0)),
		"fullscreen": bool(snapshot.get("fullscreen", false))
	}
	var recent_events: Array[Dictionary] = []
	var recent_raw = decision.get("recent_events", [])
	if typeof(recent_raw) == TYPE_ARRAY:
		for item in recent_raw:
			if typeof(item) == TYPE_DICTIONARY:
				recent_events.append(item as Dictionary)
	var recent_names: Array[Dictionary] = []
	for e in recent_events:
		recent_names.append({"type": String(e.get("type", ""))})
	var tags: Array[String] = []
	var tags_raw = decision.get("tags", [])
	if typeof(tags_raw) == TYPE_ARRAY:
		for tag_value in tags_raw:
			tags.append(String(tag_value))
	var persona: Dictionary = {}
	var persona_raw = decision.get("persona", {})
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary
	_llm_adapter.generate_decision_async({
		"psyche": snapshot.get("psyche", {}),
		"context": llm_context,
		"memory_lines": snapshot.get("memory_lines", []),
		"recent_events": recent_names,
		"tags": tags,
		"persona": persona,
		"silent_streak": _silent_streak,
		"fallback_action": String(decision.get("action_id", "idle")),
		"fallback_line": String(decision.get("template_line", ""))
	}, String(decision.get("action_id", "idle")), String(decision.get("template_line", "")))

func _on_llm_line_ready(line: String, source: String, _meta: Dictionary) -> void:
	if source == "llm_polish":
		# 润色回来：超时（气泡可能已淡出）则丢弃，模板已展示
		if _polish_deadline_ms > 0 and Time.get_ticks_msec() > _polish_deadline_ms:
			return
		smart_line_generated.emit(line, source)
		return
	smart_line_generated.emit(line, source)

func _on_llm_decision_ready(action: String, line: String, source: String, _meta: Dictionary) -> void:
	_silent_streak = 0
	smart_action_requested.emit(action, {"source": source})
	# 空台词 = LLM 选择"只做动作不说话"（llm_silent），不弹气泡
	if not line.is_empty():
		smart_line_generated.emit(line, source)

func _on_llm_no_reaction() -> void:
	# LLM 判断当下不该打扰：安静周期，什么都不发；累计沉默供反压
	_silent_streak += 1
	record_event("smart_quiet", {})
