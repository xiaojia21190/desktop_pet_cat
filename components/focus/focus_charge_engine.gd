class_name FocusChargeEngine
extends RefCounted

## 专注会话充能引擎：把真实工作信号翻译成 focus 增减。纯逻辑无状态。
##
## 玩法反转的核心：勤奋工作 → focus 上升；闲置 → 缓慢下降（约 8 分钟失败）；
## 猫的干扰事件不再大幅扣 focus（会话侧另有小系数处理）。

const TYPING_WEIGHT := 0.6       # 每次键入的工作分
const TYPING_CAP := 4.0          # 键入分封顶
const CLICK_WEIGHT := 0.3
const CLICK_CAP := 2.0
const FOCUS_ACTIVITY_BONUS := 1.5  # 专注类活动（coding 等）底薪
const CHARGE_MULTIPLIER := 1.2   # 工作分 → focus 增益倍率
const CHARGE_FLOOR := 0.8        # 达标时最低充能
const IDLE_DRAIN := -0.18        # 完全闲置每秒衰减（85 → 0 约 8 分钟）
const WORK_SCORE_THRESHOLD := 1.0
const MAX_DELTA := 10.0          # 单秒增减封顶

func compute_focus_delta(work_signal: Dictionary) -> float:
	## work_signal: {typing: int, clicks: int, focus_activity: bool}
	## 返回该秒的 focus 变化量
	var score := get_work_score(work_signal)
	var delta := 0.0
	if score >= WORK_SCORE_THRESHOLD:
		delta = maxf(score * CHARGE_MULTIPLIER, CHARGE_FLOOR)
	else:
		delta = IDLE_DRAIN
	return clampf(delta, -MAX_DELTA, MAX_DELTA)

func get_work_score(work_signal: Dictionary) -> float:
	var typing := float(work_signal.get("typing", 0))
	var clicks := float(work_signal.get("clicks", 0))
	var focus_activity := bool(work_signal.get("focus_activity", false))
	var score := minf(typing * TYPING_WEIGHT, TYPING_CAP)
	score += minf(clicks * CLICK_WEIGHT, CLICK_CAP)
	if focus_activity:
		score += FOCUS_ACTIVITY_BONUS
	return score
