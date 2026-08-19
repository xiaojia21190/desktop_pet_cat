class_name OfflineSettlement
extends RefCounted

## P9 离线正向结算：纯静态函数，不挂节点
## 你不在时猫在睡觉——回来补精力 + 按离线时长分档迎接（零惩罚）

const MIN_ELAPSED_SEC := 300          # 5 分钟内关开不结算
const HOUR_SEC := 3600
const ENERGY_PER_HOUR := 8.0
const ENERGY_CAP := 100.0
const TIER_1H := 3600
const TIER_1D := 86400
const TIER_3D := 3 * 86400

## personality → {tier: line}；未知性格走 tsundere
const LINES := {
	"tsundere": {
		1: "哼，可算回来了。",
		2: "一天不见，还记得我？",
		3: "以为你不回来了呢……",
	},
	"gentle": {
		1: "欢迎回来。",
		2: "好久不见，我好想你。",
		3: "等了你好久，还好你回来了。",
	},
	"playful": {
		1: "你回来啦！",
		2: "你终于回来啦你回来啦！",
		3: "呜哇你去哪了！想死我了！",
	},
}

static func settle(elapsed_sec: int, energy_now: float, personality: String) -> Dictionary:
	## 返回 {energy_gain: float, welcome_tier: int, line: String}
	if elapsed_sec < 0:
		elapsed_sec = 0
	if elapsed_sec < MIN_ELAPSED_SEC:
		return {"energy_gain": 0.0, "welcome_tier": 0, "line": ""}
	@warning_ignore("integer_division")
	var hours := int(elapsed_sec / HOUR_SEC)
	var raw_gain := float(hours) * ENERGY_PER_HOUR
	var room := maxf(ENERGY_CAP - energy_now, 0.0)
	var gain := minf(raw_gain, room)
	var tier := 0
	if elapsed_sec >= TIER_3D:
		tier = 3
	elif elapsed_sec >= TIER_1D:
		tier = 2
	elif elapsed_sec >= TIER_1H:
		tier = 1
	var persona := personality if LINES.has(personality) else "tsundere"
	var line := ""
	if tier > 0:
		line = String(LINES[persona].get(tier, ""))
	return {"energy_gain": gain, "welcome_tier": tier, "line": line}
