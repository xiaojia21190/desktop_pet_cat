@tool
extends Resource
class_name CatAnimationData

# 单个动画配置资源
# 使用 Resource 类型便于在编辑器中可视化编辑

@export var animation_name: String = ""
@export var row: int = 0
@export var frames: int = 6
@export var speed: float = 5.0
@export var loop: bool = true
@export var col_start: int = 0

func to_dict() -> Dictionary:
	return {
		"row": row,
		"frames": frames,
		"speed": speed,
		"loop": loop,
		"col_start": col_start
	}

static func from_dict(name: String, data: Dictionary) -> CatAnimationData:
	var res = CatAnimationData.new()
	res.animation_name = name
	res.row = data.get("row", 0)
	res.frames = data.get("frames", 6)
	res.speed = data.get("speed", 5.0)
	res.loop = data.get("loop", true)
	res.col_start = data.get("col_start", 0)
	return res
