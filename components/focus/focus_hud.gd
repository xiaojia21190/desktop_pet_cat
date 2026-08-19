class_name FocusHud
extends CanvasLayer

## 专注会话 HUD：三数值条 + 时间 + 目标卡 + 提示文案 + 结果面板。纯视图，数值由外部喂入。
## P7 奶油风：UiTheme 代码绘制

const UiThemeScript = preload("res://components/ui/ui_theme.gd")

const HUD_WIDTH := 430.0
const HUD_HEIGHT := 260.0
const MIN_VALUE := 0.0
const MAX_VALUE := 100.0

var hud_panel: PanelContainer
var time_label: Label
var objective_card_panel: PanelContainer
var objective_label: Label
var objective_progress_label: Label
var objective_progress_bar: ProgressBar
var focus_bar: ProgressBar
var affection_bar: ProgressBar
var chaos_bar: ProgressBar
var hint_label: Label
var help_label: Label
var result_panel: PanelContainer
var result_title: Label
var result_detail: Label

func _ready() -> void:
	layer = 100
	_build()

func show_hud() -> void:
	hud_panel.visible = true
	var vp := get_viewport().get_visible_rect().size
	hud_panel.position = Vector2((vp.x - HUD_WIDTH) * 0.5, (vp.y - HUD_HEIGHT) * 0.5)

func hide_hud() -> void:
	hud_panel.visible = false

func show_result(title: String, detail: String) -> void:
	result_title.text = title
	result_detail.text = detail
	result_panel.visible = true

func hide_result() -> void:
	result_panel.visible = false

func set_hint(text: String) -> void:
	hint_label.text = text

func set_help(text: String) -> void:
	help_label.text = text

func update_metrics(metrics: Dictionary) -> void:
	## metrics: remaining_text/objective_title/objective_target_text/
	## objective_progress(0-1)/focus/affection/chaos/help_text
	time_label.text = "Remaining: " + String(metrics.get("remaining_text", ""))
	objective_label.text = "Objective Card: " + String(metrics.get("objective_title", "-"))
	objective_progress_label.text = String(metrics.get("objective_detail", ""))
	objective_progress_bar.value = float(metrics.get("objective_progress", 0.0)) * 100.0
	focus_bar.value = float(metrics.get("focus", 0.0))
	affection_bar.value = float(metrics.get("affection", 0.0))
	chaos_bar.value = float(metrics.get("chaos", 0.0))
	help_label.text = String(metrics.get("help_text", ""))

func _build() -> void:
	hud_panel = PanelContainer.new()
	hud_panel.custom_minimum_size = Vector2(HUD_WIDTH, HUD_HEIGHT)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.visible = false
	hud_panel.add_theme_stylebox_override("panel", UiThemeScript.panel_style())
	add_child(hud_panel)

	var hud_box := VBoxContainer.new()
	hud_box.add_theme_constant_override("separation", 6)
	hud_panel.add_child(hud_box)

	var title := Label.new()
	title.text = "30m Focus Session"
	hud_box.add_child(title)

	time_label = Label.new()
	hud_box.add_child(time_label)

	objective_card_panel = PanelContainer.new()
	objective_card_panel.custom_minimum_size = Vector2(390, 92)
	hud_box.add_child(objective_card_panel)

	var objective_box := VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 2)
	objective_card_panel.add_child(objective_box)

	objective_label = Label.new()
	objective_box.add_child(objective_label)

	objective_progress_label = Label.new()
	objective_box.add_child(objective_progress_label)

	objective_progress_bar = ProgressBar.new()
	objective_progress_bar.min_value = 0.0
	objective_progress_bar.max_value = 100.0
	objective_progress_bar.show_percentage = true
	objective_box.add_child(objective_progress_bar)

	focus_bar = _create_metric_bar(hud_box, "Focus")
	affection_bar = _create_metric_bar(hud_box, "Affection")
	chaos_bar = _create_metric_bar(hud_box, "Chaos")

	hint_label = Label.new()
	hint_label.text = "-"
	hud_box.add_child(hint_label)

	help_label = Label.new()
	hud_box.add_child(help_label)

	result_panel = PanelContainer.new()
	var vp := get_viewport().get_visible_rect().size
	result_panel.position = Vector2((vp.x - HUD_WIDTH) * 0.5, (vp.y - HUD_HEIGHT) * 0.5 + 274)
	result_panel.custom_minimum_size = Vector2(HUD_WIDTH, 112)
	result_panel.visible = false
	add_child(result_panel)

	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 4)
	result_panel.add_child(result_box)

	result_title = Label.new()
	result_title.text = "Session Result"
	result_box.add_child(result_title)

	result_detail = Label.new()
	result_detail.text = "Press F5 to restart."
	result_box.add_child(result_detail)

func _create_metric_bar(parent: VBoxContainer, metric_name: String) -> ProgressBar:
	var label := Label.new()
	label.text = metric_name
	parent.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = MIN_VALUE
	bar.max_value = MAX_VALUE
	bar.show_percentage = true
	parent.add_child(bar)
	return bar
