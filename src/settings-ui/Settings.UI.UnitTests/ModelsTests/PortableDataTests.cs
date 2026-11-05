// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PowerToys.Common;

namespace CommonLibTest
{
    [TestClass]
    public class PortableDataTests
    {
        private string _testRoot = string.Empty;

        [TestInitialize]
        public void Initialize()
        {
            _testRoot = Path.Combine(Path.GetTempPath(), "PowerToys-PortableDataTests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_testRoot);
        }

        [TestCleanup]
        public void Cleanup()
        {
            if (Path.GetFullPath(_testRoot).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) &&
                Path.GetFileName(_testRoot).StartsWith("PowerToys-PortableDataTests-", StringComparison.Ordinal))
            {
                Directory.Delete(_testRoot, recursive: true);
            }
        }

        [TestMethod]
        public void WithoutMarker_PreservesInstalledPathAndCreatesNoData()
        {
            string installed = Path.Combine(_testRoot, "installed-profile");
            Assert.AreEqual(installed, PortableData.ResolveLocalApplicationDataPath(_testRoot, installed));
            Assert.IsFalse(Directory.Exists(Path.Combine(_testRoot, "Data")));
            Assert.IsFalse(Directory.Exists(installed));
        }

        [TestMethod]
        public void WithMarker_CreatesOnlyAdjacentDataAndRemovesWriteProbe()
        {
            File.WriteAllText(Path.Combine(_testRoot, PortableData.MarkerFileName), string.Empty);
            string installed = Path.Combine(_testRoot, "installed-profile");
            string actual = PortableData.ResolveLocalApplicationDataPath(_testRoot, installed);
            Assert.AreEqual(Path.Combine(_testRoot, "Data"), actual);
            Assert.IsTrue(Directory.Exists(Path.Combine(actual, "Microsoft", "PowerToys")));
            Assert.AreEqual(0, Directory.GetFiles(actual, "*.tmp", SearchOption.AllDirectories).Length);
            Assert.IsFalse(Directory.Exists(installed));
        }

        [TestMethod]
        public void BlockedData_ThrowsWithoutFallingBackToInstalledProfile()
        {
            File.WriteAllText(Path.Combine(_testRoot, PortableData.MarkerFileName), string.Empty);
            File.WriteAllText(Path.Combine(_testRoot, "Data"), "block");
            string installed = Path.Combine(_testRoot, "installed-profile");
            Assert.ThrowsException<IOException>(() => PortableData.ResolveLocalApplicationDataPath(_testRoot, installed));
            Assert.IsFalse(Directory.Exists(installed));
        }

        [TestMethod]
        public void DirectoryMarker_IsRejectedInsteadOfUsingInstalledProfile()
        {
            Directory.CreateDirectory(Path.Combine(_testRoot, PortableData.MarkerFileName));
            string installed = Path.Combine(_testRoot, "installed-profile");
            Assert.ThrowsException<IOException>(() => PortableData.ResolveLocalApplicationDataPath(_testRoot, installed));
            Assert.IsFalse(Directory.Exists(installed));
        }
    }
}
