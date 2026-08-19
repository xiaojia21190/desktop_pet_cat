# P11 橘猫素材重生成 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 橘猫 28 个实际动作图重生成为循环 12 帧 / 一次性 10 帧，更新 manifest 与 tres，全链回归验收——动画流畅度的素材层质变。

**Architecture:** 薄封装脚本 `tools/p11_regen_actions.py` 复用 pixellab_generate 的生成函数（帧数表注入、旧图备份、单动作失败跳过、质量走查）；生成后链：manifest frames 更新（脚本自动）→ gen_tres_headless 重建 tres → tune_anim_speeds 重落帧率曲线 → 回归 + MCP。

**Tech Stack:** Python（requests/PIL，复用现有）；Godot headless 重建资源；PixelLab API v3。

**设计文档:** `docs/superpowers/specs/2026-08-19-p11-asset-regen-design.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- **key 池**：执行时用户提供 5 个 key 注入 `PIXELLAB_SECRETS`（逗号分隔）环境变量——**不落盘不入库不入文档**
- **已核实代码事实**：
  - `tools/pixellab_generate.py`：`generate_ref` / `generate_action(ref, key)`（帧数从 ACTIONS 表读）/ `stitch` / `save_png` / `request_json` / `poll_job` / key 轮换全部现成，直接 import 复用
  - `generate_action` 的帧数来自模块级 `ACTIONS[key]` 元组第 2 位——**封装脚本运行时 monkeypatch ACTIONS 的帧数值即可**，不动原脚本
  - 橘猫 28 张实际图（`assets/actions/orange_tabby/*.png` 去掉 `_ref_idle`）；循环 12 个 / 一次性 16 个（清单见设计文档，与 ONESHOT_ACTIONS 交集）
  - **manifest 是权威**：`resources/sprite_manifest.json` → `cats.orange_tabby.actions[动作].frames`（44 条目含 tres 命名差条目）；frame_width 全部 128；重建 tres 读 manifest
  - tres 重建：`"$GODOT" --headless --path . --script tools/gen_tres_headless.gd`（遍历全部品种）
  - 帧率/曲线重落：`python tools/tune_anim_speeds.py`（P10 脚本，speed 映射与 ONESHOT 曲线固定）
  - 既有 15 套 389 断言；`test_sprite_manifest_loader` 读 manifest/tres——frames 值变更后若断言锁旧值需同步（数据变更非回归）
  - 生成 API 计费按次：28 动作 ×1 次调用（含重试上限 2 次/动作）

## 文件结构总览

- Task 1 — `tools/p11_regen_actions.py` 封装脚本（帧数表/备份/质量走查/失败记录）
- Task 2 — 首两验：生成 walk + eat，拼新旧对比图，用户确认
- Task 3 — 批量生成其余 26 动作
- Task 4 — manifest frames 更新 + tres 重建 + 帧率重落
- Task 5 — 全量回归 + MCP 真机验收 + 文档收尾

---

### Task 1: 重生成封装脚本

**Files:**
- Create: `tools/p11_regen_actions.py`

- [x] **Step 1: 写 tools/p11_regen_actions.py**

```python
#!/usr/bin/env python3
"""P11 橘猫动作素材重生成：循环 12 帧 / 一次性 10 帧。

用法:
  python tools/p11_regen_actions.py --first-two     # 首两验（walk + eat）
  python tools/p11_regen_actions.py --rest          # 其余 26 动作
  python tools/p11_regen_actions.py --retry walk    # 单动作重抽

依赖 PIXELLAB_SECRETS 环境变量（逗号分隔多 key 自动轮换）。
生成前自动备份旧图到 orange_tabby_p10_backup/；失败动作记 _p11_failed.txt 并保留旧图。
"""
from __future__ import annotations
import argparse, sys, shutil
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import pixellab_generate as plg

sys.stdout.reconfigure(encoding="utf-8")

CAT = "orange_tabby"
OUT_DIR = plg.ROOT / "assets" / "actions" / CAT
BACKUP_DIR = plg.ROOT / "assets" / "actions" / CAT + "_p10_backup" if False else plg.ROOT / "assets" / "orange_tabby_p10_backup"
FRAME_SIZE = 128

# P11 帧数表（与设计文档一致；ONESHOT 16 个 → 10 帧，循环 12 个 → 12 帧）
LOOP_ACTIONS = ["walk", "trot", "run", "chasing", "idle_stand", "idle_sit",
                "idle_lie", "sleep_curl", "watch_focus", "lick_groom", "tail_wag", "rolling"]
ONESHOT_ACTIONS = ["blocking", "carry", "celebrate", "comfort", "dodge", "eat",
                   "greet", "jump", "land", "pounce_attack", "pounce_ready",
                   "retreat", "startled", "stretch", "typing_attack", "yawn"]

def target_frames(key: str) -> int:
    return 12 if key in LOOP_ACTIONS else 10

def backup_once() -> None:
    if BACKUP_DIR.exists():
        return
    BACKUP_DIR.mkdir(parents=True)
    for png in OUT_DIR.glob("*.png"):
        shutil.copy2(png, BACKUP_DIR / png.name)
    print(f"已备份 {len(list(BACKUP_DIR.glob('*.png')))} 张旧图 → {BACKUP_DIR.name}/")

def quality_check(path: Path, expect_frames: int) -> list[str]:
    """返回问题清单（空=通过）：帧数、帧间包围盒抖动。"""
    issues = []
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    frames = w // FRAME_SIZE
    if frames != expect_frames:
        issues.append(f"帧数 {frames} != 目标 {expect_frames}")
        return issues
    # 帧间 alpha 包围盒中心偏移（>24px 判漂移）
    centers = []
    for i in range(frames):
        box = im.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, h)).getbbox()
        if box:
            centers.append(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2))
    for i in range(1, len(centers)):
        dx = abs(centers[i][0] - centers[0][0])
        dy = abs(centers[i][1] - centers[0][1])
        if dx > 24 or dy > 24:
            issues.append(f"帧{i}包围盒偏移 dx={dx:.0f} dy={dy:.0f}（漂移嫌疑）")
            break
    return issues

def regen(key: str) -> bool:
    dest = OUT_DIR / f"{key}.png"
    want = target_frames(key)
    # monkeypatch：把该动作帧数改为目标（保留原描述与 drop_first）
    old_entry = plg.ACTIONS[key]
    action_desc, _old_frames, drop_first = old_entry
    plg.ACTIONS[key] = (action_desc, want, drop_first)
    ref = None
    ref_path = OUT_DIR / "_ref_idle.png"
    try:
        for attempt in range(2):
            try:
                ref = Image.open(ref_path).convert("RGBA") if ref_path.exists() else plg.generate_ref(CAT)
                if not ref_path.exists():
                    plg.save_png(ref, ref_path)
                frames = plg.generate_action(ref, key)
                plg.save_png(plg.stitch(frames), dest)
                issues = quality_check(dest, want)
                if issues:
                    print(f"  [质量] {key}: {'; '.join(issues)}")
                print(f"完成 {key}: {plg.inspect(dest, want)}")
                return True
            except Exception as exc:
                print(f"  {key} 第{attempt + 1}次失败: {exc}")
        return False
    finally:
        plg.ACTIONS[key] = old_entry

def main() -> None:
    parser = argparse.ArgumentParser()
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--first-two", action="store_true")
    g.add_argument("--rest", action="store_true")
    g.add_argument("--retry", metavar="KEY")
    args = parser.parse_args()

    backup_once()
    keys: list[str]
    if args.retry:
        keys = [args.retry]
    elif args.first_two:
        keys = ["walk", "eat"]
    else:
        keys = [k for k in LOOP_ACTIONS + ONESHOT_ACTIONS if k not in ("walk", "eat")]

    failed_path = plg.ROOT / "_p11_failed.txt"
    failed: list[str] = []
    for key in keys:
        print(f"生成 {key}（目标 {target_frames(key)} 帧）...")
        if not regen(key):
            failed.append(key)
            print(f"  [跳过] {key} 保留旧图")
    if failed:
        failed_path.write_text("\n".join(failed), encoding="utf-8")
        print(f"失败清单 → {failed_path.name}: {failed}")
    else:
        failed_path.unlink(missing_ok=True)
        print("全部成功")

if __name__ == "__main__":
    main()
```

（注意 `BACKUP_DIR` 行的写法：直接 `plg.ROOT / "assets" / "actions" / (CAT + "_p10_backup")`——上面三元是笔误演示，执行时写干净版：备份放 `assets/actions/orange_tabby_p10_backup/` 与品种目录平级，**避免被 manifest 的 action_path_template 扫到**。）

- [x] **Step 2: 语法自检**

Run: `python -c "import ast; ast.parse(open('tools/p11_regen_actions.py', encoding='utf-8').read())" && echo OK`
Expected: OK

- [x] **Step 3: Commit**

```bash
git add tools/p11_regen_actions.py
git commit -m "feat: P11素材重生成封装脚本"
```

---

### Task 2: 首两验（walk + eat）

**Files:** 生成产物 `assets/actions/orange_tabby/walk.png` `eat.png`（不入库前的验证阶段）

- [x] **Step 1: 注入 key 池并跑首两动作**

Run: `PIXELLAB_SECRETS="<key1>,<key2>,<key3>,<key4>,<key5>" python tools/p11_regen_actions.py --first-two`
（key 由用户提供，命令行注入不落盘；预计 2 次生成调用 + 轮询）
Expected: `完成 walk`、`完成 eat`，质量行无「漂移嫌疑」

- [x] **Step 2: 拼新旧对比图**

```bash
python - << 'EOF'
from PIL import Image
from pathlib import Path
import sys
sys.stdout.reconfigure(encoding="utf-8")
root = Path(".")
for key in ["walk", "eat"]:
    new = Image.open(f"assets/actions/orange_tabby/{key}.png")
    old = Image.open(f"assets/actions/orange_tabby_p10_backup/{key}.png")
    # 缩放到同高拼接（上下两行：上新下旧，标注宽度差异）
    H = 128
    new_r = new.resize((new.width * H // new.height, H))
    old_r = old.resize((old.width * H // old.height, H))
    W = max(new_r.width, old_r.width)
    canvas = Image.new("RGBA", (W, H * 2 + 8), (40, 40, 40, 255))
    canvas.paste(new_r, (0, 0))
    canvas.paste(old_r, (0, H + 8))
    canvas.save(f".claude/p11_compare_{key}.png")
    print(f"对比图 .claude/p11_compare_{key}.png  新{new_r.width//128}帧 vs 旧{old_r.width//128}帧")
EOF
```

- [x] **Step 3: 视觉分析对比图（vision MCP）**

对 `.claude/p11_compare_{walk,eat}.png` 各跑一次 vision_analyze：问「上行是新生成 12/10 帧、下行是旧 8/7 帧——新生成的动作连贯性/角色一致性/像素风是否明显更好？有无肢体崩坏、残影、角色漂移？」

- [x] **Step 4: 用户终审**

把分析结论呈现给用户：满意 → Task 3；不满意 → `--retry walk` 重抽（≤2 轮）或调 prompt 重抽；仍不行该动作保持旧图（从清单剔除）。

---

### Task 3: 批量生成其余 26 动作

- [x] **Step 1: 跑批量**

Run: `PIXELLAB_SECRETS="<keys>" python tools/p11_regen_actions.py --rest`
（26 次生成 + 轮询，预计 15-40 分钟；额度不足自动切 key）
Expected: 逐个「完成」；失败动作进 `_p11_failed.txt`

- [x] **Step 2: 汇总生成报告**

```bash
python - << 'EOF'
from PIL import Image
from pathlib import Path
import sys
sys.stdout.reconfigure(encoding="utf-8")
d = Path("assets/actions/orange_tabby")
loop = ["walk","trot","run","chasing","idle_stand","idle_sit","idle_lie","sleep_curl","watch_focus","lick_groom","tail_wag","rolling"]
ok, stale = 0, []
for p in sorted(d.glob("*.png")):
    if p.name.startswith("_"): continue
    key = p.stem
    want = 12 if key in loop else 10
    frames = Image.open(p).width // 128
    if frames == want: ok += 1
    else: stale.append(f"{key}={frames}帧(旧)")
fail = Path("_p11_failed.txt")
if fail.exists(): print("生成失败:", fail.read_text(encoding="utf-8"))
print(f"达标 {ok} 个；旧图保留 {len(stale)} 个: {stale}")
EOF
```

- [x] **Step 3: Commit 素材与备份**

```bash
git add assets/actions/orange_tabby/ assets/actions/orange_tabby_p10_backup/
git commit -m "feat: 橘猫28动作高帧数素材重生成"
```

（备份目录一并入库——回滚与后续品种对照用。）

---

### Task 4: manifest 更新 + tres 重建 + 帧率重落

**Files:**
- Modify: `resources/sprite_manifest.json`（orange actions 的 frames 值）
- Modify: `resources/animations/orange_tabby.tres`（gen 重建）
- Create: 脚本化更新（并入 p11_regen_actions.py 或独立小脚本）

- [x] **Step 1: manifest frames 更新脚本（追加到 p11_regen_actions.py）**

```python
def update_manifest() -> None:
    import json
    mf_path = plg.ROOT / "resources" / "sprite_manifest.json"
    mf = json.loads(mf_path.read_text(encoding="utf-8"))
    acts = mf["cats"][CAT]["actions"]
    changed = 0
    for key in LOOP_ACTIONS + ONESHOT_ACTIONS:
        if key in acts and acts[key].get("path", "").endswith(f"{key}.png"):
            want = target_frames(key)
            if acts[key].get("frames") != want:
                acts[key]["frames"] = want
                changed += 1
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest 更新 {changed} 条 frames")
```

（`main()` 里加 `--update-manifest` 参数调用它。注意：实际图仍是旧帧数的动作**不更新**——Step 2 会按图宽校验过滤。改进：循环里先读图宽确认 `Image.open(path).width//128 == want` 才写。）

- [x] **Step 2: 跑 manifest 更新并校验**

Run: `python tools/p11_regen_actions.py --update-manifest`
Expected: `manifest 更新 N 条`（N = 达标动作数）；抽查 `resources/sprite_manifest.json` orange walk frames=12

- [x] **Step 3: tres 重建**

Run: `"/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/gen_tres_headless.gd 2>&1 | grep -E "已生成|完成"`
Expected: `已生成: ...orange_tabby.tres (N 个动画)`、`完成: 6/6`

- [x] **Step 4: 帧率与曲线重落**

Run: `python tools/tune_anim_speeds.py && grep -A1 '"name": &"walk"' resources/animations/orange_tabby.tres | head -2`
Expected: walk speed 10.0；eat duration 曲线 [1.6, 0.7...1.6]

- [x] **Step 5: Commit**

```bash
git add resources/sprite_manifest.json resources/animations/orange_tabby.tres tools/p11_regen_actions.py
git commit -m "feat: 橘猫高帧数manifest与tres重建"
```

---

### Task 5: 全量回归 + MCP 真机验收 + 文档收尾

- [x] **Step 1: 15 套全量测试**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests test_ui_theme test_offline_settlement test_anim_flow; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | grep -E "passed:|failed:|通过:" | tail -2
done
```
Expected: 全绿（test_sprite_manifest_loader 若锁旧 frames 值，按新值更新断言——数据变更非回归）

- [x] **Step 2: MCP 真机动画验收**

- `run_project` 观察 60 秒：待机/走动/行为链动画明显更连贯
- 快捷菜单投食 → chasing → eat 全链（新 10 帧吃动画）
- `stop_project`

- [x] **Step 3: 勾选本计划 + 主文档 P11 完成记录**（含生成报告：成功率/跳过清单/对比图路径）

- [x] **Step 4: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p11-asset-regen.md
git commit -m "docs: P11 完成记录"
```

---

## 附：执行提示

- Task 2 的用户终审是**硬闸门**——首两验不通过不进 Task 3
- key 只进环境变量，任何输出/日志/文档不得出现完整 key
- Task 3 批量跑前确认首两验通过；中途 Ctrl-C 安全（已完成的图保留，重跑只补缺）
- Task 4 manifest 更新必须按实际图宽过滤（失败动作保持旧 frames）
- 生成期间每动作 2 次重试上限，额度池耗尽即停并报告
