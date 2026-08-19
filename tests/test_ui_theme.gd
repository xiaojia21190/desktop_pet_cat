extends Node

## P7 奶油风主题中心测试

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_palette_tokens()
	_test_stylebox_factories()
	_test_label_tint()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_palette_tokens() -> void:
	# 色板 token 值锁定（防手滑改坏全局色）
	_assert_true(UiThemeScript.BG == Color("FFF6E9"), "bg_cream")
	_assert_true(UiThemeScript.PRIMARY == Color("F5A623"), "primary_orange")
	_assert_true(UiThemeScript.TEXT == Color("5C4A32"), "text_warm_brown")
	_assert_equal(UiThemeScript.RADIUS_M, 14, "radius_m")
	_assert_equal(UiThemeScript.FONT_BODY, 14, "font_body")

func _test_stylebox_factories() -> void:
	# 工厂返回 StyleBoxFlat 且关键属性生效
	var panel: StyleBoxFlat = UiThemeScript.panel_style()
	_assert_true(panel is StyleBoxFlat, "panel_returns_flat")
	_assert_equal(panel.corner_radius_top_left, UiThemeScript.RADIUS_L, "panel_corner_l")
	var btn: StyleBoxFlat = UiThemeScript.btn_style()
	_assert_true(btn.bg_color == UiThemeScript.CARD, "btn_bg_card")
	var btn_hover: StyleBoxFlat = UiThemeScript.btn_style(true)
	_assert_true(btn_hover.bg_color == UiThemeScript.CARD_HOVER, "btn_hover_differs")
	var bubble: StyleBoxFlat = UiThemeScript.bubble_style()
	_assert_equal(bubble.border_width_left, 2, "bubble_border_2")
	var tab_active: StyleBoxFlat = UiThemeScript.tab_style(true)
	_assert_true(tab_active.bg_color == UiThemeScript.PRIMARY, "tab_active_primary")

func _test_label_tint() -> void:
	# tint_label 刷字色字号
	var label := Label.new()
	add_child(label)
	UiThemeScript.tint_label(label, "title")
	_assert_equal(label.get_theme_font_size("font_size"), UiThemeScript.FONT_TITLE, "tint_title_size")
	label.queue_free()

func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)

func _assert_equal(actual, expected, name: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s (expected=%s actual=%s)" % [name, str(expected), str(actual)])

func _print_summary() -> void:
	print("========== ui_theme tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
