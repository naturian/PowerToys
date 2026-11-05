# Machbarkeit einzelner portabler PowerToys-Module

Stand: 5. November 2026. Im separaten Branch `codex/portable-first-modules` werden zehn experimentelle Portable-Pakete gebaut: FancyZones, Farbwähler, Textextraktor, Bildgrößenänderung, Power Display, Immer im Vordergrund, File Locksmith, Peek, Zuschneiden und Sperren sowie Erweitertes Einfügen mit gesperrter KI. Sie enthalten deutsche grafische Einstellungen und Tray-Steuerung. Der bestehende Minimal-Installer bleibt auf seinem eigenen Branch.

Die Pakete sind vollständige Ordner mit Laufzeitdateien, keine einzelnen EXE-Dateien. Eigene Einstellungen und Protokolle liegen unter `Data/Microsoft/PowerToys` im jeweiligen Ordner. Details zu Start, Build und Grenzen stehen in [tools/portable/README.md](tools/portable/README.md). Die folgende Machbarkeitsuntersuchung beschreibt die ursprüngliche Ausgangslage und die noch nicht herausgelösten Module.

Als aktuelle stabile Vergleichsbasis dient [PowerToys 0.102.3001.0 vom 27. Oktober 2026](https://github.com/microsoft/PowerToys/releases/tag/v0.102.3001), Tag `v0.102.3001`, Commit `a00b2bce7403f0a48efe5cbb6671074e01f27824`.
Die untersuchten Einstiegspunkte der Arbeitskopie 0.102.2883.0 wurden gezielt gegen diesen Tag verglichen; ihre hier beschriebenen Startbedingungen sind unverändert. Die Angaben beruhen auf Quellprüfung, nicht auf ausgeführten Portable-Paketen oder einem Test auf einem sauberen Zielrechner.

## Was „portabel“ hier bedeutet

**Installfrei** bedeutet: Einen vollständigen Programmordner entpacken und daraus starten, ohne den PowerToys-Installer auszuführen. Einstellungen und Protokolle dürfen dabei weiterhin im Benutzerprofil liegen.

**Mit portablen Anwendungsdaten** bedeutet zusätzlich: Einstellungen, Verlauf und Protokolle bleiben in einem mitnehmbaren Datenordner. Dafür müsste PowerToys einen gemeinsamen, konfigurierbaren Datenpfad erhalten. Eine Garantie, dass Windows selbst keinerlei Ausführungsspuren speichert, ist damit nicht verbunden.

Das Kopieren einer einzelnen EXE erfüllt diese Anforderungen meistens nicht: Die vier geprüften WinUI-Anwendungen importieren `Common.SelfContained.props` und setzen `WindowsAppSDKSelfContained=true`. Laufzeitdateien, native Bibliotheken und Ressourcen gehören zum Paket. Beispiele: [ColorPicker-Projekt] und [ImageResizer-Projekt].

## Einordnung unserer 20 Modulgruppen

Der Aufwand beschreibt ein eigenständig startbares, installfreies Ordnerpaket mit vorhandener Funktionalität. Ein portabler Datenpfad und eine gemeinsame Startoberfläche kommen gegebenenfalls hinzu. „Gering“ ist eine Architektur-Einschätzung, keine Zeit- oder Funktionsgarantie.

| Modulgruppe | Einschätzung | Begründung und Grenze |
| --- | --- | --- |
| ZoomIt | Gering; offiziell separat erhältlich | Start ohne Runner ist vorgesehen. Die eigenständige Sysinternals-Ausgabe ist bereits verfügbar; ihre Einstellungen liegen allerdings in der Registry. [ZoomIt-Start], [ZoomIt-Registry] |
| Image Resizer | Gering | Startet ohne Runner, übernimmt Dateipfade oder öffnet einen Dateiauswahldialog. Das Explorer-Menü ist ein zusätzlicher Integrationsschritt. [ImageResizer-Start] |
| File Locksmith | Gering für CLI, mittel für GUI | Die CLI verarbeitet ihre eigenen Argumente. Die GUI übernimmt ihre Auswahl aus einer Datei im PowerToys-Benutzerprofil; für eine unabhängige GUI wäre ein anderer Dateieingang sinnvoll. [FileLocksmith-CLI], [FileLocksmith-Auswahl] |
| Color Picker | Gering | Erkennt den Start ohne Runner und aktiviert dann einen eigenen Tastatur-Hook. Einstellungen und Farbverlauf bleiben zunächst im Benutzerprofil. [ColorPicker-Start], [ColorPicker-Hook] |
| Text Extractor | Gering | Ohne Runner-PID wird ein eigener KeyboardMonitor gestartet. Die Texterkennung verwendet weiterhin die Windows-OCR-Sprachunterstützung. [OCR-Start], [OCR-Backend] |
| FancyZones | Mittel | Die Runner-PID ist optional; FancyZones richtet eigene Tastatur- und Fenster-Hooks ein. Editor und Layoutdaten müssen mit berücksichtigt werden. [FancyZones-Start], [FancyZones-Hook] |
| Always On Top | Gering bis mittel | Runner-PID ist optional, eigene Hotkey-Registrierung ist vorhanden. Eine Start-/Beenden-Oberfläche und ein portabler Einstellungspfad fehlen als Paketkonzept. [AlwaysOnTop-Start], [AlwaysOnTop-Hotkeys] |
| Crop And Lock | Mittel | Verweigert den Start ohne Runner ausdrücklich; seine Aktionen kommen über benannte Events. Ein eigenständiger Launcher müsste diese Steuerung übernehmen. [CropAndLock-Start] |
| Grab And Move | Mittel | Verweigert den Start ohne Runner-PID ausdrücklich und verwendet Runner-Lebenszyklus sowie benannte Settings-/Exit-Events. [GrabAndMove-Start] |
| Screen Ruler | Gering bis mittel | Eine Runner-PID wird nur optional überwacht; die eigene Oberfläche wird unabhängig davon erzeugt. Die native MeasureToolCore-Bibliothek gehört mit ins Paket. [ScreenRuler-Start] |
| Power Display | Gering bis mittel | Besitzt ausdrücklich einen Standalone-Modus mit eigenem Fenster und Tray. Hardwarezugriff und zugehörige Bibliotheken bleiben Voraussetzung. [PowerDisplay-Start] |
| Light Switch | Mittel | Der Hilfsprozess kann außerhalb des Windows-Dienstmanagers laufen; die CLI spricht diesen Prozess über IPC an. Die gewollte Änderung des Windows-Themas schreibt selbst Registry-Werte. [LightSwitch-Start], [LightSwitch-CLI], [LightSwitch-Thema] |
| Mouse Utilities | Mittel bis hoch als gesamte Gruppe | Mehrere Werkzeuge sind DLL-Module für den Runner. Mouse Jump verlangt zusätzlich eine Runner-PID und Aktivierungs-Events. Die fünf ausgewählten Werkzeuge benötigen daher einen gemeinsamen Host oder eigene Startlogik. [MouseUtils-Host], [MouseJump-Start] |
| Window Hopper | Mittel | Implementiert die PowerToys-Modulschnittstelle als DLL; Hotkey-Beschreibung und Aktivierungs-Callback werden vom Host bedient. [WindowHopper-Host] |
| Advanced Paste | Gering für CLI, mittel für GUI | Die CLI besitzt einen eigenen Einstieg und eine gemeinsame Engine. Die GUI erwartet ihre Anzeige-/Aktionsbefehle über eine Pipe; ihr bloßer Prozessstart öffnet kein Dashboard. Unsere vorhandene KI-Sperre muss in jedem Paket erhalten bleiben. [AdvancedPaste-CLI], [AdvancedPaste-GUI] |
| New+ | Hoch ohne Explorer-Registrierung | Das Produkt ist eine Explorer-Erweiterung. Der Modulstart registriert COM-Kontextmenüs beziehungsweise ein Sparse-Paket; ohne diese Integration fehlt die eigentliche Oberfläche. [NewPlus-Host], [NewPlus-Registrierung] |
| PowerRename | Gering bis mittel ohne Explorer-Menü | Die eigene Oberfläche akzeptiert explizite Dateipfade, alternativ Pipe/Standardeingabe. Ein installfreier Dateistart ist damit plausibel; das originale Explorer-Menü benötigt Registrierung. [PowerRename-Start], [PowerRename-Registrierung] |
| Peek | Gering bis mittel mit Dateipfaden | Unterscheidet Runner-Aufruf und direkten CLI-Aufruf mit Pfaden. Das originale Explorer-Hotkey-Verhalten und die Vorschau-Abhängigkeiten müssen zusätzlich bewertet werden. [Peek-Start] |
| Workspaces | Mittel | Der Editor kann ohne Runner-PID starten; ein vollständiges Paket umfasst zusätzlich Aufnahme-, Launcher- und Anordnungsprozesse sowie Arbeitsbereichsdaten. [Workspaces-Start] |
| Shortcut Guide | Mittel | Die PID ist optional, die Oberfläche bleibt zunächst verborgen und wartet auf Aktivierungs-Events. Für ein eigenständiges Werkzeug fehlt daher eine eigene Aktivierungsoberfläche beziehungsweise Hotkey-Steuerung. [ShortcutGuide-Start], [ShortcutGuide-Events] |

## Wo der zusätzliche Aufwand entsteht

Ein **Launcher** kann Programmordner starten und beenden sowie bisherige Runner-Hotkeys und Aktivierungs-Events übernehmen. Das ersetzt bei DLL-Modulen nicht automatisch die Modulschnittstelle und löst noch keinen Datenpfad auf. Belege sind die Host-Callbacks von [WindowHopper-Host] und der ausdrücklich erzwungene Runner-Start von [CropAndLock-Start].

Ein **gemeinsamer Datenpfad** ist eine gesonderte Änderung: Die native SettingsAPI verwendet `SHGetKnownFolderPath(FOLDERID_LocalAppData)` und erstellt `Microsoft\PowerToys`; C#-Settings und Logger verwenden denselben Benutzerbereich. Image Resizer besitzt außerdem einen eigenen Einstellungspfad. Allein das Umsetzen der Umgebungsvariablen `LOCALAPPDATA` deckt diese nativen Known-Folder-Aufrufe nicht ab. [Native-Datenwurzel], [Managed-Datenwurzel], [Managed-Logs], [ImageResizer-Daten]

**Explorer-Integration** ist ein weiterer eigener Bereich. New+, PowerRename, Image Resizer und File Locksmith registrieren Kontextmenüs über COM/Registry oder Sparse-Pakete. Eine Registrierung beim Start mit späterem Aufräumen wäre eine Änderung am Zielsystem; bei Abstürzen oder einem verschobenen Programmordner blieben Wiederherstellung und veraltete Pfade zu behandeln. Eine eigene Dateiauswahl beziehungsweise ein Start mit Dateipfaden vermeidet diese Integration, ersetzt bei New+ aber dessen eigentliche Bedienung. [NewPlus-Registrierung], [PowerRename-Registrierung], [Explorer-Manifest]

ZoomIt zeigt die Begriffsgrenze gut: Microsoft bietet [ZoomIt 12.3 separat als Download und über Sysinternals Live](https://learn.microsoft.com/en-us/sysinternals/downloads/zoomit) an. Das ist sofort installfrei nutzbar, aber der Quellcode liest und schreibt `HKCU\Software\Sysinternals\ZoomIt`. Auch hier ist „ohne Installer“ nicht gleichbedeutend mit „alle eigenen Daten im Programmordner“. [ZoomIt-Registry]

Für einen ersten kleinen Umfang bieten sich ZoomIt, Image Resizer, Color Picker und Text Extractor sowie File Locksmith als CLI an. FancyZones und PowerRename sind ebenfalls realistische Kandidaten; sie sollten nicht pauschal als ausschließlich Runner-gebunden eingeordnet werden. Diese Auswahl ist eine Empfehlung aus den belegten Einstiegspunkten, keine bereits validierte Auslieferung.

## Quellbelege

Die folgenden Permalinks zeigen unveränderliche Upstream-Dateien der stabilen Basis. Die lokalen Pfade entsprechen den verlinkten Repository-Pfaden. Unsere KI-Sperre ist eine zusätzliche Fork-Änderung in `src/modules/AdvancedPaste/AdvancedPaste.Engine/AdvancedPastePolicy.cs` und wird von diesen Upstream-Links nicht behauptet.

[ColorPicker-Projekt]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ColorPickerUI.csproj#L4-L19
[ImageResizer-Projekt]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/ImageResizerUI.csproj#L4-L20
[ZoomIt-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ZoomIt/ZoomIt/Zoomit.cpp#L13064-L13099
[ZoomIt-Registry]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ZoomIt/ZoomIt/Zoomit.cpp#L280
[ImageResizer-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/ImageResizerXAML/App.xaml.cs#L102-L129
[FileLocksmith-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/FileLocksmith/FileLocksmithCLI/main.cpp#L52-L67
[FileLocksmith-Auswahl]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/FileLocksmith/FileLocksmithLibInterop/NativeMethods.cpp#L14-L21
[ColorPicker-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ColorPickerXAML/App.xaml.cs#L84-L99
[ColorPicker-Hook]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/colorPicker/ColorPickerUI/ViewModels/MainViewModel.cs#L84-L88
[OCR-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/PowerOCR/PowerOCR/PowerOCRXAML/App.xaml.cs#L127-L143
[OCR-Backend]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/PowerOCR/PowerOCR.Core/Ocr/WindowsOcrRecognizer.cs#L19-L29
[FancyZones-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/fancyzones/FancyZones/main.cpp#L67-L88
[FancyZones-Hook]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/fancyzones/FancyZones/FancyZonesApp.cpp#L76-L103
[AlwaysOnTop-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/alwaysontop/AlwaysOnTop/main.cpp#L48-L68
[AlwaysOnTop-Hotkeys]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/alwaysontop/AlwaysOnTop/AlwaysOnTop.cpp#L364-L383
[CropAndLock-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/CropAndLock/CropAndLock/main.cpp#L96-L105
[GrabAndMove-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/GrabAndMove/GrabAndMove/main.cpp#L3326-L3353
[ScreenRuler-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MeasureTool/MeasureToolUI/MeasureToolXAML/App.xaml.cs#L50-L76
[PowerDisplay-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerdisplay/PowerDisplay/PowerDisplayXAML/App.xaml.cs#L153-L195
[LightSwitch-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitchService/LightSwitchService.cpp#L36-L73
[LightSwitch-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitch.Cli/Program.cs#L117-L123
[LightSwitch-Thema]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/LightSwitch/LightSwitchLib/ThemeHelper.cpp#L93-L106
[MouseUtils-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MouseUtils/FindMyMouse/dllmain.cpp#L62-L81
[MouseJump-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/MouseUtils/MouseJump.WinUI3/Program.cs#L47-L78
[WindowHopper-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AltWindowCycle/dllmain.cpp#L180-L230
[AdvancedPaste-CLI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AdvancedPaste/AdvancedPaste.CLI/Program.cs#L96-L104
[AdvancedPaste-GUI]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/AdvancedPaste/AdvancedPaste/AdvancedPasteXAML/App.xaml.cs#L104-L126
[NewPlus-Host]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/NewPlus/NewShellExtensionContextMenu/powertoys_module.cpp#L123-L140
[NewPlus-Registrierung]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/NewPlus/NewShellExtensionContextMenu/RuntimeRegistration.h#L14-L31
[PowerRename-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerrename/PowerRenameUILib/PowerRenameXAML/App.xaml.cpp#L130-L149
[PowerRename-Registrierung]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/powerrename/dll/RuntimeRegistration.h#L14-L33
[Peek-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/peek/Peek.UI/PeekXAML/App.xaml.cs#L112-L136
[Workspaces-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/Workspaces/WorkspacesEditor/App.xaml.cs#L79-L109
[ShortcutGuide-Start]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ShortcutGuide/ShortcutGuide.Ui/Program.cs#L52-L55
[ShortcutGuide-Events]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/ShortcutGuide/ShortcutGuide.Ui/ShortcutGuideXAML/App.xaml.cs#L93-L113
[Native-Datenwurzel]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/common/SettingsAPI/settings_helpers.cpp#L14-L25
[Managed-Datenwurzel]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/settings-ui/Settings.UI.Library/SettingPath.cs#L34-L64
[Managed-Logs]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/common/ManagedCommon/Logger.cs#L75-L87
[ImageResizer-Daten]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ui/Properties/Settings.cs#L65
[Explorer-Manifest]: https://github.com/microsoft/PowerToys/blob/a00b2bce7403f0a48efe5cbb6671074e01f27824/src/modules/imageresizer/ImageResizerContextMenu/AppxManifest.xml#L38-L48
