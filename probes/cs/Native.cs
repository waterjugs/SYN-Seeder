using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;

namespace SynSeeder
{
    /// <summary>Windows calls for finding the game's window and clicking and typing into it.</summary>
    static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

        [StructLayout(LayoutKind.Sequential)]
        struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

        [StructLayout(LayoutKind.Explicit)]
        struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

        [StructLayout(LayoutKind.Sequential)]
        struct INPUT { public uint type; public INPUTUNION u; }

        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize, dwTime; }

        [StructLayout(LayoutKind.Sequential)]
        struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags, uCount, dwTimeout; }

        delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
        const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;
        const uint KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004, KEYEVENTF_SCANCODE = 0x0008;
        const int SW_RESTORE = 9;
        const uint GW_OWNER = 4;
        const uint FLASHW_ALL = 3, FLASHW_TIMERNOFG = 12;
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000, VK_END = 0x23;

        [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hwnd, int command);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hwnd, ref POINT point);
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
        [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
        [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
        [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO info);
        [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern short VkKeyScanExW(char ch, IntPtr layout);
        [DllImport("user32.dll")] static extern uint MapVirtualKeyExW(uint code, uint mapType, IntPtr layout);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);

        // Clicking and typing

        public static void Click(int x, int y)
        {
            SetCursorPos(x, y);
            Thread.Sleep(30);
            Send(Mouse(MOUSEEVENTF_LEFTDOWN));
            Thread.Sleep(40);
            Send(Mouse(MOUSEEVENTF_LEFTUP));
        }

        public static void MoveCursor(int x, int y) => SetCursorPos(x, y);

        /// <summary>Presses a key by its character, e.g. 'm' or '\r' for Enter.</summary>
        public static void Press(char key, int holdMs = 50)
        {
            ushort scan = ScanCode(key);
            Send(Key(scan, KEYEVENTF_SCANCODE));
            Thread.Sleep(holdMs);
            Send(Key(scan, KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP));
        }

        public static void KeyDown(char key) => Send(Key(ScanCode(key), KEYEVENTF_SCANCODE));

        public static void KeyUp(char key) => Send(Key(ScanCode(key), KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP));

        public static void TypeText(string text)
        {
            foreach (char ch in text)
            {
                Send(Key(ch, KEYEVENTF_UNICODE), Key(ch, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
                Thread.Sleep(40);
            }
        }

        static ushort ScanCode(char key)
        {
            IntPtr layout = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), out _));
            uint vk = key == '\r' ? 0x0D : key == '\x1b' ? 0x1B : (uint)(VkKeyScanExW(key, layout) & 0xFF);
            return (ushort)MapVirtualKeyExW(vk, 0, layout);  // MAPVK_VK_TO_VSC
        }

        static INPUT Mouse(uint flags) => new INPUT { type = INPUT_MOUSE, u = new INPUTUNION { mi = new MOUSEINPUT { dwFlags = flags } } };

        static INPUT Key(ushort scan, uint flags) => new INPUT { type = INPUT_KEYBOARD, u = new INPUTUNION { ki = new KEYBDINPUT { wScan = scan, dwFlags = flags } } };

        static void Send(params INPUT[] inputs) => SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));

        // Windows

        /// <summary>The biggest visible top-level window of a process, or zero.</summary>
        public static IntPtr MainWindow(int pid)
        {
            IntPtr best = IntPtr.Zero;
            long bestArea = 0;
            EnumWindows((hwnd, _) =>
            {
                GetWindowThreadProcessId(hwnd, out uint owner);
                if (owner == pid && IsWindowVisible(hwnd) && GetWindow(hwnd, GW_OWNER) == IntPtr.Zero && GetWindowRect(hwnd, out RECT r))
                {
                    long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
                    if (area > bestArea)
                    {
                        best = hwnd;
                        bestArea = area;
                    }
                }
                return true;
            }, IntPtr.Zero);
            return best;
        }

        /// <summary>Where the window draws, in screen pixels.</summary>
        public static Rectangle ClientArea(IntPtr hwnd)
        {
            if (!GetClientRect(hwnd, out RECT r))
                return Rectangle.Empty;
            var origin = new POINT();
            ClientToScreen(hwnd, ref origin);
            return new Rectangle(origin.X, origin.Y, r.Right - r.Left, r.Bottom - r.Top);
        }

        public static bool InFront(IntPtr hwnd) => GetForegroundWindow() == hwnd;

        public static int ForegroundPid()
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out uint pid);
            return (int)pid;
        }

        public static bool BringToFront(IntPtr hwnd)
        {
            if (IsHungAppWindow(hwnd))
                return false;
            if (IsIconic(hwnd))
                ShowWindowAsync(hwnd, SW_RESTORE);  // async: a frozen game can't block us
            for (int i = 0; i < 5 && GetForegroundWindow() != hwnd; i++)
            {
                SetForegroundWindow(hwnd);
                Thread.Sleep(200);
            }
            return GetForegroundWindow() == hwnd;
        }

        public static void Flash(IntPtr hwnd)
        {
            var info = new FLASHWINFO { hwnd = hwnd, dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG, uCount = 3 };
            info.cbSize = (uint)Marshal.SizeOf(info);
            FlashWindowEx(ref info);
        }

        /// <summary>Seconds since the last mouse or keyboard use.</summary>
        public static double IdleSeconds()
        {
            var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO)) };
            if (!GetLastInputInfo(ref info))
                return 0;
            return unchecked((uint)Environment.TickCount - info.dwTime) / 1000.0;
        }

        /// <summary>False while the PC is locked: Windows blocks screenshots and input then.</summary>
        public static bool DesktopUnlocked()
        {
            IntPtr desktop = OpenInputDesktop(0, false, 0x0100);  // DESKTOP_SWITCHDESKTOP
            if (desktop == IntPtr.Zero)
                return false;
            CloseDesktop(desktop);
            return true;
        }
    }
}
