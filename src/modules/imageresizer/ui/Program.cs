// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Threading;
using ManagedCommon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace ImageResizer
{
    public static class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
            if (PortableMode.IsEnabled)
            {
                _ = PortableMode.DataRoot;
                Directory.SetCurrentDirectory(AppContext.BaseDirectory);
            }

            WinRT.ComWrappersSupport.InitializeComWrappers();
            Application.Start((p) =>
            {
                var context = new DispatcherQueueSynchronizationContext(
                    DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App();
            });
        }
    }
}
