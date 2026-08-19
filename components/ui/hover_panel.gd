class_name DesktopHoverPanel
extends Node2D

## P7 聚合抽屉：右缘常驻猫爪圆钮，点开竖排四按钮（道具/设置/专注/存档）
## 兼容旧接口：is_out / panel 属性（穿透管理器判定读它们）
## 旧信号 items_requested / settings_requested 保留，新增 focus_requested / save_requested

signal items_requested
signal settings_requested
signal focus_requested
signal save_requested

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const BTN_SIZE := 32.0
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
	_knob.modulate = Color(1, 1, 1, 0.55)
	_knob.pressed.connect(_toggle_drawer)
	_knob.mouse_entered.connect(func(): _knob.modulate = Color(1, 1, 1, 1.0))
	_knob.mouse_exited.connect(func():
		if not is_out:
			_knob.modulate = Color(1, 1, 1, 0.55))
	_knob.add_theme_stylebox_override("normal", _round_style(false))
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
		btn.add_theme_stylebox_override("normal", _round_style(false))
		btn.add_theme_stylebox_override("hover", _round_style(true))
		btn.add_theme_stylebox_override("pressed", _round_style(true))
		var sig: Signal = entry[2]
		btn.pressed.connect(func():
			sig.emit()
			_toggle_drawer())
		_drawer.add_child(btn)

	_auto_close_timer = Timer.new()
	_auto_close_timer.one_shot = true
	_auto_close_timer.wait_time = AUTO_CLOSE_SEC
	_auto_close_timer.timeout.connect(func():
		if is_out:
			_toggle_drawer())
	add_child(_auto_close_timer)
	_layout()

func _round_style(hover: bool) -> StyleBoxFlat:
	var sb := UiThemeScript.btn_style(hover)
	sb.set_corner_radius_all(roundi(BTN_SIZE * 0.5))
	sb.border_color = UiThemeScript.PINK if hover else UiThemeScript.PRIMARY
	sb.set_border_width_all(2)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	return sb

func _layout() -> void:
	var cy := _screen_size.y * 0.5
	_knob.position = Vector2(_screen_size.x - BTN_SIZE - 4.0, cy - BTN_SIZE * 0.5)
	var drawer_h := _drawer.get_child_count() * (BTN_SIZE + DRAWER_GAP)
	_drawer.position = Vector2(_screen_size.x - BTN_SIZE - 4.0, cy - drawer_h * 0.5)

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
