extends Node

## 全局事件总线
## 用于解耦组件间的通信

# 猫咪事件
signal cat_state_changed(from_state: StringName, to_state: StringName)
signal cat_emotion_changed(emotion_type: String, new_state: int)
signal cat_interacted(part: String)
signal cat_dragged(is_dragging: bool)

# 道具事件
signal item_spawned(item: Node2D, item_type: String)
signal item_collected(item: Node2D, item_type: String)
signal item_nearby(item: Node2D, distance: float)

# 输入事件
signal typing_detected(key_event: InputEvent)
signal mouse_clicked(position: Vector2, button: int)

# 系统事件
signal settings_changed(setting_name: String, value: Variant)
signal game_saved
signal game_loaded
