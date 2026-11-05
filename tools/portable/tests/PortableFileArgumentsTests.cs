// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PowerToys.Common;

namespace Portable.UnitTests;

[TestClass]
public class PortableFileArgumentsTests
{
    [TestMethod]
    public void ExplicitSelectionResolvesSpacesUnicodeAndDirectoriesAndRemovesDuplicates()
    {
        string root = Directory.CreateTempSubdirectory("portable-input-tests-").FullName;
        try
        {
            string file = Path.Combine(root, "Prüfung mit Leerzeichen.txt");
            File.WriteAllText(file, "fixture");
            string folder = Directory.CreateDirectory(Path.Combine(root, "Ordner")).FullName;
            var result = PortableFileArguments.Parse(new[] { Path.GetFileName(file), file, "Ordner" }, root);
            CollectionAssert.AreEqual(new[] { file, folder }, result);
            Assert.AreEqual("fixture", File.ReadAllText(file));
        }
        finally
        {
            string file = Path.Combine(root, "Prüfung mit Leerzeichen.txt");
            string folder = Path.Combine(root, "Ordner");
            if (File.Exists(file))
            {
                File.Delete(file);
            }

            if (Directory.Exists(folder))
            {
                Directory.Delete(folder);
            }

            Directory.Delete(root);
        }
    }

    [TestMethod]
    public void EmptySelectionRemainsEmptyInsteadOfReadingAStoredSelection()
    {
        Assert.AreEqual(0, PortableFileArguments.Parse(Array.Empty<string>(), Path.GetTempPath()).Length);
    }

    [TestMethod]
    [DataRow("--runner-pid")]
    [DataRow("--background")]
    [DataRow("--elevated")]
    [DataRow("--selection")]
    [DataRow("")]
    [DataRow(" ")]
    public void CommandsCannotBeInterpretedAsFilePaths(string input)
    {
        Assert.ThrowsExactly<ArgumentException>(() => PortableFileArguments.Parse(new[] { input }, Path.GetTempPath()));
    }

    [TestMethod]
    public void MissingFileIsRejectedAndOversizedSelectionIsBounded()
    {
        string missing = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Assert.ThrowsExactly<FileNotFoundException>(() => PortableFileArguments.Parse(new[] { missing }, Path.GetTempPath()));
        Assert.ThrowsExactly<ArgumentException>(() => PortableFileArguments.Parse(new string[257], Path.GetTempPath()));
    }

    [TestMethod]
    public void FuzzInvalidSelectionsCannotFallBackToAnyOtherFile()
    {
        string root = Directory.CreateTempSubdirectory("portable-input-fuzz-").FullName;
        var random = new Random(7358);
        try
        {
            for (int attempt = 0; attempt < 2000; attempt++)
            {
                var characters = new char[random.Next(1, 80)];
                for (int index = 0; index < characters.Length; index++)
                {
                    characters[index] = (char)random.Next(0, 65536);
                }

                // Keep the fuzz input inside our empty fixture, including any malformed suffix.
                string input = Path.Combine(root, "missing-" + attempt + "-" + new string(characters));
                try
                {
                    var result = PortableFileArguments.Parse(new[] { input }, root);
                    Assert.Fail("An invalid nonexistent selection was accepted: " + result.Length);
                }
                catch (Exception exception) when (exception is ArgumentException or IOException or NotSupportedException)
                {
                    Assert.IsFalse(File.Exists(input));
                }
            }
        }
        finally
        {
            Directory.Delete(root);
        }
    }
}
