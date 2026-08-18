class_name AutoStartManager
extends RefCounted

## 开机自启管理(Windows 注册表 HKCU Run 键)
## 自启命令带 --minimized 参数:开机后台静默启动,托盘常驻

const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const APP_NAME := "DesktopPetCat"

static func is_enabled() -> bool:
	if OS.get_name() != "Windows":
		return false
	var output: Array = []
	var exit_code := OS.execute("reg", ["query", RUN_KEY, "/v", APP_NAME], output, true)
	return exit_code == 0 and not String(output[0] if output.size() > 0 else "").contains("系统找不到") and not String(output[0] if output.size() > 0 else "").contains("cannot find")

static func set_enabled(enabled: bool) -> bool:
	if OS.get_name() != "Windows":
		push_warning("开机自启仅支持 Windows")
		return false
	if enabled:
		var exe_path := OS.get_executable_path()
		if exe_path.is_empty() or not exe_path.get_file().begins_with("DesktopPetCat"):
			# 编辑器运行时无法注册真实自启(指向的是 Godot 编辑器)
			push_warning("请在导出的 exe 中设置开机自启")
			return false
		var cmd := "\"%s\" -- --minimized" % exe_path
		var output: Array = []
		var err := OS.execute("reg", ["add", RUN_KEY, "/v", APP_NAME, "/t", "REG_SZ", "/d", cmd, "/f"], output, true)
		return err == 0
	else:
		var output: Array = []
		OS.execute("reg", ["delete", RUN_KEY, "/v", APP_NAME, "/f"], output, true)
		# 不存在时删除返回非 0,视为已关闭成功
		return true

static func get_exe_path() -> String:
	return OS.get_executable_path()
