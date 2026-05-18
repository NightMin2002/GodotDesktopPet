using Godot;
using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>
/// 文件操作桥接层 — 为 GDScript 提供文件属性查询、删除、定位等系统级操作。
/// 由 GDScript 通过 Node.Call() 调用。
/// </summary>
public partial class FileOperations : Node
{
    /// <summary>
    /// 获取文件/目录的详细属性信息。
    /// 返回 Godot Dictionary, GDScript 可直接当 Dictionary 用。
    /// </summary>
    public Godot.Collections.Dictionary GetFileInfo(string path)
    {
        var result = new Godot.Collections.Dictionary();

        try
        {
            if (Directory.Exists(path))
            {
                var dir = new DirectoryInfo(path);
                result["exists"] = true;
                result["is_dir"] = true;
                result["name"] = dir.Name;
                result["full_path"] = dir.FullName;
                result["size"] = GetDirectorySize(dir);
                result["created"] = dir.CreationTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["modified"] = dir.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["extension"] = "";
                result["item_count"] = dir.GetFileSystemInfos().Length;
            }
            else if (File.Exists(path))
            {
                var file = new FileInfo(path);
                result["exists"] = true;
                result["is_dir"] = false;
                result["name"] = file.Name;
                result["full_path"] = file.FullName;
                result["size"] = file.Length;
                result["created"] = file.CreationTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["modified"] = file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["extension"] = file.Extension.ToLower();
                result["item_count"] = 0;
            }
            else
            {
                result["exists"] = false;
                result["error"] = "路径不存在";
            }
        }
        catch (Exception e)
        {
            result["exists"] = false;
            result["error"] = e.Message;
        }

        return result;
    }

    /// <summary>
    /// 彻底删除文件或目录 (不走回收站, 不可恢复)。
    /// 返回 Dictionary: { success: bool, error: string }
    /// </summary>
    public Godot.Collections.Dictionary DeleteFilePermanently(string path)
    {
        var result = new Godot.Collections.Dictionary();

        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true); // recursive
                result["success"] = true;
            }
            else if (File.Exists(path))
            {
                // 先尝试去除只读属性
                var attrs = File.GetAttributes(path);
                if ((attrs & FileAttributes.ReadOnly) == FileAttributes.ReadOnly)
                {
                    File.SetAttributes(path, attrs & ~FileAttributes.ReadOnly);
                }
                File.Delete(path);
                result["success"] = true;
            }
            else
            {
                result["success"] = false;
                result["error"] = "目标不存在";
            }
        }
        catch (Exception e)
        {
            result["success"] = false;
            result["error"] = e.Message;
        }

        return result;
    }

    /// <summary>
    /// 在 Windows 资源管理器中定位并选中文件/目录。
    /// </summary>
    public void OpenInExplorer(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                // /select 参数: 打开父文件夹并选中目标文件
                Process.Start("explorer.exe", $"/select,\"{path}\"");
            }
            else if (Directory.Exists(path))
            {
                Process.Start("explorer.exe", $"\"{path}\"");
            }
        }
        catch (Exception e)
        {
            GD.PrintErr($"[FileOperations] OpenInExplorer failed: {e.Message}");
        }
    }

    /// <summary>
    /// 将文件或目录移入回收站 (可恢复)。
    /// 使用 Win32 SHFileOperation + FOF_ALLOWUNDO。
    /// 返回 Dictionary: { success: bool, error: string }
    /// </summary>
    public Godot.Collections.Dictionary RecycleFile(string path)
    {
        var result = new Godot.Collections.Dictionary();

        try
        {
            if (!File.Exists(path) && !Directory.Exists(path))
            {
                result["success"] = false;
                result["error"] = "目标不存在";
                return result;
            }

            var fileOp = new SHFILEOPSTRUCT
            {
                wFunc = FO_DELETE,
                pFrom = path + '\0' + '\0',  // 双 null 结尾
                fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT,
            };

            int ret = SHFileOperation(ref fileOp);
            if (ret == 0 && !fileOp.fAnyOperationsAborted)
            {
                result["success"] = true;
            }
            else
            {
                result["success"] = false;
                result["error"] = fileOp.fAnyOperationsAborted ? "操作被取消" : $"SHFileOperation 返回 {ret}";
            }
        }
        catch (Exception e)
        {
            result["success"] = false;
            result["error"] = e.Message;
        }

        return result;
    }

    // ── SHFileOperation P/Invoke ──

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT fileOp);

    private const int FO_DELETE = 0x0003;
    private const int FOF_ALLOWUNDO = 0x0040;       // 回收站
    private const int FOF_NOCONFIRMATION = 0x0010;   // 不弹确认框
    private const int FOF_NOERRORUI = 0x0400;        // 不弹错误框
    private const int FOF_SILENT = 0x0004;           // 不显示进度条

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public int wFunc;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string pFrom;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string pTo;
        public short fFlags;
        [MarshalAs(UnmanagedType.Bool)]
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string lpszProgressTitle;
    }

    /// <summary>
    /// 递归计算目录总大小 (字节)。
    /// 大目录可能耗时, 上限 1000 个文件后停止计数返回估算值。
    /// </summary>
    private long GetDirectorySize(DirectoryInfo dir)
    {
        long size = 0;
        int count = 0;
        const int maxFiles = 1000;

        try
        {
            foreach (var file in dir.EnumerateFiles("*", SearchOption.AllDirectories))
            {
                size += file.Length;
                count++;
                if (count >= maxFiles) break; // 防止巨型目录卡死
            }
        }
        catch { /* 权限不足等, 忽略 */ }

        return size;
    }
}
