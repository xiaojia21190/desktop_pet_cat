class_name LLMAdapter
extends Node

## 云端 LLM 适配层（失败自动回退）

signal line_ready(line: String, source: String, meta: Dictionary)
signal decision_ready(action: String, line: String, source: String, meta: Dictionary)

@export var enabled: bool = false
@export var endpoint: String = "https://api.openai.com/v1/chat/completions"
@export var model: String = "gpt-4o-mini"
@export var api_key: String = ""
@export var api_key_env: String = "OPENAI_API_KEY"
@export var timeout_seconds: float = 10.0

var _http_request: HTTPRequest
var _fallback_line: String = ""
var _fallback_action: String = ""
var _pending: bool = false
var _decision_mode: bool = false

# LLM 决策缓存（intent → {action, line, timestamp}）
var _decision_cache: Dictionary = {}
const CACHE_TTL_SECONDS: float = 480.0  # 8分钟

const VALID_ACTIONS: Array[String] = [
	"idle", "walk", "watch", "pounce", "chase", "roll", "tail_wag",
	"sleep_curl", "greet", "comfort", "celebrate", "break_hint",
	"retreat", "lick", "blocking"
]

const SYSTEM_PROMPT_LINE := "You are a concise desktop pet assistant. Return one short line in Simplified Chinese."

const SYSTEM_PROMPT_DECISION := """You are a desktop cat pet AI controller. Given the user's context, decide what action the cat should perform and what it should say.

Available actions: idle, walk, watch, pounce, chase, roll, tail_wag, sleep_curl, greet, comfort, celebrate, break_hint, retreat, lick, blocking

Rules:
- Choose actions that match the context (e.g. comfort when user is frustrated, break_hint when working too long, greet when returning)
- The line should be a short, cute cat personality sentence in Simplified Chinese (max 25 chars)
- Personality styles: tsundere=傲娇, gentle=温柔, playful=活泼

Return ONLY a JSON object: {"action":"<action>","line":"<text>"}"""

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = timeout_seconds
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

func configure(settings: Dictionary) -> void:
	enabled = bool(settings.get("llm_enabled", enabled))
	var new_endpoint := String(settings.get("llm_endpoint", endpoint)).strip_edges()
	if not new_endpoint.is_empty():
		endpoint = new_endpoint
	var new_model := String(settings.get("llm_model", model)).strip_edges()
	if not new_model.is_empty():
		model = new_model
	api_key = String(settings.get("llm_api_key", api_key)).strip_edges()
	var env_name := String(settings.get("llm_api_key_env", api_key_env)).strip_edges()
	if not env_name.is_empty():
		api_key_env = env_name
	timeout_seconds = clampf(float(settings.get("llm_timeout_seconds", timeout_seconds)), 1.0, 60.0)
	if _http_request:
		_http_request.timeout = timeout_seconds

func generate_line_async(payload: Dictionary, fallback_line: String) -> void:
	_decision_mode = false
	_fallback_line = fallback_line
	_fallback_action = ""
	_send_request(SYSTEM_PROMPT_LINE, _build_prompt(payload))

func generate_decision_async(payload: Dictionary, fallback_action: String, fallback_line: String) -> void:
	_decision_mode = true
	_fallback_action = fallback_action
	_fallback_line = fallback_line

	# 检查缓存
	var cache_key := String(payload.get("intent", ""))
	if not cache_key.is_empty() and _decision_cache.has(cache_key):
		var cached: Dictionary = _decision_cache[cache_key]
		var age: float = Time.get_unix_time_from_system() - float(cached.get("timestamp", 0.0))
		if age < CACHE_TTL_SECONDS:
			decision_ready.emit(String(cached.get("action", fallback_action)), String(cached.get("line", fallback_line)), "llm_cache", {})
			return

	_send_request(SYSTEM_PROMPT_DECISION, _build_decision_prompt(payload))

func _send_request(system_prompt: String, user_prompt: String) -> void:
	if not enabled:
		_emit_fallback("llm_disabled")
		return
	if _pending:
		_emit_fallback("llm_busy")
		return

	var resolved_api_key := _resolve_api_key()
	if resolved_api_key.is_empty():
		_emit_fallback("api_key_missing")
		return

	var body := {
		"model": model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt}
		],
		"temperature": 0.7
	}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + resolved_api_key
	])
	_pending = true
	var err := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_pending = false
		_emit_fallback("request_failed")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_emit_fallback("http_error")
		return

	var content := body.get_string_from_utf8()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		_emit_fallback("invalid_json")
		return

	var raw_line := _extract_line(parsed as Dictionary)
	if raw_line.is_empty():
		_emit_fallback("empty_line")
		return

	if _decision_mode:
		_parse_decision_response(raw_line)
	else:
		line_ready.emit(raw_line, "llm", {"code": response_code})

func _parse_decision_response(raw: String) -> void:
	var json = JSON.parse_string(raw)
	if typeof(json) == TYPE_DICTIONARY:
		var d := json as Dictionary
		var action := String(d.get("action", "")).strip_edges()
		var line := String(d.get("line", "")).strip_edges()
		if action in VALID_ACTIONS and not line.is_empty():
			# 写入缓存
			var cache_key := _fallback_action  # intent 用 fallback_action 区分
			_decision_cache[cache_key] = {"action": action, "line": line, "timestamp": Time.get_unix_time_from_system()}
			decision_ready.emit(action, line, "llm", {})
			return

	decision_ready.emit(_fallback_action, raw if not raw.is_empty() else _fallback_line, "llm_partial", {})

func _emit_fallback(reason: String) -> void:
	var meta := {"reason": reason}
	if _decision_mode:
		decision_ready.emit(_fallback_action, _fallback_line, "policy", meta)
	else:
		line_ready.emit(_fallback_line, "policy", meta)

func _extract_line(payload: Dictionary) -> String:
	if payload.has("line"):
		return String(payload.get("line", "")).strip_edges()

	var choices_raw = payload.get("choices", [])
	if typeof(choices_raw) != TYPE_ARRAY:
		return ""
	var choices := choices_raw as Array
	if choices.is_empty():
		return ""
	var first_raw = choices[0]
	if typeof(first_raw) != TYPE_DICTIONARY:
		return ""
	var first := first_raw as Dictionary
	var message_raw = first.get("message", {})
	if typeof(message_raw) != TYPE_DICTIONARY:
		return ""
	var message := message_raw as Dictionary
	return String(message.get("content", "")).strip_edges()

func _build_prompt(payload: Dictionary) -> String:
	var persona_raw = payload.get("persona", {})
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary

	var intent := String(payload.get("intent", ""))
	var fallback := String(payload.get("fallback_line", ""))
	var tags_raw = payload.get("tags", [])
	var tags: Array[String] = []
	if typeof(tags_raw) == TYPE_ARRAY:
		for tag_value in tags_raw:
			tags.append(String(tag_value))

	return "intent=%s; personality=%s; intensity=%s; tags=%s; fallback=%s" % [
		intent,
		String(persona.get("personality", "tsundere")),
		String(persona.get("reminder_intensity", "medium")),
		",".join(tags),
		fallback
	]

func _build_decision_prompt(payload: Dictionary) -> String:
	var persona_raw = payload.get("persona", {})
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary

	var tags_raw = payload.get("tags", [])
	var tags: Array[String] = []
	if typeof(tags_raw) == TYPE_ARRAY:
		for tag_value in tags_raw:
			tags.append(String(tag_value))

	return "intent=%s; personality=%s; intensity=%s; tags=%s; fallback_action=%s" % [
		String(payload.get("intent", "")),
		String(persona.get("personality", "tsundere")),
		String(persona.get("reminder_intensity", "medium")),
		",".join(tags),
		String(payload.get("fallback_action", "idle"))
	]

func _resolve_api_key() -> String:
	if not api_key.is_empty():
		return api_key
	if api_key_env.is_empty():
		return ""
	return String(OS.get_environment(api_key_env)).strip_edges()
