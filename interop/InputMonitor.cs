using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>
/// 全局键鼠输入 + 窗口追踪 监控器
/// 键盘: WH_KEYBOARD_LL 低级钩子
/// 鼠标: 纯轮询 GetAsyncKeyState + GetCursorPos
/// 窗口: 轮询 GetForegroundWindow (每5秒), 按进程名聚合
/// </summary>
public partial class InputMonitor : Node
{
    // ══════════════════════════════════════════════════════════════
    //  Win32 API
    // ══════════════════════════════════════════════════════════════

    private delegate IntPtr LowLevelHookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelHookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private const int WH_KEYBOARD_LL = 13;
    private const int HC_ACTION = 0;

    // 键盘消息
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;

    // 鼠标按键虚拟键码 (用于 GetAsyncKeyState 轮询)
    private const int VK_LBUTTON = 0x01;
    private const int VK_RBUTTON = 0x02;
    private const int VK_MBUTTON = 0x04;

    // 修饰键虚拟键码
    private const uint VK_LSHIFT = 0xA0;
    private const uint VK_RSHIFT = 0xA1;
    private const uint VK_LCONTROL = 0xA2;
    private const uint VK_RCONTROL = 0xA3;
    private const uint VK_LMENU = 0xA4;
    private const uint VK_RMENU = 0xA5;

    // ══════════════════════════════════════════════════════════════
    //  统计数据
    // ══════════════════════════════════════════════════════════════

    private readonly Dictionary<string, long> _keyStats = new();
    private readonly Dictionary<string, long> _comboStats = new();

    private long _leftClicks = 0;
    private long _rightClicks = 0;
    private long _middleClicks = 0;
    private double _mouseDistancePx = 0;

    // 修饰键状态 (键盘钩子维护)
    private bool _ctrlDown = false;
    private bool _shiftDown = false;
    private bool _altDown = false;

    // 键盘钩子句柄
    private IntPtr _kbHook = IntPtr.Zero;
    private LowLevelHookProc _kbProc; // 防 GC

    // 鼠标轮询状态
    private bool _lastLButton = false;
    private bool _lastRButton = false;
    private bool _lastMButton = false;
    private POINT _lastMousePos;
    private bool _hasLastMousePos = false;
    private double _pollTimer = 0;
    private const double MOUSE_POLL_INTERVAL = 0.05; // 50ms (20Hz 足够检测点击)

    // 是否活跃
    private bool _active = false;
    private DateTime _sessionStart;

    // 窗口追踪
    private class WindowInfo
    {
        public string ProcessName;
        public HashSet<string> Titles = new();
        public DateTime FirstSeen;
        public DateTime LastActive;
        public double FocusSeconds;  // 累计前台时长
    }
    private readonly Dictionary<string, WindowInfo> _windowStats = new();
    private string _lastFgProcess = "";
    private DateTime _lastFgTime;
    private double _windowPollTimer = 0;
    private const double WINDOW_POLL_INTERVAL = 5.0; // 5秒轮询一次

    // ══════════════════════════════════════════════════════════════
    //  生命周期
    // ══════════════════════════════════════════════════════════════

    public override void _Ready()
    {
        GD.Print("[InputMonitor] 初始化完成, 等待启动");
    }

    public override void _Process(double delta)
    {
        if (!_active) return;

        _pollTimer += delta;
        if (_pollTimer < MOUSE_POLL_INTERVAL) return;
        _pollTimer = 0;

        // ── 鼠标按键轮询 (检测 not pressed → pressed 的边沿) ──
        bool lDown = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
        bool rDown = (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
        bool mDown = (GetAsyncKeyState(VK_MBUTTON) & 0x8000) != 0;

        if (lDown && !_lastLButton) _leftClicks++;
        if (rDown && !_lastRButton) _rightClicks++;
        if (mDown && !_lastMButton) _middleClicks++;

        _lastLButton = lDown;
        _lastRButton = rDown;
        _lastMButton = mDown;

        // ── 鼠标移动距离轮询 ──
        if (GetCursorPos(out POINT pos))
        {
            if (_hasLastMousePos)
            {
                double dx = pos.X - _lastMousePos.X;
                double dy = pos.Y - _lastMousePos.Y;
                _mouseDistancePx += Math.Sqrt(dx * dx + dy * dy);
            }
            _lastMousePos = pos;
            _hasLastMousePos = true;
        }

        // ── 前台窗口轮询 (5秒一次) ──
        _windowPollTimer += MOUSE_POLL_INTERVAL; // 借用鼠标轮询的计时
        if (_windowPollTimer >= WINDOW_POLL_INTERVAL)
        {
            _windowPollTimer = 0;
            PollForegroundWindow();
        }
    }

    public override void _ExitTree()
    {
        StopMonitoring();
    }

    // ══════════════════════════════════════════════════════════════
    //  GDScript 可调用 API
    // ══════════════════════════════════════════════════════════════

    /// <summary>启动监控 (仅键盘钩子 + 鼠标轮询)</summary>
    public void StartMonitoring()
    {
        if (_active) return;
        _active = true;
        _sessionStart = DateTime.Now;

        _kbProc = KeyboardHookCallback;
        IntPtr hMod = GetModuleHandle(null);
        _kbHook = SetWindowsHookEx(WH_KEYBOARD_LL, _kbProc, hMod, 0);

        _lastFgTime = DateTime.Now;

        // 冷启动: 扫描当前所有可见窗口
        ScanAllVisibleWindows();

        GD.Print($"[InputMonitor] 监控已启动 (keyboard_hook={_kbHook != IntPtr.Zero}, mouse=polling, window=5s, 初始窗口={_windowStats.Count})");
    }

    /// <summary>停止监控</summary>
    public void StopMonitoring()
    {
        if (!_active) return;
        _active = false;

        if (_kbHook != IntPtr.Zero) { UnhookWindowsHookEx(_kbHook); _kbHook = IntPtr.Zero; }
        GD.Print("[InputMonitor] 监控已停止");
    }

    public bool IsActive() => _active;

    /// <summary>获取每键计数</summary>
    public Godot.Collections.Dictionary GetKeyStats()
    {
        var dict = new Godot.Collections.Dictionary();
        foreach (var kv in _keyStats) dict[kv.Key] = kv.Value;
        return dict;
    }

    /// <summary>获取组合键计数</summary>
    public Godot.Collections.Dictionary GetComboStats()
    {
        var dict = new Godot.Collections.Dictionary();
        foreach (var kv in _comboStats) dict[kv.Key] = kv.Value;
        return dict;
    }

    /// <summary>获取鼠标统计</summary>
    public Godot.Collections.Dictionary GetMouseStats()
    {
        var dict = new Godot.Collections.Dictionary();
        dict["left_clicks"] = _leftClicks;
        dict["right_clicks"] = _rightClicks;
        dict["middle_clicks"] = _middleClicks;
        dict["distance_px"] = (long)_mouseDistancePx;
        return dict;
    }

    /// <summary>获取窗口使用统计 (按进程名聚合)</summary>
    public Godot.Collections.Dictionary GetWindowStats()
    {
        // 先结算当前前台窗口的时长
        FlushCurrentFg();
        var dict = new Godot.Collections.Dictionary();
        foreach (var kv in _windowStats)
        {
            var info = kv.Value;
            var entry = new Godot.Collections.Dictionary();
            entry["process"] = info.ProcessName;
            var titlesArr = new Godot.Collections.Array();
            foreach (var t in info.Titles) titlesArr.Add(t);
            entry["titles"] = titlesArr;
            entry["focus_sec"] = (long)info.FocusSeconds;
            entry["first_seen"] = info.FirstSeen.ToString("HH:mm:ss");
            entry["last_active"] = info.LastActive.ToString("HH:mm:ss");
            dict[kv.Key] = entry;
        }
        return dict;
    }

    /// <summary>获取总击键次数</summary>
    public long GetTotalKeystrokes()
    {
        long total = 0;
        foreach (var v in _keyStats.Values) total += v;
        return total;
    }

    /// <summary>获取会话时长 (秒)</summary>
    public double GetSessionDurationSec()
    {
        if (!_active) return 0;
        return (DateTime.Now - _sessionStart).TotalSeconds;
    }

    /// <summary>获取完整快照</summary>
    public Godot.Collections.Dictionary GetFullSnapshot()
    {
        var snap = new Godot.Collections.Dictionary();
        snap["keys"] = GetKeyStats();
        snap["combos"] = GetComboStats();
        snap["mouse"] = GetMouseStats();
        snap["total_keystrokes"] = GetTotalKeystrokes();
        snap["session_sec"] = (long)GetSessionDurationSec();
        snap["windows"] = GetWindowStats();
        snap["timestamp"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        return snap;
    }

    /// <summary>重置所有统计数据</summary>
    public void ResetStats()
    {
        _keyStats.Clear();
        _comboStats.Clear();
        _leftClicks = 0;
        _rightClicks = 0;
        _middleClicks = 0;
        _mouseDistancePx = 0;
        _hasLastMousePos = false;
        _windowStats.Clear();
        _lastFgProcess = "";
        _windowPollTimer = 0;
        _sessionStart = DateTime.Now;
        GD.Print("[InputMonitor] 统计数据已重置");
    }

    // ══════════════════════════════════════════════════════════════
    //  键盘钩子回调 (仅键盘, 不钩鼠标)
    // ══════════════════════════════════════════════════════════════

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= HC_ACTION)
        {
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                uint vk = info.vkCode;

                if (vk == VK_LCONTROL || vk == VK_RCONTROL) _ctrlDown = true;
                else if (vk == VK_LSHIFT || vk == VK_RSHIFT) _shiftDown = true;
                else if (vk == VK_LMENU || vk == VK_RMENU) _altDown = true;
                else
                {
                    string keyName = VkToName(vk);
                    _keyStats[keyName] = _keyStats.GetValueOrDefault(keyName) + 1;

                    if (_ctrlDown || _altDown)
                    {
                        string combo = BuildComboName(vk);
                        _comboStats[combo] = _comboStats.GetValueOrDefault(combo) + 1;
                    }
                }
            }
            else
            {
                var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                uint vk = info.vkCode;
                if (vk == VK_LCONTROL || vk == VK_RCONTROL) _ctrlDown = false;
                else if (vk == VK_LSHIFT || vk == VK_RSHIFT) _shiftDown = false;
                else if (vk == VK_LMENU || vk == VK_RMENU) _altDown = false;
            }
        }
        return CallNextHookEx(_kbHook, nCode, wParam, lParam);
    }

    // ══════════════════════════════════════════════════════════════
    //  键名映射
    // ══════════════════════════════════════════════════════════════

    private string BuildComboName(uint vk)
    {
        string prefix = "";
        if (_ctrlDown) prefix += "Ctrl+";
        if (_altDown) prefix += "Alt+";
        if (_shiftDown) prefix += "Shift+";
        return prefix + VkToName(vk);
    }

    private static string VkToName(uint vk)
    {
        if (vk >= 0x41 && vk <= 0x5A) return ((char)vk).ToString();
        if (vk >= 0x30 && vk <= 0x39) return ((char)vk).ToString();
        if (vk >= 0x60 && vk <= 0x69) return "Num" + (vk - 0x60);
        if (vk >= 0x70 && vk <= 0x87) return "F" + (vk - 0x70 + 1);

        return vk switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x1B => "Escape",
            0x20 => "Space",
            0x21 => "PageUp",
            0x22 => "PageDown",
            0x23 => "End",
            0x24 => "Home",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2D => "Insert",
            0x2E => "Delete",
            0x6A => "Num*",
            0x6B => "Num+",
            0x6D => "Num-",
            0x6E => "Num.",
            0x6F => "Num/",
            0x90 => "NumLock",
            0x91 => "ScrollLock",
            0x14 => "CapsLock",
            0xBA => ";",
            0xBB => "=",
            0xBC => ",",
            0xBD => "-",
            0xBE => ".",
            0xBF => "/",
            0xC0 => "`",
            0xDB => "[",
            0xDC => "\\",
            0xDD => "]",
            0xDE => "'",
            _ => $"VK_{vk:X2}"
        };
    }

    // ══════════════════════════════════════════════════════════════
    //  前台窗口追踪
    // ══════════════════════════════════════════════════════════════

    private void PollForegroundWindow()
    {
        try
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return;
            if (!IsWindowVisible(hwnd)) return;

            // 获取进程名
            GetWindowThreadProcessId(hwnd, out uint pid);
            string procName;
            try
            {
                var proc = System.Diagnostics.Process.GetProcessById((int)pid);
                procName = proc.ProcessName;
            }
            catch { return; } // 进程可能已退出

            // 获取窗口标题
            var sb = new System.Text.StringBuilder(512);
            GetWindowText(hwnd, sb, 512);
            string title = sb.ToString().Trim();
            if (string.IsNullOrEmpty(title)) return;

            // 过滤自身和系统任务栏
            if (procName == "explorer" || procName == "SearchHost" ||
                procName == "ShellExperienceHost" || procName == "StartMenuExperienceHost")
                return;

            var now = DateTime.Now;

            // 结算上一个前台窗口的时长
            FlushCurrentFg();

            // 更新统计
            if (!_windowStats.TryGetValue(procName, out var info))
            {
                info = new WindowInfo
                {
                    ProcessName = procName,
                    FirstSeen = now,
                };
                _windowStats[procName] = info;
            }
            info.Titles.Add(title); // HashSet 自动去重
            info.LastActive = now;

            _lastFgProcess = procName;
            _lastFgTime = now;
        }
        catch (Exception e)
        {
            GD.PrintErr($"[InputMonitor] 窗口轮询异常: {e.Message}");
        }
    }

    /// <summary>结算当前前台窗口的累计时长</summary>
    private void FlushCurrentFg()
    {
        if (string.IsNullOrEmpty(_lastFgProcess)) return;
        if (_windowStats.TryGetValue(_lastFgProcess, out var info))
        {
            double elapsed = (DateTime.Now - _lastFgTime).TotalSeconds;
            if (elapsed > 0 && elapsed < 60) // 防止异常大值
            {
                info.FocusSeconds += elapsed;
            }
        }
        _lastFgTime = DateTime.Now;
    }

    /// <summary>启动时扫描所有可见窗口, 填入统计表</summary>
    private void ScanAllVisibleWindows()
    {
        var now = DateTime.Now;
        var skipProcesses = new HashSet<string>
        {
            "explorer", "SearchHost", "ShellExperienceHost",
            "StartMenuExperienceHost", "TextInputHost",
            "ApplicationFrameHost", "SystemSettings",
            "svchost", "csrss", "dwm", "winlogon"
        };

        EnumWindows((hWnd, _) =>
        {
            try
            {
                if (!IsWindowVisible(hWnd)) return true;

                var sb = new System.Text.StringBuilder(512);
                GetWindowText(hWnd, sb, 512);
                string title = sb.ToString().Trim();
                if (string.IsNullOrEmpty(title)) return true;

                GetWindowThreadProcessId(hWnd, out uint pid);
                string procName;
                try
                {
                    var proc = System.Diagnostics.Process.GetProcessById((int)pid);
                    procName = proc.ProcessName;
                }
                catch { return true; }

                if (skipProcesses.Contains(procName)) return true;

                if (!_windowStats.TryGetValue(procName, out var info))
                {
                    info = new WindowInfo
                    {
                        ProcessName = procName,
                        FirstSeen = now,
                    };
                    _windowStats[procName] = info;
                }
                info.Titles.Add(title);
                info.LastActive = now;
                // 初始扫描不累计前台时长 (FocusSeconds 保持 0)
            }
            catch { /* 忽略单个窗口的异常 */ }
            return true; // 继续枚举
        }, IntPtr.Zero);
    }
}
