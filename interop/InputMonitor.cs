using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>
/// 全局键鼠输入监控器
/// 键盘: WH_KEYBOARD_LL 低级钩子 (按键频率低, 无性能影响)
/// 鼠标: 纯轮询 GetAsyncKeyState + GetCursorPos (不使用鼠标钩子, 避免卡鼠标)
/// 代价: 滚轮无法通过轮询采集, 暂不支持
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

        GD.Print($"[InputMonitor] 监控已启动 (keyboard_hook={_kbHook != IntPtr.Zero}, mouse=polling)");
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
}
