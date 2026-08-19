# P6 每日任务/隐式签到 设计文档

日期：2026-08-19
状态：已确认（用户逐节确认定位/签到形态/奖励/展示/防焦虑/任务内容/任务量/实现方案/三节设计后落档）

## 产品定位

**一句话定位**：猫用轻量的每日好习惯任务陪你建立健康节奏——完成一次专注、久坐起身响应、按饭点吃饭、每天摸摸猫。全自动跟踪无打卡，完成时猫庆贺一句，奖励喂进亲密度成长。

路线归属：智能生活伴侣第三块拼图——P3 让陪伴可玩（专注充能）、P5 让猫活着（存在感档位）、P6 让关系有日常仪式（好习惯任务）。任务鼓励的是**用户的好习惯**，不是养猫义务——与「不是需要照顾的电子宠物」定位一致。

## 核心决策（用户已确认）

| 决策点 | 结论 |
|---|---|
| 系统目的 | 生活好习惯（健康节奏向） |
| 签到形态 | 隐式签到——开机即签到，零操作，连续天数累积 |
| 奖励机制 | bond 增量，计入 200 日上限（防刷语义统一，无双轨上限） |
| 展示形态 | 猫气泡轻提示 + 设置面板任务区块（零新弹窗） |
| 防焦虑 | 全自动无打卡：不领奖、不提醒未完成、不挽损，次日自动刷新 |
| 任务内容 | 全部 4 个：专注会话 / 久坐起身响应 / 饭点响应 / 和猫互动一次 |
| 任务量 | 每天 4 个全展示，完成任意个数都有奖励 |
| 实现方案 | A 独立 DailyQuestService（不动 SMART 管线） |

## 架构

```
事件流总汇点(context_collector.record_event —— main._record_smart_event
              与 smart_pet_controller.record_event 均汇入此处)
    │  record_event 尾部发 event_recorded(type, payload) 信号
    ▼
DailyQuestService（Node，main 挂载，components/engagement/）
    ├─ QUEST_DEFS 任务定义表（id/标题/判定/奖励/台词）
    ├─ 每日状态：_today_key + completed 集合 + streak_days
    ├─ notify_event(type, payload) — 事件驱动任务判定
    ├─ poll_snapshot(snapshot) — 每分钟拉取快照判定窗口闲置（起来动动/按时吃饭）
    ├─ _roll_day() — 读档恢复/跨天刷新/签到结算
    ├─ 信号：quest_completed(quest_id, reward_bond) / streak_changed(days)
    └─ 奖励 → cat.bond_system.add_bond("quest_reward", -1.0, 1.0) 显式 amount 传值
```

不动的部分：SMART 决策管线（policy_engine/llm_adapter/smart_pet_controller）、猫行为状态机、道具系统。唯一基础改动：context_collector.record_event 尾部加一个 `event_recorded` 信号 emit（新信号，既有调用方零影响）。

## 任务定义

| id | 标题 | 判定 | 奖励 bond | 完成台词（傲娇示例） |
|---|---|---|---|---|
| focus_session | 专注一刻 | `focus_milestone` 事件（main 在 focus 会话 victory 时发出，payload 含 summary） | +15 | 「一起专注的感觉还不赖嘛」 |
| stand_up | 起来动动 | `long_focus` 提醒后 5 分钟内闲置 ≥2 分钟 | +10 | 「站起来晃晃，对身体好」 |
| meal_on_time | 按时吃饭 | `meal_hint` 触发后 30 分钟内闲置 ≥5 分钟 | +10 | 「吃饱了才有力气陪我玩」 |
| interact_once | 摸摸我吧 | 任一互动事件（item_used / petting_started / 点击猫） | +8 | 「哼，勉强算你有良心」 |

- 三性格台词各一套（tsundere/gentle/playful），格式对齐 `_line_for` 现有模式
- **提醒→响应窗口**：service 收到 `long_focus`/`meal_hint`（经 context_collector 的 event_recorded 信号收到 smart_decision 事件的 policy_intent 字段）后开时间窗；窗口内每分钟轮询快照 `idle_seconds` 达标即完成；过期静默放弃。猫不催——响应了才庆贺
- interact_once 与 P5 首次引导互动语义重合但独立计数（引导一次性、任务每日性）
- completed 标记拦截重复判定，当日有效

## 隐式签到

- 每日首次启动或运行中跨天 → 签到，`streak_days +1`
- 断签（today - last_checkin > 1 天）→ streak 归 1
- 签到奖励：`min(10 + streak × 2, 30)` bond（1 天 12，10 天 30 封顶）
- 时钟回拨（today_key 变小）按新的一天处理，streak 保守断签

## 奖励经济

- 任务日总奖励 43 + 签到 12~30 ≈ **每日 55~73 bond**，占日上限 200 的 1/4~1/3
- 任务奖励计入 DAILY_BOND_CAP（add_bond 现有防刷逻辑天然覆盖）
- 任务成为 bond 第二大来源，喂食/陪玩互动仍是主体（P5 道具激活闭环不受冲击）

## 数据流与存档

存档新 `daily_quests` 区块（save_manager 四点贯通：`_get_default_data` / `load_data` / `_write_config` / `_gather_current_data`）：

```ini
[daily_quests]
today_key=20260819
completed=["focus_session","interact_once"]
streak_days=3
last_checkin_key=20260819
```

窗口状态（提醒时间戳）不落档——重启丢弃，当日任务重新等待提醒事件（简单且无损：重等提醒成本低于持久化复杂度）。

流程：
1. 启动 → main 挂载 service → 读档注入 → `_roll_day()` 刷新任务+签到结算
2. 运行 → context_collector 新增 `event_recorded(type, payload)` 信号（record_event 尾部 emit，一处改动覆盖 main 与 smart_pet_controller 两个来源）→ service 连接判定 → 完成时 emit quest_completed → main 播气泡 + add_bond + 「亲密度 +N」轻提示（复用 show_gain_tip）
3. 面板 → settings_panel 轮询 `get_today_summary()` 渲染（1 秒 Timer 同 bond 进度条模式，visible 才刷）
4. 闲置轮询 → main 已有的分钟级聚合计时器调用 `service.poll_snapshot(context_collector.get_snapshot())`（不新建 Timer）

## UI 改动

- **气泡**：任务完成时台词走现有 smart_line_bubble（与 SMART 台词同队列，不打断）；签到完成首日播一句「今天也要好好相处哦」
- **设置面板**：亲密度进度条下新增「今日任务」区块——4 行任务（标题+✓/○状态）+ 连续签到天数徽标。零新弹窗、零新交互

## 错误处理

- 存档缺区块/字段 → 默认值兜底（today_key 空 → 触发首次签到）
- 事件 payload 字段缺失 → 判定不满足即跳过，不报错
- bond_system 未就绪收到完成 → 延迟到就绪补发（防御性，main 挂载顺序实际不会触发）

## 测试计划（tests/test_daily_quests.gd，约 25-30 断言）

- 签到：首日 streak=1、连续 +1、断签归 1、同日重复启动不重复计、奖励递增封顶 30
- 任务：4 任务事件判定正向路径 + 不满足条件的拒绝路径（focus_session 判定依据是 main.gd `_on_focus_session_finished` victory 分支发出的 `focus_milestone` 事件，非 focus_session_mode 内部 `_record_event`——后者仅录制模式生效）
- 窗口：提醒后窗口内闲置达标完成、窗口过期静默、无提醒直接闲置不触发
- 存档：roundtrip、跨天刷新重置 completed、异常数据兜底
- 奖励：完成 → bond_system.bond 增量正确、completed 拦截重复发放

## 边界（不做的事）

- 不做手动签到按钮、不做任务领奖交互、不做未完成提醒（防焦虑三不）
- 不做周任务/成就系统（首期验证后再说）
- 不做任务随机抽取与画像动态任务（HabitProfileService 联动留给 P7+）
- 不引入新货币/道具类型

## 验收标准

1. 新测试全绿 + 既有 11 套回归全绿
2. MCP 端到端：启动 → 首次签到气泡/streak=1 → 投食一次 → interact_once 完成气泡 + bond +8 → 设置面板显示任务区与状态 → 重启后 completed/streak 保持
3. 全自动：全程无任何需要用户主动点击的领取/确认步骤
