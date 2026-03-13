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

var _main_node: Node
var _cat_node: Node2D
var _timer: float = 0.0
var _recent_events: Array[Dictionary] = []

var _context_collector
var _profile_service
var _policy_engine
var _llm_adapter
var _customization_service

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

func bind_nodes(main_node: Node, cat_node: Node2D) -> void:
	_main_node = main_node
	_cat_node = cat_node

func configure(settings: Dictionary) -> void:
	_customization_service.apply_settings(settings)
	_llm_adapter.enabled = _customization_service.llm_enabled

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
		return

	_timer = 0.0
	_evaluate_policy()

func _evaluate_policy() -> void:
	var snapshot_raw = _context_collector.get_snapshot()
	var snapshot: Dictionary = {}
	if typeof(snapshot_raw) == TYPE_DICTIONARY:
		snapshot = snapshot_raw as Dictionary
	snapshot["quiet_hours_start"] = _customization_service.quiet_hours_start
	snapshot["quiet_hours_end"] = _customization_service.quiet_hours_end

	var recent_raw = _context_collector.get_recent_events(600)
	var recent_events: Array[Dictionary] = []
	if typeof(recent_raw) == TYPE_ARRAY:
		for item in recent_raw:
			if typeof(item) == TYPE_DICTIONARY:
				recent_events.append(item as Dictionary)

	_profile_service.ingest_snapshot(snapshot)
	var tags_raw = _profile_service.build_tags(snapshot, recent_events)
	var tags: Array[String] = []
	if typeof(tags_raw) == TYPE_ARRAY:
		for tag_value in tags_raw:
			tags.append(String(tag_value))

	var persona_raw = _customization_service.get_persona()
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary

	var decision_raw = _policy_engine.evaluate(snapshot, tags, recent_events, persona)
	var decision: Dictionary = {}
	if typeof(decision_raw) == TYPE_DICTIONARY:
		decision = decision_raw as Dictionary

	if not bool(decision.get("react", false)):
		return

	var action_id := String(decision.get("action_id", ""))
	if action_id.is_empty():
		return
	smart_action_requested.emit(action_id, decision)
	record_event("smart_decision", {"action_id": action_id, "intent": String(decision.get("policy_intent", ""))})

	var fallback_line := String(decision.get("template_line", ""))
	if _customization_service.llm_enabled:
		_llm_adapter.generate_line_async({
			"intent": String(decision.get("policy_intent", "")),
			"fallback_line": fallback_line,
			"tags": tags,
			"persona": persona
		}, fallback_line)
	else:
		smart_line_generated.emit(fallback_line, "policy")

func _on_llm_line_ready(line: String, source: String, _meta: Dictionary) -> void:
	smart_line_generated.emit(line, source)
