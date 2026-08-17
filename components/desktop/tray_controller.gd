class_name TrayController
extends Node

## 系统托盘：图标、原生菜单、双击切换可见性。动作经信号交还宿主。

signal toggle_visibility_requested
signal open_settings_requested
signal exit_requested
signal toggle_focus_session_requested

const TRAY_DOUBLE_CLICK_MS := 400
const TRAY_ICON_PATH := "res://icon.svg"

var _indicator: StatusIndicator
var _menu: RID = RID()
var _menu_show_index := -1
var _focus_index := -1
var _focus_active := false
var _last_click_time := 0

func setup() -> void:
	if OS.get_name() != "Windows" and OS.get_name() != "macOS":
		return

	_indicator = StatusIndicator.new()
	_indicator.icon = load(TRAY_ICON_PATH)
	_indicator.tooltip = "Desktop Pet Cat"
	_indicator.pressed.connect(_on_tray_pressed)
	add_child(_indicator)

	_build_menu()

func _build_menu() -> void:
	if not NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU):
		return

	_menu = NativeMenu.create_menu()
	_menu_show_index = NativeMenu.add_item(
		_menu,
		_visibility_label(true),
		Callable(self, "_on_toggle_visibility")
	)
	NativeMenu.add_item(
		_menu,
		"设置",
		Callable(self, "_on_open_settings")
	)
	_focus_index = NativeMenu.add_item(
		_menu,
		_focus_label(),
		Callable(self, "_on_toggle_focus_session")
	)
	NativeMenu.add_separator(_menu)
	NativeMenu.add_item(
		_menu,
		"退出程序",
		Callable(self, "_on_exit")
	)

func _on_tray_pressed(mouse_button: int, _mouse_position: Vector2i):
	if mouse_button == MOUSE_BUTTON_RIGHT:
		show_menu(_mouse_position)
		return

	if mouse_button == MOUSE_BUTTON_LEFT:
		var now := Time.get_ticks_msec()
		if now - _last_click_time <= TRAY_DOUBLE_CLICK_MS:
			_last_click_time = 0
			toggle_visibility_requested.emit()
		else:
			_last_click_time = now

func show_menu(mouse_position: Vector2i) -> void:
	if not _menu.is_valid():
		return
	NativeMenu.popup(_menu, mouse_position)

func update_menu_label(pet_visible: bool) -> void:
	if not _menu.is_valid() or _menu_show_index < 0:
		return
	NativeMenu.set_item_text(_menu, _menu_show_index, _visibility_label(pet_visible))

func set_focus_session_active(active: bool) -> void:
	_focus_active = active
	if _menu.is_valid() and _focus_index >= 0:
		NativeMenu.set_item_text(_menu, _focus_index, _focus_label())

func _on_toggle_focus_session() -> void:
	toggle_focus_session_requested.emit()

func _focus_label() -> String:
	return "结束专注会话" if _focus_active else "开始专注会话"

func cleanup() -> void:
	if _indicator:
		_indicator.visible = false
		_indicator.queue_free()
		_indicator = null

	if _menu.is_valid():
		NativeMenu.free_menu(_menu)
		_menu = RID()

func _on_toggle_visibility() -> void:
	toggle_visibility_requested.emit()

func _on_open_settings() -> void:
	open_settings_requested.emit()

func _on_exit() -> void:
	exit_requested.emit()

func _visibility_label(pet_visible: bool) -> String:
	return "隐藏桌宠" if pet_visible else "显示桌宠"
