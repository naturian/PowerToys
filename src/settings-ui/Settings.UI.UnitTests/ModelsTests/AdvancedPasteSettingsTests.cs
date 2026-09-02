// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

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
    }
}
