class_name UiTheme
extends RefCounted

## P7 奶油风主题中心：全部 UI 唯一的视觉来源（色板/几何/字号 + StyleBoxFlat 工厂）
## 用法：UiTheme.panel_style() 返回新实例，控件 add_theme_stylebox_override 即用

# —— 色板 ——
const BG := Color("FFF6E9")            # 面板底：奶油白
const SURFACE := Color("FFFDF7")       # 卡片面
const CARD := Color("FFF0D9")          # 强调卡片
const CARD_HOVER := Color("FFE7BE")    # 卡片 hover
const PRIMARY := Color("F5A623")       # 主色：暖橙
const PRIMARY_HOVER := Color("E8940F") # 主色 hover
const TEXT := Color("5C4A32")          # 主文字：暖棕
const TEXT_DIM := Color("A08B70")      # 次文字
const SUCCESS := Color("7FB86A")
const DANGER := Color("E07856")
const PINK := Color("F7B8C4")          # 肉垫粉点缀
const SHADOW := Color(0.36, 0.29, 0.20, 0.15)  # 暖棕阴影

# —— 几何 ——
const RADIUS_S := 8
const RADIUS_M := 14
const RADIUS_L := 22
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 16
const SPACE_L := 24

# —— 字号 ——
const FONT_TITLE := 20
const FONT_SECTION := 16
const FONT_BODY := 14
const FONT_CAPTION := 12

# —— 面板/卡片 ——
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(RADIUS_L)
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.set_content_margin_all(SPACE_M)
	return sb

static func card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(RADIUS_M)
	sb.set_content_margin_all(SPACE_S)
	return sb

# —— 按钮 ——
static func btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_HOVER if hover else CARD
	sb.set_corner_radius_all(RADIUS_M)
	sb.border_color = PINK if hover else TEXT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

static func btn_primary_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY_HOVER if hover else PRIMARY
	sb.set_corner_radius_all(RADIUS_M)
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

# —— 输入控件 ——
static func line_style(focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(RADIUS_S)
	sb.border_color = PRIMARY if focused else TEXT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = SPACE_S
	sb.content_margin_right = SPACE_S
	return sb

static func check_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY if on else SURFACE
	sb.set_corner_radius_all(RADIUS_S)
	sb.border_color = TEXT_DIM
	sb.set_border_width_all(1)
	sb.set_content_margin_all(SPACE_XS)
	return sb

static func slider_track_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

static func slider_fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# —— 气泡 ——
static func bubble_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(16)
	sb.border_color = TEXT
	sb.set_border_width_all(2)
	sb.shadow_color = SHADOW
	sb.shadow_size = 4
	sb.content_margin_left = SPACE_M
	sb.content_margin_right = SPACE_M
	sb.content_margin_top = SPACE_S
	sb.content_margin_bottom = SPACE_S
	return sb

# —— 页签 ——
static func tab_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PRIMARY if active else Color.TRANSPARENT
	sb.set_corner_radius_all(RADIUS_M)
	if active:
		sb.content_margin_left = SPACE_S
		sb.content_margin_right = SPACE_S
		sb.content_margin_top = SPACE_XS
		sb.content_margin_bottom = SPACE_XS
	return sb

# —— 文字 ——
static func tint_label(label: Label, role: String) -> void:
	match role:
		"title":
			label.add_theme_font_size_override("font_size", FONT_TITLE)
			label.add_theme_color_override("font_color", TEXT)
		"section":
			label.add_theme_font_size_override("font_size", FONT_SECTION)
			label.add_theme_color_override("font_color", PRIMARY)
		"caption":
			label.add_theme_font_size_override("font_size", FONT_CAPTION)
			label.add_theme_color_override("font_color", TEXT_DIM)
		_:
			label.add_theme_font_size_override("font_size", FONT_BODY)
			label.add_theme_color_override("font_color", TEXT)
