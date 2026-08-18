extends CharacterBody2D

@warning_ignore("shadowed_global_identifier")
const CatStates = preload("res://cat_states.gd")
const BondSystemScript = preload("res://components/bond_system.gd")

## 桌面宠物猫主控制器
## 使用组件和状态机模式重构

signal typing_attack_started
signal cat_left_clicked(part: String, pos: Vector2)
signal bond_level_up(level: int, message: String)
signal bond_gained(amount: float)  # P5c：每次互动 bond 增量（气泡小提示数据源）

# 组件引用
@onready var state_machine: StateMachine = $StateMachine
@onready var input_component: CatInputComponent = $InputComponent
@onready var animation_component: CatAnimationComponent = $AnimationComponent
@onready var item_detector: CatItemDetector = $ItemDetector
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var live_overlay: Node2D = $LiveOverlay

# 行为系统
var behavior_system: CatBehaviorSystem
var bond_system: Node

# 状态驻留间隔(每次切换后随机 6-9s;存档 intensity 设置会覆盖此默认值)
@export var state_change_interval: float = 7.0
var _state_timer: float = 0.0
@export var block_trigger_distance: float = 180.0
@export var block_mouse_move_distance: float = 8.0
@export var block_check_interval: float = 0.2
@export var block_cooldown: float = 4.0
@export var block_chance_low: float = 0.05
@export var block_chance_mid: float = 0.08
@export var block_chance_high: float = 0.1
var _block_check_timer: float = 0.0
var _block_cooldown_timer: float = 0.0
var _last_block_mouse_pos: Vector2 = Vector2.ZERO

# 鼠标proximity互动
var _mouse_near_timer: float = 0.0
var _mouse_near_cooldown: float = 0.0
const MOUSE_NEAR_DISTANCE: float = 200.0
const MOUSE_NEAR_THRESHOLD: float = 2.0
const MOUSE_NEAR_COOLDOWN: float = 15.0

# 随机状态切换概率阈值（累积概率）
@export_group("State Probabilities")
@export var prob_idle: float = 0.15
@export var prob_walking: float = 0.15
@export var prob_watching: float = 0.10
@export var prob_pouncing: float = 0.10
@export var prob_chasing: float = 0.15
@export var prob_rolling: float = 0.20
@export var prob_tail_wag: float = 0.08
# 剩余为 Ignoring (0.07)

# 屏幕尺寸缓存
var screen_size: Vector2 = Vector2(1920, 1080)
var screen_center: Vector2 = Vector2(960, 540)

func _ready() -> void:
	randomize()
	_update_screen_size()
	_last_block_mouse_pos = get_global_mouse_position()
	_init_behavior_system()
	_connect_signals()
	_load_saved_data()

	# 监听窗口大小变化
	get_tree().root.size_changed.connect(_update_screen_size)

func _update_screen_size() -> void:
	screen_size = get_viewport_rect().size
	screen_center = screen_size / 2

func _init_behavior_system() -> void:
	behavior_system = CatBehaviorSystem.new()
	add_child(behavior_system)

	behavior_system.emotion_state_changed.connect(_on_emotion_state_changed)
	behavior_system.chain_step_changed.connect(_on_chain_step_changed)
	behavior_system.chain_completed.connect(_on_chain_completed)

	# 亲密度养成:只涨不跌的 bond 进度(与瞬时好感度分离)
	bond_system = BondSystemScript.new()
	bond_system.name = "BondSystem"
	add_child(bond_system)
	bond_system.bond_changed.connect(_on_bond_changed)
	bond_system.level_up.connect(_on_bond_level_up)

	# 实时反应层:眼神跟踪/眨眼/受惊/爱心(叠加在动画之上)
	if live_overlay:
		live_overlay.setup(animated_sprite, 0.55)  # 与 AnimatedSprite2D scale 一致
		live_overlay.bind_behavior(behavior_system)
		live_overlay.startled.connect(_on_live_startled)

func _connect_signals() -> void:
	# 输入组件信号
	if input_component:
		input_component.drag_started.connect(_on_drag_started)
		input_component.drag_ended.connect(_on_drag_ended)
		input_component.clicked.connect(_on_clicked)
		input_component.petting_started.connect(_on_petting_started)
		input_component.petting_tick.connect(_on_petting_tick)
		input_component.petting_ended.connect(_on_petting_ended)

	# 道具检测信号
	if item_detector:
		item_detector.item_reaction.connect(_on_item_reaction)
		if not item_detector.wand_play_requested.is_connected(_on_wand_play_requested):
			item_detector.wand_play_requested.connect(_on_wand_play_requested)

	# 状态机信号
	if state_machine:
		state_machine.state_changed.connect(_on_state_changed)

	# 键盘监听器
	var keyboard_listener := get_node_or_null("/root/Main/KeyboardListener")
	if keyboard_listener:
		keyboard_listener.typing_detected.connect(_on_typing_detected)

func _load_saved_data() -> void:
	var data := SaveManager.load_data()
	var cat_data: Dictionary = data.get("cat", {})
	var settings: Dictionary = data.get("settings", {})
	var behavior_data: Dictionary = data.get("behavior", {})

	# 加载缩放
	if cat_data.has("scale_factor") and input_component:
		input_component.set_scale_factor(cat_data["scale_factor"])

	# 加载猫咪类型
	if cat_data.has("cat_type") and animation_component:
		animation_component.switch_cat_type(cat_data["cat_type"])
	elif animation_component:
		animation_component.load_random_cat()

	# 加载活跃度设置
	if settings.has("intensity"):
		state_change_interval = SaveManager._intensity_to_interval(settings["intensity"])

	# 加载行为系统数据
	if behavior_system and not behavior_data.is_empty():
		behavior_system.load_save_data(behavior_data)

	# 加载亲密度养成数据
	if bond_system and behavior_data.has("bond"):
		bond_system.load_save_data(behavior_data["bond"])

func _process(delta: float) -> void:
	# 更新行为系统
	if behavior_system:
		behavior_system.update(delta)

	# 拖拽时暂停自主行为
	if input_component and input_component.is_dragging:
		return

	# 状态链控制时跳过
	if behavior_system and behavior_system.is_in_chain():
		return

	# 缓存本帧鼠标位置，供多处复用
	var mouse_pos := get_global_mouse_position()

	# 定时随机切换状态
	if _try_trigger_blocking(delta, mouse_pos):
		return

	if _try_proximity_interaction(delta, mouse_pos):
		return

	# 状态驻留:随机 6-9 秒,且等当前动画播完再切(避免动画被打断的生硬感)
	_state_timer += delta
	if _state_timer > state_change_interval:
		if _current_animation_finished():
			_state_timer = 0.0
			state_change_interval = randf_range(6.0, 9.0)
			_smart_state_change()

## 当前动画是否已播完(循环动画视为播完,随时可切)
func _current_animation_finished() -> bool:
	if not animated_sprite or not animated_sprite.is_playing():
		return true
	var frames := animated_sprite.sprite_frames
	if frames == null:
		return true
	# 循环动画不打断判定,非循环动画等到最后一帧
	if frames.get_animation_loop(animated_sprite.animation):
		return true
	return animated_sprite.frame >= frames.get_frame_count(animated_sprite.animation) - 1

func _smart_state_change() -> void:
	if not behavior_system:
		_random_state_change()
		return

	var time_mod := behavior_system.get_time_behavior_modifier()
	var activity_mod: float = time_mod.activity_mod

	# 有概率触发行为链
	if _try_trigger_chain(activity_mod):
		return

	var available_actions := ["idle_stand", "idle_sit", "walk", "watch", "lick",
		"daze", "kneading", "stretch", "yawn", "roll", "tail_wag",
		"chase_mouse", "pounce_mouse", "jump"]

	# 夜晚作息:大幅偏向打盹/蜷睡/哈欠,减少活跃行为
	if activity_mod < 0.7:
		available_actions = ["sleep_curl", "idle_lie", "daze", "yawn", "stretch", "kneading"]

	var selected := behavior_system.select_weighted_behavior(available_actions)

	match selected:
		"idle_stand", "idle_sit":
			state_machine.transition_to(CatStates.IDLE)
		"daze", "kneading", "idle_lie":
			state_machine.transition_to(CatStates.IDLE, {"animation": selected})
		"sleep_curl":
			state_machine.transition_to(CatStates.IDLE, {"animation": "sleep_curl"})
		"stretch", "yawn":
			# 醒来舒展/犯困:直接播动画(状态机没有对应状态)
			animation_component.play(selected)
		"jump":
			_jump_excited()
		"walk":
			state_machine.transition_to(CatStates.WALKING)
		"watch":
			state_machine.transition_to(CatStates.WATCHING)
		"lick":
			state_machine.transition_to(CatStates.LICKING)
		"roll":
			state_machine.transition_to(CatStates.ROLLING)
		"tail_wag":
			state_machine.transition_to(CatStates.TAIL_WAGGING)
		"chase_mouse":
			state_machine.transition_to(CatStates.CHASING)
		"pounce_mouse":
			state_machine.transition_to(CatStates.POUNCING)
		_:
			_random_state_change()

## 兴奋小跳:jump 起跳 + land 落地组合
func _jump_excited() -> void:
	animation_component.play("jump")
	await animated_sprite.animation_finished
	animation_component.play("land")


func _try_trigger_chain(activity_mod: float) -> bool:
	if not behavior_system or behavior_system.is_in_chain():
		return false

	var roll := randf()
	var energy_state := behavior_system.get_energy_state()
	var mood_state := behavior_system.get_mood_state()

	if activity_mod >= 0.7:
		if energy_state == CatBehaviorSystem.EnergyState.ENERGETIC:
			if roll < 0.05:
				behavior_system.start_chain("playful_burst")
				return true
			elif roll < 0.09:
				behavior_system.start_chain("pounce_sequence")
				return true
		if roll < 0.04:
			behavior_system.start_chain("curious_peek")
			return true
		elif roll < 0.07:
			behavior_system.start_chain("greeting_sequence")
			return true
		elif roll < 0.09:
			behavior_system.start_chain("startled_sequence")
			return true
		elif roll < 0.11:
			behavior_system.start_chain("grooming_sequence")
			return true
	else:
		if roll < 0.03:
			behavior_system.start_chain("sleep_sequence")
			return true
		elif roll < 0.05:
			behavior_system.start_chain("stretch_relax")
			return true
		elif roll < 0.07:
			behavior_system.start_chain("grooming_sequence")
			return true

	if mood_state == CatBehaviorSystem.MoodState.GRUMPY and roll < 0.03:
		behavior_system.start_chain("angry_sequence")
		return true

	return false

func _try_proximity_interaction(delta: float, mouse_pos: Vector2 = Vector2.ZERO) -> bool:
	_mouse_near_cooldown = maxf(_mouse_near_cooldown - delta, 0.0)
	if _mouse_near_cooldown > 0.0:
		return false
	if not behavior_system or behavior_system.is_in_chain():
		return false
	if not state_machine or not state_machine.is_in_state(CatStates.IDLE):
		return false

	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_global_mouse_position()
	var dist := global_position.distance_to(mouse_pos)

	if dist < MOUSE_NEAR_DISTANCE:
		_mouse_near_timer += delta
		if _mouse_near_timer >= MOUSE_NEAR_THRESHOLD:
			_mouse_near_timer = 0.0
			_mouse_near_cooldown = MOUSE_NEAR_COOLDOWN
			var roll := randf()
			if roll < 0.4:
				behavior_system.start_chain("curious_peek")
			elif roll < 0.7:
				behavior_system.start_chain("greeting_sequence")
			else:
				state_machine.transition_to(CatStates.WATCHING)
			return true
	else:
		_mouse_near_timer = 0.0

	return false

func _random_state_change() -> void:
	var rand := randf()
	var cumulative := 0.0

	cumulative += prob_idle
	if rand < cumulative:
		state_machine.transition_to(CatStates.IDLE)
		return

	cumulative += prob_walking
	if rand < cumulative:
		state_machine.transition_to(CatStates.WALKING)
		return

	cumulative += prob_watching
	if rand < cumulative:
		state_machine.transition_to(CatStates.WATCHING)
		return

	cumulative += prob_pouncing
	if rand < cumulative:
		state_machine.transition_to(CatStates.POUNCING)
		return

	cumulative += prob_chasing
	if rand < cumulative:
		state_machine.transition_to(CatStates.CHASING)
		return

	cumulative += prob_rolling
	if rand < cumulative:
		state_machine.transition_to(CatStates.ROLLING)
		return

	cumulative += prob_tail_wag
	if rand < cumulative:
		state_machine.transition_to(CatStates.TAIL_WAGGING)
		return

	state_machine.transition_to(CatStates.IGNORING)

func _try_trigger_blocking(delta: float, mouse_pos: Vector2 = Vector2.ZERO) -> bool:
	_block_check_timer += delta
	_block_cooldown_timer = maxf(_block_cooldown_timer - delta, 0.0)

	if _block_check_timer < block_check_interval:
		return false

	_block_check_timer = 0.0
	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_global_mouse_position()
	var moved_sq := mouse_pos.distance_squared_to(_last_block_mouse_pos)
	_last_block_mouse_pos = mouse_pos

	if _block_cooldown_timer > 0.0:
		return false
	if not state_machine or not state_machine.is_in_state(CatStates.IDLE):
		return false
	if moved_sq < block_mouse_move_distance * block_mouse_move_distance:
		return false
	if global_position.distance_squared_to(mouse_pos) > block_trigger_distance * block_trigger_distance:
		return false

	if randf() < _get_blocking_chance():
		state_machine.transition_to(CatStates.BLOCKING, {"target": mouse_pos})
		_block_cooldown_timer = block_cooldown
		_state_timer = 0.0
		return true
	return false

func _get_blocking_chance() -> float:
	var intensity := 1
	if SaveManager:
		intensity = SaveManager._interval_to_intensity(state_change_interval)
	match intensity:
		0:
			return block_chance_low
		2:
			return block_chance_high
		_:
			return block_chance_mid

# ============================================
# 信号处理
# ============================================

# —— 撸猫(按住不动 0.6s)——
func _on_petting_started(part: String) -> void:
	# 撸猫时暂停自主状态切换,猫享受地眯眼
	set_process(false)
	match part:
		"head":
			animation_component.play("head_pat_happy")
		"tail":
			animation_component.play("startled")  # 摸尾巴会炸毛
		_:
			animation_component.play("comfort")

func _on_petting_tick(part: String) -> void:
	# 每 0.5s:心情+2 好感+0.3(摸尾巴例外:反向)
	if behavior_system:
		if part == "tail":
			behavior_system.modify_mood(-1)
		else:
			behavior_system.modify_mood(2)
			behavior_system.modify_affection(0.3)
	if bond_system and part != "tail":
		bond_system.add_bond("pet", 0.6)
	# 舒服时小概率换个姿势
	if randf() < 0.25:
		animation_component.play("kneading" if randf() < 0.5 else "comfort")

func _on_petting_ended(pet_seconds: float) -> void:
	set_process(true)
	# 撸超过 3 秒:满足地伸懒腰
	if pet_seconds > 3.0 and behavior_system:
		behavior_system.modify_mood(3)
		animation_component.play("stretch")

func _on_drag_started() -> void:
	if item_detector:
		item_detector.set_enabled(false)

func _on_drag_ended() -> void:
	if item_detector:
		item_detector.set_enabled(true)
	_random_state_change()

func _on_clicked(part: String) -> void:
	cat_left_clicked.emit(part, global_position)

func _on_item_reaction(reaction: String, item: Node2D) -> void:
	# 正在玩耍/吃/叼时不响应
	if state_machine.is_in_state(CatStates.WAND_PLAYING) \
			or state_machine.is_in_state(CatStates.EATING) \
			or state_machine.is_in_state(CatStates.CARRYING):
		return

	match reaction:
		"ignore":
			state_machine.transition_to(CatStates.IGNORING)
		"eat":
			state_machine.transition_to(CatStates.EATING, {"item": item})
			_record_item_interaction("food_given")
		"carry":
			state_machine.transition_to(CatStates.CARRYING, {"item": item})
			_record_item_interaction("wand_given" if _is_wand(item) else "food_given")

func _on_wand_play_requested(wand: Node2D) -> void:
	# 吃/叼/拖拽中不进入玩耍
	if not state_machine:
		return
	if state_machine.is_in_state(CatStates.EATING) or state_machine.is_in_state(CatStates.CARRYING):
		return
	if input_component and input_component.is_dragging:
		return
	state_machine.transition_to(CatStates.WAND_PLAYING, {"item": wand})

func _record_item_interaction(interaction_type: String) -> void:
	if behavior_system:
		behavior_system.record_interaction(interaction_type)
	if bond_system:
		# P5c 饿猫喂食加成：energy < 40 时喂食 ×1.5（饿的时候喂更亲）
		var multiplier := 1.0
		if interaction_type == "food_given" and behavior_system and behavior_system.energy < 40.0:
			multiplier = 1.5
		var gained: float = bond_system.add_bond(interaction_type, -1.0, multiplier)
		if gained > 0.0:
			bond_gained.emit(gained)

func _is_wand(item: Node2D) -> bool:
	return String(item.get("item_type")) == "wand"

func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	# 只在特定状态切换时叫（不是每次都叫）
	var vocal_states: Array[StringName] = [
		CatStates.POUNCING, CatStates.CHASING, CatStates.BLOCKING,
		CatStates.TYPING_ATTACK, CatStates.EATING,
	]
	if to_state in vocal_states or (from_state == CatStates.IDLE and randf() < 0.15):
		AudioManager.play_cat_sound()

	if to_state == CatStates.TYPING_ATTACK:
		typing_attack_started.emit()

func _on_typing_detected(_key_event: InputEvent) -> void:
	if randf() < 0.3:
		state_machine.transition_to(CatStates.TYPING_ATTACK)

func _on_bond_changed(_bond: float, _level: int) -> void:
	# bond 变化时同步到行为存档(事件驱动,避免每帧写)
	if behavior_system and bond_system:
		behavior_system.set_meta("bond_data", bond_system.get_save_data())

func _on_bond_level_up(new_level: int, unlock: Dictionary) -> void:
	# 升级庆祝:解锁动画演示 + 气播提示(main 监听 cat_signal)
	var title := String(unlock.get("title", ""))
	var unlock_anim := String(unlock.get("unlock_anim", ""))
	var unlock_breed := String(unlock.get("unlock_breed", ""))
	if not unlock_anim.is_empty():
		animation_component.play(unlock_anim)
	var msg := "亲密度升到 Lv.%d「%s」!" % [new_level, title]
	if not unlock_breed.is_empty():
		msg += " 解锁新品种"
	bond_level_up.emit(new_level, msg)

func _on_live_startled() -> void:	# 鼠标快速晃动受惊:非占用状态时切受惊/闪避动画
	if not state_machine:
		return
	if state_machine.is_in_state(CatStates.IDLE) and randf() > 0.4:
		return  # 待机中 40% 概率才反应,避免过度触发
	if state_machine.is_in_state(CatStates.EATING) \
			or state_machine.is_in_state(CatStates.CARRYING) \
			or state_machine.is_in_state(CatStates.WAND_PLAYING):
		return
	if randf() < 0.6:
		animation_component.play("startled")
	else:
		animation_component.play("dodge")

func _on_emotion_state_changed(emotion_type: String, new_state: int) -> void:
	if emotion_type == "energy" and new_state == CatBehaviorSystem.EnergyState.TIRED:
		behavior_system.start_chain("sleep_sequence")

func _on_chain_step_changed(_chain_name: String, _step_index: int, state: String) -> void:
	play_animation(state)

func _on_chain_completed(_chain_name: String) -> void:
	state_machine.transition_to(CatStates.IDLE)

# ============================================
# 公共方法
# ============================================

func play_animation(anim_name: String) -> void:
	if animation_component:
		animation_component.play(anim_name)

func _trigger_tsundere_reaction(part: String) -> void:
	# 记录互动，情绪变化由 behavior_system.record_interaction 统一处理
	if behavior_system:
		behavior_system.record_interaction(part + "_touch")
	if bond_system:
		bond_system.add_bond(part + "_pat" if part == "head" else part + "_touch")

	var affection_state := CatBehaviorSystem.AffectionState.NEUTRAL
	if behavior_system:
		affection_state = behavior_system.get_affection_state()

	var rand := randf()

	# 仅处理视觉反馈（状态切换），情绪修改已在 record_interaction 中完成
	match part:
		"head":
			var dodge_chance := 0.6 if affection_state == CatBehaviorSystem.AffectionState.TSUNDERE else 0.3
			var happy_chance := 0.1 if affection_state == CatBehaviorSystem.AffectionState.TSUNDERE else 0.4

			if rand < dodge_chance:
				state_machine.transition_to(CatStates.IDLE)
				play_animation("head_pat_dodge")
			elif rand < dodge_chance + happy_chance:
				state_machine.transition_to(CatStates.IDLE)
				play_animation("head_pat_happy")
			else:
				# 其余情况:舒服地眯眼摇尾
				state_machine.transition_to(CatStates.TAIL_WAGGING)

		"body":
			if rand < 0.5:
				state_machine.transition_to(CatStates.ROLLING)
			elif rand < 0.8:
				state_machine.transition_to(CatStates.IGNORING)
			else:
				state_machine.transition_to(CatStates.WALKING)

		"tail":
			if rand < 0.25:
				state_machine.transition_to(CatStates.IDLE)
				play_animation("startled")
			elif rand < 0.7:
				state_machine.transition_to(CatStates.TAIL_WAGGING)
				play_animation("angry")
			elif rand < 0.9:
				state_machine.transition_to(CatStates.POUNCING)
			else:
				state_machine.transition_to(CatStates.WALKING)

# 兼容旧代码的属性
var scale_factor: float:
	get:
		if input_component:
			return input_component.scale_factor
		return 1.0
	set(value):
		if input_component:
			input_component.set_scale_factor(value)

var current_cat_type: String:
	get:
		if animation_component:
			return animation_component.current_cat_type
		return "orange_tabby"
