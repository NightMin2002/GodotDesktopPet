using Godot;
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using Microsoft.Win32;

public partial class WindowsManager : Node
{
    // ── Win32 API 导入 ──
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd); // 判断是否最小化

    [DllImport("user32.dll")]
    private static extern IntPtr GetShellWindow();

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14; 
    
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_APPWINDOW = 0x00040000;

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    private static extern bool SetPriorityClass(IntPtr hProcess, uint dwPriorityClass);

    private const uint ABOVE_NORMAL_PRIORITY_CLASS = 0x00008000;

    private uint _myProcessId;
    private IntPtr _shellWindow;

    public override void _Ready()
    {
        // 获取当前运行时的进程 ID（但无法彻底防御你在使用编辑器预览时的编辑器窗口）
        _myProcessId = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        _shellWindow = GetShellWindow();
    }

    /// <summary>
    /// 将进程优先级提升至 Above Normal，对抗游戏等高占用程序的资源抢夺
    /// </summary>
    public void BoostProcessPriority()
    {
        SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS);
    }

    private const string AutoStartKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AutoStartName = "DesktopPet";

    /// <summary>
    /// 检测当前是否已注册开机自启动
    /// </summary>
    public bool IsAutoStartEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(AutoStartKey, false);
            return key?.GetValue(AutoStartName) != null;
        }
        catch { return false; }
    }

    /// <summary>
    /// 设置/移除开机自启动注册表项
    /// </summary>
    public void SetAutoStart(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(AutoStartKey, true);
            if (key == null) return;
            if (enabled)
            {
                var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? "";
                if (!string.IsNullOrEmpty(exePath))
                    key.SetValue(AutoStartName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(AutoStartName, false);
            }
        }
        catch { /* 权限不足时静默 */ }
    }

    /// <summary>
    /// 将主窗口彻底从 Windows 任务栏中抹除（使其变成工具悬浮层属性）
    /// </summary>
    public void HideFromTaskbar()
    {
        // 从 Godot 取得原生 HWND 句柄
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        
        // 移除普通 App 窗口特征，并打上工具悬浮窗特征 (ToolWindow 不会出现在任务栏和 Alt+Tab 中)
        style |= WS_EX_TOOLWINDOW;
        style &= ~WS_EX_APPWINDOW;
        
        SetWindowLong(hwnd, GWL_EXSTYLE, style);
    }

    /// <summary>
    /// 获取当前系统的所有活跃可见窗口真实的屏幕坐标系矩形边界
    /// </summary>
    public Godot.Collections.Array<Rect2I> GetVisibleWindowRects()
    {
        var result = new Godot.Collections.Array<Rect2I>();
        List<IntPtr> windows = new List<IntPtr>();

        EnumWindows((hWnd, lParam) => {
            windows.Add(hWnd);
            return true;
        }, IntPtr.Zero);

        foreach (IntPtr hWnd in windows)
        {
            if (hWnd == _shellWindow) continue;
            if (!IsWindowVisible(hWnd)) continue;
            if (IsIconic(hWnd)) continue; // 忽略最小化的窗口

            // 过滤自身
            GetWindowThreadProcessId(hWnd, out uint processId);
            if (processId == _myProcessId) continue;

            // 过滤没有标题的幽灵窗口（有些系统的隐形基础挂靠）
            System.Text.StringBuilder title = new System.Text.StringBuilder(256);
            GetWindowText(hWnd, title, 256);
            if (title.Length == 0) continue;

            // 过滤隐形的 Win10/11 Cloaked 系统虚空层（极为致命！必须过滤）
            DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out int cloaked, sizeof(int));
            if (cloaked != 0) continue;

            // 获取真实的视觉边框坐标（剔除 Win10/11 那看不见的 7 像素拖拽阴影边框）
            if (DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT rect, Marshal.SizeOf(typeof(RECT))) == 0)
            {
                // 如果被后台挂载的极小虚空碎片干扰，则直接丢弃
                if (rect.Right - rect.Left < 100 || rect.Bottom - rect.Top < 50) continue;

                var newRect = new Rect2I(
                    rect.Left,
                    rect.Top,
                    rect.Right - rect.Left,
                    rect.Bottom - rect.Top
                );

                // Z-Order 空间遮挡剔除测试 (Z-Culling)
                // 因为 EnumWindows 天然返回从最顶层向下遍历的窗口数组结果
                // 所以如果在 result 里有某一个更高层级的界面（例如前台最大化的浏览器）“完全包围/盖住”了当前的新窗口
                // 那么这个被埋在下面的背景窗口就应该被我们剔除，防止宠物在视觉覆盖物里撞空气墙
                bool isTotallyOccluded = false;
                foreach (var topRect in result)
                {
                    if (topRect.Encloses(newRect))
                    {
                        isTotallyOccluded = true;
                        break;
                    }
                }

                if (!isTotallyOccluded)
                {
                    result.Add(newRect);
                }
            }
        }

        return result;
    }
}
