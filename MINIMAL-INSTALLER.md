# PowerToys – minimierter Installer

Dieser Branch basiert auf Microsofts offiziellem Preview-Tag `v0.102.2883.0`
(`6b8238253ace26851eaf3b5784dd7c6181cf0267`, veröffentlicht am 16. Oktober 2026).
Die Produktversion `0.102.2883.0` wird unverändert aus diesem Release übernommen;
der interne Updatekanal bleibt `private`. Der Microsoft-Tag ist weiterhin eine Preview.

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
Zusätzlich verweigert die gemeinsame Advanced-Paste-Engine alle KI-Anbieter, einschließlich
lokaler Modelle. Die neue Advanced-Paste-CLI und die PATH-Shims werden nicht installiert.
Die neu hinzugekommenen Mausmodule CursorHide und Mouse Button Lock sind nicht ausgewählt.
ZoomIts neue Offline-Diktierfunktion bleibt gemäß Upstream standardmäßig ausgeschaltet;
sie kann vom Benutzer aktiviert werden und verwendet dann das Mikrofon.

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

Das Skript verwendet die zum oben genannten Microsoft-Release gehörende Version, stellt
Abhängigkeiten wieder her, baut die Solution ohne Tests, baut die Diagnosewerkzeuge, filtert
nicht ausgewählte Module und erzeugt einen deutsch lokalisierten Per-User-MSI.

Nur Filter und Installer erneut ausführen:

```powershell
tools\build\build-minimal-installer.ps1 -SkipSolutionBuild
```

Ergebnis: `installer/PowerToysSetupVNext/<Platform>/<Configuration>/UserSetup/*.msi`.

Die Pipeline verwendet den ignorierten Paketcache `.build-cache/nuget` und erzwingt dessen
Wiederherstellung, damit Restore und Kompilierung dieselben vorhandenen Pakete verwenden.

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
`import-german-localization.ps1` aus dem signierten Microsoft-Build `v0.102.2883.0` extrahiert und
auf die Ressourcenschlüssel desselben Quellstands übertragen. Dabei werden ausdrücklich keine
fremden PRI- oder Satelliten-Binärdateien kopiert; XAML und Assembly-Versionen bleiben konsistent.

Farbauswahl und Textextraktor verwenden seit diesem Update WinUI-RESW/PRI statt WPF-Satelliten.
Beim Aktualisieren der Microsoft-Basis müssen die deutschen Quellen mit einem möglichst passenden
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
