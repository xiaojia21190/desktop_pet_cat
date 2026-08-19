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
const POPUP_MENU_ITEMS_NAME := "items_menu"
const POPUP_MENU_ID_WAND := 0
const POPUP_MENU_ID_FOOD := 1
const POPUP_MENU_ID_YARN := 2
const POPUP_MENU_ID_BOX := 3
const POPUP_MENU_ID_SETTINGS := 10
const POPUP_MENU_ID_TOGGLE_VISIBILITY := 11
const POPUP_MENU_ID_EXIT := 12
const TIMED_HIDE_CONTROLLER_SCRIPT := preload("res://components/desktop/timed_hide_controller.gd")
var timed_hide_controller
var focus_session_mode
var smart_pet_controller
var foreground_app_monitor
var _last_fg_log_unix := 0
var _session_typing_count := 0
var _session_click_count := 0
var _session_signal_timer := 0.0
var tray_controller
var passthrough_manager
var smart_line_bubble
var hover_panel_component
var quick_action_menu
var _start_minimized := false  # --minimized 启动:视觉隐藏仅托盘常驻(开机自启用)

var _cached_screen_size: Vector2 = Vector2(1920, 1080)
const SETTINGS_PANEL_WIDTH := 560.0
const SETTINGS_PANEL_HEIGHT := 900.0
const FORCE_START_AT_BOTTOM_RIGHT := false

const ITEM_WAND_SCENE = preload("res://item_wand.tscn")
const ITEM_FOOD_SCENE = preload("res://item_food.tscn")
const FIRST_GUIDE_SCRIPT := preload("res://components/engagement/first_guide_controller.gd")
var first_guide_controller  # 首次引导状态机（P5c）
const DAILY_QUEST_SCRIPT := preload("res://components/engagement/daily_quest_service.gd")
var daily_quest_service  # P6：每日任务/隐式签到
var _quest_poll_timer: float = 0.0  # 分钟级快照轮询
@warning_ignore("shadowed_global_identifier")
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
		cat.bond_level_up.connect(_on_bond_level_up)
		cat.bond_gained.connect(_on_bond_gained)

	_setup_timed_hide_timer()

	# 注册节点提供者（SaveManager 存档收集依赖注入，先于 apply_settings）
	SaveManager.register_providers(
		func(): return self,
		func(): return cat,
		func(): return settings_panel,
		func(): return smart_pet_controller
	)

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
	hover_panel_component = DesktopHoverPanel.new()
	add_child(hover_panel_component)
	hover_panel_component.setup(_cached_screen_size)
	hover_panel_component.items_requested.connect(_on_items_btn_pressed)
	hover_panel_component.settings_requested.connect(_on_settings_pressed)

	var panel_scene = load("res://settings_panel.tscn")
	if panel_scene:
		settings_panel = panel_scene.instantiate()
		settings_panel.visible = false
		add_child(settings_panel)
		# Panel 挂在 Node2D 下锚点失效（父级无尺寸）→ 代码定位屏幕居中
		_center_settings_panel()

	_setup_focus_session_mode()
	_setup_smart_pet_controller(settings)
	smart_line_bubble = SmartLineBubble.new()
	add_child(smart_line_bubble)
	_setup_first_guide(settings)
	_setup_daily_quests(data)
	_setup_quick_action_menu()
	_record_smart_event("session_resume")
	_setup_tray()
	passthrough_manager = PassthroughManager.new()
	add_child(passthrough_manager)
	_update_mouse_passthrough_region()
	_log_window_state()

	# --minimized 启动:隐藏猫仅托盘常驻(托盘菜单可再显示)
	for arg in OS.get_cmdline_user_args():
		if arg == "--minimized":
			_start_minimized = true
			break

	# 延迟重申窗口标志:编辑器/快速启动场景下窗口创建与标志设置存在竞态,
	# 透明窗口若标志丢失会整屏黑;启动 0.5s 后再强制应用一次确保生效
	get_tree().create_timer(0.5).timeout.connect(func():
		if not _start_minimized:
			_apply_window_style()
			_update_mouse_passthrough_region()
	)
	if _start_minimized:
		_set_pet_visible(false)
		# minimized 模式:窗口位置可能被后续布局/size 变化复位,持续压制 3 秒
		var guard_start := Time.get_ticks_msec()
		var guard_timer := Timer.new()
		guard_timer.wait_time = 0.1
		add_child(guard_timer)
		guard_timer.timeout.connect(func():
			if _start_minimized and not _is_pet_visible():
				get_window().position = Vector2i(-20000, -20000)
			if Time.get_ticks_msec() - guard_start > 3000:
				guard_timer.queue_free()
		)
		guard_timer.start()


func _on_bond_level_up(_level: int, message: String) -> void:
	# 亲密度升级:气泡提示 + 播放庆祝音
	if smart_line_bubble and cat:
		smart_line_bubble.show_line(message, cat.global_position, _cached_screen_size)
	AudioManager.play_cat_sound()
	# 面板若开着,刷新品种解锁显示
	if settings_panel and settings_panel.visible and settings_panel.has_method("refresh_bond_ui"):
		settings_panel.refresh_bond_ui()


func _on_bond_gained(amount: float) -> void:
	# P5c：互动 bond 增量轻提示（主气泡占用时丢弃）
	if smart_line_bubble and cat and not smart_line_bubble.is_visible_to_user():
		smart_line_bubble.show_gain_tip(amount, cat.global_position, _cached_screen_size)
	if settings_panel and settings_panel.visible and settings_panel.has_method("refresh_bond_ui"):
		settings_panel.refresh_bond_ui()


func _center_settings_panel() -> void:
	if not settings_panel:
		return
	var vp := get_viewport_rect().size
	settings_panel.size = Vector2(SETTINGS_PANEL_WIDTH, SETTINGS_PANEL_HEIGHT)
	settings_panel.position = Vector2((vp.x - SETTINGS_PANEL_WIDTH) * 0.5, (vp.y - SETTINGS_PANEL_HEIGHT) * 0.5)

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
	if tray_controller:
		tray_controller.cleanup()

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
	if hover_panel_component and hover_panel_component.panel:
		var _panel_width = hover_panel_component.panel.size.x
		var panel_height = hover_panel_component.panel.size.y
		hover_panel_component.panel.position.y = (_cached_screen_size.y - panel_height) / 2
		if not hover_panel_component.is_out:
			hover_panel_component.panel.position.x = _cached_screen_size.x
			hover_panel_component._target_x = _cached_screen_size.x
	if smart_line_bubble and cat:
		smart_line_bubble.reposition(cat.global_position, _cached_screen_size)
	_center_settings_panel()
	_update_mouse_passthrough_region()

func _process(delta):
	# 首次引导状态机驱动
	if first_guide_controller and not first_guide_controller.is_done():
		first_guide_controller.tick(delta)
	# P5c：主动邀请忽略检查（每秒一次足够）
	_check_invite_ignored(delta)
	_poll_daily_quests(delta)

	# 处理悬浮面板边缘检测
	if hover_panel_component:
		hover_panel_component.update(delta, get_global_mouse_position(), _cached_screen_size)

	# 处理抖动效果
	_update_shake(delta)
	if smart_line_bubble and smart_line_bubble.is_visible_to_user() and cat:
		smart_line_bubble.reposition(cat.global_position, _cached_screen_size)
	# P3：每秒聚合工作信号喂给专注会话
	if focus_session_mode and focus_session_mode._running:
		_session_signal_timer += delta
		if _session_signal_timer >= 1.0:
			_session_signal_timer = 0.0
			var focus_activity := false
			if smart_pet_controller and smart_pet_controller._context_collector:
				var snap: Dictionary = smart_pet_controller._context_collector.get_snapshot()
				focus_activity = String(snap.get("activity", "")) == "coding"
			focus_session_mode.record_work_input({
				"typing": _session_typing_count,
				"clicks": _session_click_count,
				"focus_activity": focus_activity
			})
			_session_typing_count = 0
			_session_click_count = 0
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
	timed_hide_controller = TIMED_HIDE_CONTROLLER_SCRIPT.new()
	timed_hide_controller.name = "TimedHideController"
	add_child(timed_hide_controller)
	timed_hide_controller.bind_save_request(func(): SaveManager.save_data())
	timed_hide_controller.hide_timeout.connect(_on_timed_hide_timeout)
	timed_hide_controller.option_changed.connect(func(_index: int): _sync_timed_hide_panel())

# —— 定时隐藏公共接口：转发到 TimedHideController（外部调用点不变）——
func apply_timed_hide_settings(settings: Dictionary) -> void:
	timed_hide_controller.apply_settings(settings)

func set_timed_hide_option(option_index: int) -> void:
	timed_hide_controller.select_option(option_index)

func get_timed_hide_remaining_seconds() -> int:
	return timed_hide_controller.get_remaining_seconds()

func get_timed_hide_save_data() -> Dictionary:
	return timed_hide_controller.get_save_data()

func _on_timed_hide_timeout():
	_record_smart_event("user_busy")
	_set_pet_visible(false)

func _sync_timed_hide_panel():
	if settings_panel and settings_panel.has_method("set_timed_hide_option"):
		settings_panel.set_timed_hide_option(timed_hide_controller.option_index)

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
	if cat and cat.behavior_system:
		smart_pet_controller.bind_behavior(cat.behavior_system)
	smart_pet_controller.configure(settings)
	smart_pet_controller.smart_action_requested.connect(_on_smart_action_requested)
	smart_pet_controller.smart_line_generated.connect(_on_smart_line_generated)

	var keyboard_listener := get_node_or_null("KeyboardListener")
	if keyboard_listener and not keyboard_listener.typing_detected.is_connected(_on_keyboard_typing_for_smart):
		keyboard_listener.typing_detected.connect(_on_keyboard_typing_for_smart)

	# 感知接线：monitor → collector（设置开启时才创建）
	if bool(settings.get("perception_enabled", false)):
		_setup_perception(settings)

func _setup_perception(settings: Dictionary) -> void:
	if foreground_app_monitor:
		return
	foreground_app_monitor = ForegroundAppMonitor.new()
	foreground_app_monitor.name = "ForegroundAppMonitor"
	add_child(foreground_app_monitor)
	var no_custom_rules: Array[Dictionary] = []
	foreground_app_monitor.set_rules(
		no_custom_rules, bool(settings.get("perception_default_rules", true)))
	foreground_app_monitor.enabled = true
	foreground_app_monitor.foreground_app_changed.connect(_on_foreground_app_changed)

func _on_foreground_app_changed(app_name: String, activity: String) -> void:
	if smart_pet_controller and smart_pet_controller._context_collector:
		smart_pet_controller._context_collector.update_foreground(app_name, activity)
	# 首次采集打一行日志（真机验证感知链路；后续静默）
	if _last_fg_log_unix == 0:
		_last_fg_log_unix = int(Time.get_unix_time_from_system())
		print("[Perception] foreground: ", app_name, " -> ", activity)

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
	popup_menu_items.add_item("毛线球", POPUP_MENU_ID_YARN)
	popup_menu_items.add_item("纸箱", POPUP_MENU_ID_BOX)
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
	if tray_controller:
		tray_controller.update_menu_label(_is_pet_visible())
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
	elif id == POPUP_MENU_ID_YARN:
		spawn_item("yarn", last_menu_position)
	elif id == POPUP_MENU_ID_BOX:
		spawn_item("box", last_menu_position)
	elif id == POPUP_MENU_ID_FOOD:
		spawn_item("food", last_menu_position)

func _on_popup_menu_selected(id):
	if id == POPUP_MENU_ID_SETTINGS:
		_on_tray_open_settings()
	elif id == POPUP_MENU_ID_TOGGLE_VISIBILITY:
		_toggle_pet_visibility()
	elif id == POPUP_MENU_ID_EXIT:
		_on_tray_exit()

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
		"yarn", "box":
			# 毛线球/纸箱复用 wand 场景结构（脚本按 item_type 加载对应贴图）
			scene = ITEM_WAND_SCENE
			var inst = scene.instantiate()
			inst.item_type = item_type
			inst.global_position = pos
			add_child(inst)
			_after_item_spawned(item_type)
			return

	if scene == null:
		return

	var item = scene.instantiate()
	item.global_position = pos
	add_child(item)
	_after_item_spawned(item_type)

func _after_item_spawned(item_type: String) -> void:
	AudioManager.play_item_sound()
	if smart_pet_controller:
		smart_pet_controller.record_item_use(item_type)
	_record_smart_event("item_used", {"item_type": item_type})
	if first_guide_controller:
		first_guide_controller.notify_interaction(item_type)
	if focus_session_mode:
		focus_session_mode.on_item_used(item_type)

func _setup_first_guide(settings: Dictionary) -> void:
	# P5c 首次引导：读档判断是否已完成；未完成则启动（气泡引导，非弹窗）
	if first_guide_controller:
		return
	first_guide_controller = FIRST_GUIDE_SCRIPT.new()
	first_guide_controller.name = "FirstGuideController"
	add_child(first_guide_controller)
	first_guide_controller.load_from_save(bool(settings.get("first_interaction_done", false)))
	if not first_guide_controller.is_done():
		first_guide_controller.start()
	first_guide_controller.guide_stage_changed.connect(_on_guide_stage_changed)
	# 撸猫结束 → 引导互动喂入 + 互动时间戳（主动邀请数据源）
	if cat and cat.input_component:
		cat.input_component.petting_ended.connect(
			func(_sec):
			first_guide_controller.notify_interaction("pet")
			if smart_pet_controller and smart_pet_controller._context_collector:
				smart_pet_controller._context_collector.record_interaction())

func _on_guide_stage_changed(stage: int, message: String) -> void:
	# 引导消息走气泡；stage1/2 有 message，完成时静默
	if message.is_empty():
		return
	if smart_line_bubble and cat:
		smart_line_bubble.show_line(message, cat.global_position, _cached_screen_size)
	print("[Guide] stage=", stage, " ", message)

func first_interaction_done() -> bool:
	# SaveManager._gather_current_data 经 main provider 读取
	return first_guide_controller != null and first_guide_controller.is_done()

func _setup_daily_quests(data: Dictionary) -> void:
	# P6：挂载服务 + 读档 + 事件订阅 + 完成信号接线
	if daily_quest_service:
		return
	daily_quest_service = DAILY_QUEST_SCRIPT.new()
	daily_quest_service.name = "DailyQuestService"
	add_child(daily_quest_service)
	daily_quest_service.load_from_save(data.get("daily_quests", {}))
	daily_quest_service.checkin_done.connect(_on_checkin_done)
	daily_quest_service.quest_completed.connect(_on_quest_completed)
	# 事件流总订阅：collector 是 main 与 smart_pet_controller 两个来源的汇点
	if smart_pet_controller and smart_pet_controller._context_collector:
		smart_pet_controller._context_collector.event_recorded.connect(
			func(event_type, payload): daily_quest_service.notify_event(event_type, payload))

func _on_checkin_done(streak: int, reward: float) -> void:
	# 隐式签到：首日播一句；奖励直发（无需庆祝动作）
	if cat and smart_line_bubble and streak == 1:
		smart_line_bubble.show_line("今天也要好好相处哦", cat.global_position, _cached_screen_size)
	_grant_quest_bond(reward)

func _on_quest_completed(quest_id: String, reward: float) -> void:
	# 任务完成：台词气泡 + bond 发放（tail_wag 基础动作，greet 是 Lv2 解锁）
	var line := _quest_line(quest_id)
	if cat and smart_line_bubble:
		smart_line_bubble.show_line(line, cat.global_position, _cached_screen_size)
	if cat and cat.has_method("play_animation"):
		cat.play_animation("tail_wag")
	_grant_quest_bond(reward)

func _grant_quest_bond(reward: float) -> void:
	if cat and cat.bond_system:
		cat.bond_system.add_bond("quest_reward", reward)

func _quest_line(quest_id: String) -> String:
	# 任务完成台词（傲娇基底；性格化润色留给 LLM 轨道）
	match quest_id:
		"focus_session":
			return "一起专注的感觉还不赖嘛。"
		"stand_up":
			return "站起来晃晃，对身体好。"
		"meal_on_time":
			return "吃饱了才有力气陪我玩。"
		"interact_once":
			return "哼，勉强算你有良心。"
	return "做得不错。"

func daily_quests_save_data() -> Dictionary:
	# SaveManager._gather_current_data 经 main provider 读取
	if daily_quest_service:
		return daily_quest_service.get_save_data()
	return {}

func _poll_daily_quests(delta: float) -> void:
	# P6：窗口类任务每分钟轮询快照闲置（与 _check_invite_ignored 同聚合模式）
	if not daily_quest_service or not smart_pet_controller:
		return
	_quest_poll_timer += delta
	if _quest_poll_timer < 60.0:
		return
	_quest_poll_timer = 0.0
	daily_quest_service.poll_snapshot(smart_pet_controller._context_collector.get_snapshot())
	daily_quest_service._roll_day()  # 运行中跨天：刷新任务与签到

var _invite_check_timer: float = 0.0

func _check_invite_ignored(delta: float) -> void:
	# 邀请发出 10 分钟内无互动 → 记一次忽略（冷却翻倍；三次当日停邀）
	if not smart_pet_controller or not smart_pet_controller._policy_engine:
		return
	_invite_check_timer += delta
	if _invite_check_timer < 60.0:
		return
	_invite_check_timer = 0.0
	var engine = smart_pet_controller._policy_engine
	var last_invite: int = int(engine._last_trigger_time.get("invite_play", 0))
	if last_invite <= 0:
		return
	var now := int(Time.get_unix_time_from_system())
	var collector = smart_pet_controller._context_collector
	var last_interaction: int = collector._last_interaction_unix if collector else 0
	# 邀请满 10 分钟且期间无新互动 → 忽略
	if now - last_invite >= 600 and last_interaction < last_invite:
		engine.register_invite_ignored()
		engine._last_trigger_time["invite_play"] = 0  # 清标记避免重复记

func _on_cat_state_changed(_from_state: StringName, to_state: StringName) -> void:
	if smart_pet_controller:
		smart_pet_controller.record_state_change(to_state)
	_record_smart_event("state_changed", {"to_state": String(to_state)})
	if focus_session_mode:
		focus_session_mode.on_cat_state_changed(to_state)

func _on_focus_session_finished(result: String, summary: Dictionary) -> void:
	print("Focus session finished: ", result, " | ", summary)
	if tray_controller:
		tray_controller.set_focus_session_active(false)
	if result == "victory":
		_record_smart_event("focus_milestone", {"summary": summary})
	else:
		_record_smart_event("focus_failed", {"summary": summary})

func _on_keyboard_typing_for_smart(_event: InputEvent) -> void:
	if smart_pet_controller:
		smart_pet_controller.record_typing()
	# P3：会话工作信号计数（每秒聚合后由 _process 喂入）
	if focus_session_mode and focus_session_mode._running:
		_session_typing_count += 1

func _on_smart_action_requested(action_id: String, _decision: Dictionary) -> void:
	if not cat:
		return
	# P5c：扔东西——猫把毛线球扒拉出来（在猫爪边生成 yarn 道具）
	if action_id == "pounce" and String(_decision.get("policy_intent", "")) == "throw_yarn" \
			and _decision.has("source") == false:
		spawn_item("yarn", cat.global_position + Vector2(50, 10))
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
	if smart_line_bubble and cat:
		smart_line_bubble.show_line(line, cat.global_position, _cached_screen_size)

func _record_smart_event(event_type: String, payload: Dictionary = {}) -> void:
	if smart_pet_controller and smart_pet_controller.has_method("record_event"):
		smart_pet_controller.record_event(event_type, payload)

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
	tray_controller = TrayController.new()
	add_child(tray_controller)
	tray_controller.setup()
	tray_controller.toggle_visibility_requested.connect(_toggle_pet_visibility)
	tray_controller.open_settings_requested.connect(_on_tray_open_settings)
	tray_controller.exit_requested.connect(_on_tray_exit)
	tray_controller.toggle_focus_session_requested.connect(_on_tray_toggle_focus_session)

func _on_tray_open_settings():
	_set_pet_visible(true)
	if settings_panel:
		settings_panel.visible = true
	_update_mouse_passthrough_region()

func _on_tray_exit():
	if tray_controller:
		tray_controller.cleanup()
	get_tree().quit()

func _on_tray_toggle_focus_session() -> void:
	if not focus_session_mode:
		return
	if focus_session_mode._running:
		focus_session_mode.stop_session("tray_toggle")
	else:
		focus_session_mode.start_session()
	if tray_controller:
		tray_controller.set_focus_session_active(focus_session_mode._running)

func _toggle_pet_visibility():
	_set_pet_visible(not _is_pet_visible())

func _set_pet_visible(pet_visible: bool):
	# Godot 不允许隐藏主窗口,且铺屏 borderless 窗口的 position 会被钳制;
	# 视觉隐藏 = 缩到 1x1 移到角落 + 鼠标全穿透,托盘常驻不受影响
	var window := get_window()
	if pet_visible:
		var screen_index := DisplayServer.window_get_current_screen()
		window.size = Vector2i(DisplayServer.screen_get_size(screen_index))
		window.position = DisplayServer.screen_get_position(screen_index)
		if passthrough_manager:
			passthrough_manager.set_force_passthrough(false)
	else:
		window.size = Vector2i(1, 1)
		window.position = Vector2i(-20000, -20000)
		if passthrough_manager:
			passthrough_manager.set_force_passthrough(true)
	_update_visibility_menu_labels()
	_update_mouse_passthrough_region()

func _is_pet_visible() -> bool:
	# 视觉可见 = 窗口为全屏尺寸(隐藏方案是缩为 1x1)
	return get_window().size.x > 100

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
	# 穿透逻辑已拆至 PassthroughManager，此处保留转发
	if passthrough_manager:
		passthrough_manager.update(self)

func _setup_quick_action_menu() -> void:
	if quick_action_menu:
		return
	quick_action_menu = QUICK_ACTION_MENU_SCRIPT.new()
	add_child(quick_action_menu)
	quick_action_menu.action_selected.connect(_on_quick_action_selected)
	quick_action_menu.menu_closed.connect(_on_quick_action_menu_closed)

func _on_cat_left_clicked(_part: String, pos: Vector2) -> void:
	if quick_action_menu and quick_action_menu.visible:
		return
	# P6：点击猫算互动（任务事件源；顺带入事件流供画像）
	_record_smart_event("cat_clicked", {"pos": pos})
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
		"yarn":
			var pos: Vector2 = cat.global_position if cat else get_global_mouse_position()
			spawn_item("yarn", pos + Vector2(60, 0))
		"box":
			var pos: Vector2 = cat.global_position if cat else get_global_mouse_position()
			spawn_item("box", pos + Vector2(60, 0))
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





