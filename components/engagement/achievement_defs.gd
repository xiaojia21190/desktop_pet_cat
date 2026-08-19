class_name AchievementDefs
extends RefCounted

## P8 成就与周任务定义表（纯常量）：id → 定义
## 成就判定源 stat 键对应 lifetime_totals；need 为累计阈值

## 周任务：quest_id → {title, quest_id(计数的每日任务), target, reward}
const WEEKLY_QUESTS := {
	"week_focus": {"title": "专注搭档之路", "quest_id": "focus_session", "target": 3, "reward": 30.0},
	"week_stand": {"title": "起身活动周", "quest_id": "stand_up", "target": 5, "reward": 25.0},
	"week_interact": {"title": "每日一见", "quest_id": "interact_once", "target": 7, "reward": 25.0},
}

## 成就：id → {name, stat(累计键), need(阈值), reward, title(称号，空=无称号)}
const ACHIEVEMENTS := {
	"focus_10": {"name": "初入专注", "stat": "focus_session", "need": 10, "reward": 50.0, "title": "专注搭档"},
	"focus_50": {"name": "专注大师", "stat": "focus_session", "need": 50, "reward": 150.0, "title": "深度工作之魂"},
	"pet_100": {"name": "百次撸猫", "stat": "pet_count", "need": 100, "reward": 80.0, "title": "撸猫圣手"},
	"week_all": {"name": "完美一周", "stat": "week_all", "need": 1, "reward": 60.0, "title": "完美一周"},
	"checkin_7": {"name": "一周之约", "stat": "checkin_days", "need": 7, "reward": 40.0, "title": "一周之约"},
	"checkin_30": {"name": "月度挚友", "stat": "checkin_days", "need": 30, "reward": 150.0, "title": "月度挚友"},
	"interact_50": {"name": "破冰之交", "stat": "interact_total", "need": 50, "reward": 40.0, "title": "破冰之交"},
	"bond_lv5": {"name": "挚友认证", "stat": "bond_level", "need": 5, "reward": 100.0, "title": "挚友认证"},
}
