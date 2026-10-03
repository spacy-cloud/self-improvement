# Implementierungsentscheidungen

Fortlaufend gepflegtes Protokoll der technischen Festlegungen. Es ergänzt die fachlichen Regeln (Funktions- und technische Spezifikation, nicht Teil dieses Repositories) und die Design-Übergabe in [design-handoff.md](design-handoff.md). Jira: [BS-4](https://spacy-cloud.atlassian.net/browse/BS-4) (Technologie-Stack), [BS-52](https://spacy-cloud.atlassian.net/browse/BS-52) (Bootstrap/CI).

## 1. Quellenstand des Implementierungslaufs

| Quelle | Gelesen am | Stand / Verwendung |
|---|---|---|
| Repository `spacy-cloud/self-improvement` | 2026-10-03 | `main` enthielt nur Initial-Commit und README. Kein App-Code, keine fremden Änderungen. |
| Confluence „LF10a Design-Handoff“ | 2026-10-03 | Version 1 vom 2026-10-02; inhaltlich identisch mit [design-handoff.md](design-handoff.md). Wird im Lauf nicht verändert. |
| Figma `LF10-Desing-App` (`K4IWQEjnzuNkRUzkq8JaKz`) | 2026-10-03 | Lesezugriff über Figma-MCP; Einzelheiten und verwendete Referenzscreens in [design-handoff.md](design-handoff.md). |
| Jira BS-Board | 2026-10-03 | 80 Vorgänge. Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51) mit den Umsetzungstickets BS-52 bis BS-80 (AP00–AP13). Offene formale Punkte: [BS-47](https://spacy-cloud.atlassian.net/browse/BS-47) (App-Name), [BS-49](https://spacy-cloud.atlassian.net/browse/BS-49) (benannte Figma-Version). |

## 2. Toolchain (festgehalten)

| Komponente | Version |
|---|---|
| Flutter | 3.47.6 (stable), Framework-Revision `5fc346839b` vom 2026-09-30 |
| Dart | 3.13.5 |
| DevTools | 2.60.0 |
| Android Gradle Plugin / Gradle / Kotlin | 9.1.0 / 9.3.1 / 2.4.0 (aus der Flutter-Vorlage dieser Version) |
| Java (CI, Android-Build) | Temurin 21 |
| Android `minSdk` | 26, gesetzt in `android/app/build.gradle.kts` (der Flutter-Standard wäre 24; Benachrichtigungskanäle gibt es ab Android 8, kein Plugin verlangt mehr). `targetSdk` gibt Flutter 3.47.6 mit 36 vor |
| iOS Deployment Target | 15.0 (Vorlage; nicht auf macOS verifiziert) |

Die exakte Flutter-Version ist in `.github/workflows/ci.yml` (`FLUTTER_VERSION`) festgehalten und muss mit dieser Tabelle übereinstimmen.

## 3. Paketstände (`pubspec.lock` ist eingecheckt)

| Zweck | Paket | Version |
|---|---|---|
| State / DI | `flutter_riverpod` (ohne Codegenerierung) | 3.4.3 |
| Navigation | `go_router` | 18.0.2 |
| Datenbank | `drift`, `drift_flutter` | 2.35.1, 0.3.1 |
| Datenbank-Generator | `drift_dev`, `build_runner` | 2.35.1, 2.16.1 |
| SQLite-Bindung (transitiv) | `sqlite3` | 3.5.2 |
| Diagramme | `fl_chart` | 1.2.0 |
| Lokale Erinnerungen | `flutter_local_notifications`, `timezone`, `flutter_timezone` | 22.3.1, 0.11.1, 5.1.0 |
| Pfade und Dateien, IDs | `path_provider`, `path`, `uuid` | 2.1.6, 1.9.1, 4.6.0 |
| Lokalisierung (von `flutter_localizations` vorausgesetzt) | `intl` | 0.20.3 |
| Backup-Dateien | `file_selector` (Import), `share_plus` (Export) | 1.1.0, 13.3.1 |
| Lints | `flutter_lints` | 6.0.0 |

Alle Versionen entsprechen `pubspec.lock`. Zwei Einträge verdienen eine Präzisierung (geprüft per Importsuche in `lib`, `test`, `tool` und `integration_test`): `intl` ist in der `pubspec.yaml` deklariert, wird aber im eigenen Code nirgends direkt importiert; Datums- und Zahlentexte erzeugen reine Funktionen in `lib/shared/` (`german_date.dart`, `number_format.dart`), und `intl` ist nur als Voraussetzung von `flutter_localizations` im Projekt. `path` wird in genau zwei Backup-Adaptern direkt genutzt (`lib/core/backup/platform/share_plus_backup_file_gateway.dart` und `file_selector_backup_file_picker.dart`); der Dateiauswahl-Adapter erkennt damit den Cache-Ordner mit der Kopie der gewählten Sicherung (ein UUID-Ordner direkt im Cache) und löscht ihn nach dem Lesen. Alle anderen deklarierten Pakete werden im eigenen Code direkt importiert.

## 4. Entscheidungen

| ID | Entscheidung | Begründung |
|---|---|---|
| D-001 | Technologie: Flutter/Dart, ein App-Projekt mit fünf mitgelieferten Fachmodulen (`body`, `nutrition`, `focus`, `tasks`, `gamification`). | Bereits in README und Planung festgelegt; BS-4 wird damit bestätigt, kein Frameworkvergleich im Lauf. |
| D-002 | Technische Kennungen: Paket `self_improvement`, Android-Namespace/-Application-ID und iOS-Bundle-ID `de.lf10.selfimprovement`. | Vorgabe des Auftrags; das Repository machte keine abweichende Vorgabe. |
| D-003 | Sichtbarer App-Name zentral in `lib/core/config/app_config.dart` (`AppConfig.appName`, Platzhalter „App-Name“). Native Anzeigenamen werden mit `dart run tool/sync_app_name.dart` synchronisiert; ein Test prüft die Übereinstimmung. | BS-47 ist offen; technische Kennungen bleiben bei einer Namensänderung unverändert. |
| D-004 | Backup-Format-Marker `levelup_life_backup` bleibt als stabiler technischer V1-Vertrag erhalten; Dateiname `self-improvement-backup-YYYY-MM-DD-HHmm.json`. | Vorgabe des Auftrags; der Marker ist keine sichtbare Marke. |
| D-005 | Von `build_runner` erzeugte Dateien (`*.g.dart`, Drift) werden nicht eingecheckt. Einrichtung, CI und Tests führen `dart run build_runner build` aus. | Verhindert große, schwer prüfbare Generator-Diffs; die Erzeugung ist deterministisch durch das Lockfile. |
| D-006 | Riverpod: automatische Provider-Wiederholung ist abgeschaltet (`ProviderScope(retry: …)` liefert `null`). | Fehler müssen sichtbar werden; Wiederholungen laufen bewusst über dieselbe Command-ID, nicht über stilles Neustarten von Providern. |
| D-007 | Lint-Regeln: `strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures` als Fehler. | Spezifikation verlangt, dass alle inneren Futures einer Transaktion abgewartet werden. |
| D-008 | Branch-Modell: Integrationsbranch `feature/BS-51-android-v1`, ein erster kleiner Branch `feature/BS-52-bootstrap-ci`; Pull Requests gegen `main`, kumulativ und in dokumentierter Reihenfolge; kein automatisches Merge, kein Push nach `main`. | Das Jira-Epic BS-51 beschreibt die tatsächliche Aufteilung; Abhängigkeiten sind in der PR-Beschreibung dokumentiert. |
| D-009 | CI auf GitHub Actions (Aktionen per Commit-SHA festgelegt): Format, Codegenerierung, Analyse, Tests, Debug-APK sowie Integrationstests auf einem Android-Emulator (API 34). Zusätzlich baut die CI ein Release-APK (mit dem Debug-Schlüssel signiert, nur für manuelle Leistungsproben, kein Store-Build) und veröffentlicht die Artefakte `debug-apk`, `release-apk`, `load-test-results` und `demo-backup`. | Lokal steht kein Android-SDK zur Verfügung (siehe Abschnitt 5). Ein CI-Ergebnis ist ein dokumentierter Android-Nachweis, aber keine Prüfung auf einem realen Gerät; was jeder Job beweist, steht in [test-report.md](test-report.md). |
| D-010 | Zentrale Fehlerbehandlung (`installErrorHandling`, aufgerufen in `lib/main.dart`): unbekannte Fehler werden an einer Stelle gefangen und nur mit Typ und Bibliothek protokolliert, nie mit Meldung oder Stacktrace. Im Debug-Modus bleiben die Details des Frameworks; sonst ersetzt ein neutraler deutscher Satz ein fehlgeschlagenes Widget. | Meldungen können Eingaben enthalten; die App protokolliert keine personenbezogenen Werte. Ticket [BS-85](https://spacy-cloud.atlassian.net/browse/BS-85). |
| D-011 | Android-Manifest: `android:enableOnBackInvokedCallback="false"`, ein ausdrücklicher Opt-out aus dem vorhersagenden Zurück. | Die App ordnet Zurück selbst (eine Seite ohne Verlauf führt zu Home, siehe [screens/shell.md](screens/shell.md)). Mit targetSdk 36 aktiviert Android 16 das vorhersagende Zurück sonst standardmäßig und würde die App vor dieser Reihenfolge schließen. Auf keinem Gerät geprüft. |
| D-012 | Eigene Seitenübergänge (`lib/app/router/app_pages.dart`): der Material-Übergang der Plattform, bei reduzierter Bewegung (System oder App-Schalter) keiner; der App-Schalter erreicht Sheets und Snackbars über `AppMotion.surfaceStyleOf`. | go_router 18 wählt den Seitentyp über den `MaterialApp` des separaten Pakets `material_ui`, die App nutzt den des SDK; ohne eigene Seiten wäre jeder Routenwechsel ein harter Schnitt. Das Framework selbst folgt nur dem Systemflag. Ticket [BS-87](https://spacy-cloud.atlassian.net/browse/BS-87). |

## 5. Umgebung des Laufs und Grenzen

| Aspekt | Stand |
|---|---|
| Entwicklungsrechner | Linux x86_64; Flutter nutzerlokal installiert (keine Systempakete). |
| Android-SDK / Lizenzen | Nicht installiert, Lizenzen nicht akzeptiert und im Lauf nicht angenommen. Ein lokaler APK-Build und Emulator-Tests sind daher nicht möglich. |
| Gerät / Emulator lokal | Keines vorhanden. |
| Linux-Desktop-Target | Nicht verfügbar (CMake fehlt); nicht Teil des Auftrags. |
| Ausführbar lokal | Format, `flutter analyze`, Unit-, Repository- und Widget-Tests auf dem Host (`flutter test`, SQLite im Prozess). |
| Android-Nachweis | Über CI (GitHub-gehostetes Android-SDK und Emulator); die Ergebnisse der CI-Läufe stehen im Pull Request, die lokalen Läufe und was die Jobs beweisen oder nicht in [test-report.md](test-report.md). |
| iOS | Projektdateien vorbereitet; kein Build und kein Test (macOS/Xcode nötig). |
