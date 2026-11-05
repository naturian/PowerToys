// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PowerToys.Common;

namespace CommonLibTest;

[TestClass]
public class StandaloneDataTests
{
    private string _root = string.Empty;
    private string _application = string.Empty;
    private string _profile = string.Empty;

    [TestInitialize]
    public void Initialize()
    {
        _root = Path.Combine(Path.GetTempPath(), "PowerToys-StandaloneDataTests-" + Guid.NewGuid().ToString("N"));
        _application = Path.Combine(_root, "ProgramFiles", "Module");
        _profile = Path.Combine(_root, "UserProfile");
        Directory.CreateDirectory(Path.Combine(_application, "Defaults"));
        Directory.CreateDirectory(_profile);
        File.WriteAllText(Path.Combine(_application, "Defaults", "language.json"), "{\"language\":\"de-DE\"}");
        File.WriteAllText(Path.Combine(_application, "Defaults", "settings.json"), "{\"startup\":false}");
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Path.GetDirectoryName(_root) == Path.GetTempPath().TrimEnd(Path.DirectorySeparatorChar) &&
            Path.GetFileName(_root).StartsWith("PowerToys-StandaloneDataTests-", StringComparison.Ordinal))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    [DataTestMethod]
    [DataRow("FancyZones")]
    [DataRow("ColorPicker")]
    [DataRow("TextExtractor")]
    [DataRow("ImageResizer")]
    [DataRow("PowerDisplay")]
    [DataRow("AlwaysOnTop")]
    [DataRow("FileLocksmith")]
    [DataRow("Peek")]
    [DataRow("CropAndLock")]
    [DataRow("AdvancedPaste")]
    public void InstalledModule_UsesIsolatedUserProfileAndGermanDefaults(string module)
    {
        File.WriteAllText(Path.Combine(_application, PortableData.StandaloneMarkerFileName), module);
        string actual = PortableData.ResolveLocalApplicationDataPath(_application, _profile);
        Assert.AreEqual(Path.Combine(_profile, "Naturian", "PowerToysModules", module), actual);
        Assert.AreEqual("{\"language\":\"de-DE\"}", File.ReadAllText(Path.Combine(actual, "Microsoft", "PowerToys", "language.json")));
        Assert.IsFalse(Directory.Exists(Path.Combine(_application, "Data")));
        Assert.IsFalse(Directory.Exists(Path.Combine(_profile, "Microsoft", "PowerToys")));
    }

    [TestMethod]
    public void ExistingSettings_ArePreservedAcrossRepeatedAndConcurrentStarts()
    {
        File.WriteAllText(Path.Combine(_application, PortableData.StandaloneMarkerFileName), "FancyZones");
        Parallel.For(0, 32, _ => PortableData.ResolveLocalApplicationDataPath(_application, _profile));
        string root = Path.Combine(_profile, "Naturian", "PowerToysModules", "FancyZones", "Microsoft", "PowerToys");
        File.WriteAllText(Path.Combine(root, "settings.json"), "custom settings");
        PortableData.ResolveLocalApplicationDataPath(_application, _profile);
        Assert.AreEqual("custom settings", File.ReadAllText(Path.Combine(root, "settings.json")));
        Assert.AreEqual(0, Directory.GetFiles(root, "*.tmp").Length);
    }

    [TestMethod]
    public void DistinctUsersAndModules_GetDistinctRoots()
    {
        string secondUser = Path.Combine(_root, "SecondUser");
        Directory.CreateDirectory(secondUser);
        string marker = Path.Combine(_application, PortableData.StandaloneMarkerFileName);
        File.WriteAllText(marker, "FancyZones");
        string first = PortableData.ResolveLocalApplicationDataPath(_application, _profile);
        string second = PortableData.ResolveLocalApplicationDataPath(_application, secondUser);
        File.WriteAllText(marker, "Peek");
        string third = PortableData.ResolveLocalApplicationDataPath(_application, _profile);
        Assert.AreNotEqual(first, second);
        Assert.AreNotEqual(first, third);
    }

    [TestMethod]
    public void ConflictingMarkers_AreRejectedBeforeCreatingData()
    {
        File.WriteAllText(Path.Combine(_application, PortableData.MarkerFileName), string.Empty);
        File.WriteAllText(Path.Combine(_application, PortableData.StandaloneMarkerFileName), "FancyZones");
        Assert.ThrowsException<IOException>(() => PortableData.ResolveLocalApplicationDataPath(_application, _profile));
        Assert.IsFalse(Directory.Exists(Path.Combine(_application, "Data")));
        Assert.IsFalse(Directory.Exists(Path.Combine(_profile, "Naturian")));
    }

    [DataTestMethod]
    [DataRow("../FancyZones")]
    [DataRow("C:\\outside")]
    [DataRow("")]
    [DataRow("UnknownModule")]
    [DataRow("FancyZones/Peek")]
    public void InvalidIdentity_IsRejectedBeforeCreatingData(string module)
    {
        File.WriteAllText(Path.Combine(_application, PortableData.StandaloneMarkerFileName), module);
        Assert.ThrowsException<InvalidDataException>(() => PortableData.ResolveLocalApplicationDataPath(_application, _profile));
        Assert.IsFalse(Directory.Exists(Path.Combine(_profile, "Naturian")));
    }

    [TestMethod]
    public void MutatedIdentityFuzz_CannotSelectPaths()
    {
        var random = new Random(20261105);
        string marker = Path.Combine(_application, PortableData.StandaloneMarkerFileName);
        for (int iteration = 0; iteration < 2000; iteration++)
        {
            var bytes = new byte[random.Next(8, 110)];
            random.NextBytes(bytes);
            "invalid-"u8.CopyTo(bytes);
            File.WriteAllBytes(marker, bytes);
            Assert.ThrowsException<InvalidDataException>(() => PortableData.ResolveLocalApplicationDataPath(_application, _profile));
        }

        Assert.IsFalse(Directory.Exists(Path.Combine(_profile, "Naturian")));
    }

    [TestMethod]
    public void IncompleteProfileSeed_CanRetryAndPreservesExistingUserData()
    {
        File.WriteAllText(Path.Combine(_application, PortableData.StandaloneMarkerFileName), "FancyZones");
        string settingsTemplate = Path.Combine(_application, "Defaults", "settings.json");
        File.Delete(settingsTemplate);
        Assert.ThrowsException<FileNotFoundException>(() => PortableData.ResolveLocalApplicationDataPath(_application, _profile));
        string root = Path.Combine(_profile, "Naturian", "PowerToysModules", "FancyZones", "Microsoft", "PowerToys");
        File.WriteAllText(Path.Combine(root, "language.json"), "user language");
        File.WriteAllText(settingsTemplate, "recovered settings");
        PortableData.ResolveLocalApplicationDataPath(_application, _profile);
        Assert.AreEqual("user language", File.ReadAllText(Path.Combine(root, "language.json")));
        Assert.AreEqual("recovered settings", File.ReadAllText(Path.Combine(root, "settings.json")));
        Assert.AreEqual(0, Directory.GetFiles(root, "*.tmp").Length);
    }
}
