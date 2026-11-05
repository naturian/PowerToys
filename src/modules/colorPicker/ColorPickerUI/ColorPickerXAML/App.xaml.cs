// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

using ManagedCommon;
using Microsoft.PowerToys.Telemetry;
using Microsoft.UI.Xaml;
using WinUIEx;

namespace ColorPicker
{
    public partial class App : Application, IDisposable
    {
        private readonly string[] _args;
        private Mutex _instanceMutex;
        private EventWaitHandle _portableActivationEvent;
        private int _powerToysRunnerPid;
        private bool _disposed;

        private static IServiceProvider _serviceProvider;

        public static Window Window { get; private set; }

        // ETW diagnostic trace session. Dispose it during process cleanup so buffered
        // diagnostic events are flushed before the process exits.
        public ETWTrace EtwTrace { get; } = new ETWTrace();

        public App(string[] args)
        {
            _args = args ?? Array.Empty<string>();

            InitializeLanguage();

            _serviceProvider = ConfigureServices();

            // Environment.Exit on the runner-exit / terminate / single-instance paths raises no
            // Window.Closed, so the cursor-restore in MouseInfoProvider.DisposeHook never runs.
            // Restore the system cursors on any process exit (idempotent) so an abnormal exit while
            // a pick is active with ChangeCursor enabled does not leave the crosshair as the
            // system-wide cursor — parity with the WPF App.OnExit.
            AppDomain.CurrentDomain.ProcessExit += OnProcessExit;

            InitializeComponent();
            UnhandledException += App_UnhandledException;
        }

        public bool IsRunningDetachedFromPowerToys() => _powerToysRunnerPid == -1;

        private static string InstanceMutexName => PortableMode.IsEnabled
            ? @"Local\PowerToys_ColorPicker_Portable_" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(PortableMode.DataRoot.ToUpperInvariant())))
            : @"Local\PowerToys_ColorPicker_InstanceMutex";

        internal static string PortableActivationEventName => InstanceMutexName + "_Activate";

        public static T GetService<T>()
            where T : class
            => _serviceProvider.GetService(typeof(T)) as T;

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            if (PortableMode.IsEnabled)
            {
                // Keep the event alive before the mutex is claimed, so an early second launch is not lost.
                _portableActivationEvent = new EventWaitHandle(false, EventResetMode.AutoReset, PortableActivationEventName);
            }

            // Allow only one instance of Color Picker.
            // Single-instance guard. The mutex is intentionally released by OS process
            // exit (this is an unpackaged single-process app); no explicit ReleaseMutex.
            _instanceMutex = new Mutex(true, InstanceMutexName, out bool createdNew);
            if (!createdNew)
            {
                _portableActivationEvent?.Set();
                Logger.LogWarning("There is a ColorPicker instance running. Exiting Color Picker");
                _instanceMutex = null;
                Environment.Exit(0);
                return;
            }

            if (!PortableMode.IsEnabled && _args.Length > 0 && int.TryParse(_args[0], out _powerToysRunnerPid))
            {
                Logger.LogInfo($"Color Picker started from the PowerToys Runner. Runner pid={_powerToysRunnerPid}");
                RunnerHelper.WaitForPowerToysRunner(_powerToysRunnerPid, () =>
                {
                    Logger.LogInfo("PowerToys Runner exited. Exiting ColorPicker");
                    GetService<CancellationTokenSource>()?.Cancel();
                    Environment.Exit(0);
                });
            }
            else
            {
                _powerToysRunnerPid = -1;
            }

            // Build the picking overlay first so the DI graph (AppStateHandler etc.) can read
            // App.Window, then resolve the main view model (which wires the named events + input)
            // and host it in the overlay's ColorPickerView. The overlay starts hidden (TransparentWindow)
            // and is shown on the hotkey / ShowColorPicker event.
            var overlay = new ColorPickerOverlayWindow();
            Window = overlay;

            var hwnd = overlay.GetWindowHandle();
            var mainViewModel = GetService<ColorPicker.ViewModelContracts.IMainViewModel>();
            overlay.ColorPickerViewControl.DataContext = mainViewModel;
            mainViewModel.RegisterWindowHandle(hwnd);

            // Make the overlay size to the tooltip and follow the cursor while shown (the
            // IMouseInfoProvider singleton is the same one the MainViewModel reads).
            overlay.InitializeCursorFollow(GetService<ColorPicker.Mouse.IMouseInfoProvider>());

            if (PortableMode.IsEnabled && Array.IndexOf(_args, "--background") < 0)
            {
                overlay.DispatcherQueue.TryEnqueue(() => GetService<ColorPicker.Helpers.AppStateHandler>().StartEditorSession());
            }
        }

        private static void InitializeLanguage()
        {
            try
            {
                string appLanguage = LanguageHelper.LoadLanguage();
                if (!string.IsNullOrEmpty(appLanguage))
                {
                    Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = appLanguage;
                }
            }
            catch (ArgumentException ex)
            {
                Logger.LogError("Language initialization error", ex);
            }
        }

        private static IServiceProvider ConfigureServices()
            => ColorPicker.Foundation.AppServices.Configure();

        private void App_UnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
        {
            Program.HandleFatalException(e.Exception);
        }

        private void OnProcessExit(object sender, EventArgs e)
        {
            // Environment.Exit and normal shutdown both raise ProcessExit; run the deterministic
            // cleanup here since the WinUI Application model never calls Dispose() on the App.
            Mouse.CursorManager.RestoreOriginalCursors();
            Dispose();
        }

        protected virtual void Dispose(bool disposing)
        {
            if (_disposed)
            {
                return;
            }

            if (disposing)
            {
                EtwTrace.Dispose();
                _instanceMutex?.Dispose();
                _instanceMutex = null;
                _portableActivationEvent?.Dispose();
                _portableActivationEvent = null;
            }

            _disposed = true;
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }
    }
}
