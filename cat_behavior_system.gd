extends Node
class_name CatBehaviorSystem

# 猫咪行为系统 - 高级版
# 包含：情绪系统、记忆系统、学习系统、状态链系统

# P10：节奏表（preload 避免 headless 全局类名注册滞后）
const AnimationTiming = preload("res://components/animation_timing.gd")

# ============================================
# 一、情绪系统
# ============================================

# 情绪属性（0-100）
var mood: float = 50.0        # 心情：影响傲娇/撒娇倾向
var energy: float = 80.0      # 精力：影响活跃/懒散倾向
var affection: float = 30.0   # 好感度：影响对用户的态度
var curiosity: float = 60.0   # 好奇心：影响探索/互动倾向
var chaos: float = 20.0       # 混乱度：影响猫闹腾程度（事件驱动，不随时间衰减）

# 情绪衰减/恢复速率（每秒）
const MOOD_DECAY = 0.5        # 心情自然衰减
const ENERGY_DECAY = 0.3      # 精力自然衰减
const ENERGY_RECOVERY = 2.0   # 睡觉时精力恢复
const AFFECTION_DECAY = 0.1   # 好感度缓慢衰减

# 情绪阈值
const MOOD_HIGH = 70
const MOOD_LOW = 30
const ENERGY_HIGH = 70
const ENERGY_LOW = 30
const AFFECTION_HIGH = 70
const AFFECTION_LOW = 30

# 情绪状态枚举
enum MoodState { HAPPY, NEUTRAL, GRUMPY }
enum EnergyState { ENERGETIC, NORMAL, TIRED }
enum AffectionState { LOVING, NEUTRAL, TSUNDERE }

func get_mood_state() -> MoodState:
	if mood > MOOD_HIGH: return MoodState.HAPPY
	if mood < MOOD_LOW: return MoodState.GRUMPY
	return MoodState.NEUTRAL

func get_energy_state() -> EnergyState:
	if energy > ENERGY_HIGH: return EnergyState.ENERGETIC
	if energy < ENERGY_LOW: return EnergyState.TIRED
	return EnergyState.NORMAL

func get_affection_state() -> AffectionState:
	if affection > AFFECTION_HIGH: return AffectionState.LOVING
	if affection < AFFECTION_LOW: return AffectionState.TSUNDERE
	return AffectionState.NEUTRAL

# 情绪变化事件
signal mood_changed(new_mood: float, old_mood: float)
signal energy_changed(new_energy: float, old_energy: float)
signal affection_changed(new_affection: float, old_affection: float)
signal chaos_changed(new_chaos: float, old_chaos: float)
signal emotion_state_changed(emotion_type: String, new_state: int)

func modify_mood(delta: float):
	var old = mood
	mood = clamp(mood + delta, 0, 100)
	if mood != old:
		mood_changed.emit(mood, old)
		_check_state_change("mood", old, mood)

func modify_energy(delta: float):
	var old = energy
	energy = clamp(energy + delta, 0, 100)
	if energy != old:
		energy_changed.emit(energy, old)
		_check_state_change("energy", old, energy)

func modify_chaos(delta: float):
	var old = chaos
	chaos = clamp(chaos + delta, 0, 100)
	if chaos != old:
		chaos_changed.emit(chaos, old)

func modify_affection(delta: float):
	var old = affection
	affection = clamp(affection + delta, 0, 100)
	if affection != old:
		affection_changed.emit(affection, old)
		_check_state_change("affection", old, affection)

func _check_state_change(emotion_type: String, old_value: float, new_value: float):
	var old_state = _get_state_for_value(emotion_type, old_value)
	var new_state = _get_state_for_value(emotion_type, new_value)
	if old_state != new_state:
		emotion_state_changed.emit(emotion_type, new_state)

func _get_state_for_value(emotion_type: String, value: float) -> int:
	match emotion_type:
		"mood":
			if value > MOOD_HIGH: return MoodState.HAPPY
			if value < MOOD_LOW: return MoodState.GRUMPY
			return MoodState.NEUTRAL
		"energy":
			if value > ENERGY_HIGH: return EnergyState.ENERGETIC
			if value < ENERGY_LOW: return EnergyState.TIRED
			return EnergyState.NORMAL
		"affection":
			if value > AFFECTION_HIGH: return AffectionState.LOVING
			if value < AFFECTION_LOW: return AffectionState.TSUNDERE
			return AffectionState.NEUTRAL
	return 0

# ============================================
# 二、记忆系统
# ============================================

# 互动记录
var interaction_history: Array = []  # 最近的互动记录
const MAX_HISTORY_SIZE = 100

# 互动统计
var interaction_stats = {
	"head_pat": 0,
	"body_touch": 0,
	"tail_touch": 0,
	"drag": 0,
	"food_given": 0,
	"wand_given": 0,
	"ignored_food": 0,
	"ignored_wand": 0,
}

# 时间记忆
var last_interaction_time: float = 0.0
var last_feed_time: float = 0.0
var total_play_time: float = 0.0
var session_start_time: float = 0.0

# 偏好记忆
var favorite_actions: Dictionary = {}  # 动作 -> 触发次数
var disliked_actions: Dictionary = {}  # 被打断的动作

func record_interaction(interaction_type: String, details: Dictionary = {}):
	var record = {
		"type": interaction_type,
		"time": Time.get_unix_time_from_system(),
		"mood": mood,
		"energy": energy,
		"details": details
	}
	interaction_history.append(record)

	# 限制历史记录大小
	if interaction_history.size() > MAX_HISTORY_SIZE:
		interaction_history.pop_front()

	# 更新统计
	if interaction_stats.has(interaction_type):
		interaction_stats[interaction_type] += 1

	last_interaction_time = Time.get_ticks_msec() / 1000.0

	# 根据互动类型调整情绪
	_apply_interaction_emotion_effect(interaction_type)

func _apply_interaction_emotion_effect(interaction_type: String):
	match interaction_type:
		"head_touch", "head_pat":
			if get_affection_state() == AffectionState.LOVING:
				modify_mood(5)
				modify_affection(2)
			else:
				modify_mood(-2)  # 傲娇时不喜欢被摸
		"body_touch":
			# 摸身体时有正向反馈
			modify_mood(3)
		"tail_touch":
			modify_mood(-3)  # 猫咪通常不喜欢被摸尾巴
			modify_affection(-1)
		"food_given":
			modify_mood(8)
			modify_affection(3)
			last_feed_time = Time.get_ticks_msec() / 1000.0
		"wand_given":
			modify_mood(5)
			modify_energy(-5)  # 玩耍消耗精力
		"drag":
			modify_mood(-5)
			modify_affection(-2)

func get_time_since_last_interaction() -> float:
	return Time.get_ticks_msec() / 1000.0 - last_interaction_time

func get_time_since_last_feed() -> float:
	if last_feed_time == 0:
		return 9999.0
	return Time.get_ticks_msec() / 1000.0 - last_feed_time

# ============================================
# 三、学习系统
# ============================================

# 行为权重（可学习调整）
var behavior_weights = {
	# 自主行为
	"idle_stand": 25.0,
	"idle_sit": 20.0,
	"idle_lie": 15.0,
	"lick": 15.0,
	"daze": 10.0,
	"kneading": 8.0,
	"stretch": 5.0,
	"yawn": 4.0,
	"sleep_curl": 6.0,
	"jump": 3.0,
	# 移动行为
	"walk": 20.0,
	"trot": 10.0,
	"run": 5.0,
	# 互动行为
	"watch": 15.0,
	"pounce": 10.0,
	"roll": 10.0,
	"tail_wag": 10.0,
	"chase_mouse": 12.0,
	"pounce_mouse": 8.0,
}

# 学习参数
const LEARNING_RATE = 0.1
const WEIGHT_MIN = 1.0
const WEIGHT_MAX = 50.0

# 正向强化：用户喜欢的行为增加权重
func reinforce_behavior(action: String, positive: bool = true):
	if not behavior_weights.has(action):
		behavior_weights[action] = 10.0

	var delta = LEARNING_RATE * (10 if positive else -10)
	behavior_weights[action] = clamp(
		behavior_weights[action] + delta,
		WEIGHT_MIN,
		WEIGHT_MAX
	)

	# 记录偏好
	if positive:
		if not favorite_actions.has(action):
			favorite_actions[action] = 0
		favorite_actions[action] += 1
	else:
		if not disliked_actions.has(action):
			disliked_actions[action] = 0
		disliked_actions[action] += 1

# 根据当前情绪状态调整权重（带缓存）
func get_adjusted_weights() -> Dictionary:
	var e := get_energy_state()
	var m := get_mood_state()
	var a := get_affection_state()
	if not _cached_weights.is_empty() and e == _cache_energy_state and m == _cache_mood_state and a == _cache_affection_state:
		return _cached_weights

	var adjusted = behavior_weights.duplicate()

	# 根据精力调整
	match e:
		EnergyState.ENERGETIC:
			_multiply_weights(adjusted, ["run", "trot", "pounce", "roll"], 2.0)
			_multiply_weights(adjusted, ["idle_lie", "sleep", "daze"], 0.3)
		EnergyState.TIRED:
			_multiply_weights(adjusted, ["run", "trot", "pounce"], 0.2)
			_multiply_weights(adjusted, ["idle_lie", "sleep", "yawn"], 3.0)

	# 根据心情调整
	match m:
		MoodState.HAPPY:
			_multiply_weights(adjusted, ["roll", "kneading", "happy"], 2.0)
			_multiply_weights(adjusted, ["ignore", "angry", "walk_away"], 0.3)
		MoodState.GRUMPY:
			_multiply_weights(adjusted, ["ignore", "angry", "walk_away", "tail_wag"], 2.5)
			_multiply_weights(adjusted, ["happy", "kneading"], 0.2)

	# 根据好感度调整
	match a:
		AffectionState.LOVING:
			_multiply_weights(adjusted, ["head_pat_happy", "kneading", "happy"], 2.0)
			_multiply_weights(adjusted, ["head_pat_dodge", "ignore"], 0.3)
		AffectionState.TSUNDERE:
			_multiply_weights(adjusted, ["ignore", "walk_away", "peek", "head_pat_dodge"], 2.5)
			_multiply_weights(adjusted, ["head_pat_happy"], 0.1)

	_cached_weights = adjusted
	_cache_energy_state = e
	_cache_mood_state = m
	_cache_affection_state = a
	return adjusted

func _multiply_weights(weights: Dictionary, actions: Array, multiplier: float):
	for action in actions:
		if weights.has(action):
			weights[action] *= multiplier

# 根据权重随机选择行为
func select_weighted_behavior(available_actions: Array) -> String:
	var adjusted = get_adjusted_weights()
	var total_weight = 0.0

	for action in available_actions:
		if adjusted.has(action):
			total_weight += adjusted[action]

	if total_weight == 0:
		return available_actions[randi() % available_actions.size()]

	var rand = randf() * total_weight
	var cumulative = 0.0

	for action in available_actions:
		if adjusted.has(action):
			cumulative += adjusted[action]
			if rand <= cumulative:
				return action

	return available_actions[0]

# ============================================
# 四、状态链系统
# ============================================

# 状态链定义
const STATE_CHAINS = {
	"pounce_sequence": {
		"states": ["watch", "pounce_ready", "pounce"],
		"durations": [1.0, 0.5, 0.3],
		"interruptible": true
	},
	"sleep_sequence": {
		"states": ["yawn", "idle_lie", "sleep"],
		"durations": [2.0, 3.0, -1],  # -1 表示持续直到被打断
		"interruptible": true
	},
	"eat_sequence": {
		"states": ["sneak_eat", "eat", "lick", "happy"],
		"durations": [1.5, 3.0, 2.0, 1.0],
		"interruptible": false
	},
	"startled_sequence": {
		"states": ["startled", "run", "peek"],
		"durations": [0.5, 1.5, 2.0],
		"interruptible": true
	},
	"greeting_sequence": {
		"states": ["watch", "trot", "tail_wag", "happy"],
		"durations": [0.5, 1.0, 1.5, 1.0],
		"interruptible": true
	},
	"angry_sequence": {
		"states": ["angry", "tail_wag", "walk_away", "ignore"],
		"durations": [1.0, 1.5, 2.0, 3.0],
		"interruptible": true
	},
	"curious_peek": {
		"states": ["watch", "sneak_eat", "peek", "idle_stand"],
		"durations": [1.0, 1.5, 2.0, 0.5],
		"interruptible": true
	},
	"stretch_relax": {
		"states": ["stretch", "yawn", "idle_lie"],
		"durations": [2.0, 2.0, -1],
		"interruptible": true
	},
	"playful_burst": {
		"states": ["run", "pounce_attack", "rolling", "happy"],
		"durations": [1.0, 0.5, 1.5, 1.0],
		"interruptible": true
	},
	"grooming_sequence": {
		"states": ["lick_groom", "stretch", "idle_sit"],
		"durations": [3.0, 2.0, 1.0],
		"interruptible": true
	},
}

# 当前状态链
var current_chain: String = ""
var chain_index: int = 0
var chain_timer: float = 0.0

signal chain_started(chain_name: String)
signal chain_step_changed(chain_name: String, step_index: int, state: String)
signal chain_completed(chain_name: String)
signal chain_interrupted(chain_name: String, at_step: int)

func start_chain(chain_name: String) -> bool:
	if not STATE_CHAINS.has(chain_name):
		return false

	# 检查是否可以打断当前链
	if current_chain != "" and not STATE_CHAINS[current_chain].interruptible:
		return false

	current_chain = chain_name
	chain_index = 0
	chain_timer = 0.0
	chain_started.emit(chain_name)
	_emit_chain_step()
	return true

func update_chain(delta: float) -> String:
	if current_chain == "":
		return ""

	var chain = STATE_CHAINS[current_chain]
	var duration: float = float(chain.durations[chain_index])
	# P10：步进时长不低于对应动画播完一遍（节奏表）——杜绝调度比动画短把动作截断
	var chain_anim: String = AnimationConfig.get_animation_for_state(String(chain.states[chain_index]))
	var anim_cfg := AnimationConfig.get_animation_config(chain_anim)
	if not anim_cfg.is_empty():
		var floor_t: float = AnimationTiming.min_duration(
			String(anim_cfg.get("name", chain_anim)),
			int(anim_cfg.get("frames", 8)),
			float(anim_cfg.get("speed", 6.0)))
		duration = maxf(duration, floor_t)

	# -1 表示无限持续
	if duration > 0:
		chain_timer += delta
		if chain_timer >= duration:
			chain_timer = 0.0
			chain_index += 1

			if chain_index >= chain.states.size():
				var completed_chain = current_chain
				current_chain = ""
				chain_completed.emit(completed_chain)
				return ""
			else:
				_emit_chain_step()

	return chain.states[chain_index]

func _emit_chain_step():
	var chain = STATE_CHAINS[current_chain]
	chain_step_changed.emit(current_chain, chain_index, chain.states[chain_index])

func interrupt_chain():
	if current_chain != "" and STATE_CHAINS[current_chain].interruptible:
		var interrupted_chain = current_chain
		var interrupted_step = chain_index
		current_chain = ""
		chain_interrupted.emit(interrupted_chain, interrupted_step)

func is_in_chain() -> bool:
	return current_chain != ""

func get_current_chain_state() -> String:
	if current_chain == "":
		return ""
	return STATE_CHAINS[current_chain].states[chain_index]

# ============================================
# 五、时间感知系统
# ============================================

func get_time_of_day() -> String:
	var hour = Time.get_datetime_dict_from_system().hour
	if hour >= 6 and hour < 12:
		return "morning"
	elif hour >= 12 and hour < 18:
		return "afternoon"
	elif hour >= 18 and hour < 22:
		return "evening"
	else:
		return "night"

func get_time_behavior_modifier() -> Dictionary:
	var time = get_time_of_day()
	match time:
		"morning":
			return {"energy_mod": 1.2, "activity_mod": 1.1}
		"afternoon":
			return {"energy_mod": 0.8, "activity_mod": 0.9}  # 午后犯困
		"evening":
			return {"energy_mod": 1.3, "activity_mod": 1.2}  # 猫咪黄昏活跃
		"night":
			return {"energy_mod": 0.5, "activity_mod": 0.6}
	return {"energy_mod": 1.0, "activity_mod": 1.0}

# ============================================
# 六、更新循环
# ============================================

var _time_check_timer: float = 0.0
const TIME_CHECK_INTERVAL = 60.0  # 每分钟检查一次时间

# 权重缓存
var _cached_weights: Dictionary = {}
var _cache_energy_state: int = -1
var _cache_mood_state: int = -1
var _cache_affection_state: int = -1

# 时间修正缓存
var _cached_time_mod: Dictionary = {"energy_mod": 1.0, "activity_mod": 1.0}

func update(delta: float):
	# 情绪自然衰减（应用时间修正缓存）
	var time_mod = _cached_time_mod
	var energy_decay_rate = ENERGY_DECAY * (2.0 - time_mod.energy_mod)  # 夜晚精力衰减更快

	modify_mood(-MOOD_DECAY * delta)
	modify_energy(-energy_decay_rate * delta)
	modify_affection(-AFFECTION_DECAY * delta)

	# 长时间无互动影响
	var idle_time = get_time_since_last_interaction()
	if idle_time > 300:  # 5分钟无互动
		modify_mood(-0.1 * delta)

	# 定期检查时间并调整行为
	_time_check_timer += delta
	if _time_check_timer >= TIME_CHECK_INTERVAL:
		_time_check_timer = 0.0
		_apply_time_based_effects()

	# 更新状态链
	if is_in_chain():
		update_chain(delta)

	# 更新游戏时间
	total_play_time += delta

func _apply_time_based_effects():
	var time = get_time_of_day()
	_cached_time_mod = get_time_behavior_modifier()
	var mod = _cached_time_mod

	match time:
		"morning":
			# 早晨精力恢复
			modify_energy(5 * mod.energy_mod)
		"afternoon":
			# 午后犯困
			if energy > 50:
				modify_energy(-3)
		"evening":
			# 黄昏活跃期
			modify_energy(3 * mod.energy_mod)
			modify_mood(2)
		"night":
			# 夜晚应该休息
			if energy < 30:
				# 触发睡眠链
				start_chain("sleep_sequence")

# ============================================
# 七、数据持久化
# ============================================

func get_save_data() -> Dictionary:
	var data := {
		"mood": mood,
		"energy": energy,
		"affection": affection,
		"chaos": chaos,
		"curiosity": curiosity,
		"interaction_stats": interaction_stats,
		"behavior_weights": behavior_weights,
		"favorite_actions": favorite_actions,
		"disliked_actions": disliked_actions,
		"total_play_time": total_play_time,
	}
	# 亲密度养成数据(bond_system 经 meta 挂载)
	if has_meta("bond_data"):
		data["bond"] = get_meta("bond_data")
	return data

func load_save_data(data: Dictionary):
	mood = data.get("mood", 50.0)
	energy = data.get("energy", 80.0)
	affection = data.get("affection", 30.0)
	chaos = data.get("chaos", 20.0)
	curiosity = data.get("curiosity", 60.0)
	interaction_stats = data.get("interaction_stats", interaction_stats)
	behavior_weights = data.get("behavior_weights", behavior_weights)
	favorite_actions = data.get("favorite_actions", {})
	disliked_actions = data.get("disliked_actions", {})
	total_play_time = data.get("total_play_time", 0.0)
