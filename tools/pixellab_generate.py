#!/usr/bin/env python3
"""用 PixelLab 生成单动作像素条带：先出站立参考，再按动作出帧。"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from io import BytesIO
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
API = "https://api.pixellab.ai/v2"
SIZE = 128
POLL_SEC = 4
POLL_MAX = 90

CATS = {
    "orange_tabby": (
        "chibi orange tabby cat, warm orange fur with darker stripes, "
        "yellow-green eyes, pink nose, fluffy tail, standing idle"
    ),
    "calico": (
        "chibi calico cat, white base coat with orange and black patches, "
        "green eyes, pink nose, fluffy tail, standing idle"
    ),
    "british_blue": (
        "chibi british shorthair blue cat, solid blue-gray plush fur, "
        "round chubby face, copper eyes, stocky body, standing idle"
    ),
    "tuxedo": (
        "chibi tuxedo cat, black body with white chest belly and paws, "
        "green eyes, sleek coat, standing idle"
    ),
}

ACTIONS = {
    "idle_stand": ("gentle idle breathing, chest rise and fall, tail tip twitch, stay in place", 6, False),
    "idle_sit": ("sit down then settle, blink, tiny head tilt, stay seated", 6, False),
    "idle_lie": ("loaf lying pose, relaxed tail tap, stay in place", 6, False),
    "sleep_curl": ("curled sleeping, subtle breathing, eyes closed", 4, False),
    "walk": ("smooth side-view walk cycle facing right, looping gait", 8, True),
    "retreat": ("cautious backward retreat facing right, then reset", 6, False),
    "watch_focus": ("focused stare, tiny head motion, ears alert, stay in place", 4, False),
    "pounce_attack": ("crouch then pounce forward and recover", 4, False),
    "lick_groom": ("lick front paw and wash face, stay in place", 6, False),
    "tail_wag": ("tail wag with slight body sway, stay in place", 6, False),
    "typing_attack": ("rapid paw slaps toward a keyboard on the right, stay in place", 6, False),
    "blocking": ("assertive block stance, paw up, stay in place", 6, False),
    "chasing": ("fast pursuit run cycle facing right", 6, True),
    "eat": ("nibble chew swallow loop, head down, stay in place", 6, False),
    "greet": ("friendly tail-up approach and paw wave, then reset", 6, False),
    "stretch": ("front paw stretch, back arch, then recover to stand", 6, False),
    "yawn": ("sleepy yawn, mouth open then close, reset to stand", 6, False),
    "trot": ("bouncy trot cycle facing right, looping gait", 6, True),
    "run": ("fast compact run cycle facing right, looping gait", 6, True),
    "pounce_ready": ("crouch with butt wiggle, ready to pounce, stay in place", 4, False),
    "dodge": ("quick side dodge then reset to stand", 4, False),
    "startled": ("startled recoil then recover to stand", 4, False),
    "rolling": ("playful roll over then reset to stand", 6, False),
    "carry": ("hold a small fish in mouth and walk facing right", 6, True),
    "celebrate": ("happy bounce and tail swing then reset", 6, False),
    "comfort": ("soft reassuring nod, ears relax, stay in place", 6, False),
    "break_hint": ("stretch then point-like invitation to rest, then reset", 6, False),
    "jump": ("crouch, launch, airborne, fall facing right", 4, False),
    "land": ("contact squash then recover to stand", 4, False),
}

ITEMS = {
    "wand": (
        "pixel art cat teaser wand toy, thin wooden stick with colorful feather "
        "and small bell, side view facing right, game item icon, no cat"
    ),
    "food": (
        "pixel art dried fish cat treat, golden orange fish snack, "
        "cute game item icon, no bowl, no cat"
    ),
    "yarn": (
        "pixel art yarn ball toy, coral red wool ball with loose thread, "
        "cute game item icon, no cat"
    ),
    "box": (
        "pixel art small cardboard box, open top, cute game prop, no cat"
    ),
    "leash": (
        "pixel art cat leash handle, short brown leather strap with metal clip, "
        "game item icon, no cat, no text"
    ),
    "icon_pet": (
        "pixel art cute UI icon of a small hand petting, 64x64 game button icon, no text"
    ),
    "icon_wand": (
        "pixel art cute UI icon of a cat teaser wand, 64x64 game button icon, no text"
    ),
    "icon_food": (
        "pixel art cute UI icon of a dried fish snack, 64x64 game button icon, no text"
    ),
    "icon_leash": (
        "pixel art cute UI icon of a cat leash handle, 64x64 game button icon, no text"
    ),
}


_SECRET_POOL: list[str] = []
_SECRET_INDEX = 0


def _load_secret_pool() -> list[str]:
    raw = os.environ.get("PIXELLAB_SECRETS", "").strip()
    if raw:
        return [item.strip() for item in raw.replace(";", ",").split(",") if item.strip()]
    single = os.environ.get("PIXELLAB_SECRET", "").strip()
    return [single] if single else []


def token() -> str:
    global _SECRET_POOL, _SECRET_INDEX
    if not _SECRET_POOL:
        _SECRET_POOL = _load_secret_pool()
        _SECRET_INDEX = 0
    if not _SECRET_POOL:
        raise SystemExit("缺少 PIXELLAB_SECRET 或 PIXELLAB_SECRETS 环境变量")
    return _SECRET_POOL[_SECRET_INDEX]


def rotate_secret(reason: str) -> bool:
    global _SECRET_INDEX
    if _SECRET_INDEX + 1 >= len(_SECRET_POOL):
        return False
    _SECRET_INDEX += 1
    print(f"  额度不足，切换到第 {_SECRET_INDEX + 1} 个 key ({reason})")
    return True


def headers() -> dict:
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def session() -> requests.Session:
    sess = requests.Session()
    sess.trust_env = False
    return sess


def decode_image(payload) -> Image.Image:
    if isinstance(payload, Image.Image):
        return payload
    raw = payload.get("base64", payload) if isinstance(payload, dict) else payload
    if isinstance(raw, str) and "," in raw and raw.startswith("data:"):
        raw = raw.split(",", 1)[1]
    return Image.open(BytesIO(base64.b64decode(raw))).convert("RGBA")


def encode_image(image: Image.Image) -> dict:
    buf = BytesIO()
    image.save(buf, format="PNG")
    return {"type": "base64", "base64": base64.b64encode(buf.getvalue()).decode(), "format": "png"}


def request_json(method: str, path: str, body=None, timeout=180, retries=4):
    last_error = None
    for attempt in range(retries):
        try:
            resp = session().request(
                method, API + path, headers=headers(), json=body, timeout=timeout
            )
            if resp.status_code == 402 and rotate_secret(resp.text[:120]):
                continue
            if resp.status_code >= 400:
                raise RuntimeError(f"{method} {path} -> {resp.status_code}: {resp.text[:800]}")
            return resp.json()
        except (requests.exceptions.SSLError, requests.exceptions.ConnectionError) as exc:
            last_error = exc
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{method} {path} 网络失败: {last_error}")


def poll_job(job_id: str) -> dict:
    for _ in range(POLL_MAX):
        data = request_json("GET", f"/background-jobs/{job_id}")
        status = data.get("status")
        if status == "completed":
            return data
        if status == "failed":
            raise RuntimeError(f"任务失败: {data}")
        print(f"  等待 {job_id[:8]}... {status}")
        time.sleep(POLL_SEC)
    raise TimeoutError(f"任务超时: {job_id}")


def save_png(image: Image.Image, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def stitch(frames: list[Image.Image]) -> Image.Image:
    width, height = frames[0].size
    sheet = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        if frame.size != (width, height):
            frame = frame.resize((width, height), Image.Resampling.NEAREST)
        sheet.paste(frame, (i * width, 0), frame)
    return sheet


def generate_item(item_key: str) -> Image.Image:
    desc = ITEMS[item_key]
    data = request_json("POST", "/create-image-pixen", {
        "description": f"{desc}, clean 2D chibi pixel art, single object",
        "image_size": {"width": 64, "height": 64},
        "no_background": True,
        "view": "side",
        "outline": "single color black outline",
        "detail": "medium detail",
        "enhance_prompt": True,
    })
    return decode_image(data["image"])


def run_items(keys: list[str]) -> None:
    out_dir = ROOT / "assets" / "items"
    for key in keys:
        dest = out_dir / f"{key}.png"
        if dest.exists():
            print("已存在，跳过:", dest.name)
            continue
        print("生成道具", key, "...")
        image = generate_item(key)
        save_png(image, dest)
        print("完成:", inspect(dest, 1))


def generate_ref(cat_id: str) -> Image.Image:
    desc = CATS[cat_id]
    data = request_json("POST", "/create-image-pixen", {
        "description": f"{desc}, side view, facing right, clean pixel art game sprite",
        "image_size": {"width": SIZE, "height": SIZE},
        "no_background": True,
        "view": "side",
        "direction": "east",
        "outline": "single color black outline",
        "detail": "medium detail",
        "enhance_prompt": True,
    })
    return decode_image(data["image"])


def generate_action(first_frame: Image.Image, action_key: str) -> list[Image.Image]:
    action, frames, drop_first = ACTIONS[action_key]
    payload = {
        "first_frame": encode_image(first_frame),
        "action": action,
        "frame_count": frames,
        "no_background": True,
        "enhance_prompt": True,
    }
    try:
        job = request_json("POST", "/animate-with-text-v3", payload)
    except RuntimeError as exc:
        if "enhance" not in str(exc).lower() and "500" not in str(exc):
            raise
        print(f"  {action_key} 增强失败，改为直接生成")
        payload["enhance_prompt"] = False
        job = request_json("POST", "/animate-with-text-v3", payload)
    result = poll_job(job["background_job_id"])
    images = (result.get("last_response") or {}).get("images") or []
    if not images:
        raise RuntimeError(f"{action_key} 没有返回帧: {json.dumps(result)[:500]}")
    decoded = [decode_image(item) for item in images]
    if drop_first and len(decoded) > 1:
        return decoded[1:]
    return decoded


def inspect(path: Path, cols: int) -> str:
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    cell_w = width // cols
    alpha = image.getchannel("A")
    values = list(alpha.tobytes())
    opaque = sum(1 for value in values if value > 10)
    fringe = sum(1 for value in values if 0 < value < 250)
    return f"{path.name} {width}x{height} cell={cell_w}x{height} opaque={opaque} fringe={fringe}"


def run_smoke(cat_id: str) -> None:
    out_dir = ROOT / "assets" / "actions" / cat_id
    print("查余额...")
    balance = request_json("GET", "/balance")
    print(json.dumps(balance, ensure_ascii=False))
    print("生成站立参考...")
    ref = generate_ref(cat_id)
    ref_path = save_png(ref, out_dir / "_ref_idle.png")
    print("参考图:", inspect(ref_path, 1))
    print("生成 idle_stand...")
    frames = generate_action(ref, "idle_stand")
    sheet_path = save_png(stitch(frames), out_dir / "idle_stand.png")
    print("动作图:", inspect(sheet_path, len(frames)))


def run_batch(cat_id: str, keys: list[str]) -> None:
    out_dir = ROOT / "assets" / "actions" / cat_id
    ref_path = out_dir / "_ref_idle.png"
    ref = Image.open(ref_path).convert("RGBA") if ref_path.exists() else generate_ref(cat_id)
    if not ref_path.exists():
        save_png(ref, ref_path)
        print("参考图:", inspect(ref_path, 1))
    for key in keys:
        dest = out_dir / f"{key}.png"
        if dest.exists():
            print("已存在，跳过:", dest.name)
            continue
        print("生成", key, "...")
        frames = generate_action(ref, key)
        save_png(stitch(frames), dest)
        print("完成:", inspect(dest, len(frames)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cat", default="orange_tabby")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--actions", nargs="*")
    parser.add_argument("--items", nargs="*")
    args = parser.parse_args()
    if args.items is not None:
        keys = args.items or list(ITEMS)
        unknown = [key for key in keys if key not in ITEMS]
        if unknown:
            raise SystemExit(f"未知道具: {unknown}")
        run_items(keys)
        return
    if args.cat not in CATS:
        raise SystemExit(f"未知猫咪: {args.cat}")
    if args.smoke:
        run_smoke(args.cat)
        return
    keys = args.actions or list(ACTIONS)
    unknown = [key for key in keys if key not in ACTIONS]
    if unknown:
        raise SystemExit(f"未知动作: {unknown}")
    run_batch(args.cat, keys)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("失败:", exc, file=sys.stderr)
        sys.exit(1)
