// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

#nullable enable
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace PowerToys.Common
{
    // Source-linked into managed libraries to avoid a telemetry/common reference cycle.
    internal static class PortableData
    {
        internal const string MarkerFileName = "portable-mode";

        private static readonly Lazy<string?> PortableLocalAppData = new(() => ResolvePortableRoot(AppContext.BaseDirectory));

        internal static bool IsEnabled => PortableLocalAppData.Value is not null;

        internal static string ResolveLocalApplicationDataPath(string installedPath)
            => PortableLocalAppData.Value ?? installedPath;

        internal static string ResolveLocalApplicationDataPath(string executableDirectory, string installedPath)
            => ResolvePortableRoot(executableDirectory) ?? installedPath;

        internal static string GetPowerToysDataRoot(string installedPath)
            => Path.Combine(ResolveLocalApplicationDataPath(installedPath), "Microsoft", "PowerToys");

        internal static string GetScopedEventName(string dataRoot, string command)
            => @"Local\PowerToys_Portable_" + Convert.ToHexString(SHA256.HashData(
                Encoding.UTF8.GetBytes(Path.GetFullPath(dataRoot).ToUpperInvariant() + "\0" + command)));

        private static string? ResolvePortableRoot(string executableDirectory)
        {
            string directory = Path.GetFullPath(executableDirectory);
            string marker = Path.Combine(directory, MarkerFileName);
            FileAttributes attributes;
            try
            {
                attributes = File.GetAttributes(marker);
            }
            catch (FileNotFoundException)
            {
                return null;
            }
            catch (DirectoryNotFoundException)
            {
                return null;
            }

            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
            {
                throw new IOException("The portable-mode marker must be a regular file beside the executable.");
            }

            EnsurePlainDirectory(directory);
            string localRoot = Path.Combine(directory, "Data");
            string path = directory;
            foreach (string segment in new[] { "Data", "Microsoft", "PowerToys" })
            {
                path = Path.Combine(path, segment);
                if (File.Exists(path))
                {
                    throw new IOException("A file blocks the portable data directory: " + path);
                }

                if (Directory.Exists(path))
                {
                    EnsurePlainDirectory(path);
                }
                else
                {
                    Directory.CreateDirectory(path);
                    EnsurePlainDirectory(path);
                }
            }

            // Never fall back to the installed profile when portable storage is unavailable.
            string probe = Path.Combine(path, ".portable-write-" + Guid.NewGuid().ToString("N") + ".tmp");
            using (var stream = new FileStream(probe, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose))
            {
                stream.WriteByte(0);
                stream.Flush(flushToDisk: true);
            }

            return localRoot;
        }

        private static void EnsurePlainDirectory(string path)
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.Directory) == 0 || (attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException("Portable data must stay in plain executable-adjacent directories: " + path);
            }
        }
    }
}
