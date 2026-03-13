extends Panel

@onready var opacity_slider: HSlider = $VBoxContainer/OpacitySlider
@onready var always_on_top_check: CheckBox = $VBoxContainer/AlwaysOnTopCheck
@onready var timed_hide_option: OptionButton = $VBoxContainer/TimedHideOption
@onready var timed_hide_remaining_label: Label = $VBoxContainer/TimedHideRemainingLabel
@onready var timed_hide_update_timer: Timer = $TimedHideUpdateTimer
@onready var intensity_option: OptionButton = $VBoxContainer/IntensityOption
@onready var sound_check: CheckBox = $VBoxContainer/SoundCheck
@onready var bgm_check: CheckBox = $VBoxContainer/BGMCheck
@onready var volume_slider: HSlider = $VBoxContainer/VolumeSlider
@onready var smart_mode_check: CheckBox = $VBoxContainer/SmartModeCheck
@onready var llm_enabled_check: CheckBox = $VBoxContainer/LLMEnabledCheck
@onready var personality_option: OptionButton = $VBoxContainer/PersonalityOption
@onready var reminder_intensity_option: OptionButton = $VBoxContainer/ReminderIntensityOption
@onready var quiet_start_spin: SpinBox = $VBoxContainer/QuietHoursRow/QuietStartSpin
@onready var quiet_end_spin: SpinBox = $VBoxContainer/QuietHoursRow/QuietEndSpin
@onready var save_manager_button: Button = $VBoxContainer/SaveManagerButton

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

	if reminder_intensity_option.get_item_count() == 0:
		reminder_intensity_option.add_item("低")
		reminder_intensity_option.add_item("中")
		reminder_intensity_option.add_item("高")

	var data = SaveManager.load_data()
	var settings = data.get("settings", {})
	var opacity_value = settings.get("opacity", opacity_slider.value)
	opacity_slider.value = opacity_value
	_apply_opacity(opacity_value)
	always_on_top_check.button_pressed = settings.get("always_on_top", always_on_top_check.button_pressed)
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
	llm_enabled_check.button_pressed = bool(settings.get("llm_enabled", false))
	_set_option_value(personality_option, _personality_to_index(String(settings.get("personality", "tsundere"))))
	_set_option_value(reminder_intensity_option, _reminder_to_index(String(settings.get("reminder_intensity", "medium"))))
	_set_spin_value(quiet_start_spin, float(settings.get("quiet_hours_start", 23)))
	_set_spin_value(quiet_end_spin, float(settings.get("quiet_hours_end", 8)))

	AudioManager.sound_enabled = sound_check.button_pressed
	AudioManager.bgm_enabled = bgm_check.button_pressed
	AudioManager.set_volume(volume_slider.value)
	_apply_smart_settings()

	opacity_slider.value_changed.connect(_on_opacity_changed)
	always_on_top_check.toggled.connect(_on_always_on_top_toggled)
	intensity_option.item_selected.connect(_on_intensity_selected)
	timed_hide_option.item_selected.connect(_on_timed_hide_selected)
	sound_check.toggled.connect(_on_sound_toggled)
	bgm_check.toggled.connect(_on_bgm_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)
	smart_mode_check.toggled.connect(_on_smart_mode_toggled)
	llm_enabled_check.toggled.connect(_on_llm_enabled_toggled)
	personality_option.item_selected.connect(_on_personality_selected)
	reminder_intensity_option.item_selected.connect(_on_reminder_intensity_selected)
	quiet_start_spin.value_changed.connect(_on_quiet_hours_changed)
	quiet_end_spin.value_changed.connect(_on_quiet_hours_changed)
	if save_manager_button and not save_manager_button.pressed.is_connected(_on_save_manager_pressed):
		save_manager_button.pressed.connect(_on_save_manager_pressed)
	if timed_hide_update_timer and not timed_hide_update_timer.timeout.is_connected(_on_timed_hide_update_timer):
		timed_hide_update_timer.timeout.connect(_on_timed_hide_update_timer)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

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

func _on_llm_enabled_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_personality_selected(_index: int) -> void:
	_apply_smart_settings()
	SaveManager.save_data()

func _on_reminder_intensity_selected(_index: int) -> void:
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
	_set_option_value(personality_option, _personality_to_index(String(settings.get("personality", "tsundere"))))
	_set_option_value(reminder_intensity_option, _reminder_to_index(String(settings.get("reminder_intensity", "medium"))))
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

func _reminder_to_index(value: String) -> int:
	match value:
		"low":
			return 0
		"high":
			return 2
		_:
			return 1

func _index_to_reminder(index: int) -> String:
	match index:
		0:
			return "low"
		2:
			return "high"
		_:
			return "medium"

func _apply_smart_settings() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main:
		return
	var smart = main.get_node_or_null("SmartPetController")
	if smart and smart.has_method("configure"):
		smart.configure({
			"smart_mode": smart_mode_check.button_pressed,
			"llm_enabled": llm_enabled_check.button_pressed,
			"data_collection_level": "minimal",
			"personality": _index_to_personality(personality_option.selected),
			"reminder_intensity": _index_to_reminder(reminder_intensity_option.selected),
			"quiet_hours_start": int(round(quiet_start_spin.value)),
			"quiet_hours_end": int(round(quiet_end_spin.value))
		})
