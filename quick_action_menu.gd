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
	sb.content_margin_left = 0
	sb.content_margin_right = 0
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
		var angle: float = ANGLE_FROM + (ANGLE_TO - ANGLE_FROM) * t
		var radial_offset := Vector2(cos(angle), sin(angle)) * RADIUS
		var btn: Button = _buttons[i]
		btn.position = pos + radial_offset - Vector2(BTN_SIZE, BTN_SIZE) * 0.5
	_kill_tween()
	_panel.scale = Vector2(0.4, 0.4)
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
