# tools/ 目录说明

> 存放独立工具和技术储备代码，不参与 Godot 主项目编译。

---

## MftIndexer/

**状态**: 技术储备 (未启用)

**用途**: 独立 MFT 索引构建工具。通过 Win32 `FSCTL_ENUM_USN_DATA` 直读 NTFS MFT，遍历全盘文件并序列化索引到磁盘。

**背景**: 为了让宠物具备不依赖 Everything 的独立文件搜索能力而开发。经实测发现 .NET 的 string 对象开销导致内存占用过高 (~135MB / 百万文件)，短期内无法达到 Everything 的水平 (C 语言 + 连续内存池)，暂时搁置。

**文件说明**:

| 文件 | 说明 |
|------|------|
| `MftIndexer.csproj` | 独立 .NET 8 控制台项目 |
| `Program.cs` | MFT 遍历 + 二进制序列化，需 SYSTEM/管理员权限 |
| `MftSearchEngine.cs` | 宠物端索引加载 + 搜索 + schtasks 按需刷新 |

**设计方案**:

```
安装包 (管理员)
  └── schtasks /create 注册计划任务 (SYSTEM 权限, 开机运行)
  └── MftIndexer.exe 遍历 MFT → 序列化到 %PROGRAMDATA%\DesktopPet\mft_index.dat

宠物本体 (普通权限)
  └── 启动时加载 mft_index.dat → 内存搜索
  └── 5 秒轮询索引文件变化 → 自动热加载
  └── 索引过期 (>2h) → schtasks /run 触发刷新
```

**待解决问题** (如果未来重新启用):

1. 内存优化 — 需要用 `byte[]` 内存池替代独立 `string` 对象
2. 增量更新 — USN Journal 监控实时文件变化
3. 索引持久化优化 — Memory-mapped file 替代全量加载
4. 非 NTFS 文件系统兼容
