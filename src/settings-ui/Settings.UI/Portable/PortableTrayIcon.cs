// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using WinRT.Interop;
using WinUIEx.Messaging;

namespace Microsoft.PowerToys.Settings.UI.Portable;

/// <summary>Owns one notification icon, including Explorer restart recovery and its native menu.</summary>
internal sealed class PortableTrayIcon : IDisposable
{
    private const uint CallbackMessage = 0x8001;
    private readonly WindowMessageMonitor monitor;
    private readonly Action<int> command;
    private readonly nint menu;
    private readonly uint taskbarCreated;
    private IconData data;

    internal PortableTrayIcon(Window window, string iconPath, string title, string openLabel, Action<int> command, bool folderSelection = false)
    {
        this.command = command;
        data = new IconData
        {
            Size = (uint)Marshal.SizeOf<IconData>(),
            Window = WindowNative.GetWindowHandle(window),
            Id = 1,
            Flags = 1 | 2 | 4,
            Callback = CallbackMessage,
            Icon = LoadImage(0, iconPath, 1, 32, 32, 0x10),
            Tip = title,
            Info = string.Empty,
            InfoTitle = string.Empty,
        };
        if (data.Icon == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Portable-Symbol konnte nicht geladen werden.");
        }

        menu = CreatePopupMenu();
        AppendMenu(menu, 0, 1, openLabel);
        if (folderSelection)
        {
            AppendMenu(menu, 0, 4, "Ordner auswählen");
        }
        AppendMenu(menu, 0, 2, "Einstellungen");
        AppendMenu(menu, 0x800, 0, string.Empty);
        AppendMenu(menu, 0, 3, "Beenden");
        taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        monitor = new WindowMessageMonitor(window);
        monitor.WindowMessageReceived += OnMessage;
        if (!Shell_NotifyIcon(0, ref data))
        {
            Dispose();
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Portable-Tray-Symbol konnte nicht erstellt werden.");
        }
    }

    private void OnMessage(object sender, WindowMessageEventArgs e)
    {
        if (e.Message.MessageId == taskbarCreated)
        {
            Shell_NotifyIcon(0, ref data);
        }
        else if (e.Message.MessageId == CallbackMessage)
        {
            var message = (uint)e.Message.LParam & 0xffff;
            if (message == 0x205 || message == 0x7b)
            {
                GetCursorPos(out var point);
                SetForegroundWindow(data.Window);
                uint selected = TrackPopupMenuEx(menu, 0x100 | 2, point.X, point.Y, data.Window, 0);
                PostMessage(data.Window, 0, 0, 0);
                if (selected != 0)
                {
                    command((int)selected);
                }
            }
            else if (message == 0x203 || message == 0x400 || message == 0x401)
            {
                // Double-click or keyboard activation opens settings.
                command(2);
            }

            e.Handled = true;
        }
    }

    public void Dispose()
    {
        Shell_NotifyIcon(2, ref data);
        monitor.WindowMessageReceived -= OnMessage;
        monitor.Dispose();
        DestroyMenu(menu);
        DestroyIcon(data.Icon);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct IconData
    {
        internal uint Size;
        internal nint Window;
        internal uint Id;
        internal uint Flags;
        internal uint Callback;
        internal nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        internal string Tip;
        internal uint State;
        internal uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        internal string Info;
        internal uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        internal string InfoTitle;
        internal uint InfoFlags;
        internal Guid Guid;
        internal nint BalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        internal int X;
        internal int Y;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Shell_NotifyIcon(uint message, ref IconData data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadImage(nint instance, string name, uint type, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenu(nint menu, uint flags, nuint id, string text);

    [DllImport("user32.dll")]
    private static extern uint TrackPopupMenuEx(nint menu, uint flags, int x, int y, nint window, nint parameters);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, uint message, nuint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string name);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(nint menu);
}
