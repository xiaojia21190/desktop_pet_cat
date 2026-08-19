# P9 离线成长（正向）设计文档

日期：2026-08-19
状态：已确认（用户逐节确认语义/内容/台词档位/性格分化/实现方案/两节设计后落档）

## 产品定位

**一句话定位**：你不在时猫好好睡觉——回来时精神饱满，按离线时长用性格化台词迎接你。纯正向、零惩罚，与「不是需要照顾的电子宠物」定位一致。

原 P5 边界「不做离线成长（桌宠直觉）」针对的是**惩罚性衰减**（饿/无聊逼你上线）。本设计做的是**正向结算**，不推翻那条边界，只填「回归仪式 + 睡眠恢复」这一缺口。

## 核心决策（用户已确认）

| 决策点 | 结论 |
|---|---|
| 语义 | 正向成长（离线=猫在睡觉，精力恢复） |
| 内容 | 精力恢复 + 回归仪式（不做任务离线推进） |
| 台词 | 分档（1h / 1 天 / 3 天）× 三性格 |
| 实现 | A 启动结算：纯函数 + main 读档时一次性结算 |

## 架构

新建 `components/engagement/offline_settlement.gd`（`class_name OfflineSettlement extends RefCounted`，纯静态函数，不挂节点）：

```
settle(elapsed_sec: int, energy_now: float, personality: String)
  → {energy_gain: float, welcome_tier: int, line: String}
```

main._ready 读档拿到 `meta.saved_at` 后：

1. `elapsed = now - saved_at`（saved_at≤0 或 elapsed<0 当 0）
2. 调 `settle(...)`
3. `energy_gain > 0` → `cat.behavior_system.modify_energy(gain)`
4. `welcome_tier ≥ 1` → 气泡播 `line`（猫做 greet/tail_wag）
5. `welcome_tier ≥ 1` 时**不发** `session_resume`（压制 SMART `welcome_back`，避免叠两句）；短离线仍发 `session_resume`

## 精力公式

| 条件 | 结果 |
|---|---|
| elapsed < 300s（5 分钟） | gain = 0 |
| 其余 | `gain = min(100 - energy_now, floor(elapsed / 3600) * 8)` |

- 每满小时 +8，不满一小时的零头不计（1h59m 仍 +8）
- 封顶 100（behavior_system energy 上限）
- **不用** `ENERGY_RECOVERY = 2.0/秒`（那是在线睡觉的瞬时速率；离线 1 小时按该值会瞬间满——过猛）

## 回归台词（welcome_tier）

| tier | 门槛 | 傲娇 | 温柔 | 活泼 |
|---|---|---|---|---|
| 0 | <1h | （不播） | （不播） | （不播） |
| 1 | ≥1h | 哼，可算回来了。 | 欢迎回来。 | 你回来啦！ |
| 2 | ≥1 天 | 一天不见，还记得我？ | 好久不见，我好想你。 | 你终于回来啦你回来啦！ |
| 3 | ≥3 天 | 以为你不回来了呢…… | 等了你好久，还好你回来了。 | 呜哇你去哪了！想死我了！ |

性格键：`tsundere` / `gentle` / `playful`，与 `customization_service.personality` 同源。未知性格走 tsundere。

## 与现有 welcome_back 的边界

- 现有：`session_resume` 事件后 120 秒内 SMART 可触发 `welcome_back`（受存在感档位/静音拦截）
- 新：离线 ≥1h 的回归仪式**绕过 SMART**（安静档/硬静音也播——这是「你回来了」的一次性仪式，不是存在感闲聊）
- 互斥：`welcome_tier ≥ 1` → 跳过 `_record_smart_event("session_resume")`；短离线行为完全不变

## 挂接点（已核实）

- `save_manager.gd` `meta.saved_at` 读写四点已有；`main.gd:204` 已读该字段（用于位置默认判定）
- `cat.behavior_system.modify_energy(delta)` 存在，内部会 clamp
- `main.gd:128` `_record_smart_event("session_resume")` 在 `_setup_daily_quests` 之后——结算放在猫与气泡都就绪之后、`session_resume` 之前
- 性格：`smart_pet_controller._customization_service.personality`（`_setup_smart_pet_controller` 在 session_resume 之前已跑）

## 测试计划（新建 `tests/test_offline_settlement.gd`，约 12 断言）

- <5min：gain=0, tier=0
- 1h energy=50 → gain=8, tier=1
- 12h energy=80 → gain=20（封顶 100，不是 96）
- 25h → tier=2；73h → tier=3
- elapsed<0 → 当 0
- 三性格 tier=1 台词互不相同且非空
- 未知性格走 tsundere 台词

## 边界（不做的事）

- 不做惩罚性衰减（饿/心情变差/bond 下降）
- 不做任务离线推进（饭点/久坐离线期间不自动完成）
- 不做离线过程动画（启动瞬间结算，无「睡着」过场）
- 不改 `ENERGY_RECOVERY` 在线睡觉速率

## 验收标准

1. 新测试全绿 + 既有 13 套回归全绿
2. MCP：把 `saved_at` 改成 2 小时前启动 → 气泡播档 1 台词、energy 有增加；改成 30 秒前 → 无新仪式、welcome_back 仍可走
3. 短离线（F5 重启）行为与 P8 完全一致
