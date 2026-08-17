class_name FocusObjectiveSystem
extends Node

## 专注会话目标卡系统：卡组管理、按难度抽卡、完成/超时判定。纯逻辑，无 UI。

signal objective_completed(objective_id: String, target: float)
signal objective_failed(objective_id: String, target: float)
signal objective_rolled(objective_id: String, target: float, tier: int)

const OBJECTIVE_KEEP_FOCUS := "keep_focus"
const OBJECTIVE_REDUCE_CHAOS := "reduce_chaos"
const OBJECTIVE_BUILD_AFFECTION := "build_affection"

var _cards: Array[Dictionary] = []
var _current_key: String = ""
var _current_target: float = 0.0
var _start_focus: float = 0.0
var _start_affection: float = 0.0
var _start_chaos: float = 0.0
var _demo_mode: bool = false
var _demo_cursor: int = 0

func set_cards(cards: Array[Dictionary]) -> void:
	var normalized: Array[Dictionary] = []
	for card in cards:
		if not card.has("id"):
			continue
		normalized.append({
			"id": String(card.get("id", "")),
			"target_min": float(card.get("target_min", 0.0)),
			"target_max": float(card.get("target_max", 100.0)),
			"weight": float(card.get("weight", 1.0)),
			"tier_min": int(card.get("tier_min", 1)),
			"tier_max": int(card.get("tier_max", 3))
		})
	if normalized.is_empty():
		return
	_cards = normalized

func set_demo_mode(enabled: bool) -> void:
	_demo_mode = enabled

func reset_demo_cursor() -> void:
	_demo_cursor = 0

func roll_new_objective(tier: int, focus: float, affection: float, chaos: float) -> void:
	if _cards.is_empty():
		return
	var card := {}
	for _i in range(8):
		card = _pick_card(tier)
		_current_key = String(card.get("id", ""))
		_current_target = _sample_target(_current_key, card, focus, affection, chaos)
		if not is_completed(focus, affection, chaos):
			break
	_start_focus = focus
	_start_affection = affection
	_start_chaos = chaos
	objective_rolled.emit(_current_key, _current_target, tier)

func get_objective_key() -> String:
	return _current_key

func get_objective_target() -> float:
	return _current_target

func is_completed(focus: float, affection: float, chaos: float) -> bool:
	match _current_key:
		OBJECTIVE_KEEP_FOCUS:
			return focus >= _current_target
		OBJECTIVE_REDUCE_CHAOS:
			return chaos <= _current_target
		OBJECTIVE_BUILD_AFFECTION:
			return affection >= _current_target
		_:
			return false

func progress(focus: float, affection: float, chaos: float) -> float:
	match _current_key:
		OBJECTIVE_KEEP_FOCUS:
			if _current_target <= 0.0:
				return 0.0
			return clampf(focus / _current_target, 0.0, 1.0)
		OBJECTIVE_REDUCE_CHAOS:
			var span := maxf(_start_chaos - _current_target, 0.01)
			return clampf((_start_chaos - chaos) / span, 0.0, 1.0)
		OBJECTIVE_BUILD_AFFECTION:
			var span_up := maxf(_current_target - _start_affection, 0.01)
			return clampf((affection - _start_affection) / span_up, 0.0, 1.0)
		_:
			return 0.0

func check_progress(focus: float, affection: float, chaos: float) -> bool:
	## 已完成返回 true（由调用方发奖励并重 roll）
	if _current_key.is_empty() or not is_completed(focus, affection, chaos):
		return false
	objective_completed.emit(_current_key, _current_target)
	return true

func check_timeout(timer_left: float, focus: float, affection: float, chaos: float) -> bool:
	## 超时未完成返回 true（由调用方发惩罚并重 roll）
	if timer_left > 0.0 or _current_key.is_empty():
		return false
	if is_completed(focus, affection, chaos):
		return false
	objective_failed.emit(_current_key, _current_target)
	return true

func _pick_card(tier: int) -> Dictionary:
	var cards := _cards_for_tier(tier)
	if cards.is_empty():
		cards = _cards

	if _demo_mode:
		var idx := _demo_cursor % cards.size()
		_demo_cursor += 1
		return cards[idx]

	return _weighted_pick(cards)

func _cards_for_tier(tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _cards:
		if tier >= int(card.get("tier_min", 1)) and tier <= int(card.get("tier_max", 3)):
			result.append(card)
	return result

func _weighted_pick(cards: Array[Dictionary]) -> Dictionary:
	if cards.is_empty():
		return {}

	var total_weight := 0.0
	for card in cards:
		total_weight += maxf(float(card.get("weight", 1.0)), 0.01)

	var roll := randf_range(0.0, total_weight)
	var cursor := 0.0
	for card in cards:
		cursor += maxf(float(card.get("weight", 1.0)), 0.01)
		if roll <= cursor:
			return card

	return cards[cards.size() - 1]

func _sample_target(objective_id: String, card: Dictionary, focus: float, affection: float, chaos: float) -> float:
	var target := randf_range(float(card.get("target_min", 0.0)), float(card.get("target_max", 100.0)))

	match objective_id:
		OBJECTIVE_KEEP_FOCUS:
			if focus >= target:
				target = minf(95.0, focus + 6.0)
		OBJECTIVE_BUILD_AFFECTION:
			if affection >= target:
				target = minf(95.0, affection + 6.0)
		OBJECTIVE_REDUCE_CHAOS:
			if chaos <= target:
				target = maxf(2.0, chaos - 1.0)
		_:
			pass

	return target

static func default_cards() -> Array[Dictionary]:
	return [
		{"id": OBJECTIVE_KEEP_FOCUS, "target_min": 62.0, "target_max": 78.0, "weight": 1.6, "tier_min": 1, "tier_max": 2},
		{"id": OBJECTIVE_KEEP_FOCUS, "target_min": 72.0, "target_max": 90.0, "weight": 1.1, "tier_min": 2, "tier_max": 3},
		{"id": OBJECTIVE_REDUCE_CHAOS, "target_min": 18.0, "target_max": 34.0, "weight": 1.4, "tier_min": 1, "tier_max": 2},
		{"id": OBJECTIVE_REDUCE_CHAOS, "target_min": 6.0, "target_max": 22.0, "weight": 1.0, "tier_min": 2, "tier_max": 3},
		{"id": OBJECTIVE_BUILD_AFFECTION, "target_min": 48.0, "target_max": 70.0, "weight": 1.3, "tier_min": 1, "tier_max": 2},
		{"id": OBJECTIVE_BUILD_AFFECTION, "target_min": 62.0, "target_max": 88.0, "weight": 0.9, "tier_min": 2, "tier_max": 3}
	]
