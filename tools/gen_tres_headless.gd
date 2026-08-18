extends SceneTree
## 命令行生成 SpriteFrames .tres：godot --headless --script tools/gen_tres_headless.gd
## 切图逻辑统一复用 SpriteFramesGenerator（单一事实来源）
func _init():
	var output_dir := "res://resources/animations/"
	var cats := SpriteFramesGenerator.get_available_cat_types()
	var ok_count := 0
	for cat_type in cats:
		SpriteFramesGenerator.clear_cache()
		var sf := SpriteFramesGenerator.generate(String(cat_type))
		if sf == null:
			push_warning("猫咪 %s 没有可用动画" % cat_type)
			continue
		var err := ResourceSaver.save(sf, output_dir + String(cat_type) + ".tres")
		if err == OK:
			ok_count += 1
			print("已生成: %s%s.tres (%d 个动画)" % [output_dir, cat_type, sf.get_animation_names().size()])
		else:
			push_error("保存失败: %s error=%d" % [cat_type, err])
	SpriteFramesGenerator.clear_cache()
	print("完成: %d/%d" % [ok_count, cats.size()])
	quit()
