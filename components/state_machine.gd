class_name StateMachine
extends Node

## 通用状态机
## 管理状态切换和状态更新

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state_name: StringName = &"Idle"

var current_state: Node  # 使用 Node 类型以兼容继承链
var states: Dictionary = {}

var _pending_state: StringName = &""
var _pending_msg: Dictionary = {}

## P10 动画锁查询（cat 挂载时注入；返回 true = 有一次性动作在播）
var anim_lock_provider: Callable

func _ready() -> void:
	# 注册所有 State 子节点
	for child in get_children():
		# 检查是否有 state_machine 属性（State 基类的特征）
		if "state_machine" in child:
			states[child.name] = child
			child.state_machine = self
			child.process_mode = Node.PROCESS_MODE_DISABLED

	# 启动初始状态
	if states.has(initial_state_name):
		current_state = states[initial_state_name]
		current_state.process_mode = Node.PROCESS_MODE_INHERIT
		current_state.enter()
	elif states.size() > 0:
		# 如果没有找到指定的初始状态，使用第一个
		current_state = states.values()[0]
		current_state.process_mode = Node.PROCESS_MODE_INHERIT
		current_state.enter()

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not states.has(state_name):
		push_error("状态 '%s' 不存在" % state_name)
		return

	# P10 锁排队：一次性动画播放中，非 urgent 切换排队等待
	if not bool(msg.get("urgent", false)) and _anim_locked():
		_pending_state = state_name
		_pending_msg = msg
		return

	var previous_state := current_state
	if previous_state:
		previous_state.exit()
		previous_state.process_mode = Node.PROCESS_MODE_DISABLED

	current_state = states[state_name]
	current_state.process_mode = Node.PROCESS_MODE_INHERIT
	current_state.enter(msg)

	if previous_state:
		state_changed.emit(previous_state.name, current_state.name)

func _anim_locked() -> bool:
	if anim_lock_provider.is_valid():
		return bool(anim_lock_provider.call())
	return false

func notify_anim_unlocked() -> void:
	## P10 动画锁解除（cat 监听 animation_finished 后调用）：执行排队的切换
	if _pending_state != &"" and states.has(_pending_state):
		var st := _pending_state
		var msg := _pending_msg
		_pending_state = &""
		_pending_msg = {}
		transition_to(st, msg)

func get_current_state_name() -> StringName:
	if current_state:
		return current_state.name
	return &""

func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.name == state_name
