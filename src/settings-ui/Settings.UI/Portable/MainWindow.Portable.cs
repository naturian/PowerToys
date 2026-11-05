// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using Microsoft.PowerToys.Settings.UI.Portable;
using Microsoft.PowerToys.Settings.UI.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WinUIEx;

namespace Microsoft.PowerToys.Settings.UI;

public sealed partial class MainWindow
{
    private void InitializePortable(PortableSession session)
    {
        // Deliberately do not instantiate ShellPage: a portable package has exactly one page,
        // no updater, dashboard, installed Runner bridge, or navigation into absent modules.
        Title = session.Name + " Portable – Einstellungen";
        MinWidth = 640;
        MinHeight = 500;
        Width = 1000;
        Height = 820;
        this.SetIcon(Path.Combine(AppContext.BaseDirectory, "portable.ico"));

        ShellPage.SetDefaultSndMessageCallback(session.ReceiveSettingsMessage);
        var panel = new Grid { RequestedTheme = App.ThemeService.Theme };
        panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var commands = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(24, 12, 24, 12) };
        var open = new Button { Content = session.OpenLabel };
        open.Click += (_, _) => session.OpenModule();
        commands.Children.Add(open);
        if (session.RequiresFileSelection)
        {
            var folder = new Button { Content = "Ordner auswählen" };
            folder.Click += (_, _) => session.OpenFolder();
            commands.Children.Add(folder);
        }
        if (!session.UsesModuleTray)
        {
            var close = new Button { Content = "Vollständig beenden" };
            close.Click += async (_, _) => await session.ShutdownAsync();
            commands.Children.Add(close);
        }

        panel.Children.Add(commands);
        var frame = new Frame();
        Grid.SetRow(frame, 1);
        panel.Children.Add(frame);
        Content = panel;
        frame.Navigate(session.PageType);
        Closed += (_, args) =>
        {
            if (!session.Exiting && !session.UsesModuleTray)
            {
                args.Handled = true;
                AppWindow.Hide();
            }
            else if (session.UsesModuleTray)
            {
                session.Dispose();
                Application.Current.Exit();
            }
        };
    }
}
