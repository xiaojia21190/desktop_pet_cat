class_name AnimationTiming
extends RefCounted

## P10 动作节奏表：一次性动作的调度最短时长（≥播完一遍），链调度用
## key → 倍率（相对 frames/speed 的一遍时长）；未列动作回退 1.0 倍

const OVERRIDES := {
	"eat": 1.6,        # 吃要有满足感（约 2.3s @8帧7fps）
	"pounce": 1.0,
	"pounce_attack": 1.0,
	"pounce_ready": 1.2,
	"greet": 1.2,
	"celebrate": 1.3,
	"comfort": 1.4,
	"stretch": 1.2,
	"yawn": 1.1,
	"watch_focus": 1.0,
}

static func min_duration(anim_name: String, frames: int, speed: float) -> float:
	var speed_safe := maxf(speed, 0.1)
	var base := float(frames) / speed_safe
	var mult := float(OVERRIDES.get(anim_name, 1.0))
	return base * mult
