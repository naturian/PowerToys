# PowerToys – minimierter Installer

Dieser Branch basiert direkt auf dem aktuellen `origin/main` von Microsoft PowerToys. Die
Versionierung bleibt unverändert aus `src/Version.props`; die Minimal-Pipeline setzt keine
künstliche Release-Version.

Der erzeugte MSI enthält diese 16 Modulgruppen:

| Modul | Interner Schlüssel |
|---|---|
| FancyZones | `FancyZones` |
| Always on Top | `AlwaysOnTop` |
| Zuschneiden und Sperren | `CropAndLock` |
| Textextraktor | `TextExtractor` / `PowerOCR` |
| Arbeitsbereiche | `Workspaces` |
| Bildgrößenänderung | `ImageResizer` |
| File Locksmith | `FileLocksmith` |
| PowerRename | `PowerRename` |
| Vorschau | `Peek` |
| Farbauswahl | `ColorPicker` |
| Bildschirmlineal | `ScreenRuler` / `MeasureTool` |
| Bildschirmsteuerung | `PowerDisplay` |
| Automatischer Hell-/Dunkelmodus | `LightSwitch` |
| Mausdienstprogramme | `MouseUtils` |
| Window Hopper | `WindowHopper` / `AltWindowCycle` |
| Erweitertes Einfügen | `AdvancedPaste` |

`MouseUtils` umfasst Cursor Wrap, Find My Mouse, Mouse Highlighter, Mouse Jump und Mouse
Pointer Crosshairs. Nicht ausgewählte Module werden vor dem WiX-Harvest aus dem Build-Output
entfernt und nicht installiert.

In Erweitertes Einfügen ist „Paste with AI“ dauerhaft gesperrt.
Auch bestehende oder manuell geänderte Einstellungen können die Funktion nicht aktivieren.

## Modulauswahl

Die Auswahl steht in
`installer/PowerToysSetupVNext/selected-modules.txt`. Die zentrale Zuordnung liegt in
`installer/PowerToysSetupVNext/Modules-Database.ps1`.

```text
selected-modules.txt ──▶ Configure-Modules.ps1 ──▶ Runner-Ladeliste
                                               ├─▶ Settings-Dashboard
                                               └─▶ WiX-Komponentengruppen
Modules-Database.ps1 ──▶ filter-minimal-modules.ps1 ──▶ bereinigter Build-Output
```

Nach einer Änderung an `selected-modules.txt` genügt ein neuer Build. `CmdPal`, `CmdNotFound`,
`ZoomIt` und `Run` sind in der Datenbank bewusst als nicht baubar markiert, weil ihre
Paketierung noch nicht in die Minimal-Pipeline integriert ist.

## Build

Aus dem Repo-Wurzelverzeichnis:

```powershell
tools\build\build-minimal-installer.ps1
```

Das Skript verwendet die Version des ausgecheckten Microsoft-`main`, stellt Abhängigkeiten
wieder her, baut die Solution ohne Tests, baut die Diagnosewerkzeuge, filtert nicht ausgewählte
Module und erzeugt einen englischen Per-User-MSI.

Nur Filter und Installer erneut ausführen:

```powershell
tools\build\build-minimal-installer.ps1 -SkipSolutionBuild
```

Ergebnis: `installer/PowerToysSetupVNext/<Platform>/<Configuration>/UserSetup/*.msi`.

Voraussetzungen entsprechen dem Upstream-Repository: Visual Studio 2022 17.4+ oder Visual
Studio 2026 mit C++-Desktop-Workload, passende Windows- und .NET-SDKs sowie initialisierte
Submodule.

## Technischer Ausschluss

Der VNext-Installer harvestet den gemeinsamen Release-Ausgabeordner. Daher reichen entfernte
WiX-Referenzen allein nicht:

1. `filter-minimal-modules.ps1` entfernt Dateien und Modulordner nicht ausgewählter Utilities.
2. `Product.wxs` referenziert nur Infrastruktur und ausgewählte Modulgruppen.
3. `PowerToysInstallerVNext.wixproj` kompiliert nur die dafür benötigten `.wxs`-Dateien.
4. `src/runner/main.cpp` lädt nur paketierte Modul-DLLs.
5. Settings-Dashboard und Navigation zeigen nur installierte Bereiche.

Gemeinsam benötigte Settings-Abhängigkeiten bleiben erhalten. Peek aktiviert automatisch die
Monaco-/File-Explorer-Preview-Komponentengruppen.

## Lokalisierung

Der Quellcode-Build ist standardmäßig Englisch. Das vorhandene
`apply-german-localization.ps1` kann Ressourcen aus einem offiziellen Paket überlagern. Diese
Ressourcen müssen binär zur ausgecheckten Quelle passen. Für einen beliebigen `main`-Commit ohne
passendes offizielles Paket darf kein älteres Release-Overlay verwendet werden.

## Wichtige Dateien

- `installer/PowerToysSetupVNext/selected-modules.txt` – aktive Auswahl
- `installer/PowerToysSetupVNext/Modules-Database.ps1` – zentrale Modulmetadaten
- `installer/PowerToysSetupVNext/Configure-Modules.ps1` – Generator
- `installer/PowerToysSetupVNext/filter-minimal-modules.ps1` – Output-Filter
- `tools/build/build-minimal-installer.ps1` – Gesamt-Pipeline
