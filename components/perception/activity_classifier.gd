class_name ActivityClassifier
extends RefCounted

## 前台应用活动分类：进程名 → 活动类别。纯函数，无状态。
## 隐私边界：只处理进程名，永不接触窗口标题。

const CATEGORIES := [
	"coding", "browsing", "video", "social", "game",
	"music", "reading", "office", "design", "other"
]

# 默认规则：按进程名（小写包含匹配）归类。用户规则优先。
const DEFAULT_RULES := [
	{"match": "code", "activity": "coding"},
	{"match": "godot", "activity": "coding"},
	{"match": "devenv", "activity": "coding"},
	{"match": "idea", "activity": "coding"},
	{"match": "pycharm", "activity": "coding"},
	{"match": "webstorm", "activity": "coding"},
	{"match": "neovide", "activity": "coding"},
	{"match": "terminal", "activity": "coding"},
	{"match": "powershell", "activity": "coding"},
	{"match": "cmd", "activity": "coding"},
	{"match": "windsurf", "activity": "coding"},
	{"match": "cursor", "activity": "coding"},

	{"match": "chrome", "activity": "browsing"},
	{"match": "msedge", "activity": "browsing"},
	{"match": "firefox", "activity": "browsing"},
	{"match": "opera", "activity": "browsing"},
	{"match": "vivaldi", "activity": "browsing"},

	{"match": "potplayer", "activity": "video"},
	{"match": "vlc", "activity": "video"},
	{"match": "mpv", "activity": "video"},
	{"match": "bilibili", "activity": "video"},
	{"match": "iqiyi", "activity": "video"},
	{"match": "mpc-hc", "activity": "video"},
	{"match": "movies", "activity": "video"},

	{"match": "qq", "activity": "social"},
	{"match": "wechat", "activity": "social"},
	{"match": "dingtalk", "activity": "social"},
	{"match": "telegram", "activity": "social"},
	{"match": "discord", "activity": "social"},
	{"match": "slack", "activity": "social"},

	{"match": "steam", "activity": "game"},
	{"match": "epicgames", "activity": "game"},
	{"match": "game", "activity": "game"},

	{"match": "spotify", "activity": "music"},
	{"match": "cloudmusic", "activity": "music"},
	{"match": "qqmusic", "activity": "music"},
	{"match": "kugoo", "activity": "music"},
	{"match": "foobar2000", "activity": "music"},

	{"match": "sumatrapdf", "activity": "reading"},
	{"match": "acrobat", "activity": "reading"},
	{"match": "foxit", "activity": "reading"},
	{"match": "calibre", "activity": "reading"},

	{"match": "excel", "activity": "office"},
	{"match": "winword", "activity": "office"},
	{"match": "powerpnt", "activity": "office"},
	{"match": "onenote", "activity": "office"},
	{"match": "outlook", "activity": "office"},
	{"match": "wps", "activity": "office"},

	{"match": "photoshop", "activity": "design"},
	{"match": "illustrator", "activity": "design"},
	{"match": "figma", "activity": "design"},
	{"match": "blender", "activity": "design"},
	{"match": "clipstudio", "activity": "design"}
]

static func classify(process_name: String, custom_rules: Array[Dictionary] = [], use_defaults: bool = true) -> String:
	var normalized := process_name.to_lower().strip_edges()
	if normalized.is_empty():
		return "other"

	for rule in custom_rules:
		var match_key := String(rule.get("match", "")).to_lower()
		var activity := String(rule.get("activity", "other"))
		if not match_key.is_empty() and normalized.contains(match_key):
			return activity

	if use_defaults:
		for rule in DEFAULT_RULES:
			var match_key := String(rule.get("match", ""))
			var activity := String(rule.get("activity", "other"))
			if normalized.contains(match_key):
				return activity

	return "other"

static func normalize_rules(raw_rules: Array) -> Array[Dictionary]:
	## 存档里的规则数组（无类型）→ 强类型规则数组；非法项剔除
	var normalized: Array[Dictionary] = []
	for raw in raw_rules:
		if not (raw is Dictionary):
			continue
		var match_key := String(raw.get("match", "")).strip_edges()
		var activity := String(raw.get("activity", "")).strip_edges()
		if match_key.is_empty() or not CATEGORIES.has(activity):
			continue
		normalized.append({"match": match_key, "activity": activity})
	return normalized
