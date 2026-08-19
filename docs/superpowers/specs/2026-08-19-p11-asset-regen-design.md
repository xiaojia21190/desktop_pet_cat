# P11 动画素材重生成（橘猫先行）设计文档

日期：2026-08-19
状态：已确认（用户确认范围/帧数规格/生成方案/两节设计后落档；用户提供 5 个 PixelLab key——仅进运行时环境不落盘）

## 产品定位

**一句话定位**：把橘猫 28 个动作从 3-8 帧升到循环 12 / 一次性 10 帧——P10 代码层榨满旧素材天花板后，帧数翻倍是动画流畅度的素材层质变。

## 核心决策（用户已确认）

| 决策点 | 结论 |
|---|---|
| 范围 | 仅橘猫 28 动作（其他品种后续批次） |
| 帧数 | 循环 12 帧 / 一次性 10 帧 |
| 方案 | A 批量 + 首两验：walk/eat 先行，暂停验质量后继续 |
| 生成渠道 | 用户提供的 5 key 进 PIXELLAB_SECRETS 轮换池，会话内直跑 |

## 生成管线

```
tools/p11_regen_actions.py（新，薄封装）
  ├─ import pixellab_generate（复用参考图/生成/轮换/落盘函数）
  ├─ P11 帧数表覆盖：循环 12 / 一次性 10
  ├─ 生成前备份 assets/actions/orange_tabby/ → orange_tabby_p10_backup/
  ├─ 顺序：walk → eat →（暂停验图）→ 其余 26 按原序
  └─ 每图自动质量走查（帧数/包围盒抖动/fringe）

生成后全链（零新代码）：
  tools/gen_tres_headless.gd 重建 orange_tabby.tres（按新帧数）
  → tools/tune_anim_speeds.py 重落帧率与帧曲线
  → 15 套回归 + MCP 真机验收
```

## P11 帧数表（已按真实文件清单核对：28 动作）

- **循环 12 帧（12 个）**：walk, trot, run, chasing, idle_stand, idle_sit, idle_lie, sleep_curl, watch_focus, lick_groom, tail_wag, rolling
- **一次性 10 帧（16 个）**：eat, pounce_attack, pounce_ready, pounce, greet, celebrate, comfort, stretch, yawn, dodge, startled, typing_attack, blocking, retreat, jump, land, carry, break_hint 中与图集交集——**实际 16 个**：blocking, carry, celebrate, comfort, dodge, eat, greet, jump, land, pounce_attack, pounce_ready, retreat, startled, stretch, typing_attack, yawn

执行注意：`pounce` 与 `break_hint` 不在橘猫图集清单内（breed tres 有 pounce/break_hint 键但 28 图无对应 png——实际是 manifest 与 tres 的历史命名差），P11 只重生**存在的 28 张图**，命名差不动。

## 质量门禁与失败兜底

1. **首两验**：walk + eat 生成即暂停，拼新旧对比图给用户确认；不满意调提示词重抽（≤2 轮），仍不行该动作保持旧帧数
2. **单动作失败**：重试 1 次 → 跳过记 `_p11_failed.txt` → 旧图保留，tres 按实际图配（混帧数天然兼容）
3. **额度不足**：脚本自动轮换下一 key（5 key 池）
4. **质量走查（自动）**：帧数=目标；逐帧 alpha 包围盒中心偏移 >24px 判不稳定标记人工看；透明 fringe 沿用 inspect

## 验收标准

1. 新素材 tres 重建 + 15 套回归全绿
2. MCP 真机：walk 12 帧@10fps 流畅、eat 10 帧完整仪式
3. walk/eat/chase 新旧对比图留档（.claude/ 下不入库）
4. 生成报告：28 动作成功率与跳过清单写入完成记录

## 边界（不做的事）

- 不动其他品种（后续批次）
- 不改提示词主体风格（保持品种一致性，仅按需微调动作描述）
- 不做生成素材的手动修图（不合格就重抽或保持旧图）
- DLC 品种（mochi/dracula）不在本期

## 风险

- Pixellab 高帧数一致性：12 帧可能出现角色漂移——包围盒走查 + 首两验拦截
- 额度：28 动作 × 平均 11 帧一次生成调用/动作（计费按生成次数），5 key 池 + 轮换兜底
