# Nano Banner Pro 全量动作重生提示词（单动作单图）

## 1. 通用模板

```text
Create a 2D chibi pixel-art cat sprite sheet.
Style: clean pixel art, soft shading, no anti-alias blur, transparent background.
Direction: ALWAYS face RIGHT.
Grid: 1 row x 8 columns.
Cell size: 170x139 px.
Canvas: 1360x139 px.
Keep body proportions consistent with previous outputs.
No watermark, no text, no extra props unless requested.
Character: [CAT_PROFILE]
Action: [ACTION_SPEC]
Frames: [FRAME_SPEC]
If frames < 8, leave remaining cells fully transparent.
```

## 2. 猫咪外观块（CAT_PROFILE）

- `orange_tabby`: warm orange fur, dark stripes, yellow-green eyes, pink nose, fluffy tail.
- `calico`: white base with black+orange patches, green eyes, pink nose.
- `british_blue`: solid blue-gray fur, round face, copper eyes, plush coat.
- `tuxedo`: black body with white chest/belly/paws, green eyes.

## 3. 动作定义（ACTION_SPEC + FRAME_SPEC）

- `idle_stand`: calm standing breathing, ear twitch, `6 frames`
- `idle_sit`: sit settle, blink, tiny head tilt, `6 frames`
- `idle_lie`: loaf pose, tail tap, relaxed, `6 frames`
- `sleep_curl`: curled sleeping with subtle breathing, `4 frames`
- `stretch`: front stretch, back arch, recover, `6 frames`
- `yawn`: mouth open-close, sleepy reset, `6 frames`

- `walk`: smooth walk cycle, `8 frames`
- `trot`: bouncy trot cycle, `6 frames`
- `run`: fast run cycle, compact arcs, `6 frames`
- `jump`: crouch-launch-airborne-fall, `4 frames`
- `land`: contact-squash-recover-stand, `4 frames`
- `retreat`: cautious backward/side retreat, `6 frames`

- `watch_focus`: focused stare with tiny head motion, `4 frames`
- `pounce_ready`: crouch with butt wiggle prep, `4 frames`
- `pounce_attack`: launch-hit-recover, `4 frames`
- `dodge`: quick side dodge and reset, `4 frames`
- `startled`: startled recoil then recover, `4 frames`

- `lick_groom`: lick paw/leg and face wash, `6 frames`
- `tail_wag`: tail wag with slight body sway, `6 frames`
- `typing_attack`: rapid paw hit rhythm toward keyboard direction, `6 frames`
- `blocking`: block posture, assertive front stance, `6 frames`
- `chasing`: pursuit run with intent, `6 frames`
- `rolling`: playful roll over and reset, `6 frames`
- `eat`: nibble-chew-swallow loop, `6 frames`
- `carry`: hold item in mouth and move, `6 frames`

- `greet`: friendly tail-up approach and paw wave, `6 frames`
- `celebrate`: happy bounce and tail swing, `6 frames`
- `comfort`: soft posture, gentle nod, reassuring, `6 frames`
- `break_hint`: stretch/point-like invitation to rest, `6 frames`

## 4. 命名规范

```text
{cat_id}_{action_key}.png
```

示例：

- `orange_tabby_idle_stand.png`
- `calico_comfort.png`
- `british_blue_typing_attack.png`
- `tuxedo_retreat.png`

## 5. 生成顺序建议

1. 先生成 `orange_tabby` 全动作，确定风格基线。
2. 基线通过后替换 `CAT_PROFILE` 批量生成其余 3 只猫。
3. 每批次按 `sprite_generation_checklist.md` 验收后再导入。
