# Architektur

Dieses Dokument beschreibt die tatsächlich umgesetzte Architektur und die Verträge, auf die sich alle Features stützen. Es wird mit den Arbeitspaketen fortgeschrieben (Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51)); beschrieben ist der Code-Stand `c0ce096`. Fachliche Regeln stehen in der Funktions- und technischen Spezifikation des Teams; hier stehen Struktur, Verträge und Muster.

## 1. Schichten

```text
UI (Widgets) -> Controller (Riverpod Notifier) -> Repository / Command -> Drift (SQLite)
                                  \-> reine Domain-Funktionen (Regeln, Berechnungen)
```

- Widgets enthalten weder SQL noch Punkte- oder Zielregeln. Sie lesen Providers und rufen Controller auf. Geprüft per Importsuche: Keine Datei unter `presentation/` oder `lib/core/design/` importiert Drift oder etwas aus `core/database/`; `lib/app/` importiert Drift nirgends und die Datenbankklasse nur für den Start (`bootstrap/app_services.dart`).
- Alle fachlichen Regeln sind reine Dart-Funktionen in `domain/` ohne Drift-, Riverpod- und Widget-Import. 45 der 97 `domain/`-Dateien importieren aus Flutter nur `foundation.dart` (für `@immutable` und einzelne Vergleichshilfen).
- Jede Änderung ist ein **Command** (Abschnitt 4): atomar, idempotent, mit Undo.
- Abgeleitete Werte (Tagesring, Streak, XP, Analyse) werden aus den Fakten berechnet und nie als eigene Wahrheit gespeichert.
- Plattformfunktionen (Benachrichtigungen, Dateien) liegen hinter Schnittstellen (`ReminderPlatform`, Teilen und Dateiauswahl in `lib/core/backup/`); die Domain kennt keine Android-Klassen.
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
    backup/                       Export, Import, Zurücksetzen, Plattform-Adapter (dto/, platform/, testing/)
    bootstrap/                    AppRuntime, Datenbank öffnen und Singletons anlegen, Gerätezone
    commands/                     CommandRunner, UndoAction, Events, SubmissionTracker, AttemptClock, IdGenerator
    config/                       AppConfig (App-Name, stabile technische Kennungen)
    dashboard/domain/             reine Dashboard-Regeln (Layout und Leerzustände, Motivationstexte)
    database/                     Drift-Schema 1 (tables/), Converter, Schlüssel, Verbindung, reaktive Abfragen
    design/                       Tokens, Themes, Komponenten, Bewegung, Symbole, Raster
    errors/                       typisierte Fehler (AppFailure)
    feedback/                     FeedbackService (Vertrag)
    goals/                        application/, domain/ (Ziele, Snapshots, Tagesstatus, Streak), data/ (Snapshots, Fakten, Status, XP-Abgleich)
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

## 3. Datenmodell (Schema 1)

Eine lokale SQLite-Datenbank (Drift) im App-Support-Verzeichnis, Schema-Version 1, 19 Tabellen. Fremdschlüssel sind aktiv; Bereichs- und Enum-Prüfungen existieren zusätzlich zur UI-Validierung als `CHECK`-Constraints. Von `build_runner` erzeugter Code wird nicht eingecheckt.

| Gruppe | Tabellen |
|---|---|
| Singletons | `profile` (id `local`), `app_settings` (id `app`) |
| Module/Konfiguration | `module_status_history`, `dashboard_cards`, `goal_versions`, `daily_goal_snapshots` |
| Körper | `weight_entries` (Gramm, Messbedingungen), `step_days` (ein aktiver Wert je Datum) |
| Ernährung | `water_entries` (ml), `meal_entries` (optionale kcal) |
| Fokus | `focus_sessions` (persistente Zeitsegmente), `workout_entries` (`training_category`, `muscle_groups`, `intensity`) |
| Aufgaben | `tasks`, `habits` (`icon_key`), `habit_checks` |
| Projektion/technisch | `xp_awards`, `command_receipts`, `reminder_rules`, `scheduled_notifications` |

Konventionen:

- IDs sind UUID v4 (Text). Zeitpunkte sind UTC als Integer-Millisekunden; fachliche Tage sind `YYYY-MM-DD` (`LocalDate`) und werden beim Ereignis **eingefroren**, zusammen mit der IANA-Zone.
- Veränderliche Fachtabellen haben `created_at_utc`, `updated_at_utc`, `row_version` (bei jeder Änderung erhöht) und Soft-Delete (`deleted_at_utc`); Abfragen schließen gelöschte Zeilen aus.
- Eligibility-Flags (`gamification_eligible`, `completion_eligibility`, `eligibility`, `reached_goal_eligible`) werden beim ersten Anlegen/Abschließen eingefroren und nie nachträglich auf wahr gesetzt.
- Partielle Unique-Indizes: eine aktive Gewichtsmessung je exakter Messzeit, ein aktiver Schrittwert je Datum, höchstens eine offene Fokus-Sitzung. Weitere Eindeutigkeiten: ein Habit-Check je Habit/Tag, eine Zielversion je Typ/Datum, ein Snapshot je Tag/Zielschlüssel.
- Enum-Schlüssel sind in `core/database/schema_keys.dart` zentral definiert (stabiler Vertrag für Datenbank, Backup und Import).

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
| `dashboardCards` | `DashboardCardDescriptor` (`cardId` aus `SchemaKeys.dashboardCards`, `defaultRank`, `fullWidth`, Builder) |
| `quickActions` | `QuickAction` für das Plus-Menü (`id`, `route`, `plusOrder`, optional `dynamicLabel`); es gibt genau acht Einträge in fester Reihenfolge |
| `initialize(Ref)`, `dispose()` | idempotente Vorbereitung beim Start und bei Reaktivierung, Freigabe beim Ausschalten; nie Daten anfassen |
| `canDeactivate(Ref)` | `CanDeactivate` oder `MustResolveFirst` (zum Beispiel eine offene Fokus-Sitzung) |

Der Modulstatus ist eine Append-only-Historie; Deaktivieren löscht nichts (`ModuleManager`, Fokus-Sperre bei offener Sitzung). Kartenreihenfolge und Sichtbarkeit sind persistent (`DashboardCardRepository`, Drag **und** Auf/Ab-Aktionen). Die Navigation besteht aus vier Tabs in einer `StatefulShellRoute`, den Kernseiten und den Modulrouten; Einzelheiten stehen in [screens/shell.md](screens/shell.md).

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

`DataHarness` (`lib/core/testing/data_harness.dart`) liefert eine echte In-Memory-Datenbank, `FakeClock` (Europe/Berlin), deterministische IDs, Command-Runner und einen `ProviderContainer`. Mit `realProjection: true` laufen Snapshots und XP wie in der App; `seedOnboarded()` legt den Zustand nach dem Onboarding an. Widget-Tests nutzen zusätzlich `test/support/pump_app.dart`. Test-Fixtures verwenden ausschließlich synthetische Daten. Ergebnisse und Befehle: [test-report.md](test-report.md).

## 10. iOS-Vorbereitung

Keine Android-Imports in Domain und Daten; Benachrichtigungen und Dateien liegen hinter Schnittstellen; Projektdateien für iOS sind vorhanden. Es gibt keinen iOS-Build und keine iOS-Prüfung (siehe [known-limitations.md](known-limitations.md)).

## 11. Start der App

Von `main()` bis zum ersten echten Frame (Code: `lib/main.dart`, `lib/app/app.dart`, `lib/core/bootstrap/`):

1. `main()` installiert die zentrale Fehlerbehandlung, schaltet Edge-to-Edge ein und startet `SelfImprovementApp`.
2. Das Start-Gate zeigt eine neutrale Ladeseite (kein Logo) und ruft `startProductionServices()`. Das ruft `AppRuntime.create()`: Gerätezone erkennen, `SystemClock` mit dieser Zone bauen, die Drift-Datenbank im App-Support-Verzeichnis öffnen, `AppBootstrap.run` (öffnet und migriert die Datenbank und legt die Singleton-Zeilen `profile` und `app_settings` an).
3. Scheitert das, wird die Datenbank geschlossen und ein `MigrationFailure` zeigt „Daten konnten nicht geöffnet werden“ mit „Erneut versuchen“; es wird nie automatisch etwas gelöscht oder zurückgesetzt.
4. Gelingt es, baut die laufende App den `GoRouter` (mit dem Guard für das Onboarding) und einen eigenen `ProviderContainer` mit abgeschaltetem automatischem Provider-Retry und diesen Overrides (`buildAppOverrides`): geöffnete Datenbank, Uhr, Zonenquelle, die fünf Module, Router, Snackbar-Feedback, Wasserziel-Prüfung für Erinnerungen, Benachrichtigungs-Canceller und Backup-Listener.
5. **Vor dem ersten echten Frame** (`_prepare`): die Erinnerungs-Plattform wird initialisiert (ein Fehler dort lässt die App trotzdem starten, die Einstellungen zeigen das Problem), die Gerätezone wird gelesen, und `profileProvider`, `moduleStatusesProvider` und `appSettingsProvider` werden gelesen. Damit gibt es weder ein falsches Theme noch einen falschen Screen im ersten Frame.
6. Danach erscheint die App (`MaterialApp.router` mit dem Theme aus den Einstellungen und dem Schalter für reduzierte Bewegung) und `AppWiring.start()` verdrahtet das Dauerhafte: Modul-Lebenszyklus (`initialize` der aktiven Module), automatischer Abgleich und Lebenszyklus der Erinnerungen, Uhr (Rückkehr in die App und Mitternacht), Aufräumen temporärer Export- und Dateiauswahl-Kopien, Tipps auf Benachrichtigungen und die Start-Nutzlast (nur nach abgeschlossenem Onboarding).

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
