// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using Microsoft.Win32;
using PowerToys.Common;

namespace Microsoft.PowerToys.Telemetry
{
    public static class DataDiagnosticsSettings
    {
        private static readonly string DataDiagnosticsRegistryKey = @"HKEY_CURRENT_USER\Software\Classes\PowerToys\";
        private static readonly string DataDiagnosticsRegistryValueName = @"AllowDataDiagnostics";
        private static readonly string DataDiagnosticsDataDiagnosticsUserActionRegistryValueName = @"DataDiagnosticsUserAction";
        private static readonly string DataDiagnosticsDataDiagnosticsViewDataRegistryValueName = @"DataDiagnosticsViewEnabled";

        public static bool GetEnabledValue()
        {
            if (PortableData.IsEnabled)
            {
                return false;
            }

            object registryValue = null;
            try
            {
                registryValue = Registry.GetValue(DataDiagnosticsRegistryKey, DataDiagnosticsRegistryValueName, 0);

                if (registryValue is not null)
                {
                    return (int)registryValue == 1 ? true : false;
                }
            }
            catch
            {
            }

            return false;
        }

        public static void SetEnabledValue(bool value)
        {
            if (PortableData.IsEnabled)
            {
                return;
            }

            try
            {
                Registry.SetValue(DataDiagnosticsRegistryKey, DataDiagnosticsRegistryValueName, value ? 1 : 0);
            }
            catch (Exception)
            {
            }
        }

        public static bool GetUserActionValue()
        {
            if (PortableData.IsEnabled)
            {
                return false;
            }

            object registryValue = null;
            try
            {
                registryValue = Registry.GetValue(DataDiagnosticsRegistryKey, DataDiagnosticsDataDiagnosticsUserActionRegistryValueName, 0);
            }
            catch
            {
            }

            if (registryValue is not null)
            {
                return (int)registryValue == 1 ? true : false;
            }

            return false;
        }

        public static void SetUserActionValue(bool value)
        {
            if (PortableData.IsEnabled)
            {
                return;
            }

            try
            {
                Registry.SetValue(DataDiagnosticsRegistryKey, DataDiagnosticsDataDiagnosticsUserActionRegistryValueName, value ? 1 : 0);
            }
            catch (Exception)
            {
            }
        }

        public static bool GetViewEnabledValue()
        {
            if (PortableData.IsEnabled)
            {
                return false;
            }

            object registryValue = null;
            try
            {
                registryValue = Registry.GetValue(DataDiagnosticsRegistryKey, DataDiagnosticsDataDiagnosticsViewDataRegistryValueName, 0);
            }
            catch
            {
            }

            if (registryValue is not null)
            {
                return (int)registryValue == 1 ? true : false;
            }

            return false;
        }

        public static void SetViewEnabledValue(bool value)
        {
            if (PortableData.IsEnabled)
            {
                return;
            }

            try
            {
                Registry.SetValue(DataDiagnosticsRegistryKey, DataDiagnosticsDataDiagnosticsViewDataRegistryValueName, value ? 1 : 0);
            }
            catch (Exception)
            {
            }
        }
    }
}
