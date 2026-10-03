# Selbstverbesserungsapp (Arbeitstitel)

Gruppenprojekt LF10a (Benutzerschnittstellen gestalten und entwickeln), Team IA24.

Lokale Fitness- und Habit-App für Android, umgesetzt mit Flutter. Alle Daten bleiben auf dem Gerät (lokales Profil, kein Cloud-Konto in V1).

Der App-Name steht noch nicht fest und wird im Code als eine Konstante geführt (`AppConfig.appName`, aktuell „App-Name“).

## Projektstand

| Bereich | Stand |
|---|---|
| Design | Freigegeben (V1, 02.10.2026) |
| Umsetzung | In Arbeit: Android V1 im Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51); Fortschritt und Nachweise in [docs/requirements-matrix.md](docs/requirements-matrix.md) |
| iOS | Projektdateien vorbereitet, nicht gebaut und nicht getestet |

## Dokumentation

- [Design-Handoff](docs/design-handoff.md): Screens, Routen, Komponenten, Tokens, Barrierefreiheit
- [Implementierungsentscheidungen](docs/implementation-decisions.md): exakte Versionen, Entscheidungen, Umgebung
- [Anforderungsmatrix](docs/requirements-matrix.md): Jira → Anforderung → Umsetzung → Test → Status
- [Bekannte Grenzen](docs/known-limitations.md)
- Figma: [LF10-Desing-App](https://www.figma.com/design/K4IWQEjnzuNkRUzkq8JaKz/LF10-Desing-App)
- Jira: [BS-Board](https://spacy-cloud.atlassian.net/jira/software/projects/BS/boards/34)

## Technik

- Flutter / Dart, Zielplattform Android (iOS vorbereitet)
- `flutter_riverpod` (ohne Codegenerierung), Navigation mit `go_router`
- Lokale Datenhaltung mit SQLite über `drift`, Diagramme mit `fl_chart`, lokale Erinnerungen mit `flutter_local_notifications`
- JSON-Export/Import als Datei; keine Cloud, keine Konten, keine Telemetrie

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
flutter test integration_test        # Integrationstests (benötigt Gerät oder Emulator)
dart run tool/sync_app_name.dart     # native Anzeigenamen nach Änderung von AppConfig.appName angleichen
```

Die Continuous Integration (GitHub Actions, `.github/workflows/ci.yml`) führt Format-Check, Codegenerierung, Analyse, Tests, den Debug-APK-Build und die Integrationstests auf einem Android-Emulator aus.

APK-Dateien und Build-Ordner werden nicht eingecheckt. Eine Store-Veröffentlichung ist nicht Teil von V1.

## Mitwirken

- `main` ist der stabile Stand; Änderungen über Feature-Branches und Pull Requests.
- Branch-Namen mit Jira-Key, z. B. `feature/BS-61-weight-flow` (BS-61 ist das Gewichtsticket).
- Code, Kommentare und Commit-Messages auf Englisch; Oberfläche und Dokumentation auf Deutsch.
- Keine echten Gesundheitsdaten, Zugangsdaten oder privaten Notizen in Code, Tests oder Dokumentation; Testdaten sind synthetisch.
