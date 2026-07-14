using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace AtG.TestHarness;

public sealed class Win32WindowDriver : IWindowDriver
{
    private readonly string _processName;
    private readonly int? _processId;
    private IntPtr _window;

    public Win32WindowDriver(string processName = "At The Gates", int? processId = null)
    {
        _processName = processName;
        _processId = processId;
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        SetProcessDPIAware();
        ResolveWindow(TimeSpan.FromSeconds(1));
    }

    public int ClientWidth { get; private set; }
    public int ClientHeight { get; private set; }

    public void Move(int referenceX, int referenceY)
    {
        var point = ToScreen(referenceX, referenceY);
        if (!SetCursorPos(point.X, point.Y))
            throw new InvalidOperationException("SetCursorPos failed.");
    }

    public void Click(int referenceX, int referenceY)
    {
        const uint positionFlags = SetWindowPosNoMove | SetWindowPosNoSize | SetWindowPosShowWindow;
        var window = ResolveWindow();
        ShowWindow(window, ShowWindowRestore);
        SetWindowPos(window, WindowTopMost, 0, 0, 0, 0, positionFlags);
        SetForegroundWindow(window);
        Thread.Sleep(100);
        Move(referenceX, referenceY);
        Thread.Sleep(40);
        mouse_event(MouseEventMove, 1, 1, 0, UIntPtr.Zero);
        Thread.Sleep(20);
        mouse_event(MouseEventMove, unchecked((uint)-1), unchecked((uint)-1), 0, UIntPtr.Zero);
        Thread.Sleep(20);
        mouse_event(MouseEventLeftDown, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(80);
        mouse_event(MouseEventLeftUp, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
        SetWindowPos(window, WindowNotTopMost, 0, 0, 0, 0, positionFlags);
    }

    public void KeyPress(string key)
    {
        var virtualKey = key.ToUpperInvariant() switch
        {
            "ESC" or "ESCAPE" => (byte)0x1B,
            "ENTER" or "RETURN" => (byte)0x0D,
            "SPACE" or "SPACEBAR" => (byte)0x20,
            "TAB" => (byte)0x09,
            "F1" => (byte)0x70,
            "F10" => (byte)0x79,
            "F11" => (byte)0x7A,
            "F12" => (byte)0x7B,
            _ => throw new ArgumentException($"Unsupported key '{key}'.", nameof(key)),
        };
        SetForegroundWindow(ResolveWindow());
        keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
        Thread.Sleep(80);
        keybd_event(virtualKey, 0, KeyEventKeyUp, UIntPtr.Zero);
    }

    public string ReadFingerprint(CropRegion? referenceRegion)
    {
        using var bitmap = CaptureBitmap(referenceRegion);
        var rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var length = Math.Abs(data.Stride) * data.Height;
            var bytes = new byte[length];
            Marshal.Copy(data.Scan0, bytes, 0, length);
            return Convert.ToHexString(SHA256.HashData(bytes));
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    public void Capture(string outputPath, CropRegion? referenceRegion, bool markCursor)
    {
        using var bitmap = CaptureBitmap(referenceRegion);
        if (markCursor)
        {
            var cursor = Cursor.Position;
            var clientOrigin = ClientOrigin();
            var region = ScaleRegion(referenceRegion) ?? new CropRegion(0, 0, ClientWidth, ClientHeight);
            var x = cursor.X - clientOrigin.X - region.X;
            var y = cursor.Y - clientOrigin.Y - region.Y;
            if (x >= 0 && y >= 0 && x < bitmap.Width && y < bitmap.Height)
            {
                using var graphics = Graphics.FromImage(bitmap);
                using var pen = new Pen(Color.Magenta, 2);
                graphics.DrawEllipse(pen, x - 7, y - 7, 14, 14);
                graphics.DrawLine(pen, x - 10, y, x + 10, y);
                graphics.DrawLine(pen, x, y - 10, x, y + 10);
            }
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        bitmap.Save(outputPath, ImageFormat.Png);
    }

    public void Dispose() { }

    private static IntPtr FindWindow(IReadOnlyCollection<Process> processes)
    {
        var processIds = new HashSet<int>(processes.Select(process => process.Id));
        var candidates = new List<(IntPtr Handle, long Area, string Title)>();
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle)) return true;
            GetWindowThreadProcessId(handle, out var processId);
            if (!processIds.Contains(processId) || !GetWindowRect(handle, out var windowRect)) return true;
            var width = windowRect.Right - windowRect.Left;
            var height = windowRect.Bottom - windowRect.Top;
            if (width < 200 || height < 200) return true;
            var length = GetWindowTextLength(handle);
            var title = new StringBuilder(Math.Max(256, length + 1));
            GetWindowText(handle, title, title.Capacity);
            candidates.Add((handle, (long)width * height, title.ToString()));
            return true;
        }, IntPtr.Zero);

        var enumerated = candidates
            .OrderBy(candidate => candidate.Title.Contains("At the Gates", StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenByDescending(candidate => candidate.Area)
            .Select(candidate => candidate.Handle)
            .FirstOrDefault();
        if (enumerated != IntPtr.Zero) return enumerated;
        return processes.Select(process => process.MainWindowHandle)
            .FirstOrDefault(handle => handle != IntPtr.Zero);
    }

    private Bitmap CaptureBitmap(CropRegion? referenceRegion)
    {
        var origin = ClientOrigin();
        var region = ScaleRegion(referenceRegion) ?? new CropRegion(0, 0, ClientWidth, ClientHeight);
        var bitmap = new Bitmap(region.Width, region.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(origin.X + region.X, origin.Y + region.Y, 0, 0,
            new Size(region.Width, region.Height), CopyPixelOperation.SourceCopy);
        return bitmap;
    }

    private CropRegion? ScaleRegion(CropRegion? region)
    {
        if (region is null) return null;
        var topLeft = CoordinateTransform.Scale(region.X, region.Y, ClientWidth, ClientHeight);
        var bottomRight = CoordinateTransform.Scale(region.X + region.Width, region.Y + region.Height,
            ClientWidth, ClientHeight);
        var left = Math.Clamp(topLeft.X, 0, ClientWidth - 1);
        var top = Math.Clamp(topLeft.Y, 0, ClientHeight - 1);
        var right = Math.Clamp(bottomRight.X, left + 1, ClientWidth);
        var bottom = Math.Clamp(bottomRight.Y, top + 1, ClientHeight);
        return new CropRegion(left, top, right - left, bottom - top);
    }

    private Point ToScreen(int referenceX, int referenceY)
    {
        var window = ResolveWindow();
        var scaled = CoordinateTransform.Scale(referenceX, referenceY, ClientWidth, ClientHeight);
        var point = new NativePoint { X = scaled.X, Y = scaled.Y };
        if (!ClientToScreen(window, ref point))
        {
            _window = IntPtr.Zero;
            window = ResolveWindow();
            scaled = CoordinateTransform.Scale(referenceX, referenceY, ClientWidth, ClientHeight);
            point = new NativePoint { X = scaled.X, Y = scaled.Y };
            if (!ClientToScreen(window, ref point))
                throw new InvalidOperationException("ClientToScreen failed after window recovery.");
        }
        return new Point(point.X, point.Y);
    }

    private Point ClientOrigin()
    {
        var point = new NativePoint();
        if (!ClientToScreen(ResolveWindow(), ref point))
        {
            _window = IntPtr.Zero;
            point = new NativePoint();
            if (!ClientToScreen(ResolveWindow(), ref point))
                throw new InvalidOperationException("ClientToScreen failed after window recovery.");
        }
        return new Point(point.X, point.Y);
    }

    private IntPtr ResolveWindow(TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(5));
        do
        {
            try
            {
                _window = WindowHandleRecovery.Select(
                    _window, IsUsableWindow, FindCurrentWindow);
                if (GetClientRect(_window, out var rect))
                {
                    ClientWidth = rect.Right - rect.Left;
                    ClientHeight = rect.Bottom - rect.Top;
                    if (ClientWidth > 0 && ClientHeight > 0) return _window;
                }
            }
            catch (InvalidOperationException)
            {
                _window = IntPtr.Zero;
            }
            Thread.Sleep(100);
        }
        while (DateTime.UtcNow < deadline);
        throw new InvalidOperationException(
            $"No visible window found for process '{_processName}' after window recovery.");
    }

    private bool IsUsableWindow(IntPtr window) =>
        window != IntPtr.Zero && IsWindow(window) && GetClientRect(window, out var rect) &&
        rect.Right > rect.Left && rect.Bottom > rect.Top;

    private IntPtr FindCurrentWindow()
    {
        var processes = Process.GetProcessesByName(_processName)
            .Where(process => _processId is null || process.Id == _processId.Value)
            .ToArray();
        try { return FindWindow(processes); }
        finally { foreach (var process in processes) process.Dispose(); }
    }

    private const uint MouseEventMove = 0x0001;
    private const uint MouseEventLeftDown = 0x0002;
    private const uint MouseEventLeftUp = 0x0004;
    private const uint KeyEventKeyUp = 0x0002;
    private const int ShowWindowRestore = 9;
    private const uint SetWindowPosNoSize = 0x0001;
    private const uint SetWindowPosNoMove = 0x0002;
    private const uint SetWindowPosShowWindow = 0x0040;
    private static readonly IntPtr WindowTopMost = new(-1);
    private static readonly IntPtr WindowNotTopMost = new(-2);

    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left; public int Top; public int Right; public int Bottom; }
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximumCount);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int processId);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hWnd, ref NativePoint point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")] private static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);
}
