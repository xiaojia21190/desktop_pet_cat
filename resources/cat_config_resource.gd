@tool
extends Resource
class_name CatConfigResource

# 猫咪配置主资源
# 包含所有猫咪类型和动画配置
# 可在编辑器中可视化编辑

@export var frame_size: Vector2 = Vector2(170, 139)
@export var columns: int = 8

@export_group("Cat Types")
@export var cat_types: Array[CatTypeData] = []

@export_group("Animations")
@export var animations: Array[CatAnimationData] = []

@export_group("State Animation Mapping")
@export var state_animation_map: Dictionary = {}

# 获取猫咪类型配置
func get_cat_type(cat_id: String) -> CatTypeData:
	for cat in cat_types:
		if cat.cat_id == cat_id:
			return cat
	return null

# 获取动画配置
func get_animation(anim_name: String) -> CatAnimationData:
	for anim in animations:
		if anim.animation_name == anim_name:
			return anim
	return null

# 获取状态对应的动画名称
func get_animation_for_state(state_name: String) -> String:
	if state_animation_map.has(state_name):
		var anims = state_animation_map[state_name]
		if anims is Array and anims.size() > 0:
			return anims[randi() % anims.size()]
	return "idle_stand"

# 获取所有猫咪ID
func get_all_cat_ids() -> Array:
	var ids = []
	for cat in cat_types:
		ids.append(cat.cat_id)
	return ids

# 转换为兼容旧代码的 Dictionary 格式
func to_legacy_format() -> Dictionary:
	var result = {
		"FRAME_SIZE": frame_size,
		"COLUMNS": columns,
		"CAT_TYPES": {},
		"ANIMATIONS": {},
		"STATE_ANIMATION_MAP": state_animation_map
	}

	for cat in cat_types:
		result["CAT_TYPES"][cat.cat_id] = cat.to_dict()

	for anim in animations:
		result["ANIMATIONS"][anim.animation_name] = anim.to_dict()

	return result

# 从旧格式加载
static func from_legacy_format(data: Dictionary) -> CatConfigResource:
	var res = CatConfigResource.new()
	res.frame_size = data.get("FRAME_SIZE", Vector2(170, 139))
	res.columns = data.get("COLUMNS", 8)

	var cat_types_dict = data.get("CAT_TYPES", {})
	for cat_id in cat_types_dict:
		res.cat_types.append(CatTypeData.from_dict(cat_id, cat_types_dict[cat_id]))

	var animations_dict = data.get("ANIMATIONS", {})
	for anim_name in animations_dict:
		res.animations.append(CatAnimationData.from_dict(anim_name, animations_dict[anim_name]))

	res.state_animation_map = data.get("STATE_ANIMATION_MAP", {})

	return res

# 创建默认配置
static func create_default() -> CatConfigResource:
	var res = CatConfigResource.new()
	res.frame_size = Vector2(170, 139)
	res.columns = 8

	# 添加默认猫咪类型
	var orange = CatTypeData.new()
	orange.cat_id = "orange_tabby"
	orange.display_name = "橘猫"
	orange.sprite_path = "res://assets/Orange Tabby.png"
	orange.description = "傲娇的橘猫，喜欢捣乱"
	res.cat_types.append(orange)

	var calico = CatTypeData.new()
	calico.cat_id = "calico"
	calico.display_name = "三花猫"
	calico.sprite_path = "res://assets/Calico.png"
	calico.description = "优雅的三花猫"
	res.cat_types.append(calico)

	var british = CatTypeData.new()
	british.cat_id = "british_blue"
	british.display_name = "英短蓝猫"
	british.sprite_path = "res://assets/British Shorthair Blue.png"
	british.description = "圆脸的英短蓝猫"
	res.cat_types.append(british)

	var tuxedo = CatTypeData.new()
	tuxedo.cat_id = "tuxedo"
	tuxedo.display_name = "燕尾服猫"
	tuxedo.sprite_path = "res://assets/Tuxedo Cat.png"
	tuxedo.description = "绅士的燕尾服猫"
	res.cat_types.append(tuxedo)

	# 添加默认动画
	var idle_stand = CatAnimationData.new()
	idle_stand.animation_name = "idle_stand"
	idle_stand.row = 0
	idle_stand.frames = 6
	idle_stand.speed = 5.0
	idle_stand.loop = true
	res.animations.append(idle_stand)

	var idle_active = CatAnimationData.new()
	idle_active.animation_name = "idle_active"
	idle_active.row = 1
	idle_active.frames = 6
	idle_active.speed = 7.0
	idle_active.loop = true
	res.animations.append(idle_active)

	# 状态映射
	res.state_animation_map = {
		"IDLE": ["idle_stand"],
		"WALKING": ["idle_active"],
		"WATCHING": ["idle_stand"],
		"POUNCING": ["idle_active"],
		"CHASING_MOUSE": ["idle_active"],
		"BLOCKING_MOUSE": ["idle_active"],
		"ROLLING": ["idle_active"],
		"TYPING_ATTACK": ["idle_active"],
		"TAIL_WAGGING": ["idle_active"],
		"DRINKING": ["idle_stand"],
		"EATING": ["idle_active"],
		"CARRYING": ["idle_active"],
		"IGNORING": ["idle_stand"],
	}

	return res
