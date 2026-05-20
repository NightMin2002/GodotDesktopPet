using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// 文件搜索引擎 — 自动检测 / 自动下载 Everything SDK。
/// 
/// 查找优先级:
///   1. 可执行文件目录 (之前下载的或手动放的)
///   2. Everything 进程路径
///   3. 注册表
///   4. 常见安装目录
///   5. 全部失败 → 自动从 voidtools.com 下载 SDK zip 并解压
///
/// API: StartSearch → PollResults (每帧) → IsSearchDone
/// </summary>
public partial class FileSearchEngine : Node
{
    // ── 搜索状态 ──
    private CancellationTokenSource _cts;
    private readonly List<Godot.Collections.Dictionary> _resultBuffer = new();
    private int _deliveredCount = 0;
    private int _totalFound = 0;
    private int _totalMatched = 0;
    private volatile bool _isSearching = false;
    private volatile bool _searchDone = false;
    private readonly object _lock = new();

    // ── SDK 状态 ──
    private bool _sdkChecked = false;
    private bool _sdkAvailable = false;
    private string _sdkVersion = "";
    private string _sdkError = "";     // "not_found", "not_running", "downloading", 等
    private string _dllPath = "";
    private volatile bool _isDownloading = false;

    // ── 常量 ──
    private const string SDK_URL = "https://www.voidtools.com/Everything-SDK.zip";
    private const string DLL_NAME = "Everything64.dll";

    private const int EVERYTHING_OK = 0;
    private const int EVERYTHING_ERROR_IPC = 2;
    private const int EVERYTHING_REQUEST_FILE_NAME = 0x00000001;
    private const int EVERYTHING_REQUEST_PATH = 0x00000002;
    private const int EVERYTHING_REQUEST_SIZE = 0x00000010;
    private const int EVERYTHING_REQUEST_DATE_MODIFIED = 0x00000040;
    private const int EVERYTHING_REQUEST_EXTENSION = 0x00000008;
    private const int EVERYTHING_SORT_DATE_MODIFIED_DESCENDING = 14;

    // ══════════════════════════════════════
    //  DllImport: Everything SDK
    // ══════════════════════════════════════

    [DllImport(DLL_NAME, CharSet = CharSet.Unicode)]
    private static extern uint Everything_SetSearchW(string lpSearchString);

    [DllImport(DLL_NAME)]
    private static extern void Everything_SetMax(uint dwMax);

    [DllImport(DLL_NAME)]
    private static extern void Everything_SetOffset(uint dwOffset);

    [DllImport(DLL_NAME)]
    private static extern void Everything_SetRequestFlags(uint dwRequestFlags);

    [DllImport(DLL_NAME)]
    private static extern void Everything_SetSort(uint dwSortType);

    [DllImport(DLL_NAME)]
    private static extern bool Everything_QueryW(bool bWait);

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetNumResults();

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetTotResults();

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetLastError();

    [DllImport(DLL_NAME, CharSet = CharSet.Unicode)]
    private static extern IntPtr Everything_GetResultFileName(uint nIndex);

    [DllImport(DLL_NAME, CharSet = CharSet.Unicode)]
    private static extern void Everything_GetResultFullPathName(uint nIndex, System.Text.StringBuilder lpString, uint nMaxCount);

    [DllImport(DLL_NAME)]
    private static extern bool Everything_IsFolderResult(uint nIndex);

    [DllImport(DLL_NAME)]
    private static extern bool Everything_GetResultSize(uint nIndex, out long lpFileSize);

    [DllImport(DLL_NAME)]
    private static extern bool Everything_GetResultDateModified(uint nIndex, out long lpFileTime);

    [DllImport(DLL_NAME, CharSet = CharSet.Unicode)]
    private static extern IntPtr Everything_GetResultExtension(uint nIndex);

    [DllImport(DLL_NAME, CharSet = CharSet.Unicode)]
    private static extern IntPtr Everything_GetResultPath(uint nIndex);

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetMajorVersion();

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetMinorVersion();

    [DllImport(DLL_NAME)]
    private static extern uint Everything_GetRevision();

    [DllImport(DLL_NAME)]
    private static extern void Everything_Reset();

    // ══════════════════════════════════════
    //  生命周期
    // ══════════════════════════════════════

    private static bool _resolverRegistered = false;

    public override void _Ready()
    {
        // 注册 DllImport 解析器 (只能注册一次)
        if (!_resolverRegistered)
        {
            NativeLibrary.SetDllImportResolver(
                Assembly.GetExecutingAssembly(),
                DllImportResolver
            );
            _resolverRegistered = true;
        }

        // 尝试初始化
        _sdkAvailable = TryInit();
        _sdkChecked = true;

        if (_sdkAvailable)
        {
            GD.Print($"[FileSearch] Everything SDK 已就绪 (v{_sdkVersion}), DLL: {_dllPath}");
        }
        else
        {
            GD.Print($"[FileSearch] Everything SDK 未就绪: {_sdkError}");
            // 后台自动下载
            if (_sdkError == "dll_not_found")
            {
                GD.Print("[FileSearch] 正在后台下载 Everything SDK...");
                _isDownloading = true;
                _sdkError = "downloading";
                Task.Run(async () => await DownloadSDKAsync());
            }
        }
    }

    public override void _ExitTree()
    {
        CancelSearch();
    }

    // ══════════════════════════════════════
    //  DllImport 解析器 (关键: 自定义 DLL 搜索路径)
    // ══════════════════════════════════════

    private static string _resolvedDllDir = "";

    private static IntPtr DllImportResolver(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != DLL_NAME)
            return IntPtr.Zero;

        // 如果已知 DLL 路径，直接加载
        if (!string.IsNullOrEmpty(_resolvedDllDir))
        {
            var fullPath = Path.Combine(_resolvedDllDir, DLL_NAME);
            if (NativeLibrary.TryLoad(fullPath, out IntPtr handle))
                return handle;
        }

        // 降级到默认搜索
        return IntPtr.Zero;
    }

    // ══════════════════════════════════════
    //  初始化 & DLL 查找
    // ══════════════════════════════════════

    private bool TryInit()
    {
        // 查找 DLL 文件
        var foundPath = FindDll();
        if (string.IsNullOrEmpty(foundPath))
        {
            _sdkError = "dll_not_found";
            return false;
        }

        _dllPath = foundPath;
        _resolvedDllDir = Path.GetDirectoryName(foundPath) ?? "";

        // 测试调用
        try
        {
            var major = Everything_GetMajorVersion();
            var err = Everything_GetLastError();

            if (err == EVERYTHING_ERROR_IPC)
            {
                _sdkError = "not_running";
                _sdkVersion = "";
                return false;
            }

            var minor = Everything_GetMinorVersion();
            var rev = Everything_GetRevision();
            _sdkVersion = $"{major}.{minor}.{rev}";
            _sdkError = "";
            return true;
        }
        catch (DllNotFoundException)
        {
            _sdkError = "dll_load_failed";
            return false;
        }
        catch (Exception e)
        {
            _sdkError = e.Message;
            return false;
        }
    }

    /// <summary>
    /// 在多个位置查找 Everything64.dll，返回完整路径或 null。
    /// </summary>
    private string FindDll()
    {
        var candidates = new List<string>();

        // 1. Godot 可执行文件目录
        try
        {
            var exeDir = AppDomain.CurrentDomain.BaseDirectory;
            if (!string.IsNullOrEmpty(exeDir))
                candidates.Add(Path.Combine(exeDir, DLL_NAME));
        }
        catch { }

        // 2. 项目根目录 (编辑器模式下 res:// 对应的路径)
        try
        {
            var resPath = ProjectSettings.GlobalizePath("res://");
            if (!string.IsNullOrEmpty(resPath))
                candidates.Add(Path.Combine(resPath, DLL_NAME));
        }
        catch { }

        // 3. 从正在运行的 Everything 进程获取路径
        try
        {
            var processes = Process.GetProcessesByName("Everything");
            foreach (var p in processes)
            {
                try
                {
                    var module = p.MainModule;
                    if (module != null)
                    {
                        var dir = Path.GetDirectoryName(module.FileName);
                        if (!string.IsNullOrEmpty(dir))
                            candidates.Add(Path.Combine(dir, DLL_NAME));
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
        }
        catch { }

        // 4. 注册表
        foreach (var regPath in new[] {
            @"SOFTWARE\voidtools\Everything",
            @"SOFTWARE\WOW6432Node\voidtools\Everything"
        })
        {
            try
            {
                using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(regPath);
                var installPath = key?.GetValue("InstallPath") as string
                    ?? key?.GetValue("Install_Dir") as string;
                if (!string.IsNullOrEmpty(installPath))
                    candidates.Add(Path.Combine(installPath, DLL_NAME));
            }
            catch { }

            try
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(regPath);
                var installPath = key?.GetValue("InstallPath") as string
                    ?? key?.GetValue("Install_Dir") as string;
                if (!string.IsNullOrEmpty(installPath))
                    candidates.Add(Path.Combine(installPath, DLL_NAME));
            }
            catch { }
        }

        // 5. 常见安装路径
        foreach (var dir in new[] {
            @"C:\Program Files\Everything",
            @"C:\Program Files (x86)\Everything",
            @"D:\Program Files\Everything",
            @"E:\Program Files\Everything",
            @"E:\Everything",
            @"D:\Everything",
            Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.ProgramFiles), "Everything"),
            Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.ProgramFilesX86), "Everything"),
            Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData), "Everything"),
        })
        {
            if (!string.IsNullOrEmpty(dir))
                candidates.Add(Path.Combine(dir, DLL_NAME));
        }

        // 依次检查
        foreach (var path in candidates)
        {
            try
            {
                if (File.Exists(path))
                {
                    GD.Print($"[FileSearch] 找到 DLL: {path}");
                    return path;
                }
            }
            catch { }
        }

        GD.Print("[FileSearch] 未在以下位置找到 Everything64.dll:");
        foreach (var path in candidates)
            GD.Print($"  - {path}");

        return null;
    }

    // ══════════════════════════════════════
    //  自动下载 SDK
    // ══════════════════════════════════════

    private async Task DownloadSDKAsync()
    {
        try
        {
            // 下载目标: Godot 可执行文件目录
            var targetDir = AppDomain.CurrentDomain.BaseDirectory;
            var targetDll = Path.Combine(targetDir, DLL_NAME);

            // 如果已经存在就跳过
            if (File.Exists(targetDll))
            {
                GD.Print("[FileSearch] DLL 已存在，跳过下载");
                _isDownloading = false;
                // 重试初始化
                CallDeferred(nameof(RetryInit));
                return;
            }

            using var http = new System.Net.Http.HttpClient();
            http.Timeout = TimeSpan.FromSeconds(30);

            GD.Print($"[FileSearch] 正在下载: {SDK_URL}");
            var zipBytes = await http.GetByteArrayAsync(SDK_URL);
            GD.Print($"[FileSearch] 下载完成: {zipBytes.Length} bytes");

            // 解压找到 Everything64.dll
            using var zipStream = new MemoryStream(zipBytes);
            using var archive = new ZipArchive(zipStream, ZipArchiveMode.Read);

            ZipArchiveEntry dllEntry = null;
            foreach (var entry in archive.Entries)
            {
                if (entry.Name.Equals(DLL_NAME, StringComparison.OrdinalIgnoreCase))
                {
                    // 优先选 dll/Everything64.dll (而非 x86 版)
                    if (entry.FullName.Contains("x64") || entry.FullName.Contains("dll") || dllEntry == null)
                        dllEntry = entry;
                }
            }

            if (dllEntry == null)
            {
                GD.PrintErr("[FileSearch] SDK zip 中未找到 Everything64.dll");
                _sdkError = "download_failed";
                _isDownloading = false;
                return;
            }

            // 解压到目标目录
            using (var entryStream = dllEntry.Open())
            using (var fileStream = File.Create(targetDll))
            {
                await entryStream.CopyToAsync(fileStream);
            }

            GD.Print($"[FileSearch] DLL 已解压到: {targetDll}");
            _isDownloading = false;

            // 回主线程重试初始化
            CallDeferred(nameof(RetryInit));
        }
        catch (Exception e)
        {
            GD.PrintErr($"[FileSearch] SDK 下载失败: {e.Message}");
            _sdkError = "download_failed";
            _isDownloading = false;
        }
    }

    private void RetryInit()
    {
        _sdkAvailable = TryInit();
        _sdkChecked = true;

        if (_sdkAvailable)
            GD.Print($"[FileSearch] 重试成功! Everything v{_sdkVersion} 已就绪");
        else
            GD.Print($"[FileSearch] 重试失败: {_sdkError}");
    }

    // ══════════════════════════════════════
    //  公共 API
    // ══════════════════════════════════════

    public Godot.Collections.Dictionary GetStatus()
    {
        // 如果正在下载或之前失败, 重试
        if (!_sdkAvailable && !_isDownloading)
        {
            _sdkAvailable = TryInit();
        }

        var result = new Godot.Collections.Dictionary();
        result["available"] = _sdkAvailable;
        result["error"] = _sdkError;
        result["version"] = _sdkVersion;
        result["downloading"] = _isDownloading;
        return result;
    }

    public void StartSearch(string query, int maxResults = 200, string searchScope = "all")
    {
        CancelSearch();

        lock (_lock)
        {
            _resultBuffer.Clear();
            _deliveredCount = 0;
            _totalFound = 0;
            _totalMatched = 0;
            _searchDone = false;
        }

        if (string.IsNullOrWhiteSpace(query))
        {
            _searchDone = true;
            return;
        }

        if (!_sdkAvailable)
        {
            _sdkAvailable = TryInit();
            if (!_sdkAvailable)
            {
                _searchDone = true;
                return;
            }
        }

        _cts = new CancellationTokenSource();
        _isSearching = true;
        var token = _cts.Token;
        var q = query.Trim();
        var max = maxResults;

        Task.Run(() =>
        {
            try { ExecuteSearch(q, max, token); }
            catch (Exception e) { GD.PrintErr($"[FileSearch] Error: {e.Message}"); }
            finally { _isSearching = false; _searchDone = true; }
        }, token);
    }

    public void CancelSearch()
    {
        if (_cts != null)
        {
            _cts.Cancel();
            _cts.Dispose();
            _cts = null;
        }
        _isSearching = false;
    }

    public Godot.Collections.Array PollResults()
    {
        var results = new Godot.Collections.Array();
        lock (_lock)
        {
            if (_deliveredCount < _resultBuffer.Count)
            {
                for (int i = _deliveredCount; i < _resultBuffer.Count; i++)
                    results.Add(_resultBuffer[i]);
                _deliveredCount = _resultBuffer.Count;
            }
        }
        return results;
    }

    public bool IsSearching() => _isSearching;
    public bool IsSearchDone() => _searchDone;
    public int GetTotalFound() => _totalFound;
    public int GetTotalMatched() => _totalMatched;

    // ══════════════════════════════════════
    //  搜索核心
    // ══════════════════════════════════════

    private void ExecuteSearch(string query, int maxResults, CancellationToken ct)
    {
        if (ct.IsCancellationRequested) return;

        Everything_SetSearchW(query);
        Everything_SetMax((uint)maxResults);
        Everything_SetOffset(0);
        Everything_SetRequestFlags(
            EVERYTHING_REQUEST_FILE_NAME |
            EVERYTHING_REQUEST_PATH |
            EVERYTHING_REQUEST_SIZE |
            EVERYTHING_REQUEST_DATE_MODIFIED |
            EVERYTHING_REQUEST_EXTENSION
        );
        Everything_SetSort((uint)EVERYTHING_SORT_DATE_MODIFIED_DESCENDING);

        if (!Everything_QueryW(true))
        {
            var err = Everything_GetLastError();
            GD.PrintErr($"[FileSearch] Query failed, error: {err}");

            // IPC 错误 = Everything 掉线了
            if (err == EVERYTHING_ERROR_IPC)
            {
                _sdkAvailable = false;
                _sdkError = "not_running";
                GD.Print("[FileSearch] Everything IPC 断开，引擎已标记为离线");
            }
            return;
        }

        if (ct.IsCancellationRequested) return;

        var numResults = Everything_GetNumResults();
        _totalMatched = (int)Everything_GetTotResults();
        var pathBuf = new System.Text.StringBuilder(512);

        for (uint i = 0; i < numResults; i++)
        {
            if (ct.IsCancellationRequested) break;

            var item = new Godot.Collections.Dictionary();

            var namePtr = Everything_GetResultFileName(i);
            item["name"] = namePtr != IntPtr.Zero ? Marshal.PtrToStringUni(namePtr) : "";

            var pathPtr = Everything_GetResultPath(i);
            item["path"] = pathPtr != IntPtr.Zero ? Marshal.PtrToStringUni(pathPtr) : "";

            pathBuf.Clear();
            Everything_GetResultFullPathName(i, pathBuf, (uint)pathBuf.Capacity);
            item["full_path"] = pathBuf.ToString();

            item["is_folder"] = Everything_IsFolderResult(i);
            item["size"] = Everything_GetResultSize(i, out long fileSize) ? fileSize : 0L;

            if (Everything_GetResultDateModified(i, out long fileTime))
            {
                try { item["date_modified"] = DateTime.FromFileTime(fileTime).ToString("yyyy-MM-dd HH:mm"); }
                catch { item["date_modified"] = ""; }
            }
            else item["date_modified"] = "";

            var extPtr = Everything_GetResultExtension(i);
            item["extension"] = extPtr != IntPtr.Zero ? Marshal.PtrToStringUni(extPtr) : "";

            lock (_lock)
            {
                _resultBuffer.Add(item);
                _totalFound++;
            }
        }
    }
}
