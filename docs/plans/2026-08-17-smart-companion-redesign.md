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

## P3 完成记录（2026-08-17）

**交付**（提交 a6b630c..P3 收尾，5 任务）：

| 改动 | 说明 |
|---|---|
| components/focus/focus_charge_engine.gd | 充能引擎：打字 0.6/键（封顶4）+ 点击 0.3（封顶2）+ 专注活动底薪 1.5，×1.2 倍率充能；闲置 -0.18/秒 |
| 数值反转 | 被动衰减(≥1/秒必败) → 工作充能；打字攻击不再扣 focus（改 chaos 小波动）；猫干扰 -5/-4/-3 → -1.2/-1.0/-0.8 |
| 托盘入口 | "开始/结束专注会话"菜单项 + stop_session 手动结算（Session Paused，不判失败） |
| 时长档位 | 设置面板 15/30/60 分钟，focus_duration_index 四点存档 |
| _tick_one_second | 每秒滴答从 _process 抽出，支持测试单步快进驱动 |

**数值新旧对照**：

| 项 | 旧（必败制） | 新（充能制） |
|---|---|---|
| 被动 focus | -(1+chaos*0.03)/秒 | 工作时 +(score×1.2)，闲置 -0.18/秒 |
| 打字攻击 | focus -8 / chaos +16 | focus 0 / chaos +3 |
| 猫挡屏幕(Blocking) | focus -5 | focus -1.2 |
| 会话结局 | ~54 秒必弹 Session Failed | 工作必胜 / 闲置约 8.4 分钟失败 |

**验证**：八套测试全绿（150 断言）；主场景级端到端（真实 main.tscn + 行为系统绑定 + 快进驱动）：持续普通工作（2键/秒+coding）→ 120 秒会话完整跑完 focus=100 **WINNABLE**；纯闲置 → sec=505 失败（约 8.4 分钟，命中 8-10 分钟设计区间）。

## P4 完成记录（2026-08-17）

**交付**（提交 7523d61..P4 收尾，5 任务）：

| 改动 | 说明 |
|---|---|
| psyche 注入 | SmartPetController.bind_behavior → 决策快照携带 mood/energy/affection/chaos 四值 |
| 心理调制 | 精力 <30 时欢快动作（celebrate/greet/tail_wag）自动换 sleep_curl（安静的猫） |
| 新意图 ×3 | video_companion（看视频陪伴）、coding_cheer（写代码 30 分钟鼓励）、night_owl_care（深夜关怀，消费记忆线） |
| 记忆生成 | HabitProfileService.build_memory_lines：深夜活跃>60%/代码>2h/视频>1h 三类记忆台词 |
| 决策上下文 | 快照新增 memory_lines 字段，策略引擎深夜意图优先消费记忆台词 |

**验证**：八套测试全绿（~187 断言，smart_modules 涨至 45）；MCP 端到端 15 秒无错误、SMART 决策链路带 psyche/memory 正常运行。（注：test_sprite_manifest_loader 首跑出现过一次 mtime 缓存偶发 flake，复跑三次稳定全绿，与 P4 改动无关。）

## 四期总览（全部完成）

| 期 | 主题 | 核心成果 |
|---|---|---|
| P1 | 架构地基 | 1884→529 行拆分 7 组件、心理统一到行为系统、main 962→645 行 |
| P2 | 感知升级 | 前台应用监测（隐私默认关）、活动分类 10 类、SMART 活动标签 |
| P3 | 会话重塑 | 玩法反转为工作充能制（必胜/闲置 8 分钟）、托盘入口、时长档位 |
| P4 | 心理记忆 | 决策读心理、3 新意图、作息记忆反馈 |

产品定位闭环：猫**看得见**你在干什么（P2）、**有统一的内在**（P1）、**陪你工作就会成长**（P3）、**记得你、懂你**（P4）——智能生活伴侣四块基石齐备。

## P5 完成记录（2026-08-18）「活过来的猫」

**背景**：用户反馈"都不太会触发"。诊断证实：触发链路大面积死亡——静音时段全覆盖夜间活跃时段（night_owl_care 数学上永不触发）、45 秒清零杀死全部长时意图、LLM 提示词自缚导致系统性沉默、build_fail_streak 零调用死代码、产品累计真实使用仅 19 分钟且互动全零。设计文档：`docs/superpowers/specs/2026-08-18-p5-alive-cat-design.md`。

### P5a 落袋为安（10 提交）

| 内容 | 说明 |
|---|---|
| 验收落袋 | 工作区滞留约 3 周的 ~10500 行改动按逻辑拆 5+5 提交（亲密度系统/撸猫交互/LLM 代理修复/4品种13新动作/DLC 品种/托盘常驻等） |
| 测试补齐 | bond_system 21 断言 + 撸猫意图 6 断言（此前零测试）；顺手修 2 个启动 WARNING |
| 仓库卫生 | .gitignore 生效（.godot/pycache/uid 停止跟踪），工作区 clean |

### P5b 让猫活过来（8 提交）

| 改动 | 说明 |
|---|---|
| presence_level 档位 | 5 档（安静/低频/中频/高频/智能）取代 reminder_intensity；旧档读档迁移 low/med/high→1/2/3；驱动三层：意图白名单+冷却倍率（×4~×0.5）、LLM 决策周期（180~20s）、提示词人设 |
| 死链①分层静音 | 静音时段前 60 分钟为软静音（放行深夜关怀/晚安），其余硬静音；非跨午夜同样成立 |
| 死链②滑窗累计 | 停止输入 45s~5min 按 50% 折算（思考间隙不打断），>5min 才清零——久坐/深夜关怀/写代码鼓励从不可达变可达 |
| 死链③删死代码 | build_fail_streak 意图与 report_build_result 全删（零数据源；LLM 推断+主动邀请覆盖同类体验） |
| LLM 双轨 | 轨道A规则保底（模板台词立即上+5s 异步润色）；轨道B LLM 自主（档位人设+silent_streak 沉默反压）；规则引擎从"降级参考"升回保底大脑 |
| 新意图 ×6 | meal_hint（饭点）/slacking_caught（摸鱼抓包）/weather_smalltalk（每小时闲聊）/invite_play（主动邀请）/throw_yarn（高频扔毛线球）/智能档按活动自适应折算 |

### P5c 道具激活闭环（3 提交）

| 改动 | 说明 |
|---|---|
| 首次引导 | FirstGuideController 状态机（0未引导→1摸摸→2道具→3完成），猫气泡引导非弹窗；first_interaction_done 落档防重放；step2 十分钟超时自动完成 |
| 主动邀请 | 30 分钟无互动猫主动邀玩（中频 8%/高频 15% 概率）；**克制机制**：忽略 10 分钟→冷却翻倍（180→360→720→1440），三次忽略当日停邀 |
| bond 反馈 | 气泡"亲密度 +N"轻提示、设置面板亲密度进度条（等级+进度+解锁预告）、饿猫（energy<40）喂食 ×1.5 加成 |

### 验证

- **11 套测试全绿**：behavior 34 / focus_session / manifest / objective / classifier / monitor / charge / smart 44 / **bond 29** / **presence 32** / **first_guide 8**（P5 新增 3 套 69 断言）
- **MCP 端到端**：启动即 `[SMART/policy]`（规则轨道活）、45s `[SMART/llm] 哼，这么晚了还不休息？`（LLM 轨道主动开口——过去永久沉默）、30s `[Guide] stage=1 摸摸我吧`（首次引导触发）、整点 `[SMART/policy] 喂，偶尔也看看我嘛。`（新意图 weather_smalltalk）；150 秒 5+ 次猫输出，零错误
- 修复过程记录：Godot 4.7 的 const 类型化数组传参退化为未类型化（测试须用函数返回局部数组）；ACTION_POUNCE 常量缺失补齐；main.gd 误删 SETTINGS_PANEL_WIDTH 当场发现恢复

### P5 后世界

猫开机即活：档位控制存在感、深夜被关怀、整点闲聊、摸鱼被抓包、久坐被提醒；首次使用即被引导互动，互动喂进亲密度解锁动作与品种；LLM 在场有灵气、不在场模板有性格——「都不太会触发」成为历史。

## P6 完成记录（2026-08-19）「每日任务与隐式签到」

**背景**：设计文档明确「每日任务/签到（下一步再说）」。P6 落地：猫用全自动好习惯任务陪用户建立健康节奏——零打卡、零弹窗、零焦虑（不催不领不挽损）。设计文档：`docs/superpowers/specs/2026-08-19-p6-daily-quests-design.md`，实现计划：`docs/superpowers/plans/2026-08-19-p6-daily-quests.md`。

### 交付（9 提交）

| 改动 | 说明 |
|---|---|
| event_recorded 信号 | context_collector.record_event 尾部广播——main 与 smart_pet_controller 两来源事件流总汇点（smart_decision 不经 main，挂接点必须在 collector） |
| DailyQuestService | 纯逻辑服务（components/engagement/）：隐式签到结算（连续 +1/断签归 1/奖励 min(10+streak×2,30)）+ 4 任务状态机 |
| 4 任务 | 专注一刻（focus_milestone 事件 +15）/ 起来动动（long_focus 提醒后 5 分钟窗闲置 2 分钟 +10）/ 按时吃饭（meal_hint 后 30 分钟窗闲置 5 分钟 +10）/ 摸摸我吧（任一互动事件 +8） |
| 提醒→响应窗口 | 收到提醒开时间窗，main 每分钟轮询快照 idle_seconds 达标即完成；过期静默——猫不催，响应了才庆贺 |
| 存档贯通 | daily_quests 区块四点贯通（today_key/completed/streak_days/last_checkin_key）；窗口状态不落档（重启重等提醒，简单无损） |
| bond 集成 | quest_reward 增益类型（显式 amount、豁免同类递减）；计入 200 日上限——任务日总奖励 55~73，第二大 bond 来源不冲击互动主体 |
| 面板区块 | 设置面板「今日任务」4 行（✓/○ 状态）+ 连续签到天数徽标，代码构建 visible 才刷（同亲密度进度条模式） |

### 执行中发现并修复（计划外）

1. **load_from_save 状态残留 bug**（TDD 当场抓获）：测试驱动服务实例复用连续 load 时，上次 load 的 today_key/checked_in 干扰本次跨天结算（连续签到 streak+1 被吞）→ load 前全量重置实例状态
2. **异常兜底加固**：streak_days 非数值（"abc"）与 completed 非数组（字符串）的类型检查——GDScript int("abc") 得 0 不报错但 `var x: Array = "str"` 直接崩
3. **窗口轮询遍历安全**：poll_snapshot 收集过期/完成项后统一 erase（遍历字典同时 erase 是未定义行为）

### 验证

- **12 套测试全绿**：behavior 34 / focus_session 28 / manifest 19 / objective 8 / classifier 24 / monitor 10 / charge 8 / smart 44 / bond 29 / presence 32 / first_guide 8 / **daily_quests 42**（合计 286 断言，P6 新增 42）
- **MCP 端到端真机**：首启签到落档（today_key/streak_days 正确递增）；真实互动触发 interact_once 完成并落档 completed；二次启动同日不重复签到（streak 3→3）、completed 保持；全程零 SCRIPT ERROR；存档 daily_quests 区块 ConfigFile 序列化正确
- smart_modules 首跑出现过一次 43/44 断言数偶发漏报，复跑两次稳定 44（failed 恒 0，与 P4 manifest flake 同类引擎偶发，与改动无关）

### P6 后世界

开机即签到（连续天数在涨）、完成一次专注/起身响应/按点吃饭/摸摸猫都被猫看见并庆贺，奖励静默喂进亲密度——生活伴侣的日常仪式感闭环。设计边界保持：不催、不领、不挽损，猫是陪伴者不是监工。

## P7 完成记录（2026-08-19）「奶油风 UI 全面重做」

**背景**：用户四项痛点全选（面板乱/风格旧/可用性差/入口混乱），全部 UI 推倒重做。设计文档：`docs/superpowers/specs/2026-08-19-p7-ui-cream-redesign.md`。

### 交付（15 提交）

| 改动 | 说明 |
|---|---|
| UiTheme 主题中心 | components/ui/ui_theme.gd：色板 12 色（奶油白/暖橙/暖棕/肉垫粉）+ 几何/字号 token + 12 个 StyleBoxFlat 工厂函数——全部 UI 唯一视觉来源，纯代码绘制零图片 |
| 设置面板重构 | 57 控件平铺 → 侧边页签 6 页（外观/声音/猫性格/智能/任务·亲密度/关于），代码构建；569 行旧面板+495 行 tscn 推倒重写；改即存 |
| 新增猫大小滑条 | scale_factor 存档链路一直存在但无 UI——补上外观页 |
| 快捷菜单弧形轮盘 | 6 动作绕猫头顶半圆扇形展开（-160°~-20°），64px 正圆粉描边按钮，设置入口移除归抽屉 |
| 聚合抽屉 | 右缘常驻 32px 猫爪圆钮（半透明 hover 实心），点开竖排四按钮（道具/设置/专注/存档），30s 自动收起；替代旧贴边滑入面板（误触多） |
| 气泡换装 | aurora 图片皮 → StyleBoxFlat 奶油底+暖棕 2px 描边+圆角 16，字号 13→15 |
| HUD/托盘 | 专注 HUD 换 token 样式；托盘专注会话入口提前首位 |
| 存档管理承接 | save_manager_panel（独立弹窗）删除，导出/导入/重置四功能并入「关于」页直排 |
| 删除清单 | assets/aurora/ 全目录（CC Credits 文字保留到关于页）、typing_effect_overlay（打字攻击特效，P3 后仅 chaos 小波动猫本体动画已覆盖）、save_manager_panel |

### 接口零破坏

quick_action_menu/bubble/settings_panel/hover_panel 对外信号与函数签名全部不变；main.gd 仅 5 处改动（删 typing 链/面板尺寸/抽屉新信号/穿透区域简化/cat_scale 喂入）；存档键零变化（新增 cat_scale 由面板 collect 顺带持久化）。

### 执行中修正（计划外）

1. 测试 `await get_tree().process_frame` 使协程被 quit 截断——radial 用例三断言静默丢失（26 应为 29），去 await 修复
2. 删除 `_get_typing_attack_duration` 留下孤儿 `return default_duration` 行——Parse Error 当场冒烟抓获
3. `@warning_ignore` 注解位置必须贴在目标语句行前（放在函数体内 return 前无效）

### 验证

- **13 套测试全绿**：286 既有 + **test_ui_theme 29**（token 锁定/工厂返回/页签切换/roundtrip 12 键/轮盘信号）= 315 断言
- presence_level 首跑偶发 31/1（randf 时序 flake，P4 manifest 同类），复跑两次 32/0 稳定
- MCP 端到端：启动零 ERROR；SMART 规则轨道/引导链路正常；删 aurora 后 `grep` 零残留引用；脚本警告从 3 清零
- 视觉走查受限（MCP 后台进程截屏只能捕获终端），桌面端实际观感待用户日常使用确认

### P7 后世界

整个 UI 一套奶油风：面板翻页不翻滚、菜单是猫头顶的一圈圆钮、入口收拢到右缘一颗猫爪、气泡说奶油话。改主题一处改全局——UiTheme 是未来一切 UI 的唯一样式来源。
