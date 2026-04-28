# pet_color_palette.gd — 单宠物调色板
# 每个宠物实例 (原体/克隆体) 持有一个独立调色板
# 存储 HSV 色调(H) + 饱和度缩放(S) + 明度缩放(V)
# 所有 _draw() 硬编码颜色通过 shift_color() 统一变换
class_name PetColorPalette
extends RefCounted

## 当前硬编码模板的基准 Hue (湛蓝色 ≈ 0.62)
const DEFAULT_HUE := 0.62

## ── 可调参数 ──
var hue: float = DEFAULT_HUE       # 绝对色调 (0.0~1.0)
var sat_scale: float = 1.0          # 饱和度缩放 (0.5~1.5, 默认1.0=不变)
var val_scale: float = 1.0          # 明度缩放 (0.5~1.5, 默认1.0=不变)

## ── 缓存 (避免每帧重算 delta) ──
var _hue_delta: float = 0.0
var _dirty: bool = true

## 设置色调 (0~360 度数映射到 0~1)
func set_hue_degrees(degrees: int) -> void:
	hue = clampf(float(degrees) / 360.0, 0.0, 1.0)
	_hue_delta = hue - DEFAULT_HUE
	_dirty = false

## 设置色调 (0~1 浮点)
func set_hue(h: float) -> void:
	hue = clampf(h, 0.0, 1.0)
	_hue_delta = hue - DEFAULT_HUE
	_dirty = false

## 设置饱和度缩放 (0~100 映射到 0.5~1.5)
func set_sat_percent(pct: int) -> void:
	sat_scale = clampf(float(pct) / 100.0 + 0.5, 0.5, 1.5)

## 设置明度缩放 (0~100 映射到 0.5~1.5)
func set_val_percent(pct: int) -> void:
	val_scale = clampf(float(pct) / 100.0 + 0.5, 0.5, 1.5)

## 获取色调 (0~360 整数)
func get_hue_degrees() -> int:
	return int(hue * 360.0)

## 获取饱和度百分比 (0~100)
func get_sat_percent() -> int:
	return int((sat_scale - 0.5) * 100.0)

## 获取明度百分比 (0~100)
func get_val_percent() -> int:
	return int((val_scale - 0.5) * 100.0)

## ── 核心颜色变换 ──
## 将模板 RGB 颜色按当前 palette 参数偏移
## 替代原来的 pet.gd._shift_color() + clone_hue_shift
func shift_color(c: Color) -> Color:
	if _dirty:
		_hue_delta = hue - DEFAULT_HUE
		_dirty = false
	# 快速路径：完全默认时直接返回
	if absf(_hue_delta) < 0.001 and absf(sat_scale - 1.0) < 0.001 and absf(val_scale - 1.0) < 0.001:
		return c
	var h = fmod(c.h + _hue_delta + 1.0, 1.0)
	var s = clampf(c.s * sat_scale, 0.0, 1.0)
	var v = clampf(c.v * val_scale, 0.0, 1.0)
	return Color.from_hsv(h, s, v, c.a)

## 获取有效 hue (供特效系统使用)
func effective_hue() -> float:
	return hue

## 重置为默认值
func reset() -> void:
	hue = DEFAULT_HUE
	sat_scale = 1.0
	val_scale = 1.0
	_hue_delta = 0.0
	_dirty = false

## 判断是否为默认配置
func is_default() -> bool:
	return absf(hue - DEFAULT_HUE) < 0.001 and absf(sat_scale - 1.0) < 0.001 and absf(val_scale - 1.0) < 0.001
