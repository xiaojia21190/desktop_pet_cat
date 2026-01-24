extends Node

# 键盘监听器 - 监听用户打字并触发猫咪互动

signal typing_detected(key_event)

var typing_timer = 0.0
const TYPING_COOLDOWN = 0.5  # 打字冷却时间

func _ready():
	set_process_input(true)

func _input(event):
	if event is InputEventKey and event.pressed:
		# 检测到打字
		if typing_timer <= 0:
			typing_detected.emit(event)
			typing_timer = TYPING_COOLDOWN

func _process(delta):
	if typing_timer > 0:
		typing_timer -= delta
