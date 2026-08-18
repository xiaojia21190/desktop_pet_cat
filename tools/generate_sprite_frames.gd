@tool
extends EditorScript

## 从 sprite_manifest.json 生成 SpriteFrames .tres 资源
## 切图逻辑统一复用 SpriteFramesGenerator（单一事实来源）
## 使用：Script > Run

const OUTPUT_DIR := "res://resources/animations/"

func _run() -> void:
	var cats := SpriteFramesGenerator.get_available_cat_types()
	var ok_count := 0
	for cat_type in cats:
		SpriteFramesGenerator.clear_cache()
		var sf := SpriteFramesGenerator.generate(String(cat_type))
		if sf == null:
			push_warning("猫咪 %s 没有可用动画" % cat_type)
			continue
		var path := OUTPUT_DIR + String(cat_type) + ".tres"
		var err := ResourceSaver.save(sf, path)
		if err == OK:
			ok_count += 1
			print("已生成: %s (%d 个动画)" % [path, sf.get_animation_names().size()])
		else:
			push_error("保存失败: %s (error=%d)" % [path, err])
	SpriteFramesGenerator.clear_cache()
	print("SpriteFrames 生成完成: %d/%d" % [ok_count, cats.size()])
