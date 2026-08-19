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
	_test_settings_tabs()
	_test_settings_roundtrip()
	_test_radial_menu()
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

const SettingsPanelScript = preload("res://settings_panel.gd")

func _test_settings_tabs() -> void:
	# 骨架：6 页签构建、切换、对外接口存在
	var panel = SettingsPanelScript.new()
	add_child(panel)
	var tabs: Array = panel.get_tab_names()
	_assert_equal(tabs.size(), 6, "six_tabs")
	_assert_true(tabs.has("外观") and tabs.has("关于"), "tabs_named")
	panel.switch_tab(2)
	_assert_equal(panel.current_tab_index, 2, "switch_tab_works")
	_assert_true(panel.has_method("apply_settings"), "has_apply")
	_assert_true(panel.has_method("collect_settings"), "has_collect")
	_assert_true(panel.has_method("refresh_bond_ui"), "has_refresh_bond")
	panel.queue_free()

func _test_settings_roundtrip() -> void:
	# 新结构下 apply→collect 关键 12 键 roundtrip
	var panel = SettingsPanelScript.new()
	add_child(panel)
	var src := {
		"opacity": 0.8, "always_on_top": false, "timed_hide_option": 2,
		"sound_enabled": false, "bgm_enabled": true, "volume": 0.5,
		"intensity": 2, "smart_mode": false, "perception_enabled": true,
		"presence_level": 3, "quiet_hours_start": 22, "quiet_hours_end": 7,
		"personality": "gentle", "cat_type": "calico", "llm_enabled": true,
	}
	panel.apply_settings(src)
	var out: Dictionary = panel.collect_settings()
	_assert_true(is_equal_approx(float(out.get("opacity", 0.0)), 0.8), "rt_opacity")
	_assert_true(bool(out.get("always_on_top", true)) == false, "rt_on_top")
	_assert_equal(int(out.get("timed_hide_option", -1)), 2, "rt_timed_hide")
	_assert_equal(int(out.get("presence_level", -1)), 3, "rt_presence")
	_assert_equal(int(out.get("quiet_hours_start", -1)), 22, "rt_quiet_start")
	_assert_equal(String(out.get("personality", "")), "gentle", "rt_personality")
	_assert_equal(String(out.get("cat_type", "")), "calico", "rt_cat_type")
	_assert_true(bool(out.get("llm_enabled", false)), "rt_llm")
	panel.queue_free()

const QuickMenuScript = preload("res://quick_action_menu.gd")

func _test_radial_menu() -> void:
	var menu = QuickMenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	var actions: Array = menu.get_action_ids()
	_assert_equal(actions.size(), 6, "six_actions")
	_assert_true(not actions.has("settings"), "settings_removed")
	var fired: Array = []
	menu.action_selected.connect(func(a): fired.append(a))
	menu._emit_action("pet")
	_assert_equal(String(fired[0] if fired.size() > 0 else ""), "pet", "signal_carries_action")
	menu.queue_free()

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
