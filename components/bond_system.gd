class_name BondSystem
extends Node

## 亲密度养成系统：只涨不跌的 bond 值驱动等级解锁
## 与瞬时好感度(affection)分离：affection 表达当下态度可涨可跌，
## bond 是长期养成的进度(喂食/逗猫/摸摸/陪玩累计)，解锁动作与品种

signal bond_changed(bond: float, level: int)
signal level_up(new_level: int, unlock: Dictionary)

# —— 等级定义：bond 阈值 + 解锁内容 ——
const LEVELS := [
	{"level": 1, "need": 0.0, "title": "初识", "unlock_anim": "", "unlock_breed": ""},
	{"level": 2, "need": 50.0, "title": "点头之交", "unlock_anim": "greet", "unlock_breed": ""},
	{"level": 3, "need": 150.0, "title": "熟悉", "unlock_anim": "celebrate", "unlock_breed": "calico"},
	{"level": 4, "need": 320.0, "title": "好朋友", "unlock_anim": "comfort", "unlock_breed": "british_blue"},
	{"level": 5, "need": 600.0, "title": "挚友", "unlock_anim": "break_hint", "unlock_breed": "tuxedo"},
]

# —— 各互动的 bond 增量(同类型连续重复收益递减) ——
const BOND_GAINS := {
	"food_given": 4.0,
	"wand_given": 5.0,
	"head_pat": 2.0,
	"body_touch": 1.5,
	"pet": 2.0,
	"play_success": 6.0,
}
const REPEAT_DECAY := 0.6      # 连续同类互动每次乘以该系数
const REPEAT_WINDOW := 120.0   # 窗口期(秒)
const DAILY_BOND_CAP := 200.0  # 每日上限,防刷

var bond: float = 0.0
var _last_gain_type := ""
var _last_gain_time := 0.0
var _decay_factor := 1.0
var _today_key := ""
var _today_bond := 0.0

func _ready() -> void:
	_roll_day_if_needed()

func get_level() -> int:
	var lv := 1
	for entry in LEVELS:
		if bond >= entry["need"]:
			lv = entry["level"]
	return lv

func get_level_info(level: int = -1) -> Dictionary:
	var target := level if level > 0 else get_level()
	for entry in LEVELS:
		if entry["level"] == target:
			return entry
	return LEVELS[0]

func get_next_level_info() -> Dictionary:
	var next := get_level() + 1
	for entry in LEVELS:
		if entry["level"] == next:
			return entry
	return {}  # 已满级

func get_progress() -> float:
	## 当前等级内进度 0-1
	var cur := get_level_info()
	var next := get_next_level_info()
	if next.is_empty():
		return 1.0
	var span: float = next["need"] - cur["need"]
	if span <= 0.0:
		return 1.0
	return clampf((bond - cur["need"]) / span, 0.0, 1.0)

func add_bond(interaction_type: String, amount: float = -1.0) -> float:
	## 记录互动涨 bond;返回实际增量(0=被日上限或无增益类型拦下)
	if not BOND_GAINS.has(interaction_type):
		return 0.0
	_roll_day_if_needed()
	if _today_bond >= DAILY_BOND_CAP:
		return 0.0
	var gain: float = BOND_GAINS[interaction_type] if amount < 0.0 else amount
	# 同类连续重复递减
	var now := Time.get_unix_time_from_system()
	if interaction_type == _last_gain_type and now - _last_gain_time < REPEAT_WINDOW:
		_decay_factor *= REPEAT_DECAY
	else:
		_decay_factor = 1.0
	gain *= _decay_factor
	gain = minf(gain, DAILY_BOND_CAP - _today_bond)
	var old_level := get_level()
	bond += gain
	_today_bond += gain
	_last_gain_type = interaction_type
	_last_gain_time = now
	var new_level := get_level()
	bond_changed.emit(bond, new_level)
	if new_level > old_level:
		level_up.emit(new_level, get_level_info(new_level))
	return gain

func is_anim_unlocked(anim_name: String) -> bool:
	## 解锁规则:1 级即拥有基础动作;表内动作需要达到对应等级
	var lv := get_level()
	for entry in LEVELS:
		if entry["unlock_anim"] == anim_name:
			return lv >= entry["level"]
	return true  # 不在解锁表中的动作默认可用

func is_breed_unlocked(breed_id: String) -> bool:
	var lv := get_level()
	for entry in LEVELS:
		if entry["unlock_breed"] == breed_id:
			return lv >= entry["level"]
	return true

func get_unlocked_breeds() -> Array:
	var result: Array = []
	for entry in LEVELS:
		var breed: String = entry["unlock_breed"]
		if not breed.is_empty() and not result.has(breed):
			result.append(breed)
	return result

func get_save_data() -> Dictionary:
	return {"bond": bond, "today": _today_key, "today_bond": _today_bond}

func load_save_data(data: Dictionary) -> void:
	bond = clampf(float(data.get("bond", 0.0)), 0.0, 9999.0)
	_today_key = String(data.get("today", ""))
	_today_bond = clampf(float(data.get("today_bond", 0.0)), 0.0, DAILY_BOND_CAP)
	if _today_key != _date_key():
		_today_key = _date_key()
		_today_bond = 0.0

func _roll_day_if_needed() -> void:
	var key := _date_key()
	if key != _today_key:
		_today_key = key
		_today_bond = 0.0

func _date_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]
