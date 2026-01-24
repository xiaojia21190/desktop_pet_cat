@tool
extends Resource
class_name CatTypeData

# 猫咪类型配置资源
# 使用 Resource 类型便于在编辑器中可视化编辑

@export var cat_id: String = ""
@export var display_name: String = ""
@export var sprite_path: String = ""
@export var description: String = ""

# 可选：猫咪特有的性格参数
@export_group("Personality")
@export_range(0, 100) var base_mood: float = 50.0
@export_range(0, 100) var base_energy: float = 80.0
@export_range(0, 100) var base_affection: float = 30.0
@export_range(0, 100) var base_curiosity: float = 60.0

# 可选：行为倾向
@export_group("Behavior Tendencies")
@export_range(0.5, 2.0) var activity_multiplier: float = 1.0
@export_range(0.5, 2.0) var tsundere_multiplier: float = 1.0

func to_dict() -> Dictionary:
	return {
		"name": display_name,
		"sprite_path": sprite_path,
		"description": description,
		"personality": {
			"mood": base_mood,
			"energy": base_energy,
			"affection": base_affection,
			"curiosity": base_curiosity
		},
		"behavior": {
			"activity_multiplier": activity_multiplier,
			"tsundere_multiplier": tsundere_multiplier
		}
	}

static func from_dict(id: String, data: Dictionary) -> CatTypeData:
	var res = CatTypeData.new()
	res.cat_id = id
	res.display_name = data.get("name", "")
	res.sprite_path = data.get("sprite_path", "")
	res.description = data.get("description", "")

	var personality = data.get("personality", {})
	res.base_mood = personality.get("mood", 50.0)
	res.base_energy = personality.get("energy", 80.0)
	res.base_affection = personality.get("affection", 30.0)
	res.base_curiosity = personality.get("curiosity", 60.0)

	var behavior = data.get("behavior", {})
	res.activity_multiplier = behavior.get("activity_multiplier", 1.0)
	res.tsundere_multiplier = behavior.get("tsundere_multiplier", 1.0)

	return res
