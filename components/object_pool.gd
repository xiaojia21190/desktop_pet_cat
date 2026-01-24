class_name ObjectPool
extends Node

## 对象池
## 用于高效复用频繁创建/销毁的对象

signal instance_spawned(instance: Node)
signal instance_returned(instance: Node)

@export var pooled_scene: PackedScene
@export var initial_size: int = 5
@export var can_grow: bool = true
@export var max_size: int = 20

var _available: Array[Node] = []
var _in_use: Array[Node] = []

func _ready() -> void:
	_initialize_pool()

func _initialize_pool() -> void:
	for i in initial_size:
		_create_instance()

func _create_instance() -> Node:
	if not pooled_scene:
		push_error("ObjectPool: pooled_scene 未设置")
		return null

	var instance := pooled_scene.instantiate()
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	instance.visible = false
	add_child(instance)
	_available.append(instance)

	# 连接返回信号（如果存在）
	if instance.has_signal("returned_to_pool"):
		instance.returned_to_pool.connect(_return_to_pool.bind(instance))

	return instance

func get_instance() -> Node:
	var instance: Node

	if _available.is_empty():
		if can_grow and (_in_use.size() + _available.size()) < max_size:
			instance = _create_instance()
			if instance:
				_available.erase(instance)
		else:
			push_warning("ObjectPool: 池已耗尽且无法扩展")
			return null
	else:
		instance = _available.pop_back()

	if not instance:
		return null

	instance.process_mode = Node.PROCESS_MODE_INHERIT
	instance.visible = true
	_in_use.append(instance)

	if instance.has_method("on_spawn"):
		instance.on_spawn()

	instance_spawned.emit(instance)
	return instance

func return_instance(instance: Node) -> void:
	_return_to_pool(instance)

func _return_to_pool(instance: Node) -> void:
	if instance not in _in_use:
		return

	_in_use.erase(instance)

	if instance.has_method("on_despawn"):
		instance.on_despawn()

	instance.process_mode = Node.PROCESS_MODE_DISABLED
	instance.visible = false
	_available.append(instance)

	instance_returned.emit(instance)

func return_all() -> void:
	for instance in _in_use.duplicate():
		_return_to_pool(instance)

func get_available_count() -> int:
	return _available.size()

func get_in_use_count() -> int:
	return _in_use.size()

func get_total_count() -> int:
	return _available.size() + _in_use.size()
