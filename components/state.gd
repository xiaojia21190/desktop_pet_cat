class_name State
extends Node

## 状态基类
## 所有具体状态继承此类

var state_machine: Node  # 使用 Node 避免循环依赖

## 进入状态时调用
func enter(_msg: Dictionary = {}) -> void:
	pass

## 退出状态时调用
func exit() -> void:
	pass

## 每帧更新（_process）
func update(_delta: float) -> void:
	pass

## 物理更新（_physics_process）
func physics_update(_delta: float) -> void:
	pass

## 处理输入
func handle_input(_event: InputEvent) -> void:
	pass
