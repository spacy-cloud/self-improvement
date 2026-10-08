# Architektur

Dieses Dokument beschreibt die tatsächlich umgesetzte Architektur und die Verträge, auf die sich alle Features stützen. Es wird mit den Arbeitspaketen fortgeschrieben (Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51)); beschrieben ist der Code-Stand `a90f3b1` (Ende der Kette der Pull Requests des Releases v0.2.0; der Stand von V1 war `c0ce096`). Fachliche Regeln stehen in der Funktions- und technischen Spezifikation des Teams; hier stehen Struktur, Verträge und Muster.

## 1. Schichten

```text
UI (Widgets) -> Controller (Riverpod Notifier) -> Repository / Command -> Drift (SQLite)
                                  \-> reine Domain-Funktionen (Regeln, Berechnungen)
```

- Widgets enthalten weder SQL noch Punkte- oder Zielregeln. Sie lesen Providers und rufen Controller auf. Geprüft per Importsuche: Keine Datei unter `presentation/` oder `lib/core/design/` importiert Drift oder etwas aus `core/database/`; `lib/app/` importiert Drift nirgends und die Datenbankklasse nur für den Start (`bootstrap/app_services.dart`).
- Alle fachlichen Regeln sind reine Dart-Funktionen in `domain/` ohne Drift-, Riverpod- und Widget-Import. 54 der 108 `domain/`-Dateien importieren aus Flutter nur `foundation.dart` (für `@immutable` und einzelne Vergleichshilfen).
- Jede Änderung ist ein **Command** (Abschnitt 4): atomar, idempotent, mit Undo.
- Abgeleitete Werte (Tagesring, Streak, XP, Analyse) werden aus den Fakten berechnet und nie als eigene Wahrheit gespeichert.
- Plattformfunktionen (Benachrichtigungen, Dateien, Health-Schritte) liegen hinter Schnittstellen (`ReminderPlatform`, Teilen und Dateiauswahl in `lib/core/backup/`, `HealthStepsSource` in `lib/core/health/`); die Domain kennt keine Android-Klassen.
- Ausnahmen, die der Code macht: Die Erinnerungs-Engine liest die Datenbank an zwei Stellen direkt in ihrer `application/`-Schicht (`notification_entry_resolver.dart`, `reminder_auto_reconciler.dart`). `core/` kennt in vier Dateien Feature-Code: die Modulregistrierung (`core/modules/module_registry.dart`, die fünf Modulklassen) und den XP-Projektor des Moduls Gamification (`core/goals/data/projection_synchronizer_impl.dart`, `core/providers/core_providers.dart`, `core/testing/data_harness.dart`).
- Features importieren aus anderen Features nur Dateien aus `domain/`, Provider aus `application/` und kleine Hilfen aus `presentation/` (Routen, gemeinsame Widgets), nie eine Datei aus `data/` (Repository-Implementierungen). Auch das ist eine Importsuche, kein Test: Nur `test/features/settings/architecture_test.dart` und `test/core/notifications/architecture_test.dart` prüfen Importregeln, für ihren eigenen Bereich.

## 2. Verzeichnisse

```text
lib/
  main.dart                       Fehlerbehandlung installieren, Edge-to-Edge, runApp
  app/
    app.dart                      Start-Gate, Theme, Router, Zurück-Dispatcher
    bootstrap/                    AppServices, neutrale Lade- und Fehlerseite, zentrale Fehlerbehandlung
    feedback/                     Snackbar-Umsetzung von FeedbackService
    router/                       Routen, Guards, Seitenbau (Übergänge), Zurück-Reihenfolge
    screens/                      "Nicht gefunden", "Modul ausgeschaltet" (Seite und Tab)
    shell/                        Tab-Gerüst, Plus-Menü
    wiring/                       Provider-Overrides und Dauerverdrahtung (Erinnerungen, Backup, Uhr)
  core/
    analysis/                     Analyse-Engine (application/, data/, domain/)
    backup/                       Export, Import, Aufwärtsschritt älterer Versionen (backup_upgrade.dart), Zurücksetzen, Plattform-Adapter (dto/, platform/, testing/)
    bootstrap/                    AppRuntime, Datenbank öffnen und Singletons anlegen, Gerätezone
    commands/                     CommandRunner, UndoAction, Events, SubmissionTracker, AttemptClock, IdGenerator
    config/                       AppConfig (App-Name, stabile technische Kennungen)
    dashboard/domain/             reine Dashboard-Regeln (Layout und Leerzustände, Motivationstexte)
    database/                     Drift-Schema 2 (tables/), Migrationsschritte (schema_migrations.dart), Converter, Schlüssel, Verbindung, reaktive Abfragen
    design/                       Tokens, Themes, Komponenten, Bewegung, Symbole, Raster
    errors/                       typisierte Fehler (AppFailure)
    feedback/                     FeedbackService (Vertrag)
    goals/                        application/, domain/ (Ziele, Snapshots, Tagesstatus, Streak), data/ (Snapshots, Fakten, Status, XP-Abgleich)
    health/                       Schnittstelle zur Health-Quelle (domain/: HealthStepsSource, Tagesfenster; platform/: Fake und Adapter), siehe Abschnitt 13
    modules/                      Modulvertrag, Registry der fünf Module, Status, ModuleManager, Kartenkonfiguration
    notifications/                Erinnerungs-Engine (application/, data/, domain/, platform/)
    onboarding/, profile/, settings/   Repositories und Befehle für Start, Profil und Einstellungen
    providers/                    Riverpod-Grundprovider (core_providers) und Command-Provider (command_providers)
    testing/                      DataHarness, Test-Datenbank, Fehler-Executor, aufzeichnende Projektion
    time/                         ClockService (UTC, IANA-Zone, lokale Kalendertage), FakeClock
  features/
    analysis/ dashboard/ modules/ onboarding/ profile/ reminders/ settings/   Oberflächen und ihre Anwendungsschicht
    body/ nutrition/ focus/ tasks/ gamification/                              Module, je domain/, data/, application/, presentation/ nach Bedarf
    body/steps/                   Schritte als Unterbereich des Moduls body
  shared/                         LocalDate, LocalTime, deutsche Datums- und Zahlentexte
test/                             spiegelt lib/; test/support/ hält gemeinsame Hilfen (pump_app, db_fixtures, synthetic_records)
integration_test/                 Emulator-Job (siehe test-report.md)
```

Feature-UI importiert Core-Komponenten, aber niemals die konkrete Repository-Implementierung eines anderen Features (Abschnitt 1).

## 3. Datenmodell (Schema 2)

Eine lokale SQLite-Datenbank (Drift) im App-Support-Verzeichnis, Schema-Version 2, 20 Tabellen. Fremdschlüssel sind aktiv; Bereichs- und Enum-Prüfungen existieren zusätzlich zur UI-Validierung als `CHECK`-Constraints. Von `build_runner` erzeugter Code wird nicht eingecheckt.

| Gruppe | Tabellen |
|---|---|
| Singletons | `profile` (id `local`), `app_settings` (id `app`) |
| Module/Konfiguration | `module_status_history`, `dashboard_cards`, `goal_versions`, `daily_goal_snapshots` |
| Körper | `weight_entries` (Gramm, Messbedingungen), `step_days` (ein aktiver Wert je Datum, Quelle `manual` oder `health`) |
| Ernährung | `water_entries` (ml), `meal_entries` (optionale kcal) |
| Fokus | `focus_sessions` (persistente Zeitsegmente), `workout_entries` (`training_category`, `muscle_groups`, `intensity`), `workout_day_marks` (Ruhetag oder übersprungen je Tag) |
| Aufgaben | `tasks` (mit optionaler Erinnerung), `habits` (`icon_key`), `habit_checks` |
| Projektion/technisch | `xp_awards`, `command_receipts`, `reminder_rules`, `scheduled_notifications` |

Konventionen:

- IDs sind UUID v4 (Text). Zeitpunkte sind UTC als Integer-Millisekunden; fachliche Tage sind `YYYY-MM-DD` (`LocalDate`) und werden beim Ereignis **eingefroren**, zusammen mit der IANA-Zone.
- Veränderliche Fachtabellen haben `created_at_utc`, `updated_at_utc`, `row_version` (bei jeder Änderung erhöht) und Soft-Delete (`deleted_at_utc`); Abfragen schließen gelöschte Zeilen aus.
- Eligibility-Flags (`gamification_eligible`, `completion_eligibility`, `eligibility`, `reached_goal_eligible`) werden beim ersten Anlegen/Abschließen eingefroren und nie nachträglich auf wahr gesetzt.
- Partielle Unique-Indizes: eine aktive Gewichtsmessung je exakter Messzeit, ein aktiver Schrittwert je Datum, eine aktive Ruhetag-Markierung je Datum, höchstens eine offene Fokus-Sitzung. Weitere Eindeutigkeiten: ein Habit-Check je Habit/Tag, eine Zielversion je Typ/Datum, ein Snapshot je Tag/Zielschlüssel.
- Enum-Schlüssel sind in `core/database/schema_keys.dart` zentral definiert (stabiler Vertrag für Datenbank, Backup und Import).

### Datenvertrag v2 (Schema 2 und Backup 2, BS-98)

Schema 2 hat genau die Daten der drei schemaberührenden Features von v0.2.0 vorbereitet (Entscheidungen D-015 und D-016); alles ist additiv, vorhandene Zeilen behalten jeden Wert.

| Feature | Datenbank | Standard | Sicherung (Version 2) |
|---|---|---|---|
| BS-99 Tagesziel „Workout heute“, Ruhetag, Überspringen | Tabelle `workout_day_marks` (`kind` `rest` oder `skipped`, höchstens eine aktive Zeile je `local_date`, Audit- und Soft-Delete-Spalten); Zieltyp `workout_daily` in `goal_versions` | keine Markierung; das Ziel ist ohne Zeile in `goal_versions` aus | neuer Abschnitt `workout_day_marks`; `workout_daily` als `goal_type` und als Zielschlüssel der Snapshots |
| BS-97 Schritte aus Health | `step_days.source` (`manual` oder `health`); `app_settings.health_steps_sync_enabled`, `health_steps_last_sync_at_utc` | `manual`; aus; nie abgeglichen | Felder `source` (je Schrittetag) sowie `health_steps_sync_enabled` und `health_steps_last_sync_at_utc` in `app_settings` |
| BS-111 Erinnerung je Aufgabe | `tasks.reminder_at_utc`, `reminder_local_date`, `reminder_timezone_id` (alle drei oder keines, unabhängig vom Abschluss) | keine Erinnerung | drei Felder je Aufgabe |

Die Datenbank wird von Schema 1 durch benannte, einzeln getestete Schritte in einer Transaktion migriert (`SchemaMigrations` in `lib/core/database/schema_migrations.dart`: `workout_day_marks`, `workout_daily_goal_type` als Umbau von `goal_versions`, `step_day_source`, `health_steps_settings`, `task_reminder`); ein neueres Schema wird nicht geöffnet. Dateien der Backup-Version 1 liest der Import über den Aufwärtsschritt `BackupUpgrade` (Einzelheiten und Fixtures in [backup-format.md](backup-format.md)). Die Features setzen mit Repositories und Commands auf diese Tabellen und Spalten auf und ändern Schema und Backup nicht mehr.

## 4. Commands, Transaktionen, Undo

`CommandRunner.run(commandId, type, body)` führt in **einer** Datenbanktransaktion aus (der genaue Ablauf steht als Sequenz in Abschnitt 12):

1. Receipt prüfen (`command_receipts`): bekannte ID ist ein Replay und tut nichts (`CommandOutcome.replayed`).
2. `body(ctx)` validiert und mutiert (Fehler -> Rollback).
3. Projektion für die betroffenen Tage synchronisieren (`ProjectionSynchronizer.syncDays`): zuerst Tagesziel-Snapshots, dann XP-Awards.
4. Receipt schreiben.

Erst nach dem Commit werden Ereignisse veröffentlicht (`ActivityCommitted`, `ActivityRemoved`, `GoalsChanged`, `ModulesChanged`, `FocusStateChanged`). Datenbankstreams sind maßgeblich; ein verlorenes Ereignis verliert keine Daten.

- **Command-IDs:** der erste Submit erzeugt eine ID; ein Retry mit unverändertem Inhalt verwendet dieselbe ID, geänderter Inhalt bekommt eine neue (`SubmissionTracker`). Ein neuer Eintrag, dessen Zeit der Nutzer nicht anfasst, speichert „jetzt“ beim Speichern; damit ein Retry denselben Inhalt hat, friert `AttemptClock` diesen Zeitpunkt für den ersten Versuch ein. Eine fehlgeschlagene Mutation hinterlässt weder Datensatz noch Receipt.
- **`CommandContext`** friert den Zeitpunkt, die Zone und das lokale Datum **einmal** je Command ein (`nowUtc`, `today`, `freeze(utc)`); `isGamificationEnabled()` wird innerhalb der Transaktion gelesen.
- **Undo** ist eine inverse Mutation mit eigener Command-ID und `row_version`-Prüfung (`UndoAction`): wurde der Datensatz inzwischen geändert, entsteht `ConflictFailure(staleVersion)` statt eines stillen Überschreibens. Undo-Fenster 8 Sekunden, höchstens eine sichtbare Undo-Aktion, kein Replay nach Prozessneustart.
- **Fehler:** `AppFailure` (`validation`, `not_found`, `conflict`, `storage`, `migration`, `permission`, `unsupported_backup`) mit deutschen Nutzertexten ohne personenbezogene Werte. Unbekannte Fehler werden zu `StorageFailure`; protokolliert wird nur der Typname. Fehler außerhalb von Commands fängt `installErrorHandling` (`lib/app/bootstrap/error_handling.dart`): Es protokolliert nur Fehlertyp und Bibliothek, nie Meldung oder Stacktrace; im Debug-Modus zeigt zusätzlich das Framework seinen vollständigen Bericht an (der Meldungstexte enthalten kann), Builds außerhalb des Debug-Modus ersetzen ein fehlgeschlagenes Widget durch einen neutralen deutschen Satz.

## 5. Zeitmodell

`ClockService` (UTC-Zeit, IANA-Zone, lokales Datum, Wanduhr -> UTC mit Erkennung der Sommerzeitlücke und früherem Offset bei Überlappung) ist injizierbar (`FakeClock` in Tests). Tagesarithmetik läuft ausschließlich über `LocalDate.addDays` (Kalender, nie `Duration(hours: 24)`). Eine spätere Reise verschiebt vorhandene Einträge nicht: lokales Datum und Zone sind am Datensatz eingefroren. „Heute“ steht im `todayProvider` und wird bei Rückkehr in die App und zum lokalen Mitternacht neu gelesen (`AppWiring`).

## 6. Ziele, Snapshots, XP, Streak

- `goal_versions` speichern Zielwert und Schalter mit Wirksamkeitsdatum; Änderungen gelten **ab morgen** (`GoalsCommands`), mehrere Änderungen für morgen ersetzen dieselbe Version.
- `daily_goal_snapshots` frieren je Tag ein, welche Ziele mit welcher Schwelle galten. Fehlende Tage werden aus Versionen und Modulhistorie nachgezogen (Batches zu 365 Tagen); es gibt keinen Snapshot vor dem Profilstart oder für zukünftige Tage. Der Snapshot von **heute** folgt Modulwechseln sofort (Maskierung), Vergangenes bleibt unverändert. Ob ein Ziel erfüllt ist, wird nie gespeichert, sondern aus den Fakten berechnet (`computeDayStatus`). Ein Gewohnheitsziel, dessen Gewohnheit keine Zeile hat (ein Backup trägt gelöschte Gewohnheiten nicht), fehlt im gelesenen Snapshot; das Format erlaubt es weiter als Verlauf.
- Tagesring = erfüllte / anwendbare Ziele (kein Ring bei 0 anwendbaren Zielen). Aktiver Tag (Streak) = mindestens ein erfülltes anwendbares Ziel; Kompletttag (Analyse) = alle erfüllt.
- **XP** sind eine Projektion: für jeden betroffenen Tag werden aus allen aktiven Fakten die gewünschten Awards berechnet (`computeDayAwards`, Regeln in `XpRules`) und mit `xp_awards` abgeglichen (einfügen/ändern/löschen; `xp_projector.dart`). Gesamt-XP = Summe gültiger Awards; Level = 1 + XP/100.
- Reaktive Lesemodelle (`DayStatusRepository`, Streak) nutzen `watchComputed` (`core/database/reactive.dart`): Neuberechnung bei Tabellenänderungen, zusammengefasst und nie pro Widget-Build.

## 7. Module, Karten, Navigation

Fünf mitgelieferte Module (`body`, `nutrition`, `focus`, `tasks`, `gamification`, gesammelt in `bundledModules`) implementieren `SelfImprovementModule`:

| Teil des Vertrags | Inhalt |
|---|---|
| `id`, `title`, `description`, `icon` | stabile Kennung (`ModuleId`) und deutscher Anzeigetext für die Modulverwaltung |
| `routes` | Routen des Moduls, einmal registriert und zentral durch den Modulstatus geschützt (Pfade statisch vor parametrisch) |
| `dashboardCards` | `DashboardCardDescriptor` (`cardId` aus `SchemaKeys.dashboardCards`, `defaultRank`, `fullWidth`, Builder, optional `dayBuilder` für die Karte eines vergangenen Tages, BS-93) |
| `quickActions` | `QuickAction` für das Plus-Menü (`id`, `route`, `plusOrder`, optional `dynamicLabel`); es gibt genau acht Einträge in fester Reihenfolge |
| `initialize(Ref)`, `dispose()` | idempotente Vorbereitung beim Start und bei Reaktivierung, Freigabe beim Ausschalten; nie Daten anfassen |
| `canDeactivate(Ref)` | `CanDeactivate` oder `MustResolveFirst` (zum Beispiel eine offene Fokus-Sitzung) |

Der Modulstatus ist eine Append-only-Historie; Deaktivieren löscht nichts (`ModuleManager`, Fokus-Sperre bei offener Sitzung). Kartenreihenfolge und Sichtbarkeit sind persistent (`DashboardCardRepository`, Drag **und** Auf/Ab-Aktionen). Die Navigation besteht aus vier Tabs in einer `StatefulShellRoute`, den Kernseiten (darunter seit v0.2.0 `/goals/today` und `/settings/about`) und den Modulrouten; Einzelheiten stehen in [screens/shell.md](screens/shell.md).

**Home zeigt einen Tag (BS-93, D-029).** `selectedDayProvider` hält den gewählten Tag nur im Speicher (`null` heißt heute), `browsedDayProvider` begrenzt ihn auf heute und die sieben Tage davor, nie vor dem Profilstart; ein neuer Kalendertag wirft die Wahl weg. `DashboardView` trägt den Tag und den Status dieses Tages, gebaut aus dem Snapshot und den Fakten des Tages (`dayStatusProvider`). Für einen anderen Tag baut jedes Modul seine Karte über `dayBuilder` selbst, nur lesend; ein Modul ohne `dayBuilder` fehlt an diesen Tagen, statt die Zahlen von heute zu zeigen. Die Seite „Ziele heute“ liest dieselbe `DashboardView` und rechnet keine zweite Zahl ([screens/dashboard-gamification.md](screens/dashboard-gamification.md), Abschnitte 12 und 13).

## 8. Muster für ein Feature (Referenz: Gewichtsfluss)

Die vollständige Referenzimplementierung liegt in `lib/features/body/`:

| Datei | Rolle |
|---|---|
| `domain/weight_input.dart`, `weight_validation.dart` | strenger Parser, Validierung, deutsche Feldfehler |
| `domain/weight_calculations.dart`, `weight_overview.dart` | reine Berechnungen und das Übersichtsmodell |
| `domain/weight_entry.dart` | Domainmodell und Entwurf (`WeightDraft`) |
| `data/weight_repository.dart` | Lesen (Streams) und Commands (create/update/delete/undo) |
| `application/weight_providers.dart` | Riverpod-Provider (Einträge, Auswahl, Übersicht) |
| `application/weight_form_controller.dart` | Formularzustand, Submit-Sperre, Command-ID-Wiederverwendung (`SubmissionTracker`), eingefrorenes „jetzt“ bei Wiederholung (`AttemptClock`), Duplikat-Hinweis |
| `test/features/body/...` | Parser-, Berechnungs-, Repository-, Controller-, Provider- und Screen-Tests |

Regeln für jede Mutation: erst `validate...` (wirft `ValidationFailure` mit Feldern), dann prüfen (Duplikate, Version), dann schreiben, Einfrieren von Datum/Zone über `ctx.freeze`, `affectedDays` angeben (bei verschobenem Datum alt **und** neu), `UndoAction` zurückgeben (Create -> Soft-Delete mit `row_version` 1, Update -> Werte zurück mit neuer Version, Delete -> Wiederherstellen derselben ID). Die Oberfläche des Referenzflusses beschreibt [screens/body-weight-steps.md](screens/body-weight-steps.md).

## 9. Tests

`DataHarness` (`lib/core/testing/data_harness.dart`) liefert eine echte In-Memory-Datenbank, `FakeClock` (Europe/Berlin), deterministische IDs, Command-Runner und einen `ProviderContainer`. Mit `realProjection: true` laufen Snapshots und XP wie in der App; `seedOnboarded()` legt den Zustand nach dem Onboarding an. Widget-Tests nutzen zusätzlich `test/support/pump_app.dart`. Test-Fixtures verwenden ausschließlich synthetische Daten. Die Migrations- und Importtests des Datenvertrags v2 lesen Fixtures, die der unveränderte Code von v0.1.0 schrieb (`test/fixtures/v1/`, Herkunft in [backup-format.md](backup-format.md)). Ergebnisse und Befehle: [test-report.md](test-report.md).

## 10. iOS-Vorbereitung

Keine Android-Imports in Domain und Daten; Benachrichtigungen und Dateien liegen hinter Schnittstellen; Projektdateien für iOS sind vorhanden. Ein CI-Workflow baut eine IPA ohne Zertifikat (BS-95; die Hauptdatei trägt eine Ad-hoc-Signatur mit den Entitlements, D-034); der iOS-Tester hat die IPA des Stands v0.1.0 am 2026-10-04 auf einem iPhone 15 Pro ohne blockierende Fehler ausprobiert (BS-96, Rückmeldung des Testers, drei Folgetickets, die v0.2.0 umsetzt oder entscheidet). Der Stand v0.2.0 ist auf keinem iPhone geprüft; VoiceOver und weitere Geräte sind ungeprüft, die Schritte aus Health sind für iOS umgesetzt, aber auf keinem iPhone geprüft (Abschnitt 13; siehe [known-limitations.md](known-limitations.md)).

## 11. Start der App

Von `main()` bis zum ersten echten Frame (Code: `lib/main.dart`, `lib/app/app.dart`, `lib/core/bootstrap/`):

1. `main()` installiert die zentrale Fehlerbehandlung, schaltet Edge-to-Edge ein und startet `SelfImprovementApp`.
2. Das Start-Gate zeigt eine neutrale Ladeseite (kein Logo) und ruft `startProductionServices()`. Das ruft `AppRuntime.create()`: Gerätezone erkennen, `SystemClock` mit dieser Zone bauen, die Drift-Datenbank im App-Support-Verzeichnis öffnen, `AppBootstrap.run` (öffnet und migriert die Datenbank und legt die Singleton-Zeilen `profile` und `app_settings` an).
3. Scheitert das, wird die Datenbank geschlossen und ein `MigrationFailure` zeigt „Daten konnten nicht geöffnet werden“ mit „Erneut versuchen“; es wird nie automatisch etwas gelöscht oder zurückgesetzt.
4. Gelingt es, baut die laufende App den `GoRouter` (mit dem Guard für das Onboarding) und einen eigenen `ProviderContainer` mit abgeschaltetem automatischem Provider-Retry und diesen Overrides (`buildAppOverrides`): geöffnete Datenbank, Uhr, Zonenquelle, die fünf Module, Router, Snackbar-Feedback, Wasserziel-Prüfung für Erinnerungen, Benachrichtigungs-Canceller und Backup-Listener.
5. **Vor dem ersten echten Frame** (`_prepare`): die Erinnerungs-Plattform wird initialisiert (ein Fehler dort lässt die App trotzdem starten, die Einstellungen zeigen das Problem), die Gerätezone wird gelesen, und `profileProvider`, `moduleStatusesProvider` und `appSettingsProvider` werden gelesen. Damit gibt es weder ein falsches Theme noch einen falschen Screen im ersten Frame.
6. Danach erscheint die App (`MaterialApp.router` mit dem Theme aus den Einstellungen und dem Schalter für reduzierte Bewegung) und `AppWiring.start()` verdrahtet das Dauerhafte: Modul-Lebenszyklus (`initialize` der aktiven Module), automatischer Abgleich und Lebenszyklus der Erinnerungen, Abgleich mit Health (Start und Rückkehr in die App; bei ausgeschaltetem Schalter endet er sofort), Uhr (Rückkehr in die App und Mitternacht), Aufräumen temporärer Export- und Dateiauswahl-Kopien, Tipps auf Benachrichtigungen und die Start-Nutzlast (nur nach abgeschlossenem Onboarding).

## 12. Ein Befehl

Vom Tipp auf „Speichern“ bis zur Rückmeldung (Referenz: Gewichtseintrag):

1. Der Controller prüft die Eingabe (Feldfehler bleiben am Feld, nichts wird geschrieben), wählt die Befehls-ID (`SubmissionTracker`: gleicher Inhalt gleiche ID, geänderter Inhalt neue ID; unberührtes „jetzt“ eingefroren durch `AttemptClock`) und sperrt weitere Taps (`submitting`).
2. Das Repository ruft `CommandRunner.run(commandId, type, body)`. In **einer** Transaktion:
   1. Receipt prüfen: bekannte ID ist ein Replay, es geschieht nichts (kein neues Undo).
   2. Gesamt-XP vorher lesen.
   3. `body`: validieren (`ValidationFailure`), prüfen (Duplikate, Zeilenversion), schreiben mit eingefrorenem Datum und eingefrorener Zone, `CommandEffect` mit `affectedDays` und `UndoAction` zurückgeben.
   4. Projektion für `affectedDays` synchronisieren: zuerst Tagesziel-Snapshots, dann XP-Awards.
   5. Gesamt-XP nachher lesen, Receipt schreiben.
3. Ein Fehler irgendwo rollt alles zurück (auch das Receipt). `AppFailure` wird weitergereicht, unbekannte Fehler werden zu `StorageFailure` (nur der Typname im Log). Der Controller behält die Eingabe und bietet „Erneut“ an; die Wiederholung nutzt dieselbe Befehls-ID, kann also nie einen zweiten Datensatz erzeugen.
4. Nach dem Commit veröffentlicht der Runner `ActivityCommitted` oder `ActivityRemoved` (mit XP vorher und nachher), danach zusätzliche Ereignisse.
5. Die Oberfläche meldet über `FeedbackService.showSaved(message, undo: outcome.undo)`; die Datenbankstreams (`watchComputed`) aktualisieren Dashboard, Ring und Karten von selbst.
6. „Rückgängig“ (8 Sekunden) führt `UndoAction.run` mit einer **neuen** Befehls-ID aus, mit Prüfung der Zeilenversion: Wurde der Datensatz inzwischen geändert, entsteht ein Konflikt statt eines Überschreibens. Ein zweiter Tipp auf „Rückgängig“ wird ignoriert.

## 13. Schnittstelle zur Health-Quelle (BS-97)

Schritte können aus der Health-App des Telefons übernommen werden (Android: Health Connect; iOS: HealthKit, BS-122, nicht auf einem Gerät geprüft, siehe [known-limitations.md](known-limitations.md)). Die Entscheidungen stehen in D-031 bis D-034 ([implementation-decisions.md](implementation-decisions.md)).

| Teil | Datei | Rolle |
|---|---|---|
| Schnittstelle | `lib/core/health/domain/health_steps_source.dart` | `HealthStepsSource`: `displayName`, `availability`, `access`, `requestAccess`, `totalSteps`, `openInstallPage`, `openAccessSettings`. **Nur lesend, nur Schritte, nur Summen:** `totalSteps` fragt die von der Schnittstelle aggregierte Summe eines Zeitraums, es gibt keine Methode für Rohdatensätze, zum Schreiben oder für andere Datenarten (ein Test hält das fest). Nur `requestAccess` zeigt den Systemdialog, und nur nach dem Erklärtext. |
| Tagesfenster | `lib/core/health/domain/health_day_range.dart` | `healthDayRange` (ein lokaler Kalendertag als Zeitraum von Mitternacht bis Mitternacht in der Zone der Uhr, mit der wirklichen Länge von 23, 24,5 oder 25 Stunden an Tagen mit Zeitumstellung) und `healthSyncWindow` (heute und die sechs Tage davor). Uhr und Zone sind injizierbar (`FakeClock`). |
| Adapter | `lib/core/health/platform/` | `UnsupportedHealthStepsSource` (Standard: kein Zugriff, Schalter ausgeblendet), `FakeHealthStepsSource` (Tests: Verfügbarkeit, Zugriff, Datensätze, Fehler, aufgezeichnete Aufrufe, Gates); `HealthConnectStepsSource` (Android, Standard auf Android: Kanal `de.lf10.selfimprovement/health_steps` zur Kotlin-Klasse `HealthStepsPlugin`, D-031); `HealthKitStepsSource` (iOS, Standard auf iOS: derselbe Kanal zur Swift-Klasse `HealthStepsPlugin`, Anzeigename „Apple Health“, D-034); ein Host-Test ohne Plattformseite meldet „nicht unterstützt“. |
| Konfliktregel | `lib/features/body/steps/domain/step_source.dart` | `StepSource` (`manual`, `health`) und `decideHealthDay`: von Hand eingetragen hat Vorrang, Health füllt leere Tage und aktualisiert nur eigene Werte, „keine Daten“ ändert nichts (D-032). |
| Schreiben | `StepsRepository.applyHealthTotals` | Wendet die Regel je Tag an, in **einem** Befehl (`steps.health.sync`) mit Tagesziel-Snapshot und XP je geänderten Tag; ändert sich nichts, läuft kein Befehl. Die Entscheidung fällt innerhalb der Transaktion noch einmal, ein gleichzeitiger manueller Eintrag gewinnt. |
| Abgleich | `lib/features/body/steps/application/health_steps_sync.dart` | `HealthStepsSync.reconcile`: Schalter und Modul prüfen, Verfügbarkeit und Zugriff prüfen (kein Dialog), die sieben Tage lesen, schreiben, den Zeitpunkt speichern. Wirft nie: jede Störung endet als typisiertes Ergebnis (`HealthSyncKind`). |
| Zustand und Auslöser | `lib/features/body/steps/application/health_steps_controller.dart` | `HealthStepsController` (Einschalten mit Zugriff und erstem Abgleich, Ausschalten, „Zugriff erlauben“, Abgleich per Aktion), `healthStepsStatusProvider` (`HealthStepsStatus.condition`: `hidden`, `unknown`, `off`, `ready`, `interfaceMissing`, `interfaceOutdated`, `accessMissing`, `failed`) und die Auslöser Start und Rückkehr (`HealthStepsAutoSync`, gelesen in `AppWiring.start`). |
| Aktionen | `lib/features/body/steps/application/health_steps_actions.dart` | `HealthStepsActions`: Einschalten, Ausschalten, Aktualisieren, „Zugriff erlauben“, Store und Systemeinstellungen öffnen, jeweils mit den Meldungen an die Nutzerin. Einstellungen, Hinweise und Karte rufen dieselben Aktionen auf, damit derselbe Zustand überall dieselben Worte bekommt (D-033). |
| Texte | `lib/features/body/steps/presentation/health_steps_labels.dart` | Reine Dart-Funktionen: Zeitangaben („heute, 09:41“), Zeilen der Quellenkarte und der Karte auf Home, Untertitel des Schalters, `HealthNotice.of(status)` (Hinweis mit Wegen je Zustand), Warnung der Karte. Die Schnittstelle wird über ihren Anzeigenamen genannt, nie eine Plattform. |
| Oberfläche | `lib/features/body/steps/presentation/health_steps_section.dart`, `health_explanation_sheet.dart`, `health_notice_card.dart` | Gruppe „Schritte“ der Einstellungen (Schalter, Erklärtext vor dem Systemdialog, Hinweis), Quellenkarte, Hinweiskarte und die gemeinsame Textaktion mit 48 px Tippfläche. Karte „Heute“, Übersicht, Formular und Dashboard-Karte der Schritte (`steps_*`) lesen `healthStepsStatusProvider` und zeigen Quelle und Zustand. Die Einstellungsseite bettet die Gruppe nur ein (`HealthStepsSection` liegt im Schritte-Feature, wie `RemindersSection` im Erinnerungs-Feature). |

**Android.** Die Klasse `HealthStepsPlugin` (`android/app/src/main/kotlin/de/lf10/selfimprovement/`, von `MainActivity` im Engine registriert) kennt sechs Methoden: `availability`, `hasAccess`, `requestAccess`, `totalSteps`, `openInstallPage`, `openAccessSettings`. Sie liest ausschließlich `StepsRecord.COUNT_TOTAL` über `HealthConnectClient.aggregate` (Instants, die Tagesgrenzen kommen aus Dart), fragt genau eine Berechtigung (`android.permission.health.READ_STEPS`) und meldet Fehler nur mit Code und Klassenname, nie mit einer Meldung. Das Manifest enthält zusätzlich die Datenschutz-Erklärung (`HealthRationaleActivity` und der Alias für `VIEW_PERMISSION_USAGE`) und die Sichtbarkeit von Health Connect (`<queries>`); es gibt weiter keine Internet-Berechtigung. `test/platform/android_health_manifest_test.dart` liest die Dateien und hält diese Form fest (eine Berechtigung, keine Schreib-, Hintergrund- oder Historienrechte, nur Schritte, nur Aggregation); `test/core/health/health_connect_steps_source_test.dart` prüft die Dart-Seite des Kanals mit einem nachgebauten Kanal und gleicht Kanalname, Methoden, Antworten und Fehlercodes mit der Kotlin-Datei ab.

**iOS.** Die Klasse `HealthStepsPlugin` (`ios/Runner/HealthStepsPlugin.swift`, in `AppDelegate.didInitializeImplicitFlutterEngine` registriert) kennt fünf Methoden: `availability`, `hasAccess`, `requestAccess`, `totalSteps`, `openAccessSettings` (eine Seite zum Installieren gibt es nicht). Sie liest ausschließlich die kumulative Statistik von `stepCount` (`HKStatisticsQuery`), fragt genau eine Berechtigung (Lesen von `stepCount`; die Menge der Typen zum Schreiben ist leer) und meldet Fehler nur mit Code und Klassenname. Jeder Aufruf, der eine Objective-C-Ausnahme auslösen kann (fehlendes Entitlement), läuft in `HealthExceptionGuard`; `availability` meldet dann „nicht unterstützt“, und der Schalter bleibt ausgeblendet. HealthKit sagt nie, ob das Lesen erlaubt wurde: `hasAccess` heißt „schon gefragt“, eine Ablehnung zeigt sich als „keine Daten“ (D-034). `Info.plist` enthält `NSHealthShareUsageDescription`, `Runner.entitlements` genau das Entitlement `com.apple.developer.healthkit`; `ios-ipa.yml` trägt es in einer Ad-hoc-Signatur der Hauptdatei (ohne Zertifikat, Profil und Geheimnis). `test/platform/ios_health_project_test.dart` liest die Dateien und hält diese Form fest; `test/core/health/health_kit_steps_source_test.dart` prüft die Dart-Seite mit einem nachgebauten Kanal und gleicht Kanalname, Methoden, Antworten und Fehlercodes mit der Swift-Datei ab. Nichts davon lief auf einem iPhone.

Der Wunsch (`app_settings.health_steps_sync_enabled`) steht in den Einstellungen und in der Sicherung, die Berechtigung nie: Sie wird bei jedem Abgleich vom Gerät gefragt. Nach einem Import kann der Schalter deshalb an sein, ohne dass Zugriff besteht; der Zustand heißt dann `accessMissing`, und kein Abgleich liest etwas, bevor die Nutzerin den Zugriff erlaubt hat. Solange der Schalter aus ist, fragt weder der Start noch die Rückkehr das Gerät; die Verfügbarkeit liest erst die Einstellungsseite, damit sie den Schalter bei Geräten ohne Schnittstelle ausblenden kann.
