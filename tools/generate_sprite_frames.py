#!/usr/bin/env python3
"""从 sprite_manifest.json 生成 SpriteFrames .tres 资源文件"""
import json, os

MANIFEST = os.path.join(os.path.dirname(__file__), "..", "resources", "sprite_manifest.json")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "resources", "animations")

def main():
    with open(MANIFEST, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    global_actions = manifest.get("actions", {})
    defaults = manifest.get("defaults", {})
    cats = manifest.get("cats", {})

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for cat_type, cat_entry in cats.items():
        tres = build_tres(cat_type, cat_entry, global_actions, defaults)
        if tres is None:
            print(f"  跳过 {cat_type}: 无可用动画")
            continue
        out_path = os.path.join(OUTPUT_DIR, f"{cat_type}.tres")
        with open(out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(tres)
        print(f"  已生成: {out_path}")

    print("完成")

def build_tres(cat_type, cat_entry, global_actions, defaults):
    cat_defaults = cat_entry.get("defaults", {})
    sheet_path = cat_entry.get("sheet_path", "")
    action_path_template = cat_entry.get("action_path_template", "")
    require_action_files = cat_entry.get("require_action_files", False)
    action_overrides = cat_entry.get("actions", {})

    fw = cat_defaults.get("frame_width", defaults.get("frame_width", 170))
    fh = cat_defaults.get("frame_height", defaults.get("frame_height", 139))
    cols = cat_defaults.get("columns", defaults.get("columns", 8))

    # 收集所有动画及其帧
    anims = []  # [(name, speed, loop, [(tex_path, region)])]
    tex_paths_set = set()

    for action_key, action_spec in global_actions.items():
        spec = dict(action_spec)
        if action_key in action_overrides:
            spec.update(action_overrides[action_key])

        tex_path = spec.get("path", "")
        if not tex_path:
            tmpl = action_path_template.replace("{cat_id}", cat_type).replace("{action_key}", action_key)
            if tmpl and os.path.exists(to_abs(tmpl)):
                tex_path = tmpl
            elif sheet_path:
                tex_path = sheet_path

        if not tex_path or not os.path.exists(to_abs(tex_path)):
            if require_action_files:
                print(f"  警告: {cat_type}/{action_key} 纹理不存在: {tex_path}")
            continue

        row = spec.get("row", 0)
        col_start = spec.get("col_start", 0)
        frames_count = spec.get("frames", 1)
        speed = spec.get("speed", 5.0)
        loop = spec.get("loop", True)
        action_fw = spec.get("frame_width", fw)
        action_fh = spec.get("frame_height", fh)
        action_cols = spec.get("columns", cols)

        frame_regions = []
        for i in range(frames_count):
            c = col_start + i
            ar = row + c // action_cols
            ac = c % action_cols
            region = (ac * action_fw, ar * action_fh, action_fw, action_fh)
            frame_regions.append((tex_path, region))
            tex_paths_set.add(tex_path)

        anims.append((action_key, speed, loop, frame_regions))

    if not anims:
        return None

    # 分配 ext_resource id
    tex_list = sorted(tex_paths_set)
    tex_id_map = {}
    for idx, tp in enumerate(tex_list, 1):
        tex_id_map[tp] = str(idx)

    # 为每个帧创建 AtlasTexture sub_resource
    atlas_id_counter = 0
    atlas_entries = []  # [(id_str, ext_res_id, region)]
    # 帧引用：anim -> [atlas_id_str, ...]
    anim_atlas_ids = []

    for anim_name, speed, loop, frame_regions in anims:
        ids = []
        for tex_path, region in frame_regions:
            atlas_id_counter += 1
            aid = f"atlas_{atlas_id_counter}"
            atlas_entries.append((aid, tex_id_map[tex_path], region))
            ids.append(aid)
        anim_atlas_ids.append(ids)

    # 计算 load_steps
    load_steps = len(tex_list) + len(atlas_entries) + 1

    # 构建 .tres
    lines = []
    lines.append(f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3]\n')

    # ext_resources
    for tp in tex_list:
        eid = tex_id_map[tp]
        lines.append(f'[ext_resource type="Texture2D" path="{tp}" id="{eid}"]')
    lines.append("")

    # sub_resources (AtlasTexture)
    for aid, eid, (rx, ry, rw, rh) in atlas_entries:
        lines.append(f'[sub_resource type="AtlasTexture" id="{aid}"]')
        lines.append(f'atlas = ExtResource("{eid}")')
        lines.append(f'region = Rect2({rx}, {ry}, {rw}, {rh})')
        lines.append("")

    # resource
    lines.append("[resource]")
    # 构建 animations 数组
    anim_strs = []
    for i, (anim_name, speed, loop, _) in enumerate(anims):
        frame_strs = []
        for aid in anim_atlas_ids[i]:
            frame_strs.append('{\n"duration": 1.0,\n"texture": SubResource("' + aid + '")\n}')
        frames_joined = ", ".join(frame_strs)
        loop_str = "true" if loop else "false"
        anim_strs.append(
            '{\n"frames": [' + frames_joined + '],\n'
            '"loop": ' + loop_str + ',\n'
            '"name": &"' + anim_name + '",\n'
            '"speed": ' + str(float(speed)) + '\n}'
        )

    lines.append("animations = [" + ", ".join(anim_strs) + "]")
    lines.append("")

    return "\n".join(lines)

PROJECT_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

def to_abs(res_path):
    """将 res:// 路径转为绝对路径"""
    if res_path.startswith("res://"):
        return os.path.join(PROJECT_ROOT, res_path[6:])
    return res_path

if __name__ == "__main__":
    main()
