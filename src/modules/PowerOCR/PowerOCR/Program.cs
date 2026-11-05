// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

using ManagedCommon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace PowerOCR;

internal static class Program
{
    private static string InstanceMutexName => PortableMode.IsEnabled
        ? @"Local\PowerToys_PowerOCR_Portable_" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(PortableMode.DataRoot.ToUpperInvariant())))
        : @"Local\PowerToys_PowerOCR_InstanceMutex";

    internal static string PortableActivationEventName => InstanceMutexName + "_Activate";

    [STAThread]
    public static int Main(string[] args)
    {
        if (PortableMode.IsEnabled)
        {
            // Validate the portable data location before logging or loading WinUI resources.
            _ = PortableMode.DataRoot;
            Directory.SetCurrentDirectory(AppContext.BaseDirectory);
        }

        Logger.InitializeLogger("\\TextExtractor\\Logs");
        WinRT.ComWrappersSupport.InitializeComWrappers();

        if (PowerToys.GPOWrapper.GPOWrapper.GetConfiguredTextExtractorEnabledValue()
            == PowerToys.GPOWrapper.GpoRuleConfigured.Disabled)
        {
            Logger.LogWarning("Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
            return 0;
        }

        using var portableActivationEvent = PortableMode.IsEnabled
            ? new EventWaitHandle(false, EventResetMode.AutoReset, PortableActivationEventName)
            : null;
        using var instanceMutex = new Mutex(
            true,
            InstanceMutexName,
            out bool createdNew);
        if (!createdNew)
        {
            portableActivationEvent?.Set();
            Logger.LogWarning("Another running TextExtractor instance was detected. Exiting TextExtractor");
            return 0;
        }

        int runnerPid = !PortableMode.IsEnabled && args.Length > 0 && int.TryParse(args[0], out int parsedPid) ? parsedPid : -1;

        try
        {
            Application.Start((p) =>
            {
                var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App(runnerPid);
            });
            return 0;
        }
        finally
        {
            instanceMutex.ReleaseMutex();
        }
    }
}
