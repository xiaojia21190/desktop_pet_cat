class_name SmartLineBubble
extends CanvasLayer

## SMART 台词气泡：贴猫显示、定时自动隐藏。纯视图，位置由 anchor 喂入。
## P7 奶油风：StyleBoxFlat 代码绘制，不再依赖 aurora 图片皮

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const BUBBLE_WIDTH := 320.0
const BUBBLE_MIN_HEIGHT := 72.0   # 文字未排版前的最小估算高度
const CAT_ABOVE_OFFSET := 120.0   # 猫头顶到原点（脚底）的渲染高度估算（128 帧基础尺寸）
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
	_panel.add_theme_stylebox_override("panel", UiThemeScript.bubble_style())
	add_child(_panel)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", UiThemeScript.TEXT)
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

## P5c 亲密度小提示：主气泡空闲时显示"亲密度 +N"；占用时静默丢弃
func show_gain_tip(amount: float, anchor: Vector2, viewport_size: Vector2) -> void:
	if is_visible_to_user():
		return  # 主气泡正在展示台词，不打断
	show_line("亲密度 +%.0f" % amount, anchor + Vector2(40, -20), viewport_size)

func _clamped_position(anchor: Vector2, viewport_size: Vector2) -> Vector2:
	# 用面板实际渲染尺寸（custom_minimum_size 高度为 0，取 get_rect 实高）
	var bubble_size := Vector2(_panel.size.x, maxf(_panel.size.y, BUBBLE_MIN_HEIGHT))
	# 锚点是猫脚底（global_position 为 CharacterBody2D 原点），气泡放头顶：往上偏一个猫高 + 边距
	var desired := Vector2(anchor.x + 40.0, anchor.y - bubble_size.y - CAT_ABOVE_OFFSET)
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - bubble_size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - bubble_size.y - 8.0))
	return desired
