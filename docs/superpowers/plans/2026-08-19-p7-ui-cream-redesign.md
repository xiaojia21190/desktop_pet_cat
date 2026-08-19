# P7 奶油风 UI 重做 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 全部 UI 推倒重做为统一软萌奶油风：UiTheme 主题中心 + 设置面板侧边页签重构 + 快捷菜单弧形轮盘 + 气泡换装 + 聚合抽屉 + HUD 换装，删除 aurora 素材与两个冗余组件。

**Architecture:** 新建 `UiTheme`（Design Token + StyleBoxFlat 工厂）作为唯一视觉来源；7 个 UI 组件全部重写为读主题的代码绘制控件；对外信号与函数签名零变化（main 只动 3 处）；存档键零变化。

**Tech Stack:** Godot 4.7 / GDScript（StyleBoxFlat/Theme override 代码绘制）；测试 headless tscn 断言式；端到端 Godot MCP。

**设计文档:** `docs/superpowers/specs/2026-08-19-p7-ui-cream-redesign.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 既有 12 套测试零 UI 断言依赖——P7 改 UI 后跑通即回归；新增第 13 套 `test_ui_theme`
- **已核实的代码事实（写码前不要再猜）**：
  - `typing_effect_overlay` 是**打字攻击特效**（main.gd:388 `_start_typing_effects` → `start_effect(duration, cat)`），删组件须连删 main.gd 的 `_start_typing_effects` + `_get_typing_attack_duration` + `_on_keyboard_typing_for_smart` 里对它的调用 + main.tscn 的 TypingEffectOverlay 节点（ext_resource id="4"）
  - `save_manager_panel` 由 settings_panel.gd:139 内部实例化弹出（main 不挂载）；含导出/导入/重置 + FileDialog + ConfirmationDialog
  - aurora 引用面：`settings_panel.tscn`（32 处，整个文件重写即消）、`hover_panel.gd`（6）、`quick_action_menu.gd`（4）、`focus_hud.gd`（3）、`smart_line_bubble.gd`（1）——五个文件全改完后才能删目录
  - 猫大小 UI **现在不存在**（scale_factor 有完整存档链路 save_manager.gd:21/74/132/247/386 但无控件）——设计规格「外观页：猫大小」是新增，需补 UI + collect 链
  - 设置面板尺寸常量在 main.gd:41-42（`SETTINGS_PANEL_WIDTH := 560.0 / HEIGHT := 900.0`）——新面板 720×560 需同步改
  - `collect_settings()` 返回 22 键（settings_panel.gd:497-527）——重构后必须保持同键集
  - main.gd 面板调用面：`settings_panel.visible` 切换（488/744）、`set_timed_hide_option`（318）、`refresh_bond_ui`（161/169）、尺寸定位（177-178）
  - hover_panel 现有信号 `items_requested` / `settings_requested`（main.gd:101-102 连接）；穿透管理器读 `hover_panel_component.is_out` 与 `.panel`（main.gd:227-231）——新抽屉必须保留这两个属性
  - 托盘 `toggle_focus_session_requested` 信号已存在（tray_controller.gd:8）——抽屉的专注按钮可直接复用 main 现有处理函数
  - 图标资源在 `assets/items/`（icon_pet/icon_wand/icon_food/yarn/box/icon_leash）已存在且不属 aurora，可继续用

## 文件结构总览

- Task 1 — UiTheme 主题中心（token + 工厂函数）+ 测试
- Task 2 — 设置面板骨架：侧边页签容器 + 6 页切换 + 测试
- Task 3 — 外观页 + 声音页（含新增猫大小滑条）
- Task 4 — 猫性格页 + 智能页（品种锁/LLM/静音时段/档位）
- Task 5 — 任务·亲密度页 + 关于页（含存档管理四功能承接）
- Task 6 — 快捷菜单弧形轮盘
- Task 7 — 气泡换装 + 聚合抽屉（hover_panel 重写）
- Task 8 — HUD 换装 + 托盘顺序 + main 接线收尾（删 typing/save_panel 引用/面板尺寸）
- Task 9 — 删 aurora 目录 + 全量回归 + MCP 端到端验收 + 文档收尾

---

### Task 1: UiTheme 主题中心

**Files:**
- Create: `components/ui/ui_theme.gd`
- Create: `tests/test_ui_theme.gd` + `tests/test_ui_theme.tscn`

- [ ] **Step 1: 写失败测试 tests/test_ui_theme.gd**

```gdscript
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
	_assert_true(label.add_theme_color_override != null, "tint_no_crash")
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
```

- [ ] **Step 2: 创建 tests/test_ui_theme.tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_ui_theme.gd" id="1"]

[node name="UiThemeTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: FAIL（ui_theme.gd 不存在，Parse Error）

- [ ] **Step 4: 实现 components/ui/ui_theme.gd**

```gdscript
class_name UiTheme
extends RefCounted

## P7 奶油风主题中心：全部 UI 唯一的视觉来源（色板/几何/字号 + StyleBoxFlat 工厂）
## 用法：UiTheme.panel_style() 返回新实例，控件 add_theme_stylebox_override 即用

# —— 色板 ——
const BG := Color("FFF6E9")            # 面板底：奶油白
const SURFACE := Color("FFFDF7")       # 卡片面
const CARD := Color("FFF0D9")          # 强调卡片
const CARD_HOVER := Color("FFE7BE")    # 卡片 hover
const PRIMARY := Color("F5A623")       # 主色：暖橙
const PRIMARY_HOVER := Color("E8940F") # 主色 hover
const TEXT := Color("5C4A32")          # 主文字：暖棕
const TEXT_DIM := Color("A08B70")      # 次文字
const SUCCESS := Color("7FB86A")
const DANGER := Color("E07856")
const PINK := Color("F7B8C4")          # 肉垫粉点缀
const SHADOW := Color(0.36, 0.29, 0.20, 0.15)  # 暖棕阴影

# —— 几何 ——
const RADIUS_S := 8
const RADIUS_M := 14
const RADIUS_L := 22
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24

# —— 字号 ——
const FONT_TITLE := 20
const FONT_SECTION := 16
const FONT_BODY := 14
const FONT_CAPTION := 12

# —— 面板/卡片 ——
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(RADIUS_L)
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.set_content_margin_all(SPACE_M)
	return sb

static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(RADIUS_M)
	sb.set_content_margin_all(SPACE_S)
	return sb

# —— 按钮 ——
static func btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_HOVER if hover else CARD
	sb.set_corner_radius_all(RADIUS_M)
	sb.border_color = PINK if hover else TEXT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

static func btn_primary_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY_HOVER if hover else PRIMARY
	sb.set_corner_radius_all(RADIUS_M)
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

# —— 输入控件 ——
static func line_style(focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(RADIUS_S)
	sb.border_color = PRIMARY if focused else TEXT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = SPACE_S
	sb.content_margin_right = SPACE_S
	return sb

static func check_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY if on else SURFACE
	sb.set_corner_radius_all(RADIUS_S)
	sb.border_color = TEXT_DIM
	sb.set_border_width_all(1)
	sb.set_content_margin_all(SPACE_XS)
	return sb

static func slider_track_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

static func slider_fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# —— 气泡 ——
static func bubble_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(16)
	sb.border_color = TEXT
	sb.set_border_width_all(2)
	sb.shadow_color = SHADOW
	sb.shadow_size = 4
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

# —— 页签 ——
static func tab_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY if active else Color.TRANSPARENT
	sb.set_corner_radius_all(RADIUS_M)
	if active:
		sb.content_margin_left = SPACE_S
		sb.content_margin_right = SPACE_S
		sb.content_margin_top = SPACE_XS
		sb.content_margin_bottom = SPACE_XS
	return sb

# —— 文字 ——
static func tint_label(label: Label, role: String) -> void:
	match role:
		"title":
			label.add_theme_font_size_override("font_size", FONT_TITLE)
			label.add_theme_color_override("font_color", TEXT)
		"section":
			label.add_theme_font_size_override("font_size", FONT_SECTION)
			label.add_theme_color_override("font_color", PRIMARY)
		"caption":
			label.add_theme_font_size_override("font_size", FONT_CAPTION)
			label.add_theme_color_override("font_color", TEXT_DIM)
		_:
			label.add_theme_font_size_override("font_size", FONT_BODY)
			label.add_theme_color_override("font_color", TEXT)
```

- [ ] **Step 5: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: `passed: 14  failed: 0`（5+8+1）

- [ ] **Step 6: Commit**

```bash
git add components/ui/ui_theme.gd tests/test_ui_theme.gd tests/test_ui_theme.tscn tests/test_ui_theme.gd.uid 2>/dev/null || git add components/ui/ui_theme.gd tests/test_ui_theme.gd tests/test_ui_theme.tscn
git commit -m "feat: 奶油风主题中心UiTheme"
```

---

### Task 2: 设置面板骨架——侧边页签容器

**Files:**
- Rewrite: `settings_panel.gd`（全删重写为骨架 + 两页占位）
- Rewrite: `settings_panel.tscn`（只留根节点）
- Test: `tests/test_ui_theme.gd`（追加）

- [ ] **Step 1: 追加失败测试（_run 追加 `_test_settings_tabs()`）**

```gdscript
const SettingsPanelScript = preload("res://settings_panel.gd")

func _test_settings_tabs() -> void:
	# 骨架：6 页签构建、切换、对外接口存在
	var panel = SettingsPanelScript.new()
	add_child(panel)
	var tabs: Array = panel.get_tab_names()
	_assert_equal(tabs.size(), 6, "six_tabs")
	_assert_true(tabs.has("外观") and tabs.has("关于"), "tabs_named")
	# 切换页签 → 当前页索引变化
	panel.switch_tab(2)
	_assert_equal(panel.current_tab_index, 2, "switch_tab_works")
	# 对外接口（main 依赖的三个方法 + SaveManager collect 链）
	_assert_true(panel.has_method("apply_settings"), "has_apply")
	_assert_true(panel.has_method("collect_settings"), "has_collect")
	_assert_true(panel.has_method("refresh_bond_ui"), "has_refresh_bond")
	panel.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: FAIL（get_tab_names 不存在）

- [ ] **Step 3: 重写 settings_panel.tscn（只留根节点）**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://settings_panel.gd" id="1"]

[node name="SettingsPanel" type="Panel"]
script = ExtResource("1")
```

- [ ] **Step 4: 重写 settings_panel.gd 骨架**

```gdscript
extends Panel

## P7 设置面板：侧边页签 + 内容区，全部代码构建（奶油风 UiTheme）
## 对外接口不变：apply_settings / collect_settings / refresh_bond_ui /
## refresh_quest_ui / set_timed_hide_option / refresh_breed_locks

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const TAB_NAMES: Array[String] = ["外观", "声音", "猫性格", "智能", "任务·亲密度", "关于"]

var current_tab_index: int = 0
var _tab_buttons: Array = []
var _tab_column: VBoxContainer
var _content_area: ScrollContainer
var _pages: Dictionary = {}          # 页签名 → VBoxContainer
var _status_label: Label

# —— 各页控件引用（Task 3-5 逐页填充）——
var opacity_slider: HSlider
var cat_scale_slider: HSlider
var timed_hide_option: OptionButton
var timed_hide_remaining_label: Label
var timed_hide_update_timer: Timer
var always_on_top_check: CheckBox
var auto_start_check: CheckBox
var sound_check: CheckBox
var bgm_check: CheckBox
var volume_slider: HSlider
var cat_breed_option: OptionButton
var personality_option: OptionButton
var intensity_option: OptionButton
var smart_mode_check: CheckBox
var perception_check: CheckBox
var perception_default_rules_check: CheckBox
var presence_level_option: OptionButton
var quiet_start_spin: SpinBox
var quiet_end_spin: SpinBox
var llm_enabled_check: CheckBox
var llm_endpoint_input: LineEdit
var llm_model_input: LineEdit
var llm_api_key_input: LineEdit
var llm_api_env_input: LineEdit
var focus_duration_option: OptionButton
var close_button: Button

const CAT_BREED_IDS: Array[String] = ["orange_tabby", "calico", "british_blue", "tuxedo"]
const CAT_BREED_NAMES: Array[String] = ["橘猫", "三花猫", "蓝猫", "燕尾服猫"]
const DEFAULT_LLM_ENDPOINT := "https://api.openai.com/v1/chat/completions"

func _ready() -> void:
	custom_minimum_size = Vector2(720, 560)
	add_theme_stylebox_override("panel", UiThemeScript.panel_style())
	_build_layout()

func _build_layout() -> void:
	# 标题栏
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 12
	root.offset_bottom = -12
	add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := Label.new()
	title.text = "🐾 设置"
	UiThemeScript.tint_label(title, "title")
	title_row.add_child(title)
	title_row.add_child(_spacer())
	close_button = Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = Vector2(36, 36)
	close_button.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
	close_button.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
	close_button.add_theme_color_override("font_color", UiThemeScript.TEXT)
	close_button.pressed.connect(_on_close_pressed)
	title_row.add_child(close_button)

	# 主体：左页签列 + 右内容区
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiThemeScript.SPACE_M)
	root.add_child(body)

	_tab_column = VBoxContainer.new()
	_tab_column.custom_minimum_size = Vector2(140, 0)
	_tab_column.add_theme_constant_override("separation", UiThemeScript.SPACE_XS)
	body.add_child(_tab_column)

	_content_area = ScrollContainer.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content_area)

	# 底部状态条
	_status_label = Label.new()
	_status_label.text = "✓ 改动会自动保存"
	UiThemeScript.tint_label(_status_label, "caption")
	root.add_child(_status_label)

	# 6 页签与页面容器
	for i in TAB_NAMES.size():
		var tab_btn := Button.new()
		tab_btn.text = TAB_NAMES[i]
		tab_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab_btn.add_theme_stylebox_override("normal", UiThemeScript.tab_style(i == 0))
		tab_btn.add_theme_stylebox_override("hover", UiThemeScript.tab_style(true))
		tab_btn.add_theme_color_override("font_color", UiThemeScript.TEXT if i == 0 else UiThemeScript.TEXT_DIM)
		tab_btn.pressed.connect(switch_tab.bind(i))
		_tab_column.add_child(tab_btn)
		_tab_buttons.append(tab_btn)

		var page := VBoxContainer.new()
		page.name = TAB_NAMES[i]
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", UiThemeScript.SPACE_S)
		page.visible = i == 0
		_content_area.add_child(page)
		_pages[TAB_NAMES[i]] = page

	_build_page_appearance()
	_build_page_sound()
	_build_page_personality()
	_build_page_smart()
	_build_page_progress()
	_build_page_about()

	timed_hide_update_timer = Timer.new()
	timed_hide_update_timer.wait_time = 1.0
	timed_hide_update_timer.timeout.connect(_on_timed_hide_update_timer)
	add_child(timed_hide_update_timer)
	visibility_changed.connect(_on_visibility_changed)

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func get_tab_names() -> Array[String]:
	return TAB_NAMES.duplicate()

func switch_tab(index: int) -> void:
	current_tab_index = clampi(index, 0, TAB_NAMES.size() - 1)
	for i in TAB_NAMES.size():
		var page: VBoxContainer = _pages[TAB_NAMES[i]]
		page.visible = i == current_tab_index
		var btn: Button = _tab_buttons[i]
		btn.add_theme_stylebox_override("normal", UiThemeScript.tab_style(i == current_tab_index))
		btn.add_theme_color_override("font_color", UiThemeScript.TEXT if i == current_tab_index else UiThemeScript.TEXT_DIM)

# —— 页构建占位（Task 3-5 实现）——
func _build_page_appearance() -> void:
	pass

func _build_page_sound() -> void:
	pass

func _build_page_personality() -> void:
	pass

func _build_page_smart() -> void:
	pass

func _build_page_progress() -> void:
	pass

func _build_page_about() -> void:
	pass

# —— 对外接口占位（Task 3-5 逐个补实现）——
func apply_settings(_settings: Dictionary) -> void:
	pass

func collect_settings() -> Dictionary:
	return {}

func refresh_bond_ui() -> void:
	pass

func refresh_quest_ui() -> void:
	pass

func refresh_breed_locks(_bond_level: int) -> void:
	pass

func set_timed_hide_option(_index: int) -> void:
	pass

func _on_timed_hide_update_timer() -> void:
	if not visible:
		return

func _on_visibility_changed() -> void:
	if visible:
		_on_timed_hide_update_timer()

func _on_close_pressed() -> void:
	visible = false
```

- [ ] **Step 5: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: `passed: 20  failed: 0`（14 + 6）

- [ ] **Step 6: headless 冒烟（此时面板可能因 main 旧调用报错——冒烟只查本测试）**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: 同上（main.tscn 冒烟推迟到 Task 8 接线完成后）

- [ ] **Step 7: Commit**

```bash
git add settings_panel.gd settings_panel.tscn tests/test_ui_theme.gd
git commit -m "feat: 设置面板侧边页签骨架"
```

---

### Task 3: 外观页 + 声音页

**Files:**
- Modify: `settings_panel.gd`（实现 `_build_page_appearance` / `_build_page_sound` / 相关 handler / collect 部分）

- [ ] **Step 1: 实现 `_build_page_appearance`（替换 Task 2 的空函数）**

```gdscript
func _build_page_appearance() -> void:
	var page: VBoxContainer = _pages["外观"]

	# 透明度
	var opacity_label := _section_label(page, "透明度")
	opacity_slider = _make_slider(page, 0.2, 1.0, 0.05)
	opacity_slider.value_changed.connect(_on_opacity_changed)

	# 猫大小（P7 新增：scale_factor 存档链路一直无 UI）
	var scale_label := _section_label(page, "猫咪大小")
	cat_scale_slider = _make_slider(page, 0.6, 2.0, 0.1)

	# 开关两枚
	always_on_top_check = _make_check(page, "窗口置顶")
	always_on_top_check.toggled.connect(_on_always_on_top_toggled)
	auto_start_check = _make_check(page, "开机自启")
	auto_start_check.toggled.connect(_on_auto_start_toggled)

	# 定时隐藏
	_section_label(page, "定时隐藏")
	timed_hide_option = OptionButton.new()
	for opt in ["关闭", "15分钟", "30分钟", "1小时", "2小时"]:
		timed_hide_option.add_item(opt)
	timed_hide_option.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
	timed_hide_option.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
	timed_hide_option.item_selected.connect(_on_timed_hide_selected)
	page.add_child(timed_hide_option)
	timed_hide_remaining_label = Label.new()
	timed_hide_remaining_label.visible = false
	UiThemeScript.tint_label(timed_hide_remaining_label, "caption")
	page.add_child(timed_hide_remaining_label)

func _section_label(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	UiThemeScript.tint_label(label, "section")
	parent.add_child(label)
	return label

func _make_slider(parent: Container, min_v: float, max_v: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 28)
	slider.add_theme_stylebox_override("slider", UiThemeScript.slider_track_style())
	slider.add_theme_stylebox_override("grabber_area", UiThemeScript.slider_fill_style())
	slider.add_theme_stylebox_override("grabber_area_highlight", UiThemeScript.slider_fill_style())
	parent.add_child(slider)
	return slider

func _make_check(parent: Container, text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.add_theme_stylebox_override("normal", UiThemeScript.check_style(false))
	check.add_theme_stylebox_override("checked", UiThemeScript.check_style(true))
	check.add_theme_color_override("font_color", UiThemeScript.TEXT)
	parent.add_child(check)
	return check
```

- [ ] **Step 2: 实现 `_build_page_sound`**

```gdscript
func _build_page_sound() -> void:
	var page: VBoxContainer = _pages["声音"]
	sound_check = _make_check(page, "音效")
	sound_check.toggled.connect(_on_sound_toggled)
	bgm_check = _make_check(page, "背景音乐")
	bgm_check.toggled.connect(_on_bgm_toggled)
	_section_label(page, "音量")
	volume_slider = _make_slider(page, 0.0, 1.0, 0.05)
	volume_slider.value_changed.connect(_on_volume_changed)
```

- [ ] **Step 3: 实现 handler（沿用旧面板逻辑，改即存）**

```gdscript
func _on_opacity_changed(value: float) -> void:
	SaveManager.save_data()

func _on_always_on_top_toggled(enabled: bool) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
	SaveManager.save_data()

func _on_auto_start_toggled(enabled: bool) -> void:
	var asm = get_node_or_null("/root/Main/AutoStartManager")
	if asm and asm.has_method("set_auto_start"):
		asm.set_auto_start(enabled)
	SaveManager.save_data()

func _on_timed_hide_selected(index: int) -> void:
	# 已核实：SaveManager.set_timed_hide_option 存在（save_manager.gd:318）并转发 main
	SaveManager.set_timed_hide_option(index)
	SaveManager.save_data()
	_update_timed_hide_remaining()

func _on_sound_toggled(enabled: bool) -> void:
	if AudioManager:
		AudioManager.sound_enabled = enabled
	SaveManager.save_data()

func _on_bgm_toggled(enabled: bool) -> void:
	if AudioManager:
		AudioManager.bgm_enabled = enabled
	SaveManager.save_data()

func _on_volume_changed(value: float) -> void:
	if AudioManager:
		AudioManager.set_volume(value)
	SaveManager.save_data()

func _on_cat_scale_changed(value: float) -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.has_method("set"):
		main.cat.scale_factor = value
	SaveManager.save_data()
```

（`_on_timed_hide_selected` 的 main 侧承接已核实：`SaveManager.set_timed_hide_option(index)`（save_manager.gd:318）→ 转发 `main.set_timed_hide_option`。`_update_timed_hide_remaining` / `_format_duration` 从旧面板 settings_panel.gd:286-307 原样照搬，计划内不再重复列出——执行时从 git 历史旧文件抄。）

- [ ] **Step 4: 补 apply/collect 的本页键**

`apply_settings` 填充：

```gdscript
func apply_settings(settings: Dictionary) -> void:
	if settings.has("opacity"):
		_set_slider_value(opacity_slider, float(settings["opacity"]))
	always_on_top_check.button_pressed = bool(settings.get("always_on_top", true))
	auto_start_check.button_pressed = bool(settings.get("auto_start", false))
	timed_hide_option.select(int(settings.get("timed_hide_option", 0)))
	sound_check.button_pressed = bool(settings.get("sound_enabled", true))
	bgm_check.button_pressed = bool(settings.get("bgm_enabled", true))
	_set_slider_value(volume_slider, float(settings.get("volume", 1.0)))
	# 猫大小（cat 区块键，main 读档时未注入 settings——由 set_cat_scale 单独喂，见 Task 8）
	if settings.has("cat_scale"):
		_set_slider_value(cat_scale_slider, float(settings["cat_scale"]))
```

`collect_settings` 填充（保持旧 22 键 + 新增 cat_scale）：

```gdscript
func collect_settings() -> Dictionary:
	var settings: Dictionary = {}
	settings["opacity"] = opacity_slider.value
	settings["always_on_top"] = always_on_top_check.button_pressed
	settings["timed_hide_option"] = timed_hide_option.selected
	settings["sound_enabled"] = sound_check.button_pressed
	settings["bgm_enabled"] = bgm_check.button_pressed
	settings["volume"] = volume_slider.value
	settings["cat_scale"] = cat_scale_slider.value
	return settings

func _set_slider_value(slider: Range, value: float) -> void:
	slider.set_value_no_signal(value)
```

- [ ] **Step 5: 跑测试 + Commit**

```bash
timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn
git add settings_panel.gd
git commit -m "feat: 设置面板外观与声音页"
```
Expected: `passed: 20  failed: 0`（占位实现不炸即过；键集断言在 Task 5 补）

---

### Task 4: 猫性格页 + 智能页

**Files:**
- Modify: `settings_panel.gd`

- [ ] **Step 1: 实现 `_build_page_personality`**

```gdscript
func _build_page_personality() -> void:
	var page: VBoxContainer = _pages["猫性格"]
	_section_label(page, "品种")
	cat_breed_option = _make_option(page)
	for i in CAT_BREED_IDS.size():
		cat_breed_option.add_item(CAT_BREED_NAMES[i])
	cat_breed_option.item_selected.connect(_on_cat_breed_selected)

	_section_label(page, "性格")
	personality_option = _make_option(page)
	personality_option.add_item("傲娇")
	personality_option.add_item("温柔")
	personality_option.add_item("活泼")
	personality_option.item_selected.connect(_on_personality_selected)

	_section_label(page, "活跃度")
	intensity_option = _make_option(page)
	intensity_option.add_item("安静")
	intensity_option.add_item("正常")
	intensity_option.add_item("活跃")
	intensity_option.item_selected.connect(_on_intensity_selected)

func _make_option(parent: Container) -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
	option.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
	option.add_theme_color_override("font_color", UiThemeScript.TEXT)
	parent.add_child(option)
	return option
```

- [ ] **Step 2: 实现 `_build_page_smart`**

```gdscript
func _build_page_smart() -> void:
	var page: VBoxContainer = _pages["智能"]
	smart_mode_check = _make_check(page, "智能模式（SMART）")
	smart_mode_check.toggled.connect(_on_smart_mode_toggled)
	perception_check = _make_check(page, "感知前台应用")
	perception_check.toggled.connect(_on_perception_toggled)
	perception_default_rules_check = _make_check(page, "使用默认分类规则")
	perception_default_rules_check.toggled.connect(func(_v): _apply_smart_settings(); SaveManager.save_data())

	_section_label(page, "存在感")
	presence_level_option = _make_option(page)
	for opt in ["安静（≤1句/小时）", "低频（关键时刻）", "中频（工位同事）", "高频（话痨猫）", "智能（按活动自适应）"]:
		presence_level_option.add_item(opt)
	presence_level_option.item_selected.connect(_on_presence_level_selected)

	_section_label(page, "静音时段")
	var row := HBoxContainer.new()
	page.add_child(row)
	quiet_start_spin = _make_spin(row)
	var sep := Label.new()
	sep.text = " 至 次日 "
	UiThemeScript.tint_label(sep, "body")
	row.add_child(sep)
	quiet_end_spin = _make_spin(row)
	quiet_start_spin.value_changed.connect(func(_v): _on_quiet_hours_changed(_v))
	quiet_end_spin.value_changed.connect(func(_v): _on_quiet_hours_changed(_v))

	_section_label(page, "专注会话时长")
	focus_duration_option = _make_option(page)
	for opt in ["15 分钟", "30 分钟", "60 分钟"]:
		focus_duration_option.add_item(opt)
	focus_duration_option.item_selected.connect(_on_focus_duration_selected)

	_section_label(page, "LLM 大模型")
	llm_enabled_check = _make_check(page, "启用 LLM（无 Key 时用模板台词）")
	llm_enabled_check.toggled.connect(_on_llm_enabled_toggled)
	llm_endpoint_input = _make_line(page, "API 端点")
	llm_endpoint_input.text_changed.connect(func(_v): _apply_smart_settings(); SaveManager.save_data())
	llm_model_input = _make_line(page, "模型名")
	llm_model_input.text_changed.connect(func(_v): _apply_smart_settings(); SaveManager.save_data())
	llm_api_key_input = _make_line(page, "API Key")
	llm_api_key_input.secret = true
	llm_api_key_input.text_changed.connect(func(_v): _apply_smart_settings(); SaveManager.save_data())
	llm_api_env_input = _make_line(page, "环境变量名（优先读取）")
	llm_api_env_input.text_changed.connect(func(_v): _apply_smart_settings(); SaveManager.save_data())

func _make_spin(parent: Container) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 23
	spin.step = 1
	spin.custom_minimum_size = Vector2(72, 32)
	parent.add_child(spin)
	return spin

func _make_line(parent: Container, placeholder: String) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.custom_minimum_size = Vector2(0, 36)
	line.add_theme_stylebox_override("normal", UiThemeScript.line_style())
	line.add_theme_stylebox_override("focus", UiThemeScript.line_style(true))
	parent.add_child(line)
	return line
```

- [ ] **Step 3: 实现 handler 与 apply/collect 补全**

handler（照旧逻辑：改即存 + `_apply_smart_settings`）：

```gdscript
func _on_smart_mode_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_perception_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_presence_level_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_quiet_hours_changed(_value: float) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_personality_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_intensity_selected(_index: int) -> void:
	SaveManager.save_data()

func _on_focus_duration_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_llm_enabled_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_cat_breed_selected(_index: int) -> void:
	_apply_cat_breed()
	SaveManager.save_data()

func _apply_smart_settings() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.smart_pet_controller and main.smart_pet_controller.has_method("configure"):
		main.smart_pet_controller.configure(collect_settings())

func _apply_cat_breed() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.animation_component:
		var breed_id := CAT_BREED_IDS[clampi(cat_breed_option.selected, 0, CAT_BREED_IDS.size() - 1)]
		main.cat.animation_component.switch_cat_type(breed_id)
```

`apply_settings` 追加（在 Task 3 版本末尾）：

```gdscript
	var breed_index: int = CAT_BREED_IDS.find(String(settings.get("cat_type", "orange_tabby")))
	cat_breed_option.select(maxi(breed_index, 0))
	personality_option.select(_personality_to_index(String(settings.get("personality", "tsundere"))))
	intensity_option.select(int(settings.get("intensity", 1)))
	smart_mode_check.button_pressed = bool(settings.get("smart_mode", true))
	perception_check.button_pressed = bool(settings.get("perception_enabled", false))
	perception_default_rules_check.button_pressed = bool(settings.get("perception_default_rules", true))
	presence_level_option.select(clampi(int(settings.get("presence_level", 2)), 0, 4))
	_set_spin_value(quiet_start_spin, float(settings.get("quiet_hours_start", 23)))
	_set_spin_value(quiet_end_spin, float(settings.get("quiet_hours_end", 8)))
	focus_duration_option.select(clampi(int(settings.get("focus_duration_index", 1)), 0, 2))
	llm_enabled_check.button_pressed = bool(settings.get("llm_enabled", false))
	llm_endpoint_input.text = String(settings.get("llm_endpoint", DEFAULT_LLM_ENDPOINT))
	llm_model_input.text = String(settings.get("llm_model", "gpt-4o-mini"))
	llm_api_key_input.text = String(settings.get("llm_api_key", ""))
	llm_api_env_input.text = String(settings.get("llm_api_key_env", "OPENAI_API_KEY"))

func _set_spin_value(spin: SpinBox, value: float) -> void:
	spin.set_value_no_signal(value)

func _personality_to_index(value: String) -> int:
	match value:
		"gentle":
			return 1
		"playful":
			return 2
		_:
			return 0
```

`collect_settings` 追加（在 Task 3 版本 return 前）：

```gdscript
	settings["intensity"] = intensity_option.selected
	settings["smart_mode"] = smart_mode_check.button_pressed
	settings["perception_enabled"] = perception_check.button_pressed
	settings["perception_default_rules"] = perception_default_rules_check.button_pressed
	settings["focus_duration_index"] = focus_duration_option.selected
	settings["cat_type"] = CAT_BREED_IDS[clampi(cat_breed_option.selected, 0, CAT_BREED_IDS.size() - 1)]
	settings["llm_enabled"] = llm_enabled_check.button_pressed
	settings["llm_endpoint"] = llm_endpoint_input.text.strip_edges()
	settings["llm_model"] = llm_model_input.text.strip_edges()
	settings["llm_api_key"] = llm_api_key_input.text.strip_edges()
	settings["llm_api_key_env"] = llm_api_env_input.text.strip_edges()
	match personality_option.selected:
		1:
			settings["personality"] = "gentle"
		2:
			settings["personality"] = "playful"
		_:
			settings["personality"] = "tsundere"
	settings["presence_level"] = clampi(presence_level_option.selected, 0, 4)
	settings["quiet_hours_start"] = int(round(quiet_start_spin.value))
	settings["quiet_hours_end"] = int(round(quiet_end_spin.value))
	settings["data_collection_level"] = "minimal"
```

- [ ] **Step 4: 补品种锁与刷新函数（旧逻辑照搬）**

```gdscript
const BREED_LOCK_LEVELS: Dictionary = {"calico": 3, "british_blue": 4, "tuxedo": 5}

func refresh_breed_locks(bond_level: int) -> void:
	for i in CAT_BREED_IDS.size():
		var breed_id := CAT_BREED_IDS[i]
		var need: int = int(BREED_LOCK_LEVELS.get(breed_id, 1))
		var unlocked: bool = bond_level >= need
		var label := CAT_BREED_NAMES[i]
		if not unlocked:
			cat_breed_option.set_item_text(i, "%s 🔒Lv%d" % [label, need])
		else:
			cat_breed_option.set_item_text(i, label)

func _on_cat_breed_selected(_index: int) -> void:
	# 拦截未解锁品种（旧逻辑：锁定项不可选）
	var breed_id := CAT_BREED_IDS[clampi(_index, 0, CAT_BREED_IDS.size() - 1)]
	var main = get_tree().get_root().get_node_or_null("Main")
	var bond_level := _get_bond_level()
	var need: int = int(BREED_LOCK_LEVELS.get(breed_id, 1))
	if bond_level < need:
		# 回退到当前品种
		var current := String(main.cat.current_cat_type if main and main.cat else "orange_tabby")
		cat_breed_option.select(maxi(CAT_BREED_IDS.find(current), 0))
		return
	_apply_cat_breed()
	SaveManager.save_data()

func _get_bond_level() -> int:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.bond_system:
		return main.cat.bond_system.get_level()
	return 1
```

（注意：Task 4 Step 3 已定义过 `_on_cat_breed_selected`——以本 Step 版本为准**覆盖**，Step 3 的简化版删除。）

- [ ] **Step 5: 跑测试 + Commit**

```bash
timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn
git add settings_panel.gd
git commit -m "feat: 设置面板性格与智能页"
```

---

### Task 5: 任务·亲密度页 + 关于页（含存档管理承接）

**Files:**
- Modify: `settings_panel.gd`
- Test: `tests/test_ui_theme.gd`（追加 roundtrip 断言）

- [ ] **Step 1: 实现 `_build_page_progress`（承接 P5/P6 的 bond/quest 区块）**

```gdscript
var _bond_level_label: Label
var _bond_progress_bar: ProgressBar
var _quest_rows: Array = []
var _quest_streak_label: Label

func _build_page_progress() -> void:
	var page: VBoxContainer = _pages["任务·亲密度"]
	_bond_level_label = Label.new()
	UiThemeScript.tint_label(_bond_level_label, "body")
	page.add_child(_bond_level_label)
	_bond_progress_bar = ProgressBar.new()
	_bond_progress_bar.min_value = 0.0
	_bond_progress_bar.max_value = 100.0
	_bond_progress_bar.show_percentage = false
	_bond_progress_bar.custom_minimum_size = Vector2(0, 14)
	_bond_progress_bar.add_theme_stylebox_override("background", UiThemeScript.slider_track_style())
	_bond_progress_bar.add_theme_stylebox_override("fill", UiThemeScript.slider_fill_style())
	page.add_child(_bond_progress_bar)

	var quest_title := Label.new()
	quest_title.text = "今日任务"
	UiThemeScript.tint_label(quest_title, "section")
	page.add_child(quest_title)
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.daily_quest_service:
		for qid in main.daily_quest_service.QUEST_DEFS:
			var row := Label.new()
			UiThemeScript.tint_label(row, "body")
			page.add_child(row)
			_quest_rows.append({"label": row, "quest_id": String(qid)})
	_quest_streak_label = Label.new()
	UiThemeScript.tint_label(_quest_streak_label, "body")
	_quest_streak_label.add_theme_color_override("font_color", UiThemeScript.PRIMARY)
	page.add_child(_quest_streak_label)

func refresh_bond_ui() -> void:
	if not _bond_level_label:
		return
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main or not main.cat or not main.cat.bond_system:
		return
	var bs = main.cat.bond_system
	var info: Dictionary = bs.get_level_info()
	var next: Dictionary = bs.get_next_level_info()
	_bond_level_label.text = "亲密度 Lv.%d「%s」" % [bs.get_level(), String(info.get("title", ""))]
	if next.is_empty():
		_bond_progress_bar.value = 100.0
	else:
		_bond_progress_bar.value = bs.get_progress() * 100.0
		var unlock_breed := String(next.get("unlock_breed", ""))
		var unlock_anim := String(next.get("unlock_anim", ""))
		if not unlock_breed.is_empty():
			_bond_level_label.text += "　下一级解锁：品种"
		elif not unlock_anim.is_empty():
			_bond_level_label.text += "　下一级解锁：新动作"

func refresh_quest_ui() -> void:
	if _quest_rows.is_empty():
		return
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main or not main.daily_quest_service:
		return
	var summary: Dictionary = main.daily_quest_service.get_today_summary()
	for row in _quest_rows:
		var quest_id: String = row["quest_id"]
		var title := ""
		var done := false
		for q in summary.get("quests", []):
			if String(q.get("id", "")) == quest_id:
				title = String(q.get("title", ""))
				done = bool(q.get("completed", false))
		row["label"].text = ("✓ " if done else "○ ") + title
	_quest_streak_label.text = "陪伴 · 连续签到 %d 天" % int(summary.get("streak_days", 0))

func _on_visibility_changed() -> void:
	if visible:
		_on_timed_hide_update_timer()
		refresh_breed_locks(_get_bond_level())
		refresh_bond_ui()
		refresh_quest_ui()
```

（Task 2 骨架里的 `_on_visibility_changed` 简化版删除，用本版本。）

- [ ] **Step 2: 实现 `_build_page_about`（存档管理四功能承接 + Credits）**

```gdscript
var _save_time_label: Label
var _export_dialog: FileDialog
var _import_dialog: FileDialog

func _build_page_about() -> void:
	var page: VBoxContainer = _pages["关于"]
	var version := Label.new()
	version.text = "桌宠猫 · 智能生活伴侣 v1.7（P7 奶油风）"
	UiThemeScript.tint_label(version, "body")
	page.add_child(version)
	var credits := Label.new()
	credits.text = "原创猫素材：本地生成\n历史 UI 素材：VerzatileDev (CC BY 4.0)"
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiThemeScript.tint_label(credits, "caption")
	page.add_child(credits)

	_section_label(page, "存档管理")
	_save_time_label = Label.new()
	UiThemeScript.tint_label(_save_time_label, "caption")
	page.add_child(_save_time_label)
	var row := HBoxContainer.new()
	page.add_child(row)
	var export_btn := Button.new()
	export_btn.text = "导出"
	export_btn.pressed.connect(func(): _export_dialog.popup_centered())
	row.add_child(export_btn)
	var import_btn := Button.new()
	import_btn.text = "导入"
	import_btn.pressed.connect(func(): _import_dialog.popup_centered())
	row.add_child(import_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置存档"
	reset_btn.add_theme_color_override("font_color", UiThemeScript.DANGER)
	row.add_child(reset_btn)
	_style_btn_row([export_btn, import_btn, reset_btn])

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.catpet"])
	add_child(_export_dialog)
	_export_dialog.file_selected.connect(_on_export_selected)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.catpet"])
	add_child(_import_dialog)
	_import_dialog.file_selected.connect(_on_import_selected)

	reset_btn.pressed.connect(func():
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = "确定要重置存档吗？这将清除所有数据并恢复默认。"
		add_child(confirm)
		confirm.confirmed.connect(func():
			SaveManager.reset_data()
			confirm.queue_free())
		confirm.close_requested.connect(func(): confirm.queue_free())
		confirm.popup_centered())

func _style_btn_row(buttons: Array) -> void:
	for btn in buttons:
		btn.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
		btn.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
		btn.add_theme_color_override("font_color", UiThemeScript.TEXT)

func _on_export_selected(path: String) -> void:
	# 已核实：SaveManager.export_to_file(path) -> bool（save_manager.gd:323，内部自处理 .catpet 扩展名）
	if SaveManager.export_to_file(path):
		_status_label.text = "✓ 导出成功"
	else:
		_status_label.text = "✗ 导出失败"
	_refresh_save_info()

func _on_import_selected(path: String) -> void:
	# 已核实：SaveManager.import_from_file(path) -> bool（save_manager.gd:336，内部 _normalize_import_data）
	if SaveManager.import_from_file(path):
		var data: Dictionary = SaveManager.load_data()
		SaveManager.apply_settings(data)
		apply_settings(data)
		_status_label.text = "✓ 导入成功，已应用"
	else:
		_status_label.text = "✗ 导入失败"
	_refresh_save_info()

func _refresh_save_info() -> void:
	if not _save_time_label:
		return
	var data: Dictionary = SaveManager.load_data()
	var meta: Dictionary = data.get("meta", {})
	var saved_at := int(meta.get("saved_at", 0))
	if saved_at > 0:
		var dt := Time.get_datetime_dict_from_unix_time(saved_at)
		_save_time_label.text = "上次保存：%04d-%02d-%02d %02d:%02d" % [
			dt.year, dt.month, dt.day, dt.hour, dt.minute]
	else:
		_save_time_label.text = "暂无存档"
	var cat_type := String(data.get("cat", {}).get("cat_type", "orange_tabby"))
	_save_time_label.text += "　品种：" + cat_type
```

（已核实：`SaveManager.reset_data()` 存在（save_manager.gd:367），旧 save_manager_panel.gd:76 正是调它——直接用。）

- [ ] **Step 3: 追加 roundtrip 测试（_run 追加 `_test_settings_roundtrip()`）**

```gdscript
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
```

- [ ] **Step 4: 跑测试 + Commit**

```bash
timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn
git add settings_panel.gd tests/test_ui_theme.gd
git commit -m "feat: 设置面板进度与关于页含存档管理"
```
Expected: `passed: 28  failed: 0`（20 + 8）

---

### Task 6: 快捷菜单弧形轮盘

**Files:**
- Rewrite: `quick_action_menu.gd`
- Test: `tests/test_ui_theme.gd`（追加）

- [ ] **Step 1: 追加失败测试（_run 追加 `_test_radial_menu()`）**

```gdscript
const QuickMenuScript = preload("res://quick_action_menu.gd")

func _test_radial_menu() -> void:
	var menu = QuickMenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	# 6 动作按钮构建（设置入口移除后）
	var actions: Array = menu.get_action_ids()
	_assert_equal(actions.size(), 6, "six_actions")
	_assert_true(not actions.has("settings"), "settings_removed")
	# 信号：action_selected 带 action 值发射
	var fired: Array = []
	menu.action_selected.connect(func(a): fired.append(a))
	menu._emit_action("pet")
	_assert_equal(String(fired[0] if fired.size() > 0 else ""), "pet", "signal_carries_action")
	menu.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn`
Expected: FAIL（get_action_ids 不存在）

- [ ] **Step 3: 重写 quick_action_menu.gd（弧形轮盘）**

```gdscript
extends CanvasLayer

## P7 快捷菜单：6 动作弧形轮盘（扇形绕猫展开），奶油风圆钮
## 对外接口不变：action_selected(action) / menu_closed / show_at / hide_menu

signal action_selected(action: String)
signal menu_closed()

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const ACTIONS := [
	["摸摸", "pet", "res://assets/items/icon_pet.png"],
	["逗猫棒", "wand", "res://assets/items/icon_wand.png"],
	["投食", "food", "res://assets/items/icon_food.png"],
	["毛线球", "yarn", "res://assets/items/yarn.png"],
	["纸箱", "box", "res://assets/items/box.png"],
	["溜猫", "leash", "res://assets/items/icon_leash.png"],
]
const AUTO_CLOSE_SEC := 3.0
const TWEEN_DURATION := 0.15
const RADIUS := 110.0
## 扇形角度：从 -160° 到 -20°（猫头顶上方半圆，开口朝下）
const ANGLE_FROM := deg_to_rad(-160.0)
const ANGLE_TO := deg_to_rad(-20.0)
const BTN_SIZE := 64.0

var _root: Control
var _panel: Control
var _buttons: Array = []
var _auto_close_timer: Timer
var _tween: Tween

func _ready() -> void:
	layer = 15
	visible = false
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_gui_input)
	add_child(_root)

	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	for i in ACTIONS.size():
		var entry: Array = ACTIONS[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		btn.icon = _load_icon(String(entry[2]))
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 28)
		btn.tooltip_text = String(entry[0])
		btn.add_theme_stylebox_override("normal", _round_style(false))
		btn.add_theme_stylebox_override("hover", _round_style(true))
		btn.add_theme_stylebox_override("pressed", _round_style(true))
		btn.pressed.connect(_emit_action.bind(String(entry[1])))
		_panel.add_child(btn)
		_buttons.append(btn)

	_auto_close_timer = Timer.new()
	_auto_close_timer.one_shot = true
	_auto_close_timer.wait_time = AUTO_CLOSE_SEC
	_auto_close_timer.timeout.connect(hide_menu)
	add_child(_auto_close_timer)

func _round_style(hover: bool) -> StyleBoxFlat:
	var sb := UiThemeScript.btn_style(hover)
	sb.set_corner_radius_all(int(BTN_SIZE * 0.5))  # 正圆
	sb.border_color = UiThemeScript.PINK if hover else UiThemeScript.PRIMARY
	sb.set_border_width_all(2)
	return sb

func _load_icon(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func get_action_ids() -> Array:
	var ids: Array = []
	for entry in ACTIONS:
		ids.append(String(entry[1]))
	return ids

func _emit_action(action: String) -> void:
	action_selected.emit(action)
	hide_menu()

func show_at(pos: Vector2) -> void:
	visible = true
	# 按弧形分布按钮（猫头顶半圆）
	for i in _buttons.size():
		var t: float = float(i) / float(maxi(_buttons.size() - 1, 1))
		var angle: float = lerpf(ANGLE_FROM, ANGLE_TO, t)
		var offset := Vector2(cos(angle), sin(angle)) * RADIUS
		var btn: Button = _buttons[i]
		btn.position = pos + offset - Vector2(BTN_SIZE, BTN_SIZE) * 0.5
	_kill_tween()
	_panel.scale = Vector2(0.4, 0.4)
	_panel.pivot_offset = pos - _panel.global_position
	_panel.modulate = Color(1, 1, 1, 0)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, TWEEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), TWEEN_DURATION)
	_auto_close_timer.start()

func hide_menu() -> void:
	_auto_close_timer.stop()
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2(0.4, 0.4), TWEEN_DURATION).set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 0), TWEEN_DURATION)
	_tween.chain().tween_callback(_on_hide_finished)

func _on_hide_finished() -> void:
	visible = false
	menu_closed.emit()

func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_menu()

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
```

- [ ] **Step 4: 跑测试 + 冒烟 main（settings 入口移除后 main 的 `"settings"` 分支成死码，Task 8 清理）**

```bash
timeout 60 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn
```
Expected: `passed: 32  failed: 0`（28 + 4）

- [ ] **Step 5: Commit**

```bash
git add quick_action_menu.gd tests/test_ui_theme.gd
git commit -m "feat: 快捷菜单弧形轮盘奶油风"
```

---

### Task 7: 气泡换装 + 聚合抽屉

**Files:**
- Modify: `components/ui/smart_line_bubble.gd`（视觉换装，接口不动）
- Rewrite: `components/ui/hover_panel.gd`（常驻圆钮 + 抽屉）

- [ ] **Step 1: smart_line_bubble.gd 换装**

找到 `_ready` 中 aurora bubble 加载段（smart_line_bubble.gd:23 附近）：

```gdscript
	var bubble_tex := load("res://assets/aurora/bubble.png") as Texture2D
```

及其 StyleBoxTexture 构建块，整体替换为：

```gdscript
	_panel.add_theme_stylebox_override("panel", UiThemeScript.bubble_style())
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", UiThemeScript.TEXT)
```

（`const UiThemeScript = preload("res://components/ui/ui_theme.gd")` 加文件头。原 StyleBoxTexture 变量与 aurora_tex 判定块全删。函数签名 `show_line` / `show_gain_tip` / `reposition` / `is_visible_to_user` / `hide_bubble` 一律不动。）

- [ ] **Step 2: 重写 hover_panel.gd（聚合抽屉）**

```gdscript
class_name DesktopHoverPanel
extends Node2D

## P7 聚合抽屉：右缘常驻猫爪圆钮，点开竖排四按钮（道具/设置/专注/存档）
## 兼容旧接口：is_out / panel 属性（穿透管理器读）；items_requested / settings_requested 保留

signal items_requested
signal settings_requested
signal focus_requested
signal save_requested

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const BTN_SIZE := 32.0
const DRAWER_WIDTH := 56.0
const DRAWER_GAP := 10.0
const AUTO_CLOSE_SEC := 30.0

var is_out: bool = false  # 抽屉展开状态（穿透管理器判定用，保持旧名）
var panel: Control  # 兼容旧属性名（穿透区域计算读它）
var _knob: Button
var _drawer: VBoxContainer
var _screen_size: Vector2 = Vector2(1920, 1080)
var _auto_close_timer: Timer

func setup(screen_size: Vector2) -> void:
	_screen_size = screen_size
	_build_ui()

func _build_ui() -> void:
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_knob = Button.new()
	_knob.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_knob.flat = true
	_knob.modulate = Color(1, 1, 1, 0.55)
	_knob.pressed.connect(_toggle_drawer)
	_knob.mouse_entered.connect(func(): _knob.modulate = Color(1, 1, 1, 1.0))
	_knob.mouse_exited.connect(func(): if not is_out: _knob.modulate = Color(1, 1, 1, 0.55))
	_knob.add_theme_stylebox_override("normal", _round_style())
	_knob.add_theme_stylebox_override("hover", _round_style(true))
	_knob.add_theme_stylebox_override("pressed", _round_style(true))
	_knob.tooltip_text = "打开菜单"
	_knob.text = "🐾"
	panel.add_child(_knob)

	_drawer = VBoxContainer.new()
	_drawer.add_theme_constant_override("separation", DRAWER_GAP)
	_drawer.visible = false
	panel.add_child(_drawer)
	for entry in [["🧶", "道具", items_requested], ["⚙️", "设置", settings_requested],
			["🎯", "专注", focus_requested], ["💾", "存档", save_requested]]:
		var btn := Button.new()
		btn.text = String(entry[0])
		btn.tooltip_text = String(entry[1])
		btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		btn.add_theme_stylebox_override("normal", _round_style())
		btn.add_theme_stylebox_override("hover", _round_style(true))
		btn.add_theme_stylebox_override("pressed", _round_style(true))
		btn.pressed.connect(func():
			entry[2].emit()
			_toggle_drawer())
		_drawer.add_child(btn)

	_auto_close_timer = Timer.new()
	_auto_close_timer.one_shot = true
	_auto_close_timer.wait_time = AUTO_CLOSE_SEC
	_auto_close_timer.timeout.connect(func(): if is_out: _toggle_drawer())
	add_child(_auto_close_timer)
	_layout()

func _round_style(hover: bool = false) -> StyleBoxFlat:
	var sb := UiThemeScript.btn_style(hover)
	sb.set_corner_radius_all(int(BTN_SIZE * 0.5))
	sb.border_color = UiThemeScript.PINK if hover else UiThemeScript.PRIMARY
	sb.set_border_width_all(2)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	return sb

func _layout() -> void:
	var cy := _screen_size.y * 0.5
	_knob.position = Vector2(_screen_size.x - BTN_SIZE - 4.0, cy - BTN_SIZE * 0.5)
	_drawer.position = Vector2(_screen_size.x - DRAWER_WIDTH - 4.0,
		cy - (_drawer.get_child_count() * (BTN_SIZE + DRAWER_GAP)) * 0.5)

func _toggle_drawer() -> void:
	is_out = not is_out
	_drawer.visible = is_out
	_knob.modulate = Color(1, 1, 1, 1.0)
	if is_out:
		_layout()
		_auto_close_timer.start()
	else:
		_auto_close_timer.stop()

func update(_delta: float, _mouse: Vector2, screen_size: Vector2) -> void:
	# 兼容旧每帧调用（main._process 喂）；尺寸变化时重排
	if screen_size != _screen_size:
		_screen_size = screen_size
		_layout()
```

- [ ] **Step 3: headless 冒烟 + 回归**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR|Parse" | head -4 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn 2>&1 | grep -E "passed|failed"
```
Expected: 启动成功（hover_panel 旧 update 签名兼容）；`failed: 0`

注意：main.gd:227-231 穿透管理器读 `hover_panel_component.panel.size.y` 与 `.is_out`——新 panel 是 Control 无显式尺寸，Task 8 接线时把穿透区域计算改为 `_knob.position + _drawer 展开时区域`；本任务先保证启动不炸（panel 属性存在即不崩）。

- [ ] **Step 4: Commit**

```bash
git add components/ui/smart_line_bubble.gd components/ui/hover_panel.gd
git commit -m "feat: 气泡奶油换装与聚合抽屉"
```

---

### Task 8: HUD 换装 + 托盘顺序 + main 接线收尾

**Files:**
- Modify: `components/focus/focus_hud.gd`（aurora → UiTheme）
- Modify: `components/desktop/tray_controller.gd`（菜单项顺序）
- Modify: `main.gd` + `main.tscn`（删 typing_overlay / 面板尺寸 / 抽屉信号 / 穿透区域 / cat_scale 喂入）

- [ ] **Step 1: focus_hud.gd 换装**

aurora 加载块（focus_hud.gd:69-72）替换：

```gdscript
	add_theme_stylebox_override("panel", UiThemeScript.panel_style())
```

（`const UiThemeScript = preload("res://components/ui/ui_theme.gd")` 加头部；原 aurora_tex/StyleBoxTexture 块删。进度条若引用 aurora slider 素材同法替换为 `slider_track_style()/slider_fill_style()`。执行时 grep aurora 清零本文件。）

- [ ] **Step 2: 托盘菜单项顺序**

tray_controller.gd `_build_menu` 中把「开始/结束专注会话」项移到最前（现有 addItem 顺序调整，其他不动）。

- [ ] **Step 3: main.gd 收尾改动（5 处）**

1. 删 `@onready var typing_effect_overlay = $TypingEffectOverlay`（main.gd:3）
2. 删 `_start_typing_effects` 与 `_get_typing_attack_duration` 函数及其调用点（`_on_keyboard_typing_for_smart` 附近 grep `_start_typing_effects` 全清）
3. `SETTINGS_PANEL_WIDTH/HEIGHT`（main.gd:41-42）改 `720.0 / 560.0`
4. `_center_settings_panel`（177-178 行）同步（尺寸常量改后此处引用常量即可，无需单独改——核实引用）
5. hover_panel 信号接线（101-102 行处）追加：

```gdscript
	hover_panel_component.focus_requested.connect(_on_tray_toggle_focus_session)
	hover_panel_component.save_requested.connect(func():
		if settings_panel:
			settings_panel.visible = true
			settings_panel.switch_tab(5))  # 「关于」页含存档管理
```

（已核实：main.gd:739 已有 `tray_controller.toggle_focus_session_requested.connect(_on_tray_toggle_focus_session)`，handler `_on_tray_toggle_focus_session` 在 main.gd:752——抽屉 focus 按钮直连同一 handler。）

6. 穿透区域计算（main.gd:227-231）替换：

```gdscript
	if hover_panel_component:
		var knob_area := Rect2(hover_panel_component._knob.position, Vector2(32, 32))
		var drawer_area := Rect2(Vector2.ZERO, Vector2.ZERO)
		if hover_panel_component.is_out:
			drawer_area = Rect2(hover_panel_component._drawer.position,
				Vector2(56, hover_panel_component._drawer.get_child_count() * 42))
		# 两区域并入 passthrough 例外清单（照现有 panel 例外写法）
```

（执行时看 passthrough_manager 的例外注册接口——现有代码如何用 `hover_panel_component.panel` 注册例外，新代码照同接口传 knob_area/drawer_area。）

7. 读档处给面板喂猫大小（`_setup` 中 apply_settings 后）：

```gdscript
	settings_panel.set_cat_scale(float(cat_data.get("scale_factor", 1.0)))
```

settings_panel.gd 加：

```gdscript
func set_cat_scale(value: float) -> void:
	_set_slider_value(cat_scale_slider, value)
```

- [ ] **Step 4: main.tscn 删 TypingEffectOverlay 节点**

main.tscn 中删 `[node name="TypingEffectOverlay" parent="." instance=ExtResource("4")]` 行与其 ext_resource 声明（id="4" 指向 typing_effect_overlay.tscn）。

- [ ] **Step 5: 全量冒烟 + 回归**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR|Parse" | head -5 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn 2>&1 | grep -E "passed|failed" && \
timeout 90 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn 2>&1 | grep -E "passed|failed"
```
Expected: 启动成功零脚本错误；两套测试绿

- [ ] **Step 6: Commit**

```bash
git add components/focus/focus_hud.gd components/desktop/tray_controller.gd main.gd main.tscn settings_panel.gd
git commit -m "feat: HUD换装托盘调整与主场景接线收尾"
```

---

### Task 9: 删旧素材 + 全量回归 + MCP 端到端 + 文档收尾

- [ ] **Step 1: 删除文件**

```bash
git rm -r assets/aurora/ typing_effect_overlay.gd typing_effect_overlay.tscn typing_effect_overlay.gd.uid save_manager_panel.gd save_manager_panel.tscn save_manager_panel.gd.uid
```

（uid 文件若 git 报不存在则去掉对应参数。删除后 `grep -rn "aurora\|typing_effect\|save_manager_panel" --include="*.gd" --include="*.tscn" . | grep -v .godot` 应零命中。）

- [ ] **Step 2: 13 套全量测试**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests test_ui_theme; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | grep -E "passed|failed|通过|失败" | tail -2
done
```
Expected: 全绿（286 + ui_theme ~32）

- [ ] **Step 3: MCP 端到端验收**

- `run_project` 启动，观察 60 秒：零 ERROR；气泡台词奶油风正常显示
- 点击猫 → 轮盘展开（6 圆钮弧形）→ 点「投食」→ 猫追食物开吃 + `action_selected` 链路正常
- 右缘猫爪圆钮 → 抽屉展开 → 「设置」→ 面板 6 页签逐页切换 → 改透明度即存即生效（猫与面板透明度实时变）
- 「专注」按钮 → 专注会话启动（HUD 奶油风）→ 托盘结束
- 「存档」→ 面板跳「关于」页 → 导出/导入按钮弹出 FileDialog
- 「关于」页 Credits 文字可见
- `stop_project`

- [ ] **Step 4: 视觉走查**

MCP 截图核查：设置面板奶油底/圆角/暖棕字、轮盘正圆粉描边、气泡描边尾巴、无 aurora 暗皮残留。

- [ ] **Step 5: 更新主计划文档 + 勾选本计划复选框**

`docs/plans/2026-08-17-smart-companion-redesign.md` 追加 P7 完成记录（对齐 P5/P6 格式）；本文件全部勾选。

- [ ] **Step 6: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p7-ui-cream-redesign.md
git commit -m "docs: P7 完成记录"
```

---

## 附：执行提示

- Task 1-8 强顺序（主题 → 骨架 → 逐页 → 独立组件 → 接线 → 清理）；Task 6/7 可互换
- 旧 settings_panel.gd 有 569 行逻辑——Task 2 重写前先通读旧文件把 22 键 collect/apply 的键值语义抄对，宁可搬旧逻辑不要凭记忆重写
- 三处「已核实」接口（set_timed_hide_option / export_to_file+import_from_file / reset_data）行号写在计划内，直接用不再查
- main.gd 改动每步后 headless 冒烟（`timeout 20`），脚本错误早发现
- Godot 4.7 lambda 多行体缩进敏感（Task 5 reset 确认弹窗、Task 7 hover lambda）——复制时保持整体右缩
- 删文件必须在 Task 9（引用清零后才删，中途删会炸启动）
