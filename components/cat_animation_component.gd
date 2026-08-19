class_name CatAnimationComponent
extends Node

## 猫咪动画组件
## 优先加载预生成的 SpriteFrames .tres 资源（可在编辑器中编辑）
## 找不到 .tres 时回退到运行时生成

signal animation_finished(anim_name: String)
signal cat_type_changed(cat_type: String)

@export var animated_sprite_path: NodePath = ^"../AnimatedSprite2D"

var animated_sprite: AnimatedSprite2D
var current_cat_type: String = "orange_tabby"

const SPRITE_FRAMES_DIR := "res://resources/animations/"

## P10 一次性动作语义表（tres 的 loop 值不可信——pounce_attack 被错标 loop=1）
## 依据状态用法与帧语义人工核定；不在表内 = 循环动作
const ONESHOT_ACTIONS := {
	"eat": true, "pounce_attack": true, "pounce_ready": true, "pounce": true,
	"greet": true, "celebrate": true, "comfort": true, "dodge": true,
	"startled": true, "stretch": true, "yawn": true, "jump": true, "land": true,
	"retreat": true, "typing_attack": true, "blocking": true, "kneading": true,
	"head_pat_happy": true, "sneak_eat": true, "happy": true, "peek": true,
	"carry": true, "break_hint": true,
}

## P10 帧时长曲线：一次性动作首尾帧慢、中间帧快（8 帧观感更连贯）
const CURVE_FIRST_LAST := 1.6
const CURVE_MIDDLE := 0.7

var _locked: bool = false
var _locked_anim := ""

func _ready() -> void:
	animated_sprite = get_node_or_null(animated_sprite_path) as AnimatedSprite2D
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

func play(anim_name: String) -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	var target := anim_name
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.sprite_frames.has_animation("idle_stand"):
			target = "idle_stand"
		else:
			return
	if target != animated_sprite.animation or not animated_sprite.is_playing():
		pass  # 帧时长曲线由 tools/tune_anim_speeds.py 写入 tres（P10：API 无 set_frame_duration）
	animated_sprite.play(target)
	# P10 播放锁：一次性动作播完前锁（状态机查询）
	if ONESHOT_ACTIONS.has(target):
		_locked = true
		_locked_anim = target
	else:
		_locked = false
		_locked_anim = ""

func is_action_locked() -> bool:
	## P10：一次性动作播放中返回 true（状态机切换排队依据）
	return _locked

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

	# 优先加载预生成的 .tres
	var tres_path := SPRITE_FRAMES_DIR + current_cat_type + ".tres"
	if ResourceLoader.exists(tres_path):
		var sf := load(tres_path) as SpriteFrames
		if sf:
			animated_sprite.sprite_frames = sf
			_locked = false  # P10：品种切换是天然 urgent 场景，锁重置
			_locked_anim = ""
			animated_sprite.play("idle_stand")
			print("已加载猫咪(.tres): ", current_cat_type)
			return

	# 回退到运行时生成
	var generated := SpriteFramesGenerator.generate(current_cat_type)
	if generated:
		animated_sprite.sprite_frames = generated
		_locked = false
		_locked_anim = ""
		animated_sprite.play("idle_stand")
		print("已加载猫咪(运行时): ", current_cat_type)

func _on_animation_finished() -> void:
	# P10：一次性动作播完解锁（同动画匹配防误清）
	if _locked and animated_sprite.animation == _locked_anim:
		_locked = false
		_locked_anim = ""
	animation_finished.emit(animated_sprite.animation)

func get_current_animation() -> String:
	if animated_sprite:
		return animated_sprite.animation
	return ""

func is_playing() -> bool:
	if animated_sprite:
		return animated_sprite.is_playing()
	return false
