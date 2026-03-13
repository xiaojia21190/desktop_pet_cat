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

	# 添加默认动画（与 sprite_manifest 的 key 对齐，便于编辑器识别）
	var default_animations: Array[Dictionary] = [
		{"name": "idle_stand", "row": 0, "frames": 6, "speed": 5.0, "loop": true},
		{"name": "idle_active", "row": 1, "frames": 6, "speed": 7.0, "loop": true},
		{"name": "idle_sit", "row": 1, "frames": 6, "speed": 5.0, "loop": true},
		{"name": "idle_lie", "row": 2, "frames": 6, "speed": 4.0, "loop": true},
		{"name": "sleep_curl", "row": 3, "frames": 4, "speed": 3.0, "loop": true},
		{"name": "stretch", "row": 4, "frames": 6, "speed": 6.0, "loop": false},
		{"name": "yawn", "row": 5, "frames": 6, "speed": 6.0, "loop": false},
		{"name": "walk", "row": 0, "frames": 8, "speed": 8.0, "loop": true},
		{"name": "trot", "row": 1, "frames": 6, "speed": 9.0, "loop": true},
		{"name": "run", "row": 2, "frames": 6, "speed": 11.0, "loop": true},
		{"name": "jump", "row": 3, "frames": 4, "speed": 8.0, "loop": false},
		{"name": "land", "row": 4, "frames": 4, "speed": 8.0, "loop": false},
		{"name": "retreat", "row": 5, "frames": 6, "speed": 8.0, "loop": false},
		{"name": "watch_focus", "row": 0, "frames": 4, "speed": 6.0, "loop": true},
		{"name": "pounce_ready", "row": 1, "frames": 4, "speed": 8.0, "loop": true},
		{"name": "pounce_attack", "row": 2, "frames": 4, "speed": 10.0, "loop": false},
		{"name": "dodge", "row": 3, "frames": 4, "speed": 10.0, "loop": false},
		{"name": "startled", "row": 4, "frames": 4, "speed": 8.0, "loop": false},
		{"name": "lick_groom", "row": 5, "frames": 6, "speed": 7.0, "loop": true},
		{"name": "tail_wag", "row": 1, "frames": 6, "speed": 8.0, "loop": true},
		{"name": "typing_attack", "row": 2, "frames": 6, "speed": 10.0, "loop": true},
		{"name": "blocking", "row": 3, "frames": 6, "speed": 8.0, "loop": true},
		{"name": "chasing", "row": 0, "frames": 6, "speed": 10.0, "loop": true},
		{"name": "rolling", "row": 4, "frames": 6, "speed": 9.0, "loop": false},
		{"name": "eat", "row": 2, "frames": 6, "speed": 7.0, "loop": true},
		{"name": "carry", "row": 2, "frames": 6, "speed": 7.0, "loop": true},
		{"name": "greet", "row": 1, "frames": 6, "speed": 8.0, "loop": false},
		{"name": "celebrate", "row": 4, "frames": 6, "speed": 9.0, "loop": false},
		{"name": "comfort", "row": 5, "frames": 6, "speed": 6.0, "loop": false},
		{"name": "break_hint", "row": 5, "frames": 6, "speed": 6.0, "loop": false},
		{"name": "head_pat_happy", "row": 1, "frames": 6, "speed": 8.0, "loop": false},
		{"name": "head_pat_dodge", "row": 3, "frames": 4, "speed": 9.0, "loop": false},
		{"name": "angry", "row": 4, "frames": 4, "speed": 8.0, "loop": false},
		{"name": "daze", "row": 5, "frames": 4, "speed": 4.0, "loop": true},
		{"name": "watch", "row": 0, "frames": 4, "speed": 6.0, "loop": true},
		{"name": "pounce", "row": 2, "frames": 4, "speed": 10.0, "loop": false},
		{"name": "sleep", "row": 3, "frames": 4, "speed": 3.0, "loop": true},
		{"name": "sneak_eat", "row": 2, "frames": 6, "speed": 7.0, "loop": false},
		{"name": "lick", "row": 5, "frames": 6, "speed": 7.0, "loop": false},
		{"name": "happy", "row": 4, "frames": 6, "speed": 9.0, "loop": false},
		{"name": "peek", "row": 0, "frames": 4, "speed": 6.0, "loop": true},
		{"name": "walk_away", "row": 5, "frames": 6, "speed": 8.0, "loop": false},
		{"name": "ignore", "row": 5, "frames": 4, "speed": 4.0, "loop": true},
		{"name": "kneading", "row": 1, "frames": 6, "speed": 6.0, "loop": true}
	]

	for anim_cfg in default_animations:
		var anim := CatAnimationData.new()
		anim.animation_name = String(anim_cfg.get("name", ""))
		anim.row = int(anim_cfg.get("row", 0))
		anim.frames = int(anim_cfg.get("frames", 1))
		anim.speed = float(anim_cfg.get("speed", 5.0))
		anim.loop = bool(anim_cfg.get("loop", true))
		anim.col_start = int(anim_cfg.get("col_start", 0))
		res.animations.append(anim)

	# 状态映射（新旧 key 并存）
	res.state_animation_map = {
		"IDLE": ["idle_stand", "idle_sit", "idle_lie"],
		"WALKING": ["walk"],
		"WATCHING": ["watch_focus"],
		"POUNCING": ["pounce_attack"],
		"CHASING": ["chasing"],
		"BLOCKING": ["blocking"],
		"ROLLING": ["rolling"],
		"TYPING_ATTACK": ["typing_attack"],
		"TAIL_WAGGING": ["tail_wag"],
		"EATING": ["eat"],
		"CARRYING": ["carry"],
		"IGNORING": ["retreat", "idle_lie"],
		"LICKING": ["lick_groom"],
		"SLEEP_CURL": ["sleep_curl"],
		"GREET": ["greet"],
		"CELEBRATE": ["celebrate"],
		"COMFORT": ["comfort"],
		"BREAK_HINT": ["break_hint"],

		"CHASING_MOUSE": ["chasing"],
		"BLOCKING_MOUSE": ["blocking"],
		"DRINKING": ["idle_lie"],

		"watch": ["watch_focus"],
		"pounce_ready": ["pounce_ready"],
		"pounce": ["pounce_attack"],
		"yawn": ["yawn"],
		"idle_lie": ["idle_lie"],
		"sleep": ["sleep_curl"],
		"sneak_eat": ["sneak_eat"],
		"eat": ["eat"],
		"lick": ["lick_groom"],
		"happy": ["celebrate"],
		"startled": ["startled"],
		"run": ["run"],
		"peek": ["peek"],
		"trot": ["trot"],
		"tail_wag": ["tail_wag"],
		"angry": ["angry"],
		"walk_away": ["walk_away"],
		"ignore": ["retreat"]
	}

	return res
