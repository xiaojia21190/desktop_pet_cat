class_name CatStateBase
extends State

## 猫咪状态基类
## 提供猫咪状态共用的功能

var cat: Node2D  # 猫咪主节点引用

func _ready() -> void:
	# 使用 owner 获取猫咪主节点（需要在场景中正确设置 owner）
	# 如果 owner 未设置，回退到通过父节点查找
	if owner and owner is Node2D:
		cat = owner as Node2D
	else:
		var sm := get_parent()
		if sm:
			cat = sm.get_parent() as Node2D

## 播放动画
func play_animation(anim_name: String) -> void:
	if cat and cat.has_method("play_animation"):
		cat.play_animation(anim_name)

## 获取鼠标位置
func get_mouse_position() -> Vector2:
	if cat:
		return cat.get_global_mouse_position()
	return Vector2.ZERO

## 获取屏幕尺寸
func get_screen_size() -> Vector2:
	if cat:
		return cat.get_viewport_rect().size
	return Vector2(1920, 1080)

## 切换到另一个状态
func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	state_machine.transition_to(state_name, msg)
