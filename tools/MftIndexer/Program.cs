using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

/// <summary>
/// MFT 索引构建工具。
/// 以 SYSTEM 权限运行，遍历所有 NTFS 卷的 MFT，序列化索引到磁盘。
/// 由计划任务触发，跑完就退出。
/// </summary>
class Program
{
    // ══════════════════════════════════════
    //  索引文件路径
    // ══════════════════════════════════════

    static readonly string IndexDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "DesktopPet");

    static readonly string IndexPath = Path.Combine(IndexDir, "mft_index.dat");
    static readonly string TempPath = IndexPath + ".tmp";

    // 文件头魔数
    static readonly byte[] MAGIC = "MFTX"u8.ToArray();
    const int VERSION = 1;

    // ══════════════════════════════════════
    //  Win32 P/Invoke
    // ══════════════════════════════════════

    const uint GENERIC_READ = 0x80000000;
    const uint FILE_SHARE_READ = 0x01;
    const uint FILE_SHARE_WRITE = 0x02;
    const uint OPEN_EXISTING = 3;
    const uint FSCTL_ENUM_USN_DATA = 0x000900B3;

    [StructLayout(LayoutKind.Sequential)]
    struct MFT_ENUM_DATA_V0
    {
        public ulong StartFileReferenceNumber;
        public long LowUsn;
        public long HighUsn;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
        ref MFT_ENUM_DATA_V0 lpInBuffer, int nInBufferSize,
        IntPtr lpOutBuffer, int nOutBufferSize,
        out int lpBytesReturned, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    // ══════════════════════════════════════
    //  入口
    // ══════════════════════════════════════

    static int Main(string[] args)
    {
        try
        {
            Console.WriteLine("[MftIndexer] 开始构建索引...");
            var sw = System.Diagnostics.Stopwatch.StartNew();

            // 确保输出目录存在
            Directory.CreateDirectory(IndexDir);

            // 遍历所有 NTFS 卷
            var allEntries = new Dictionary<string, List<IndexEntry>>();
            int totalCount = 0;

            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady || drive.DriveType != DriveType.Fixed) continue;
                    if (!drive.DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase)) continue;

                    string vol = drive.Name.TrimEnd('\\');
                    Console.Write($"  [{vol}] 扫描中... ");

                    var entries = EnumerateVolume(vol);
                    if (entries.Count > 0)
                    {
                        allEntries[vol] = entries;
                        totalCount += entries.Count;
                        Console.WriteLine($"{entries.Count} 条记录");
                    }
                    else
                    {
                        Console.WriteLine("跳过 (无法访问)");
                    }
                }
                catch (Exception e)
                {
                    Console.WriteLine($"失败: {e.Message}");
                }
            }

            // 序列化到临时文件 (写完再 rename，防止读到半成品)
            SerializeIndex(TempPath, allEntries);

            // 原子替换
            if (File.Exists(IndexPath))
                File.Delete(IndexPath);
            File.Move(TempPath, IndexPath);

            sw.Stop();
            Console.WriteLine($"[MftIndexer] 完成! {totalCount} 条记录, 耗时 {sw.Elapsed.TotalSeconds:F1}s");
            Console.WriteLine($"[MftIndexer] 索引文件: {IndexPath}");
            return 0;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"[MftIndexer] 致命错误: {e.Message}");
            return 1;
        }
    }

    // ══════════════════════════════════════
    //  MFT 遍历
    // ══════════════════════════════════════

    struct IndexEntry
    {
        public ulong FileRef;
        public ulong ParentRef;
        public bool IsDirectory;
        public string Name;
    }

    static List<IndexEntry> EnumerateVolume(string volumePath)
    {
        var entries = new List<IndexEntry>();

        var handle = CreateFile(@"\\.\" + volumePath, GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);

        if (handle == INVALID_HANDLE_VALUE)
            return entries;

        try
        {
            var enumData = new MFT_ENUM_DATA_V0
            {
                StartFileReferenceNumber = 0,
                LowUsn = 0,
                HighUsn = long.MaxValue
            };

            int bufferSize = 1024 * 1024;
            IntPtr buffer = Marshal.AllocHGlobal(bufferSize);

            try
            {
                while (true)
                {
                    bool ok = DeviceIoControl(handle, FSCTL_ENUM_USN_DATA,
                        ref enumData, Marshal.SizeOf(enumData),
                        buffer, bufferSize, out int bytesReturned, IntPtr.Zero);

                    if (!ok || bytesReturned <= 8) break;

                    enumData.StartFileReferenceNumber = (ulong)Marshal.ReadInt64(buffer, 0);

                    int offset = 8;
                    while (offset + 64 <= bytesReturned)
                    {
                        int recordLen = Marshal.ReadInt32(buffer, offset);
                        if (recordLen < 64 || offset + recordLen > bytesReturned) break;

                        ulong fileRef = (ulong)Marshal.ReadInt64(buffer, offset + 8) & 0x0000FFFFFFFFFFFF;
                        ulong parentRef = (ulong)Marshal.ReadInt64(buffer, offset + 16) & 0x0000FFFFFFFFFFFF;
                        int fileAttributes = Marshal.ReadInt32(buffer, offset + 52);
                        short fileNameLength = Marshal.ReadInt16(buffer, offset + 56);
                        short fileNameOffset = Marshal.ReadInt16(buffer, offset + 58);

                        if (fileNameLength > 0 && fileNameOffset >= 60
                            && fileNameOffset + fileNameLength <= recordLen)
                        {
                            string name = Marshal.PtrToStringUni(
                                buffer + offset + fileNameOffset, fileNameLength / 2);

                            if (name != null && !name.StartsWith("$"))
                            {
                                entries.Add(new IndexEntry
                                {
                                    FileRef = fileRef,
                                    ParentRef = parentRef,
                                    IsDirectory = (fileAttributes & 0x10) != 0,
                                    Name = name
                                });
                            }
                        }
                        offset += recordLen;
                    }
                }
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        finally { CloseHandle(handle); }

        return entries;
    }

    // ══════════════════════════════════════
    //  索引序列化
    // ══════════════════════════════════════

    static void SerializeIndex(string path, Dictionary<string, List<IndexEntry>> allEntries)
    {
        using var fs = File.Create(path);
        using var bw = new BinaryWriter(fs, Encoding.UTF8);

        // Header
        bw.Write(MAGIC);                                   // 4 bytes
        bw.Write(VERSION);                                 // 4 bytes
        bw.Write(DateTimeOffset.UtcNow.ToUnixTimeSeconds()); // 8 bytes
        bw.Write(allEntries.Count);                        // 4 bytes

        // Per volume
        foreach (var kvp in allEntries)
        {
            bw.Write(kvp.Key);       // volume path (length-prefixed UTF8)
            bw.Write(kvp.Value.Count);

            foreach (var entry in kvp.Value)
            {
                bw.Write(entry.FileRef);
                bw.Write(entry.ParentRef);
                bw.Write(entry.IsDirectory);
                bw.Write(entry.Name);
            }
        }
    }
}
