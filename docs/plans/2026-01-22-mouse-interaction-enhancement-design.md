# 鼠标互动增强设计文档

**日期**: 2026-01-22
**模块**: 鼠标互动增强
**优先级**: 高

## 概述

本设计文档描述了桌面宠物猫项目的鼠标互动增强功能，包括追逐鼠标、挡住鼠标、拖拽猫咪和缩放功能。这些功能旨在实现70%自主行为+30%可控互动的核心设计目标。

## 设计决策

### 1. 整体架构

**实现方案**: 状态机扩展
**理由**: 与现有代码风格一致，实现简单，性能开销最小，符合YAGNI原则

**核心改动**:
- 在现有 `cat.gd` 状态机基础上扩展
- 添加两个新状态: `CHASING_MOUSE` 和 `BLOCKING_MOUSE`
- 添加三个交互功能: 拖拽、缩放、鼠标追逐

### 2. 交互设计决策

| 功能 | 实现方式 | 理由 |
|------|---------|------|
| 挡住鼠标 | 纯视觉效果 | 不影响实际操作，保持简单高效 |
| 缩放控制 | 鼠标滚轮 | 直观自然，符合用户习惯 |
| 拖拽方式 | 直接拖拽 | 最直观，符合桌面宠物习惯 |

## 技术实现

### 新增状态

```gdscript
enum State {
    # ... 现有状态
    CHASING_MOUSE,   # 追逐鼠标
    BLOCKING_MOUSE,  # 挡住鼠标
}
```

### 新增变量

```gdscript
var is_dragging = false          # 是否正在被拖拽
var drag_offset = Vector2.ZERO   # 拖拽偏移量
var scale_factor = 1.0           # 缩放比例（0.5-2.0）
```

### 状态处理函数

**1. 追逐鼠标 (CHASING_MOUSE)**
```gdscript
func process_chasing_mouse(delta):
    var direction = (mouse_position - global_position).normalized()
    global_position += direction * POUNCE_SPEED * delta
    look_at(mouse_position)
    if global_position.distance_to(mouse_position) < 50:
        change_state(State.IDLE)
```

**2. 挡住鼠标 (BLOCKING_MOUSE)**
```gdscript
func process_blocking_mouse(delta):
    var target = mouse_position + Vector2(randf_range(-100, 100), -80)
    var direction = (target - global_position).normalized()
    global_position += direction * POUNCE_SPEED * delta
    if global_position.distance_to(target) < 20:
        change_state(State.IDLE)
```

### 输入处理

**拖拽功能**
```gdscript
func _input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and global_position.distance_to(mouse_position) < 100:
                is_dragging = true
                drag_offset = global_position - mouse_position
            else:
                is_dragging = false

    if event is InputEventMouseMotion and is_dragging:
        global_position = mouse_position + drag_offset
```

**缩放功能**
```gdscript
if event is InputEventMouseButton:
    if global_position.distance_to(mouse_position) < 100:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            scale_factor = clamp(scale_factor + 0.1, 0.5, 2.0)
            scale = Vector2(scale_factor, scale_factor)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            scale_factor = clamp(scale_factor - 0.1, 0.5, 2.0)
            scale = Vector2(scale_factor, scale_factor)
```

## 数据流与状态管理

### 状态优先级

拖拽状态 > 自主行为状态

```gdscript
func _process(delta):
    # 拖拽时暂停自主行为
    if is_dragging:
        return

    # 正常状态机逻辑
    state_timer += delta
    mouse_position = get_global_mouse_position()
    # ... 状态处理
```

### 状态转换概率

为实现70%自主行为，调整概率分布：

| 状态 | 概率 | 类型 |
|------|------|------|
| IDLE | 15% | 自主 |
| WALKING | 15% | 自主 |
| WATCHING | 10% | 自主 |
| POUNCING | 10% | 自主 |
| CHASING_MOUSE | 15% | 自主（新增）|
| BLOCKING_MOUSE | 10% | 自主（新增）|
| ROLLING | 10% | 自主 |
| TAIL_WAGGING | 8% | 自主 |
| DRINKING | 5% | 自主 |
| IGNORING | 2% | 自主 |

### 交互反馈

- **拖拽时**: 暂停状态机，猫咪跟随鼠标
- **释放后**: 立即恢复到 IDLE 状态，然后随机切换
- **缩放时**: 保持当前状态，仅改变 scale 属性
- **追逐/挡住鼠标**: 完全自主触发，用户无法控制

## 性能优化

1. 距离检测使用 `distance_squared_to()` 避免开方运算
2. 状态切换间隔保持 3 秒，避免频繁切换
3. 拖拽时暂停状态机更新，减少计算

## 测试与验证

### 功能验证清单

- [ ] **追逐鼠标测试**
  - 移动鼠标，观察猫咪是否会随机追逐
  - 验证追到一定距离后停止

- [ ] **挡住鼠标测试**
  - 观察猫咪是否会跳到鼠标前方
  - 验证不影响实际鼠标操作（纯视觉效果）

- [ ] **拖拽功能测试**
  - 左键按住猫咪身体，拖动到不同位置
  - 验证拖拽时暂停自主行为
  - 释放后验证恢复自主行为

- [ ] **缩放功能测试**
  - 鼠标悬停在猫咪上，滚轮上下滚动
  - 验证缩放范围 50%-200%
  - 验证缩放不影响当前状态

### 性能指标

- 帧率保持 ≥30fps
- 内存占用 ≤300MB
- 输入响应延迟 ≤300ms

## 实施步骤

1. 在 `cat.gd` 中添加新状态枚举
2. 添加新增变量（is_dragging, drag_offset, scale_factor）
3. 实现 `process_chasing_mouse()` 和 `process_blocking_mouse()`
4. 修改 `_input()` 添加拖拽和缩放逻辑
5. 调整 `random_state_change()` 概率分布
6. 测试所有功能

## 风险与限制

1. **拖拽与点击冲突**: 需要区分点击和拖拽，可能需要添加移动阈值
2. **缩放时的碰撞检测**: 缩放后可能需要调整碰撞体积
3. **性能**: 频繁的距离计算可能影响性能，需要优化

## 后续工作

完成本模块后，可以继续实现：
- 打字互动效果（扑向文字、视觉乱码效果）
- 道具系统（逗猫棒、零食）
- 设置与UI系统（透明度、音效、捣乱强度调节）
