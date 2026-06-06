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

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);

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

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
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
    private const uint MONITOR_DEFAULTTONEAREST = 0x00000002;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOZORDER = 0x0004;
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

    // ── 全局鼠标状态检测 (供拖放悬停检测用) ──

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT pt);

    [DllImport("user32.dll")]
    private static extern bool GetCursorInfo(ref CURSORINFO pci);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadCursor(IntPtr hInstance, int lpCursorName);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct CURSORINFO
    {
        public int cbSize;
        public int flags;
        public IntPtr hCursor;
        public POINT ptScreenPos;
    }

    private const int VK_LBUTTON = 0x01;

    // 所有标准系统光标 ID (从 winuser.h)
    private static readonly int[] _standardCursorIds = {
        32512, // IDC_ARROW
        32513, // IDC_IBEAM
        32514, // IDC_WAIT
        32515, // IDC_CROSS
        32516, // IDC_UPARROW
        32642, // IDC_SIZENWSE
        32643, // IDC_SIZENESW
        32644, // IDC_SIZEWE
        32645, // IDC_SIZENS
        32646, // IDC_SIZEALL
        32648, // IDC_NO
        32649, // IDC_HAND
        32650, // IDC_APPSTARTING
        32651, // IDC_HELP
    };
    private static HashSet<IntPtr> _standardCursorHandles;

    /// <summary>
    /// 检测全局鼠标状态 (不依赖 Godot 输入系统)。
    /// 返回: [isHeld, screenX, screenY, isDragCursor]
    ///   isHeld: 左键是否按住
    ///   isDragCursor: 光标是否为非标准光标 (OLE 拖拽时光标变成带文件图标的特殊光标)
    /// </summary>
    public int[] GetGlobalMouseState()
    {
        bool held = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
        GetCursorPos(out POINT pt);

        // 检测当前光标是否为标准系统光标
        bool isDragCursor = false;
        if (held)
        {
            // 懒加载标准光标句柄集合
            if (_standardCursorHandles == null)
            {
                _standardCursorHandles = new HashSet<IntPtr>();
                foreach (int id in _standardCursorIds)
                {
                    IntPtr h = LoadCursor(IntPtr.Zero, id);
                    if (h != IntPtr.Zero) _standardCursorHandles.Add(h);
                }
            }

            var ci = new CURSORINFO();
            ci.cbSize = System.Runtime.InteropServices.Marshal.SizeOf(ci);
            if (GetCursorInfo(ref ci) && ci.hCursor != IntPtr.Zero)
            {
                // 如果当前光标不属于任何标准光标 → 可能是 OLE 拖拽光标
                isDragCursor = !_standardCursorHandles.Contains(ci.hCursor);
            }
        }

        return new[] { held ? 1 : 0, pt.X, pt.Y, isDragCursor ? 1 : 0 };
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
    /// 获取当前显示器工作区在 Godot 窗口客户区内的坐标。
    /// rcWork 由 Windows 计算，会排除任务栏和停靠式 AppBar。
    /// </summary>
    public Rect2I GetCurrentMonitorWorkAreaInWindow()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (hwnd == IntPtr.Zero)
            return new Rect2I();

        IntPtr monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        if (monitor == IntPtr.Zero)
            return new Rect2I();

        var info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(monitor, ref info))
            return new Rect2I();

        var topLeft = new POINT { X = info.rcWork.Left, Y = info.rcWork.Top };
        var bottomRight = new POINT { X = info.rcWork.Right, Y = info.rcWork.Bottom };
        if (!ScreenToClient(hwnd, ref topLeft) || !ScreenToClient(hwnd, ref bottomRight))
            return new Rect2I();

        return new Rect2I(
            topLeft.X,
            topLeft.Y,
            bottomRight.X - topLeft.X,
            bottomRight.Y - topLeft.Y
        );
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

    [DllImport("user32.dll")]
    private static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    private const uint LWA_ALPHA = 0x02;

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
    // ══════════════════════════════════════════════════════════════
    //  WS_EX_TRANSPARENT 完美穿透方案 (手动注入 WS_EX_LAYERED)
    //  ── 不使用 SetWindowRgn，零视觉裁剪 ──
    //  ── GDScript 端检测鼠标位置，仅在进出宠物区域时切换 ──
    // ══════════════════════════════════════════════════════════════

    /// <summary>
    /// 向 Godot 窗口注入 WS_EX_LAYERED 标志位。
    /// Godot 4.x Compatibility/OpenGL 渲染器默认不设置此标志，
    /// 但手动注入后配合 SetLayeredWindowAttributes(255) 不影响渲染，
    /// 且使 WS_EX_TRANSPARENT 切换生效。
    /// 返回 true = 注入成功，可以使用 SetClickThrough。
    /// </summary>
    public bool InjectLayeredStyle()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (hwnd == IntPtr.Zero)
            return false;

        int style = GetWindowLong(hwnd, GWL_EXSTYLE);

        if ((style & WS_EX_LAYERED) == 0)
        {
            style |= WS_EX_LAYERED;
            SetWindowLong(hwnd, GWL_EXSTYLE, style);
        }

        SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
        ApplyFrameChanged(hwnd);

        // 同时清除残留的 SetWindowRgn 裁剪
        SetWindowRgn(hwnd, IntPtr.Zero, true);

        bool success = (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_LAYERED) != 0;
        if (success)
            GD.Print("[DWM] WS_EX_LAYERED 注入成功 -> 启用 WS_EX_TRANSPARENT 穿透模式");
        else
            GD.Print("[DWM] WS_EX_LAYERED 注入失败 -> 回退 SetWindowRgn 模式");
        return success;
    }

    /// <summary>
    /// 切换窗口鼠标穿透状态 (需要 WS_EX_LAYERED 已注入)。
    /// transparent=true:  添加 WS_EX_TRANSPARENT -> 鼠标穿透到桌面
    /// transparent=false: 移除 WS_EX_TRANSPARENT -> 窗口接收鼠标事件
    /// </summary>
    public void SetClickThrough(bool transparent)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (hwnd == IntPtr.Zero)
            return;

        int style = GetWindowLong(hwnd, GWL_EXSTYLE);
        if (transparent)
            style |= WS_EX_TRANSPARENT;
        else
            style &= ~WS_EX_TRANSPARENT;
        SetWindowLong(hwnd, GWL_EXSTYLE, style);
        ApplyFrameChanged(hwnd);
    }

    private static void ApplyFrameChanged(IntPtr hwnd)
    {
        SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }

    // ══════════════════════════════════════════════════════════════
    //  屏幕捕捉 (GDI BitBlt)
    //  ── 截取桌面画面并降采样, 供全息屏实时显示 ──
    // ══════════════════════════════════════════════════════════════

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight,
        IntPtr hdcSrc, int nXSrc, int nYSrc, uint dwRop);

    [DllImport("gdi32.dll")]
    private static extern int SetStretchBltMode(IntPtr hdc, int iStretchMode);

    [DllImport("gdi32.dll")]
    private static extern bool StretchBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
        IntPtr hdcSrc, int xSrc, int ySrc, int wSrc, int hSrc, uint dwRop);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr hdc, IntPtr hbmp, uint uStartScan, uint cScanLines,
        byte[] lpvBits, ref BITMAPINFO lpbi, uint uUsage);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    private const int SM_CXSCREEN = 0;
    private const int SM_CYSCREEN = 1;
    private const uint SRCCOPY = 0x00CC0020;
    private const int COLORONCOLOR = 3;  // StretchBlt 最近邻采样 (极快, 全息屏不需要插值)
    private const int DIB_RGB_COLORS = 0;
    private const int BI_RGB = 0;

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public short biPlanes;
        public short biBitCount;
        public int biCompression;
        public int biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public int biClrUsed;
        public int biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        // RGBQUAD[1] 占位, 这里不需要调色板
    }
    // ── 屏幕捕捉 (后台线程异步模式) ──
    // StartCapture/StopCapture 控制生命周期
    // 后台线程按间隔自动截屏, 主线程通过 GetCaptureFrame 零阻塞取最新帧
    private System.Threading.Thread _capThread = null;
    private volatile bool _capRunning = false;
    private int _capTargetW = 160, _capTargetH = 90;
    private int _capIntervalMs = 166;  // ~6fps
    private readonly object _capLock = new object();
    private byte[] _capFrontBuffer = null;  // 主线程读取的前台缓冲
    private volatile bool _capFrameReady = false;

    /// <summary>
    /// 启动后台屏幕捕捉线程。
    /// width/height: 目标尺寸, intervalMs: 截屏间隔(毫秒)
    /// </summary>
    public void StartCapture(int width = 160, int height = 90, int intervalMs = 166)
    {
        StopCapture();
        _capTargetW = width > 0 ? width : 160;
        _capTargetH = height > 0 ? height : 90;
        _capIntervalMs = intervalMs > 16 ? intervalMs : 16;
        _capRunning = true;
        _capFrameReady = false;
        _capThread = new System.Threading.Thread(_CaptureLoop);
        _capThread.IsBackground = true;
        _capThread.Priority = System.Threading.ThreadPriority.BelowNormal;
        _capThread.Start();
    }

    /// <summary>
    /// 停止后台屏幕捕捉线程。
    /// </summary>
    public void StopCapture()
    {
        _capRunning = false;
        if (_capThread != null)
        {
            _capThread.Join(500);
            _capThread = null;
        }
        _capFrameReady = false;
    }

    /// <summary>
    /// 获取最新已捕捉的帧 (RGBA byte[])。非阻塞, 无新帧时返回 null。
    /// 主线程每帧调用, 开销仅为一次 lock + Array.Copy。
    /// </summary>
    public byte[] GetCaptureFrame()
    {
        if (!_capFrameReady) return null;
        lock (_capLock)
        {
            _capFrameReady = false;
            // 返回前台缓冲的拷贝 (供 GDScript 持有, 不受后台线程覆写影响)
            var copy = new byte[_capFrontBuffer.Length];
            System.Buffer.BlockCopy(_capFrontBuffer, 0, copy, 0, copy.Length);
            return copy;
        }
    }

    /// <summary>
    /// 后台截屏是否运行中。
    /// </summary>
    public bool IsCaptureRunning()
    {
        return _capRunning;
    }

    private void _CaptureLoop()
    {
        int tw = _capTargetW, th = _capTargetH;

        // GDI 资源 (在后台线程创建和使用, 不跨线程)
        IntPtr screenDC = GetDC(IntPtr.Zero);
        IntPtr memDC = CreateCompatibleDC(screenDC);
        IntPtr hBitmap = CreateCompatibleBitmap(screenDC, tw, th);
        IntPtr oldBmp = SelectObject(memDC, hBitmap);
        SetStretchBltMode(memDC, COLORONCOLOR);
        ReleaseDC(IntPtr.Zero, screenDC);

        var bmi = new BITMAPINFO();
        bmi.bmiHeader.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER));
        bmi.bmiHeader.biWidth = tw;
        bmi.bmiHeader.biHeight = -th;
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        byte[] backBuffer = new byte[tw * th * 4];
        int screenW = GetSystemMetrics(SM_CXSCREEN);
        int screenH = GetSystemMetrics(SM_CYSCREEN);

        while (_capRunning)
        {
            // 截屏
            IntPtr srcDC = GetDC(IntPtr.Zero);
            StretchBlt(memDC, 0, 0, tw, th, srcDC, 0, 0, screenW, screenH, SRCCOPY);
            GetDIBits(memDC, hBitmap, 0, (uint)th, backBuffer, ref bmi, DIB_RGB_COLORS);
            ReleaseDC(IntPtr.Zero, srcDC);

            // BGRA → RGBA
            for (int i = 0; i < backBuffer.Length; i += 4)
            {
                byte tmp = backBuffer[i];
                backBuffer[i] = backBuffer[i + 2];
                backBuffer[i + 2] = tmp;
                backBuffer[i + 3] = 255;
            }

            // 交换到前台缓冲
            lock (_capLock)
            {
                if (_capFrontBuffer == null || _capFrontBuffer.Length != backBuffer.Length)
                    _capFrontBuffer = new byte[backBuffer.Length];
                System.Buffer.BlockCopy(backBuffer, 0, _capFrontBuffer, 0, backBuffer.Length);
                _capFrameReady = true;
            }

            System.Threading.Thread.Sleep(_capIntervalMs);
        }

        // 清理 GDI 资源
        SelectObject(memDC, oldBmp);
        DeleteObject(hBitmap);
        DeleteDC(memDC);
    }

    // ══════════════════════════════════════════════════════════════
    //  全局热键 (RegisterHotKey / UnregisterHotKey)
    //  ── 注册系统级热键, 任何时候都能响应 ──
    //  ── 支持冲突探测: 尝试注册→立即释放 ──
    // ══════════════════════════════════════════════════════════════

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int pt_x;
        public int pt_y;
    }

    private const uint WM_HOTKEY = 0x0312;
    private const uint PM_REMOVE = 0x0001;

    // Win32 modifier flags for RegisterHotKey
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;
    private const uint MOD_NOREPEAT = 0x4000;

    // 已注册热键 ID 追踪 (防止重复注册)
    private HashSet<int> _registeredHotKeys = new HashSet<int>();

    /// <summary>
    /// 注册一个全局热键。
    /// modifiers: 修饰键标志 (1=Alt, 2=Ctrl, 4=Shift, 8=Win)
    /// keyCode: 虚拟键码 (Win32 VK_* 值)
    /// hotkeyId: 热键标识 (用于后续轮询和注销)
    /// 返回 true = 注册成功
    /// </summary>
    public bool RegisterGlobalHotKey(int hotkeyId, int modifiers, int keyCode)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        // 先尝试注销 (防止重复注册)
        if (_registeredHotKeys.Contains(hotkeyId))
        {
            UnregisterHotKey(hwnd, hotkeyId);
            _registeredHotKeys.Remove(hotkeyId);
        }
        uint mods = (uint)modifiers | MOD_NOREPEAT;
        bool ok = RegisterHotKey(hwnd, hotkeyId, mods, (uint)keyCode);
        if (ok)
        {
            _registeredHotKeys.Add(hotkeyId);
            GD.Print($"[HotKey] 注册成功: id={hotkeyId}, mods={modifiers}, vk=0x{keyCode:X2}");
        }
        else
        {
            int err = Marshal.GetLastWin32Error();
            GD.Print($"[HotKey] 注册失败: id={hotkeyId}, mods={modifiers}, vk=0x{keyCode:X2}, error={err}");
        }
        return ok;
    }

    /// <summary>
    /// 注销一个已注册的全局热键。
    /// </summary>
    public bool UnregisterGlobalHotKey(int hotkeyId)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        bool ok = UnregisterHotKey(hwnd, hotkeyId);
        _registeredHotKeys.Remove(hotkeyId);
        return ok;
    }

    /// <summary>
    /// 探测一个组合键是否可用 (未被其他程序注册为全局热键)。
    /// 原理: 尝试 RegisterHotKey, 成功则立即 UnregisterHotKey。
    /// 返回 true = 可用, false = 已被占用。
    /// </summary>
    public bool TestHotKeyAvailable(int modifiers, int keyCode)
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        int probeId = 0x7FFF;  // 临时 ID (不会和正式的冲突)
        uint mods = (uint)modifiers | MOD_NOREPEAT;
        bool ok = RegisterHotKey(hwnd, probeId, mods, (uint)keyCode);
        if (ok)
            UnregisterHotKey(hwnd, probeId);
        return ok;
    }

    /// <summary>
    /// 轮询是否有全局热键被按下 (通过 PeekMessage 检查 WM_HOTKEY)。
    /// 返回被按下的热键 ID, 无则返回 -1。
    /// GDScript 端在 _process() 中每帧调用。
    /// </summary>
    public int PollHotKey()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        MSG msg;
        if (PeekMessage(out msg, hwnd, WM_HOTKEY, WM_HOTKEY, PM_REMOVE))
        {
            return (int)msg.wParam;  // wParam = hotkey id
        }
        return -1;
    }

    /// <summary>
    /// 注销所有已注册的全局热键 (退出时调用)。
    /// </summary>
    public void UnregisterAllHotKeys()
    {
        IntPtr hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        foreach (int id in _registeredHotKeys)
        {
            UnregisterHotKey(hwnd, id);
        }
        _registeredHotKeys.Clear();
    }

    public override void _ExitTree()
    {
        UnregisterAllHotKeys();
        StopCapture();
    }
}

