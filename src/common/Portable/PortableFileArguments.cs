// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Linq;

namespace PowerToys.Common;

/// <summary>Parses explicit portable file selections without reading installed IPC selections.</summary>
internal static class PortableFileArguments
{
    internal static string[] Parse(string[] inputs, string workingDirectory)
    {
        ArgumentNullException.ThrowIfNull(inputs);
        ArgumentNullException.ThrowIfNull(workingDirectory);
        if (inputs.Length > 256)
        {
            throw new ArgumentException("Höchstens 256 Dateien oder Ordner gleichzeitig auswählen.", nameof(inputs));
        }

        return inputs.Select(input =>
        {
            if (string.IsNullOrWhiteSpace(input) || input.StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException("Die portable Vorschau benötigt explizite Datei- oder Ordnerpfade.", nameof(inputs));
            }

            string path = Path.GetFullPath(input, workingDirectory);
            if (!File.Exists(path) && !Directory.Exists(path))
            {
                throw new FileNotFoundException("Die ausgewählte Datei oder der Ordner ist nicht verfügbar.", path);
            }

            return path;
        }).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }
}
