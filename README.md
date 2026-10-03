# Selbstverbesserungsapp (Arbeitstitel)

Gruppenprojekt LF10a (Benutzerschnittstellen gestalten und entwickeln), Team IA24.

Lokale Fitness- und Habit-App für Android, umgesetzt mit Flutter. Alle Daten bleiben auf dem Gerät (lokales Profil, kein Cloud-Konto in V1).

Der App-Name steht noch nicht fest und wird im Code als eine Konstante geführt (`AppConfig.appName`, aktuell „App-Name“).

## Projektstand

| Bereich | Stand |
|---|---|
| Design | Freigegeben (V1, 02.10.2026) |
| Umsetzung | Android V1 im Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51): Kern und alle fünf Module sind umgesetzt, der Integrationsbranch `feature/BS-51-android-v1` liegt als Entwurfs-PR gegen `main`. Stand der Anforderungen und Abnahmefälle mit Nachweisen und offenen Punkten: [docs/requirements-matrix.md](docs/requirements-matrix.md) |
| Tests | 6472 Host-Tests lokal bestanden (Stand 2026-10-03, Code-Stand `873f9ff`), Analyse und Format ohne Befund; das CI-Ergebnis steht im Pull Request. Auf einem Gerät (Samsung S25) wurde bisher nur der Start eines Debug-Builds gesehen, kein Funktionstest: Details und Grenzen in [docs/test-report.md](docs/test-report.md) |
| Abnahme | Nicht abgenommen: Die Abnahme entscheidet das Team, kein Umsetzungsticket der V1 (BS-52 bis BS-92) ist auf „Erledigt“ |
| iOS | Projektdateien vorbereitet, nicht gebaut und nicht getestet |

## Dokumentation

- [Erste Tests](docs/erste-tests.md): App starten (Android Studio, Handy, CI-APK), Demo-Daten, Rundgang
- [Demo-Skript](docs/demo-script.md): 15-Minuten-Vorführung mit Vorbereitung, Ablauf, Fehlerplan und dem, was nicht behauptet wird
- [Emulator-Abläufe](docs/integration-tests.md): sieben Kernabläufe mit dem echten Produktionsstart (Emulator und Host), Ausführung und Grenzen
- [Testbericht](docs/test-report.md): ausgeführte Prüfungen mit Befehlen und Ergebnissen, Lastzahlen, was die CI-Jobs beweisen, was nicht getestet ist
- [Anforderungsmatrix](docs/requirements-matrix.md): Jira → Anforderung → Umsetzung → Test → Status, Abnahmefälle AT01 bis AT36, offene Punkte
- [Architektur](docs/architecture.md): Schichten, Verzeichnisse, Datenmodell, Commands, Start der App
- [Design-Handoff](docs/design-handoff.md): Screens, Routen, Komponenten, Tokens, Abweichungen vom Figma-Entwurf, Barrierefreiheit
- [Screen-Dokumente](docs/screens/): je Bereich Screens, Verhalten, Abweichungen, Tests und offene Punkte
- [Backup-Format](docs/backup-format.md): Aufbau und Prüfregeln der JSON-Sicherung
- [Implementierungsentscheidungen](docs/implementation-decisions.md): exakte Versionen, Entscheidungen, Umgebung
- [Bekannte Grenzen](docs/known-limitations.md)
- Figma: [LF10-Desing-App](https://www.figma.com/design/K4IWQEjnzuNkRUzkq8JaKz/LF10-Desing-App)
- Jira: [BS-Board](https://spacy-cloud.atlassian.net/jira/software/projects/BS/boards/34)

## Technik

- Flutter / Dart, Zielplattform Android ab API 26 (Android 8, `minSdk` 26; iOS vorbereitet)
- `flutter_riverpod` (ohne Codegenerierung), Navigation mit `go_router`
- Lokale Datenhaltung mit SQLite über `drift`, Diagramme mit `fl_chart`, lokale Erinnerungen mit `flutter_local_notifications`
- JSON-Export/Import als Datei; keine Cloud, keine Konten, keine Telemetrie
- App-Symbol: grüner Verlauf mit weißem Pfeil nach oben wie das Zeichen im Onboarding, adaptiv ab Android 8 und mit einfarbiger Ebene ab Android 13; Quelle und Lizenz in [assets/branding/README.md](assets/branding/README.md). Die iOS-Symbole sind nicht angepasst.

## Entwicklungsumgebung einrichten

Voraussetzungen: Flutter **3.47.6** (stable, Dart 3.13.5). Für Android-Builds zusätzlich Android SDK (API 36 oder die von Flutter geforderte Version) und JDK 17 oder 21.

```bash
flutter --version                    # muss 3.47.6 zeigen
flutter pub get                      # Abhängigkeiten laut pubspec.lock
dart run build_runner build          # erzeugt die Drift-Dateien (*.g.dart, nicht eingecheckt)
```

## Starten, bauen, testen

```bash
flutter run                          # auf verbundenem Android-Gerät oder Emulator
flutter build apk --debug            # Debug-APK: build/app/outputs/flutter-apk/app-debug.apk
dart format --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test                         # Unit-, Repository- und Widget-Tests (laufen auf dem Host)
flutter test integration_test --dart-define=WIPE_APP_DATA=yes   # Emulator-Abläufe; löschen die App-Daten des Geräts (siehe docs/integration-tests.md)
dart run tool/sync_app_name.dart     # native Anzeigenamen nach Änderung von AppConfig.appName angleichen
dart run tool/at_coverage.dart       # welche Tests welchen Abnahmefall (AT01 bis AT36) benennen
flutter test test/tool/demo_backup_test.dart   # erzeugt die Demo-Sicherung build/demo-backup/demo-daten-90-tage.json
```

Die Continuous Integration (GitHub Actions, `.github/workflows/ci.yml`) führt Format-Check, Codegenerierung, Analyse und Tests aus, baut ein Debug-APK und ein Release-APK (mit Debug-Schlüssel signiert, nur für manuelle Leistungsproben) und führt die Integrationstests auf einem Android-Emulator aus. Sie veröffentlicht die Artefakte `debug-apk`, `release-apk`, `load-test-results` und `demo-backup`.

APK-Dateien und Build-Ordner werden nicht eingecheckt. Eine Store-Veröffentlichung ist nicht Teil von V1.

## Mitwirken

- `main` ist der stabile Stand; Änderungen über Feature-Branches und Pull Requests.
- Branch-Namen mit Jira-Key, z. B. `feature/BS-61-weight-flow` (BS-61 ist das Gewichtsticket).
- Code, Kommentare und Commit-Messages auf Englisch; Oberfläche und Dokumentation auf Deutsch.
- Keine echten Gesundheitsdaten, Zugangsdaten oder privaten Notizen in Code, Tests oder Dokumentation; Testdaten sind synthetisch.
