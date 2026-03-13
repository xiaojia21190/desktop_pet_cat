extends Node

const SpriteFramesGeneratorScript := preload("res://sprite_frames_generator.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var cat_types: Array = SpriteFramesGeneratorScript.get_available_cat_types()
	_assert_true(cat_types.size() >= 4, "cat_types_count")

	for raw_type in cat_types:
		var cat_type := String(raw_type)
		var sf := SpriteFramesGeneratorScript.generate(cat_type)
		_assert_true(sf != null, "sprite_frames_generated_" + cat_type)
		if sf == null:
			continue
		_assert_true(sf.has_animation("idle_stand"), "has_idle_stand_" + cat_type)
		_assert_true(sf.has_animation("greet"), "has_greet_" + cat_type)

	SpriteFramesGeneratorScript.clear_cache()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		return
	_failed += 1
	_failures.append(test_name)

func _print_summary() -> void:
	print("")
	print("========== sprite manifest loader tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		print("failure list:")
		for name in _failures:
			print(" - ", name)
