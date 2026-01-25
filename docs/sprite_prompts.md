没问题！这是根据你要求的**严格网格与逐帧描述格式**，重写了全部 40 个动作的提示词。

为了方便你生成和管理，我按照你之前规划的**6 个文件分组**（基础、移动、互动、傲娇、日常、特殊）将它们拆分为 **6 个独立的 Prompt**。

---

### ⚠️ 使用说明

1. **通用语言**：为了保证生成质量，提示词内容使用**英文**（目前主流 AI 对英文理解最好）。
2. **角色替换**：所有 Prompt 默认使用了 **橘猫 (Orange Tabby)** 的设定。如果你要生成其他猫，请直接替换每个 Prompt 中的 `***CRITICAL CHARACTER DESIGN***` 模块。
3. **网格统一**：所有 Prompt 均设定为 **8 列 (Columns)**。
* 如果是 4 帧动作，第 5-8 格标记为 `EMPTY`。
* 如果是 6 帧动作，第 7-8 格标记为 `EMPTY`。
* 这样能确保切图时逻辑一致。



---

### 📋 角色特征模块 (复制替换用)

在生成不同猫咪时，请用以下对应的块替换提示词中的 `***CRITICAL CHARACTER DESIGN***` 部分：

**橘猫 (默认):**

```markdown
***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.
- **Vibe:** Energetic and friendly.

```

**三花猫:**

```markdown
***CRITICAL CHARACTER DESIGN***
- **Subject:** Calico cat (Tricolor).
- **Key Features:** White base coat with random patches of orange and black, green eyes, pink nose.
- **Vibe:** Independent and unique.

```

**英短蓝猫:**

```markdown
***CRITICAL CHARACTER DESIGN***
- **Subject:** British Shorthair Blue cat.
- **Key Features:** Solid blue-gray fur, round chubby face, copper/orange eyes, dense plush coat, stocky body.
- **Vibe:** Calm and dignified.

```

**燕尾服猫:**

```markdown
***CRITICAL CHARACTER DESIGN***
- **Subject:** Tuxedo cat (Black and White).
- **Key Features:** Mostly black body with white chest, belly, and paws (like a suit), green eyes.
- **Vibe:** Formal and sleek.

```

---

### 📂 文件 1：基础状态 (Basic State)

*包含：站立, 坐下, 趴下, 睡觉, 伸懒腰, 打哈欠*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Basic Actions).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline, game asset style.
- **Background:** Transparent PNG (or Solid Magenta #FF00FF).
- **Grid:** Strict 6 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.
- **Canvas Size:** 1360x834 pixels.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***
- In ALL rows, the cat must be facing RIGHT (East).

***ANIMATION ROWS***

**Row 1: Idle Stand (6 Frames)**
- Frame 1: Neutral standing pose, tail down.
- Frame 2: Chest expands slightly (breathing in).
- Frame 3: Chest contracts (breathing out), tail tip twitches.
- Frame 4: Neutral stand, ears flicker.
- Frame 5: Head turns slightly to viewer then back.
- Frame 6: Return to neutral.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 2: Idle Sit (6 Frames)**
- Frame 1: Standing to sitting transition (lowering rear).
- Frame 2: Fully seated, front paws straight.
- Frame 3: Tail wraps around paws smoothly.
- Frame 4: Eyes blink closed.
- Frame 5: Eyes open, head tilts slightly.
- Frame 6: Hold sitting pose.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 3: Idle Lie Down (6 Frames)**
- Frame 1: Sitting to lying transition (front paws slide forward).
- Frame 2: Sphinx pose (loaf), head up alert.
- Frame 3: Head lowers slightly, relaxed.
- Frame 4: Tail gently taps the floor.
- Frame 5: Ears swivel listening.
- Frame 6: Alert sphinx pose again.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 4: Sleep (4 Frames)**
- Frame 1: Curled up tightly in a ball.
- Frame 2: Eyes fully closed, body expands (breathe in).
- Frame 3: Body contracts (breathe out), "Zzz" bubble appears.
- Frame 4: Hold sleep pose with Zzz.
- Frame 5-8: EMPTY / TRANSPARENT.

**Row 5: Stretch (6 Frames)**
- Frame 1: Standing, preparing to stretch.
- Frame 2: Front legs slide forward, chest lowers.
- Frame 3: Back arches high (Halloween cat pose).
- Frame 4: Rear legs extend back (long cat).
- Frame 5: Shake body to reset.
- Frame 6: Return to standing.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 6: Yawn (6 Frames)**
- Frame 1: Sitting, mouth closed.
- Frame 2: Mouth opens slightly, eyes squint.
- Frame 3: Mouth wide open, tongue visible, big yawn.
- Frame 4: Hold yawn, eyes closed tight.
- Frame 5: Mouth closing, smacking lips.
- Frame 6: Return to neutral sit.
- Frame 7-8: EMPTY / TRANSPARENT.

```

---

### 📂 文件 2：移动 (Movement)

*包含：行走, 小跑, 奔跑, 跳跃, 落地, 转身*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Movement).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline.
- **Background:** Transparent PNG (or Solid Magenta #FF00FF).
- **Grid:** Strict 6 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***

***ANIMATION ROWS***

**Row 1: Walk Cycle (8 Frames)**
- Frame 1: Right front paw forward (contact).
- Frame 2: Body lowest point (passing).
- Frame 3: Left front paw passing.
- Frame 4: Left front paw forward (contact).
- Frame 5: Body highest point (crossover).
- Frame 6: Right back paw passing.
- Frame 7: Tail sways left.
- Frame 8: Tail sways right, loop close.

**Row 2: Trot (6 Frames)**
- Frame 1: Bouncy step, head held high.
- Frame 2: Mid-air float momentarily.
- Frame 3: Landing on opposite diagonal paws.
- Frame 4: Compress for next bounce.
- Frame 5: Tail bounces up.
- Frame 6: Happy expression while moving.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 3: Run Cycle (6 Frames)**
- Frame 1: Full extension (airborne), legs stretched front and back.
- Frame 2: Front paws land, body compresses.
- Frame 3: Back legs tuck under body.
- Frame 4: Back legs kick off ground.
- Frame 5: Ears pinned back for speed.
- Frame 6: Dust cloud effect behind paws.
- Frame 7-8: EMPTY / TRANSPARENT.

**Row 4: Jump (4 Frames)**
- Frame 1: Crouch down low, loading energy.
- Frame 2: Launch upward, body stretched vertical.
- Frame 3: Mid-air peak, paws tucked in.
- Frame 4: Falling phase, looking at ground.
- Frame 5-8: EMPTY / TRANSPARENT.

**Row 5: Land (4 Frames)**
- Frame 1: First contact with ground (toes).
- Frame 2: Deep squash to absorb impact.
- Frame 3: Recovering, standing up.
- Frame 4: Return to neutral stand.
- Frame 5-8: EMPTY / TRANSPARENT.

**Row 6: Turn Around (4 Frames)**
- Frame 1: Facing Right.
- Frame 2: Body turns towards camera (Front view).
- Frame 3: Body turns away (Back view/Butt visible).
- Frame 4: Facing Left (Mirror of Frame 1).
- Frame 5-8: EMPTY / TRANSPARENT.

```

---

### 📂 文件 3：互动反应 (Interaction)

*包含：注视, 扑击准备, 扑击, 躲闪, 被吓到, 摸头撒娇, 摸头躲闪*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Interaction).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline.
- **Background:** Transparent PNG.
- **Grid:** Strict 7 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***

***ANIMATION ROWS***

**Row 1: Watch/Focus (4 Frames)**
- Frame 1: Head lowers, eyes widen (pupils dilate).
- Frame 2: Head tilts left slightly.
- Frame 3: Head tilts right slightly.
- Frame 4: Intense stare, tail twitching nervously.
- Frame 5-8: EMPTY.

**Row 2: Pounce Ready (4 Frames)**
- Frame 1: Low crouch, butt in air.
- Frame 2: Butt wiggles left.
- Frame 3: Butt wiggles right.
- Frame 4: Rear legs tread ground, ready to launch.
- Frame 5-8: EMPTY.

**Row 3: Pounce Attack (4 Frames)**
- Frame 1: Launch forward, claws extended.
- Frame 2: Mid-air flying towards target.
- Frame 3: Landing with paws slamming down.
- Frame 4: Bit/Grab motion with mouth.
- Frame 5-8: EMPTY.

**Row 4: Dodge (4 Frames)**
- Frame 1: Neutral stand.
- Frame 2: Sudden jump backwards/sideways.
- Frame 3: Land in defensive crouch.
- Frame 4: Wide eyes, alert.
- Frame 5-8: EMPTY.

**Row 5: Startled/Scared (4 Frames)**
- Frame 1: Sudden freeze frame.
- Frame 2: Fur puffs up, back arches, tail straight up.
- Frame 3: Hissing mouth open.
- Frame 4: Shaking slightly.
- Frame 5-8: EMPTY.

**Row 6: Head Pat Happy (4 Frames)**
- Frame 1: Hand (cursor) approaches, cat looks up.
- Frame 2: Cat closes eyes, leans head up into hand.
- Frame 3: Cat rubs cheek against imaginary hand.
- Frame 4: Happy hearts float up.
- Frame 5-8: EMPTY.

**Row 7: Head Pat Dodge (4 Frames)**
- Frame 1: Hand (cursor) approaches.
- Frame 2: Cat ducks head down quickly.
- Frame 3: Cat backs away slightly, ears flat (airplane ears).
- Frame 4: Annoyed expression.
- Frame 5-8: EMPTY.

```

---

### 📂 文件 4：傲娇行为 (Tsundere)

*包含：无视, 傲娇走开, 偷看, 甩尾, 翻滚, 偷吃*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Tsundere/Attitude).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline.
- **Background:** Transparent PNG.
- **Grid:** Strict 6 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***

***ANIMATION ROWS***

**Row 1: Ignore/Snub (4 Frames)**
- Frame 1: Cat sitting, looking at viewer.
- Frame 2: Sharp head turn away (nose in air).
- Frame 3: Eyes close ("Hmph!").
- Frame 4: Hold pose, ignoring viewer.
- Frame 5-8: EMPTY.

**Row 2: Walk Away Proudly (6 Frames)**
- Frame 1: Turn back to viewer.
- Frame 2: Walk away, tail held perfectly vertical.
- Frame 3: Butt sway exaggerated.
- Frame 4: Pause, look back over shoulder.
- Frame 5: Turn head forward again ("I don't care").
- Frame 6: Resume walking away.
- Frame 7-8: EMPTY.

**Row 3: Peek (4 Frames)**
- Frame 1: Hiding behind paws or low to ground.
- Frame 2: One eye opens to check surroundings.
- Frame 3: Head pops up slightly.
- Frame 4: Quickly hides again.
- Frame 5-8: EMPTY.

**Row 4: Tail Wag Annoyed (6 Frames)**
- Frame 1: Sitting, ears slightly back.
- Frame 2: Tail flicks sharply to the left.
- Frame 3: Tail pauses.
- Frame 4: Tail flicks sharply to the right.
- Frame 5: Tail tip twitches.
- Frame 6: Grumpy expression.
- Frame 7-8: EMPTY.

**Row 5: Roll/Playful (8 Frames)**
- Frame 1: Lie on stomach.
- Frame 2: Roll onto side.
- Frame 3: Roll onto back, belly exposed.
- Frame 4: Wiggle on back, paws in air.
- Frame 5: Roll to other side.
- Frame 6: Roll back to stomach.
- Frame 7: Shake head dizzily.
- Frame 8: Reset.

**Row 6: Sneak Eat (6 Frames)**
- Frame 1: Low profile sneak pose.
- Frame 2: Look left and right (paranoid).
- Frame 3: Quick snatch/bite at food.
- Frame 4: Chewing fast.
- Frame 5: Gulp.
- Frame 6: Look innocent (whistle).
- Frame 7-8: EMPTY.

```

---

### 📂 文件 5：日常行为 (Daily Life)

*包含：舔毛, 喝水, 吃东西, 叼东西, 磨爪, 踩奶*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Daily Life).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline.
- **Background:** Transparent PNG.
- **Grid:** Strict 6 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***

***ANIMATION ROWS***

**Row 1: Lick/Groom (6 Frames)**
- Frame 1: Sitting, leg extended up (chicken leg pose).
- Frame 2: Tongue out, licking leg.
- Frame 3: Tongue retraction.
- Frame 4: Licking paw.
- Frame 5: Rubbing paw on face (face wash).
- Frame 6: Pause to look around.
- Frame 7-8: EMPTY.

**Row 2: Drink Water (6 Frames)**
- Frame 1: Crouching over bowl.
- Frame 2: Head dips down.
- Frame 3: Tongue lapping motion (down).
- Frame 4: Tongue lapping motion (up).
- Frame 5: Head up, swallowing.
- Frame 6: Water droplet drips from chin.
- Frame 7-8: EMPTY.

**Row 3: Eat Food (6 Frames)**
- Frame 1: Crouching, happy anticipation.
- Frame 2: Bite down on food pile.
- Frame 3: Head up, chewing (cheek bulge).
- Frame 4: Chewing motion.
- Frame 5: Swallow.
- Frame 6: Lick lips.
- Frame 7-8: EMPTY.

**Row 4: Carry Item (6 Frames)**
- Frame 1: Mouth holding a generic pixel object (fish/toy).
- Frame 2: Walking pose with object, head held high.
- Frame 3: Mid-step, object sways.
- Frame 4: Pause, adjust grip on object.
- Frame 5: Continue walking.
- Frame 6: Muffled meow (mouth full).
- Frame 7-8: EMPTY.

**Row 5: Scratch/Sharpen Claws (6 Frames)**
- Frame 1: Standing near vertical surface (imaginary post).
- Frame 2: Reach up high with both paws.
- Frame 3: Drag paws down, claws visible.
- Frame 4: Reach up again.
- Frame 5: Drag down vigorously.
- Frame 6: Satisfied stretch.
- Frame 7-8: EMPTY.

**Row 6: Kneading/Biscuits (6 Frames)**
- Frame 1: Standing on soft surface.
- Frame 2: Push Left paw down, Right paw up.
- Frame 3: Push Right paw down, Left paw up.
- Frame 4: Eyes half-closed, purring face.
- Frame 5: Repeat kneading motion.
- Frame 6: Happy trance state.
- Frame 7-8: EMPTY.

```

---

### 📂 文件 6：特殊动作 (Special Actions)

*包含：攻击键盘, 推东西, 惊讶, 开心, 生气, 委屈, 困惑, 发呆, 打喷嚏*

```markdown
A pixel art sprite sheet of a cute Kawaii Cat character (Special/Emotes).

***GLOBAL CONSTRAINTS***
- **Style:** 2D chibi pixel art, soft pastel colors, clean lines, white outline.
- **Background:** Transparent PNG.
- **Grid:** Strict 9 Rows x 8 Columns.
- **Cell Size:** 170x139 pixels per cell.

***CRITICAL CHARACTER DESIGN***
- **Subject:** Orange tabby cat / ginger cat.
- **Key Features:** Warm orange fur with distinct darker stripes, yellow-green eyes, pink nose, fluffy tail.

***DIRECTION RULE: ALWAYS FACE RIGHT***

***ANIMATION ROWS***

**Row 1: Typing Attack (6 Frames)**
- Frame 1: Standing over keyboard.
- Frame 2: Rapidly patting with left paw.
- Frame 3: Rapidly patting with right paw.
- Frame 4: Both paws slam down.
- Frame 5: Mischievous grin.
- Frame 6: Pause to see chaos caused.
- Frame 7-8: EMPTY.

**Row 2: Push Object (4 Frames)**
- Frame 1: Paw hovering near object (cup).
- Frame 2: Slow deliberate touch.
- Frame 3: Sudden hard shove.
- Frame 4: Watching object fall (evil satisfaction).
- Frame 5-8: EMPTY.

**Row 3: Surprised (4 Frames)**
- Frame 1: Neutral.
- Frame 2: Eyes pop open wide, ears perk up vertical.
- Frame 3: Mouth forms small 'o'.
- Frame 4: Exclamation mark ! appears above head.
- Frame 5-8: EMPTY.

**Row 4: Happy (4 Frames)**
- Frame 1: Eyes close in upside down U shape (smile).
- Frame 2: Mouth opens in smile.
- Frame 3: Flowers/sparkles appear around head.
- Frame 4: Head bobs side to side.
- Frame 5-8: EMPTY.

**Row 5: Angry (4 Frames)**
- Frame 1: Brows furrow, eyes narrow.
- Frame 2: Vein pops symbol.
- Frame 3: Mouth opens to hiss.
- Frame 4: Red face/fuming breath.
- Frame 5-8: EMPTY.

**Row 6: Sad (4 Frames)**
- Frame 1: Ears droop down low.
- Frame 2: Eyes water, tears forming.
- Frame 3: Head hangs low.
- Frame 4: Single tear drop falls.
- Frame 5-8: EMPTY.

**Row 7: Confused (4 Frames)**
- Frame 1: One ear up, one ear down.
- Frame 2: Head tilts 45 degrees.
- Frame 3: Question mark ? appears.
- Frame 4: Blink slowly.
- Frame 5-8: EMPTY.

**Row 8: Daze/Zoned Out (4 Frames)**
- Frame 1: Blank stare, eyes unfocused.
- Frame 2: Mouth hangs slightly open.
- Frame 3: Soul leaving body ghost effect (subtle).
- Frame 4: Drool bubble.
- Frame 5-8: EMPTY.

**Row 9: Sneeze (4 Frames)**
- Frame 1: Inhale deep, nose scrunching.
- Frame 2: Head tilts back.
- Frame 3: Violent forward motion (ACHOO!).
- Frame 4: Shake head to recover.
- Frame 5-8: EMPTY.

```
