# Portable PowerToys-Module

Experimentelle Windows-x64-Pakete auf Basis **0.102.3001.0**, Branch `codex/portable-first-modules` im Fork `naturian/PowerToys`. Der Minimal-Installer und sein Release werden durch diese Pakete nicht ersetzt.

## Benutzung

Das gesamte ZIP in einen beschreibbaren Ordner entpacken. Die Dateien `portable-mode`, `portable-module.json` und alle mitgelieferten Laufzeitdateien gehören zum Paket.

| Paket | Einstiegspunkt | Bedienung |
| --- | --- | --- |
| FancyZones | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, originale Einstellungen und Layout-Editor |
| Farbwähler | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, originale Einstellungen und Farbeditor |
| Textextraktor | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, originale Einstellungen und Texterfassung |
| Bildgrößenänderung | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, originale Größen- und Kodierungseinstellungen, Dateiauswahl |
| Power Display | `PowerToys.PowerDisplay.exe` | Bereits vorhandenes Tray-Menü; „Einstellungen“ öffnet die originale Einstellungsseite |
| Immer im Vordergrund | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, originale Regeln und Tastenkürzel zum Anheften von Fenstern |
| File Locksmith / Dateischlosser | `PowerToys.Portable.exe` | Datei- und Ordnerauswahl, Anzeige sperrender Prozesse und originale Einstellungen |
| Peek | `PowerToys.Portable.exe` | Datei- und Ordnerauswahl; konfiguriertes Tastenkürzel öffnet die Explorer-Auswahl |
| Zuschneiden und Sperren | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, Miniaturansicht, Einbetten und Bildschirmfoto über eigene Tastenkürzel |
| Erweitertes Einfügen | `PowerToys.Portable.exe` | Eigene Tray-Steuerung, normale Einfügeformate und sichere Zusatzaktionen; KI bleibt gesperrt |

Die Einstellungsoberfläche zeigt ausschließlich das enthaltene Modul. Sie startet keinen installierten PowerToys-Runner. Ein Doppelklick auf das neue Tray-Symbol öffnet die Einstellungen; das Kontextmenü bietet zusätzlich das Werkzeug selbst und „Beenden“. Beim Schließen der Einstellungen bleibt der Portable-Host im Tray. Power Display behält sein vorhandenes Tray einschließlich Helligkeitssteuerung. „Einstellungen“ innerhalb eines Werkzeugs öffnet ebenfalls die lokale grafische Oberfläche.

Immer im Vordergrund verwendet standardmäßig **Win+Strg+T**. Zuschneiden und Sperren verwendet **Win+Strg+Umschalt+T/R/S** für Miniaturansicht, Einbetten und Bildschirmfoto. Peek verwendet standardmäßig **Strg+Leertaste** für ausgewählte Explorer-Dateien; alternativ die Datei- oder Ordnerauswahl im Tray verwenden. Die originalen Einstellungsseiten ändern diese Kürzel lokal.

File Locksmith scannt nur ausdrücklich ausgewählte Dateien oder Ordner. Prozesse werden erst auf ausdrückliche Betätigung von „Task beenden“ beendet. Die vorhandene Schaltfläche zum Neustart als Administrator bleibt eine ausdrückliche Benutzeraktion. Advanced Paste registriert die vier grundlegenden Einfügekürzel und sichtbare Nicht-KI-Zusatzaktionen; KI-, Grammatik-, Coaching- und benutzerdefinierte KI-Kürzel bleiben gesperrt. Auch KI-Modellvorbereitung und die Migration gespeicherter KI-Zugangsdaten sind im Portable-Modus ausgeschlossen.

Einstellungen werden automatisch gespeichert. Das jeweilige Modul ist in neuen Paketen eingeschaltet, soweit keine GPO es sperrt. Eigene Daten, Farbverlauf, Layouts und Protokolle bleiben unter `Data/Microsoft/PowerToys`. Diesen Unterordner zum Sichern mitnehmen. Vor Verschieben oder Löschen alle Werkzeuge über ihre Tray-Menüs beenden. Laufende Bildverarbeitung wird beim Beenden nicht gewaltsam abgebrochen.

## Grenzen

- Keine Installation, kein Autostart, keine Explorer-Menüregistrierung und kein automatischer Updater. Neue Pakete werden manuell entpackt. Die vorhandenen GPO-Sperren bleiben wirksam.
- Installiertes FancyZones vor dem Start ausschalten. Zwei Instanzen können dieselben Fenster und Tastenkürzel beeinflussen. Farbwähler und Textextraktor können ebenfalls mit globalen Tastenkürzeln anderer Programme kollidieren.
- Textextraktor benötigt eine bereits vorhandene Windows-OCR-Sprache. Power Display benötigt passende Monitorunterstützung; Helligkeits- und Profiländerungen wirken auf die Hardware.
- Peek benötigt für browsergestützte Vorschauen eine vorhandene Microsoft-Edge-WebView2-Laufzeit. Zusätzliche Vorschauformate hängen von den vorhandenen Windows-Vorschauhandlern ab. Das Paket installiert keine Vorschauhandler.
- Das ist kein System zur spurlosen Ausführung: Windows verwaltet weiterhin Zwischenablage, Ausführungsverlauf und weitere Betriebssystemdaten.
- Die Original-Einstellungsanwendung wird als gemeinsame Abhängigkeit mitgeliefert. Dadurch sind die Pakete größer als die ersten Prototypen. Andere Werkzeugprogramme werden nicht mitgeliefert oder gestartet.
- Ohne erhöhte Rechte lassen sich erhöhte Fenster teilweise nicht steuern. Die Portable-Ausgabe fordert keine Erhöhung an.
- Unsignierte Versuchsbuilds, keine Firmenfreigabe oder Zertifizierung. Umfang der tatsächlich ausgeführten Tests steht in den Release-Hinweisen.

## Build und Prüfung

Aus dem Repository-Stamm in PowerShell:

```powershell
.\tools\portable\build-portable.ps1 -OutputRoot G:\PowerToys\artifacts\portable\my-build
```

Optional `-Modules FancyZones,ColorPicker` verwenden. Der Builder nutzt die normalen Repository-Buildskripte, prüft Abhängigkeiten, publiziert die .NET-/Windows-App-SDK-Laufzeiten und erzeugt pro Paket ein `package-manifest.json` mit Dateigrößen und SHA-256. Ein vorhandener Ausgabeordner erfordert ausdrücklich `-Resume`; Release-Pakete sollten aus einem frischen Ordner stammen.

Die isolierten Tests liegen unter `tools/portable/tests`. Zuerst mit `tools/build/build.ps1` bauen, danach mit Visual Studio `vstest.console.exe` ausführen. Sie prüfen Datenpfade, Fehler ohne Rückfall ins installierte Profil, Ereignisnamen und feste Paketidentitäten einschließlich mutierter Eingaben. `test-portable-startup.ps1` prüft die echten Pakete auf geöffnete Einstellungsseiten, Zweitstart und vollständiges Beenden, bei FancyZones auch unmittelbar nach dem Editorstart. `package-portable.ps1` erzeugt und verifiziert ZIP-Dateien mit frischen Profilen; Testdaten werden nicht übernommen. Hardware- und Mehrmonitorprüfungen sind getrennt auszuweisen.

## Umsetzung

`src/common/Portable/PortableData.cs` und `src/common/utils/portable_mode.h` aktivieren die lokalen Datenpfade ausschließlich bei vorhandener Markerdatei. Schreibfehler führen zum Abbruch. Der installierte Modus behält seine bisherigen Pfade.

`src/settings-ui/Settings.UI/Portable` enthält die Tray-Steuerung und die Verbindung zu den vorhandenen Einstellungsseiten. `portable-module.json` wählt nur eine der zehn fest definierten Paketidentitäten; es kann keine Programm- oder Datenpfade vorgeben. Instanzsperren und Ereignisse sind nach Paketordner getrennt. Einstellungen anderer Module und globale Runner-Befehle werden nicht weitergeleitet. Telemetrie bleibt im Portable-Modus aus. Der Dateipfadparser für File Locksmith und Peek wird direkt aus derselben Quelldatei in den Tests und in beiden Programmen verwendet.

Store- und WinGet-Veröffentlichungen sind auf das Microsoft-Repository begrenzt. Portable-Releases im Fork werden separat als Vorabversionen veröffentlicht.
