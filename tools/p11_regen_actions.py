#!/usr/bin/env python3
"""P11 橘猫动作素材重生成：循环 12 帧 / 一次性 10 帧。

用法:
  python tools/p11_regen_actions.py --first-two     # 首两验（walk + eat）
  python tools/p11_regen_actions.py --rest          # 其余 26 动作
  python tools/p11_regen_actions.py --retry walk    # 单动作重抽
  python tools/p11_regen_actions.py --update-manifest  # 按实际图宽更新 manifest frames

依赖 PIXELLAB_SECRETS 环境变量（逗号分隔多 key 自动轮换）。
生成前自动备份旧图；失败动作记 _p11_failed.txt 并保留旧图。
"""
from __future__ import annotations
import argparse, json, shutil, sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import pixellab_generate as plg

sys.stdout.reconfigure(encoding="utf-8")

CAT = "orange_tabby"
OUT_DIR = plg.ROOT / "assets" / "actions" / CAT
# 备份与品种目录平级——避免被 manifest 的 action_path_template 扫到
BACKUP_DIR = plg.ROOT / "assets" / "actions" / (CAT + "_p10_backup")
FRAME_SIZE = 128

# P11 帧数表（与设计文档一致；循环 12 个 → 12 帧，一次性 16 个 → 10 帧）
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
    # monkeypatch：该动作帧数改为目标（保留原描述与 drop_first）
    old_entry = plg.ACTIONS[key]
    action_desc, _old_frames, drop_first = old_entry
    plg.ACTIONS[key] = (action_desc, want, drop_first)
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

def update_manifest() -> None:
    """按实际图宽更新 manifest 的 orange frames（失败/旧图动作不动）。"""
    mf_path = plg.ROOT / "resources" / "sprite_manifest.json"
    mf = json.loads(mf_path.read_text(encoding="utf-8"))
    acts = mf["cats"][CAT]["actions"]
    changed = 0
    for key in LOOP_ACTIONS + ONESHOT_ACTIONS:
        entry = acts.get(key)
        if not entry:
            continue
        png = OUT_DIR / f"{key}.png"
        if not png.exists():
            continue
        actual = Image.open(png).width // FRAME_SIZE
        if actual != target_frames(key):
            continue  # 旧图/失败保留，不更新
        if entry.get("frames") != actual:
            entry["frames"] = actual
            changed += 1
    mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest 更新 {changed} 条 frames")

def main() -> None:
    parser = argparse.ArgumentParser()
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--first-two", action="store_true")
    g.add_argument("--rest", action="store_true")
    g.add_argument("--retry", metavar="KEY")
    g.add_argument("--update-manifest", action="store_true")
    args = parser.parse_args()

    if args.update_manifest:
        update_manifest()
        return

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
