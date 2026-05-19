# action_scan.gd — [扫描] 属性检索操作
# 调用 C# GetFileInfo() 深度采集文件/目录属性
# 逐条气泡播报 + 全息屏 QUERY→DONE/ERROR 视觉反馈
# 扫描结果: 自动归档到数据日志 (sys:scan) + 复制到剪贴板

# ── 操作接口 ──

func get_action_id() -> String:
	return "scan"

func get_action_label() -> String:
	return "[扫描] 属性检索"

func execute(file_drop, paths: PackedStringArray) -> void:
	var pet = file_drop.pet
	if not pet or not is_instance_valid(pet):
		return
	
	var ops = file_drop.get_file_ops()
	if ops == null:
		pet.show_local_bubble(file_drop.LINES.no_bridge)
		return
	
	# 启动全息屏检索模式
	var hs = pet.holo_screen
	var side = hs.side if hs else 1.0
	if hs:
		hs.show_query(side, 0.0)  # duration=0 持续显示, 手动关闭
	
	# 起始话术
	if paths.size() == 1:
		pet.show_local_bubble("扫描启动。检索目标属性中...")
	else:
		pet.show_local_bubble("批量扫描启动。%d 项排队检索。" % paths.size())
	
	var tree = pet.get_tree()
	if not tree:
		return
	
	# 逐个文件扫描, 收集所有结果
	var success_count := 0
	var fail_count := 0
	var all_results: Array[Dictionary] = []  # 用于归档和剪贴板
	
	for i in paths.size():
		var path: String = paths[i]
		
		# 多文件时每项之间间隔
		if i > 0:
			await tree.create_timer(1.2).timeout
			if not is_instance_valid(pet):
				return
		
		var info: Dictionary = ops.call("GetFileInfo", path)
		
		if not info.get("exists", false):
			fail_count += 1
			pet.show_local_bubble("目标丢失。%s" % info.get("error", "路径无效。"))
			all_results.append({"path": path, "error": "目标不存在"})
			continue
		
		success_count += 1
		all_results.append(info)
		
		# ── 播报: 名称 + 类型 ──
		var type_tag: String
		if info.get("is_dir", false):
			var fc: int = info.get("file_count", 0)
			var dc: int = info.get("dir_count", 0)
			type_tag = "目录 / %d 文件, %d 子目录" % [fc, dc]
		else:
			var ext: String = info.get("extension", "")
			type_tag = _classify_extension(ext)
		
		pet.show_local_bubble("[%s] %s" % [type_tag, info.get("name", "?")])
		await tree.create_timer(1.5).timeout
		if not is_instance_valid(pet):
			return
		
		# ── 播报: 图片尺寸 ──
		var img_w: int = info.get("img_width", 0)
		var img_h: int = info.get("img_height", 0)
		if img_w > 0 and img_h > 0:
			pet.show_local_bubble("尺寸: %d x %d px" % [img_w, img_h])
			await tree.create_timer(0.8).timeout
			if not is_instance_valid(pet):
				return
		
		# ── 播报: 精确容量 ──
		var size_bytes: int = info.get("size", 0)
		pet.show_local_bubble("容量: %s (%s bytes)" % [file_drop.format_size(size_bytes), _format_int(size_bytes)])
		await tree.create_timer(1.2).timeout
		if not is_instance_valid(pet):
			return
		
		# ── 播报: 完整路径 ──
		pet.show_local_bubble("路径: %s" % info.get("full_path", path))
		await tree.create_timer(1.2).timeout
		if not is_instance_valid(pet):
			return
		
		# ── 播报: 时间戳 (三组) ──
		var modified: String = info.get("modified", "")
		var created: String = info.get("created", "")
		var accessed: String = info.get("accessed", "")
		if modified != "":
			pet.show_local_bubble("修改: %s" % modified)
			await tree.create_timer(0.8).timeout
			if not is_instance_valid(pet):
				return
		if created != "" and created != modified:
			pet.show_local_bubble("创建: %s" % created)
			await tree.create_timer(0.8).timeout
			if not is_instance_valid(pet):
				return
		if accessed != "" and accessed != modified and accessed != created:
			pet.show_local_bubble("访问: %s" % accessed)
			await tree.create_timer(0.8).timeout
			if not is_instance_valid(pet):
				return
		
		# ── 播报: 属性标志 ──
		var flags: PackedStringArray = []
		if info.get("is_readonly", false): flags.append("只读")
		if info.get("is_hidden", false): flags.append("隐藏")
		if info.get("is_system", false): flags.append("系统")
		if info.get("is_archive", false): flags.append("归档")
		if flags.size() > 0:
			pet.show_local_bubble("属性: %s" % ", ".join(flags))
			await tree.create_timer(0.8).timeout
			if not is_instance_valid(pet):
				return
		
		# ── 播报: MD5 哈希 ──
		var md5: String = info.get("md5", "")
		if md5 != "":
			pet.show_local_bubble("MD5: %s" % md5)
			await tree.create_timer(1.0).timeout
			if not is_instance_valid(pet):
				return
		
		# ── 播报: 版本信息 (exe/dll) ──
		var product: String = str(info.get("product_name", "")).strip_edges()
		var version: String = str(info.get("file_version", "")).strip_edges()
		var company: String = str(info.get("company", "")).strip_edges()
		if product != "" or version != "":
			var ver_text := ""
			if product != "": ver_text += product
			if version != "": ver_text += " v%s" % version
			if company != "": ver_text += " (%s)" % company
			pet.show_local_bubble("版本: %s" % ver_text.strip_edges())
			await tree.create_timer(1.0).timeout
			if not is_instance_valid(pet):
				return
		
		# ── 播报: 快捷方式目标 ──
		var lnk_target: String = info.get("lnk_target", "")
		if lnk_target != "":
			pet.show_local_bubble("目标: %s" % lnk_target)
			await tree.create_timer(1.0).timeout
			if not is_instance_valid(pet):
				return
	
	# ── 归档 + 剪贴板 ──
	await tree.create_timer(0.5).timeout
	if not is_instance_valid(pet):
		return
	
	var clipboard_text := _build_report_text(all_results, file_drop)
	DisplayServer.clipboard_set(clipboard_text)
	
	_save_to_datalog(all_results, file_drop)
	
	# ── 结算话术 ──
	if fail_count == 0:
		pet.show_local_bubble("属性检索完毕。已归档并写入剪贴板。")
		if hs:
			hs.show_done(side, 2.5)
	elif success_count > 0:
		pet.show_local_bubble("扫描完成。%d 项成功, %d 项丢失。已归档。" % [success_count, fail_count])
		if hs:
			hs.show_warning(side, 2.5)
	else:
		pet.show_local_bubble("全部目标丢失。扫描中止。")
		if hs:
			hs.show_error(side, 2.0)

# ══════════════════════════════════════
#  数据日志归档
# ══════════════════════════════════════

func _save_to_datalog(results: Array, file_drop) -> void:
	var now = Time.get_datetime_string_from_system(false, true)
	var td = Time.get_datetime_dict_from_system()
	var logs = SettingsManager.get_datalogs()
	
	# 标题: 单文件用文件名, 多文件用数量
	var title: String
	var valid_count := 0
	var first_name := ""
	for r in results:
		if r.get("exists", false) or r.get("name", "") != "":
			valid_count += 1
			if first_name == "":
				first_name = r.get("name", "?")
	
	if results.size() == 1:
		title = "扫描: %s" % first_name
	else:
		title = "扫描: %s 等 %d 项" % [first_name, results.size()]
	
	# 正文: 完整报告文本
	var content := _build_report_text(results, file_drop)
	
	var entry := {
		"id": "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		"title": title,
		"content": content,
		"scan_data": results.duplicate(true),
		"tags": ["sys:scan", "auto"],
		"source": "pet",
		"created": now,
		"updated": now,
	}
	logs.insert(0, entry)
	SettingsManager.save_datalogs(logs)

# ══════════════════════════════════════
#  报告文本生成 (剪贴板 + 日志正文共用)
# ══════════════════════════════════════

func _build_report_text(results: Array, file_drop) -> String:
	var lines: PackedStringArray = []
	var td = Time.get_datetime_dict_from_system()
	lines.append("=== 文件属性检索报告 ===")
	lines.append("扫描时间: %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("扫描项数: %d" % results.size())
	lines.append("")
	
	for i in results.size():
		var info: Dictionary = results[i]
		if info.has("error"):
			lines.append("[%d] 目标丢失: %s" % [i + 1, info.get("path", "?")])
			lines.append("    错误: %s" % info.get("error", ""))
			lines.append("")
			continue
		
		var is_dir: bool = info.get("is_dir", false)
		lines.append("[%d] %s" % [i + 1, info.get("name", "?")])
		lines.append("    类型: %s" % (_classify_extension(info.get("extension", "")) if not is_dir else "目录"))
		lines.append("    路径: %s" % info.get("full_path", ""))
		
		# 容量
		var size_bytes: int = info.get("size", 0)
		lines.append("    容量: %s (%s bytes)" % [file_drop.format_size(size_bytes), _format_int(size_bytes)])
		
		# 图片尺寸
		var img_w: int = info.get("img_width", 0)
		var img_h: int = info.get("img_height", 0)
		if img_w > 0 and img_h > 0:
			lines.append("    尺寸: %d x %d px" % [img_w, img_h])
		
		# 目录详情
		if is_dir:
			lines.append("    内容: %d 文件, %d 子目录" % [info.get("file_count", 0), info.get("dir_count", 0)])
		
		# 时间戳
		lines.append("    创建: %s" % info.get("created", ""))
		lines.append("    修改: %s" % info.get("modified", ""))
		var accessed: String = info.get("accessed", "")
		if accessed != "" and accessed != info.get("modified", ""):
			lines.append("    访问: %s" % accessed)
		
		# 属性标志
		var flags: PackedStringArray = []
		if info.get("is_readonly", false): flags.append("只读")
		if info.get("is_hidden", false): flags.append("隐藏")
		if info.get("is_system", false): flags.append("系统")
		if info.get("is_archive", false): flags.append("归档")
		if flags.size() > 0:
			lines.append("    属性: %s" % ", ".join(flags))
		
		# MD5
		var md5: String = info.get("md5", "")
		if md5 != "":
			lines.append("    MD5: %s" % md5)
		
		# 版本信息
		var product: String = str(info.get("product_name", "")).strip_edges()
		var version: String = str(info.get("file_version", "")).strip_edges()
		var company: String = str(info.get("company", "")).strip_edges()
		var desc: String = str(info.get("description", "")).strip_edges()
		if product != "" or version != "":
			if product != "":
				lines.append("    产品: %s" % product)
			if version != "":
				lines.append("    版本: %s" % version)
			if company != "":
				lines.append("    厂商: %s" % company)
			if desc != "":
				lines.append("    描述: %s" % desc)
		
		# 快捷方式
		var lnk_target: String = info.get("lnk_target", "")
		if lnk_target != "":
			lines.append("    指向: %s" % lnk_target)
		
		lines.append("")
	
	return "\n".join(lines)

# ══════════════════════════════════════
#  工具方法
# ══════════════════════════════════════

## 整数千分位格式化 (如 1234567 → "1,234,567")
func _format_int(n: int) -> String:
	var s := str(absi(n))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	if n < 0:
		result = "-" + result
	return result

## 根据扩展名分类文件类型
func _classify_extension(ext: String) -> String:
	if ext == "":
		return "未知"
	ext = ext.trim_prefix(".")
	match ext:
		"jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "ico", "tiff", "tif", "raw", "psd", "ai":
			return "图像"
		"mp4", "avi", "mkv", "mov", "wmv", "flv", "webm", "m4v", "ts":
			return "视频"
		"mp3", "wav", "flac", "aac", "ogg", "wma", "m4a", "opus":
			return "音频"
		"pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "rtf":
			return "文档"
		"txt", "md", "log", "csv", "json", "xml", "yaml", "yml", "ini", "cfg", "toml", "conf":
			return "文本"
		"gd", "cs", "py", "js", "ts", "java", "cpp", "c", "h", "hpp", "rs", "go", "lua", "rb", "php", "html", "css", "scss", "swift", "kt", "r", "sql", "sh", "bat", "ps1":
			return "代码"
		"zip", "rar", "7z", "tar", "gz", "bz2", "xz", "cab", "iso":
			return "压缩包"
		"exe", "msi", "dll", "sys", "drv":
			return "可执行"
		"lnk":
			return "快捷方式"
		"tscn", "tres", "godot", "import":
			return "Godot资源"
		"ttf", "otf", "woff", "woff2":
			return "字体"
		"db", "sqlite", "mdb":
			return "数据库"
		_:
			return ext.to_upper()
