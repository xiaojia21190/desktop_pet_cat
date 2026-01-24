class_name ItemTypes
extends RefCounted

## 道具类型枚举
## 替代字符串匹配，提供类型安全

enum Type {
	NONE,
	FOOD,
	WAND,
}

## 从字符串转换为枚举
static func from_string(type_str: String) -> Type:
	match type_str.to_lower():
		"food":
			return Type.FOOD
		"wand":
			return Type.WAND
		_:
			return Type.NONE

## 从枚举转换为字符串
static func to_string_name(type: Type) -> String:
	match type:
		Type.FOOD:
			return "food"
		Type.WAND:
			return "wand"
		_:
			return ""
