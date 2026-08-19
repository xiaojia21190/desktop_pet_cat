extends Panel

@onready var opacity_slider: HSlider = $ScrollContainer/VBoxContainer/OpacitySlider
@onready var always_on_top_check: CheckBox = $ScrollContainer/VBoxContainer/AlwaysOnTopCheck
@onready var auto_start_check: CheckBox = $ScrollContainer/VBoxContainer/AutoStartCheck
@onready var timed_hide_option: OptionButton = $ScrollContainer/VBoxContainer/TimedHideOption
@onready var timed_hide_remaining_label: Label = $ScrollContainer/VBoxContainer/TimedHideRemainingLabel
@onready var timed_hide_update_timer: Timer = $TimedHideUpdateTimer
@onready var intensity_option: OptionButton = $ScrollContainer/VBoxContainer/IntensityOption
@onready var sound_check: CheckBox = $ScrollContainer/VBoxContainer/SoundCheck
@onready var bgm_check: CheckBox = $ScrollContainer/VBoxContainer/BGMCheck
@onready var volume_slider: HSlider = $ScrollContainer/VBoxContainer/VolumeSlider
@onready var smart_mode_check: CheckBox = $ScrollContainer/VBoxContainer/SmartModeCheck
@onready var perception_check: CheckBox = $ScrollContainer/VBoxContainer/PerceptionCheck
@onready var perception_default_rules_check: CheckBox = $ScrollContainer/VBoxContainer/PerceptionDefaultRulesCheck
@onready var focus_duration_option: OptionButton = $ScrollContainer/VBoxContainer/FocusDurationOption
@onready var cat_breed_option: OptionButton = $ScrollContainer/VBoxContainer/CatBreedOption
@onready var llm_enabled_check: CheckBox = $ScrollContainer/VBoxContainer/LLMEnabledCheck
@onready var llm_endpoint_input: LineEdit = $ScrollContainer/VBoxContainer/LLMEndpointInput
@onready var llm_model_input: LineEdit = $ScrollContainer/VBoxContainer/LLMModelInput
@onready var llm_api_env_input: LineEdit = $ScrollContainer/VBoxContainer/LLMApiEnvInput
@onready var llm_api_key_input: LineEdit = $ScrollContainer/VBoxContainer/LLMApiKeyInput
@onready var personality_option: OptionButton = $ScrollContainer/VBoxContainer/PersonalityOption
@onready var presence_level_option: OptionButton = $ScrollContainer/VBoxContainer/PresenceLevelOption
@onready var quiet_start_spin: SpinBox = $ScrollContainer/VBoxContainer/QuietHoursRow/QuietStartSpin
@onready var quiet_end_spin: SpinBox = $ScrollContainer/VBoxContainer/QuietHoursRow/QuietEndSpin
@onready var save_manager_button: Button = $ScrollContainer/VBoxContainer/SaveManagerButton
@onready var close_button: Button = $CloseButton

const DEFAULT_LLM_ENDPOINT := "https://api.openai.com/v1/chat/completions"
const DEFAULT_LLM_MODEL := "gpt-4o-mini"
const DEFAULT_LLM_API_ENV := "OPENAI_API_KEY"
const AUTO_START_MGR = preload("res://components/desktop/auto_start_manager.gd")

var save_manager_panel: PopupPanel

func _ready():
	if intensity_option.get_item_count() == 0:
		intensity_option.add_item("低")
		intensity_option.add_item("中")
		intensity_option.add_item("高")
		intensity_option.select(1)
	elif intensity_option.get_item_count() > 1:
		intensity_option.select(1)

	if timed_hide_option.get_item_count() == 0:
		timed_hide_option.add_item("关闭")
		timed_hide_option.add_item("15分钟")
		timed_hide_option.add_item("30分钟")
		timed_hide_option.add_item("1小时")
		timed_hide_option.add_item("2小时")

	if personality_option.get_item_count() == 0:
		personality_option.add_item("傲娇")
		personality_option.add_item("温柔")
		personality_option.add_item("活泼")

	if presence_level_option.get_item_count() == 0:
		presence_level_option.add_item("安静（≤1句/小时）")
		presence_level_option.add_item("低频（关键时刻）")
		presence_level_option.add_item("中频（工位同事）")
		presence_level_option.add_item("高频（话痨猫）")
		presence_level_option.add_item("智能（按活动自适应）")
		presence_level_option.select(2)

	var data = SaveManager.load_data()
	var settings = data.get("settings", {})
	var opacity_value = settings.get("opacity", opacity_slider.value)
	opacity_slider.value = opacity_value
	_apply_opacity(opacity_value)
	always_on_top_check.button_pressed = settings.get("always_on_top", always_on_top_check.button_pressed)
	# 开机自启:读注册表实际状态(真实来源),编辑器下禁用提示
	auto_start_check.button_pressed = AUTO_START_MGR.is_enabled()
	auto_start_check.disabled = not AUTO_START_MGR.get_exe_path().get_file().begins_with("DesktopPetCat")
	if auto_start_check.disabled:
		auto_start_check.text = "开机自动启动（需导出 exe）"
	intensity_option.select(settings.get("intensity", 1))
	var timed_hide_index = int(settings.get("timed_hide_option", 0))
	if timed_hide_index < 0 or timed_hide_index >= timed_hide_option.get_item_count():
		timed_hide_index = 0
	if timed_hide_option.get_item_count() > 0:
		timed_hide_option.select(timed_hide_index)
	sound_check.button_pressed = settings.get("sound_enabled", sound_check.button_pressed)
	bgm_check.button_pressed = settings.get("bgm_enabled", bgm_check.button_pressed)
	volume_slider.value = settings.get("volume", volume_slider.value)
	smart_mode_check.button_pressed = bool(settings.get("smart_mode", true))
	perception_check.button_pressed = bool(settings.get("perception_enabled", false))
	perception_default_rules_check.button_pressed = bool(settings.get("perception_default_rules", true))
	var focus_duration_index := int(settings.get("focus_duration_index", 1))
	focus_duration_option.select(clampi(focus_duration_index, 0, 2))
	var breed_index: int = CAT_BREED_IDS.find(String(settings.get("cat_type", "orange_tabby")))
	cat_breed_option.select(maxi(breed_index, 0))
	llm_enabled_check.button_pressed = bool(settings.get("llm_enabled", false))
	llm_endpoint_input.text = String(settings.get("llm_endpoint", DEFAULT_LLM_ENDPOINT))
	llm_model_input.text = String(settings.get("llm_model", DEFAULT_LLM_MODEL))
	llm_api_env_input.text = String(settings.get("llm_api_key_env", DEFAULT_LLM_API_ENV))
	llm_api_key_input.text = String(settings.get("llm_api_key", ""))
	_set_option_value(personality_option, _personality_to_index(String(settings.get("personality", "tsundere"))))
	presence_level_option.select(clampi(int(settings.get("presence_level", 2)), 0, 4))
	_set_spin_value(quiet_start_spin, float(settings.get("quiet_hours_start", 23)))
	_set_spin_value(quiet_end_spin, float(settings.get("quiet_hours_end", 8)))

	AudioManager.sound_enabled = sound_check.button_pressed
	AudioManager.bgm_enabled = bgm_check.button_pressed
	AudioManager.set_volume(volume_slider.value)
	_apply_smart_settings()

	opacity_slider.value_changed.connect(_on_opacity_changed)
	always_on_top_check.toggled.connect(_on_always_on_top_toggled)
	auto_start_check.toggled.connect(_on_auto_start_toggled)
	intensity_option.item_selected.connect(_on_intensity_selected)
	timed_hide_option.item_selected.connect(_on_timed_hide_selected)
	sound_check.toggled.connect(_on_sound_toggled)
	bgm_check.toggled.connect(_on_bgm_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)
	smart_mode_check.toggled.connect(_on_smart_mode_toggled)
	perception_check.toggled.connect(_on_perception_toggled)
	perception_default_rules_check.toggled.connect(_on_perception_toggled)
	focus_duration_option.item_selected.connect(_on_focus_duration_selected)
	cat_breed_option.item_selected.connect(_on_cat_breed_selected)
	llm_enabled_check.toggled.connect(_on_llm_enabled_toggled)
	llm_endpoint_input.text_changed.connect(_on_llm_endpoint_changed)
	llm_model_input.text_changed.connect(_on_llm_model_changed)
	llm_api_env_input.text_changed.connect(_on_llm_api_env_changed)
	llm_api_key_input.text_changed.connect(_on_llm_api_key_changed)
	personality_option.item_selected.connect(_on_personality_selected)
	presence_level_option.item_selected.connect(_on_presence_level_selected)
	quiet_start_spin.value_changed.connect(_on_quiet_hours_changed)
	quiet_end_spin.value_changed.connect(_on_quiet_hours_changed)
	if save_manager_button and not save_manager_button.pressed.is_connected(_on_save_manager_pressed):
		save_manager_button.pressed.connect(_on_save_manager_pressed)
	if timed_hide_update_timer and not timed_hide_update_timer.timeout.is_connected(_on_timed_hide_update_timer):
		timed_hide_update_timer.timeout.connect(_on_timed_hide_update_timer)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if not save_manager_panel:
		var panel_scene = load("res://save_manager_panel.tscn")
		if panel_scene:
			save_manager_panel = panel_scene.instantiate()
			add_child(save_manager_panel)

	_update_timed_hide_remaining()

func _apply_opacity(value):
	var parent_node = get_parent()
	if parent_node and parent_node is CanvasItem:
		var color = parent_node.modulate
		color.a = value
		parent_node.modulate = color

func _on_opacity_changed(value):
	_apply_opacity(value)
	SaveManager.save_data()

func _on_always_on_top_toggled(enabled):
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
	SaveManager.save_data()

func _on_auto_start_toggled(enabled):
	# 写/删注册表 Run 键;失败(如编辑器运行)则回弹
	if AUTO_START_MGR.set_enabled(enabled):
		auto_start_check.button_pressed = AUTO_START_MGR.is_enabled()
	else:
		auto_start_check.button_pressed = false

func _on_intensity_selected(index):
	SaveManager.set_cat_intensity(index)
	SaveManager.save_data()

func _on_timed_hide_selected(index):
	SaveManager.set_timed_hide_option(index)
	SaveManager.save_data()
	_update_timed_hide_remaining()

func _on_timed_hide_update_timer():
	if not visible:
		return
	_update_timed_hide_remaining()

func _on_visibility_changed():
	if visible:
		_update_timed_hide_remaining()
		# 面板每次打开刷新品种解锁状态
		refresh_breed_locks(_get_bond_level())
		refresh_bond_ui()
		refresh_quest_ui()

## P5c：亲密度进度区（等级 + 进度 + 下一级解锁预告），代码构建
var _bond_level_label: Label
var _bond_progress_bar: ProgressBar

func _ensure_bond_ui() -> void:
	if _bond_level_label:
		return
	var vbox = get_node_or_null("ScrollContainer/VBoxContainer")
	if not vbox:
		return
	_bond_level_label = Label.new()
	_bond_level_label.name = "BondLevelLabel"
	_bond_level_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_bond_level_label)
	_bond_progress_bar = ProgressBar.new()
	_bond_progress_bar.name = "BondProgressBar"
	_bond_progress_bar.min_value = 0.0
	_bond_progress_bar.max_value = 100.0
	_bond_progress_bar.show_percentage = false
	_bond_progress_bar.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(_bond_progress_bar)

func refresh_bond_ui() -> void:
	# 亲密度等级/进度刷新（面板打开时与 bond 变化时调用）
	_ensure_bond_ui()
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

## P6：今日任务区块（任务列表 + 连续签到），代码构建 + visible 才刷
var _quest_title_label: Label
var _quest_rows: Array = []  # [{label: Label, quest_id: String}]
var _quest_streak_label: Label

func _ensure_quest_ui() -> void:
	if _quest_title_label:
		return
	var vbox = get_node_or_null("ScrollContainer/VBoxContainer")
	if not vbox:
		return
	_quest_title_label = Label.new()
	_quest_title_label.name = "QuestTitleLabel"
	_quest_title_label.text = "今日任务"
	_quest_title_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_quest_title_label)
	var main = get_tree().get_root().get_node_or_null("Main")
	var quest_defs: Dictionary = {}
	if main and main.daily_quest_service:
		quest_defs = main.daily_quest_service.QUEST_DEFS
	for qid in quest_defs:
		var row = Label.new()
		row.name = "QuestRow_" + String(qid)
		row.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		vbox.add_child(row)
		_quest_rows.append({"label": row, "quest_id": String(qid)})
	_quest_streak_label = Label.new()
	_quest_streak_label.name = "QuestStreakLabel"
	_quest_streak_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_quest_streak_label)

func refresh_quest_ui() -> void:
	_ensure_quest_ui()
	if not _quest_title_label:
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

func _update_timed_hide_remaining():
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
	var total = max(seconds, 0)
	var hours = total / 3600
	var minutes = (total % 3600) / 60
	var secs = total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%d:%02d" % [minutes, secs]

func set_timed_hide_option(index: int) -> void:
	if timed_hide_option and timed_hide_option.get_item_count() > 0:
		var clamped = clampi(index, 0, timed_hide_option.get_item_count() - 1)
		timed_hide_option.select(clamped)
	_update_timed_hide_remaining()

func _on_sound_toggled(enabled):
	AudioManager.sound_enabled = enabled
	SaveManager.save_data()

func _on_bgm_toggled(enabled):
	AudioManager.bgm_enabled = enabled
	if AudioManager.bgm_player:
		if enabled:
			if AudioManager.bgm_player.stream and not AudioManager.bgm_player.playing:
				AudioManager.bgm_player.play()
		else:
			AudioManager.bgm_player.stop()
	SaveManager.save_data()

func _on_volume_changed(value):
	AudioManager.set_volume(value)
	SaveManager.save_data()

func _on_smart_mode_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_perception_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

const FOCUS_DURATION_SECONDS := [15 * 60, 30 * 60, 60 * 60]
const CAT_BREED_IDS: Array[String] = ["orange_tabby", "calico", "british_blue", "tuxedo"]
## 品种解锁所需亲密度等级(bond_system 等级对齐);orange_tabby 初始解锁
const CAT_BREED_UNLOCK_LEVEL := {"orange_tabby": 1, "calico": 3, "british_blue": 4, "tuxedo": 5}

## 按当前亲密度等级刷新品种选项文案(未解锁显示 🔒)
func refresh_breed_locks(bond_level: int) -> void:
	var names := ["橘猫", "三花猫", "英短蓝猫", "燕尾服猫"]
	for i in CAT_BREED_IDS.size():
		var need: int = CAT_BREED_UNLOCK_LEVEL.get(CAT_BREED_IDS[i], 1)
		if bond_level >= need:
			cat_breed_option.set_item_text(i, names[i])
		else:
			cat_breed_option.set_item_text(i, "%s 🔒Lv%d" % [names[i], need])
	var selected_need: int = CAT_BREED_UNLOCK_LEVEL.get(
		CAT_BREED_IDS[clampi(cat_breed_option.selected, 0, CAT_BREED_IDS.size() - 1)], 1)
	if bond_level < selected_need:
		# 当前选中品种被锁(降级读档),回退橘猫
		cat_breed_option.select(0)
		_apply_cat_breed()

func _on_focus_duration_selected(_index: int) -> void:
	SaveManager.save_data()
	_apply_focus_duration()

func _on_cat_breed_selected(_index: int) -> void:
	# 未解锁品种不可选(锁定的选项文案带 🔒,此处拦截)
	var need: int = CAT_BREED_UNLOCK_LEVEL.get(
		CAT_BREED_IDS[clampi(_index, 0, CAT_BREED_IDS.size() - 1)], 1)
	var bond_level := _get_bond_level()
	if bond_level < need:
		cat_breed_option.select(0)  # 弹回橘猫
		return
	SaveManager.save_data()
	_apply_cat_breed()

func _get_bond_level() -> int:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.bond_system:
		return int(main.cat.bond_system.get_level())
	return 1

func _apply_cat_breed() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.cat and main.cat.animation_component:
		var breed_id: String = CAT_BREED_IDS[clampi(cat_breed_option.selected, 0, CAT_BREED_IDS.size() - 1)]
		main.cat.animation_component.switch_cat_type(breed_id)

func _apply_focus_duration() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.focus_session_mode:
		main.focus_session_mode.session_duration_seconds = FOCUS_DURATION_SECONDS[clampi(focus_duration_option.selected, 0, 2)]

func _on_llm_enabled_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_llm_endpoint_changed(_value: String) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_llm_model_changed(_value: String) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_llm_api_env_changed(_value: String) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_llm_api_key_changed(_value: String) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_personality_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_presence_level_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_quiet_hours_changed(_value: float) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_save_manager_pressed():
	if save_manager_panel and save_manager_panel.has_method("show_panel"):
		save_manager_panel.show_panel()
	elif save_manager_panel and save_manager_panel.has_method("popup_centered"):
		save_manager_panel.popup_centered()

func _on_close_pressed() -> void:
	visible = false

func apply_settings(settings: Dictionary) -> void:
	if settings.is_empty():
		return
	_set_slider_value(opacity_slider, settings.get("opacity", opacity_slider.value))
	_apply_opacity(opacity_slider.value)
	_set_check_value(always_on_top_check, settings.get("always_on_top", always_on_top_check.button_pressed))
	_set_option_value(intensity_option, settings.get("intensity", 1))
	_set_option_value(timed_hide_option, settings.get("timed_hide_option", 0))
	_set_check_value(sound_check, settings.get("sound_enabled", sound_check.button_pressed))
	_set_check_value(bgm_check, settings.get("bgm_enabled", bgm_check.button_pressed))
	_set_slider_value(volume_slider, settings.get("volume", volume_slider.value))
	_set_check_value(smart_mode_check, bool(settings.get("smart_mode", smart_mode_check.button_pressed)))
	_set_check_value(llm_enabled_check, bool(settings.get("llm_enabled", llm_enabled_check.button_pressed)))
	_set_line_edit_value(llm_endpoint_input, String(settings.get("llm_endpoint", llm_endpoint_input.text)))
	_set_line_edit_value(llm_model_input, String(settings.get("llm_model", llm_model_input.text)))
	_set_line_edit_value(llm_api_env_input, String(settings.get("llm_api_key_env", llm_api_env_input.text)))
	_set_line_edit_value(llm_api_key_input, String(settings.get("llm_api_key", llm_api_key_input.text)))
	_set_option_value(personality_option, _personality_to_index(String(settings.get("personality", "tsundere"))))
	presence_level_option.select(clampi(int(settings.get("presence_level", 2)), 0, 4))
	_set_spin_value(quiet_start_spin, float(settings.get("quiet_hours_start", quiet_start_spin.value)))
	_set_spin_value(quiet_end_spin, float(settings.get("quiet_hours_end", quiet_end_spin.value)))
	_apply_smart_settings()
	_update_timed_hide_remaining()

func _set_slider_value(slider: Range, value: float) -> void:
	if not slider:
		return
	slider.set_block_signals(true)
	slider.value = value
	slider.set_block_signals(false)

func _set_check_value(check: CheckBox, value: bool) -> void:
	if not check:
		return
	check.set_block_signals(true)
	check.button_pressed = value
	check.set_block_signals(false)

func _set_option_value(option: OptionButton, index: int) -> void:
	if not option or option.get_item_count() == 0:
		return
	var clamped = clampi(index, 0, option.get_item_count() - 1)
	option.set_block_signals(true)
	option.select(clamped)
	option.set_block_signals(false)

func _set_spin_value(spin: SpinBox, value: float) -> void:
	if not spin:
		return
	spin.set_block_signals(true)
	spin.value = clampf(value, spin.min_value, spin.max_value)
	spin.set_block_signals(false)

func _set_line_edit_value(line_edit: LineEdit, value: String) -> void:
	if not line_edit:
		return
	line_edit.set_block_signals(true)
	line_edit.text = value
	line_edit.set_block_signals(false)

## 收集面板全部设置项（供 SaveManager 通过注册的 provider 调用）
## 修复旧实现：save_manager 曾用错误路径 VBoxContainer/... 抓节点导致全部 null
func collect_settings() -> Dictionary:
	var settings: Dictionary = {}
	settings["opacity"] = opacity_slider.value
	settings["always_on_top"] = always_on_top_check.button_pressed
	settings["intensity"] = intensity_option.selected
	settings["timed_hide_option"] = timed_hide_option.selected
	settings["sound_enabled"] = sound_check.button_pressed
	settings["bgm_enabled"] = bgm_check.button_pressed
	settings["volume"] = volume_slider.value
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

func _index_to_personality(index: int) -> String:
	match index:
		1:
			return "gentle"
		2:
			return "playful"
		_:
			return "tsundere"

func _apply_smart_settings() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main:
		return
	var smart = main.get_node_or_null("SmartPetController")
	if smart and smart.has_method("configure"):
		smart.configure({
			"smart_mode": smart_mode_check.button_pressed,
		"perception_enabled": perception_check.button_pressed,
		"perception_default_rules": perception_default_rules_check.button_pressed,
			"llm_enabled": llm_enabled_check.button_pressed,
			"llm_endpoint": llm_endpoint_input.text.strip_edges(),
			"llm_model": llm_model_input.text.strip_edges(),
			"llm_api_key_env": llm_api_env_input.text.strip_edges(),
			"llm_api_key": llm_api_key_input.text.strip_edges(),
			"llm_timeout_seconds": 10.0,
			"data_collection_level": "minimal",
			"personality": _index_to_personality(personality_option.selected),
			"presence_level": clampi(presence_level_option.selected, 0, 4),
			"quiet_hours_start": int(round(quiet_start_spin.value)),
			"quiet_hours_end": int(round(quiet_end_spin.value))
		})
	_apply_focus_duration()
