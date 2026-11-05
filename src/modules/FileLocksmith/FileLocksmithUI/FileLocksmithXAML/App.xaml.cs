// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Threading;

using ManagedCommon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using PowerToys.Common;

namespace FileLocksmithUI
{
    /// <summary>
    /// Provides application-specific behavior to supplement the default Application class.
    /// </summary>
    public partial class App : Application
    {
        private readonly bool _portable;
        private readonly string _launchDirectory = string.Empty;
        private EventWaitHandle? _portableStopEvent;
        private RegisteredWaitHandle? _portableStopWait;

        /// <summary>
        /// Gets the portable CLI selection. Null is reserved for an explicit --elevated
        /// relaunch, which reads the same portable folder's native IPC selection.
        /// </summary>
        public static string[]? PortableInputPaths { get; private set; } = Array.Empty<string>();

        /// <summary>
        /// Initializes a new instance of the <see cref="App"/> class.
        /// Initializes the singleton application object.  This is the first line of authored code
        /// executed, and as such is the logical equivalent of main() or WinMain().
        /// </summary>
        public App()
        {
            _portable = PortableMode.IsEnabled;
            if (_portable)
            {
                _ = PortableMode.DataRoot;
                _launchDirectory = Directory.GetCurrentDirectory();
                Directory.SetCurrentDirectory(AppContext.BaseDirectory);
            }

            string appLanguage = LanguageHelper.LoadLanguage();
            if (!string.IsNullOrEmpty(appLanguage))
            {
                Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = appLanguage;
            }

            Logger.InitializeLogger("\\File Locksmith\\FileLocksmithUI\\Logs");

            this.InitializeComponent();

            UnhandledException += App_UnhandledException;
        }

        /// <summary>
        /// Invoked when the application is launched normally by the end user.  Other entry points
        /// will be used such as when the application is launched to open a specific file.
        /// </summary>
        /// <param name="args">Details about the launch request and process.</param>
        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            if (PowerToys.GPOWrapper.GPOWrapper.GetConfiguredFileLocksmithEnabledValue() == PowerToys.GPOWrapper.GpoRuleConfigured.Disabled)
            {
                Logger.LogWarning("Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
                Environment.Exit(0); // Current.Exit won't work until there's a window opened.
                return;
            }

            if (_portable)
            {
                string[] inputs = Environment.GetCommandLineArgs().Skip(1).ToArray();
                if (inputs.Length == 1 && inputs[0] == "--elevated")
                {
                    PortableInputPaths = null;
                }
                else
                {
                    try
                    {
                        PortableInputPaths = PortableFileArguments.Parse(inputs, _launchDirectory);
                    }
                    catch (Exception ex)
                    {
                        Logger.LogError("Invalid portable File Locksmith selection.", ex);
                        Environment.Exit(2);
                        return;
                    }
                }
            }

            bool isElevated = PowerToys.FileLocksmithLib.Interop.NativeMethods.IsProcessElevated();

            if (isElevated)
            {
                if (!PowerToys.FileLocksmithLib.Interop.NativeMethods.SetDebugPrivilege())
                {
                    Logger.LogWarning("Couldn't set debug privileges to see system processes.");
                }
            }

            _window = new MainWindow(isElevated);
            _window.Activate();
            if (_portable)
            {
                var queue = _window.DispatcherQueue;
                _portableStopEvent = new EventWaitHandle(false, EventResetMode.ManualReset, PortableMode.EventName("StopModule"));
                _portableStopEvent.Reset();
                _portableStopWait = ThreadPool.RegisterWaitForSingleObject(_portableStopEvent, (_, _) => queue.TryEnqueue(StopPortable), null, Timeout.Infinite, true);
                _window.Closed += (_, _) => DisposePortableWait();
            }
        }

        private void StopPortable()
        {
            DisposePortableWait();
            try
            {
                _window?.Close();
            }
            finally
            {
                Exit();
            }
        }

        private void DisposePortableWait()
        {
            _portableStopWait?.Unregister(null);
            _portableStopWait = null;
            _portableStopEvent?.Dispose();
            _portableStopEvent = null;
        }

        private void App_UnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
        {
            Logger.LogError("Unhandled exception", e.Exception);
        }

        private Window? _window;
    }
}
