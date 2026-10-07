# Testbericht

Dokumentiert tatsächlich ausgeführte Prüfungen mit Umgebung und Ergebnis. Nicht ausgeführte oder nicht prüfbare Punkte sind als solche gekennzeichnet; ein gestarteter CI-Lauf gilt nicht als bestanden. Ergebnisse von CI-Läufen stehen im Pull Request, nicht in dieser Datei (Abschnitt 5 sagt, was die Jobs beweisen und was nicht). Welche Anforderung oder welcher Abnahmefall durch welche Tests belegt ist, steht in der [Anforderungsmatrix](requirements-matrix.md). Die Datei beschreibt den Stand des Releases v0.2.0: Die Zahlen der Abschnitte 2 bis 4 stammen aus den Läufen dieses Stands (Befehle in Abschnitt 8), Abschnitt 6 fasst zusammen, was für v0.2.0 zusätzlich geprüft wurde, und Abschnitt 7 nennt, was auf keinem Gerät geprüft ist.

## 1. Umgebung

| Aspekt | Wert |
|---|---|
| Datum der Läufe | 2026-10-07 |
| Code-Stand | Commit `a90f3b1` (Branch `feature/BS-98-version-0-2-0`, PR 28: das Ende der Kette der Pull Requests des Releases v0.2.0 bis PR 27 mit der Versionsanhebung auf 0.2.0+2; die Pull Requests 4 bis 21, 23, 25, 26 und 27); die Zahlen dieser Seite sind für diesen Stand gemessen, der Rest von PR 28 ändert nur Dateien unter `docs/` und `README.md` |
| Toolchain | Flutter 3.47.6 (stable, Framework-Revision `5fc346839b`), Dart 3.13.5, DevTools 2.60.0 (Ausgabe von `flutter --version`; siehe [implementation-decisions.md](implementation-decisions.md)) |
| Host | Linux x86_64, 16 Kerne |
| Host-Tests | `flutter test` mit echter In-Memory-SQLite-Datenbank (Drift), fester Uhr `FakeClock` (Zone Europa/Berlin), Fakes für Erinnerungs-Plattform, Teilen und Dateiauswahl, Fake-Quelle und nachgebautem Kanal für Health, simulierter Textskala und Tastatur; nur synthetische Daten |
| Lokales Android-Ziel | In der automatischen Entwicklungsumgebung keines (kein Android-SDK, kein Gerät, kein Emulator); der Projektinhaber hat am 2026-10-04 einen Debug-Build des Stands v0.1.0 auf einem Samsung S25 gestartet |
| CI | GitHub Actions, siehe `.github/workflows/ci.yml`, `.github/workflows/ios-ipa.yml` und Abschnitt 5 |

## 2. Gesamtlauf der Host-Tests

Befehl, ausgeführt nach `flutter pub get` und `dart run build_runner build`:

```bash
flutter test --no-pub
```

Ergebnis: **8540 Tests bestanden, 0 übersprungen, 0 fehlgeschlagen**, Exit-Code 0, Laufzeit laut Reporter 3:48 Minuten (Lauf mit `--reporter json`, damit sich die Tests je Verzeichnis zählen lassen; der Rechner war dabei sonst ruhig). Sie verteilen sich auf 357 Testdateien; 4 weitere Dateien (`focus_visual_test.dart`, `workout_day_visual_test.dart`, `goals_today_visual_test.dart`, `habits_dashboard_card_visual_test.dart`) registrieren nur mit einer Umgebungsvariable Tests (Bilder für den Sichtvergleich mit Figma). Auf der Basis (`origin/dev` vor der Kette, Commit `0c2ae0f`) waren es 6485 Tests; die Kette brachte 2055 hinzu (bis PR 21 stand der Lauf bei 8226 Tests, mit PR 23 bei 8268, mit PR 25 bei 8493, mit PR 27 bei 8540).

### Ergebnis je Bereich

Die Zeilen stammen aus dem Gesamtlauf und sind nach dem Verzeichnis der Testdatei aufgeteilt; jedes Verzeichnis lässt sich einzeln mit `flutter test --no-pub <Verzeichnis>` wiederholen. Die Summe der Zeilen ist 8540 und stimmt mit dem Gesamtlauf überein.

| Bereich | Verzeichnis | Tests |
|---|---|---:|
| App (Start, Router, Shell, Fehlerbehandlung, Verdrahtung) | `test/app` | 736 |
| Analyse-Engine | `test/core/analysis` | 280 |
| Backup (Format, Validierung, Import, Export, Zurücksetzen) | `test/core/backup` | 850 |
| Bootstrap | `test/core/bootstrap` | 13 |
| Commands (Runner, Undo, Befehls-IDs) | `test/core/commands` | 20 |
| Konfiguration | `test/core/config` | 6 |
| Dashboard-Regeln | `test/core/dashboard` | 19 |
| Datenbank-Schema (Schema 2, Migrationsschritte) | `test/core/database` | 75 |
| Design-System (Tokens, Kontrast, Komponenten, Golden-Tests) | `test/core/design` | 906 |
| Feedback | `test/core/feedback` | 6 |
| Ziele, Snapshots, XP-Projektion, Streak | `test/core/goals` | 235 |
| Health-Schnittstelle (Tagesfenster, Vertrag, Kanal zu Health Connect, Adapterwahl) | `test/core/health` | 50 |
| Module | `test/core/modules` | 23 |
| Benachrichtigungen (Planer, Service, Plattform-Adapter) | `test/core/notifications` | 540 |
| Onboarding-Repository | `test/core/onboarding` | 11 |
| Profil | `test/core/profile` | 11 |
| Einstellungen | `test/core/settings` | 10 |
| Zeit | `test/core/time` | 12 |
| Analyse (Oberfläche) | `test/features/analysis` | 123 |
| Körper (Gewicht und Schritte, mit Health) | `test/features/body` | 497 |
| Dashboard (Home, Ziele heute, Tage blättern) | `test/features/dashboard` | 584 |
| Fokus und Workouts | `test/features/focus` | 788 |
| Gamification | `test/features/gamification` | 173 |
| Modulverwaltung | `test/features/modules` | 42 |
| Ernährung (Wasser und Mahlzeiten) | `test/features/nutrition` | 618 |
| Onboarding | `test/features/onboarding` | 100 |
| Profil und Ziele | `test/features/profile` | 248 |
| Erinnerungen (Oberfläche) | `test/features/reminders` | 114 |
| Einstellungen, Daten und Sicherung | `test/features/settings` | 251 |
| Aufgaben und Gewohnheiten | `test/features/tasks` | 1129 |
| Lasttest und Listen-Scroll | `test/performance` | 7 |
| Plattform (Manifest-Prüfungen) | `test/platform` | 28 |
| Gemeinsame Hilfen (Datum, Zahlen) | `test/shared` | 24 |
| Test-Hilfen | `test/support` | 10 |
| Demo-Backup-Erzeuger | `test/tool` | 1 |
| **Summe** | | **8540** |

Die Tests je Abnahmefall (AT01 bis AT36) zählt `dart run tool/at_coverage.dart`; die Auswertung steht in Abschnitt 3 der Anforderungsmatrix.

## 3. Statische Prüfungen

| Prüfung | Befehl | Ergebnis |
|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test tool integration_test` | „Formatted 929 files (0 changed)“, Exit-Code 0 (gezählt vor der Codegenerierung wie in der CI; lokal nach der Codegenerierung ist es eine erzeugte Datei mehr) |
| Statische Analyse | `flutter analyze --no-pub` | „No issues found!“, Exit-Code 0 |
| Native Anzeigenamen | `dart run tool/sync_app_name.dart --check` | „Native display names are in sync („App-Name“)“, Exit-Code 0 |

## 4. Lasttest (Host und CI-Runner, kein Gerät)

Der Lasttest (`test/performance/load_test.dart`, Ticket BS-75, Abnahmefall AT36) schreibt 10.582 synthetische Datensätze über drei Jahre direkt in eine In-Memory-SQLite-Datenbank, baut die gemeinsamen Projektionen einmal neu auf (das Szenario eines Imports) und misst die Alltagsoperationen in dieser Größe. **Alle Werte sind Messungen eines Linux-Rechners (Host und CI-Runner) mit In-Memory-Datenbank; keine einzige ist auf einem Gerät gemessen.**

| Messung | Entwicklungsrechner (Stand dieser Datei) | CI-Runner (Stand v0.1.0, Lauf 37136052363) |
|---|---:|---:|
| Synthetische Datensätze | 10.582 | 10.582 |
| Einfügen der Datensätze | 214 ms | nicht übernommen |
| Neuaufbau der Projektionen über alle Tage (drei Jahre) | 1.338 ms | 2.199 ms |
| Gewichts-Commit, Median von 20 | 6 ms | 10 ms |
| Gewichts-Commit, Maximum | 15 ms | 21 ms |
| Erster Wert Gesamt-XP | 1 ms | 3 ms |
| Erster Wert Tagesstatus heute | 145 ms | 237 ms |
| Erster Wert Schritteverlauf (90 Tage) | 0 ms | unter 250 ms |
| Erster Wert Analysebericht | 28 ms | 70 ms |
| Erster Wert Streak | 0 ms | 0 ms |
| Backup-Export mit Selbstprüfung | 340 ms | 406 ms |
| Größe der Sicherung | 5.133.105 Byte | 4.526.520 Byte |

Die Spalte „Entwicklungsrechner“ stammt aus einem Lauf von `flutter test test/performance` allein (nicht im Gesamtlauf), der `build/load-test-results.json` schreibt. Auf dem 16-Kern-Rechner lief nebenher ein weiterer Testlauf (Last etwa 2,5). Die Werte schwanken von Lauf zu Lauf: drei Läufe hintereinander wichen bei den Messungen über 100 ms um weniger als 10 % voneinander ab; die Tabelle zeigt den dritten. Die CI-Spalte stammt aus dem Artefakt `load-test-results` eines CI-Laufs auf dem Stand v0.1.0 (für den Schritteverlauf liegt nur die Obergrenze vor); sie ist für v0.2.0 nicht erneuert und gilt deshalb nur als Größenordnung. Der Lasttest selbst ist seit v0.1.0 unverändert; neu ist, dass die Sicherung in Version 2 geschrieben wird.

Die Schwellen des Tests sind absichtlich großzügige Regressionsgrenzen für einen CI-Rechner: Projektions-Neuaufbau unter 120 s, Gewichts-Commit Median unter 300 ms und Maximum unter 2 s, jeder erste Wert unter 5 s, Sicherung unter 10 MiB und beim Import wiederherstellbar. Alle Schwellen wurden eingehalten (der Test ist grün).

Planungsziele für ein **Gerät**, an denen die Werte gemessen werden müssen: Start etwa 3 s, einfacher Commit 300 ms, Scrollen mit 60 Hz. **Auf einem Gerät nicht gemessen.** Der Test `test/performance/list_scroll_test.dart` prüft für 3.000 Messungen nur, dass die Zeilen lazy gebaut werden und das Ende erreichbar ist, nicht die Bildrate.

## 5. CI-Jobs: was sie beweisen und was nicht

Definiert in `.github/workflows/ci.yml` und `.github/workflows/ios-ipa.yml`; Ergebnis der Läufe: siehe Pull Request. Am 2026-10-07 waren die Prüfungen der Pull Requests 4 bis 21, 23, 25 und 26 grün; jeder Branch der Kette enthält seine Vorgänger, die CI von PR 25 hat also den Stand `577a853` geprüft und die von PR 26 den Stand `4fb9936` (dazu nur Dokumente). Die Prüfungen von PR 27 und PR 28 stehen in den Pull Requests.

| Job | Was der Job ausführt | Beweist | Beweist nicht |
|---|---|---|---|
| Format, analyze, test | Lockfile erzwungen (`flutter pub get --enforce-lockfile`), Format-Check, Drift-Codegenerierung, Prüfung der nativen Anzeigenamen, `flutter analyze --no-pub`, `flutter test --no-pub`; lädt `load-test-results` und `demo-backup` als Artefakte hoch | Dasselbe wie die lokalen Läufe in den Abschnitten 2 bis 4, auf sauberer Umgebung mit der gesperrten Toolchain | Verhalten auf Android und iOS |
| Android debug APK | `flutter build apk --debug`, danach `flutter build apk --release` (mit dem Debug-Schlüssel signiert, nur für manuelle Leistungsproben); lädt `debug-apk` und `release-apk` hoch | Die App lässt sich für Android bauen und verpacken, einschließlich der Health-Connect-Anbindung (Kotlin-Kanal, `connect-client` 1.1.0, Coroutines), des Plugins `url_launcher_android` und, im Release-Schritt, der Code-Verkleinerung (R8) | Dass die APKs starten: Der Job startet keine; das Release-Paket wurde nirgends gestartet. Auch das zusammengeführte Manifest liest kein Test, die Health-Anbindung läuft auf keinem Gerät, und das Update einer echten Datenbank ist nicht Teil des Jobs |
| Android emulator integration tests (API 34) | `flutter test integration_test --dart-define=WIPE_APP_DATA=yes` auf einem Emulator (x86_64, Google APIs, Profil Pixel 6, Animationen aus): `integration_test/app_smoke_test.dart` (In-Memory-Datenbank, Test-Ersatz für Benachrichtigungen) und `integration_test/app_flows_test.dart` (der echte Produktionsstart, siehe [integration-tests.md](integration-tests.md)) | Der Dart-Code läuft auf einem Android-Emulator. Smoke-Test: Start hinter dem Onboarding, vier Tabs, Plus-Menü. Abläufe mit dem echten Start (echte SQLite-Datei im App-Support-Verzeichnis, echte Zeitzonenerkennung, echtes Benachrichtigungs-Plugin): F1 Erststart und Onboarding (AT01), F2 Gewicht mit Neustart (AT02, AT06), F3 Wasser mit Rückgängig (AT10), F4 Aufgabe abschließen (AT13), F5 Fokus mit Pause und Neustart mitten in der Sitzung (AT16), F6 Zurücksetzen (AT32), F7 Datenbankdatei, Gerätezone und Initialisierung der Erinnerungs-Plattform | Systemdialoge, Teilen-Menü und Dateiauswahl, TalkBack, echte Benachrichtigungszustellung, Leistung, ein echtes Gerät, den Release-Build; die Abläufe laufen bei ausgeschalteten Animationen und auf einem frischen Emulator (Schema 2 wird dort neu angelegt, die Migration einer v0.1.0-Datenbank läuft nicht). Die Funktionen von v0.2.0 haben keinen Emulator-Ablauf |
| iOS unsigned IPA (`ios-ipa.yml`, macOS-Runner, bei Pushes auf `dev` und auf dem Branch zu BS-95) | baut eine unsignierte IPA und lädt sie als `ios-ipa-unsigned` hoch | Die App lässt sich für iOS bauen, einschließlich `url_launcher_ios` | Dass die IPA sich signieren, installieren und starten lässt; ein grüner Lauf ist kein Gerätetest |

Das CI-Ergebnis des Emulator-Jobs steht im Pull Request. Die Abläufe löschen die App-Datenbank des Zielgeräts und starten deshalb nur mit der ausdrücklichen Bestätigung `--dart-define=WIPE_APP_DATA=yes` (die CI übergibt sie); sie gehören nicht auf ein Handy mit echten Daten.

Zusätzlich lief die App am 2026-10-03 manuell auf einem Android-Emulator des Projektteams (Debug-Build aus Android Studio): Start mit dem Produktionspfad und Anzeige des Dashboards mit leeren Zuständen. Am 2026-10-04 lief ein Debug-Build (arm64) auf einem Samsung S25 und zeigte die Willkommensseite des Onboardings; ein erster Startversuch auf dem S25 war abgestürzt, die Ursache ist nicht untersucht (kein Log vorhanden). Laut Rückmeldung funktioniert auf dem S25 auch eine Benachrichtigung; es wurde nicht genauer getestet, ein Protokoll gibt es nicht. Beides betrifft den Stand v0.1.0; für v0.2.0 gibt es keine Geräteläufe. Die Punkte für ein Gerät stehen in der [Geräte-Checkliste](geraete-checkliste-v0.2.0.md).

## 6. Release v0.2.0

Das Release besteht aus einer Kette von Pull Requests gegen `dev`; jeder Branch enthält seine Vorgänger. Reihenfolge: PR 4 (iOS und Doku), 8 (Datenvertrag v2), 6 (BS-113), 5 (BS-108), 7 (BS-118), 9 (BS-117), 10 (BS-120), 11 (BS-112), 12 (BS-114), 15 (BS-121), 16 (BS-99), 17 (BS-111), 13, 14 und 18 (BS-97), 19 (BS-110), 20 und 21 (BS-100), 23 (Befunde des Prüfzyklus 1), 25 (BS-93), 26 (Abnahme der Dokumente), 27 (Befunde des Prüfzyklus 2), 28 (Versionsanhebung 0.2.0+2 und die nach Prüfzyklus 2 neu gesetzten Zahlen). Die Zuordnung von Pull Request, Ticket und Jira-Status steht in Abschnitt 1a der [Anforderungsmatrix](requirements-matrix.md). Alles in diesem Abschnitt sind Host-Tests und Prüfungen am Quelltext; **nichts davon ist auf einem Gerät geprüft** (Abschnitt 7).

### 6.1 Migration und Import älterer Sicherungen (Datenvertrag v2, BS-98)

Schema 2 und Backup 2 brachten die Daten für BS-99 (Ruhetag und Überspringen), BS-97 (Quelle der Schritte, Wunsch für Health) und BS-111 (Erinnerung je Aufgabe); alles ist additiv, vorhandene Zeilen behalten jeden Wert (D-015, D-016).

- **Fixtures aus dem unveränderten Code von v0.1.0** (`test/fixtures/v1/`): der SQL-Textdump einer Datenbank mit allen 19 Tabellen, ihre Sicherung und die 90-Tage-Beispielsicherung. Sie entstanden mit einem Stand, dessen `lib/`, `test/` und `pubspec.*` denen des Tags `v0.1.0` gleichen, über die echten Repositories und Commands, nur mit synthetischen Daten. Der unabhängige Prüfer hat die fünf Dateien mit dem unveränderten Code neu erzeugt: Sie sind byte-identisch.
- **Migration:** Jeder der fünf Schritte hat einen eigenen Test, dazu kommen ein Gesamtlauf und der Vergleich mit einem frisch angelegten Schema 2 (`test/core/database/schema_migration_test.dart`, 36 Tests): Alle Werte aller Spalten der 19 Tabellen bleiben, `PRAGMA integrity_check` ist ok, `foreign_key_check` ist leer, die Schritte sind wiederholbar, ein Abbruch lässt die Datei auf Schema 1, eine Datenbank mit höherer Version wird nicht geöffnet. Der Produktionsstart `AppRuntime.create()` öffnet eine v0.1.0-Datei auf der Platte (`test/core/bootstrap/app_start_on_v1_database_test.dart`, 5 Tests).
- **Import älterer Sicherungen:** Dateien der Version 1 laufen über den Aufwärtsschritt `BackupUpgrade` (`test/core/backup/backup_upgrade_test.dart`, `backup_v1_import_test.dart`); eine Datei der Version 1 mit Inhalt der Version 2 und jede andere Version (0, 3, 99, Text, 1.0) werden abgelehnt. Eine migrierte Datenbank und eine importierte Sicherung derselben Daten exportieren byte-identische Dateien; die XP-Neuberechnung nach dem Import gibt die 89 Vergaben zurück, die v0.1.0 geschrieben hatte.
- **Mutationsproben:** 11 des Datenvertrags (Abschnitt 6.2), dazu zwölf weitere des Prüfers (M01 bis M12), alle erkannt.
- **Nicht belegt:** das Update einer echten Installation auf einem Gerät (Datei-Datenbank, Signaturschlüssel der APK). Dass v0.1.0 eine Datenbank oder Sicherung der Version 2 ablehnt, ist aus dem Code abgeleitet und mit einem Modell seiner Migrationsstrategie getestet, nicht mit dem Release-APK ausprobiert. Die Emulator-Abläufe der CI starten auf einer frischen Datenbank.

### 6.2 Mutationsproben

Bei Fehlerkorrekturen und beim Datenvertrag wurde der Produktivcode vorübergehend an einer tragenden Stelle verändert (oder die Korrektur zurückgenommen); die neuen Tests mussten scheitern, danach wurde der Stand wiederhergestellt, nie committet. Die Zahlen stehen in den Texten der Pull Requests; die Tabelle fasst sie zusammen.

| Ticket | Pull Request | Proben | Scheiternde Tests je Probe |
|---|---|---:|---|
| BS-98 Datenvertrag | 8 | 11 | 1 bis 13 |
| BS-108 Schritte-Karte | 5 | 1 | 22 (kein bestehender Test) |
| BS-113 neutrale Texte | 6 | 10 | je der Regeltest und mindestens 2 weitere; alle zehn zusammen 54 von 131 |
| BS-118 Über die App (zusätzliche Proben) | 7 | 3 | 2 bis 3 |
| BS-117 Plus-Menü | 9 | 2 | 27 von 34 Widget-Tests; 30 |
| BS-120 Lizenz | 10 | 5 | mindestens 2 |
| BS-112 Tastatur | 11 | 9 | 2 bis 42 |
| BS-114 Querformat | 12 | 0 (zwei Empfindlichkeitsproben) | 1 und 3 |
| BS-121 Tagesring | 15 | 4 | 15 bis 27 |
| BS-99 Workout heute | 16 | 12 | 1 bis 46 |
| BS-111 Erinnerung je Aufgabe | 17 | 25 | 1 bis 14 (ein Eingriff überlebte zuerst, dafür gibt es einen Test) |
| BS-97 Kern | 13 | 15 | 1 bis 16 |
| BS-97 Android-Quelle | 14 | 7 | 1 bis 2 |
| BS-97 Oberfläche | 18 | 37 | 31 sofort erkannt; 6 überlebten zunächst (für 5 wurden Tests ergänzt, eine ist gleichwertig) |
| BS-110 Heute abhaken | 19 | 13 | 1 bis 60 |
| BS-100 Ziele heute | 20 | 17 | 1 bis 31 |
| BS-105, BS-106 Sprung zum Modul | 21 | 10 | 1 bis 11 |
| BS-98 Befunde des Prüfzyklus 1 | 23 | 13 | die neuen Tests scheitern (R1-01: 35) |
| BS-93 Tage blättern | 25 | 28 | 1 bis 24 |
| **Summe der Proben der Umsetzung** | | **222** | |

Dazu kommen die Stichproben des unabhängigen Prüfers (Abschnitt 6.3). Eine Mutationsprobe zeigt, dass die Tests an dieser Stelle greifen; sie beweist nicht, dass es keine andere Lücke gibt.

### 6.3 Unabhängige Prüfzyklen

Ein Prüfer, der den Code nicht geschrieben hat, prüft den Stand in Zyklen (höchstens drei sind vorgesehen); er ändert nichts am Prüfobjekt. Dieser Abschnitt nennt abgeschlossene Zyklen.

**Zyklus 1** prüfte den Integrationsstand `e99de3a` (die Pull Requests 4 bis 17; 7774 Tests, davon 6485 der Basis). Ergebnis: **kein P0, zwei P1, zwölf P2** (R1-01 bis R1-14).

| Schwere | Befund | Behandlung |
|---|---|---|
| P1 | R1-01: Die iOS-Variante der Tastatur-Tests lief mit dem Theme von Android, zwei Zieh-Tests scheiterten bei echter iOS-Plattform reihenfolgeabhängig | behoben in PR 23 (Theme je Plattform, Zieh-Test neben dem Cursor, die Grenze am Cursor dokumentiert) |
| P1 | R1-02: Zwei Dokumente stritten noch ab, dass es eine Health-Anbindung gibt | behoben in PR 23 (mit Dokumenttest) |
| P2 | R1-03 Plus-Eintrag „Workout“ hing nur am Wochenziel; R1-04 `flutter test` hing bei fehlschlagenden Tests mit offener Seite; R1-05 handgepflegte Seitenlisten kannten „Über die App“ nicht; R1-08 Lücken des Regeltests gegen Plattformnamen; R1-09 Vorname des iOS-Testers in öffentlichen Dateien; R1-12 exportierter Dienst der Health-Bibliothek nicht dokumentiert | behoben in PR 23 |
| P2 | R1-06 Verweis auf D-033 vor seiner Aufnahme | erledigt: D-033 steht seit PR 18 in der Tabelle der Entscheidungen |
| P2 | R1-07 Zählungen der Anforderungsmatrix nach dem Zusammenführen veraltet | behoben mit der Abnahme der Dokumente, PR 26 (Zahlen aus den Messungen in Abschnitt 2) |
| P2 | R1-10 Pull-Request-Texte verwiesen auf das Hilfsskript des Laufs | erledigt: die Texte nennen die offenen Befehle |
| Hinweis (P2) | R1-11 die README ändert drei Stellen (Copyright, iOS-Zeile, Absatz zum iOS-Workflow); R1-13 `load_test.dart` ist reihenfolgeabhängig (schon in der Basis, kein Fehler des Releases); R1-14 Schnitt der Kette: die Pull Requests 13, 14 und 18 (Health) gehören zusammen und stehen in der Kette hintereinander | R1-11: Bestätigung des Absatzes zum iOS-Workflow offen; R1-13: nicht behoben; R1-14: bei der Reihenfolge der Merges zu beachten |

Der Prüfer hat außerdem gemessen: 6485 Tests auf der Basis (wie berichtet); Format, Codegenerierung, App-Name-Abgleich und Analyse des Integrationsstands ohne Befund; die Testzahlen der Berichte stimmen (bis auf die Zählung in R1-07); die Kontrastzahlen der Doku (Ringgrün in Hell 2,66:1 und 2,30:1) stimmen; das Kotlin der Health-Anbindung übersetzt mit `-Werror` ohne Fehler. Von 66 Stichproben-Mutationen erkannten die Tests 65; eine überlebte (M53, „Android“ im Ressourcentext der Datenschutz-Erklärung) und ist seither vom Regeltest erfasst (R1-08).

**Zyklus 2** prüfte das Kettenende `577a853` (die Pull Requests 4 bis 21, 23 und 25; 8493 Tests). Ergebnis: **kein P0, kein P1, sieben P2** (R2-01 bis R2-07); dazu kam R2-08 aus der Durchsicht des Koordinators.

| Schwere | Befund | Behandlung |
|---|---|---|
| P2 | R2-01: „Zugriff erlauben“ startete nach einem Import mit eingeschaltetem Schalter den Systemdialog ohne den Erklärtext (BS-97) | behoben in PR 27: alle drei Stellen zeigen zuerst den Erklärtext |
| P2 | R2-02: Die Fokus-Karte eines vergangenen Tages nahm das Ziel aus den Zielversionen statt aus dem Snapshot des Tages (BS-93) | behoben in PR 27 |
| P2 | R2-03: Zeitzonenwechsel nach Westen auf dem gezeigten Tag löste in der Karte „Aufgaben und Gewohnheiten“ eine Assertion aus (nur Debug und Tests; BS-93, BS-110) | behoben in PR 27 (Ladezustand im Anbieter, richtige Meldung) |
| P2 | R2-04: Der Abbau vor dem Schließen der Datenbank (R1-04) verhinderte nicht jedes Hängen von `flutter test` | gemindert in PR 27: Zeitlimit von 20 s im Abbau von `createTestHarness`, ein Hänger endet als Fehler; die Ursache des offenen Abonnements ist nicht eingegrenzt, Tests, die die Datenbank selbst schließen, haben das Limit nicht |
| P2 | R2-05: Der Löschtext der Schritte versprach das Wiedereintragen durch Health für jeden Tag (BS-97) | behoben in PR 27: nur für heute und die sechs Tage davor und nur, wenn Health liefert |
| P2 | R2-06: Veraltete Aussagen über spätere Pull Requests in Screen-Dokumenten und einem Testnamen | erledigt in PR 26 und PR 27 |
| P2 | R2-07: Texte öffentlicher Pull Requests verwiesen auf einen Bericht außerhalb des Repositorys; der Titel von PR 4 nannte einen Vornamen | erledigt: Texte und Titel umgeschrieben |
| P2 | R2-08 (Koordinator): Der Vorname des Projektinhabers stand in 13 Zeilen von 6 Dokumenten | behoben in PR 27 (Rolle statt Vorname); die Pull-Request-Texte sind angepasst |

Der Prüfer hat außerdem gemessen: Format, Codegenerierung, App-Name-Abgleich und Analyse von `577a853` ohne Befund und 8493 Tests grün; die Zahlen der Pull-Request-Texte stimmen; 44 eigene Mutationsproben (BS-93 19, BS-110 9, BS-100 6, BS-97 Oberfläche 7, Behebungen aus PR 23 3), alle lassen Tests scheitern bis auf einen gleichwertigen Mutanten; jeder Branch der Kette enthält seinen Vorgänger und alle Pull Requests waren ohne Konflikt mergebar; Schema und Backup sind seit PR 8 unverändert. Die Behebungen aus Zyklus 1 wirken (R1-01, R1-02, R1-03, R1-05, R1-06, R1-08, R1-12 und R1-14), R1-04 und R1-10 nur teilweise (R2-04 und R2-07), R1-09 im Baum (der Name bleibt im Verlauf von Git).

Die Korrekturen aus Zyklus 2 (PR 27) hat kein unabhängiger Prüfer noch einmal gelesen; ein Zyklus 3 ist nicht gelaufen. Sie sind durch neue Tests und je eine Mutationsprobe belegt (die Zahlen stehen im Text von PR 27).

### 6.4 Zufallsreihenfolge und Zeitzonen

Der Prüfer hat die Suite des Integrationsstands `e99de3a` (Zyklus 1) und des Kettenendes `577a853` (Zyklus 2) in zufälliger Reihenfolge und unter fremden Zeitzonen laufen lassen:

- **Zufällige Reihenfolge** (`--test-randomize-ordering-seed`): Seed 20261007 über die ganze Suite: 7771 grün, 3 rot (die beiden Fehler von R1-01 und das Zeitlimit von `load_test.dart`, R1-13, schon in der Basis); Seed 777 grün und Seed 4242 mit denselben zwei Fehlern, beide ohne `test/performance`.
- **Zeitzonen:** die ganze Suite unter `TZ=Pacific/Kiritimati` (UTC+14) und unter `TZ=America/St_Johns` (UTC−3:30 mit Sommerzeit), je 7741 Tests grün (ohne `test/performance`). Die CI läuft in UTC, der Rechner des Prüfers in Berlin: Eine Abhängigkeit von der Zeitzone des Rechners wurde nicht gefunden.
- **Nach der Behebung von R1-01** (PR 23): `test/app/form_keyboard_test.dart` (72) und `test/core/design/components/keyboard_dismiss_test.dart` (14), zusammen 86 Tests, sind in der Standardreihenfolge und mit den Seeds 21, 23, 26, 777, 4242 und 20261007 grün; jede der 60 Varianten (Android und iOS) läuft auch einzeln mit `--plain-name`.
- **Zyklus 2** (Stand `577a853`): Zufallsreihenfolge mit Seed 20261007 und Seed 424242, je 8486 Tests grün (ohne `test/performance`); Zeitzonen `Pacific/Kiritimati` und `America/St_Johns`, je 8486 Tests grün (ohne `test/performance`).

Die Läufe des Prüfers gelten für die Stände der Zyklen (`e99de3a`, `577a853`), nicht für das Kettenende `a90f3b1`; der Gesamtlauf in Abschnitt 2 lief in der Standardreihenfolge und in der Zeitzone des Rechners (Berlin).

## 7. Nicht getestet

Nicht auf einem Gerät oder mit der echten Plattform geprüft (in der automatischen Entwicklungsumgebung gibt es kein Android-SDK; Emulator-Läufe stammen aus der CI und aus dem einen manuellen Lauf des Projektteams); die jeweils vorhandenen Stellvertreter stehen in der [Anforderungsmatrix](requirements-matrix.md), Abschnitt 6, die Prüfpunkte für das Samsung S25 und das iPhone in der [Geräte-Checkliste](geraete-checkliste-v0.2.0.md). Von v0.2.0 ist **nichts auf einem Gerät geprüft**; vom Stand v0.1.0 sind es der Start eines Debug-Builds auf einem Samsung S25 (2026-10-04, Willkommensseite des Onboardings) und, laut Rückmeldung, eine Benachrichtigung (nicht genauer getestet).

**Allgemein**

- **Echtes Gerät:** Gefühl bei Start und Scrollen, Leistung (Start etwa 3 s, Commit 300 ms, 60 Hz), Speicher; der Release-Build zur Laufzeit (die CI baut ihn, gestartet wurde er nirgends); das Prozessende des Betriebssystems (die Emulator-Abläufe bauen den Widget-Baum auf derselben Datenbankdatei ab und neu auf, F2, F5, F6).
- **Update einer echten Installation von v0.1.0** (Migration der Datei-Datenbank, Signaturschlüssel der APK, Weg Sicherung exportieren, deinstallieren, installieren, importieren).
- **TalkBack und VoiceOver** (Lesereihenfolge, Ansagen, Fokus, Rotor), **echte Systemschrift** bis 200 % und die iOS-Einstellung „Größerer Text“, **echte Tastatur** (im Host nur simuliert).
- **Echte Seitenübergänge in den meisten Widget-Tests:** Das Test-Hilfsmittel der App-Schale schaltet die Animationen standardmäßig aus (`animations: false`, das Systemflag), damit die 684 Tests der 24 Dateien mit der vollständigen App (`pumpFullApp`) schnell und stabil laufen. Echte Übergänge prüfen nur `test/app/motion_test.dart`, einige Tests der Einstellungen und die Emulator-Abläufe; auf dem Emulator sind sie in der CI ebenfalls ausgeschaltet.
- **Zeitzonen- und Sommerzeitwechsel des Betriebssystems** (im Host mit `FakeClock` und Fake-Zonenquelle nachgestellt).

**Android**

- **Zustellung von Erinnerungen** (auch die Erinnerung je Aufgabe): Systemdialog ab Android 13, endgültige Ablehnung, ungenau getaktete Alarme, Verhalten nach Force-Stop und im Energiesparmodus, Antippen einer echten Benachrichtigung, Kaltstart aus der Benachrichtigung.
- **Schritte aus Health:** der echte Dialog von Health Connect, ob die Tagessumme der Summe in Health Connect gleicht, mehrere Quellen ohne Doppelzählung, Entzug des Zugriffs, die Datenschutz-Seite, der Weg in den Store; das zusammengeführte Manifest belegt erst der Android-Build der CI, ein Test liest es nicht.
- **Teilen-Menü und Dateiauswahl** für Export und Import, einschließlich der Kopie der Auswahl im Cache und sehr großer Dateien.
- **Android-Systemzurück** und der Opt-out aus dem vorhersagenden Zurück (`android:enableOnBackInvokedCallback="false"`, Android 16 mit targetSdk 36); die Zurück-Geste vom Rand auf Home an einem vergangenen Tag.
- **Browser-Start** der Zeile „Website“ auf „Über die App“ und das Verhalten ohne Browser.

**iOS (v0.2.0 insgesamt)**

- Die CI baut eine unsignierte IPA (`ios-ipa.yml`, erster Lauf am 2026-10-04 grün, macOS-Runner; ab diesem Stand auch bei jedem Push auf `dev`). Der iOS-Tester hat den Stand v0.1.0 am 2026-10-04 mit SideStore auf einem iPhone 15 Pro getestet (laut Rückmeldung iOS 27.0.1, Version 1.0.0, Ticket [BS-96](https://spacy-cloud.atlassian.net/browse/BS-96)); das ist die Rückmeldung des Testers und wurde von uns nicht nachvollzogen. Laut dem iOS-Tester ohne Fehler: Start und Onboarding, Wasser, Gewicht, Aufgabe, Gewohnheit, Fokus-Timer, Erinnerungen (Berechtigung, Zustellung, Antippen öffnet die App), Sicherung (exportieren und wieder importieren), Hell und Dunkel, Neustart mit erhaltenen Daten. Auffälligkeiten mit Folgetickets: Texte „Android-Abfrage“ im Erinnerungs-Ablauf ([BS-113](https://spacy-cloud.atlassian.net/browse/BS-113)), die Tastatur lässt sich nicht einklappen ([BS-112](https://spacy-cloud.atlassian.net/browse/BS-112)), das Querformat ist wenig sinnvoll ([BS-114](https://spacy-cloud.atlassian.net/browse/BS-114), Entscheidung). v0.2.0 setzt die ersten beiden um und schlägt für das dritte vor, es zu belassen.
- **Nicht geprüft:** der Stand v0.2.0 auf einem iPhone (alle Funktionen), die Tastatur ohne „Fertig“-Leiste und die Grenze beim Ziehen auf dem Cursor (im Host nur mit den Gesten von Flutter und dem Theme von iOS belegt), die neuen Texte der Erinnerungen, das Querformat, VoiceOver, die iOS-Einstellung „Größerer Text“, weitere Geräte und iOS-Versionen; die Aussage zu Notch und Dynamic Island war mehrdeutig (Bestätigung offen). Die Schritte aus Health gibt es auf iOS nicht.

**Oberfläche von v0.2.0 (Android und iOS)**

- Home an einem vergangenen Tag: die echte Wischgeste auf dem Glas, die Ansage und der Fokus mit TalkBack und VoiceOver (Fokus nach „Zurück zu heute“ am Datum), Systemschrift.
- „Ziele heute“ und die antippbare Karte: Ansage der Karte als ein Element, gedrückter Zustand, Zurück aus den Modulen.
- „Heute abhaken“: Sprechtexte, Daumenreichweite, die Snackbar über der Navigation.
- „Workout heute“: das Sheet „Wie war dein Tag?“ und die Reihenfolge der Snackbar mit dem Sheet.
- Plus-Menü nach Zielen: Ansage des Leerzustands, Optik des Symbols gegen den Figma-Vektor.
- Tagesring „alle erreicht“: Ringgrün in Hell mit 2,66:1 gegen die Kartenfläche (dekoratives Paar, nur gerechnet und im Host gerendert).
- „Über die App“ und der Lizenztext: Lesbarkeit bei 200 % Schrift, Sprachmarkierung und Aussprache des englischen Textes mit TalkBack und VoiceOver.
- Die Figma-Entwürfe sind noch nicht freigegeben; der Sichtvergleich der im Host gerenderten Bilder mit den Frames ist ein Augenschein, kein Pixelvergleich, und die Bilder liegen nicht im Repository.

## 8. Reproduktion

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
flutter test test/tool/demo_backup_test.dart     # build/demo-backup/demo-daten-90-tage.json (DEMO_TODAY=JJJJ-MM-TT für ein festes Datum)
flutter test --no-pub --test-randomize-ordering-seed=<Seed> test/app test/core test/features test/platform test/tool   # zufällige Reihenfolge (Abschnitt 6.4)
TZ=Pacific/Kiritimati flutter test --no-pub test/app test/core test/features test/platform test/tool                    # fremde Zeitzone (Abschnitt 6.4)
```

Die Tests laufen ohne Netzwerk und ohne Gerät. Die Laufzeit des Gesamtlaufs hängt vom Rechner ab; die Lastzahlen schwanken von Lauf zu Lauf (Abschnitt 4).
