# 桌面宠物猫 - Nana Banner 精灵图生成提示词

## 输出规格

- 每帧尺寸：170×139 像素
- 精灵图布局：横向排列多帧
- 背景：透明 PNG
- 风格：萌系卡通 / Q版

---

## Nana Banner 参数设置

```
图片尺寸: 1360x139 (8帧横排) 或 1360x278 (8帧x2行)
采样方法: DPM++ 2M Karras
采样步数: 25-30
CFG Scale: 7
```

---

## 基础提示词模板

### 正向提示词 (Positive)
```
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, [猫咪特征], [动作描述], multiple frames in a row, animation frames
```

### 负向提示词 (Negative)
```
lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry, artist name, background, realistic, 3d render, photo
```

---

## 一、橘猫 (Orange Tabby)

### 猫咪特征
```
orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face
```

### 动作提示词

#### 1. 站立呼吸 (idle_stand) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, standing pose, breathing animation, ears twitching slightly, tail gentle sway, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 2. 坐姿 (idle_sit) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, sitting pose, front paws together, tail wrapped around body, relaxed, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 3. 趴下 (idle_lie) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, lying down, sphinx pose, head up alert, paws forward, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 4. 睡觉 (sleep) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, sleeping, curled up ball, eyes closed, peaceful breathing, zzz, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 5. 行走 (walk) - 8帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, walking cycle, casual stroll, legs moving, tail up, 8 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 6. 奔跑 (run) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, running cycle, fast sprint, legs extended, dynamic pose, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 7. 注视 (watch) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, watching intently, big curious eyes, ears forward, head tilting, focused expression, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 8. 扑击准备 (pounce_ready) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, crouching, ready to pounce, butt wiggle, tail twitching, hunting pose, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 9. 扑击 (pounce) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, pouncing, leaping forward, front paws extended, playful attack, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 10. 傲娇无视 (ignore) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, looking away, nose up in air, eyes closed, tsundere pose, dismissive, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 11. 甩尾 (tail_wag) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, tail wagging, annoyed swishing, ears back slightly, irritated expression, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 12. 翻滚 (roll) - 8帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, rolling on back, playful, belly up, paws in air, happy, 8 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 13. 舔毛 (lick) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, grooming, licking paw, cleaning face, eyes half closed, relaxed, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 14. 吃东西 (eat) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, eating, head down, chewing motion, happy satisfied expression, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 15. 攻击键盘 (typing_attack) - 6帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, paw pressing down, tapping motion, mischievous expression, playful attack, 6 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 16. 开心 (happy) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, happy expression, eyes closed smile, whiskers up, joyful, content, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 17. 生气 (angry) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, angry expression, ears flat back, narrowed eyes, hissing, annoyed, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 18. 摸头撒娇 (head_pat_happy) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, enjoying head pat, eyes closed blissfully, purring, leaning into touch, happy, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 19. 摸头躲闪 (head_pat_dodge) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, dodging head pat, ducking away, annoyed expression, ears back, tsundere, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

#### 20. 偷看 (peek) - 4帧
```
正向:
masterpiece, best quality, game sprite sheet, pixel art style, chibi cat, cute kawaii style, transparent background, consistent character design, clean lines, soft shading, side view, orange tabby cat, ginger fur, darker stripes, yellow-green eyes, pink nose, fluffy tail, round face, peeking sideways, one eye open, pretending not to care, curious but hiding it, tsundere, 4 animation frames in a horizontal row

负向:
lowres, bad anatomy, text, error, cropped, worst quality, low quality, jpeg artifacts, signature, watermark, blurry, background, realistic, 3d
```

---

## 二、其他猫咪 - 替换特征即可

### 三花猫 (Calico)
```
calico cat, tricolor, white base with orange and black patches, green eyes, pink nose, medium fur
```

### 英短蓝猫 (British Shorthair Blue)
```
british shorthair cat, blue-gray fur, round face, copper orange eyes, chubby cheeks, dense plush coat, stocky body
```

### 燕尾服猫 (Tuxedo)
```
tuxedo cat, black and white, black fur with white chest and paws, green eyes, sleek fur, formal looking
```

---

## 快速生成清单

| 动作 | 帧数 | 图片宽度 | 优先级 |
|------|------|----------|--------|
| idle_stand | 6 | 1020px | 必需 |
| idle_sit | 6 | 1020px | 必需 |
| walk | 8 | 1360px | 必需 |
| run | 6 | 1020px | 必需 |
| watch | 4 | 680px | 必需 |
| pounce_ready | 4 | 680px | 必需 |
| pounce | 4 | 680px | 必需 |
| ignore | 4 | 680px | 必需 |
| tail_wag | 6 | 1020px | 必需 |
| roll | 8 | 1360px | 高 |
| lick | 6 | 1020px | 高 |
| eat | 6 | 1020px | 高 |
| typing_attack | 6 | 1020px | 高 |
| happy | 4 | 680px | 高 |
| angry | 4 | 680px | 高 |
| head_pat_happy | 4 | 680px | 中 |
| head_pat_dodge | 4 | 680px | 中 |
| peek | 4 | 680px | 中 |
| sleep | 4 | 680px | 中 |
| idle_lie | 6 | 1020px | 中 |

**计算公式**: 图片宽度 = 帧数 × 170px

---

## Nana Banner 使用技巧

1. **保持一致性**: 同一只猫的所有动作使用相同的种子(seed)值
2. **批量生成**: 使用 X/Y/Z Plot 功能批量生成不同动作
3. **后处理**: 使用 Photoshop/GIMP 裁剪和对齐帧
4. **透明背景**: 启用 "Remove Background" 扩展或使用纯色背景后抠图

---

## 简化版提示词（复制即用）

### 橘猫站立 6帧
```
masterpiece, best quality, game sprite sheet, pixel art, chibi orange tabby cat, cute kawaii, transparent bg, side view, ginger fur, yellow-green eyes, standing, breathing animation, 6 frames horizontal
```

### 橘猫行走 8帧
```
masterpiece, best quality, game sprite sheet, pixel art, chibi orange tabby cat, cute kawaii, transparent bg, side view, ginger fur, yellow-green eyes, walking cycle, 8 frames horizontal
```

### 橘猫扑击 4帧
```
masterpiece, best quality, game sprite sheet, pixel art, chibi orange tabby cat, cute kawaii, transparent bg, side view, ginger fur, yellow-green eyes, pouncing attack, 4 frames horizontal
```

### 橘猫傲娇无视 4帧
```
masterpiece, best quality, game sprite sheet, pixel art, chibi orange tabby cat, cute kawaii, transparent bg, side view, ginger fur, yellow-green eyes, looking away, tsundere pose, 4 frames horizontal
```
