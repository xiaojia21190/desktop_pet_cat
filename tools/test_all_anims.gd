extends SceneTree
## 全量验证:每个品种的每个动画都能加载且帧数据有效
func _init() -> void:
	var all_ok := true
	for cat_id in ["orange_tabby", "calico", "british_blue", "tuxedo", "dracula", "mochi"]:
		var path := "res://resources/animations/%s.tres" % cat_id
		if not ResourceLoader.exists(path):
			print("CATTEST[%s]: .tres 不存在!" % cat_id)
			all_ok = false
			continue
		var sf := load(path) as SpriteFrames
		if sf == null:
			print("CATTEST[%s]: 加载失败!" % cat_id)
			all_ok = false
			continue
		var anims := sf.get_animation_names()
		var bad_anims: Array[String] = []
		var total_frames := 0
		for anim in anims:
			var frames := sf.get_frame_count(anim)
			total_frames += frames
			if frames <= 0:
				bad_anims.append("%s(0帧)" % anim)
				continue
			# 检查每帧纹理有效
			for i in frames:
				var tex := sf.get_frame_texture(anim, i)
				if tex == null or tex.get_width() <= 0:
					bad_anims.append("%s(第%d帧无效)" % [anim, i])
					break
		# 检查关键状态动画是否齐备
		var required := ["idle_stand", "walk", "eat", "chasing", "sleep_curl", "carry", "greet", "watch_focus"]
		var missing: Array[String] = []
		for r in required:
			if not sf.has_animation(r):
				missing.append(r)
		var status := "OK" if bad_anims.is_empty() and missing.is_empty() else "FAIL"
		print("CATTEST[%s]: %s | %d 动画 %d 帧 | 坏动画:%s 缺关键:%s" % [
			cat_id, status, anims.size(), total_frames,
			",".join(bad_anims) if not bad_anims.is_empty() else "无",
			",".join(missing) if not missing.is_empty() else "无"])
		if not (bad_anims.is_empty() and missing.is_empty()):
			all_ok = false
	print("CATTEST: 总结 = ", "全部通过" if all_ok else "存在问题")
	quit(0 if all_ok else 1)
