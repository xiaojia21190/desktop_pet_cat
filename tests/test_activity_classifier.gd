extends Node

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 默认规则分类
	_assert_equal(ActivityClassifier.classify("Code.exe"), "coding", "vscode_coding")
	_assert_equal(ActivityClassifier.classify("godot"), "coding", "godot_coding")
	_assert_equal(ActivityClassifier.classify("chrome.exe"), "browsing", "chrome_browsing")
	_assert_equal(ActivityClassifier.classify("PotPlayerMini64.exe"), "video", "potplayer_video")
	_assert_equal(ActivityClassifier.classify("QQ.exe"), "social", "qq_social")
	_assert_equal(ActivityClassifier.classify("WeChat.exe"), "social", "wechat_social")
	_assert_equal(ActivityClassifier.classify("excel.exe"), "office", "excel_office")
	_assert_equal(ActivityClassifier.classify("totally_unknown_app"), "other", "unknown_other")

	# 大小写不敏感
	_assert_equal(ActivityClassifier.classify("CHROME.EXE"), "browsing", "case_insensitive")

	# 用户规则优先于默认规则
	var custom: Array[Dictionary] = [
		{"match": "mycompany", "activity": "coding"}
	]
	_assert_equal(ActivityClassifier.classify("MyCompanyIDE.exe", custom), "coding", "custom_rule_wins")
	_assert_equal(ActivityClassifier.classify("chrome.exe", custom), "browsing", "custom_not_break_default")

	# 默认规则可整体禁用（只留用户规则）
	_assert_equal(ActivityClassifier.classify("chrome.exe", custom, false), "other", "defaults_disabled")

	# 类别集合完整
	var cats := ActivityClassifier.CATEGORIES
	for expected in ["coding", "browsing", "video", "social", "game", "music", "reading", "office", "design", "other"]:
		_assert_true(cats.has(expected), "category_has_" + expected)

	# normalize_rules：非法项剔除、合法项保留
	var raw: Array = [
		{"match": "  studio3d ", "activity": "design"},
		{"match": "", "activity": "coding"},            # match 为空 → 剔除
		{"match": "foo", "activity": "not_a_category"}, # 类别非法 → 剔除
		"not_a_dict"                                    # 非字典 → 剔除
	]
	var normalized: Array[Dictionary] = ActivityClassifier.normalize_rules(raw)
	_assert_equal(normalized.size(), 1, "normalize_filters_invalid")
	_assert_equal(String(normalized[0].get("match")), "studio3d", "normalize_trims_match")

	_print_summary()
	get_tree().quit(1 if _failed > 0 else 0)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)

func _assert_equal(actual, expected, test_name: String) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	_failures.append("%s (actual=%s expected=%s)" % [test_name, str(actual), str(expected)])

func _print_summary() -> void:
	print("")
	print("========== activity_classifier tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
