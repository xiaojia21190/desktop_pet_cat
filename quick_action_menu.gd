extends CanvasLayer

signal action_selected(action: String)
signal menu_closed()

const ACTIONS := [
	["摸摸", "pet"],
	["逗猫棒", "wand"],
	["投食", "food"],
	["毛线球", "yarn"],
	["纸箱", "box"],
	["溜猫", "leash"],
	["设置", "settings"],
]
const ACTION_ICONS := {
	"pet": "res://assets/items/icon_pet.png",
	"wand": "res://assets/items/icon_wand.png",
	"food": "res://assets/items/icon_food.png",
	"yarn": "res://assets/items/yarn.png",
	"box": "res://assets/items/box.png",
	"leash": "res://assets/items/icon_leash.png",
	"settings": "res://assets/aurora/icon_gear.png",
}
const AUTO_CLOSE_SEC := 2.5
const TWEEN_DURATION := 0.15
const PANEL_OFFSET_Y := 20.0
const BTN_MIN_SIZE := Vector2(112, 52)
const PANEL_PATCH_MARGIN := 20
const BTN_PATCH_MARGIN := 16

var _root: Control
var _panel: PanelContainer
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

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_root.add_child(_panel)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_panel.add_child(grid)

	var style_normal := _make_btn_style("res://assets/aurora/btn_normal.png")
	var style_hover := _make_btn_style("res://assets/aurora/btn_hover.png")
	for entry in ACTIONS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = BTN_MIN_SIZE
		var icon_path := String(ACTION_ICONS.get(entry[1], ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path) as Texture2D
			btn.expand_icon = true
			# 图标明确尺寸(24px),避免 expand 挤压文字
			btn.add_theme_constant_override("icon_max_width", 24)
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_hover)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_action_pressed.bind(entry[1]))
		grid.add_child(btn)

	_auto_close_timer = Timer.new()
	_auto_close_timer.one_shot = true
	_auto_close_timer.wait_time = AUTO_CLOSE_SEC
	_auto_close_timer.timeout.connect(hide_menu)
	add_child(_auto_close_timer)

func _make_panel_style() -> StyleBoxTexture:
	var tex := load("res://assets/aurora/panel_dark.png") as Texture2D
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = PANEL_PATCH_MARGIN
	sb.texture_margin_top = PANEL_PATCH_MARGIN
	sb.texture_margin_right = PANEL_PATCH_MARGIN
	sb.texture_margin_bottom = PANEL_PATCH_MARGIN
	sb.content_margin_left = PANEL_PATCH_MARGIN
	sb.content_margin_top = PANEL_PATCH_MARGIN
	sb.content_margin_right = PANEL_PATCH_MARGIN
	sb.content_margin_bottom = PANEL_PATCH_MARGIN
	return sb

func _make_btn_style(path: String) -> StyleBoxTexture:
	var tex := load(path) as Texture2D
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = BTN_PATCH_MARGIN
	sb.texture_margin_top = BTN_PATCH_MARGIN
	sb.texture_margin_right = BTN_PATCH_MARGIN
	sb.texture_margin_bottom = BTN_PATCH_MARGIN
	sb.content_margin_left = BTN_PATCH_MARGIN
	sb.content_margin_top = BTN_PATCH_MARGIN
	sb.content_margin_right = BTN_PATCH_MARGIN
	sb.content_margin_bottom = BTN_PATCH_MARGIN
	return sb

func show_at(pos: Vector2) -> void:
	visible = true
	# Force layout so we can read the panel's actual size.
	_panel.reset_size()
	await get_tree().process_frame

	var panel_size := _panel.size
	var screen_size := get_viewport().get_visible_rect().size
	var target := Vector2(
		pos.x - panel_size.x * 0.5,
		pos.y - panel_size.y - PANEL_OFFSET_Y
	)
	target.x = clampf(target.x, 8.0, maxf(8.0, screen_size.x - panel_size.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, screen_size.y - panel_size.y - 8.0))
	_panel.position = target

	_kill_tween()
	_panel.pivot_offset = panel_size * 0.5
	_panel.scale = Vector2(0.5, 0.5)
	_panel.modulate = Color(1, 1, 1, 0)

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, TWEEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), TWEEN_DURATION)

	_auto_close_timer.start()

func hide_menu() -> void:
	_auto_close_timer.stop()
	_kill_tween()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2(0.5, 0.5), TWEEN_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 0), TWEEN_DURATION)
	_tween.chain().tween_callback(_on_hide_finished)

func _on_hide_finished() -> void:
	visible = false
	menu_closed.emit()

func _on_action_pressed(action: String) -> void:
	action_selected.emit(action)
	hide_menu()

func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var panel_rect := Rect2(_panel.position, _panel.size * _panel.scale)
		if not panel_rect.has_point(event.position):
			hide_menu()

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
