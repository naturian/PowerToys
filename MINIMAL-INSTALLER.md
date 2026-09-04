# PowerToys – minimierter Installer

Dieser Branch basiert auf Microsoft-`main`-Commit
`103d376c0a987cf350d4594bb3f8d71282fddfd6`. Dessen offizieller CI-Build
`PowerToys CI_2609.02003` wird mit Microsofts eigenem Release-Train-Schema als
`0.101.2453.0` paketiert. Es wird keine künstliche `0.102` gesetzt; der interne
Updatekanal bleibt `private`.

Der erzeugte MSI enthält diese 20 Modulgruppen:

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
| New+ | `NewPlus` |
| ZoomIt | `ZoomIt` |
| Grab and Move | `GrabAndMove` |
| Shortcut Guide | `ShortcutGuide` |

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
                                               ├─▶ WiX-Komponentengruppen
                                               └─▶ WiX-Quelldateien
Modules-Database.ps1 ──▶ filter-minimal-modules.ps1 ──▶ bereinigter Build-Output
```

Nach einer Änderung an `selected-modules.txt` genügt ein neuer Build. `CmdPal`, `CmdNotFound`
und `Run` sind in der Datenbank bewusst als nicht baubar markiert, weil ihre
Paketierung noch nicht in die Minimal-Pipeline integriert ist.

## Build

Aus dem Repo-Wurzelverzeichnis:

```powershell
tools\build\build-minimal-installer.ps1
```

Das Skript verwendet die zum oben genannten Microsoft-`main`-Build gehörende Version, stellt
Abhängigkeiten wieder her, baut die Solution ohne Tests, baut die Diagnosewerkzeuge, filtert
nicht ausgewählte Module und erzeugt einen deutsch lokalisierten Per-User-MSI.

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

Der öffentliche Quellcode enthält standardmäßig nur englische PowerToys-Ressourcen. Für diesen
Firmen-Build sind vollständige `de-DE`-RESW/RESX-Dateien eingecheckt. Sie wurden mit
`import-german-localization.ps1` aus dem signierten Microsoft-Build `v0.101.2432.0` extrahiert und
auf die Ressourcenschlüssel des aktuellen Main-Stands übertragen. Dabei werden ausdrücklich keine
fremden PRI- oder Satelliten-Binärdateien kopiert; XAML und Assembly-Versionen bleiben konsistent.

Beim Aktualisieren des Main-Stands müssen die deutschen Quellen mit einem möglichst passenden
offiziellen Paket neu importiert und anschließend geprüft werden:

```powershell
installer\PowerToysSetupVNext\import-german-localization.ps1 -OfficialRoot <extrahiertes PowerToys-Verzeichnis>
tools\build\test-minimal-release.ps1
```

Die Build-Pipeline bricht ab, sobald ein deutscher Schlüssel fehlt. Nach dem Kompilieren prüft sie
außerdem die tatsächlich erzeugten PRI-Dateien und die WPF-Satellitenassemblies.

## Wichtige Dateien

- `installer/PowerToysSetupVNext/selected-modules.txt` – aktive Auswahl
- `installer/PowerToysSetupVNext/Modules-Database.ps1` – zentrale Modulmetadaten
- `installer/PowerToysSetupVNext/Configure-Modules.ps1` – Generator
- `installer/PowerToysSetupVNext/filter-minimal-modules.ps1` – Output-Filter
- `installer/PowerToysSetupVNext/import-german-localization.ps1` – sichere Aktualisierung der deutschen Quellen
- `tools/build/build-minimal-installer.ps1` – Gesamt-Pipeline
- `tools/build/test-minimal-release.ps1` – Release- und Lokalisierungsregressionen
