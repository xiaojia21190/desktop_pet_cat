extends PopupPanel

const SAVE_EXTENSION := ".catpet"

@onready var save_time_label: Label = $MarginContainer/VBoxContainer/SaveTimeLabel
@onready var cat_type_label: Label = $MarginContainer/VBoxContainer/CatTypeLabel
@onready var export_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ExportButton
@onready var import_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ImportButton
@onready var reset_button: Button = $MarginContainer/VBoxContainer/ResetButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
@onready var export_dialog: FileDialog = $ExportDialog
@onready var import_dialog: FileDialog = $ImportDialog
@onready var reset_confirm_dialog: ConfirmationDialog = $ResetConfirmDialog

func _ready() -> void:
	export_button.pressed.connect(_on_export_pressed)
	import_button.pressed.connect(_on_import_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(hide)

	export_dialog.file_selected.connect(_on_export_file_selected)
	import_dialog.file_selected.connect(_on_import_file_selected)
	reset_confirm_dialog.confirmed.connect(_on_reset_confirmed)

	_configure_dialogs()
	refresh_info()

func show_panel() -> void:
	refresh_info()
	popup_centered()

func refresh_info() -> void:
	var data = SaveManager.load_data()
	var meta = data.get("meta", {})
	var saved_at = int(meta.get("saved_at", 0))
	save_time_label.text = "存档时间: " + _format_time(saved_at)
	var cat_data = data.get("cat", {})
	var cat_type = str(cat_data.get("cat_type", ""))
	cat_type_label.text = "猫咪类型: " + _get_cat_type_name(cat_type)

func _configure_dialogs() -> void:
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.catpet ; Cat Pet Save"])
	export_dialog.use_native_dialog = true
	export_dialog.title = "导出存档"

	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = PackedStringArray(["*.catpet ; Cat Pet Save"])
	import_dialog.use_native_dialog = true
	import_dialog.title = "导入存档"

	reset_confirm_dialog.dialog_text = "确定要重置存档吗？这将清除所有数据并恢复默认。"

func _on_export_pressed() -> void:
	export_dialog.current_file = _build_default_filename()
	export_dialog.popup_centered()

func _on_import_pressed() -> void:
	import_dialog.popup_centered()

func _on_reset_pressed() -> void:
	reset_confirm_dialog.popup_centered()

func _on_export_file_selected(path: String) -> void:
	var final_path = _ensure_extension(path)
	if SaveManager.export_to_file(final_path):
		refresh_info()

func _on_import_file_selected(path: String) -> void:
	if SaveManager.import_from_file(path):
		refresh_info()

func _on_reset_confirmed() -> void:
	SaveManager.reset_data()
	refresh_info()

func _format_time(timestamp: int) -> String:
	if timestamp <= 0:
		return "未保存"
	var time_data = Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d" % [
		time_data["year"],
		time_data["month"],
		time_data["day"],
		time_data["hour"],
		time_data["minute"]
	]

func _get_cat_type_name(cat_type: String) -> String:
	if cat_type.is_empty():
		return "--"
	if AnimationConfig.CAT_TYPES.has(cat_type):
		var info = AnimationConfig.CAT_TYPES[cat_type]
		return str(info.get("name", cat_type))
	return cat_type

func _ensure_extension(path: String) -> String:
	if path.to_lower().ends_with(SAVE_EXTENSION):
		return path
	return path + SAVE_EXTENSION

func _build_default_filename() -> String:
	var time_data = Time.get_datetime_dict_from_system()
	return "catpet_%04d%02d%02d.catpet" % [
		time_data["year"],
		time_data["month"],
		time_data["day"]
	]
