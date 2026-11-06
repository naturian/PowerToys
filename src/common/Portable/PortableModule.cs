// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Text.Json;

namespace PowerToys.Common;

/// <summary>Fixed package identities. Package files cannot supply executable or settings paths.</summary>
internal sealed record PortableModule(string Id, string Name, string SettingsName, string Executable, string OpenLabel)
{
    internal static string GetLaunchCommand(string[] arguments)
    {
        if (Array.IndexOf(arguments, "--stop") >= 0)
        {
            return "StopHost";
        }

        if (Array.IndexOf(arguments, "--open") >= 0)
        {
            return "Open";
        }

        if (Array.IndexOf(arguments, "--settings") >= 0)
        {
            return "Settings";
        }

        return Array.IndexOf(arguments, "--background") >= 0 ? "Background" : "Settings";
    }

    internal static PortableModule Parse(string json)
    {
        if (json.Length > 1024)
        {
            throw new InvalidDataException("Portable package identity is too large.");
        }

        using var document = JsonDocument.Parse(json);
        return document.RootElement.GetProperty("module").GetString() switch
        {
            "FancyZones" => new("FancyZones", "FancyZones", "FancyZones", "PowerToys.FancyZones.exe", "Layout-Editor öffnen"),
            "ColorPicker" => new("ColorPicker", "Farbwähler", "ColorPicker", "PowerToys.ColorPickerUI.exe", "Farbwähler öffnen"),
            "TextExtractor" => new("TextExtractor", "Textextraktor", "TextExtractor", "PowerToys.PowerOCR.exe", "Text erfassen"),
            "ImageResizer" => new("ImageResizer", "Bildgrößenänderung", "Image Resizer", "PowerToys.ImageResizer.exe", "Bilder auswählen"),
            "PowerDisplay" => new("PowerDisplay", "Power Display", "PowerDisplay", "PowerToys.PowerDisplay.exe", "Anzeige steuern"),
            "AlwaysOnTop" => new("AlwaysOnTop", "Immer im Vordergrund", "AlwaysOnTop", "PowerToys.AlwaysOnTop.exe", "Anheften konfigurieren"),
            "FileLocksmith" => new("FileLocksmith", "Dateischlosser", "File Locksmith", "PowerToys.FileLocksmithUI.exe", "Dateien prüfen"),
            "Peek" => new("Peek", "Peek", "Peek", "PowerToys.Peek.UI.exe", "Dateivorschau öffnen"),
            "CropAndLock" => new("CropAndLock", "Zuschneiden und Sperren", "CropAndLock", "PowerToys.CropAndLock.exe", "Miniaturansicht zuschneiden"),
            "AdvancedPaste" => new("AdvancedPaste", "Erweitertes Einfügen", "AdvancedPaste", "PowerToys.AdvancedPaste.exe", "Einfügefenster öffnen"),
            _ => throw new InvalidDataException("Unknown portable module."),
        };
    }
}
