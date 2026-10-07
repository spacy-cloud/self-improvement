# Testbericht

Dokumentiert tatsächlich ausgeführte Prüfungen mit Umgebung und Ergebnis. Nicht ausgeführte oder nicht prüfbare Punkte sind als solche gekennzeichnet; ein gestarteter CI-Lauf gilt nicht als bestanden. Ergebnisse von CI-Läufen stehen im Pull Request, nicht in dieser Datei (Abschnitt 5 sagt, was die Jobs beweisen und was nicht). Welche Anforderung oder welcher Abnahmefall durch welche Tests belegt ist, steht in der [Anforderungsmatrix](requirements-matrix.md).

## 1. Umgebung

| Aspekt | Wert |
|---|---|
| Datum der Läufe | 2026-10-03 |
| Code-Stand | Commit `93ee81f` auf dem Integrationsbranch `feature/BS-51-android-v1` (Stand nach Prüfzyklus 3); spätere Commits ändern nur Dateien unter `docs/` und `README.md` |
| Toolchain | Flutter 3.47.6 (stable, Framework-Revision `5fc346839b`), Dart 3.13.5, DevTools 2.60.0 (Ausgabe von `flutter --version`; siehe [implementation-decisions.md](implementation-decisions.md)) |
| Host | Linux x86_64 |
| Host-Tests | `flutter test` mit echter In-Memory-SQLite-Datenbank (Drift), fester Uhr `FakeClock` (Zone Europa/Berlin, 2026-10-03), Fakes für Erinnerungs-Plattform, Teilen und Dateiauswahl, simulierter Textskala und Tastatur; nur synthetische Daten |
| Lokales Android-Ziel | In der automatischen Entwicklungsumgebung keines (kein Android-SDK, kein Gerät, kein Emulator); der Projektinhaber startet die App lokal in Android Studio und hat sie auf einem Samsung S25 (Debug-Build) gestartet |
| CI | GitHub Actions, siehe `.github/workflows/ci.yml` und Abschnitt 5 |

## 2. Gesamtlauf der Host-Tests

Befehl, ausgeführt nach `flutter pub get` und `dart run build_runner build`:

```bash
flutter test --no-pub
```

Ergebnis: **6485 Tests bestanden, 0 übersprungen, 0 fehlgeschlagen**, Exit-Code 0, Laufzeit laut Reporter 2:42 Minuten (Lauf mit `--reporter json`, damit sich die Tests je Verzeichnis zählen lassen). Sie verteilen sich auf 277 Testdateien; eine weitere Datei (`test/features/focus/presentation/focus_visual_test.dart`) registriert nur mit der Umgebungsvariable `FOCUS_UI_PNG=1` einen Test.

### Ergebnis je Bereich

Die Zeilen stammen aus dem Gesamtlauf und sind nach dem Verzeichnis der Testdatei aufgeteilt; jedes Verzeichnis lässt sich einzeln mit `flutter test --no-pub <Verzeichnis>` wiederholen. Die Summe der Zeilen ist 6485 und stimmt mit dem Gesamtlauf überein.

| Bereich | Verzeichnis | Tests |
|---|---|---:|
| App (Start, Router, Shell, Fehlerbehandlung, Verdrahtung) | `test/app` | 459 |
| Analyse-Engine | `test/core/analysis` | 280 |
| Backup (Format, Validierung, Import, Export, Zurücksetzen) | `test/core/backup` | 717 |
| Bootstrap | `test/core/bootstrap` | 8 |
| Commands (Runner, Undo, Befehls-IDs) | `test/core/commands` | 20 |
| Konfiguration | `test/core/config` | 4 |
| Dashboard-Regeln | `test/core/dashboard` | 10 |
| Datenbank-Schema | `test/core/database` | 31 |
| Design-System (Tokens, Kontrast, Komponenten, Golden-Tests) | `test/core/design` | 840 |
| Feedback | `test/core/feedback` | 6 |
| Ziele, Snapshots, XP-Projektion, Streak | `test/core/goals` | 188 |
| Module | `test/core/modules` | 23 |
| Benachrichtigungen (Planer, Service, Plattform-Adapter) | `test/core/notifications` | 458 |
| Onboarding-Repository | `test/core/onboarding` | 7 |
| Profil | `test/core/profile` | 11 |
| Einstellungen | `test/core/settings` | 4 |
| Zeit | `test/core/time` | 12 |
| Analyse (Oberfläche) | `test/features/analysis` | 123 |
| Körper (Gewicht und Schritte) | `test/features/body` | 239 |
| Dashboard | `test/features/dashboard` | 139 |
| Fokus und Workouts | `test/features/focus` | 656 |
| Gamification | `test/features/gamification` | 173 |
| Modulverwaltung | `test/features/modules` | 42 |
| Ernährung (Wasser und Mahlzeiten) | `test/features/nutrition` | 612 |
| Onboarding | `test/features/onboarding` | 97 |
| Profil und Ziele | `test/features/profile` | 209 |
| Erinnerungen (Oberfläche) | `test/features/reminders` | 94 |
| Einstellungen, Daten und Sicherung | `test/features/settings` | 177 |
| Aufgaben und Gewohnheiten | `test/features/tasks` | 808 |
| Lasttest und Listen-Scroll | `test/performance` | 7 |
| Plattform (Manifest-Prüfungen) | `test/platform` | 4 |
| Gemeinsame Hilfen (Datum, Zahlen) | `test/shared` | 24 |
| Test-Hilfen | `test/support` | 2 |
| Demo-Backup-Erzeuger | `test/tool` | 1 |
| **Summe** | | **6485** |

Die Tests je Abnahmefall (AT01 bis AT36) zählt `dart run tool/at_coverage.dart`; die Auswertung steht in Abschnitt 3 der Anforderungsmatrix.

## 3. Statische Prüfungen

| Prüfung | Befehl | Ergebnis |
|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test tool integration_test` | „Formatted 783 files (0 changed)“, Exit-Code 0 (lokal nach der Codegenerierung, daher eine erzeugte Datei mehr als in der CI) |
| Statische Analyse | `flutter analyze --no-pub` | „No issues found!“, Exit-Code 0 |
| Native Anzeigenamen | `dart run tool/sync_app_name.dart --check` | „Native display names are in sync („App-Name“)“, Exit-Code 0 |

## 4. Lasttest (Host und CI-Runner, kein Gerät)

Der Lasttest (`test/performance/load_test.dart`, Ticket BS-75, Abnahmefall AT36) schreibt 10.582 synthetische Datensätze über drei Jahre direkt in eine In-Memory-SQLite-Datenbank, baut die gemeinsamen Projektionen einmal neu auf (das Szenario eines Imports) und misst die Alltagsoperationen in dieser Größe. **Alle Werte sind Messungen eines Linux-Rechners (Host und CI-Runner) mit In-Memory-Datenbank; keine einzige ist auf einem Gerät gemessen.**

| Messung | CI-Runner (Lauf 37136052363) | Entwicklungsrechner (dieser Stand) |
|---|---:|---:|
| Synthetische Datensätze | 10.582 | 10.582 |
| Einfügen der Datensätze | nicht übernommen | 233 ms |
| Neuaufbau der Projektionen über alle Tage (drei Jahre) | 2.199 ms | 1.298 ms |
| Gewichts-Commit, Median von 20 | 10 ms | 5 ms |
| Gewichts-Commit, Maximum | 21 ms | 14 ms |
| Erster Wert Gesamt-XP | 3 ms | 1 ms |
| Erster Wert Tagesstatus heute | 237 ms | 122 ms |
| Erster Wert Schritteverlauf (90 Tage) | unter 250 ms | 0 ms |
| Erster Wert Analysebericht | 70 ms | 45 ms |
| Erster Wert Streak | 0 ms | 0 ms |
| Backup-Export mit Selbstprüfung | 406 ms | 329 ms |
| Größe der Sicherung | 4.526.520 Byte | 4.907.497 Byte |

Die CI-Spalte stammt aus dem Artefakt `load-test-results` des genannten Laufs (für den Schritteverlauf liegt nur die Obergrenze vor). Die Spalte „Entwicklungsrechner“ stammt aus einem isolierten Lauf `flutter test test/performance`, der `build/load-test-results.json` schreibt; die Werte schwanken von Lauf zu Lauf.

Die Schwellen des Tests sind absichtlich großzügige Regressionsgrenzen für einen CI-Rechner: Projektions-Neuaufbau unter 120 s, Gewichts-Commit Median unter 300 ms und Maximum unter 2 s, jeder erste Wert unter 5 s, Sicherung unter 10 MiB und beim Import wiederherstellbar. Alle Schwellen wurden eingehalten (der Test ist grün).

Planungsziele für ein **Gerät**, an denen die Werte gemessen werden müssen: Start etwa 3 s, einfacher Commit 300 ms, Scrollen mit 60 Hz. **Auf einem Gerät nicht gemessen.** Der Test `test/performance/list_scroll_test.dart` prüft für 3.000 Messungen nur, dass die Zeilen lazy gebaut werden und das Ende erreichbar ist, nicht die Bildrate.

## 5. CI-Jobs: was sie beweisen und was nicht

Definiert in `.github/workflows/ci.yml`; Ergebnis der Läufe: siehe Pull Request.

| Job | Was der Job ausführt | Beweist | Beweist nicht |
|---|---|---|---|
| Format, analyze, test | Lockfile erzwungen (`flutter pub get --enforce-lockfile`), Format-Check, Drift-Codegenerierung, Prüfung der nativen Anzeigenamen, `flutter analyze --no-pub`, `flutter test --no-pub`; lädt `load-test-results` und `demo-backup` als Artefakte hoch | Dasselbe wie die lokalen Läufe in den Abschnitten 2 bis 4, auf sauberer Umgebung mit der gesperrten Toolchain | Verhalten auf Android |
| Android debug APK | `flutter build apk --debug`, danach `flutter build apk --release` (mit dem Debug-Schlüssel signiert, nur für manuelle Leistungsproben); lädt `debug-apk` und `release-apk` hoch | Die App lässt sich für Android bauen und verpacken | Dass die APKs starten: Der Job startet keine; das Release-Paket wurde nirgends gestartet |
| Android emulator integration tests (API 34) | `flutter test integration_test --dart-define=WIPE_APP_DATA=yes` auf einem Emulator (x86_64, Google APIs, Profil Pixel 6, Animationen aus): `integration_test/app_smoke_test.dart` (In-Memory-Datenbank, Test-Ersatz für Benachrichtigungen) und `integration_test/app_flows_test.dart` (der echte Produktionsstart, siehe [integration-tests.md](integration-tests.md)) | Der Dart-Code läuft auf einem Android-Emulator. Smoke-Test: Start hinter dem Onboarding, vier Tabs, Plus-Menü. Abläufe mit dem echten Start (echte SQLite-Datei im App-Support-Verzeichnis, echte Zeitzonenerkennung, echtes Benachrichtigungs-Plugin): F1 Erststart und Onboarding (AT01), F2 Gewicht mit Neustart (AT02, AT06), F3 Wasser mit Rückgängig (AT10), F4 Aufgabe abschließen (AT13), F5 Fokus mit Pause und Neustart mitten in der Sitzung (AT16), F6 Zurücksetzen (AT32), F7 Datenbankdatei, Gerätezone und Initialisierung der Erinnerungs-Plattform | Systemdialoge, Teilen-Menü und Dateiauswahl, TalkBack, echte Benachrichtigungszustellung, Leistung, ein echtes Gerät, den Release-Build; die Abläufe laufen bei ausgeschalteten Animationen und auf einem frischen Emulator |

Das CI-Ergebnis des Emulator-Jobs steht im Pull Request. Die Abläufe löschen die App-Datenbank des Zielgeräts und starten deshalb nur mit der ausdrücklichen Bestätigung `--dart-define=WIPE_APP_DATA=yes` (die CI übergibt sie); sie gehören nicht auf ein Handy mit echten Daten.

Zusätzlich lief die App am 2026-10-03 manuell auf einem Android-Emulator des Projektteams (Debug-Build aus Android Studio): Start mit dem Produktionspfad und Anzeige des Dashboards mit leeren Zuständen. Am 2026-10-04 lief ein Debug-Build (arm64) auf einem Samsung S25 und zeigte die Willkommensseite des Onboardings; ein erster Startversuch auf dem S25 war abgestürzt, die Ursache ist nicht untersucht (kein Log vorhanden). Laut Rückmeldung funktioniert auf dem S25 auch eine Benachrichtigung; es wurde nicht genauer getestet, ein Protokoll gibt es nicht. Weitere manuelle Prüfungen (Rundgang in [erste-tests.md](erste-tests.md)) sind offen.

## 6. Nicht getestet

Nicht auf einem Gerät oder mit der echten Plattform geprüft (in der automatischen Entwicklungsumgebung gibt es kein Android-SDK; Emulator-Läufe stammen aus der CI und aus dem einen manuellen Lauf des Projektteams); die jeweils vorhandenen Stellvertreter stehen in der [Anforderungsmatrix](requirements-matrix.md), Abschnitt 6:

- **Echtes Gerät:** Gefühl bei Start und Scrollen, Leistung, Speicher. Gesehen wurden der Start eines Debug-Builds auf einem Samsung S25 (2026-10-04, Willkommensseite des Onboardings) und, laut Rückmeldung, eine Benachrichtigung (nicht genauer getestet).
- **TalkBack** und die Lesereihenfolge; echte Systemschrift bis 200 % und echte Tastatur (im Host nur simuliert).
- **Zustellung von Erinnerungen:** Systemdialog ab Android 13, endgültige Ablehnung, ungenau getaktete Alarme, Verhalten nach Force-Stop, Antippen einer echten Benachrichtigung.
- **Teilen-Menü und Dateiauswahl** für Export und Import, einschließlich der Kopie der Auswahl im Cache und sehr großer Dateien.
- **Prozessende:** Der Neustart wird in den Emulator-Abläufen durch Abbau und Neuaufbau des Widget-Baums auf derselben Datenbankdatei nachgestellt (F2, F5, F6), nicht durch das Beenden des Betriebssystem-Prozesses.
- **Release-Build zur Laufzeit:** Die CI baut ihn (der Lauf auf `233b56e` war grün, einschließlich des Release-Schritts), gestartet wurde er nicht.
- **Echte Seitenübergänge in den meisten Widget-Tests:** Das Test-Hilfsmittel der App-Schale schaltet die Animationen standardmäßig aus (`animations: false`, das Systemflag), damit die rund 90 Tests mit der vollständigen App schnell und stabil laufen. Echte Übergänge prüfen nur `test/app/motion_test.dart`, einige Tests der Einstellungen und die Emulator-Abläufe; auf dem Emulator sind sie in der CI ebenfalls ausgeschaltet.
- **Android-Systemzurück** und der Opt-out aus dem vorhersagenden Zurück (`android:enableOnBackInvokedCallback="false"`, Android 16 mit targetSdk 36).
- **Zeitzonen- und Sommerzeitwechsel des Betriebssystems** (im Host mit `FakeClock` und Fake-Zonenquelle nachgestellt).
- **iOS:** Die CI baut eine unsignierte IPA (Workflow `ios-ipa.yml`, erster Lauf am 2026-10-04 grün, macOS-Runner; ab diesem Stand auch bei jedem Push auf `dev`). Der iOS-Tester hat sie am 2026-10-04 mit SideStore auf einem iPhone 15 Pro getestet (laut Rückmeldung iOS 27.0.1, Version 1.0.0, Ticket [BS-96](https://spacy-cloud.atlassian.net/browse/BS-96)); das ist die Rückmeldung des Testers und wurde von uns nicht nachvollzogen. Laut dem iOS-Tester ohne Fehler: Start und Onboarding, Wasser, Gewicht, Aufgabe, Gewohnheit, Fokus-Timer, Erinnerungen (Berechtigung, Zustellung, Antippen öffnet die App), Sicherung (exportieren und wieder importieren), Hell und Dunkel, Neustart mit erhaltenen Daten. Auffälligkeiten mit Folgetickets: Texte „Android-Abfrage“ im Erinnerungs-Ablauf ([BS-113](https://spacy-cloud.atlassian.net/browse/BS-113)), die Tastatur lässt sich nicht einklappen ([BS-112](https://spacy-cloud.atlassian.net/browse/BS-112)), das Querformat ist wenig sinnvoll ([BS-114](https://spacy-cloud.atlassian.net/browse/BS-114), Entscheidung). Offen: VoiceOver, die iOS-Einstellung „Größerer Text“, weitere Geräte und iOS-Versionen; die Aussage zu Notch und Dynamic Island war mehrdeutig (Bestätigung offen).

## 7. Reproduktion

Alle Zahlen dieser Datei entstehen mit diesen Befehlen im Repository-Wurzelverzeichnis (Flutter 3.47.6):

```bash
flutter pub get
dart run build_runner build                      # Drift-Dateien, nicht eingecheckt
flutter test --no-pub                            # Gesamtlauf (Abschnitt 2)
flutter test --no-pub test/features/body         # ein Bereich (Tabelle in Abschnitt 2)
flutter test --no-pub --reporter json            # Zahl je Datei: testDone-Ereignisse mit result success, hidden false zählen
dart format --output=none --set-exit-if-changed lib test tool integration_test
flutter analyze --no-pub
dart run tool/sync_app_name.dart --check
dart run tool/at_coverage.dart --markdown        # Tests je Abnahmefall
flutter test test/performance                    # Lastzahlen nach build/load-test-results.json
flutter test test/tool/demo_backup_test.dart     # build/demo-backup/demo-daten-90-tage.json
```

Die Tests laufen ohne Netzwerk und ohne Gerät. Die Laufzeit des Gesamtlaufs hängt vom Rechner ab; die Lastzahlen schwanken von Lauf zu Lauf (Abschnitt 4).
