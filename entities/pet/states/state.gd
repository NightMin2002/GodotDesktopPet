# state.gd — 宠物状态基类
# 所有具体状态 (Idle, Walk, Drag, Fall) 都继承自此类
class_name PetState
extends RefCounted

var pet: RigidBody2D  # 宠物本体引用

## 进入此状态时调用
func enter() -> void:
	pass

## 离开此状态时调用
func exit() -> void:
	pass

## 每帧逻辑 (对应 _process)
func process(_delta: float) -> void:
	pass

## 物理帧逻辑 (对应 _physics_process)
func physics_process(_delta: float) -> void:
	pass

## 输入事件处理
func input(_event: InputEvent) -> void:
	pass
