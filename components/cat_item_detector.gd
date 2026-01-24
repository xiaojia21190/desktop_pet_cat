class_name CatItemDetector
extends Node

## 猫咪道具检测组件
## 检测附近道具并触发反应

signal item_detected(item: Node2D, item_type: ItemTypes.Type)
signal item_reaction(reaction: String, item: Node2D)

@export var detect_radius: float = 120.0
@export var check_interval: float = 0.3

# 道具反应概率
@export_group("Food Probabilities")
@export var food_ignore_chance: float = 0.5
@export var food_eat_chance: float = 0.3
@export var food_carry_chance: float = 0.2

@export_group("Wand Probabilities")
@export var wand_ignore_chance: float = 0.7
@export var wand_chase_chance: float = 0.3

var owner_node: Node2D
var _cached_items: Array[Node] = []
var _check_timer: float = 0.0
var _enabled: bool = true

func _ready() -> void:
	owner_node = get_parent() as Node2D

	# 监听道具组变化
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

func _process(delta: float) -> void:
	if not _enabled or not owner_node:
		return

	_check_timer += delta
	if _check_timer >= check_interval:
		_check_timer = 0.0
		_check_nearby_items()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func _on_node_added(node: Node) -> void:
	if node.is_in_group("items"):
		_cached_items.append(node)

func _on_node_removed(node: Node) -> void:
	_cached_items.erase(node)

func _check_nearby_items() -> void:
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
