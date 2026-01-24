class_name StateMachine
extends Node

## 通用状态机
## 管理状态切换和状态更新

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state_name: StringName = &"Idle"

var current_state: Node  # 使用 Node 类型以兼容继承链
var states: Dictionary = {}

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

	var previous_state := current_state
	if previous_state:
		previous_state.exit()
		previous_state.process_mode = Node.PROCESS_MODE_DISABLED

	current_state = states[state_name]
	current_state.process_mode = Node.PROCESS_MODE_INHERIT
	current_state.enter(msg)

	if previous_state:
		state_changed.emit(previous_state.name, current_state.name)

func get_current_state_name() -> StringName:
	if current_state:
		return current_state.name
	return &""

func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.name == state_name
