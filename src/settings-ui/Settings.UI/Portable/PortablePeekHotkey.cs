// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.PowerToys.Settings.UI.Library;
using Microsoft.UI.Xaml;
using WinRT.Interop;
using WinUIEx.Messaging;

namespace Microsoft.PowerToys.Settings.UI.Portable;

/// <summary>Owns the selected portable Peek shortcut without any Explorer registration.</summary>
internal sealed class PortablePeekHotkey : IDisposable
{
    private const int HotkeyId = 0x504b;
    private readonly nint window;
    private readonly WindowMessageMonitor monitor;
    private readonly Action activate;
    private bool registered;

    internal PortablePeekHotkey(Window owner, Action activate)
    {
        window = WindowNative.GetWindowHandle(owner);
        this.activate = activate;
        monitor = new WindowMessageMonitor(owner);
        monitor.WindowMessageReceived += OnMessage;
    }

    internal void Refresh(HotkeySettings shortcut, bool enabled)
    {
        if (registered)
        {
            UnregisterHotKey(window, HotkeyId);
            registered = false;
        }

        if (!enabled || shortcut == null || shortcut.Code <= 0 || shortcut.Code > 255)
        {
            return;
        }

        uint modifiers = 0x4000u | (shortcut.Alt ? 1u : 0u) | (shortcut.Ctrl ? 2u : 0u) |
            (shortcut.Shift ? 4u : 0u) | (shortcut.Win ? 8u : 0u);
        registered = RegisterHotKey(window, HotkeyId, modifiers, (uint)shortcut.Code);
        if (!registered)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Die Peek-Tastenkombination ist bereits belegt. Wählen Sie in den Einstellungen eine andere Tastenkombination.");
        }
    }

    private void OnMessage(object sender, WindowMessageEventArgs args)
    {
        if (args.Message.MessageId == 0x0312 && args.Message.WParam.ToUInt64() == HotkeyId)
        {
            args.Handled = true;
            activate();
        }
    }

    public void Dispose()
    {
        if (registered)
        {
            UnregisterHotKey(window, HotkeyId);
            registered = false;
        }

        monitor.WindowMessageReceived -= OnMessage;
        monitor.Dispose();
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(nint window, int id);
}
