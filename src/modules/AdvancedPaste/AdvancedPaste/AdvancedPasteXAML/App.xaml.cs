// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using AdvancedPaste.Helpers;
using AdvancedPaste.Models;
using AdvancedPaste.Services;
using AdvancedPaste.Settings;
using AdvancedPaste.ViewModels;
using ManagedCommon;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.PowerToys.Settings.UI.Library;
using Microsoft.PowerToys.Telemetry;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using WinUIEx;
using WinUIEx.Messaging;

using static AdvancedPaste.Helpers.NativeMethods;

using DispatcherQueue = Microsoft.UI.Dispatching.DispatcherQueue;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.
namespace AdvancedPaste
{
    /// <summary>
    /// Provides application-specific behavior to supplement the default Application class.
    /// </summary>
    public partial class App : Application, IDisposable
    {
        public IHost Host { get; private set; }

        public ETWTrace EtwTrace { get; private set; } = new ETWTrace();

        private static readonly Dictionary<string, PasteFormats> AdditionalActionIPCKeys =
                 typeof(PasteFormats).GetFields()
                                     .Where(field => field.IsLiteral)
                                     .Select(field => (Format: (PasteFormats)field.GetRawConstantValue(), field.GetCustomAttribute<PasteFormatMetadataAttribute>().IPCKey))
                                     .Where(field => field.IPCKey != null)
                                     .ToDictionary(field => field.IPCKey, field => field.Format);

        private readonly DispatcherQueue _dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        private readonly OptionsViewModel viewModel;

        private MainWindow window;

        private nint windowHwnd;

        private bool disposedValue;

        private readonly List<RegisteredWaitHandle> portableWaits = [];
        private readonly Dictionary<int, Func<Task>> portableHotkeys = [];
        private WindowEx portableLifetimeWindow;
        private WindowMessageMonitor portableMessageMonitor;
        private IUserSettings portableUserSettings;
        private HotkeySettingsControlHook portableWinShiftVHook;
        private bool portableWinShiftVDown;
        private int nextPortableHotkeyId = 0x2000;
        private bool portableStopping;

        /// <summary>
        /// Initializes a new instance of the <see cref="App"/> class.
        /// Initializes the singleton application object.  This is the first line of authored code
        /// executed, and as such is the logical equivalent of main() or WinMain().
        /// </summary>
        public App()
        {
            string appLanguage = LanguageHelper.LoadLanguage();
            if (!string.IsNullOrEmpty(appLanguage))
            {
                Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = appLanguage;
            }

            InitializeComponent();

            Host = Microsoft.Extensions.Hosting.Host.CreateDefaultBuilder().UseContentRoot(AppContext.BaseDirectory).ConfigureServices((context, services) =>
            {
                services.AddAdvancedPasteEngine();
                services.AddSingleton<OptionsViewModel>();
            }).Build();

            viewModel = GetService<OptionsViewModel>();

            UnhandledException += App_UnhandledException;
        }

        public MainWindow GetMainWindow()
        {
            return window;
        }

        public static T GetService<T>()
            where T : class
        {
            if ((App.Current as App)!.Host.Services.GetService(typeof(T)) is not T service)
            {
                throw new ArgumentException($"{typeof(T)} needs to be registered in ConfigureServices within App.xaml.cs.");
            }

            return service;
        }

        /// <summary>
        /// Invoked when the application is launched.
        /// </summary>
        /// <param name="args">Details about the launch request and process.</param>
        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            if (PortableMode.IsEnabled)
            {
                InitializePortable();
                return;
            }

            var cmdArgs = Environment.GetCommandLineArgs();
            if (cmdArgs?.Length > 1)
            {
                if (int.TryParse(cmdArgs[1], out int powerToysRunnerPid))
                {
                    RunnerHelper.WaitForPowerToysRunner(powerToysRunnerPid, () =>
                    {
                        _dispatcherQueue.TryEnqueue(() =>
                        {
                            Dispose();
                            Environment.Exit(0);
                        });
                    });
                }
            }

            if (cmdArgs?.Length > 2)
            {
                ProcessNamedPipe(cmdArgs[2]);
            }
        }

        private void InitializePortable()
        {
            // A hidden window owns WM_HOTKEY and keeps background launches resident.
            portableLifetimeWindow = new WindowEx();
            portableLifetimeWindow.AppWindow.Hide();
            portableMessageMonitor = new WindowMessageMonitor(portableLifetimeWindow);
            portableMessageMonitor.WindowMessageReceived += (_, e) =>
            {
                const uint wmHotkey = 0x0312;
                if (e.Message.MessageId == wmHotkey && portableHotkeys.TryGetValue(unchecked((int)e.Message.WParam), out var action))
                {
                    e.Handled = true;
                    QueuePortableAction(action);
                }
            };

            portableUserSettings = GetService<IUserSettings>();
            portableUserSettings.Changed += OnPortableSettingsChanged;
            RefreshPortableHotkeys();

            foreach (var entry in Program.PortableEvents)
            {
                Func<Task> action = entry.Key switch
                {
                    "Show" => ShowWindow,
                    "StopModule" => StopPortableAsync,
                    "SettingsChanged" => () =>
                    {
                        RefreshPortableHotkeys();
                        return Task.CompletedTask;
                    },
                    "PlainText" => () => ExecutePortablePasteAsync(PasteFormats.PlainText),
                    "Markdown" => () => ExecutePortablePasteAsync(PasteFormats.Markdown),
                    "Json" => () => ExecutePortablePasteAsync(PasteFormats.Json),
                    _ => throw new InvalidOperationException("Unknown portable AdvancedPaste command."),
                };

                portableWaits.Add(ThreadPool.RegisterWaitForSingleObject(
                    entry.Value,
                    (_, _) => QueuePortableAction(action),
                    null,
                    Timeout.Infinite,
                    executeOnlyOnce: false));
            }
        }

        private void QueuePortableAction(Func<Task> action)
        {
            _dispatcherQueue.TryEnqueue(async () =>
            {
                if (disposedValue || portableStopping)
                {
                    return;
                }

                try
                {
                    await action();
                }
                catch (Exception ex)
                {
                    Logger.LogError("Portable AdvancedPaste command failed", ex);
                }
            });
        }

        private void OnPortableSettingsChanged(object sender, EventArgs e)
        {
            QueuePortableAction(() =>
            {
                RefreshPortableHotkeys();
                return Task.CompletedTask;
            });
        }

        private void RefreshPortableHotkeys()
        {
            if (disposedValue || portableStopping)
            {
                return;
            }

            try
            {
                var properties = SettingsUtils.Default.GetSettings<AdvancedPasteSettings>(AdvancedPasteSettings.ModuleName).Properties
                    ?? throw new InvalidOperationException("AdvancedPaste settings have no properties.");

                UnregisterPortableHotkeys();
                RegisterPortableShortcut(properties.AdvancedPasteUIShortcut, ShowWindow);
                RegisterPortableShortcut(properties.PasteAsPlainTextShortcut, () => ExecutePortablePasteAsync(PasteFormats.PlainText));
                RegisterPortableShortcut(properties.PasteAsMarkdownShortcut, () => ExecutePortablePasteAsync(PasteFormats.Markdown));
                RegisterPortableShortcut(properties.PasteAsJsonShortcut, () => ExecutePortablePasteAsync(PasteFormats.Json));

                var additional = properties.AdditionalActions;
                (PasteFormats Format, AdvancedPasteAdditionalAction Action, bool ParentShown)[] actions =
                [
                    (PasteFormats.ImageToText, additional.ImageToText, true),
                    (PasteFormats.PasteAsTxtFile, additional.PasteAsFile.PasteAsTxtFile, additional.PasteAsFile.IsShown),
                    (PasteFormats.PasteAsPngFile, additional.PasteAsFile.PasteAsPngFile, additional.PasteAsFile.IsShown),
                    (PasteFormats.PasteAsHtmlFile, additional.PasteAsFile.PasteAsHtmlFile, additional.PasteAsFile.IsShown),
                    (PasteFormats.TranscodeToMp3, additional.Transcode.TranscodeToMp3, additional.Transcode.IsShown),
                    (PasteFormats.TranscodeToMp4, additional.Transcode.TranscodeToMp4, additional.Transcode.IsShown),
                ];

                // No AI, grammar, coaching, or custom action shortcuts belong to this process.
                foreach (var entry in actions.Where(entry => entry.ParentShown && entry.Action.IsShown && !PasteFormat.MetadataDict[entry.Format].RequiresAIService))
                {
                    RegisterPortableShortcut(entry.Action.Shortcut, () => ExecutePortablePasteAsync(entry.Format));
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to update portable AdvancedPaste hotkeys", ex);
            }
        }

        private void RegisterPortableShortcut(HotkeySettings shortcut, Func<Task> action)
        {
            if (shortcut is null || shortcut.Code <= 0 || shortcut.Code > 0xFF)
            {
                return;
            }

            const uint modNoRepeat = 0x4000;
            uint modifiers = modNoRepeat
                | (shortcut.Alt ? 0x0001u : 0)
                | (shortcut.Ctrl ? 0x0002u : 0)
                | (shortcut.Shift ? 0x0004u : 0)
                | (shortcut.Win ? 0x0008u : 0);
            int id = nextPortableHotkeyId++;
            if (nextPortableHotkeyId > 0xBFFF)
            {
                nextPortableHotkeyId = 0x2000;
            }

            if (RegisterPortableHotKey(portableLifetimeWindow.GetWindowHandle(), id, modifiers, (uint)shortcut.Code))
            {
                portableHotkeys.Add(id, action);
            }
            else
            {
                int error = Marshal.GetLastWin32Error();
                if (!TryRegisterPortableWinShiftV(shortcut, action))
                {
                    Logger.LogWarning($"Failed to register portable AdvancedPaste shortcut {shortcut}: {error}");
                }
            }
        }

        private bool TryRegisterPortableWinShiftV(HotkeySettings shortcut, Func<Task> action)
        {
            if (shortcut.Code != 0x56 || !shortcut.Win || !shortcut.Shift || shortcut.Ctrl || shortcut.Alt || portableWinShiftVHook is not null)
            {
                return false;
            }

            // Windows reserves this shortcut, so use the same keyboard hook as the Runner.
            try
            {
                portableWinShiftVHook = new HotkeySettingsControlHook(
                    _ =>
                    {
                        if (portableWinShiftVDown)
                        {
                            return;
                        }

                        portableWinShiftVDown = true;
                        SendPortableShortcutDummyKey();
                        QueuePortableAction(action);
                    },
                    _ => portableWinShiftVDown = false,
                    () => !disposedValue && !portableStopping,
                    FilterPortableWinShiftV);
                return true;
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to create the portable AdvancedPaste shortcut hook", ex);
                return false;
            }
        }

        private bool FilterPortableWinShiftV(int key, UIntPtr extraInfo, bool isKeyDown)
        {
            if (key != 0x56 || extraInfo == (UIntPtr)0x110)
            {
                return false;
            }

            // Once V is consumed, consume its repeats and matching release even if a
            // modifier is released first. Every other key continues through the hook.
            if (portableWinShiftVDown)
            {
                return true;
            }

            return isKeyDown
                && ((GetAsyncKeyState(0x5B) | GetAsyncKeyState(0x5C)) & 0x8000) != 0
                && (GetAsyncKeyState(0x10) & 0x8000) != 0
                && (GetAsyncKeyState(0x11) & 0x8000) == 0
                && (GetAsyncKeyState(0x12) & 0x8000) == 0;
        }

        private static void SendPortableShortcutDummyKey()
        {
            INPUT[] inputs =
            [
                new()
                {
                    type = INPUTTYPE.INPUT_KEYBOARD,
                    data = new InputUnion
                    {
                        ki = new KEYBDINPUT
                        {
                            wVk = 0xFF,
                            dwFlags = (uint)KeyEventF.KeyUp,
                            dwExtraInfo = (UIntPtr)0x110,
                        },
                    },
                },
            ];
            SendInput(1, inputs, INPUT.Size);
        }

        private void UnregisterPortableHotkeys()
        {
            portableWinShiftVHook?.Dispose();
            portableWinShiftVHook = null;
            portableWinShiftVDown = false;

            if (portableLifetimeWindow is not null)
            {
                foreach (int id in portableHotkeys.Keys)
                {
                    UnregisterPortableHotKey(portableLifetimeWindow.GetWindowHandle(), id);
                }
            }

            portableHotkeys.Clear();
        }

        private async Task ExecutePortablePasteAsync(PasteFormats format)
        {
            var metadata = PasteFormat.MetadataDict[format];
            if (metadata.RequiresAIService)
            {
                return;
            }

            if (!metadata.IsCoreAction)
            {
                await ShowWindow();
            }

            await viewModel.ExecutePasteFormatAsync(format, PasteActionSource.GlobalKeyboardShortcut);
        }

        private async Task StopPortableAsync()
        {
            portableStopping = true;
            UnregisterPortableHotkeys();
            try
            {
                await viewModel.CancelPasteActionAsync();
            }
            finally
            {
                try
                {
                    Dispose();
                }
                finally
                {
                    Exit();
                }
            }
        }

        [LibraryImport("user32.dll", EntryPoint = "RegisterHotKey", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static partial bool RegisterPortableHotKey(nint hwnd, int id, uint modifiers, uint key);

        [LibraryImport("user32.dll", EntryPoint = "UnregisterHotKey", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static partial bool UnregisterPortableHotKey(nint hwnd, int id);

        private void ProcessNamedPipe(string pipeName)
        {
            void OnMessage(string message) => _dispatcherQueue.TryEnqueue(async () => await OnNamedPipeMessage(message));

            Task.Run(async () => await NamedPipeProcessor.ProcessNamedPipeAsync(pipeName, connectTimeout: TimeSpan.FromSeconds(10), OnMessage, CancellationToken.None));
        }

        private async Task OnNamedPipeMessage(string message)
        {
            var messageParts = message.Split();
            var messageType = messageParts.First();

            if (messageType == PowerToys.Interop.Constants.AdvancedPasteShowUIMessage())
            {
                await ShowWindow();
            }
            else if (messageType == PowerToys.Interop.Constants.AdvancedPasteMarkdownMessage())
            {
                await viewModel.ExecutePasteFormatAsync(PasteFormats.Markdown, PasteActionSource.GlobalKeyboardShortcut);
            }
            else if (messageType == PowerToys.Interop.Constants.AdvancedPasteJsonMessage())
            {
                await viewModel.ExecutePasteFormatAsync(PasteFormats.Json, PasteActionSource.GlobalKeyboardShortcut);
            }
            else if (messageType == PowerToys.Interop.Constants.AdvancedPasteAdditionalActionMessage())
            {
                await OnAdvancedPasteAdditionalActionHotkey(messageParts);
            }
            else if (messageType == PowerToys.Interop.Constants.AdvancedPasteCustomActionMessage())
            {
                await OnAdvancedPasteCustomActionHotkey(messageParts);
            }
            else if (messageType == PowerToys.Interop.Constants.AdvancedPasteTerminateAppMessage())
            {
                Dispose();
                Environment.Exit(0);
            }
        }

        private void App_UnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
        {
            Logger.LogError("Unhandled exception", e.Exception);
        }

        private async Task OnAdvancedPasteAdditionalActionHotkey(string[] messageParts)
        {
            if (messageParts.Length != 2)
            {
                Logger.LogWarning("Unexpected additional action message");
            }
            else
            {
                const string coachingSuffix = "-coaching";
                var actionKey = messageParts[1];
                bool forceCoaching = actionKey.EndsWith(coachingSuffix, StringComparison.OrdinalIgnoreCase);

                if (forceCoaching)
                {
                    actionKey = actionKey[..^coachingSuffix.Length];
                }

                if (!AdditionalActionIPCKeys.TryGetValue(actionKey, out PasteFormats pasteFormat))
                {
                    Logger.LogWarning($"Unexpected additional action type {messageParts[1]}");
                }
                else
                {
                    await ShowWindow();
                    await viewModel.ExecutePasteFormatAsync(pasteFormat, PasteActionSource.GlobalKeyboardShortcut, forceCoaching);
                }
            }
        }

        private async Task OnAdvancedPasteCustomActionHotkey(string[] messageParts)
        {
            if (messageParts.Length != 2)
            {
                Logger.LogWarning("Unexpected custom action message");
            }
            else
            {
                if (!int.TryParse(messageParts[1], CultureInfo.InvariantCulture, out int customActionId))
                {
                    Logger.LogWarning($"Unexpected custom action message id {messageParts[1]}");
                }
                else
                {
                    await ShowWindow();
                    await viewModel.ExecuteCustomActionAsync(customActionId, PasteActionSource.GlobalKeyboardShortcut);
                }
            }
        }

        private async Task ShowWindow()
        {
            await viewModel.OnShowAsync();

            if (window is null)
            {
                window = new MainWindow();
                windowHwnd = window.GetWindowHandle();

                MoveWindowToActiveMonitor();

                window.Activate();
            }
            else
            {
                MoveWindowToActiveMonitor();

                Windows.Win32.PInvoke.ShowWindow((Windows.Win32.Foundation.HWND)windowHwnd, Windows.Win32.UI.WindowsAndMessaging.SHOW_WINDOW_CMD.SW_SHOW);
                WindowHelpers.BringToForeground(windowHwnd);
            }

            window.SetFocus();
        }

        private void MoveWindowToActiveMonitor()
        {
            if (GetCursorPos(out PointInter cursorPosition))
            {
                DisplayArea displayArea = DisplayArea.GetFromPoint(new PointInt32(cursorPosition.X, cursorPosition.Y), DisplayAreaFallback.Nearest);

                var x = displayArea.WorkArea.X + (displayArea.WorkArea.Width / 2) - (window.Width / 2);
                var y = displayArea.WorkArea.Y + (displayArea.WorkArea.Height / 2) - (window.Height / 2);

                window.MoveAndResize(x, y, window.Width, window.Height);
            }
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                disposedValue = true;
                if (disposing)
                {
                    if (PortableMode.IsEnabled)
                    {
                        if (portableUserSettings is not null)
                        {
                            portableUserSettings.Changed -= OnPortableSettingsChanged;
                        }

                        foreach (var wait in portableWaits)
                        {
                            wait.Unregister(null);
                        }

                        portableWaits.Clear();
                        UnregisterPortableHotkeys();
                        portableMessageMonitor?.Dispose();
                        portableLifetimeWindow?.Close();
                        Host?.Dispose();
                    }

                    EtwTrace?.Dispose();
                    window?.Dispose();
                }
            }
        }

        public void Dispose()
        {
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }
    }
}
