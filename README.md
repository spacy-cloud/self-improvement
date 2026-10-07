# Selbstverbesserungsapp (Arbeitstitel)

Gruppenprojekt LF10a (Benutzerschnittstellen gestalten und entwickeln), Team IA24.

Lokale Fitness- und Habit-App für Android, umgesetzt mit Flutter. Alle Daten bleiben auf dem Gerät (lokales Profil, kein Cloud-Konto in V1).

Der App-Name steht noch nicht fest und wird im Code als eine Konstante geführt (`AppConfig.appName`, aktuell „App-Name“).

## Projektstand

| Bereich | Stand |
|---|---|
| Design | Freigegeben (V1, 02.10.2026) |
| Umsetzung | Android V1 im Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51): Kern und alle fünf Module sind umgesetzt, der Integrationsbranch `feature/BS-51-android-v1` ist am 2026-10-04 mit PR 2 (Merge-Commit `dfe560b`) in `main` gemergt. Die Funktionen von v0.2.0 (Jira-Epic [BS-98](https://spacy-cloud.atlassian.net/browse/BS-98)) sind in einer Kette von Pull Requests gegen `dev` umgesetzt (Reihenfolge in PR 4): Ziele heute, Tage blättern, Heute abhaken, Plus-Menü nach Zielen, Erinnerung je Aufgabe, Schritte aus Health (nur Android), Seite „Über die App“, Datenvertrag 2 (Schema 2, Backup-Format 2) und die Korrekturen aus dem iOS-Test; die Versionsanhebung auf 0.2.0 folgt als letzter Pull Request. Stand der Anforderungen und Abnahmefälle mit Nachweisen und offenen Punkten: [docs/requirements-matrix.md](docs/requirements-matrix.md) |
| Tests | 8493 Host-Tests lokal bestanden (Stand 2026-10-07, Code-Stand `577a853`), Analyse und Format ohne Befund; das CI-Ergebnis steht in den Pull Requests (am 2026-10-07 waren die Prüfungen aller 20 Pull Requests der Kette grün). Auf einem Gerät ist von v0.2.0 nichts geprüft; vom Stand v0.1.0 wurden auf einem Samsung S25 der Start eines Debug-Builds und, laut Rückmeldung, eine Benachrichtigung gesehen, kein Funktionstest: Details und Grenzen in [docs/test-report.md](docs/test-report.md) |
| Abnahme | Das Projektteam hat die 35 Umsetzungs- und Befundtickets aus PR 2 (BS-53 bis BS-74, BS-77, BS-81 bis BS-92) am 2026-10-04 in Jira auf „Erledigt“ gesetzt; das ist die Entscheidung des Teams, keine unabhängige Prüfung. Die umgesetzten Tickets von v0.2.0 stehen in Jira auf „Wird überprüft“ (offen sind BS-101, die Freigabe des Entwurfs „Ziele heute“, BS-107, die Geräteprüfung dazu, und BS-114, die Entscheidung zum Querformat); ein unabhängiger Prüfer hat den Stand geprüft (Prüfzyklus 1: kein P0, zwei P1, zwölf P2, Behebung in einem eigenen Pull Request; Einzelheiten im Testbericht). Die Figma-Entwürfe von v0.2.0 sind noch nicht freigegeben, die Geräteprüfungen stehen aus ([Geräte-Checkliste](docs/geraete-checkliste-v0.2.0.md)). Nicht erledigt sind in Jira (Stand 2026-10-07) außerdem BS-47 (App-Name), BS-49 (Figma-Version), BS-51 (Epic), BS-52, BS-75, BS-76 und BS-78 bis BS-80 |
| iOS | Projektdateien vorbereitet; ein CI-Workflow (`ios-ipa.yml`, BS-95) baut eine unsignierte IPA, die der Tester per SideStore selbst signiert. Der Tester hat den Stand v0.1.0 am 2026-10-04 auf einem iPhone 15 Pro getestet (Rückmeldung in BS-96, nicht von uns nachvollzogen): keine blockierenden Fehler, drei Folgetickets ([BS-112](https://spacy-cloud.atlassian.net/browse/BS-112) Tastatur, [BS-113](https://spacy-cloud.atlassian.net/browse/BS-113) Texte, [BS-114](https://spacy-cloud.atlassian.net/browse/BS-114) Querformat), die v0.2.0 umsetzt (BS-112, BS-113) oder als Vorschlag entscheidet (BS-114). v0.2.0 ist auf keinem iPhone geprüft; VoiceOver, „Größerer Text“ und weitere iOS-Versionen sind nicht geprüft. Die Schritte aus Health gibt es nur unter Android |

## Dokumentation

- [Erste Tests](docs/erste-tests.md): App starten (Android Studio, Handy, CI-APK), Update von v0.1.0, Demo-Daten, Rundgang mit den neuen Funktionen
- [Geräte-Checkliste](docs/geraete-checkliste-v0.2.0.md): Prüfpunkte für das Samsung S25 und das iPhone (v0.2.0), Ergebnis je Punkt noch offen
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

## Lizenz

Der eigene Code und die Dokumentation stehen unter der [MIT-Lizenz](LICENSE) (Copyright Spacy.cloud). Mitgelieferte Fremdinhalte behalten ihre Lizenzen: die Schrift Inter (SIL Open Font License 1.1, Text in `assets/fonts/OFL.txt`), der Pfeil des App-Symbols aus den Material Icons (CC BY 4.0, Quelle und Namensnennung in [assets/branding/README.md](assets/branding/README.md)) und die Abhängigkeiten laut `pubspec.lock` (die Lizenzseite der App listet sie).

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

iOS: Der Workflow `.github/workflows/ios-ipa.yml` baut bei jedem Push auf `dev` (und per Hand) eine unsignierte IPA als Artefakt `ios-ipa-unsigned`; der Tester signiert sie mit SideStore selbst. Ein grüner Lauf ist kein Gerätetest.

APK-Dateien und Build-Ordner werden nicht eingecheckt. Eine Store-Veröffentlichung ist nicht Teil von V1.

## Mitwirken

- `main` ist die Produktion, `dev` die Entwicklung; Änderungen laufen über Feature-Branches und Pull Requests gegen `dev` (Entscheidung D-013 in [docs/implementation-decisions.md](docs/implementation-decisions.md)).
- Branch-Namen mit Jira-Key, z. B. `feature/BS-61-weight-flow` (BS-61 ist das Gewichtsticket).
- Code, Kommentare und Commit-Messages auf Englisch; Oberfläche und Dokumentation auf Deutsch.
- Keine echten Gesundheitsdaten, Zugangsdaten oder privaten Notizen in Code, Tests oder Dokumentation; Testdaten sind synthetisch.
