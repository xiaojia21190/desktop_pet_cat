# P7 UI 全面重做（奶油风主题中心化）设计文档

日期：2026-08-19
状态：已确认（用户逐节确认动机/范围/风格/实现方式/面板形态/入口统一/方案/四节设计后落档）

## 产品定位

**一句话定位**：把aurora 游戏皮拼凑的 UI 全部推倒，换成统一的软萌奶油风代码绘制 UI——设置从 57 控件平铺变 6 页签，入口从四套收拢为一套，猫的对话气泡、轮盘菜单、聚合抽屉都有「柔软纸片猫」的视觉气质。

解决四个痛点（用户确认）：面板太乱难用、视觉风格不满意、可用性问题、交互入口混乱。

## 核心决策（用户已确认）

| 决策点 | 结论 |
|---|---|
| 动机 | 四项全选（乱/丑/可用性/入口混乱），全部重做 |
| 范围 | 全部 UI：设置面板/快捷菜单/气泡/悬浮入口/HUD/托盘 |
| 视觉风格 | 软萌奶油风（圆角大、暖色、猫爪元素） |
| 实现方式 | 代码绘制（StyleBoxFlat + 主题常量），零图片依赖 |
| 设置面板形态 | 侧边页签（左页签列 + 右内容区，一次一页） |
| 入口统一 | 聚合抽屉（常驻小圆钮点开，四按钮收拢） |
| 实现方案 | A 主题中心化（ui_theme.gd Design Token） |

## Design Token 主题中心

新建 `components/ui/ui_theme.gd`（`class_name UiTheme extends RefCounted`，纯静态常量 + 工厂函数）。

**色板**：

| Token | 值 | 用途 |
|---|---|---|
| BG | #FFF6E9 | 面板底 |
| SURFACE | #FFFDF7 | 卡片面 |
| CARD | #FFF0D9 | 强调卡片 |
| PRIMARY | #F5A623 | 主色（暖橙） |
| PRIMARY_HOVER | #E8940F | 主色 hover |
| TEXT | #5C4A32 | 主文字（暖棕） |
| TEXT_DIM | #A08B70 | 次文字 |
| SUCCESS | #7FB86A | 成功 |
| DANGER | #E07856 | 失败 |
| PINK | #F7B8C4 | 肉垫粉点缀 |
| SHADOW | #5C4A32 @15% | 阴影 |

**几何 Token**：圆角 S=8 / M=14 / L=22；间距 XS=4 / S=8 / M=16 / L=24；字号 标题20 / 小节16 / 正文14 / 辅助12。

**工厂函数**（返回 StyleBoxFlat）：`panel_style()` `card_style()` `btn_normal(hover)` `btn_primary(hover)` `line_style()` `check_style(on_off)` `slider_track()` `slider_fill()` `bubble_style()` `tab_normal()` `tab_active()`；`tint_label(label, role)` 刷字色字号。

一处改全局变；不使用 .tres 与图片。

## 设置面板重构（侧边页签）

结构（720×560 居中，代码构建，`.tscn` 只留根节点）：

```
SettingsPanel (Panel)
├─ 标题栏：猫爪图标 + 「设置」 + 关闭钮
├─ HBox
│  ├─ TabColumn (140px)：外观/声音/猫性格/智能/任务·亲密度/关于
│  └─ ContentArea (ScrollContainer)：一次一页
└─ 底部状态条：「✓ 已自动保存」
```

**6 页内容**（57 控件归位，每页 ≤12）：

| 页签 | 控件 |
|---|---|
| 外观 | 透明度滑条、置顶、自启、定时隐藏下拉+剩余时间、猫大小 |
| 声音 | 音效、BGM、音量 |
| 猫性格 | 品种（🔒Lv 锁定文案）、性格、活跃度 |
| 智能 | SMART、感知+默认规则、存在感档位、静音时段、LLM 开关/端点/模型/密钥、专注时长 |
| 任务·亲密度 | 今日任务 4 行、连续签到、亲密度进度条、下级解锁 |
| 关于 | 版本、素材 Credits（aurora CC BY 4.0 文字保留）、存档管理区块 |

**行为**：改即存（控件变化即 collect→SaveManager，无保存按钮）；页签切换 0.12s 淡入；开合 0.15s 缩放动画。

## 快捷菜单（弧形轮盘）

- 6 动作绕猫扇形展开（摸摸/逗猫棒/投食/毛线球/纸箱/溜猫），点空白收起；设置入口移除（归抽屉）
- 圆钮 56px 肉垫粉描边 + 24px 图标 + 底部小字；0.15s 弹性展开
- `action_selected(action)` 信号与 action 值不变（main 零改动）

## 气泡与轻提示

- 对话气泡：奶油底 + 暖棕 2px 描边 + 圆角 16 + 指向猫的小尾巴；字号 15
- 亲密度 +N：暖橙胶囊上浮渐隐 2s
- `show_line` / `show_gain_tip` 签名不变
- `typing_effect_overlay`（284 行）删除——自审核实：它是打字攻击特效（`_start_typing_effects` 在 typing_attack 时调用 `start_effect(duration, cat)`），非打字机文本。P3 改造后打字攻击已不扣 focus（改 chaos 小波动），猫本体动画反应已覆盖反馈；删除组件同时删 main.gd 的 `_start_typing_effects` / `_get_typing_attack_duration` 调用链（main.tscn 的 TypingEffectOverlay 节点一并移除）

## 聚合抽屉（替代右缘悬停面板）

- 常驻 32px 猫爪小圆钮贴右缘垂直居中（半透明，hover 实心）
- 点开竖排抽屉：道具/设置/专注会话/存档管理；30s 无操作自动收起
- 信号：保留 `items_requested` `settings_requested`，新增 `focus_requested` `save_requested`
- 删除旧贴边滑入触发（EDGE_TRIGGER 误触多）

## HUD 与托盘

- 专注 HUD 换装 token 样式（奶油卡片+橙填充），布局不动（P3 验证结构）
- 托盘菜单结构不动，「开始/结束专注会话」提前到首位

## 删除清单

| 删除 | 原因 |
|---|---|
| assets/aurora/ 全目录 | 图片皮废弃（Credits 文字保留到「关于」页） |
| typing_effect_overlay.gd/.tscn + main.tscn 节点 + main.gd `_start_typing_effects` 链 | 打字攻击特效；P3 后打字攻击只造成 chaos 小波动，猫本体动画已覆盖反馈 |
| save_manager_panel.gd/.tscn（settings_panel 内嵌弹出，含导出/导入/重置+FileDialog） | 并入「关于」页存档管理区块：保留存档时间/品种信息展示与导出(.catpet)/导入/重置（确认弹窗）四功能，按钮直排 |

## 兼容性承诺

- 快捷菜单/气泡/设置面板/悬浮面板对外信号与函数签名全部不变
- main.gd 仅 3 处改动：删 TypingEffectOverlay 挂载与 `_start_typing_effects` 调用链（main.tscn 节点同删）、settings_panel 内嵌的 save_manager_panel 弹出逻辑移入「关于」页、抽屉新信号接线
- 存档键零变化，用户存档完全兼容
- 既有 12 套测试零 UI 断言依赖，不受影响

## 测试计划（新增 tests/test_ui_theme.gd，约 15 断言）

- theme 工厂返回合法 StyleBoxFlat（圆角/色值抽查 4-5 断言）
- 设置面板 6 页签构建与切换（2-3 断言）
- 新结构下 collect/apply roundtrip 关键 10 键（presence_level/personality/opacity/smart_mode/llm_enabled/quiet_hours/…）
- 快捷菜单 7 按钮构建与 action_selected 信号发射
- 抽屉 4 按钮与信号

## 边界（不做的事）

- 不做皮肤切换系统（明暗双主题留给后续，YAGNI）
- 不动猫本体渲染/动画/状态机（UI 层之外零涉及）
- 不做窗口无边框拖拽调整（Panel 尺寸固定 720×560）
- 托盘菜单只调顺序不加功能

## 验收标准

1. 13 套测试全绿（286 + 新增 ~15）
2. MCP 端到端：启动零错误；轮盘展开收起、6 页签切换、改即存即生效、抽屉四按钮、气泡显示、托盘正常
3. `grep -r aurora` 代码引用零命中（素材目录删除后无死链）
