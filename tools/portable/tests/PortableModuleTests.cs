// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PowerToys.Common;

namespace Portable.UnitTests;

[TestClass]
public class PortableModuleTests
{
    [TestMethod]
    [DataRow("", "Settings")]
    [DataRow("--background", "Background")]
    [DataRow("--settings --background", "Settings")]
    [DataRow("--open --background", "Open")]
    [DataRow("--stop --background", "StopHost")]
    [DataRow("--stop --open --settings", "StopHost")]
    [DataRow("--BACKGROUND", "Settings")]
    public void LaunchCommandsKeepBackgroundStartsSilentAndExplicitActionsAvailable(string arguments, string expected)
    {
        Assert.AreEqual(expected, PortableModule.GetLaunchCommand(arguments.Split(' ', StringSplitOptions.RemoveEmptyEntries)));
    }

    [TestMethod]
    [DataRow("FancyZones", "FancyZones", "PowerToys.FancyZones.exe")]
    [DataRow("ColorPicker", "ColorPicker", "PowerToys.ColorPickerUI.exe")]
    [DataRow("TextExtractor", "TextExtractor", "PowerToys.PowerOCR.exe")]
    [DataRow("ImageResizer", "Image Resizer", "PowerToys.ImageResizer.exe")]
    [DataRow("PowerDisplay", "PowerDisplay", "PowerToys.PowerDisplay.exe")]
    [DataRow("AlwaysOnTop", "AlwaysOnTop", "PowerToys.AlwaysOnTop.exe")]
    [DataRow("FileLocksmith", "File Locksmith", "PowerToys.FileLocksmithUI.exe")]
    [DataRow("Peek", "Peek", "PowerToys.Peek.UI.exe")]
    [DataRow("CropAndLock", "CropAndLock", "PowerToys.CropAndLock.exe")]
    [DataRow("AdvancedPaste", "AdvancedPaste", "PowerToys.AdvancedPaste.exe")]
    public void PackageIdentitySelectsOnlyItsKnownExecutableAndSettings(string id, string settings, string executable)
    {
        var module = PortableModule.Parse("{\"module\":\"" + id + "\",\"executable\":\"C:\\\\unexpected.exe\",\"settings\":\"..\\\\outside\"}");
        Assert.AreEqual(settings, module.SettingsName);
        Assert.AreEqual(executable, module.Executable);
    }

    [TestMethod]
    [DataRow("../FancyZones")]
    [DataRow("C:\\Windows\\System32\\cmd.exe")]
    [DataRow("Hosts")]
    [DataRow("fancyzones")]
    public void UnknownOrPathLikeModuleIdentityIsRejected(string id)
    {
        string json = JsonSerializer.Serialize(new Dictionary<string, string> { ["module"] = id });
        Assert.ThrowsExactly<InvalidDataException>(() => PortableModule.Parse(json));
    }

    [TestMethod]
    public void ScopedEventsAcceptNativeNamesAndSeparateFoldersAndCommands()
    {
        string first = PortableData.GetScopedEventName(@"C:\Portable\Data", @"Local\PowerDisplay-Refresh");
        Assert.AreEqual(first, PortableData.GetScopedEventName(@"c:\portable\data", @"Local\PowerDisplay-Refresh"));
        Assert.AreNotEqual(first, PortableData.GetScopedEventName(@"C:\Other\Data", @"Local\PowerDisplay-Refresh"));
        Assert.AreNotEqual(first, PortableData.GetScopedEventName(@"C:\Portable\Data", @"Local\PowerDisplay-Stop"));
        Assert.AreEqual(first.IndexOf('\\'), first.LastIndexOf('\\'));
        Assert.IsTrue(first.Length < 260);
    }

    [TestMethod]
    public void OversizedIdentityIsRejectedBeforeParsing()
    {
        Assert.ThrowsExactly<InvalidDataException>(() => PortableModule.Parse(new string(' ', 1025)));
    }

    [TestMethod]
    public void FuzzMalformedAndMutatedPackageIdentityCannotChooseAnExternalPath()
    {
        var random = new Random(1826);
        string[] seeds = { "{\"module\":\"FancyZones\"}", "[]", "null", "{\"module\":1}", "{\"module\":\"..\\\\outside\"}" };
        for (int attempt = 0; attempt < 2000; attempt++)
        {
            string candidate = seeds[attempt % seeds.Length];
            for (int mutation = 0; mutation < attempt % 10; mutation++)
            {
                candidate = candidate.Insert(random.Next(candidate.Length + 1), ((char)random.Next(0, 65536)).ToString());
            }

            try
            {
                var module = PortableModule.Parse(candidate);
                Assert.IsFalse(Path.IsPathRooted(module.Executable));
                Assert.AreEqual(Path.GetFileName(module.Executable), module.Executable);
                Assert.IsFalse(module.SettingsName.Contains("..", StringComparison.Ordinal));
            }
            catch (Exception exception) when (exception is JsonException or InvalidDataException or InvalidOperationException or KeyNotFoundException ||
                exception is ArgumentException { InnerException: System.Text.EncoderFallbackException })
            {
                // Rejection is the expected result for malformed identity input.
            }
        }
    }
}
