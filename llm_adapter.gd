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
@export var timeout_seconds: float = 45.0

var _http_request: HTTPRequest
var _fallback_line: String = ""
var _fallback_action: String = ""
var _pending: bool = false
var _decision_mode: bool = false
var _polish_mode: bool = false  # 润色请求：成功直接出 line，失败静默（模板已先行展示）

const POLISH_TIMEOUT_SEC := 5.0

# （决策缓存已移除：全上下文模式每次看最新状态）

const VALID_ACTIONS: Array[String] = [
	"idle", "walk", "watch", "pounce", "chase", "roll", "tail_wag",
	"sleep_curl", "greet", "comfort", "celebrate", "break_hint",
	"retreat", "lick", "blocking"
]

const SYSTEM_PROMPT_LINE := "You are a concise desktop pet assistant. Return one short line in Simplified Chinese."

## 档位 → system prompt 人设段（注入决策提示，终结 LLM 系统性沉默）
const PRESENCE_PERSONA := {
	0: "You are a very quiet cat. Speak only for truly important moments (long sitting, victories). At most 1 line per hour.",
	1: "You speak at key moments: meal time, late night care, long sitting. 1-3 lines per hour.",
	2: "You are a friendly co-worker cat. Naturally chime in every 10-15 minutes. Gentle teasing when the user slacks off is fine.",
	3: "You are a chatty cat. Almost every decision should show something (action or line). Actively invite interaction.",
	4: "You adapt to the user's current activity: restrained when they work, playful when they relax. The activity category is provided below.",
}

const SYSTEM_PROMPT_DECISION := """You are the mind of a desktop cat pet living on the user's screen. You receive the cat's inner state and everything you can perceive about the user. Decide how the cat behaves NOW.

Available actions: idle, walk, watch, pounce, chase, roll, tail_wag, sleep_curl, greet, comfort, celebrate, break_hint, retreat, lick, blocking

How to think:
- You are a real cat with personality (tsundere=傲娇, gentle=温柔, playful=活泼), not a notification bot.
- React to the USER's situation: what app they are using, how long they've been working, their recent interactions with you, time of day, your memory of their habits.
- Use your inner state (mood/energy/affection/chaos): tired cat acts tired; high affection cat seeks contact.
- Most of the time a cat does NOT talk. Only speak when there is a genuine reason (max ~1 line per few minutes). If nothing is worth saying, choose "react": false.
- When you do speak: one short sentence (max 25 chars) in Simplified Chinese, in character, referencing the actual situation if natural.
- Do NOT repeat the fallback line; it is only a last-resort hint.

Return ONLY a JSON object: {"react": true/false, "action": "<action>", "line": "<text or empty>"}"""

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = timeout_seconds
	_http_request.use_threads = true
	_apply_system_proxy()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

## 自动应用系统代理：HTTPRequest 默认不走系统代理，直连被墙时表现为
## 重定向循环（RESULT_REDIRECT_LIMIT_REACHED）→ 永远回退规则引擎。
## 优先级：HTTPS_PROXY/HTTP_PROXY 环境变量 > Windows 注册表代理。
func _apply_system_proxy() -> void:
	var proxy_url := _detect_system_proxy()
	if proxy_url.is_empty():
		return
	var parsed := _parse_proxy_url(proxy_url)
	if parsed.is_empty():
		push_warning("LLM 代理配置无法解析: " + proxy_url)
		return
	_http_request.set_http_proxy(parsed["host"], int(parsed["port"]))
	_http_request.set_https_proxy(parsed["host"], int(parsed["port"]))
	print("LLM 已启用系统代理: ", parsed["host"], ":", parsed["port"])

func _detect_system_proxy() -> String:
	for env_name in ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]:
		var value := OS.get_environment(env_name).strip_edges()
		if not value.is_empty():
			return value
	if OS.get_name() == "Windows":
		return _read_windows_proxy()
	return ""

func _read_windows_proxy() -> String:
	# 注册表 ProxyEnable=1 时读 ProxyServer（格式 host:port）
	if not ClassDB.class_exists("RegEx"):
		return ""
	var output: Array = []
	var exit_code := OS.execute("reg", ["query",
		"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
		"/v", "ProxyEnable"], output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	if "0x1" not in String(output[0]):
		return ""
	output = []
	exit_code = OS.execute("reg", ["query",
		"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
		"/v", "ProxyServer"], output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	var line := String(output[0])
	for part in line.split("\n"):
		part = part.strip_edges()
		if part.begins_with("ProxyServer"):
			var value := part.substr(part.find("REG_SZ") + 6).strip_edges()
			# 支持格式：host:port 或 http=host:port;https=host:port
			if ";" in value:
				for seg in value.split(";"):
					if seg.begins_with("https="):
						return seg.substr(6)
				return ""
			return value
	return ""

func _parse_proxy_url(proxy_url: String) -> Dictionary:
	var cleaned := proxy_url
	for scheme in ["http://", "https://"]:
		if cleaned.begins_with(scheme):
			cleaned = cleaned.substr(scheme.length())
	var host_port := cleaned.split(":")
	if host_port.size() != 2:
		return {}
	var port := host_port[1].to_int()
	if port <= 0:
		return {}
	return {"host": host_port[0], "port": port}

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
	# 全上下文决策不做意图缓存：每次都看最新状态，避免"同一意图永远同一句话"
	_send_request(SYSTEM_PROMPT_DECISION, _build_decision_prompt(payload))

## P5b 润色轻请求：模板台词 → 猫味台词（独立小 prompt，5s 短超时，超时用模板）
func generate_polish_async(payload: Dictionary, template_line: String) -> void:
	_decision_mode = false
	_polish_mode = true
	_fallback_line = ""
	_fallback_action = ""
	_http_request.timeout = POLISH_TIMEOUT_SEC
	_send_request(SYSTEM_PROMPT_LINE, _build_polish_prompt(payload, template_line))

func _build_polish_prompt(payload: Dictionary, template_line: String) -> String:
	var persona_raw = payload.get("persona", {})
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary
	return "Rewrite this line as a cat with personality=%s (tsundere=傲娇, gentle=温柔, playful=活泼). Keep it under 25 chars, Simplified Chinese, keep the meaning, no quotes. Line: %s" % [
		String(persona.get("personality", "tsundere")), template_line]

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
	if _polish_mode:
		_polish_mode = false
		_http_request.timeout = timeout_seconds  # 恢复常规超时
		if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
			var polish_parsed = JSON.parse_string(body.get_string_from_utf8())
			if typeof(polish_parsed) == TYPE_DICTIONARY:
				var polish_line := _extract_line(polish_parsed as Dictionary)
				if not polish_line.is_empty():
					line_ready.emit(polish_line, "llm_polish", {"code": response_code})
		# 润色失败静默：模板台词已先行展示，无需兜底
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("LLM 请求失败: result=%d code=%d body=%s" % [result, response_code, body.get_string_from_utf8().left(200)])
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

signal no_reaction  ## LLM 判断当下不该说话/动作（猫保持自然状态）

func _parse_decision_response(raw: String) -> void:
	var json = JSON.parse_string(raw)
	if typeof(json) == TYPE_DICTIONARY:
		var d := json as Dictionary
		var react := bool(d.get("react", true))
		var action := String(d.get("action", "")).strip_edges()
		var line := String(d.get("line", "")).strip_edges()

		# LLM 自主判断不打扰：安静周期，不发动作不发台词
		if not react:
			no_reaction.emit()
			return

		# 只动作不说话（line 允许为空）
		if action in VALID_ACTIONS and line.is_empty():
			decision_ready.emit(action, "", "llm_silent", {})
			return

		if action in VALID_ACTIONS and not line.is_empty():
			decision_ready.emit(action, line, "llm", {})
			return

	decision_ready.emit(_fallback_action, raw if not raw.is_empty() else _fallback_line, "llm_partial", {})

func _emit_fallback(reason: String) -> void:
	if _polish_mode:
		# 润色请求的任何失败都静默（模板已展示）
		_polish_mode = false
		_http_request.timeout = timeout_seconds
		return
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
	## 全上下文决策提示：心理/感知/记忆/事件/建议全打包，LLM 自主判断
	var persona_raw = payload.get("persona", {})
	var persona: Dictionary = {}
	if typeof(persona_raw) == TYPE_DICTIONARY:
		persona = persona_raw as Dictionary

	var psyche_raw = payload.get("psyche", {})
	var psyche: Dictionary = {}
	if typeof(psyche_raw) == TYPE_DICTIONARY:
		psyche = psyche_raw as Dictionary

	var context_raw = payload.get("context", {})
	var context: Dictionary = {}
	if typeof(context_raw) == TYPE_DICTIONARY:
		context = context_raw as Dictionary

	var tags_raw = payload.get("tags", [])
	var tag_text := ""
	if typeof(tags_raw) == TYPE_ARRAY:
		var tags: Array[String] = []
		for tag_value in tags_raw:
			tags.append(String(tag_value))
		tag_text = ",".join(tags)

	var memories_raw = payload.get("memory_lines", [])
	var memory_text := ""
	if typeof(memories_raw) == TYPE_ARRAY and memories_raw.size() > 0:
		var lines: Array[String] = []
		for m in memories_raw:
			lines.append(String(m))
		memory_text = " | ".join(lines)

	var events_raw = payload.get("recent_events", [])
	var events_text := ""
	if typeof(events_raw) == TYPE_ARRAY and events_raw.size() > 0:
		var names: Array[String] = []
		for e in events_raw:
			if typeof(e) == TYPE_DICTIONARY:
				names.append(String((e as Dictionary).get("type", "")))
		events_text = ",".join(names)

	var fg_app := String(context.get("foreground_app", ""))
	var activity := String(context.get("activity", ""))
	var activity_note := ""
	if not fg_app.is_empty():
		activity_note = "user is using %s (%s)" % [fg_app, activity if not activity.is_empty() else "unknown"]

	# P5b：档位人设 + 沉默反压注入
	var presence := clampi(int(persona.get("presence_level", 2)), 0, 4)
	var streak := int(payload.get("silent_streak", 0))
	var streak_note := ""
	if streak >= 2:
		streak_note = "You have stayed silent for the last %d cycles. If there is anything at all worth reacting to, speak now." % streak

	return """== Cat inner state ==
mood=%.0f/100, energy=%.0f/100, affection=%.0f/100, chaos=%.0f/100
personality=%s
presence_persona=%s
%s

== What the cat perceives about the user ==
time=hour %d, %s
continuous_active=%d min, idle=%d min
typing_rate=%.0f/min
%s

== Memory of this user ==
%s

== Recent events (oldest->newest) ==
%s

== Habit tags ==
%s

== Rule engine suggestion (reference only, you may override) ==
action=%s, line=%s

Decide NOW as this cat.""" % [
		float(psyche.get("mood", 50.0)),
		float(psyche.get("energy", 80.0)),
		float(psyche.get("affection", 30.0)),
		float(psyche.get("chaos", 20.0)),
		String(persona.get("personality", "tsundere")),
		String(PRESENCE_PERSONA.get(presence, PRESENCE_PERSONA[2])),
		streak_note,
		int(context.get("hour", 12)),
		activity_note,
		int(float(context.get("continuous_active_seconds", 0.0)) / 60.0),
		int(float(context.get("idle_seconds", 0.0)) / 60.0),
		float(context.get("typing_per_min", 0.0)),
		"in fullscreen" if bool(context.get("fullscreen", false)) else "",
		memory_text if not memory_text.is_empty() else "(none yet)",
		events_text if not events_text.is_empty() else "(quiet)",
		tag_text,
		String(payload.get("fallback_action", "idle")),
		String(payload.get("fallback_line", ""))
	]

func _resolve_api_key() -> String:
	if not api_key.is_empty():
		return api_key
	if api_key_env.is_empty():
		return ""
	return String(OS.get_environment(api_key_env)).strip_edges()
