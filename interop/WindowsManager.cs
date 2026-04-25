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
    /// 将主窗口彻底从 Windows 任务栏中抹除
    /// </summary>
    public void HideFromTaskbar()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        ShowWindow(hwnd, SW_HIDE);
        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        style |= WS_EX_TOOLWINDOW;
        style &= ~WS_EX_APPWINDOW;
        SetWindowLong(hwnd, GWL_EXSTYLE, style);
        ShowWindow(hwnd, SW_SHOW);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }

    /// <summary>
    /// 自检：如果窗口扩展样式被引擎意外重置，重新推入 ToolWindow 标记
    /// </summary>
    public bool EnsureHiddenFromTaskbar()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        bool needsFix = (style & WS_EX_TOOLWINDOW) == 0 || (style & WS_EX_APPWINDOW) != 0;
        if (needsFix) HideFromTaskbar();
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
            if (IsIconic(hWnd)) continue;

            GetWindowThreadProcessId(hWnd, out uint processId);
            if (processId == _myProcessId) continue;

            System.Text.StringBuilder title = new System.Text.StringBuilder(256);
            GetWindowText(hWnd, title, 256);
            if (title.Length == 0) continue;

            var clsBuf = new StringBuilder(256);
            GetClassName(hWnd, clsBuf, 256);
            if (_ghostWindowClasses.Contains(clsBuf.ToString())) continue;

            int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            if ((exStyle & WS_EX_TOOLWINDOW) != 0) continue;
            if ((exStyle & WS_EX_TRANSPARENT) != 0 && (exStyle & WS_EX_LAYERED) != 0) continue;

            DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out int cloaked, sizeof(int));
            if (cloaked != 0) continue;

            if (DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT rect, Marshal.SizeOf(typeof(RECT))) == 0)
            {
                if (rect.Right - rect.Left < 100 || rect.Bottom - rect.Top < 50) continue;

                var newRect = new Rect2I(
                    rect.Left, rect.Top,
                    rect.Right - rect.Left, rect.Bottom - rect.Top
                );

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
                    result.Add(newRect);
            }
        }

        return result;
    }


    // ══════════════════════════════════════════════════════════════
    //  混合形状窗口区域 (GDI Region API)
    //  ── 椭圆区域 (宠物本体精确命中) + 矩形区域 (UI 气泡/时钟) ──
    //  ── 通过 CombineRgn(RGN_OR) 合并后应用到窗口 ──
    //  ── 已知限制: SetWindowRgn 会同时裁剪视觉特效 (冲击波/拖影) ──
    // ══════════════════════════════════════════════════════════════

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateEllipticRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);

    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(IntPtr hrgnDest, IntPtr hrgnSrc1, IntPtr hrgnSrc2, int iMode);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

    private const int RGN_OR = 2;

    /// <summary>
    /// 混合形状命中区域: 椭圆 (宠物) + 矩形 (UI) 合并后应用为窗口区域。
    /// circles: [cx1, cy1, r1, cx2, cy2, r2, ...]  — 宠物本体 (创建椭圆区域)
    /// rects:   [x1, y1, w1, h1, x2, y2, w2, h2, ...] — UI 元素 (创建矩形区域)
    /// 坐标为窗口客户区坐标 (与 Godot 视口坐标一致)。
    /// 区域间隙完全穿透到桌面。
    /// </summary>
    public void UpdateHitRegions(float[] circles, float[] rects)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);

        IntPtr combined = IntPtr.Zero;

        // ── 圆形区域: 使用 CreateEllipticRgn (精确圆形命中) ──
        if (circles != null)
        {
            for (int i = 0; i + 2 < circles.Length; i += 3)
            {
                float cx = circles[i], cy = circles[i + 1], r = circles[i + 2];
                IntPtr rgn = CreateEllipticRgn(
                    (int)(cx - r), (int)(cy - r),
                    (int)(cx + r), (int)(cy + r)
                );

                if (combined == IntPtr.Zero)
                {
                    combined = rgn;
                }
                else
                {
                    CombineRgn(combined, combined, rgn, RGN_OR);
                    DeleteObject(rgn);
                }
            }
        }

        // ── 矩形区域: 使用 CreateRectRgn (UI 元素) ──
        if (rects != null)
        {
            for (int i = 0; i + 3 < rects.Length; i += 4)
            {
                float x = rects[i], y = rects[i + 1], w = rects[i + 2], h = rects[i + 3];
                IntPtr rgn = CreateRectRgn(
                    (int)x, (int)y,
                    (int)(x + w), (int)(y + h)
                );

                if (combined == IntPtr.Zero)
                {
                    combined = rgn;
                }
                else
                {
                    CombineRgn(combined, combined, rgn, RGN_OR);
                    DeleteObject(rgn);
                }
            }
        }

        // 无任何区域时设置最小占位 (1x1 像素，防止全屏捕获)
        if (combined == IntPtr.Zero)
        {
            combined = CreateRectRgn(0, 0, 1, 1);
        }

        // 应用到窗口 (系统接管区域句柄的所有权)
        SetWindowRgn(hwnd, combined, true);
    }

    /// <summary>
    /// 切换全窗口交互模式 (拖拽/菜单打开时整个窗口可点击)
    /// </summary>
    public void SetFullWindowHit(bool enabled)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (enabled)
        {
            // 清除区域限制 → 整个窗口可交互
            SetWindowRgn(hwnd, IntPtr.Zero, true);
        }
        // disabled 时不需要做什么，下一帧 UpdateHitRegions 会自然恢复精确区域
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
