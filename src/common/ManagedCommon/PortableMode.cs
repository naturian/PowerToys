// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Diagnostics;
using System.IO;
using PowerToys.Common;

namespace ManagedCommon
{
    /// <summary>Provides isolated data and controls for portable and installed standalone modules.</summary>
    public static class PortableMode
    {
        /// <summary>Gets whether a module mode marker selects writable isolated storage.</summary>
        public static bool IsEnabled => PortableData.IsEnabled;

        /// <summary>Gets the full PowerToys settings root, validating portable storage before use.</summary>
        public static string DataRoot => PortableData.GetPowerToysDataRoot(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));

        /// <summary>Gets an event name isolated to this module's data directory.</summary>
        public static string EventName(string command) => PortableData.GetScopedEventName(DataRoot, command);

        /// <summary>Opens the settings and tray host shipped in the same portable folder.</summary>
        public static void OpenSettings()
        {
            if (!IsEnabled)
            {
                throw new InvalidOperationException("Portable settings require portable mode.");
            }

            var startInfo = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "PowerToys.Portable.exe"))
            {
                UseShellExecute = false,
                WorkingDirectory = AppContext.BaseDirectory,
            };
            startInfo.ArgumentList.Add("--settings");
            Process.Start(startInfo)?.Dispose();
        }
    }
}
