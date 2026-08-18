class_name CatLiveOverlay
extends Node2D

## 猫咪实时反应层：叠加在 AnimatedSprite2D 之上
## - 眼睛高光跟随鼠标（眼神跟踪）
## - 周期性眨眼（高光短暂消失模拟眨眼）
## - 鼠标快速晃动 → 受惊符号（!）
## - 好感度高 → 偶发爱心粒子
## 全部程序化绘制，零素材依赖，保持像素风（整数坐标渲染）

signal startled  ## 受惊触发（可接状态机扩展）

# —— 眼睛配置(128 帧内坐标,由帧扫描校准)——
# 朝向:站/坐/趴都是侧脸朝左,眼睛在左上方
const EYE_ANCHORS := {
	"idle_stand": Vector2i(62, 32),
	"idle_sit": Vector2i(62, 32),
	"idle_lie": Vector2i(62, 34),
	"trot": Vector2i(62, 47),
	"walk": Vector2i(62, 34),
	"run": Vector2i(61, 31),
	"chasing": Vector2i(61, 52),
	"watch_focus": Vector2i(62, 32),
	"greet": Vector2i(62, 32),
	"default": Vector2i(62, 34),
}
const HIDE_FOR_ANIMS := ["sleep_curl", "eat", "lick_groom", "carry", "yawn", "dodge", "startled", "retreat", "rolling"]

# —— 参数 ——
const EYE_TRACK_RANGE := 3.0        # 高光最大偏移(像素,帧内坐标)
const BLINK_INTERVAL_MIN := 2.5
const BLINK_INTERVAL_MAX := 6.0
const BLINK_DURATION := 0.12
const STARTLE_SPEED := 1600.0       # 鼠标速度阈值(px/s)
const STARTLE_COOLDOWN := 8.0
const STARTLE_SHOW_TIME := 0.9
const LOVE_PARTICLE_CHANCE := 0.008 # 每帧概率(高好感时)
const LOVE_RISE_SPEED := 22.0

var behavior_ref  # CatBehaviorSystem，可空

var _sprite: AnimatedSprite2D
var _frame_scale: float = 1.0
var _blink_timer: float = 3.0
var _blinking := false
var _blink_elapsed := 0.0
var _startle_cooldown := 0.0
var _startle_show := 0.0
var _last_mouse_pos := Vector2.ZERO
var _love_particles: Array[Dictionary] = []
var _seed := 0.0

func setup(sprite: AnimatedSprite2D, frame_scale: float) -> void:
	_sprite = sprite
	_frame_scale = frame_scale
	_last_mouse_pos = get_global_mouse_position()

func bind_behavior(behavior) -> void:
	behavior_ref = behavior

func _process(delta: float) -> void:
	if not _sprite:
		return
	_seed += delta
	_update_blink(delta)
	_update_startle(delta)
	_update_love_particles(delta)
	queue_redraw()

func _draw() -> void:
	if not _sprite:
		return
	var anim_name := _sprite.animation
	if anim_name in HIDE_FOR_ANIMS:
		_draw_startle_only()
		return

	var anchor := Vector2(EYE_ANCHORS.get(anim_name, EYE_ANCHORS["default"]))
	if anchor == Vector2.ZERO:
		_draw_startle_only()
		return

	# 眼神跟踪:鼠标方向决定高光偏移
	if not _blinking:
		var offset := _eye_track_offset()
		var px := (anchor.x + offset.x) * _frame_scale
		var py := (anchor.y + offset.y) * _frame_scale
		# 像素风高光: 1-2 个纯白块
		draw_rect(Rect2(px, py, 2.0 * _frame_scale, 2.0 * _frame_scale), Color.WHITE)
	_draw_startle_only()

func _draw_startle_only() -> void:
	# 受惊 "!" 符号
	if _startle_show > 0.0:
		var head_top := Vector2(64.0 * _frame_scale, 20.0 * _frame_scale)
		var bob := sin(_seed * 18.0) * 2.0
		var origin := head_top + Vector2(0, bob)
		var w := 3.0 * _frame_scale
		# 感叹号竖条 + 点
		draw_rect(Rect2(origin.x - w * 0.5, origin.y - 12 * _frame_scale, w, 10 * _frame_scale), Color(1.0, 0.85, 0.2))
		draw_rect(Rect2(origin.x - w * 0.5, origin.y + 2 * _frame_scale, w, 3 * _frame_scale), Color(1.0, 0.85, 0.2))
	# 爱心粒子
	for p in _love_particles:
		var pos: Vector2 = p["pos"]
		var s: float = p["size"] * _frame_scale
		_draw_heart(pos, s, Color(1.0, 0.4, 0.55, p["alpha"]))

func _eye_track_offset() -> Vector2i:
	# 鼠标全局位置 → 本地(帧内 128 坐标系)方向
	var mouse := get_global_mouse_position()
	var to_mouse := mouse - global_position
	# 猫朝左:鼠标在左 → 眼神往左下;鼠标在右(身后) → 往上瞟
	var dx := 0
	var dy := 0
	if to_mouse.x < -20.0:
		dx = -2
	elif to_mouse.x > 60.0:
		dx = 1
	if to_mouse.y < -30.0:
		dy = -1
	elif to_mouse.y > 40.0:
		dy = 1
	return Vector2i(dx, dy)

func _update_blink(delta: float) -> void:
	if _blinking:
		_blink_elapsed += delta
		if _blink_elapsed >= BLINK_DURATION:
			_blinking = false
			_blink_timer = randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blinking = true
			_blink_elapsed = 0.0

func _update_startle(delta: float) -> void:
	_startle_cooldown = maxf(_startle_cooldown - delta, 0.0)
	if _startle_show > 0.0:
		_startle_show -= delta
	var mouse := get_global_mouse_position()
	var moved := mouse.distance_to(_last_mouse_pos)
	_last_mouse_pos = mouse
	if _startle_cooldown <= 0.0 and moved / delta > STARTLE_SPEED:
		_startle_cooldown = STARTLE_COOLDOWN
		_startle_show = STARTLE_SHOW_TIME
		startled.emit()

func _update_love_particles(delta: float) -> void:
	# 高好感时偶发爱心
	if behavior_ref and behavior_ref.affection > 70.0 and randf() < LOVE_PARTICLE_CHANCE:
		_love_particles.append({
			"pos": Vector2(randf_range(50.0, 78.0), 30.0),
			"vy": -LOVE_RISE_SPEED,
			"size": randf_range(4.0, 6.0),
			"alpha": 1.0,
		})
	var alive: Array[Dictionary] = []
	for p in _love_particles:
		p["pos"] = Vector2(p["pos"].x, p["pos"].y + p["vy"] * delta / _frame_scale)
		p["alpha"] -= delta * 0.8
		if p["alpha"] > 0.0:
			alive.append(p)
	_love_particles = alive

func _draw_heart(center: Vector2, size: float, color: Color) -> void:
	# 像素爱心(两方块+三角近似,像素风足够)
	var half := size * 0.5
	var q := size * 0.25
	draw_rect(Rect2(center.x - half, center.y - q, q, q), color)
	draw_rect(Rect2(center.x, center.y - q, q, q), color)
	draw_rect(Rect2(center.x - half + q * 0.5, center.y, size - q, q), color)
