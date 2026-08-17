class_name CatItemDetector
extends Node

@warning_ignore("shadowed_global_identifier")
const ItemTypes = preload("res://item_types.gd")

## 猫咪道具检测组件
## 检测附近道具并触发反应；逗猫棒甩动时进入玩耍追逐

signal item_detected(item: Node2D, item_type: ItemTypes.Type)
signal item_reaction(reaction: String, item: Node2D)
signal wand_play_requested(item: Node2D)
signal wand_caught(item: Node2D)

@export var detect_radius: float = 120.0
@export var check_interval: float = 0.3
@export var wand_catch_distance: float = 60.0

# 道具反应概率
@export_group("Food Probabilities")
@export var food_ignore_chance: float = 0.5
@export var food_eat_chance: float = 0.3
@export var food_carry_chance: float = 0.2

@export_group("Wand Probabilities")
@export var wand_ignore_chance: float = 0.15
@export var wand_carry_chance: float = 0.85

var owner_node: Node2D
var _cached_items: Array[Node] = []
var _check_timer: float = 0.0
var _enabled: bool = true
var _playing_wand: Node2D = null
var _last_wand_signal_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	owner_node = get_parent() as Node2D

	# 监听道具组变化
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

func _process(delta: float) -> void:
	if not _enabled or not owner_node:
		return

	if is_instance_valid(_playing_wand):
		_update_wand_play()
		return

	_check_timer += delta
	if _check_timer >= check_interval:
		_check_timer = 0.0
		_check_nearby_items()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_playing_wand = null

func _on_node_added(node: Node) -> void:
	if node.is_in_group("items"):
		_register_item(node)

func _sync_items_from_group() -> void:
	_cached_items.clear()
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			_register_item(item)

func _register_item(item: Node) -> void:
	_cached_items.append(item)
	# 逗猫棒道具接入甩动信号
	if item.has_signal("wand_moved") and not item.wand_moved.is_connected(_on_wand_moved):
		item.wand_moved.connect(_on_wand_moved.bind(item))

func _on_node_removed(node: Node) -> void:
	_cached_items.erase(node)
	if _playing_wand == node:
		_playing_wand = null

func _check_nearby_items() -> void:
	# 增量同步 items 组（node_added 早于 _ready 的 add_to_group，信号可能漏掉）
	if _cached_items.size() != get_tree().get_nodes_in_group("items").size():
		_sync_items_from_group()

	var nearest_item: Node2D = null
	var nearest_dist_sq := detect_radius * detect_radius

	for item in _cached_items:
		if not is_instance_valid(item) or not item is Node2D:
			continue

		var dist_sq := owner_node.global_position.distance_squared_to(item.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_item = item

	if nearest_item:
		var item_type_str: String = nearest_item.get("item_type") if nearest_item.get("item_type") else ""
		var item_type := ItemTypes.from_string(item_type_str)
		item_detected.emit(nearest_item, item_type)
		_react_to_item(nearest_item, item_type)

func _react_to_item(item: Node2D, item_type: ItemTypes.Type) -> void:
	var rand := randf()

	match item_type:
		ItemTypes.Type.FOOD:
			if rand < food_ignore_chance:
				item_reaction.emit("ignore", item)
			elif rand < food_ignore_chance + food_eat_chance:
				item_reaction.emit("eat", item)
			else:
				item_reaction.emit("carry", item)

		ItemTypes.Type.WAND:
			if rand < wand_ignore_chance:
				item_reaction.emit("ignore", item)
			else:
				item_reaction.emit("carry", item)

		_:
			item_reaction.emit("ignore", item)

func _on_wand_moved(wand_pos: Vector2, wand: Node2D) -> void:
	if not _enabled or _playing_wand != null:
		return
	if not is_instance_valid(wand):
		return
	_last_wand_signal_pos = wand_pos
	_playing_wand = wand
	wand_play_requested.emit(wand)

func _update_wand_play() -> void:
	if not is_instance_valid(_playing_wand):
		_playing_wand = null
		return
	var wand: Node2D = _playing_wand
	# 猫追上逗猫棒 → 玩耍成功
	if owner_node.global_position.distance_to(wand.global_position) <= wand_catch_distance:
		var caught := wand
		_playing_wand = null
		wand_caught.emit(caught)
