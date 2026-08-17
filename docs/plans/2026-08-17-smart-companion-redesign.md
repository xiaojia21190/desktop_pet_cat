# 桌宠猫 → 智能生活伴侣 改造设计（第一期）

日期：2026-08-17
状态：已确认（用户逐节确认定位/架构/分期/风险后落档）

## 产品定位

**一句话定位**：猫感知你的电脑生活（在用什么应用、工作还是摸鱼、专注还是闲置），主动搭话、提醒休息、庆祝成果——是有性格的陪伴者，不是需要照顾的电子宠物。

路线归属：智能生活伴侣（区别于"活着的宠物"养成路线与 Forest 式纯专注工具路线）。

## 三条产品原则

1. **感知本地化**：所有上下文本地采集、本地消费。只有用户显式配置 LLM 后才有网络请求，且只发送意图级摘要（如"用户在写代码，已专注 40 分钟"），永不发送按键内容、窗口标题、应用列表。
2. **规则主导，LLM 润色**：没有 API key 也必须是完整产品（模板台词兜底），LLM 只负责把意图润色成有个性的自然台词。
3. **猫的内在统一**：一只猫只有一套心理状态，所有系统读同一份。

## 目标架构（四层）

```
┌─ 表达层 ──────────────────────────────────┐
│ 猫本体(cat.gd) 气泡(smart_line) 托盘/菜单     │
├─ 决策层 ──────────────────────────────────┤
│ SMART 管线（3 秒决策）                       │
│  Context → Profile → Policy → (LLM)         │
│  意图集扩充：+coding/video/social/...        │
├─ 心理层（唯一源）────────────────────────────┤
│ CatBehaviorSystem 扩展为猫心理中心            │
│  mood/energy/affection/chaos + 记忆接口       │
│  专注会话、SMART 全部读写这里                 │
├─ 感知层（新增）──────────────────────────────┤
│ ForegroundAppMonitor (Win32 API)            │
│  → 活动分类器 → ContextCollector 扩展         │
└───────────────────────────────────────────┘
```

### 关键变化

**心理统一**：`CatBehaviorSystem` 升级为心理唯一源，新增 chaos 维度；专注会话删除自带的 focus/affection/chaos 三数值，改为读写心理层；SMART 决策输入加入心理快照（心情差→安慰语气、精力低→选安静动作）。三套并行且不互通的"猫心理"数据（行为系统 / 专注会话 / SMART 各自为政）合并为一套。

**感知升级**：新增 `ForegroundAppMonitor`，定期（约 2 秒）获取前台进程名（Win32 `GetForegroundWindow` + `GetWindowThreadProcessId` + `QueryFullProcessImageName`，不取窗口标题），经活动分类表映射为活动类别（VSCode→coding、视频播放器→video、浏览器→browser 等，用户可在设置中自定义规则），写入 Context 快照。隐私边界：进程名级别，不读窗口标题与页面内容。

**专注会话重塑**：玩法方向反转——从"你照顾猫"（被动衰减、需要不停喂食才能维持，真专注工作的人反而必败）反转为"猫陪你工作"——检测到持续专注工作状态时 focus 自动充能，猫的状态是氛围加成而非惩罚源；数值重调到可胜；托盘菜单增加"开始专注会话"入口。

**架构卫生**：`focus_session_mode.gd`（1884 行）拆分为约 5 个单一职责文件（会话循环 / HUD / 目标卡 / 教程 / 调试设施）；录制回放、垃圾桶、ops 面板等测试设施移入 `tests/debug_tools/`，仅 debug 构建加载；`main.gd`（962 行）瘦身，UI 面板各自成文件。

## 分期计划（四期，每期独立交付）

| 期 | 内容 | 交付物 | 预估规模 |
|---|---|---|---|
| P1 架构地基 | 心理统一到行为系统；拆 focus_session_mode；main.gd 瘦身 | 行为不变的纯重构，全部测试绿 | 最大，约 15-20 文件 |
| P2 感知升级 | ForegroundAppMonitor + 活动分类 + 设置页"感知"分区 | 猫知道你在用什么应用 | 中，约 6 新文件 |
| P3 会话重塑 | 专注会话玩法反转 + 托盘入口 + 数值重调 + 调试设施隔离 | 可玩的专注陪伴玩法 | 中 |
| P4 心理记忆 | SMART 读心理层、意图扩充（应用类意图）、HabitProfileService 深化 | 有记忆有性格的完整体验 | 中 |

顺序理由：P1 不做，后面三期都堆在破地基上；P2 是伴侣感的核心增量且独立于 P3/P4；P3 依赖 P1 的拆分；P4 依赖 P2 的数据与 P1 的心理统一。

## 风险与对策

- **前台进程获取**：GDScript 无法直调 Win32，用 `OS.execute` 跑轻量 helper（PowerShell 或小型 exe）。单次调用 <1ms、每 2 秒一次，开销可忽略。实施时验证 Godot 4.7 DisplayServer 是否已有对应接口，有则优先。
- **行为回归风险**：P1 重构全程跑三套现有测试（test_focus_session_mode / test_smart_modules / test_sprite_manifest_loader）+ Godot MCP 端到端验证（已验证过流程有效）。
- **范围失控**：每期独立交付、独立验收；P3 数值调整不算新功能。

## 已废弃的现状问题清单（本设计解决）

1. focus_session_mode.gd 1884 行、6 种职责混装（已于 2026-08-17 修复其自启 bug，但拆分未做）
2. main.gd 962 行上帝对象
3. 三套互不相通的猫心理数据（两个 affection 语义冲突）
4. 专注会话无用户入口、数值不可胜、88% 是测试设施
5. SMART 管线感知浅（只有打字率/点击率/闲置/时钟，分不清在干什么）
6. test_behavior_system 缺 quit 调用、headless 不退出

## P1 完成记录（2026-08-17）

**拆分结果**（全部提交于 main 分支）：

| 文件 | 改造前 | 改造后 | 说明 |
|---|---|---|---|
| focus_session_mode.gd | 1884 行 | 529 行 | 会话核心：循环/数值/胜负/demo 事件注入 |
| → components/focus/objective_system.gd | - | 171 行 | 目标卡系统（纯逻辑，8 测试） |
| → components/focus/focus_hud.gd | - | 151 行 | HUD 视图（CanvasLayer） |
| → components/focus/tutorial_controller.gd | - | 65 行 | 教程状态机 |
| → tests/debug_tools/session_recorder.gd | - | 1090 行 | 录制/回放/垃圾桶/ops 调试设施（默认不加载） |
| main.gd | 962 行 | 645 行 | 剩余：窗口/菜单/猫接线/SMART 集成 |
| → components/desktop/tray_controller.gd | - | 95 行 | 系统托盘 |
| → components/desktop/passthrough_manager.gd | - | 84 行 | 鼠标穿透 |
| → components/ui/smart_line_bubble.gd | - | 77 行 | SMART 台词气泡 |
| → components/ui/hover_panel.gd | - | 121 行 | 右缘悬浮面板 |

**心理统一**：CatBehaviorSystem 新增 chaos 维度（事件驱动不衰减，34 测试）；专注会话 affection/chaos 以 getter/setter 代理到行为系统（`bind_behavior()` 注入），focus 保留会话内表现分。

**行为变更例外**（唯一一处）：`start_session()` 不再重置 affection/chaos 为固定初值——统一后延续猫的当前心理状态。旧测试 `affection_synced_from_behavior` 等已覆盖此语义。

**验证**：五套 headless 测试全绿（23+15+13+34+8=93 断言）；MCP 90 秒端到端无错误、无 Focus session failure、SMART 正常、猫渲染确认（橙色像素聚类 561）。

## P2 完成记录（2026-08-17）

**交付**（提交 91a5b8f..5707eb7，6 任务）：

| 组件 | 说明 |
|---|---|
| components/perception/activity_classifier.gd | 10 类别 58 条默认规则 + 用户规则覆盖（24 断言） |
| components/perception/foreground_app_monitor.gd | 管道轮询状态机采集（10 断言） |
| context_collector.gd 扩展 | 快照 4 新字段 + 活动用时累计 |
| 设置链路 | perception_enabled（默认关）/ perception_default_rules 贯通存档与 UI |
| habit_profile_service | watching_video / coding_now / browsing_now 活动标签（持续 10 分钟才贴） |

**实施中的关键修正**（计划外发现）：
1. PowerShell 采集脚本从 `-Command` 改为 **`-EncodedCommand`（UTF-16LE Base64）**——GDScript→cmd→PowerShell 三层引号转义不可行
2. 采集执行从 Thread+OS.execute 改为 **`OS.execute_with_pipe` 非阻塞管道 + 每帧轮询状态机**——OS.execute 在 Godot 4.7 子线程中拿不到 stdout（引擎限制），阻塞式 1.1 秒会卡主线程
3. `save_manager.load_data()` 是逐键白名单读取，新设置键必须同时补 `_get_default_data` + `load_data` + `_write_config` + `_gather_current_data` 四处

**验证**：七套测试全绿（34+23+30+13+8+24+10=142 断言）；MCP 真机端到端输出 `[Perception] foreground: Godot_v4.7-stable_win64 -> coding`——存档开关→monitor→管道采集→分类→collector 全链路打通。
