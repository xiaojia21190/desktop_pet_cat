# P10 动画流畅度代码层重做 设计文档

日期：2026-08-19
状态：已确认（用户确认四问题全中/先代码后素材策略/完整播放保护全量/两节设计后落档）

## 产品定位

**一句话定位**：不动美术素材，把动画体验从「幻灯片」修到当前 8 帧素材的天花板——动作播完不被打断、切换有过渡、移动平滑、节奏有呼吸感。素材重生成（12-16 帧）留作下一期。

## 问题与根因（已核实代码）

| # | 问题 | 根因 |
|---|---|---|
| ① 动作像幻灯片 | 实际精灵图每动作 3-8 帧（128px AI 生成），speed 3-11fps 偏低且分配不均 |
| ② 动作切换跳变 | `state_machine.transition_to` 硬切（exit→enter→play），无过渡 |
| ③ 互动动作不连贯 | **一次性动作（eat/pounce/greet 等）被状态机中途打断**——吃一半/玩一半切换；tres 中 loop 标记与动作语义有错位（pounce_attack 是 loop=1） |
| ④ 移动卡顿 + 节奏单调 | chase 300/walk 100 速度突变、方向无平滑；行为系统 chain_timer 均匀调度，动作时长与观感不匹配 |

## 方案：四修法（全代码层）

### 修法①：帧时长曲线映射

`CatAnimationComponent` 内：一次性动作的各帧 duration 按缓动曲线分配（首尾帧 ×1.6、中间帧 ×0.7）——同样 8 帧观感更连贯。循环动作不动（匀速合理）。

实现：`play()` 时对 `sprite_frames.set_frame_duration()` 逐帧设置（播放前一次性写入，无逐帧开销）。

### 修法②③：完整播放锁 + 过渡调度

- `CatAnimationComponent` 新增：
  - `play_with_transition(anim_name)`：一次性动作播放 → `is_action_locked()` 返回 true → `animation_finished` 信号解锁
  - 循环动作间切换：0.15s modulate 微淡出再切（视觉缓冲）
  - **动作属性表内联**（ONESHEET_ACTIONS）：一次性动作集合（以语义修正版为准，非 tres 的 loop 值——pounce_attack 归一次性）
- `StateMachine.transition_to` 加锁：
  - 目标动作在锁定期 → 存 `pending_state`，`animation_finished` 后自动执行
  - `msg.get("urgent", false)` 豁免：立即切换
  - **urgent 链路**：用户拖拽、点击猫、打字攻击三条

### 修法③ 节奏表：`components/animation_timing.gd`

一次性动作 → `{min_duration}`（=播完一遍时长 ×1.0）+ 随机 ±20% 抖动。行为系统 `chain_timer` 调度读表，杜绝「动画比调度短被冻在末帧」与「调度比动画短被截断」。

### 修法④：移动平滑

`cat_walking_state` / `cat_chasing_state` / `cat_leash_walking_state`：
- 方向：`direction = direction.lerp(target_dir, 0.15)`（每帧，转向平滑）
- 速度：进入状态 0→满速 0.3s 渐变（`speed_ramp`），离开自然结束
- 位移：`global_position += smoothed_dir * ramped_speed * delta`

### 帧率批量调优（数据改动）

脚本批量改 5 品种 `.tres`：待机类 5→4、walk 8→10、trot 9→11、chasing/run +1、互动类（eat/pounce/greet/celebrate/comfort）+1~2。用脚本生成避免手改 5×30 条。

## 文件结构

| 文件 | 改动 |
|---|---|
| `components/cat_animation_component.gd` | play_with_transition / is_action_locked / 帧时长曲线 / ONESHOT_ACTIONS 表 |
| `components/state_machine.gd` | transition_to 锁排队 + urgent 豁免 + pending 自动执行 |
| `components/animation_timing.gd`（新） | 节奏表纯常量 |
| `states/cat_walking_state.gd` `cat_chasing_state.gd` `cat_leash_walking_state.gd` | 方向 lerp + 速度 ramp |
| `resources/animations/*.tres` ×5 | speed 批量调优（脚本） |
| `cat_behavior_system.gd` | chain 调度读节奏表 |
| urgent 链路（cat_input_component 拖拽 / main 点击 / typing_attack） | transition_to 传 `{"urgent": true}` |

## 测试计划（新 `tests/test_anim_flow.gd`，约 15 断言）

- 动画组件：一次性播放中锁 true / finished 后解锁 / 循环动作不锁 / pounce_attack 在一次性表内
- 状态机：锁定期 transition 排队（current_state 不变）/ urgent 立即切 / pending 在 finished 后执行
- 移动：chasing 首帧方向被 lerp（构造正东目标，初始朝南，断言位移角度 < 90°）
- 节奏表：每个一次性动作 min_duration ≥ frames/speed（播完一遍）

## 边界（不做的事）

- 不重生成美术素材（下一期独立做：每动作 12-16 帧）
- 不做骨骼动画/补间变形（像素精灵图不适合）
- 不改品种切换动画链路
- 不做帧间 alpha 混合（像素风会糊）

## 验收标准

1. 15 套测试全绿（364 + ~15 新增）
2. MCP 真机：投食→chasing→eat **完整播放不被打断**；逗猫棒 pounce 全循环；走路转向平滑无折线；互动期间点击猫可打断（urgent 豁免生效）
3. 既有 14 套零回归（行为系统 chain 调度改动不破坏 P1 的 34 断言）
