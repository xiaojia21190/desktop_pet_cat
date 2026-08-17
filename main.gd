extends Node2D
@onready var cat = $Cat
@onready var typing_effect_overlay = $TypingEffectOverlay
const FOCUS_SESSION_MODE_SCRIPT := preload("res://focus_session_mode.gd")
const SMART_PET_CONTROLLER_SCRIPT := preload("res://smart_pet_controller.gd")
const QUICK_ACTION_MENU_SCRIPT := preload("res://quick_action_menu.gd")
var is_shaking = false
var shake_timer = 0.0
var shake_duration = 0.5
var shake_intensity = 10.0
var original_position = Vector2.ZERO
var popup_menu: PopupMenu
var popup_menu_items: PopupMenu
var last_menu_position = Vector2.ZERO
var settings_panel: Panel
var tray_indicator: StatusIndicator
var tray_menu: RID = RID()
var tray_menu_show_index := -1
var tray_last_click_time := 0
const TRAY_DOUBLE_CLICK_MS := 400
const TRAY_ICON_PATH := "res://icon.svg"
const POPUP_MENU_ITEMS_NAME := "items_menu"
const POPUP_MENU_ID_WAND := 0
const POPUP_MENU_ID_FOOD := 1
const POPUP_MENU_ID_SETTINGS := 10
const POPUP_MENU_ID_TOGGLE_VISIBILITY := 11
const POPUP_MENU_ID_EXIT := 12
const TIMED_HIDE_DURATIONS := [0, 15 * 60, 30 * 60, 60 * 60, 120 * 60]
var timed_hide_option := 0
var timed_hide_end_time := 0
var timed_hide_timer: Timer
var focus_session_mode
var smart_pet_controller
var quick_action_menu
var _build_failure_streak := 0
var smart_line_layer: CanvasLayer
var smart_line_panel: PanelContainer
var smart_line_label: Label
var smart_line_hide_timer: Timer
var _passthrough_cache_hash: int = 0

# 悬浮面板相关
var hover_panel: Panel
var hover_panel_visible = false
const EDGE_TRIGGER_DISTANCE = 20  # 边缘触发距离
const PANEL_SLIDE_SPEED = 800.0   # 面板滑动速度
var panel_target_x = 0.0
var _cached_screen_size: Vector2 = Vector2(1920, 1080)
const BUILD_FAILURE_STREAK_THRESHOLD := 2
const SMART_LINE_BUBBLE_WIDTH := 320.0
const SMART_LINE_BUBBLE_HEIGHT := 88.0
const CAT_HIT_RADIUS_MIN := 56.0
const CAT_HIT_RADIUS_MAX := 240.0
const FORCE_START_AT_BOTTOM_RIGHT := false

const ITEM_WAND_SCENE = preload("res://item_wand.tscn")
const ITEM_FOOD_SCENE = preload("res://item_food.tscn")
const CatStates = preload("res://cat_states.gd")

func _enter_tree():
	_apply_window_style()

func _ready():
	_apply_window_style()

	print("桌面宠物猫启动成功")
	original_position = position

	# 缓存屏幕尺寸并监听变化
	_cached_screen_size = get_viewport_rect().size
	get_tree().root.size_changed.connect(_on_screen_size_changed)

	if cat:
		cat.typing_attack_started.connect(_on_typing_attack_started)
		cat.cat_left_clicked.connect(_on_cat_left_clicked)

	_setup_timed_hide_timer()

	var data = SaveManager.load_data()
	SaveManager.apply_settings(data)
	var cat_data = data.get("cat", {})
	var meta = data.get("meta", {})
	_apply_initial_cat_position(meta, cat_data)
	var settings = data.get("settings", {})
	if settings.has("opacity"):
		var color = modulate
		color.a = settings["opacity"]
		modulate = color

	_build_popup_menu()

	# 创建悬浮功能面板（替代固定设置按钮）
	_create_hover_panel()

	var panel_scene = load("res://settings_panel.tscn")
	if panel_scene:
		settings_panel = panel_scene.instantiate()
		settings_panel.visible = false
		add_child(settings_panel)

	_setup_focus_session_mode()
	_setup_smart_pet_controller(settings)
	_setup_smart_line_bubble()
	_setup_quick_action_menu()
	_record_smart_event("session_resume")
	_setup_tray()
	_update_mouse_passthrough_region()
	_log_window_state()

func _apply_initial_cat_position(meta: Dictionary, cat_data: Dictionary) -> void:
	if not cat:
		return
	if FORCE_START_AT_BOTTOM_RIGHT:
		cat.position = _get_default_cat_position()
		return
	var has_saved_position := cat_data.has("position")
	var saved_position: Vector2 = Vector2.ZERO
	if has_saved_position:
		var raw_pos = cat_data["position"]
		if raw_pos is Vector2:
			saved_position = raw_pos
		elif raw_pos is Vector2i:
			saved_position = Vector2(raw_pos.x, raw_pos.y)

	var saved_at: int = int(meta.get("saved_at", 0))
	var need_default := (not has_saved_position) or saved_position == Vector2.ZERO or saved_at <= 0
	if need_default:
		cat.position = _get_default_cat_position()
	else:
		cat.position = _clamp_cat_position(saved_position)

func _exit_tree():
	_cleanup_tray()

func _apply_window_style() -> void:
	# 让透明区域真正透出桌面，避免出现黑色矩形背景。
	var viewport := get_viewport()
	if viewport:
		viewport.transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 0.0))

	var window := get_window()
	if window:
		window.mode = Window.MODE_WINDOWED
		window.borderless = true
		window.transparent = true
		window.always_on_top = true
		window.unresizable = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_fit_window_to_screen()

func _on_screen_size_changed():
	_cached_screen_size = get_viewport_rect().size
	# 更新悬浮面板位置
	if hover_panel:
		var panel_width = hover_panel.size.x
		var panel_height = hover_panel.size.y
		hover_panel.position.y = (_cached_screen_size.y - panel_height) / 2
		if not hover_panel_visible:
			hover_panel.position.x = _cached_screen_size.x
			panel_target_x = _cached_screen_size.x
	if smart_line_panel and smart_line_panel.visible:
		smart_line_panel.position = _get_smart_line_position()
	_update_mouse_passthrough_region()

func _process(delta):
	# 处理悬浮面板边缘检测
	_update_hover_panel(delta)

	# 处理抖动效果
	_update_shake(delta)
	if smart_line_panel and smart_line_panel.visible:
		smart_line_panel.position = _get_smart_line_position()
	_update_mouse_passthrough_region()

func _update_shake(delta):
	if not is_shaking:
		return

	shake_timer += delta
	var offset = Vector2(
		randf_range(-shake_intensity, shake_intensity),
		randf_range(-shake_intensity, shake_intensity)
	)
	position = original_position + offset
	var flicker = 0.6 + 0.4 * abs(sin(shake_timer * 40.0))
	modulate = Color(1.0, 1.0, 1.0, flicker)

	if shake_timer >= shake_duration:
		is_shaking = false
		shake_timer = 0.0
		position = original_position
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func _setup_timed_hide_timer():
	timed_hide_timer = Timer.new()
	timed_hide_timer.one_shot = true
	timed_hide_timer.timeout.connect(_on_timed_hide_timeout)
	add_child(timed_hide_timer)

func apply_timed_hide_settings(settings: Dictionary) -> void:
	var option_index = int(settings.get("timed_hide_option", 0))
	var end_time = int(settings.get("timed_hide_end_time", 0))
	if _get_timed_hide_duration(option_index) <= 0:
		timed_hide_option = 0
		timed_hide_end_time = 0
		_stop_timed_hide_timer()
		return
	var remaining = end_time - Time.get_unix_time_from_system()
	if remaining <= 0:
		timed_hide_option = 0
		timed_hide_end_time = 0
		_stop_timed_hide_timer()
		return
	timed_hide_option = option_index
	timed_hide_end_time = end_time
	_start_timed_hide_timer(float(remaining))

func set_timed_hide_option(option_index: int) -> void:
	var duration = _get_timed_hide_duration(option_index)
	if duration <= 0:
		timed_hide_option = 0
		timed_hide_end_time = 0
		_stop_timed_hide_timer()
		return
	timed_hide_option = option_index
	timed_hide_end_time = Time.get_unix_time_from_system() + duration
	_start_timed_hide_timer(float(duration))

func get_timed_hide_remaining_seconds() -> int:
	if timed_hide_end_time <= 0:
		return 0
	return maxi(timed_hide_end_time - Time.get_unix_time_from_system(), 0)

func get_timed_hide_save_data() -> Dictionary:
	return {
		"timed_hide_option": timed_hide_option,
		"timed_hide_end_time": timed_hide_end_time
	}

func _start_timed_hide_timer(duration_seconds: float):
	if not timed_hide_timer:
		return
	timed_hide_timer.stop()
	timed_hide_timer.wait_time = duration_seconds
	timed_hide_timer.start()

func _stop_timed_hide_timer():
	if timed_hide_timer:
		timed_hide_timer.stop()

func _get_timed_hide_duration(option_index: int) -> int:
	if option_index < 0 or option_index >= TIMED_HIDE_DURATIONS.size():
		return 0
	return TIMED_HIDE_DURATIONS[option_index]

func _on_timed_hide_timeout():
	timed_hide_end_time = 0
	if timed_hide_option != 0:
		timed_hide_option = 0
		_sync_timed_hide_panel()
		SaveManager.save_data()
	_record_smart_event("user_busy")
	_set_pet_visible(false)

func _sync_timed_hide_panel():
	if settings_panel and settings_panel.has_method("set_timed_hide_option"):
		settings_panel.set_timed_hide_option(timed_hide_option)

func _setup_focus_session_mode() -> void:
	if focus_session_mode:
		return

	focus_session_mode = FOCUS_SESSION_MODE_SCRIPT.new()
	add_child(focus_session_mode)
	focus_session_mode.session_finished.connect(_on_focus_session_finished)
	# 心理统一：会话的 affection/chaos 读写猫的行为系统
	if cat and cat.behavior_system:
		focus_session_mode.bind_behavior(cat.behavior_system)

	if cat and cat.state_machine and not cat.state_machine.state_changed.is_connected(_on_cat_state_changed):
		cat.state_machine.state_changed.connect(_on_cat_state_changed)

func _setup_smart_pet_controller(settings: Dictionary) -> void:
	if smart_pet_controller:
		return
	smart_pet_controller = SMART_PET_CONTROLLER_SCRIPT.new()
	smart_pet_controller.name = "SmartPetController"
	add_child(smart_pet_controller)
	smart_pet_controller.bind_nodes(self, cat)
	smart_pet_controller.configure(settings)
	smart_pet_controller.smart_action_requested.connect(_on_smart_action_requested)
	smart_pet_controller.smart_line_generated.connect(_on_smart_line_generated)

	var keyboard_listener := get_node_or_null("KeyboardListener")
	if keyboard_listener and not keyboard_listener.typing_detected.is_connected(_on_keyboard_typing_for_smart):
		keyboard_listener.typing_detected.connect(_on_keyboard_typing_for_smart)

func _on_typing_attack_started():
	AudioManager.play_typing_sound()
	is_shaking = true
	shake_timer = 0.0
	original_position = position
	_start_typing_effects()
	_record_smart_event("typing_burst")
	if smart_pet_controller:
		smart_pet_controller.record_typing()
	if focus_session_mode:
		focus_session_mode.on_typing_attack()

func _start_typing_effects() -> void:
	if not typing_effect_overlay or not cat:
		return

	var duration := _get_typing_attack_duration()
	typing_effect_overlay.start_effect(duration, cat)

func _get_typing_attack_duration() -> float:
	var default_duration := 1.5
	if not cat:
		return default_duration

	var state_machine = cat.state_machine
	if state_machine and state_machine.states.has(&"TypingAttack"):
		var typing_state = state_machine.states[&"TypingAttack"]
		if "attack_duration" in typing_state:
			return typing_state.attack_duration
	return default_duration

func _build_popup_menu():
	popup_menu = PopupMenu.new()
	add_child(popup_menu)

	popup_menu_items = PopupMenu.new()
	popup_menu_items.name = POPUP_MENU_ITEMS_NAME
	popup_menu.add_child(popup_menu_items)
	popup_menu_items.add_item("逗猫棒", POPUP_MENU_ID_WAND)
	popup_menu_items.add_item("零食", POPUP_MENU_ID_FOOD)
	popup_menu_items.id_pressed.connect(_on_popup_item_selected)

	popup_menu.add_submenu_item("道具", POPUP_MENU_ITEMS_NAME)
	popup_menu.add_separator()
	popup_menu.add_item("设置", POPUP_MENU_ID_SETTINGS)
	popup_menu.add_item(_get_visibility_label(), POPUP_MENU_ID_TOGGLE_VISIBILITY)
	popup_menu.add_separator()
	popup_menu.add_item("退出程序", POPUP_MENU_ID_EXIT)
	popup_menu.id_pressed.connect(_on_popup_menu_selected)

func _get_visibility_label() -> String:
	return "隐藏猫咪" if _is_pet_visible() else "显示猫咪"

func _update_visibility_menu_labels():
	_update_tray_menu_label()
	_update_popup_menu_label()

func _update_popup_menu_label():
	if not popup_menu:
		return

	var index = popup_menu.get_item_index(POPUP_MENU_ID_TOGGLE_VISIBILITY)
	if index < 0:
		return

	popup_menu.set_item_text(index, _get_visibility_label())

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if smart_pet_controller:
			smart_pet_controller.record_mouse_click()
		_record_smart_event("mouse_click", {"button": event.button_index})

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		last_menu_position = get_global_mouse_position()
		popup_menu.position = get_viewport().get_mouse_position()
		_update_popup_menu_label()
		popup_menu.popup()

func _on_popup_item_selected(id):
	if id == POPUP_MENU_ID_WAND:
		spawn_item("wand", last_menu_position)
	elif id == POPUP_MENU_ID_FOOD:
		spawn_item("food", last_menu_position)

func _on_popup_menu_selected(id):
	if id == POPUP_MENU_ID_SETTINGS:
		_on_tray_open_settings()
	elif id == POPUP_MENU_ID_TOGGLE_VISIBILITY:
		_toggle_pet_visibility()
	elif id == POPUP_MENU_ID_EXIT:
		_on_tray_exit()

func _create_hover_panel():
	var screen_size = _cached_screen_size
	var panel_width = 80
	var panel_height = 160

	hover_panel = Panel.new()
	hover_panel.size = Vector2(panel_width, panel_height)
	hover_panel.position = Vector2(screen_size.x, (screen_size.y - panel_height) / 2)
	panel_target_x = screen_size.x

	var aurora_tex := load("res://assets/aurora/panel_dark.png") as Texture2D
	if aurora_tex:
		var sb := StyleBoxTexture.new()
		sb.texture = aurora_tex
		sb.texture_margin_left = 20
		sb.texture_margin_top = 20
		sb.texture_margin_right = 20
		sb.texture_margin_bottom = 20
		sb.content_margin_left = 8.0
		sb.content_margin_top = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_bottom = 8.0
		hover_panel.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var margin_l := 8
	var margin_t := 12
	vbox.offset_left = margin_l
	vbox.offset_top = margin_t
	vbox.offset_right = -margin_l
	vbox.offset_bottom = -margin_t
	hover_panel.add_child(vbox)

	var btn_normal_style := _make_aurora_btn_style("res://assets/aurora/btn_normal.png")
	var btn_hover_style := _make_aurora_btn_style("res://assets/aurora/btn_hover.png")

	var items_btn = Button.new()
	items_btn.text = "道具"
	items_btn.add_theme_stylebox_override("normal", btn_normal_style)
	items_btn.add_theme_stylebox_override("hover", btn_hover_style)
	items_btn.add_theme_stylebox_override("pressed", btn_hover_style)
	items_btn.add_theme_color_override("font_color", Color.WHITE)
	items_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	items_btn.pressed.connect(_on_items_btn_pressed)
	vbox.add_child(items_btn)

	var settings_btn = Button.new()
	settings_btn.text = "设置"
	settings_btn.add_theme_stylebox_override("normal", btn_normal_style)
	settings_btn.add_theme_stylebox_override("hover", btn_hover_style)
	settings_btn.add_theme_stylebox_override("pressed", btn_hover_style)
	settings_btn.add_theme_color_override("font_color", Color.WHITE)
	settings_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	add_child(hover_panel)

func _update_hover_panel(delta):
	if not hover_panel:
		return

	var screen_size = _cached_screen_size
	var panel_width = hover_panel.size.x
	var current_x = hover_panel.position.x

	# 如果面板已到达目标位置且隐藏，跳过计算
	var is_at_target = abs(current_x - panel_target_x) <= 1
	if is_at_target and not hover_panel_visible:
		return

	var mouse_pos = get_global_mouse_position()

	# 检测鼠标是否在右边缘
	var near_edge = mouse_pos.x > screen_size.x - EDGE_TRIGGER_DISTANCE
	# 检测鼠标是否在面板上
	var on_panel = hover_panel.get_rect().has_point(mouse_pos)

	if near_edge or on_panel:
		# 显示面板（滑入）
		panel_target_x = screen_size.x - panel_width
		hover_panel_visible = true
	else:
		# 隐藏面板（滑出）
		panel_target_x = screen_size.x
		hover_panel_visible = false

	# 平滑滑动（仅在需要移动时计算）
	if not is_at_target:
		var direction = sign(panel_target_x - current_x)
		hover_panel.position.x += direction * PANEL_SLIDE_SPEED * delta
		hover_panel.position.x = clamp(hover_panel.position.x, screen_size.x - panel_width, screen_size.x)

func _on_items_btn_pressed():
	# 显示道具菜单
	if not popup_menu_items:
		return

	last_menu_position = get_global_mouse_position()
	var mouse_pos = get_viewport().get_mouse_position()
	popup_menu_items.position = mouse_pos - popup_menu.position
	popup_menu_items.popup()

func _on_settings_pressed():
	if settings_panel:
		settings_panel.visible = not settings_panel.visible
		_update_mouse_passthrough_region()

func spawn_item(item_type: String, pos: Vector2):
	var scene: PackedScene = null
	match item_type:
		"wand":
			scene = ITEM_WAND_SCENE
		"food":
			scene = ITEM_FOOD_SCENE

	if scene == null:
		return

	var item = scene.instantiate()
	item.global_position = pos
	add_child(item)
	AudioManager.play_item_sound()
	if smart_pet_controller:
		smart_pet_controller.record_item_use(item_type)
	_record_smart_event("item_used", {"item_type": item_type})
	if focus_session_mode:
		focus_session_mode.on_item_used(item_type)

func _on_cat_state_changed(_from_state: StringName, to_state: StringName) -> void:
	if smart_pet_controller:
		smart_pet_controller.record_state_change(to_state)
	_record_smart_event("state_changed", {"to_state": String(to_state)})
	if focus_session_mode:
		focus_session_mode.on_cat_state_changed(to_state)

func _on_focus_session_finished(result: String, summary: Dictionary) -> void:
	print("Focus session finished: ", result, " | ", summary)
	if result == "victory":
		_build_failure_streak = 0
		_record_smart_event("focus_milestone", {"summary": summary})
	else:
		_record_smart_event("focus_failed", {"summary": summary})
		_record_build_failure_streak({"source": "focus_session", "summary": summary})

func _on_keyboard_typing_for_smart(_event: InputEvent) -> void:
	if smart_pet_controller:
		smart_pet_controller.record_typing()

func _on_smart_action_requested(action_id: String, _decision: Dictionary) -> void:
	if not cat:
		return
	var state := _map_smart_action_to_state(action_id)
	if state.is_empty():
		var anim_name := _map_smart_action_to_animation(action_id)
		if cat.has_method("play_animation"):
			cat.play_animation(anim_name)
	else:
		if cat.state_machine:
			cat.state_machine.transition_to(state)

func _on_smart_line_generated(line: String, source: String) -> void:
	if line.is_empty():
		return
	print("[SMART/%s] %s" % [source, line])
	_show_smart_line(line)

func _record_smart_event(event_type: String, payload: Dictionary = {}) -> void:
	if smart_pet_controller and smart_pet_controller.has_method("record_event"):
		smart_pet_controller.record_event(event_type, payload)

func report_build_result(success: bool, payload: Dictionary = {}) -> void:
	var event_payload: Dictionary = payload.duplicate(true)
	if success:
		_build_failure_streak = 0
		_record_smart_event("build_success", event_payload)
		return
	_record_smart_event("build_failed", event_payload)
	_record_build_failure_streak(event_payload)

func _record_build_failure_streak(payload: Dictionary = {}) -> void:
	_build_failure_streak += 1
	var streak_payload: Dictionary = payload.duplicate(true)
	streak_payload["streak"] = _build_failure_streak
	if _build_failure_streak >= BUILD_FAILURE_STREAK_THRESHOLD:
		_record_smart_event("build_fail_streak", streak_payload)

func _setup_smart_line_bubble() -> void:
	if smart_line_layer:
		return
	smart_line_layer = CanvasLayer.new()
	smart_line_layer.layer = 20
	add_child(smart_line_layer)

	smart_line_panel = PanelContainer.new()
	smart_line_panel.visible = false
	smart_line_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smart_line_panel.custom_minimum_size = Vector2(SMART_LINE_BUBBLE_WIDTH, 0)

	var bubble_tex := load("res://assets/aurora/bubble.png") as Texture2D
	if bubble_tex:
		var sb := StyleBoxTexture.new()
		sb.texture = bubble_tex
		sb.texture_margin_left = 16
		sb.texture_margin_top = 16
		sb.texture_margin_right = 16
		sb.texture_margin_bottom = 40
		sb.content_margin_left = 16.0
		sb.content_margin_top = 12.0
		sb.content_margin_right = 16.0
		sb.content_margin_bottom = 44.0
		smart_line_panel.add_theme_stylebox_override("panel", sb)
	smart_line_layer.add_child(smart_line_panel)

	smart_line_label = Label.new()
	smart_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	smart_line_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	smart_line_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25, 1.0))
	smart_line_label.custom_minimum_size = Vector2(SMART_LINE_BUBBLE_WIDTH - 32, 0)
	smart_line_label.max_lines_visible = 4
	smart_line_label.text = ""
	smart_line_panel.add_child(smart_line_label)

	smart_line_hide_timer = Timer.new()
	smart_line_hide_timer.one_shot = true
	smart_line_hide_timer.wait_time = 4.0
	smart_line_hide_timer.timeout.connect(_hide_smart_line)
	add_child(smart_line_hide_timer)

func _show_smart_line(line: String) -> void:
	if not smart_line_panel or not smart_line_label:
		return
	smart_line_label.text = line
	smart_line_panel.position = _get_smart_line_position()
	smart_line_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	smart_line_panel.visible = true
	if smart_line_hide_timer:
		smart_line_hide_timer.start()

func _hide_smart_line() -> void:
	if smart_line_panel:
		smart_line_panel.visible = false

func _get_smart_line_position() -> Vector2:
	var viewport_size := _cached_screen_size
	if viewport_size == Vector2.ZERO:
		viewport_size = get_viewport_rect().size

	var anchor := viewport_size * 0.5
	if cat:
		anchor = cat.global_position

	var bubble_size := smart_line_panel.custom_minimum_size
	var desired := Vector2(anchor.x + 40.0, anchor.y - bubble_size.y - 30.0)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - bubble_size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - bubble_size.y - 8.0))
	return desired

func _map_smart_action_to_animation(action_id: String) -> String:
	match action_id:
		"sleep_curl":
			return "sleep_curl"
		"greet":
			return "greet"
		"celebrate":
			return "celebrate"
		"comfort":
			return "comfort"
		"break_hint":
			return "break_hint"
		"retreat":
			return "retreat"
		_:
			return "idle_stand"

func _map_smart_action_to_state(action_id: String) -> StringName:
	match action_id:
		"idle":
			return CatStates.IDLE
		"walk":
			return CatStates.WALKING
		"watch":
			return CatStates.WATCHING
		"pounce":
			return CatStates.POUNCING
		"chase":
			return CatStates.CHASING
		"roll":
			return CatStates.ROLLING
		"tail_wag":
			return CatStates.TAIL_WAGGING
		"lick":
			return CatStates.LICKING
		"blocking":
			return CatStates.BLOCKING
	return &""

func _setup_tray():
	if OS.get_name() != "Windows" and OS.get_name() != "macOS":
		return

	tray_indicator = StatusIndicator.new()
	tray_indicator.icon = load(TRAY_ICON_PATH)
	tray_indicator.tooltip = "Desktop Pet Cat"
	tray_indicator.pressed.connect(_on_tray_pressed)
	add_child(tray_indicator)

	_build_tray_menu()

func _build_tray_menu():
	if not NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU):
		return

	tray_menu = NativeMenu.create_menu()
	tray_menu_show_index = NativeMenu.add_item(
		tray_menu,
		_get_visibility_label(),
		Callable(self, "_on_tray_toggle_visibility")
	)
	NativeMenu.add_item(
		tray_menu,
		"设置",
		Callable(self, "_on_tray_open_settings")
	)
	NativeMenu.add_separator(tray_menu)
	NativeMenu.add_item(
		tray_menu,
		"退出程序",
		Callable(self, "_on_tray_exit")
	)

func _on_tray_pressed(mouse_button: int, mouse_position: Vector2i):
	if mouse_button == MOUSE_BUTTON_RIGHT:
		_show_tray_menu(mouse_position)
		return

	if mouse_button == MOUSE_BUTTON_LEFT:
		var now = Time.get_ticks_msec()
		if now - tray_last_click_time <= TRAY_DOUBLE_CLICK_MS:
			tray_last_click_time = 0
			_toggle_pet_visibility()
		else:
			tray_last_click_time = now

func _show_tray_menu(mouse_position: Vector2i):
	if not tray_menu.is_valid():
		return

	_update_visibility_menu_labels()
	NativeMenu.popup(tray_menu, mouse_position)

func _on_tray_toggle_visibility():
	_toggle_pet_visibility()

func _on_tray_open_settings():
	_set_pet_visible(true)
	if settings_panel:
		settings_panel.visible = true
	_update_mouse_passthrough_region()

func _on_tray_exit():
	_cleanup_tray()
	get_tree().quit()

func _toggle_pet_visibility():
	_set_pet_visible(not _is_pet_visible())

func _set_pet_visible(visible: bool):
	var window = get_window()
	window.visible = visible
	_update_visibility_menu_labels()
	_update_mouse_passthrough_region()

func _is_pet_visible() -> bool:
	var window = get_window()
	return window.visible

func _update_tray_menu_label():
	if not tray_menu.is_valid() or tray_menu_show_index < 0:
		return

	NativeMenu.set_item_text(tray_menu, tray_menu_show_index, _get_visibility_label())

func _cleanup_tray():
	if tray_indicator:
		tray_indicator.visible = false
		tray_indicator.queue_free()
		tray_indicator = null

	if tray_menu.is_valid():
		NativeMenu.free_menu(tray_menu)
		tray_menu = RID()

func _fit_window_to_screen() -> void:
	var window := get_window()
	if not window:
		return
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	if screen_size.x <= 0 or screen_size.y <= 0:
		return
	window.position = screen_pos
	window.size = screen_size
	_cached_screen_size = Vector2(screen_size)

func _get_default_cat_position() -> Vector2:
	var size := _cached_screen_size
	if size == Vector2.ZERO:
		size = get_viewport_rect().size
	var margin := Vector2(120.0, 120.0)
	var desired := Vector2(size.x - margin.x, size.y - margin.y)
	return _clamp_cat_position(desired)

func _clamp_cat_position(pos: Vector2) -> Vector2:
	var size := _cached_screen_size
	if size == Vector2.ZERO:
		size = get_viewport_rect().size
	var edge := 36.0
	return Vector2(
		clampf(pos.x, edge, maxf(edge, size.x - edge)),
		clampf(pos.y, edge, maxf(edge, size.y - edge))
	)

func _log_window_state() -> void:
	var window := get_window()
	if not window:
		return
	print(
		"Window state | size=", window.size,
		", pos=", window.position,
		", borderless=", window.borderless,
		", transparent=", window.transparent,
		", always_on_top=", window.always_on_top,
		", in_editor=", OS.has_feature("editor")
	)

func _update_mouse_passthrough_region() -> void:
	if not DisplayServer.has_method("window_set_mouse_passthrough"):
		return
	var polygon := _build_mouse_capture_polygon()
	var hash_input := str(polygon)
	var new_hash := hash(hash_input)
	if new_hash == _passthrough_cache_hash:
		return
	_passthrough_cache_hash = new_hash
	DisplayServer.window_set_mouse_passthrough(polygon)
	var window := get_window()
	if window:
		window.set("mouse_passthrough_polygon", polygon)

func _build_mouse_capture_polygon() -> PackedVector2Array:
	if _should_capture_full_window():
		return _build_full_window_polygon()
	# 猫命中区 + 道具命中区（保证道具可点击/拖拽）
	var polygon := _build_cat_hit_polygon()
	for item in get_tree().get_nodes_in_group("items"):
		if item is Node2D and is_instance_valid(item):
			polygon.append_array(_build_circle_polygon(item.global_position, 48.0, 8))
	return polygon

func _should_capture_full_window() -> bool:
	if settings_panel and settings_panel.visible:
		return true
	if popup_menu and popup_menu.visible:
		return true
	if hover_panel_visible:
		return true
	if quick_action_menu and quick_action_menu.visible:
		return true
	var input_component = cat.get_node_or_null("InputComponent")
	if input_component and bool(input_component.is_dragging):
		return true
	return false

func _build_full_window_polygon() -> PackedVector2Array:
	var size := _cached_screen_size
	if size == Vector2.ZERO:
		size = get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return PackedVector2Array()
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y)
	])

func _build_cat_hit_polygon() -> PackedVector2Array:
	if not cat:
		return _build_full_window_polygon()
	var radius := 100.0
	var input_component = cat.get_node_or_null("InputComponent")
	if input_component and "click_distance_sq" in input_component:
		radius = sqrt(maxf(float(input_component.click_distance_sq), 1.0))
	if "scale_factor" in cat:
		radius *= float(cat.scale_factor)
	radius = clampf(radius, CAT_HIT_RADIUS_MIN, CAT_HIT_RADIUS_MAX)

	var center: Vector2 = cat.global_position
	return _build_circle_polygon(center, radius, 14)

func _build_circle_polygon(center: Vector2, radius: float, segments: int = 12) -> PackedVector2Array:
	var result := PackedVector2Array()
	var safe_segments := maxi(segments, 6)
	for i in range(safe_segments):
		var angle := (TAU * float(i)) / float(safe_segments)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result

func _setup_quick_action_menu() -> void:
	if quick_action_menu:
		return
	quick_action_menu = QUICK_ACTION_MENU_SCRIPT.new()
	add_child(quick_action_menu)
	quick_action_menu.action_selected.connect(_on_quick_action_selected)
	quick_action_menu.menu_closed.connect(_on_quick_action_menu_closed)

func _on_cat_left_clicked(part: String, pos: Vector2) -> void:
	if quick_action_menu and quick_action_menu.visible:
		return
	if quick_action_menu:
		quick_action_menu.show_at(pos)
		_update_mouse_passthrough_region()

func _on_quick_action_selected(action: String) -> void:
	match action:
		"pet":
			if cat and cat.has_method("_trigger_tsundere_reaction"):
				cat._trigger_tsundere_reaction("head")
		"wand":
			var pos: Vector2 = cat.global_position if cat else get_global_mouse_position()
			spawn_item("wand", pos + Vector2(60, 0))
		"food":
			var pos: Vector2 = cat.global_position if cat else get_global_mouse_position()
			spawn_item("food", pos + Vector2(60, 0))
		"leash":
			_toggle_leash_walk()
		"settings":
			_on_tray_open_settings()
	_update_mouse_passthrough_region()

func _toggle_leash_walk() -> void:
	if not cat or not cat.state_machine:
		return
	if cat.state_machine.is_in_state(CatStates.LEASH_WALKING):
		cat.state_machine.transition_to(CatStates.IDLE)
		return
	cat.state_machine.transition_to(CatStates.LEASH_WALKING)
	if smart_pet_controller:
		smart_pet_controller.record_event("leash_walk_started")

func _on_quick_action_menu_closed() -> void:
	_update_mouse_passthrough_region()

func _make_aurora_btn_style(path: String) -> StyleBoxTexture:
	var tex := load(path) as Texture2D
	var sb := StyleBoxTexture.new()
	if tex:
		sb.texture = tex
	sb.texture_margin_left = 10
	sb.texture_margin_top = 10
	sb.texture_margin_right = 10
	sb.texture_margin_bottom = 10
	sb.content_margin_left = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 4.0
	return sb
