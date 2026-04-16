using Godot;
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Text;
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

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

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
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_LAYERED = 0x00080000;

    // 已知会产生幽灵墙的隐形系统窗口类名
    private static readonly HashSet<string> _ghostWindowClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "Progman",                      // 桌面管理器
        "WorkerW",                      // 桌面壁纸层
        "Shell_SecondaryTrayWnd",       // 多显示器任务栏
        "Shell_TrayWnd",                // 主任务栏
        "Windows.UI.Core.CoreWindow",   // UWP 覆盖层 (通知中心等)
        "XamlExplorerHostIslandWindow", // UWP 内部宿主
        "InputApp",                     // 触摸键盘
        "EdgeUiInputTopWndClass",       // Edge 手势层
        "Shell_InputSwitchTopLevelWindow", // 输入法切换层
    };

    private const int SW_HIDE = 0;
    private const int SW_SHOW = 5;

    private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_FRAMECHANGED = 0x0020;

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
    /// 三步法: Hide → 修改样式 → Show，强制 Windows Shell 刷新任务栏状态
    /// </summary>
    public void HideFromTaskbar()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        
        // Step 1: 先隐藏窗口，让 Shell 从任务栏移除此条目
        ShowWindow(hwnd, SW_HIDE);
        
        // Step 2: 修改扩展样式
        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        style |= WS_EX_TOOLWINDOW;
        style &= ~WS_EX_APPWINDOW;
        SetWindowLong(hwnd, GWL_EXSTYLE, style);
        
        // Step 3: 重新显示窗口 (Shell 会根据新样式决定是否添加到任务栏)
        ShowWindow(hwnd, SW_SHOW);
        
        // Step 4: 通知系统窗口帧已变更 (强制刷新)
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }

    /// <summary>
    /// 自检：如果窗口扩展样式被引擎意外重置，重新推入 ToolWindow 标记
    /// 返回 true = 样式被修复 (需要调用方关注)
    /// </summary>
    public bool EnsureHiddenFromTaskbar()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        
        bool needsFix = (style & WS_EX_TOOLWINDOW) == 0 || (style & WS_EX_APPWINDOW) != 0;
        if (needsFix)
        {
            HideFromTaskbar();
        }
        return needsFix;
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

            // 过滤已知的系统隐形窗口类名 (桌面管理器、任务栏、UWP覆盖层等)
            var clsBuf = new StringBuilder(256);
            GetClassName(hWnd, clsBuf, 256);
            if (_ghostWindowClasses.Contains(clsBuf.ToString())) continue;

            // 过滤 ToolWindow (工具悬浮窗口，包括宠物自身的 WS_EX_TOOLWINDOW 窗口)
            int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if ((exStyle & WS_EX_TOOLWINDOW) != 0) continue;
            // 过滤完全透明的叠加层窗口
            if ((exStyle & WS_EX_TRANSPARENT) != 0 && (exStyle & WS_EX_LAYERED) != 0) continue;

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



    // ── 多矩形窗口区域 (GDI Region API) ──
    // 绕过 Godot window_set_mouse_passthrough 的单多边形限制
    // 使用 CombineRgn(RGN_OR) 将多个矩形合并为真正的联合区域

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);

    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(IntPtr hrgnDest, IntPtr hrgnSrc1, IntPtr hrgnSrc2, int iMode);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

    private const int RGN_OR = 2; // 联合模式: 合并两个区域

    /// <summary>
    /// 将多个独立矩形区域合并后应用为窗口可见/可交互区域。
    /// 每个矩形独立存在，矩形之间的间隙完全穿透。
    /// 坐标为窗口客户区坐标 (与 Godot 视口坐标一致)。
    /// </summary>
    public void SetWindowRegion(Godot.Collections.Array<Rect2I> rects)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);

        if (rects == null || rects.Count == 0)
        {
            // 空数组 = 清除区域限制 (整个窗口可见)
            SetWindowRgn(hwnd, IntPtr.Zero, true);
            return;
        }

        // 创建第一个矩形作为基础区域
        var r0 = rects[0];
        IntPtr combined = CreateRectRgn(r0.Position.X, r0.Position.Y,
            r0.Position.X + r0.Size.X, r0.Position.Y + r0.Size.Y);

        // 逐个合并后续矩形
        for (int i = 1; i < rects.Count; i++)
        {
            var r = rects[i];
            IntPtr temp = CreateRectRgn(r.Position.X, r.Position.Y,
                r.Position.X + r.Size.X, r.Position.Y + r.Size.Y);
            CombineRgn(combined, combined, temp, RGN_OR);
            DeleteObject(temp); // 临时区域用完即删
        }

        // 应用到窗口 (系统接管区域句柄的所有权，无需手动删除)
        SetWindowRgn(hwnd, combined, true);
    }

    /// <summary>
    /// 清除窗口区域限制，恢复整个窗口可见
    /// </summary>
    public void ClearWindowRegion()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        SetWindowRgn(hwnd, IntPtr.Zero, true);
    }
}
