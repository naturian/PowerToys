// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System.Text.Json;

using Microsoft.PowerToys.Settings.UI.Library;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace CommonLibTest
{
    [TestClass]
    public class AdvancedPasteSettingsTests
    {
        [TestMethod]
        public void Defaults_ShouldKeepPasteWithAIDisabled()
        {
            var settings = new AdvancedPasteSettings();

            Assert.IsFalse(settings.Properties.IsAIEnabled);
        }

        [TestMethod]
        public void EnabledSetting_ShouldKeepPasteWithAILocked()
        {
            const string settingsJson = "{\"properties\":{\"IsAIEnabled\":{\"value\":true}}}";

            var settings = JsonSerializer.Deserialize<AdvancedPasteSettings>(settingsJson);

            Assert.IsNotNull(settings);
            Assert.IsFalse(settings.Properties.IsAIEnabled);
        }

        [TestMethod]
        public void LockedSetting_ShouldPreserveJsonContract()
        {
            var settingsJson = JsonSerializer.Serialize(new AdvancedPasteSettings());
            using var document = JsonDocument.Parse(settingsJson);

            var isAIEnabled = document.RootElement.GetProperty("properties").GetProperty("IsAIEnabled").GetProperty("value").GetBoolean();

            Assert.IsFalse(isAIEnabled);
        }
    }
}
