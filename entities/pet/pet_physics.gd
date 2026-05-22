# pet_physics.gd — 物理参数集中管理器
# 将散落在 8+ 个文件的物理参数赋值统一收口到配置表
# 每个状态/子阶段定义一个命名 profile，调用 apply("xxx") 即可
class_name PetPhysics
extends RefCounted

var pet: RigidBody2D

# ── 配置表 ──
# key = profile 名称
# value = 要设置的属性字典 (缺省的属性不动)
#   linear_damp, angular_damp, lock_rotation, gravity_scale
#
# 命名规范: {状态}_{子阶段}  例: walk_hop, roam_jump, hibernate

const PROFILES := {
	# ── 状态机 (states/) ──
	"idle":              { "linear_damp": 0.8,  "angular_damp": 1.0  },
	"idle_quiet":        { "linear_damp": 5.0,  "angular_damp": 8.0  },
	"idle_exit":         { "linear_damp": 0.5 },
	"walk_hop":          { "linear_damp": 0.3,  "angular_damp": 0.5  },
	"walk_roll":         { "linear_damp": 2.0,  "angular_damp": 0.8  },
	"walk_cruise":       { "linear_damp": 1.5,  "angular_damp": 0.5  },
	"jump":              { "linear_damp": 0.2,  "angular_damp": 0.8  },
	"fall":              { "linear_damp": 0.5 },
	"drag":              { "linear_damp": 0.5 },
	"retreat":           { "linear_damp": 1.5,  "angular_damp": 0.2,  "lock_rotation": false },
	"retreat_arrive":    { "linear_damp": 5.0,  "angular_damp": 5.0  },
	"retreat_night_exit":{ "linear_damp": 3.0,  "angular_damp": 5.0  },

	# ── 微行为 (idle_behaviors.gd) ──
	"hibernate":         { "linear_damp": 3.0,  "angular_damp": 5.0,  "lock_rotation": true  },
	"hibernate_wake":    { "linear_damp": 0.8,  "angular_damp": 1.0,  "lock_rotation": false },

	# ── 踏板锁定 (pet_platform.gd) ──
	"platform_lock":     { "linear_damp": 20.0 },

	# ── 空间跳跃 (free_roam.gd) ──
	"roam_jump":         { "linear_damp": 0.2,  "angular_damp": 0.6  },
	"roam_land":         { "linear_damp": 0.8,  "angular_damp": 1.5  },
	"roam_walk":         { "linear_damp": 0.1,  "angular_damp": 0.3  },
	"roam_jump_down":    { "linear_damp": 0.2,  "angular_damp": 0.4  },
	"roam_elevator_end": { "linear_damp": 0.5,  "angular_damp": 0.8  },
	"roam_full_stop":    { "linear_damp": 5.0,  "angular_damp": 8.0  },
}

## 应用指定物理配置
func apply(profile_name: String) -> void:
	var p = PROFILES.get(profile_name)
	if p == null:
		push_warning("[PetPhysics] 未知 profile: " + profile_name)
		return
	if p.has("linear_damp"):   pet.linear_damp = p["linear_damp"]
	if p.has("angular_damp"):  pet.angular_damp = p["angular_damp"]
	if p.has("lock_rotation"): pet.lock_rotation = p["lock_rotation"]
	if p.has("gravity_scale"): pet.gravity_scale = p["gravity_scale"]
