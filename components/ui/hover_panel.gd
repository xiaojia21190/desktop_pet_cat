class_name DesktopHoverPanel
extends Node2D

## 右缘悬浮功能面板：鼠标贴近右缘滑入，离开滑出。按钮动作经信号交还宿主。

signal items_requested
signal settings_requested

const EDGE_TRIGGER_DISTANCE := 20.0
const PANEL_SLIDE_SPEED := 800.0
const PANEL_WIDTH := 80.0
const PANEL_HEIGHT := 160.0

var panel: Panel
var is_out: bool = false  # 对外暴露面板可见状态（供穿透管理器判定）
var _target_x: float = 0.0
var _screen_size: Vector2 = Vector2(1920, 1080)

func setup(screen_size: Vector2) -> void:
	_screen_size = screen_size

	panel = Panel.new()
	panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.position = Vector2(screen_size.x, (screen_size.y - PANEL_HEIGHT) / 2)
	_target_x = screen_size.x

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
		panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var margin_l := 8
	var margin_t := 12
	vbox.offset_left = margin_l
	vbox.offset_top = margin_t
	vbox.offset_right = -margin_l
	vbox.offset_bottom = -margin_t
	panel.add_child(vbox)

	var btn_normal_style := _make_aurora_btn_style("res://assets/aurora/btn_normal.png")
	var btn_hover_style := _make_aurora_btn_style("res://assets/aurora/btn_hover.png")

	var items_btn := Button.new()
	items_btn.text = "道具"
	items_btn.add_theme_stylebox_override("normal", btn_normal_style)
	items_btn.add_theme_stylebox_override("hover", btn_hover_style)
	items_btn.add_theme_stylebox_override("pressed", btn_hover_style)
	items_btn.add_theme_color_override("font_color", Color.WHITE)
	items_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	items_btn.pressed.connect(func(): items_requested.emit())
	vbox.add_child(items_btn)

	var settings_btn := Button.new()
	settings_btn.text = "设置"
	settings_btn.add_theme_stylebox_override("normal", btn_normal_style)
	settings_btn.add_theme_stylebox_override("hover", btn_hover_style)
	settings_btn.add_theme_stylebox_override("pressed", btn_hover_style)
	settings_btn.add_theme_color_override("font_color", Color.WHITE)
	settings_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	settings_btn.pressed.connect(func(): settings_requested.emit())
	vbox.add_child(settings_btn)

	add_child(panel)

func update(delta: float, mouse_pos: Vector2, screen_size: Vector2) -> void:
	if not panel:
		return

	_screen_size = screen_size
	var panel_width: float = panel.size.x
	var current_x: float = panel.position.x

	# 如果面板已到达目标位置且隐藏，跳过计算
	var is_at_target: bool = abs(current_x - _target_x) <= 1
	if is_at_target and not is_out:
		return

	# 检测鼠标是否在右边缘 / 面板上
	var near_edge: bool = mouse_pos.x > screen_size.x - EDGE_TRIGGER_DISTANCE
	var on_panel: bool = panel.get_rect().has_point(mouse_pos)

	if near_edge or on_panel:
		_target_x = screen_size.x - panel_width
		is_out = true
	else:
		_target_x = screen_size.x
		is_out = false

	# 平滑滑动（仅在需要移动时计算）
	if not is_at_target:
		var direction: float = sign(_target_x - current_x)
		panel.position.x += direction * PANEL_SLIDE_SPEED * delta
		panel.position.x = clampf(panel.position.x, screen_size.x - panel_width, screen_size.x)

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
