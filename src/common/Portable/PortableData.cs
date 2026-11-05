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
        internal const string StandaloneMarkerFileName = "standalone-mode";

        private static readonly Lazy<string?> PortableLocalAppData = new(() => ResolvePortableRoot(
            AppContext.BaseDirectory, Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)));

        internal static bool IsEnabled => PortableLocalAppData.Value is not null;

        internal static string ResolveLocalApplicationDataPath(string installedPath)
            => PortableLocalAppData.Value ?? installedPath;

        internal static string ResolveLocalApplicationDataPath(string executableDirectory, string installedPath)
            => ResolvePortableRoot(executableDirectory, installedPath) ?? installedPath;

        internal static string GetPowerToysDataRoot(string installedPath)
            => Path.Combine(ResolveLocalApplicationDataPath(installedPath), "Microsoft", "PowerToys");

        internal static string GetScopedEventName(string dataRoot, string command)
            => @"Local\PowerToys_Portable_" + Convert.ToHexString(SHA256.HashData(
                Encoding.UTF8.GetBytes(Path.GetFullPath(dataRoot).ToUpperInvariant() + "\0" + command)));

        private static string? ResolvePortableRoot(string executableDirectory, string installedPath)
        {
            string directory = Path.GetFullPath(executableDirectory);
            bool portable = HasMarker(Path.Combine(directory, MarkerFileName));
            bool standalone = HasMarker(Path.Combine(directory, StandaloneMarkerFileName));
            if (!portable && !standalone)
            {
                return null;
            }

            if (portable && standalone)
            {
                throw new IOException("A package must select exactly one data-storage mode.");
            }

            EnsurePlainDirectory(directory);
            string baseDirectory = directory;
            string[] segments = { "Data", "Microsoft", "PowerToys" };
            string localRoot = Path.Combine(directory, "Data");
            if (standalone)
            {
                string marker = Path.Combine(directory, StandaloneMarkerFileName);
                if (new FileInfo(marker).Length > 64)
                {
                    throw new InvalidDataException("Standalone package identity is too large.");
                }

                string module = File.ReadAllText(marker, Encoding.UTF8).Trim();
                if (module is not ("FancyZones" or "ColorPicker" or "TextExtractor" or "ImageResizer" or "PowerDisplay" or
                    "AlwaysOnTop" or "FileLocksmith" or "Peek" or "CropAndLock" or "AdvancedPaste"))
                {
                    throw new InvalidDataException("Unknown standalone module.");
                }

                if (!Path.IsPathFullyQualified(installedPath))
                {
                    throw new IOException("Standalone storage requires an absolute local application data path.");
                }

                baseDirectory = Path.GetFullPath(installedPath);
                EnsurePlainDirectory(baseDirectory);
                segments = new[] { "Naturian", "PowerToysModules", module, "Microsoft", "PowerToys" };
                localRoot = Path.Combine(baseDirectory, "Naturian", "PowerToysModules", module);
            }

            string path = baseDirectory;
            foreach (string segment in segments)
            {
                path = Path.Combine(path, segment);
                if (File.Exists(path))
                {
                    throw new IOException("A file blocks the module data directory: " + path);
                }

                Directory.CreateDirectory(path);
                EnsurePlainDirectory(path);
            }

            // Validate the selected storage before any settings or logging code uses it.
            string probe = Path.Combine(path, ".portable-write-" + Guid.NewGuid().ToString("N") + ".tmp");
            using (var stream = new FileStream(probe, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose))
            {
                stream.WriteByte(0);
                stream.Flush(flushToDisk: true);
            }

            if (standalone)
            {
                SeedProfile(directory, path);
            }

            return localRoot;
        }

        private static bool HasMarker(string marker)
        {
            FileAttributes attributes;
            try
            {
                attributes = File.GetAttributes(marker);
            }
            catch (FileNotFoundException)
            {
                return false;
            }
            catch (DirectoryNotFoundException)
            {
                return false;
            }

            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
            {
                throw new IOException("The module mode marker must be a regular file beside the executable.");
            }

            return true;
        }

        private static void SeedProfile(string directory, string dataRoot)
        {
            foreach (string name in new[] { "language.json", "settings.json" })
            {
                string destination = Path.Combine(dataRoot, name);
                if (File.Exists(destination))
                {
                    continue;
                }

                string temporary = Path.Combine(dataRoot, ".profile-seed-" + Guid.NewGuid().ToString("N") + ".tmp");
                try
                {
                    File.Copy(Path.Combine(directory, "Defaults", name), temporary, overwrite: false);
                    try
                    {
                        File.Move(temporary, destination, overwrite: false);
                    }
                    catch (IOException) when (File.Exists(destination))
                    {
                        // Another process completed this profile seed first.
                    }
                }
                finally
                {
                    File.Delete(temporary);
                }
            }
        }

        private static void EnsurePlainDirectory(string path)
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.Directory) == 0 || (attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException("Module data requires plain directories: " + path);
            }
        }
    }
}
