# _action_template.gd — 操作模块模板 (新增功能时复制此文件)
# 
# 每个操作模块必须实现 3 个接口:
#   get_action_id()    → String   唯一标识 (如 "scan")
#   get_action_label() → String   菜单显示文本 (如 "[扫描] 属性检索")
#   execute(file_drop, paths)     执行操作
#
# file_drop 提供:
#   .pet              → 宠物节点 (show_local_bubble/holo_screen 等)
#   .get_file_ops()   → C# FileOperations 节点 (GetFileInfo/DeleteFilePermanently/OpenInExplorer)
#   .format_size(n)   → 格式化字节数为人类可读字符串
#   .LINES            → 共用话术字典
#
# 注册方式 (在 file_drop.gd 的 _register_builtin_actions 中):
#   _register_action_file("res://entities/pet/file_drop/action_xxx.gd")

func get_action_id() -> String:
	return "template"

func get_action_label() -> String:
	return "[模板] 占位操作"

func execute(file_drop, paths: PackedStringArray) -> void:
	file_drop.pet.show_local_bubble("模板操作已执行。")
