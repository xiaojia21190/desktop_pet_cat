class_name FirstGuideController
extends Node

## 首次引导状态机（非弹窗）：stage 0=未引导 1=引导摸摸 2=引导道具 3=完成
## 由 main 挂载；stage1 启动 30 秒后猫说话邀请摸摸；互动事件经 notify_interaction 喂入

signal guide_stage_changed(stage: int, message: String)

const STEP1_DELAY_SEC := 30.0
const STEP2_TIMEOUT_SEC := 600.0

var stage: int = 0
var _step2_deadline_unix: int = 0
var _elapsed: float = 0.0
var _step1_fired: bool = false

func load_from_save(done: bool) -> void:
	stage = 3 if done else 0

func is_done() -> bool:
	return stage >= 3

func start() -> void:
	if is_done():
		return
	if stage == 0:
		stage = 1
		_elapsed = 0.0
		_step1_fired = false
		guide_stage_changed.emit(stage, "")

func tick(delta: float = 0.0) -> void:
	if stage == 1 and not _step1_fired:
		_elapsed += delta
		if _elapsed >= STEP1_DELAY_SEC:
			_step1_fired = true
			guide_stage_changed.emit(1, "摸摸我吧")
	elif stage == 2:
		if _step2_deadline_unix > 0 and Time.get_unix_time_from_system() > _step2_deadline_unix:
			stage = 3
			guide_stage_changed.emit(3, "")

func notify_interaction(kind: String) -> void:
	if stage == 1 and kind in ["pet", "food", "wand"]:
		stage = 2
		_step2_deadline_unix = int(Time.get_unix_time_from_system() + STEP2_TIMEOUT_SEC)
		guide_stage_changed.emit(2, "想玩的话，点我有惊喜")
	elif stage == 2 and kind in ["food", "wand", "yarn", "box"]:
		stage = 3
		guide_stage_changed.emit(3, "")
