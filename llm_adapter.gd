class_name LLMAdapter
extends Node

## 云端 LLM 适配层（失败自动回退）

signal line_ready(line: String, source: String, meta: Dictionary)

@export var enabled: bool = false
@export var endpoint: String = "https://api.openai.com/v1/chat/completions"
@export var model: String = "gpt-4o-mini"
@export var api_key_env: String = "OPENAI_API_KEY"
@export var timeout_seconds: float = 10.0

var _http_request: HTTPRequest
var _fallback_line: String = ""
var _pending: bool = false

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = timeout_seconds
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

func generate_line_async(payload: Dictionary, fallback_line: String) -> void:
	_fallback_line = fallback_line
	if not enabled:
		line_ready.emit(_fallback_line, "policy", {"reason": "llm_disabled"})
		return
	if _pending:
		line_ready.emit(_fallback_line, "policy", {"reason": "llm_busy"})
		return

	var api_key := OS.get_environment(api_key_env)
	if api_key.is_empty():
		line_ready.emit(_fallback_line, "policy", {"reason": "api_key_missing"})
		return

	var prompt_text := _build_prompt(payload)
	var body := {
		"model": model,
		"messages": [
			{"role": "system", "content": "You are a concise desktop pet assistant. Return one short line in Simplified Chinese."},
			{"role": "user", "content": prompt_text}
		],
		"temperature": 0.7
	}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	])
	_pending = true
	var err := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_pending = false
		line_ready.emit(_fallback_line, "policy", {"reason": "request_failed", "code": err})

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		line_ready.emit(_fallback_line, "policy", {"reason": "http_error", "result": result, "code": response_code})
		return

	var content := body.get_string_from_utf8()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		line_ready.emit(_fallback_line, "policy", {"reason": "invalid_json"})
		return

	var line := _extract_line(parsed as Dictionary)
	if line.is_empty():
		line_ready.emit(_fallback_line, "policy", {"reason": "empty_line"})
		return
	line_ready.emit(line, "llm", {"code": response_code})

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
