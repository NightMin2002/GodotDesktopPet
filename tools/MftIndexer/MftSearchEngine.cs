using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Godot;

/// <summary>
/// MFT 文件搜索引擎 (宠物端)。
/// 从磁盘索引文件加载数据，不需要管理员权限。
/// 索引由独立工具 MftIndexer.exe 以 SYSTEM 权限构建。
/// </summary>
public class MftSearchEngine
{
    // ══════════════════════════════════════
    //  文件条目
    // ══════════════════════════════════════

    public struct FileEntry
    {
        public string Name;
        public ulong ParentRef;
        public bool IsDirectory;
    }

    // ══════════════════════════════════════
    //  索引状态
    // ══════════════════════════════════════

    private readonly Dictionary<string, Dictionary<ulong, FileEntry>> _volumeIndices = new();
    private volatile bool _indexReady = false;
    private volatile bool _loading = false;
    private volatile int _totalIndexed = 0;
    private volatile string _error = "";
    private long _indexTimestamp = 0; // Unix seconds

    public bool IsReady => _indexReady;
    public bool IsLoading => _loading;
    public int TotalIndexed => _totalIndexed;
    public string Error => _error;
    public long IndexTimestamp => _indexTimestamp;

    // ══════════════════════════════════════
    //  常量
    // ══════════════════════════════════════

    private static readonly byte[] MAGIC = { (byte)'M', (byte)'F', (byte)'T', (byte)'X' };
    private const int VERSION = 1;
    private const string TASK_NAME = "DesktopPetMFT";

    // 索引过期阈值 (秒)
    private const long STALE_THRESHOLD = 2 * 3600; // 2 小时

    public static readonly string IndexDir = Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.CommonApplicationData),
        "DesktopPet");

    public static readonly string IndexPath = Path.Combine(IndexDir, "mft_index.dat");

    // ══════════════════════════════════════
    //  索引加载
    // ══════════════════════════════════════

    /// <summary>
    /// 检查索引文件是否存在
    /// </summary>
    public static bool IndexExists()
    {
        return File.Exists(IndexPath);
    }

    /// <summary>
    /// 后台加载磁盘索引
    /// </summary>
    public void LoadIndexAsync()
    {
        if (_loading) return;

        _loading = true;
        _indexReady = false;
        _totalIndexed = 0;
        _error = "";

        Task.Run(() =>
        {
            try
            {
                LoadIndex();
                _indexReady = true;
                GD.Print($"[MFT] 索引加载完成: {_totalIndexed} 条记录");

                // 检查是否过期
                var age = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - _indexTimestamp;
                if (age > STALE_THRESHOLD)
                {
                    GD.Print($"[MFT] 索引已过期 ({age / 3600.0:F1}h), 触发后台刷新");
                    TriggerRefresh();
                }
            }
            catch (FileNotFoundException)
            {
                _error = "no_index";
                GD.Print("[MFT] 索引文件不存在，尝试触发首次构建");
                TriggerRefresh();
            }
            catch (Exception e)
            {
                _error = e.Message;
                GD.PrintErr($"[MFT] 索引加载失败: {e.Message}");
            }
            finally
            {
                _loading = false;
            }
        });
    }

    private void LoadIndex()
    {
        if (!File.Exists(IndexPath))
            throw new FileNotFoundException("索引文件不存在", IndexPath);

        using var fs = File.OpenRead(IndexPath);
        using var br = new BinaryReader(fs, Encoding.UTF8);

        // 验证 Header
        var magic = br.ReadBytes(4);
        if (magic.Length != 4 || magic[0] != MAGIC[0] || magic[1] != MAGIC[1]
            || magic[2] != MAGIC[2] || magic[3] != MAGIC[3])
            throw new InvalidDataException("索引文件格式错误");

        int version = br.ReadInt32();
        if (version != VERSION)
            throw new InvalidDataException($"索引版本不支持: {version}");

        _indexTimestamp = br.ReadInt64();
        int volumeCount = br.ReadInt32();

        var newIndices = new Dictionary<string, Dictionary<ulong, FileEntry>>();
        int total = 0;

        for (int v = 0; v < volumeCount; v++)
        {
            string volumePath = br.ReadString();
            int entryCount = br.ReadInt32();

            var index = new Dictionary<ulong, FileEntry>(entryCount);

            for (int i = 0; i < entryCount; i++)
            {
                ulong fileRef = br.ReadUInt64();
                ulong parentRef = br.ReadUInt64();
                bool isDir = br.ReadBoolean();
                string name = br.ReadString();

                index[fileRef] = new FileEntry
                {
                    Name = name,
                    ParentRef = parentRef,
                    IsDirectory = isDir
                };
                total++;
            }

            newIndices[volumePath] = index;
        }

        lock (_volumeIndices)
        {
            _volumeIndices.Clear();
            foreach (var kvp in newIndices)
                _volumeIndices[kvp.Key] = kvp.Value;
        }

        _totalIndexed = total;
    }

    // ══════════════════════════════════════
    //  触发索引刷新 (schtasks)
    // ══════════════════════════════════════

    /// <summary>
    /// 通过计划任务触发索引重建 (不需要管理员权限)
    /// </summary>
    public static void TriggerRefresh()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/run /tn \"{TASK_NAME}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var proc = Process.Start(psi);
            proc?.WaitForExit(5000);

            if (proc != null && proc.ExitCode == 0)
                GD.Print("[MFT] 索引刷新任务已触发");
            else
                GD.Print("[MFT] 索引刷新触发失败 (计划任务可能未注册)");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[MFT] 触发刷新失败: {e.Message}");
        }
    }

    /// <summary>
    /// 注册计划任务 (需要管理员权限，安装时调用)
    /// </summary>
    public static bool RegisterScheduledTask(string indexerExePath)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/create /tn \"{TASK_NAME}\" /tr \"\\\"{indexerExePath}\\\"\" " +
                           $"/sc ONLOGON /rl HIGHEST /ru SYSTEM /f",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var proc = Process.Start(psi);
            proc?.WaitForExit(10000);
            return proc?.ExitCode == 0;
        }
        catch { return false; }
    }

    /// <summary>
    /// 卸载计划任务
    /// </summary>
    public static bool UnregisterScheduledTask()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/delete /tn \"{TASK_NAME}\" /f",
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var proc = Process.Start(psi);
            proc?.WaitForExit(5000);
            return proc?.ExitCode == 0;
        }
        catch { return false; }
    }

    /// <summary>
    /// 重新加载索引 (索引刷新后调用)
    /// </summary>
    public void ReloadIndex()
    {
        _indexReady = false;
        LoadIndexAsync();
    }

    // ══════════════════════════════════════
    //  路径重建
    // ══════════════════════════════════════

    private readonly Dictionary<string, Dictionary<ulong, string>> _pathCache = new();

    private string BuildPath(string volumeRoot, Dictionary<ulong, FileEntry> index, ulong fileRef)
    {
        if (!_pathCache.ContainsKey(volumeRoot))
            _pathCache[volumeRoot] = new Dictionary<ulong, string>();
        var cache = _pathCache[volumeRoot];

        if (cache.TryGetValue(fileRef, out string cached))
            return cached;

        var parts = new List<string>();
        ulong current = fileRef;
        int depth = 0;

        while (index.ContainsKey(current) && depth < 64)
        {
            var entry = index[current];
            parts.Add(entry.Name);

            if (entry.ParentRef == current || entry.ParentRef == 5 || !index.ContainsKey(entry.ParentRef))
                break;

            current = entry.ParentRef;
            depth++;
        }

        parts.Reverse();
        string path = volumeRoot + "\\" + string.Join("\\", parts);

        cache[fileRef] = path;
        return path;
    }

    // ══════════════════════════════════════
    //  搜索
    // ══════════════════════════════════════

    public struct SearchResult
    {
        public string Name;
        public string FullPath;
        public string Directory;
        public bool IsDirectory;
    }

    public List<SearchResult> Search(string query, int maxResults, CancellationToken ct)
    {
        var results = new List<SearchResult>();
        if (!_indexReady || string.IsNullOrWhiteSpace(query))
            return results;

        string lowerQuery = query.ToLowerInvariant();

        Dictionary<string, Dictionary<ulong, FileEntry>> snapshot;
        lock (_volumeIndices)
        {
            snapshot = new Dictionary<string, Dictionary<ulong, FileEntry>>(_volumeIndices);
        }

        foreach (var kvp in snapshot)
        {
            if (ct.IsCancellationRequested) break;

            string volumeRoot = kvp.Key;
            var index = kvp.Value;

            foreach (var entry in index)
            {
                if (ct.IsCancellationRequested) break;
                if (results.Count >= maxResults) break;

                if (entry.Value.Name.ToLowerInvariant().Contains(lowerQuery))
                {
                    string fullPath = BuildPath(volumeRoot, index, entry.Key);
                    string dir = fullPath.Substring(0, fullPath.Length - entry.Value.Name.Length).TrimEnd('\\');

                    results.Add(new SearchResult
                    {
                        Name = entry.Value.Name,
                        FullPath = fullPath,
                        Directory = dir,
                        IsDirectory = entry.Value.IsDirectory
                    });
                }
            }

            if (results.Count >= maxResults) break;
        }

        return results;
    }

    public void ClearIndex()
    {
        lock (_volumeIndices)
        {
            _volumeIndices.Clear();
        }
        _pathCache.Clear();
        _indexReady = false;
        _totalIndexed = 0;
    }
}
