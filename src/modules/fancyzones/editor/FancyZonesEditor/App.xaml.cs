// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using Common.UI;
using FancyZoneEditor.Telemetry;
using FancyZonesEditor.Utils;
using ManagedCommon;
using Microsoft.PowerToys.Telemetry;

namespace FancyZonesEditor
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application, IDisposable
    {
        // Non-localizable strings
        private const string PowerToysIssuesURL = "https://aka.ms/powerToysReportBug";
        private const string ParsingErrorReportTag = "Settings parsing error";
        private const string ParsingErrorDataTag = "Data: ";

        public MainWindowSettingsModel MainWindowSettings { get; }

        public static FancyZonesEditorIO FancyZonesEditorIO { get; private set; }

        public static Overlay Overlay { get; private set; }

        public static int PowerToysPID { get; set; }

        private ThemeManager _themeManager;
        private Process _portableEngine;

        public static bool DebugMode
        {
            get
            {
                return _debugMode;
            }
        }

        private static bool _debugMode;
        private bool _isDisposed;

        private CancellationTokenSource NativeThreadCTS { get; set; }

        [Conditional("DEBUG")]
        private void DebugModeCheck()
        {
            _debugMode = true;
        }

        public App()
        {
            if (PortableMode.IsEnabled)
            {
                _ = PortableMode.DataRoot;
                Directory.SetCurrentDirectory(AppContext.BaseDirectory);
            }

            PowerToysTelemetry.Log.WriteEvent(new FancyZonesEditorStartEvent() { TimeStamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() });

            var languageTag = LanguageHelper.LoadLanguage();

            if (!string.IsNullOrEmpty(languageTag))
            {
                try
                {
                    System.Threading.Thread.CurrentThread.CurrentUICulture = new CultureInfo(languageTag);
                }
                catch (CultureNotFoundException ex)
                {
                    Logger.LogError("CultureNotFoundException: " + ex.Message);
                }
            }

            Logger.InitializeLogger("\\FancyZones\\Editor\\Logs");

            // DebugModeCheck();
            NativeThreadCTS = new CancellationTokenSource();
            FancyZonesEditorIO = new FancyZonesEditorIO();
            Overlay = new Overlay();
            MainWindowSettings = new MainWindowSettingsModel();

            App_WaitExit();
        }

        private void OnStartup(object sender, StartupEventArgs e)
        {
            if (PowerToys.GPOWrapperProjection.GPOWrapper.GetConfiguredFancyZonesEnabledValue() == PowerToys.GPOWrapperProjection.GpoRuleConfigured.Disabled)
            {
                Logger.LogWarning("Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
                Shutdown(0);
                return;
            }

            AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;

            _themeManager = new ThemeManager(this);

            if (!PortableMode.IsEnabled)
            {
                RunnerHelper.WaitForPowerToysRunner(PowerToysPID, () =>
                {
                    Logger.LogInfo("Runner exited");
                    NativeThreadCTS.Cancel();
                    Application.Current.Dispatcher.Invoke(Application.Current.Shutdown);
                });
            }

            var parseResult = FancyZonesEditorIO.ParseParams();

            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            if (PortableMode.IsEnabled)
            {
                try
                {
                    if (!parseResult.Result || PowerToysPID <= 0)
                    {
                        Shutdown();
                        return;
                    }

                    _portableEngine = Process.GetProcessById(PowerToysPID);
                    var expectedEngine = Path.Combine(AppContext.BaseDirectory, "PowerToys.FancyZones.exe");
                    if (_portableEngine.HasExited || !string.Equals(_portableEngine.MainModule?.FileName, expectedEngine, StringComparison.OrdinalIgnoreCase))
                    {
                        Shutdown();
                        return;
                    }

                    // Keep the verified process handle: reopening by PID races with engine exit.
                    _portableEngine.Exited += (_, _) => Current.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        NativeThreadCTS.Cancel();
                        Current.Shutdown();
                    }));
                    _portableEngine.EnableRaisingEvents = true;
                    if (_portableEngine.HasExited)
                    {
                        Shutdown();
                        return;
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogWarning("Unable to monitor the portable FancyZones engine: " + ex.Message);
                    Shutdown();
                    return;
                }
            }

            parseResult = FancyZonesEditorIO.ParseLayoutTemplates();
            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            parseResult = FancyZonesEditorIO.ParseCustomLayouts();
            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            parseResult = FancyZonesEditorIO.ParseDefaultLayouts();
            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            parseResult = FancyZonesEditorIO.ParseLayoutHotkeys();
            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            parseResult = FancyZonesEditorIO.ParseAppliedLayouts();
            if (!parseResult.Result)
            {
                Logger.LogError(ParsingErrorReportTag + ": " + parseResult.Message + "; " + ParsingErrorDataTag + ": " + parseResult.MalformedData);
                MessageBox.Show(parseResult.Message, FancyZonesEditor.Properties.Resources.Error_Parsing_Data_Title, MessageBoxButton.OK);
            }

            MainWindowSettingsModel settings = ((App)Current).MainWindowSettings;
            settings.UpdateSelectedLayoutModel();

            Overlay.Show();
        }

        private void OnExit(object sender, ExitEventArgs e)
        {
            NativeThreadCTS.Cancel();
            Dispose();

            Logger.LogInfo("FancyZones Editor exited");
        }

        private void App_WaitExit()
        {
            if (PortableMode.IsEnabled)
            {
                return;
            }

            NativeEventWaiter.WaitForEventLoop(
            PowerToys.Interop.Constants.FZEExitEvent(),
            () =>
            {
                Logger.LogInfo("Exit event triggered");
                Application.Current.Shutdown();
            },
            Current.Dispatcher,
            NativeThreadCTS.Token);
        }

        public void App_KeyUp(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == System.Windows.Input.Key.LeftShift || e.Key == System.Windows.Input.Key.RightShift)
            {
                MainWindowSettings.IsShiftKeyPressed = false;
            }
        }

        public void App_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == System.Windows.Input.Key.LeftShift || e.Key == System.Windows.Input.Key.RightShift)
            {
                MainWindowSettings.IsShiftKeyPressed = true;
            }
            else if (e.Key == Key.Tab && (Keyboard.IsKeyDown(Key.LeftCtrl) || Keyboard.IsKeyDown(Key.RightCtrl)))
            {
                e.Handled = true;
                App.Overlay.FocusEditor();
            }
        }

        public static void ShowExceptionMessageBox(string message, Exception exception = null)
        {
            string fullMessage = FancyZonesEditor.Properties.Resources.Error_Report + PowerToysIssuesURL + " \n" + message;
            if (exception != null)
            {
                fullMessage += ": " + exception.Message;
            }

            MessageBox.Show(fullMessage, FancyZonesEditor.Properties.Resources.Error_Exception_Message_Box_Title);
        }

        private void OnUnhandledException(object sender, UnhandledExceptionEventArgs args)
        {
            Logger.LogError("Unhandled exception", (Exception)args.ExceptionObject);
            ShowReportMessageBox();
        }

        private static void ShowReportMessageBox()
        {
            MessageBox.Show(
                FancyZonesEditor.Properties.Resources.Crash_Report_Message_Box_Text +
                PowerToysIssuesURL,
                FancyZonesEditor.Properties.Resources.Fancy_Zones_Editor_App_Title);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!_isDisposed)
            {
                if (disposing)
                {
                    _themeManager?.Dispose();
                    _portableEngine?.Dispose();
                }

                _isDisposed = true;
                Logger.LogInfo("FancyZones Editor disposed");
            }
        }

        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }
    }
}
