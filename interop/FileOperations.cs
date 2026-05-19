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
                result["accessed"] = dir.LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["extension"] = "";
                // 子项详细统计
                try
                {
                    var entries = dir.GetFileSystemInfos();
                    result["item_count"] = entries.Length;
                    int fileCount = 0, dirCount = 0;
                    foreach (var e in entries)
                    {
                        if (e is DirectoryInfo) dirCount++;
                        else fileCount++;
                    }
                    result["file_count"] = fileCount;
                    result["dir_count"] = dirCount;
                }
                catch { result["item_count"] = 0; result["file_count"] = 0; result["dir_count"] = 0; }
                // 属性标志
                result["is_readonly"] = dir.Attributes.HasFlag(FileAttributes.ReadOnly);
                result["is_hidden"] = dir.Attributes.HasFlag(FileAttributes.Hidden);
                result["is_system"] = dir.Attributes.HasFlag(FileAttributes.System);
                result["attributes_raw"] = dir.Attributes.ToString();
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
                result["accessed"] = file.LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss");
                result["extension"] = file.Extension.ToLower();
                result["item_count"] = 0;
                // 属性标志
                result["is_readonly"] = file.IsReadOnly;
                result["is_hidden"] = file.Attributes.HasFlag(FileAttributes.Hidden);
                result["is_system"] = file.Attributes.HasFlag(FileAttributes.System);
                result["is_archive"] = file.Attributes.HasFlag(FileAttributes.Archive);
                result["attributes_raw"] = file.Attributes.ToString();
                // 文件版本信息 (exe/dll/msi 等)
                try
                {
                    var vi = FileVersionInfo.GetVersionInfo(path);
                    if (!string.IsNullOrEmpty(vi.FileVersion) || !string.IsNullOrEmpty(vi.ProductName))
                    {
                        result["product_name"] = vi.ProductName ?? "";
                        result["file_version"] = vi.FileVersion ?? "";
                        result["product_version"] = vi.ProductVersion ?? "";
                        result["company"] = vi.CompanyName ?? "";
                        result["description"] = vi.FileDescription ?? "";
                        result["original_filename"] = vi.OriginalFilename ?? "";
                    }
                }
                catch { /* 非 PE 文件, 忽略 */ }
                // MD5 哈希 (小于 500MB 才计算, 防卡死)
                if (file.Length < 500L * 1024 * 1024)
                {
                    try
                    {
                        using var md5 = System.Security.Cryptography.MD5.Create();
                        using var stream = file.OpenRead();
                        var hash = md5.ComputeHash(stream);
                        result["md5"] = BitConverter.ToString(hash).Replace("-", "").ToLower();
                    }
                    catch { /* 文件被占用等, 跳过 */ }
                }
                // 快捷方式目标解析 (.lnk)
                if (file.Extension.ToLower() == ".lnk")
                {
                    try
                    {
                        var target = ResolveLnkTarget(path);
                        if (!string.IsNullOrEmpty(target))
                            result["lnk_target"] = target;
                    }
                    catch { }
                }
                // 图片尺寸检测 (PNG/JPEG/GIF/BMP/WebP)
                var imgExts = new[] { ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp" };
                if (Array.Exists(imgExts, e => e == file.Extension.ToLower()))
                {
                    try
                    {
                        var dims = GetImageDimensions(path);
                        if (dims != null)
                        {
                            result["img_width"] = dims[0];
                            result["img_height"] = dims[1];
                        }
                    }
                    catch { }
                }
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
    /// 解析 .lnk 快捷方式的目标路径 (通过 COM Shell32)。
    /// </summary>
    private static string ResolveLnkTarget(string lnkPath)
    {
        // 使用简单的二进制解析, 避免 COM 依赖
        try
        {
            var bytes = File.ReadAllBytes(lnkPath);
            if (bytes.Length < 76) return null;
            // Shell Link Header: 前 4 字节 = HeaderSize (0x4C)
            if (BitConverter.ToInt32(bytes, 0) != 0x4C) return null;
            var flags = BitConverter.ToInt32(bytes, 20);
            int offset = 76; // 跳过 header
            // HasLinkTargetIDList (bit 0)
            if ((flags & 1) != 0)
            {
                if (offset + 2 > bytes.Length) return null;
                int idListSize = BitConverter.ToUInt16(bytes, offset);
                offset += 2 + idListSize;
            }
            // HasLinkInfo (bit 1)
            if ((flags & 2) != 0 && offset + 4 <= bytes.Length)
            {
                int linkInfoSize = BitConverter.ToInt32(bytes, offset);
                if (offset + 16 <= bytes.Length)
                {
                    int localBasePathOffset = BitConverter.ToInt32(bytes, offset + 16);
                    if (localBasePathOffset > 0 && offset + localBasePathOffset < bytes.Length)
                    {
                        int pathStart = offset + localBasePathOffset;
                        int pathEnd = pathStart;
                        while (pathEnd < bytes.Length && bytes[pathEnd] != 0) pathEnd++;
                        return System.Text.Encoding.Default.GetString(bytes, pathStart, pathEnd - pathStart);
                    }
                }
            }
        }
        catch { }
        return null;
    }

    /// <summary>
    /// 从文件头二进制数据解析图片宽高, 支持 PNG/JPEG/GIF/BMP/WebP。
    /// 返回 [width, height], 失败返回 null。
    /// </summary>
    private static int[] GetImageDimensions(string path)
    {
        using var fs = File.OpenRead(path);
        var header = new byte[30];
        if (fs.Read(header, 0, header.Length) < 24) return null;

        // PNG: 89 50 4E 47, IHDR at offset 16 (4B width + 4B height, big-endian)
        if (header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47)
        {
            int w = (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19];
            int h = (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];
            return new[] { w, h };
        }

        // GIF: "GIF8", width at 6 (2B LE), height at 8 (2B LE)
        if (header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46)
        {
            int w = header[6] | (header[7] << 8);
            int h = header[8] | (header[9] << 8);
            return new[] { w, h };
        }

        // BMP: "BM", width at 18 (4B LE), height at 22 (4B LE)
        if (header[0] == 0x42 && header[1] == 0x4D)
        {
            int w = BitConverter.ToInt32(header, 18);
            int h = Math.Abs(BitConverter.ToInt32(header, 22)); // height 可能为负 (top-down)
            return new[] { w, h };
        }

        // WebP: "RIFF" + "WEBP"
        if (header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
            && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50)
        {
            // VP8 lossy: offset 26-27 width, 28-29 height (LE)
            if (header[12] == 0x56 && header[13] == 0x50 && header[14] == 0x38 && header[15] == 0x20)
            {
                // 需要读到 offset 29
                var vp8 = new byte[30];
                fs.Seek(0, SeekOrigin.Begin);
                if (fs.Read(vp8, 0, 30) >= 30)
                {
                    int w = (vp8[26] | (vp8[27] << 8)) & 0x3FFF;
                    int h = (vp8[28] | (vp8[29] << 8)) & 0x3FFF;
                    return new[] { w, h };
                }
            }
            // VP8L lossless: offset 21-24 contains packed width/height
            if (header[12] == 0x56 && header[13] == 0x50 && header[14] == 0x38 && header[15] == 0x4C)
            {
                var vp8l = new byte[25];
                fs.Seek(0, SeekOrigin.Begin);
                if (fs.Read(vp8l, 0, 25) >= 25)
                {
                    uint bits = (uint)(vp8l[21] | (vp8l[22] << 8) | (vp8l[23] << 16) | (vp8l[24] << 24));
                    int w = (int)(bits & 0x3FFF) + 1;
                    int h = (int)((bits >> 14) & 0x3FFF) + 1;
                    return new[] { w, h };
                }
            }
        }

        // JPEG: FF D8, 扫描 SOF 标记 (FFC0-FFCF, 排除 FFC4/FFC8/FFCC)
        if (header[0] == 0xFF && header[1] == 0xD8)
        {
            fs.Seek(2, SeekOrigin.Begin);
            var buf = new byte[8];
            while (fs.Position < fs.Length - 8)
            {
                // 找 FF 标记
                int b = fs.ReadByte();
                if (b != 0xFF) continue;
                int marker = fs.ReadByte();
                if (marker == -1) break;
                // SOF 标记: C0-CF (排除 C4 DHT, C8 JPG, CC DAC)
                if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC)
                {
                    if (fs.Read(buf, 0, 5) >= 5)
                    {
                        int h = (buf[1] << 8) | buf[2];
                        int w = (buf[3] << 8) | buf[4];
                        return new[] { w, h };
                    }
                    break;
                }
                // 跳过当前段
                if (fs.Read(buf, 0, 2) < 2) break;
                int segLen = (buf[0] << 8) | buf[1];
                if (segLen < 2) break;
                fs.Seek(segLen - 2, SeekOrigin.Current);
            }
        }

        return null;
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
