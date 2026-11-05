// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using ManagedCommon;
using Microsoft.PowerToys.Settings.UI.Helpers;
using Microsoft.PowerToys.Settings.UI.Library;
using Microsoft.PowerToys.Settings.UI.Library.Helpers;
using Microsoft.PowerToys.Settings.UI.Views;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using PowerToys.Common;
using PowerToys.GPOWrapper;
using WinUIEx;
using Windows.Storage.Pickers;

namespace Microsoft.PowerToys.Settings.UI.Portable;

/// <summary>Portable lifecycle and the existing settings-page message contract, scoped to one module.</summary>
internal sealed class PortableSession : IDisposable
{
    private readonly List<EventWaitHandle> events = new();
    private readonly List<RegisteredWaitHandle> waits = new();
    private readonly Dictionary<string, EventWaitHandle> signals = new();
    private readonly SemaphoreSlim lifecycle = new(1, 1);
    private readonly PortableModule module;
    private readonly ModuleType moduleType;
    private Mutex mutex;
    private MainWindow window;
    private PortableTrayIcon tray;
    private PortablePeekHotkey peekHotkey;
    private bool ownsMutex;
    private bool shuttingDown;

    internal PortableSession()
    {
        var identity = new FileInfo(Path.Combine(AppContext.BaseDirectory, "portable-module.json"));
        if (!identity.Exists || identity.Length > 4096 || (identity.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidDataException("Portable-Paketkennung fehlt oder ist ungültig.");
        }

        module = PortableModule.Parse(File.ReadAllText(identity.FullName));
        moduleType = module.Id switch
        {
            "FancyZones" => ModuleType.FancyZones,
            "ColorPicker" => ModuleType.ColorPicker,
            "TextExtractor" => ModuleType.PowerOCR,
            "ImageResizer" => ModuleType.ImageResizer,
            "PowerDisplay" => ModuleType.PowerDisplay,
            "AlwaysOnTop" => ModuleType.AlwaysOnTop,
            "FileLocksmith" => ModuleType.FileLocksmith,
            "Peek" => ModuleType.Peek,
            "CropAndLock" => ModuleType.CropAndLock,
            "AdvancedPaste" => ModuleType.AdvancedPaste,
            _ => throw new InvalidDataException(),
        };
    }

    internal string Name => module.Name;

    internal string OpenLabel => module.OpenLabel;

    internal bool UsesModuleTray => module.Id == "PowerDisplay";

    internal bool RequiresFileSelection => module.Id is "FileLocksmith" or "Peek";

    private bool RunsInBackground => module.Id is "FancyZones" or "ColorPicker" or "TextExtractor" or "AlwaysOnTop" or "CropAndLock" or "AdvancedPaste";

    internal bool Exiting { get; private set; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int MessageBox(nint window, string text, string caption, uint type);

    internal Type PageType => module.Id switch
    {
        "FancyZones" => typeof(FancyZonesPage),
        "ColorPicker" => typeof(ColorPickerPage),
        "TextExtractor" => typeof(PowerOcrPage),
        "ImageResizer" => typeof(ImageResizerPage),
        "PowerDisplay" => typeof(PowerDisplayPage),
        "AlwaysOnTop" => typeof(AlwaysOnTopPage),
        "FileLocksmith" => typeof(FileLocksmithPage),
        "Peek" => typeof(PeekPage),
        "CropAndLock" => typeof(CropAndLockPage),
        "AdvancedPaste" => typeof(AdvancedPastePage),
        _ => throw new InvalidDataException(),
    };

    internal bool TryAcquire(string[] arguments)
    {
        string command = arguments.Contains("--stop", StringComparer.Ordinal) ? "StopHost" :
            arguments.Contains("--open", StringComparer.Ordinal) ? "Open" : "Settings";
        // Create events before claiming the mutex so a second launch cannot lose its request.
        foreach (string name in new[] { "Settings", "Open", "StopHost" })
        {
            events.Add(new EventWaitHandle(false, EventResetMode.AutoReset, PortableMode.EventName(name)));
        }

        mutex = new Mutex(true, PortableMode.EventName("Host"), out ownsMutex);
        if (!ownsMutex)
        {
            events[command == "Settings" ? 0 : command == "Open" ? 1 : 2].Set();
            return false;
        }

        return command != "StopHost";
    }

    internal void Attach(MainWindow settingsWindow)
    {
        window = settingsWindow;
        var queue = window.DispatcherQueue;
        Action[] commands = { ShowSettings, OpenModule, () => _ = ShutdownAsync() };
        for (int index = 0; index < events.Count; index++)
        {
            var action = commands[index];
            waits.Add(ThreadPool.RegisterWaitForSingleObject(events[index], (_, _) => queue.TryEnqueue(() => action()), null, Timeout.Infinite, false));
        }

        if (!UsesModuleTray)
        {
            tray = new PortableTrayIcon(window, Path.Combine(AppContext.BaseDirectory, "portable.ico"), Name + " Portable", OpenLabel, id =>
            {
                if (id == 4)
                {
                    OpenFolder();
                }
                else
                {
                    commands[id == 1 ? 1 : id == 2 ? 0 : 2]();
                }
            }, RequiresFileSelection);
        }

        ShowSettings();
        if (module.Id == "Peek")
        {
            peekHotkey = new PortablePeekHotkey(window, () =>
            {
                if (IsEnabled())
                {
                    RunModule(false, new[] { "--selection" });
                }
            });
            RefreshPeekHotkey();
        }

        if (RunsInBackground && IsEnabled())
        {
            RunModule(true);
        }
    }

    internal void ShowSettings()
    {
        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.AppWindow.Show();
        window.Activate();
        WindowHelpers.BringToForeground(window.GetWindowHandle());
    }

    private GpoRuleConfigured Policy => module.Id switch
    {
        "FancyZones" => GPOWrapper.GetConfiguredFancyZonesEnabledValue(),
        "ColorPicker" => GPOWrapper.GetConfiguredColorPickerEnabledValue(),
        "TextExtractor" => GPOWrapper.GetConfiguredTextExtractorEnabledValue(),
        "ImageResizer" => GPOWrapper.GetConfiguredImageResizerEnabledValue(),
        "PowerDisplay" => GPOWrapper.GetConfiguredPowerDisplayEnabledValue(),
        "AlwaysOnTop" => GPOWrapper.GetConfiguredAlwaysOnTopEnabledValue(),
        "FileLocksmith" => GPOWrapper.GetConfiguredFileLocksmithEnabledValue(),
        "Peek" => GPOWrapper.GetConfiguredPeekEnabledValue(),
        "CropAndLock" => GPOWrapper.GetConfiguredCropAndLockEnabledValue(),
        "AdvancedPaste" => GPOWrapper.GetConfiguredAdvancedPasteEnabledValue(),
        _ => GpoRuleConfigured.Disabled,
    };

    private bool IsEnabled()
    {
        var policy = Policy;
        return policy == GpoRuleConfigured.Enabled || (policy != GpoRuleConfigured.Disabled &&
            ModuleHelper.GetIsModuleEnabled(SettingsRepository<GeneralSettings>.GetInstance(SettingsUtils.Default).SettingsConfig, moduleType));
    }

    internal async void OpenModule()
    {
        try
        {
            if (!IsEnabled() || module.Id == "AlwaysOnTop")
            {
                ShowSettings();
            }
            else if (RequiresFileSelection)
            {
                await PickAndOpenAsync(false);
            }
            else if (module.Id == "CropAndLock")
            {
                RunModule(false, new[] { "--thumbnail" });
            }
            else
            {
                RunModule(false);
            }
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
    }

    internal async void OpenFolder()
    {
        try
        {
            if (RequiresFileSelection && IsEnabled())
            {
                await PickAndOpenAsync(true);
            }
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
    }

    private async Task PickAndOpenAsync(bool folder)
    {
        ShowSettings();
        if (folder)
        {
            var picker = new FolderPicker();
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, window.GetWindowHandle());
            var selected = await picker.PickSingleFolderAsync();
            if (selected != null)
            {
                RunModule(false, new[] { selected.Path });
            }
        }
        else
        {
            var picker = new FileOpenPicker();
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, window.GetWindowHandle());
            var selected = await picker.PickMultipleFilesAsync();
            if (selected.Count > 0)
            {
                RunModule(false, selected.Select(file => file.Path).ToArray());
            }
        }
    }

    private void RunModule(bool background, string[] arguments = null)
    {
        try
        {
            if (shuttingDown || Exiting)
            {
                return;
            }

            if (background && HasRunningModule())
            {
                return;
            }

            var start = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, module.Executable))
            {
                UseShellExecute = false,
                WorkingDirectory = AppContext.BaseDirectory,
            };
            if (background)
            {
                start.ArgumentList.Add("--background");
            }

            if (arguments != null)
            {
                foreach (string argument in arguments)
                {
                    start.ArgumentList.Add(argument);
                }
            }

            if (RequiresFileSelection && signals.TryGetValue("StopModule", out var previousStop))
            {
                previousStop.Reset();
            }

            Process.Start(start)?.Dispose();
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
    }

    private bool HasRunningModule()
    {
        bool found = false;
        string[] executables = module.Id == "FancyZones" ? new[] { module.Executable, "PowerToys.FancyZonesEditor.exe" } : new[] { module.Executable };
        foreach (string executable in executables)
        {
            string expected = Path.Combine(AppContext.BaseDirectory, executable);
            foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))
            {
                using (process)
                {
                    try
                    {
                        found |= string.Equals(process.MainModule?.FileName, expected, StringComparison.OrdinalIgnoreCase);
                    }
                    catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
                    {
                        // An unrelated elevated instance is not ours to control.
                    }
                }
            }
        }

        return found;
    }

    internal void ReceiveSettingsMessage(string message)
    {
        // Some existing view models send from a debounce timer rather than the UI thread.
        window.DispatcherQueue.TryEnqueue(() => ApplySettingsMessage(message));
    }

    private void ApplySettingsMessage(string message)
    {
        try
        {
            using var document = JsonDocument.Parse(message);
            var root = document.RootElement;
            if (root.TryGetProperty("powertoys", out var modules) && modules.TryGetProperty(module.SettingsName, out var settings))
            {
                SettingsUtils.Default.SaveSettingsOrThrow(settings.GetRawText(), module.SettingsName);
                Signal("SettingsChanged");
                RefreshPeekHotkey();
            }
            else if (root.TryGetProperty("general", out var general))
            {
                if (general.TryGetProperty("enabled", out var enabled) && enabled.TryGetProperty(module.SettingsName, out var value))
                {
                    var config = SettingsRepository<GeneralSettings>.GetInstance(SettingsUtils.Default).SettingsConfig;
                    ModuleHelper.SetIsModuleEnabled(config, moduleType, value.GetBoolean());
                    SettingsUtils.Default.SaveSettingsOrThrow(config.ToJsonString());
                    _ = ReconcileEnabledStateAsync();
                }
            }
            else if (root.TryGetProperty("action", out var actions) && actions.TryGetProperty(module.SettingsName, out var action))
            {
                string actionName = action.GetProperty("action_name").GetString();
                if ((module.Id == "FancyZones" && actionName == "ToggledFZEditor") || (module.Id == "PowerDisplay" && actionName == "Launch"))
                {
                    OpenModule();
                }
                else if (module.Id == "PowerDisplay" && actionName == "ApplyProfile")
                {
                    if (int.TryParse(action.GetProperty("value").GetString(), out int profileId) && profileId > 0 && IsEnabled())
                    {
                        // Use the portable-only event; never the installed Runner's pipe.
                        File.WriteAllText(Path.Combine(PortableMode.DataRoot, "PowerDisplay", "portable-profile.txt"), profileId.ToString(System.Globalization.CultureInfo.InvariantCulture));
                        RunModule(true);
                        Signal("ApplyProfile");
                    }
                }
            }
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
    }

    private void Signal(string command)
    {
        if (!signals.TryGetValue(command, out var signal))
        {
            var resetMode = RequiresFileSelection && command == "StopModule" ? EventResetMode.ManualReset : EventResetMode.AutoReset;
            signal = new EventWaitHandle(false, resetMode, PortableMode.EventName(command));
            signals.Add(command, signal);
        }

        signal.Set();
    }

    private void StopModule()
    {
        if (!HasRunningModule())
        {
            return;
        }

        if (module.Id is "FancyZones" or "AlwaysOnTop" or "CropAndLock")
        {
            var start = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, module.Executable)) { UseShellExecute = false, WorkingDirectory = AppContext.BaseDirectory };
            start.ArgumentList.Add("--stop");
            Process.Start(start)?.Dispose();
        }
        else if (module.Id != "ImageResizer")
        {
            Signal("StopModule");
        }
    }

    private void RefreshPeekHotkey()
    {
        if (peekHotkey != null)
        {
            try
            {
                var settings = SettingsUtils.Default.GetSettingsOrDefault<PeekSettings>(PeekSettings.ModuleName);
                peekHotkey.Refresh(settings.Properties.ActivationShortcut, IsEnabled());
            }
            catch (Exception ex)
            {
                ReportError(ex);
            }
        }
    }

    private async Task ReconcileEnabledStateAsync()
    {
        await lifecycle.WaitAsync();
        try
        {
            if (Exiting || shuttingDown)
            {
                return;
            }

            RefreshPeekHotkey();

            if (IsEnabled())
            {
                if (RunsInBackground)
                {
                    RunModule(true);
                }
            }
            else
            {
                StopModule();
                for (int attempt = 0; attempt < 30 && HasRunningModule(); attempt++)
                {
                    await Task.Delay(100);
                    if (attempt % 5 == 4 && ((module.Id is "FancyZones" or "AlwaysOnTop" or "CropAndLock") || RequiresFileSelection))
                    {
                        StopModule();
                    }
                }
            }
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
        finally
        {
            lifecycle.Release();
        }
    }

    internal async Task ShutdownAsync()
    {
        if (shuttingDown)
        {
            return;
        }

        shuttingDown = true;
        await lifecycle.WaitAsync();
        try
        {
            StopModule();
            for (int attempt = 0; attempt < 100 && HasRunningModule(); attempt++)
            {
                await Task.Delay(100);
                if (attempt % 5 == 4 && ((module.Id is "FancyZones" or "AlwaysOnTop" or "CropAndLock") || RequiresFileSelection))
                {
                    StopModule();
                }
            }

            if (HasRunningModule())
            {
                await ShowErrorAsync("Das Werkzeug ist noch geöffnet. Bitte zuerst dessen Fenster bzw. laufende Bildverarbeitung schließen und dann erneut beenden.");
                return;
            }

            Exiting = true;
            Dispose();
            window.Close();
            Microsoft.UI.Xaml.Application.Current.Exit();
        }
        catch (Exception ex)
        {
            ReportError(ex);
        }
        finally
        {
            lifecycle.Release();
            shuttingDown = false;
        }
    }

    private void ReportError(Exception exception)
    {
        Logger.LogError("Portable operation failed", exception);
        _ = ShowErrorAsync(exception.Message);
    }

    private async Task ShowErrorAsync(string message)
    {
        ShowSettings();
        await new ContentDialog
        {
            Title = Name + " Portable",
            Content = message,
            CloseButtonText = "Schließen",
            XamlRoot = window.Content.XamlRoot,
        }.ShowAsync();
    }

    public void Dispose()
    {
        peekHotkey?.Dispose();
        peekHotkey = null;
        tray?.Dispose();
        tray = null;
        foreach (var wait in waits)
        {
            wait.Unregister(null);
        }

        waits.Clear();
        foreach (var handle in events)
        {
            handle.Dispose();
        }

        events.Clear();
        foreach (var signal in signals.Values)
        {
            signal.Dispose();
        }

        signals.Clear();
        if (ownsMutex)
        {
            mutex.ReleaseMutex();
            ownsMutex = false;
        }

        mutex?.Dispose();
        mutex = null;
    }
}
