class_name CatAnimationComponent
extends Node

## 猫咪动画组件
## 管理动画播放和猫咪类型切换

signal animation_finished(anim_name: String)
signal cat_type_changed(cat_type: String)

@export var animated_sprite_path: NodePath = ^"../AnimatedSprite2D"

var animated_sprite: AnimatedSprite2D
var current_cat_type: String = "orange_tabby"

func _ready() -> void:
	animated_sprite = get_node_or_null(animated_sprite_path) as AnimatedSprite2D
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

func play(anim_name: String) -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)
	elif animated_sprite.sprite_frames.has_animation("idle_stand"):
		animated_sprite.play("idle_stand")

func play_state_animation(state_name: String) -> void:
	var anim_name := AnimationConfig.get_animation_for_state(state_name)
	play(anim_name)

func switch_cat_type(cat_type: String) -> void:
	if not AnimationConfig.CAT_TYPES.has(cat_type):
		push_warning("未知猫咪类型: " + cat_type)
		return

	current_cat_type = cat_type
	_apply_sprite_frames()
	cat_type_changed.emit(cat_type)

func load_random_cat() -> void:
	var cat_types := SpriteFramesGenerator.get_available_cat_types()
	var random_type: String = cat_types[randi() % cat_types.size()]
	switch_cat_type(random_type)

func _apply_sprite_frames() -> void:
	if not animated_sprite:
		return

	var sprite_frames := SpriteFramesGenerator.generate(current_cat_type)
	if sprite_frames:
		animated_sprite.sprite_frames = sprite_frames
		animated_sprite.play("idle_stand")
		print("已加载猫咪: ", AnimationConfig.CAT_TYPES[current_cat_type].name)

func _on_animation_finished() -> void:
	animation_finished.emit(animated_sprite.animation)

func get_current_animation() -> String:
	if animated_sprite:
		return animated_sprite.animation
	return ""

func is_playing() -> bool:
	if animated_sprite:
		return animated_sprite.is_playing()
	return false
