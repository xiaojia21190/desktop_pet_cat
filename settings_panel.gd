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

# —— 页构建：外观 ——
func _build_page_appearance() -> void:
	var page: VBoxContainer = _pages["外观"]

	_section_label(page, "透明度")
	opacity_slider = _make_slider(page, 0.2, 1.0, 0.05)
	opacity_slider.value_changed.connect(_on_opacity_changed)

	_section_label(page, "猫咪大小")
	cat_scale_slider = _make_slider(page, 0.6, 2.0, 0.1)

	always_on_top_check = _make_check(page, "窗口置顶")
	always_on_top_check.toggled.connect(_on_always_on_top_toggled)
	auto_start_check = _make_check(page, "开机自启")
	auto_start_check.toggled.connect(_on_auto_start_toggled)

	_section_label(page, "定时隐藏")
	timed_hide_option = OptionButton.new()
	for opt in ["关闭", "15分钟", "30分钟", "1小时", "2小时"]:
		timed_hide_option.add_item(opt)
	timed_hide_option.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
	timed_hide_option.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
	timed_hide_option.add_theme_color_override("font_color", UiThemeScript.TEXT)
	timed_hide_option.item_selected.connect(_on_timed_hide_selected)
	page.add_child(timed_hide_option)
	timed_hide_remaining_label = Label.new()
	timed_hide_remaining_label.visible = false
	UiThemeScript.tint_label(timed_hide_remaining_label, "caption")
	page.add_child(timed_hide_remaining_label)

# —— 页构建：声音 ——
func _build_page_sound() -> void:
	var page: VBoxContainer = _pages["声音"]
	sound_check = _make_check(page, "音效")
	sound_check.toggled.connect(_on_sound_toggled)
	bgm_check = _make_check(page, "背景音乐")
	bgm_check.toggled.connect(_on_bgm_toggled)
	_section_label(page, "音量")
	volume_slider = _make_slider(page, 0.0, 1.0, 0.05)
	volume_slider.value_changed.connect(_on_volume_changed)

# —— 共享构建 helper ——
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
	check.add_theme_stylebox_override("hover", UiThemeScript.check_style(false))
	check.add_theme_color_override("font_color", UiThemeScript.TEXT)
	parent.add_child(check)
	return check

func _make_option(parent: Container) -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
	option.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
	option.add_theme_color_override("font_color", UiThemeScript.TEXT)
	parent.add_child(option)
	return option

# —— 外观/声音 handler（改即存）——
func _on_opacity_changed(value: float) -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main is CanvasItem:
		var color: Color = main.modulate
		color.a = value
		main.modulate = color
	SaveManager.save_data()

func _on_always_on_top_toggled(enabled: bool) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
	SaveManager.save_data()

func _on_auto_start_toggled(enabled: bool) -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.has_method("set_auto_start"):
		main.set_auto_start(enabled)
	SaveManager.save_data()

func _on_timed_hide_selected(index: int) -> void:
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

func set_cat_scale(value: float) -> void:
	if cat_scale_slider:
		cat_scale_slider.set_value_no_signal(value)

func _update_timed_hide_remaining() -> void:
	if not timed_hide_remaining_label:
		return
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main or not main.has_method("get_timed_hide_remaining_seconds"):
		timed_hide_remaining_label.visible = false
		return
	var remaining = int(main.get_timed_hide_remaining_seconds())
	if remaining <= 0:
		timed_hide_remaining_label.visible = false
		return
	timed_hide_remaining_label.visible = true
	timed_hide_remaining_label.text = "剩余时间: " + _format_duration(remaining)

func _format_duration(seconds: int) -> String:
	var minutes := seconds / 60
	var secs := seconds % 60
	@warning_ignore("integer_division")
	return "%d:%02d" % [minutes, secs]

# —— 页构建：猫性格 ——
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

# —— 页构建：智能 ——
func _build_page_smart() -> void:
	var page: VBoxContainer = _pages["智能"]
	smart_mode_check = _make_check(page, "智能模式（SMART）")
	smart_mode_check.toggled.connect(_on_smart_mode_toggled)
	perception_check = _make_check(page, "感知前台应用")
	perception_check.toggled.connect(_on_perception_toggled)
	perception_default_rules_check = _make_check(page, "使用默认分类规则")
	perception_default_rules_check.toggled.connect(_on_rules_toggled)

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
	quiet_start_spin.value_changed.connect(_on_quiet_hours_changed)
	quiet_end_spin.value_changed.connect(_on_quiet_hours_changed)

	_section_label(page, "专注会话时长")
	focus_duration_option = _make_option(page)
	for opt in ["15 分钟", "30 分钟", "60 分钟"]:
		focus_duration_option.add_item(opt)
	focus_duration_option.item_selected.connect(_on_focus_duration_selected)

	_section_label(page, "LLM 大模型")
	llm_enabled_check = _make_check(page, "启用 LLM（无 Key 时用模板台词）")
	llm_enabled_check.toggled.connect(_on_llm_enabled_toggled)
	llm_endpoint_input = _make_line(page, "API 端点")
	llm_endpoint_input.text_changed.connect(_on_llm_field_changed)
	llm_model_input = _make_line(page, "模型名")
	llm_model_input.text_changed.connect(_on_llm_field_changed)
	llm_api_key_input = _make_line(page, "API Key")
	llm_api_key_input.secret = true
	llm_api_key_input.text_changed.connect(_on_llm_field_changed)
	llm_api_env_input = _make_line(page, "环境变量名（优先读取）")
	llm_api_env_input.text_changed.connect(_on_llm_field_changed)

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

# —— 性格/智能 handler ——
func _on_smart_mode_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_perception_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_rules_toggled(_enabled: bool) -> void:
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

func _on_llm_field_changed(_value: String) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _apply_smart_settings() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.smart_pet_controller and main.smart_pet_controller.has_method("configure"):
		main.smart_pet_controller.configure(collect_settings())

# —— 品种锁（P5 逻辑照搬）——
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

func _on_cat_breed_selected(index: int) -> void:
	var breed_id := CAT_BREED_IDS[clampi(index, 0, CAT_BREED_IDS.size() - 1)]
	var bond_level := _get_bond_level()
	var need: int = int(BREED_LOCK_LEVELS.get(breed_id, 1))
	if bond_level < need:
		# 未解锁品种拦截：回退当前品种
		var main = get_tree().get_root().get_node_or_null("Main")
		var current := String(main.cat.current_cat_type) if main and main.cat else "orange_tabby"
		cat_breed_option.select(maxi(CAT_BREED_IDS.find(current), 0))
		return
	_apply_cat_breed()
	SaveManager.save_data()

func _apply_cat_breed() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.animation_component:
		var breed_id := CAT_BREED_IDS[clampi(cat_breed_option.selected, 0, CAT_BREED_IDS.size() - 1)]
		main.cat.animation_component.switch_cat_type(breed_id)

func _get_bond_level() -> int:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.bond_system:
		return main.cat.bond_system.get_level()
	return 1

# —— 页构建：任务·亲密度（P5/P6 区块承接）——
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

# —— 页构建：关于（存档管理承接 save_manager_panel 四功能）——
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
	row.add_child(export_btn)
	var import_btn := Button.new()
	import_btn.text = "导入"
	row.add_child(import_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置存档"
	reset_btn.add_theme_color_override("font_color", UiThemeScript.DANGER)
	row.add_child(reset_btn)
	_style_btn_row([export_btn, import_btn, reset_btn])

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.catpet ; 桌宠猫存档"])
	add_child(_export_dialog)
	_export_dialog.file_selected.connect(_on_export_selected)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.catpet ; 桌宠猫存档"])
	add_child(_import_dialog)
	_import_dialog.file_selected.connect(_on_import_selected)
	export_btn.pressed.connect(func(): _export_dialog.popup_centered_ratio())
	import_btn.pressed.connect(func(): _import_dialog.popup_centered_ratio())
	reset_btn.pressed.connect(_on_reset_pressed)

func _style_btn_row(buttons: Array) -> void:
	for btn in buttons:
		btn.add_theme_stylebox_override("normal", UiThemeScript.btn_style())
		btn.add_theme_stylebox_override("hover", UiThemeScript.btn_style(true))
		btn.add_theme_color_override("font_color", UiThemeScript.TEXT)

func _on_reset_pressed() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "确定要重置存档吗？这将清除所有数据并恢复默认。"
	add_child(confirm)
	confirm.confirmed.connect(func():
		SaveManager.reset_data()
		confirm.queue_free())
	confirm.close_requested.connect(func(): confirm.queue_free())
	confirm.popup_centered()

func _on_export_selected(path: String) -> void:
	if SaveManager.export_to_file(path):
		_status_label.text = "✓ 导出成功"
	else:
		_status_label.text = "✗ 导出失败"
	_refresh_save_info()

func _on_import_selected(path: String) -> void:
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

func _on_visibility_changed() -> void:
	if visible:
		_on_timed_hide_update_timer()
		refresh_breed_locks(_get_bond_level())
		refresh_bond_ui()
		refresh_quest_ui()
		_refresh_save_info()

# —— 对外接口占位（Task 3-5 逐个补实现）——
func apply_settings(settings: Dictionary) -> void:
	if settings.has("opacity"):
		opacity_slider.set_value_no_signal(float(settings["opacity"]))
	always_on_top_check.button_pressed = bool(settings.get("always_on_top", true))
	auto_start_check.button_pressed = bool(settings.get("auto_start", false))
	timed_hide_option.select(int(settings.get("timed_hide_option", 0)))
	sound_check.button_pressed = bool(settings.get("sound_enabled", true))
	bgm_check.button_pressed = bool(settings.get("bgm_enabled", true))
	volume_slider.set_value_no_signal(float(settings.get("volume", 1.0)))
	if settings.has("cat_scale"):
		cat_scale_slider.set_value_no_signal(float(settings["cat_scale"]))
	var breed_index: int = CAT_BREED_IDS.find(String(settings.get("cat_type", "orange_tabby")))
	cat_breed_option.select(maxi(breed_index, 0))
	personality_option.select(_personality_to_index(String(settings.get("personality", "tsundere"))))
	intensity_option.select(int(settings.get("intensity", 1)))
	smart_mode_check.button_pressed = bool(settings.get("smart_mode", true))
	perception_check.button_pressed = bool(settings.get("perception_enabled", false))
	perception_default_rules_check.button_pressed = bool(settings.get("perception_default_rules", true))
	presence_level_option.select(clampi(int(settings.get("presence_level", 2)), 0, 4))
	quiet_start_spin.set_value_no_signal(float(settings.get("quiet_hours_start", 23)))
	quiet_end_spin.set_value_no_signal(float(settings.get("quiet_hours_end", 8)))
	focus_duration_option.select(clampi(int(settings.get("focus_duration_index", 1)), 0, 2))
	llm_enabled_check.button_pressed = bool(settings.get("llm_enabled", false))
	llm_endpoint_input.text = String(settings.get("llm_endpoint", DEFAULT_LLM_ENDPOINT))
	llm_model_input.text = String(settings.get("llm_model", "gpt-4o-mini"))
	llm_api_key_input.text = String(settings.get("llm_api_key", ""))
	llm_api_env_input.text = String(settings.get("llm_api_key_env", "OPENAI_API_KEY"))

func collect_settings() -> Dictionary:
	var settings: Dictionary = {}
	settings["opacity"] = opacity_slider.value
	settings["always_on_top"] = always_on_top_check.button_pressed
	settings["timed_hide_option"] = timed_hide_option.selected
	settings["sound_enabled"] = sound_check.button_pressed
	settings["bgm_enabled"] = bgm_check.button_pressed
	settings["volume"] = volume_slider.value
	settings["cat_scale"] = cat_scale_slider.value
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
	return settings

func _personality_to_index(value: String) -> int:
	match value:
		"gentle":
			return 1
		"playful":
			return 2
		_:
			return 0

func set_timed_hide_option(index: int) -> void:
	timed_hide_option.select(index)

func _on_timed_hide_update_timer() -> void:
	if not visible:
		return
	_update_timed_hide_remaining()

func _on_close_pressed() -> void:
	visible = false
