# P10 帧率批量调优 + 一次性动作帧时长曲线写入 tres
# 1) speed 按动作类别映射新值（设计文档规则）
# 2) 一次性动作的每帧 duration 按曲线写入（首尾帧 1.6、中间 0.7）
#    ——Godot 4.7 无运行时 set_frame_duration，曲线必须落盘到 tres
# 用法：python tools/tune_anim_speeds.py
import re, glob, sys
sys.stdout.reconfigure(encoding="utf-8")

SPEED_MAP = {
    # 待机（更耐看）
    "idle_stand": 4.0, "idle_sit": 4.0, "idle_lie": 4.0, "idle_active": 6.0,
    # 移动（更快更连贯）
    "walk": 10.0, "trot": 11.0, "run": 12.0, "chasing": 11.0,
    # 互动（+1~2）
    "eat": 8.0, "pounce_attack": 11.0, "pounce_ready": 9.0, "pounce": 11.0,
    "greet": 9.0, "celebrate": 10.0, "comfort": 7.0, "dodge": 11.0,
    "startled": 9.0, "kneading": 6.0, "carry": 8.0, "typing_attack": 11.0,
    "blocking": 9.0, "retreat": 9.0, "jump": 9.0, "land": 9.0,
    "sleep_curl": 2.5, "sleep": 2.5, "yawn": 5.0, "stretch": 5.5,
    "lick_groom": 6.0, "watch_focus": 5.0, "tail_wag": 9.0, "rolling": 10.0,
    "break_hint": 7.0,
}

# 与 cat_animation_component.gd ONESHOT_ACTIONS 一致
ONESHOT = {
    "eat", "pounce_attack", "pounce_ready", "pounce", "greet", "celebrate",
    "comfort", "dodge", "startled", "stretch", "yawn", "jump", "land",
    "retreat", "typing_attack", "blocking", "kneading", "head_pat_happy",
    "sneak_eat", "happy", "peek", "carry", "break_hint",
}
CURVE_FIRST_LAST = 1.6
CURVE_MIDDLE = 0.7

def tune_file(path):
    src = open(path, encoding="utf-8").read()
    # 动画块切分：从 "frames": [{ 到块尾 "speed": x.x }
    blocks = re.split(r'(?=\{\n"frames": \[)', src)
    out = []
    speed_changed = 0
    curve_applied = 0
    for block in blocks:
        m = re.search(r'"name": &"(\w+)",\n"speed": ([\d.]+)', block)
        if not m:
            out.append(block)
            continue
        name = m.group(1)
        new_block = block
        if name in SPEED_MAP:
            new_block = new_block[:m.start(2)] + str(SPEED_MAP[name]) + new_block[m.end(2):]
            speed_changed += 1
        if name in ONESHOT:
            # 帧序列内的 duration 逐个按曲线替换（帧序 = 块内出现顺序）
            idx = [0]
            def repl(mm):
                i = idx[0]; idx[0] += 1
                return '"duration": ' + ("1.6" if i == 0 else "0.7")
            # 先数帧数决定末帧：需要两遍——第一遍数，第二遍替换
            n_frames = len(re.findall(r'"duration": [\d.]+', new_block))
            idx = [0]
            def repl2(mm):
                i = idx[0]; idx[0] += 1
                d = CURVE_FIRST_LAST if (i == 0 or i == n_frames - 1) else CURVE_MIDDLE
                return '"duration": ' + str(d)
            new_block, nsub = re.subn(r'"duration": [\d.]+', repl2, new_block)
            if nsub > 0:
                curve_applied += 1
        out.append(new_block)
    open(path, "w", encoding="utf-8", newline="\n").write("".join(out))
    print(path, "speed_changed=", speed_changed, "curve_applied=", curve_applied)

for p in glob.glob("resources/animations/*.tres"):
    tune_file(p)
