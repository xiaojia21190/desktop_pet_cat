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

# —— 各页控件引用 ——
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
	timed_hide_update_timer.start()
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
