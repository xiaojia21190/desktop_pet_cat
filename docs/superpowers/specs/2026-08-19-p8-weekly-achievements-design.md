# P8 周任务/成就系统 设计文档

日期：2026-08-19
状态：已确认（用户逐节确认周任务形态/成就类型/奖励/展示/称号交互/实现方案/两节设计后落档）

## 产品定位

**一句话定位**：在 P6 每日任务之上加一层长期成长叙事——本周任务给一周节奏感，成就与称号给里程碑记忆。数据全部来自既有任务完成事件，零新埋点、零新弹窗、延续「不催不领不挽损」原则。

## 核心决策（用户已确认）

| 决策点 | 结论 |
|---|---|
| 周任务形态 | 每日累计式（数据从每日完成记录累计） |
| 成就类型 | 累计里程碑型（不做探索发现型） |
| 奖励机制 | bond 增量 + 称号（不做配饰解锁） |
| 展示形态 | 「任务·亲密度」页扩为三区（今日/本周/成就徽章墙），零新弹窗 |
| 称号交互 | 可佩戴展示（面板标题显示，纯展示位） |
| 实现方案 | A 服务扩展（DailyQuestService 加周计数+终身累计，成就表拆独立常量文件） |

## 数据模型

**周计数**（并入 `daily_quests` 存档区块，新增 2 键）：

```ini
[daily_quests]
week_key="2026W34"          # ISO 周（周一为始）
week_counts={focus_session: 3, stand_up: 2, ...}
```

跨周判定：week_key 不匹配即清零（与 P6 跨天同模式，周一开机刷新）。

**成就区块**（新 `achievements` 区块，四点贯通）：

```ini
[achievements]
lifetime_totals={focus_session: 12, checkin_days: 34, pet_count: 87, interact_total: 50}
unlocked=["checkin_7","interact_50"]
equipped_title=""
```

## 首批内容定义

**周任务 3 个**（累计式，跨周清零）：

| id | 条件 | 奖励 bond |
|---|---|---|
| week_focus | 本周专注会话 ×3 | +30 |
| week_stand | 本周起身响应 ×5 | +25 |
| week_interact | 本周互动 ×7 | +25 |

**成就 8 个**（里程碑型，终身有效，定义表在 `components/engagement/achievement_defs.gd`）：

| id | 条件 | 奖励 | 称号 |
|---|---|---|---|
| focus_10 | 专注会话 ×10 | +50 | 专注搭档 |
| focus_50 | 专注会话 ×50 | +150 | 深度工作之魂 |
| pet_100 | 摸猫互动 ×100 | +80 | 撸猫圣手 |
| week_all | 单周全勤（四个每日任务当周各 ≥1 次）×1 | +60 | 完美一周 |
| checkin_7 | 连续签到 7 天 | +40 | 一周之约 |
| checkin_30 | 连续签到 30 天 | +150 | 月度挚友 |
| interact_50 | 任意互动 ×50 | +40 | 破冰之交 |
| bond_lv5 | 亲密度 Lv5 | +100 | 挚友认证 |

## 信号链与判定

```
任务完成 _complete(quest_id, reward, source_event="")
  ├─（现有）当日标记 + quest_completed 信号 → main 气泡/发奖
  ├─（新）week_counts[quest_id] += 1 → 周任务达标 → weekly_quest_completed(quest_id, reward)
  │    └─ 全勤检测：week_counts 四每日任务键全部 ≥1 → week_all 成就
  └─（新）lifetime_totals 累计（细分：source_event=="petting_started"/"cat_clicked" 喂 pet_count；
  │    interact_once 完成喂 interact_total；focus_session 喂 focus_session）
  │    → 成就扫描 → achievement_unlocked(id, title) → main 气泡「🏆 解锁成就：xxx」+ bond
签到结算 _roll_day()
  └─（新）lifetime_totals.checkin_days = streak_days（连续天数直接取值）→ 成就扫描
bond 等级（外部喂入）
  └─（新）main 在 bond_changed 时调 service.notify_bond_level(lv) → bond_lv5 成就扫描
```

- **`_complete` 签名加 `source_event` 参数**（默认空）：interact 类事件的原事件类型随完成传入——摸猫细分计数（pet_100）与互动总数（interact_50）分键累计，不丢粒度
- 全部消费 P6 既有完成事件，零新埋点
- 成就/周任务判定在服务内联扫描（遍历定义表比对累计值，8+3 条规模无需索引优化）
- 每次完成只扫描一次，防重复解锁由 `unlocked` 数组拦截

## UI（「任务·亲密度」页三区）

- **今日任务区**（现有 4 行不动）
- **本周任务区**（新）：3 行进度文案「专注搭档之路 2/3」，完成变 ✓
- **成就徽章墙**（新）：8 徽章 2×4 网格；已解锁暖橙点亮 + 名称，未解锁灰显 🔒 + tooltip 显示条件；顶部 OptionButton 佩戴已解锁称号（含「无」选项）
- 佩戴称号显示在面板标题：「🐾 设置 · 专注搭档」
- 打开面板刷新（现有模式）+ 成就解锁信号即时刷新（main 收到刷面板）
- 解锁气泡复用现有气泡，台词前缀「🏆」

## 存档与兼容

- `daily_quests` 加 2 键、新 `achievements` 区块——save_manager 四点贯通 ×2 处
- 旧档无新键 → 默认值兜底（week_key 空 → 触发首次周初始化；lifetime_totals 空 → 从零累计）
- **旧档历史不回补**：P6 上线前的历史专注次数无从统计，成就从 P8 上线起算——简单诚实

## 测试计划（tests/test_daily_quests.gd 追加 ~20 断言）

- 周任务：完成 3 次触发 week_focus、2 次不触发、跨周清零、roundtrip
- 成就：checkin_7 在 streak=7 时解锁、重复完成不重复发奖、focus_10 累计边界（9 不解 10 解）
- 称号：佩戴/卸下/存档 roundtrip、未解锁不可佩戴
- 存档：achievements 区块 roundtrip、异常兜底
- bond_lv5：notify_bond_level(5) 解锁

## 边界（不做的事）

- 不做探索发现型成就（用遍道具/换品种——留给后续）
- 不做成就弹窗动画/音效（气泡 + 🏆 前缀够了）
- 不做称号对猫行为的影响（纯展示位）
- 不做历史数据回补

## 验收标准

1. 14 套测试全绿（315 + ~20 新增）
2. MCP 端到端：投食 1 次 → 互动计数可见变化；伪造存档预置 streak=7 → 启动即解锁 checkin_7 气泡 + 徽章墙点亮 + 可佩戴；面板三区渲染正常
3. 旧档启动零报错、成就从零起算
