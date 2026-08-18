# -*- coding: utf-8 -*-
"""皮肤包 DLC 接入：把 CatMegaFree/CatPackFree 的猫素材转换为现有 manifest 帧规格（128x128）。
Mochi Idle 320x32 = 10 帧 32x32 行走循环 → 放大 4x 为 128 帧 → 派生 idle_stand/walk 等基础动作。
Dracula 192x32 = 6 帧 32x32。
策略：低分辨率素材用最近邻放大保持像素风锐度；为 44 动作全集提供回退（manifest 已有 sheet 回退机制，
这里生成可用动作图 + sheet_path 兜底其余动作）。"""
from PIL import Image
import os, json

SRC_MOCHI = r'D:\code\desktop_pet_cat\CatMegaFree\CatMegaFree\MochiFree\Idle.png'
SRC_DRACULA = r'D:\code\desktop_pet_cat\CatPackFree\CatPackFree\drculacat.png'
FRAME = 128

def upscale_strip(src_path, out_dir, frames):
    """32px 帧条 → 128px 帧条（最近邻 4x），输出单行动作图"""
    os.makedirs(out_dir, exist_ok=True)
    img = Image.open(src_path).convert('RGBA')
    fw = img.width // frames
    out = Image.new('RGBA', (frames * FRAME, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        frame = img.crop((i * fw, 0, (i + 1) * fw, img.height))
        # 帧内贴底居中放大到 128
        scale = FRAME // max(fw, img.height)
        big = frame.resize((frame.width * scale, frame.height * scale), Image.NEAREST)
        px = (FRAME - big.width) // 2
        py = FRAME - big.height  # 贴底（猫站地面）
        out.alpha_composite(big, (px, py))
    return out

def main():
    gen = {}
    # Mochi：10 帧行走 → walk 动作图；前 4 帧做 idle_stand（站立微动）
    mochi_walk = upscale_strip(SRC_MOCHI, r'D:\code\desktop_pet_cat\assets\actions\mochi', 10)
    mochi_walk.save(r'D:\code\desktop_pet_cat\assets\actions\mochi\walk.png')
    idle = mochi_walk.crop((0, 0, 4 * FRAME, FRAME))
    idle.save(r'D:\code\desktop_pet_cat\assets\actions\mochi\idle_stand.png')
    gen['mochi'] = {'frames_walk': 10, 'frames_idle': 4}

    # Dracula：6 帧
    dr_walk = upscale_strip(SRC_DRACULA, r'D:\code\desktop_pet_cat\assets\actions\dracula', 6)
    dr_walk.save(r'D:\code\desktop_pet_cat\assets\actions\dracula\walk.png')
    dr_idle = dr_walk.crop((0, 0, 3 * FRAME, FRAME))
    dr_idle.save(r'D:\code\desktop_pet_cat\assets\actions\dracula\idle_stand.png')
    gen['dracula'] = {'frames_walk': 6, 'frames_idle': 3}
    print(json.dumps(gen))

if __name__ == '__main__':
    main()
