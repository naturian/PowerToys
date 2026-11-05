// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

using ManagedCommon;
using Microsoft.UI.Dispatching;
using Microsoft.Windows.AppLifecycle;

namespace AdvancedPaste
{
    public static class Program
    {
        internal static IReadOnlyDictionary<string, EventWaitHandle> PortableEvents { get; private set; } = new Dictionary<string, EventWaitHandle>();

        [STAThread]
        public static int Main(string[] args)
        {
            if (PortableMode.IsEnabled)
            {
                // Validate storage before any logger, settings, or WinUI initialization.
                _ = PortableMode.DataRoot;
                Directory.SetCurrentDirectory(AppContext.BaseDirectory);
                if (args.Contains("--stop", StringComparer.OrdinalIgnoreCase))
                {
                    using var stop = new EventWaitHandle(false, EventResetMode.AutoReset, PortableMode.EventName("StopModule"));
                    stop.Set();
                    return 0;
                }
            }

            Logger.InitializeLogger("\\AdvancedPaste\\Logs");

            // This build prohibits every AI provider, including model preparation helpers.
            if (args.Contains("--check-phi-silica", StringComparer.OrdinalIgnoreCase)
                || args.Contains("--prepare-phi-silica", StringComparer.OrdinalIgnoreCase))
            {
                Console.Out.WriteLine("NotSupported");
                return 2;
            }

            WinRT.ComWrappersSupport.InitializeComWrappers();

            if (PowerToys.GPOWrapper.GPOWrapper.GetConfiguredAdvancedPasteEnabledValue() == PowerToys.GPOWrapper.GpoRuleConfigured.Disabled)
            {
                Logger.LogWarning("Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
                return 1;
            }

            if (PortableMode.IsEnabled)
            {
                return RunPortable(args);
            }

            var instanceKey = AppInstance.FindOrRegisterForKey("PowerToys_AdvancedPaste_Instance");
            if (instanceKey.IsCurrent)
            {
                RunApplication();
            }
            else
            {
                Logger.LogWarning("Another instance of AdvancedPasteUI is running. Exiting.");
            }

            return 0;
        }

        private static int RunPortable(string[] args)
        {
            // Hold events before claiming the instance, retaining requests during WinUI startup.
            var events = new Dictionary<string, EventWaitHandle>();
            using var instanceMutex = new Mutex(false, PortableMode.EventName("AdvancedPaste.Instance"));
            bool ownsMutex = false;
            try
            {
                foreach (string command in new[] { "Show", "StopModule", "SettingsChanged", "PlainText", "Markdown", "Json" })
                {
                    events.Add(command, new EventWaitHandle(false, EventResetMode.AutoReset, PortableMode.EventName(command)));
                }

                try
                {
                    ownsMutex = instanceMutex.WaitOne(0);
                }
                catch (AbandonedMutexException)
                {
                    ownsMutex = true;
                }

                if (!args.Contains("--background", StringComparer.OrdinalIgnoreCase))
                {
                    events["Show"].Set();
                }

                if (ownsMutex)
                {
                    PortableEvents = events;
                    RunApplication();
                }

                return 0;
            }
            finally
            {
                foreach (var handle in events.Values)
                {
                    handle.Dispose();
                }

                if (ownsMutex)
                {
                    PortableEvents = new Dictionary<string, EventWaitHandle>();
                    instanceMutex.ReleaseMutex();
                }
            }
        }

        private static void RunApplication()
        {
            Microsoft.UI.Xaml.Application.Start((p) =>
            {
                var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App();
            });
        }
    }
}
