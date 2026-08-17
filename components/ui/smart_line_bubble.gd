class_name SmartLineBubble
extends CanvasLayer

## SMART 台词气泡：贴猫显示、定时自动隐藏。纯视图，位置由 anchor 喂入。

const BUBBLE_WIDTH := 320.0
const AUTO_HIDE_SECONDS := 4.0

var _panel: PanelContainer
var _label: Label
var _hide_timer: Timer

func _ready() -> void:
	layer = 20

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)

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
		_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25, 1.0))
	_label.custom_minimum_size = Vector2(BUBBLE_WIDTH - 32, 0)
	_label.max_lines_visible = 4
	_label.text = ""
	_panel.add_child(_label)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = AUTO_HIDE_SECONDS
	_hide_timer.timeout.connect(hide_bubble)
	add_child(_hide_timer)

func show_line(line: String, anchor: Vector2, viewport_size: Vector2) -> void:
	if not _panel or not _label:
		return
	_label.text = line
	_panel.position = _clamped_position(anchor, viewport_size)
	_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_panel.visible = true
	if _hide_timer:
		_hide_timer.start()

func reposition(anchor: Vector2, viewport_size: Vector2) -> void:
	if _panel and _panel.visible:
		_panel.position = _clamped_position(anchor, viewport_size)

func hide_bubble() -> void:
	if _panel:
		_panel.visible = false

func is_visible_to_user() -> bool:
	return _panel != null and _panel.visible

func _clamped_position(anchor: Vector2, viewport_size: Vector2) -> Vector2:
	var bubble_size := _panel.custom_minimum_size
	var desired := Vector2(anchor.x + 40.0, anchor.y - bubble_size.y - 30.0)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - bubble_size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - bubble_size.y - 8.0))
	return desired
