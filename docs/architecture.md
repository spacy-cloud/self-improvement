# Architektur

Dieses Dokument beschreibt die tatsächlich umgesetzte Architektur und die Verträge, auf die sich alle Features stützen. Es wird mit den Arbeitspaketen fortgeschrieben (Jira-Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51)). Fachliche Regeln stehen in der Funktions- und technischen Spezifikation des Teams; hier stehen Struktur, Verträge und Muster.

## 1. Schichten

```text
UI (Widgets) -> Controller (Riverpod Notifier) -> Repository / Command -> Drift (SQLite)
                                  \-> reine Domain-Funktionen (Regeln, Berechnungen)
```

- Widgets enthalten weder SQL noch Punkte- oder Zielregeln. Sie lesen Providers und rufen Controller auf.
- Alle fachlichen Regeln sind reine Dart-Funktionen ohne Flutter-/Drift-Import (`domain/`), sodass sie ohne Datenbank testbar sind.
- Jede Änderung ist ein **Command** (Abschnitt 4): atomar, idempotent, mit Undo.
- Abgeleitete Werte (Tagesring, Streak, XP, Analyse) werden aus den Fakten berechnet und nie als eigene Wahrheit gespeichert.
- Plattformfunktionen (Benachrichtigungen, Dateien) liegen hinter Schnittstellen; die Domain kennt keine Android-Klassen.

## 2. Verzeichnisse

```text
lib/
  main.dart, app/                 Start, Router, Shell
  core/
    commands/                     CommandRunner, UndoAction, Events, SubmissionTracker, IdGenerator
    database/                     Drift-Schema 1, Converter, Schlüssel, reaktive Projektionen
    errors/                       typisierte Fehler (AppFailure)
    goals/                        domain/ (Ziele, Snapshots, Tagesstatus, Streak), data/ (Snapshots, Fakten, Status)
    modules/                      Modulvertrag, Registry, Status, Dashboard-Karten
    onboarding/, profile/, settings/
    providers/                    Riverpod-Grundprovider und Command-Provider
    time/                         ClockService (UTC, IANA-Zone, lokale Kalendertage)
    testing/                      DataHarness, Test-DB, FakeClock-Helfer
    config/                       AppConfig (App-Name, stabile technische Kennungen)
  features/
    body/ nutrition/ focus/ tasks/ gamification/   je domain/, data/, application/, presentation/ nach Bedarf
  shared/                         LocalDate, LocalTime, Zahlenformatierung
```

Feature-UI importiert Core-Komponenten, aber niemals die konkrete Repository-Implementierung eines anderen Features.

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

`CommandRunner.run(commandId, type, body)` führt in **einer** Datenbanktransaktion aus:

1. Receipt prüfen (`command_receipts`): bekannte ID ist ein Replay und tut nichts (`CommandOutcome.replayed`).
2. `body(ctx)` validiert und mutiert (Fehler -> Rollback).
3. Projektion für die betroffenen Tage synchronisieren (`ProjectionSynchronizer.syncDays`): zuerst Tagesziel-Snapshots, dann XP-Awards.
4. Receipt schreiben.

Erst nach dem Commit werden Ereignisse veröffentlicht (`ActivityCommitted`, `ActivityRemoved`, `GoalsChanged`, `ModulesChanged`, `FocusStateChanged`). Datenbankstreams sind maßgeblich; ein verlorenes Ereignis verliert keine Daten.

- **Command-IDs:** der erste Submit erzeugt eine ID; ein Retry mit unverändertem Inhalt verwendet dieselbe ID, geänderter Inhalt bekommt eine neue (`SubmissionTracker`). Eine fehlgeschlagene Mutation hinterlässt weder Datensatz noch Receipt.
- **`CommandContext`** friert den Zeitpunkt, die Zone und das lokale Datum **einmal** je Command ein (`nowUtc`, `today`, `freeze(utc)`); `isGamificationEnabled()` wird innerhalb der Transaktion gelesen.
- **Undo** ist eine inverse Mutation mit eigener Command-ID und `row_version`-Prüfung (`UndoAction`): wurde der Datensatz inzwischen geändert, entsteht `ConflictFailure(staleVersion)` statt eines stillen Überschreibens. Undo-Fenster 8 Sekunden, höchstens eine sichtbare Undo-Aktion, kein Replay nach Prozessneustart.
- **Fehler:** `AppFailure` (`validation`, `not_found`, `conflict`, `storage`, `migration`, `permission`, `unsupported_backup`) mit deutschen Nutzertexten ohne personenbezogene Werte. Unbekannte Fehler werden zu `StorageFailure`; protokolliert wird nur der Typname.

## 5. Zeitmodell

`ClockService` (UTC-Zeit, IANA-Zone, lokales Datum, Wanduhr -> UTC mit Erkennung der Sommerzeitlücke und früherem Offset bei Überlappung) ist injizierbar (`FakeClock` in Tests). Tagesarithmetik läuft ausschließlich über `LocalDate.addDays` (Kalender, nie `Duration(hours: 24)`). Eine spätere Reise verschiebt vorhandene Einträge nicht: lokales Datum und Zone sind am Datensatz eingefroren.

## 6. Ziele, Snapshots, XP, Streak

- `goal_versions` speichern Zielwert und Schalter mit Wirksamkeitsdatum; Änderungen gelten **ab morgen** (`GoalsCommands`), mehrere Änderungen für morgen ersetzen dieselbe Version.
- `daily_goal_snapshots` frieren je Tag ein, welche Ziele mit welcher Schwelle galten. Fehlende Tage werden aus Versionen und Modulhistorie nachgezogen (Batches zu 365 Tagen); es gibt keinen Snapshot vor dem Profilstart oder für zukünftige Tage. Der Snapshot von **heute** folgt Modulwechseln sofort (Maskierung), Vergangenes bleibt unverändert. Ob ein Ziel erfüllt ist, wird nie gespeichert, sondern aus den Fakten berechnet (`computeDayStatus`).
- Tagesring = erfüllte / anwendbare Ziele (kein Ring bei 0 anwendbaren Zielen). Aktiver Tag (Streak) = mindestens ein erfülltes anwendbares Ziel; Kompletttag (Analyse) = alle erfüllt.
- **XP** sind eine Projektion: für jeden betroffenen Tag werden aus allen aktiven Fakten die gewünschten Awards berechnet (`computeDayAwards`) und mit `xp_awards` abgeglichen (einfügen/ändern/löschen). Gesamt-XP = Summe gültiger Awards; Level = 1 + XP/100.
- Reaktive Lesemodelle (`DayStatusRepository`, Streak) nutzen `watchComputed`: Neuberechnung bei Tabellenänderungen, zusammengefasst und nie pro Widget-Build.

## 7. Module, Karten, Navigation

Fünf mitgelieferte Module (`body`, `nutrition`, `focus`, `tasks`, `gamification`) implementieren `SelfImprovementModule` (Routen, Dashboard-Karten, Quick Actions, `canDeactivate`). Der Modulstatus ist eine Append-only-Historie; Deaktivieren löscht nichts (`ModuleManager`, Fokus-Sperre bei offener Sitzung). Kartenreihenfolge und Sichtbarkeit sind persistent (`DashboardCardRepository`, Drag **und** Auf/Ab-Aktionen).

## 8. Muster für ein Feature (Referenz: Gewichtsfluss)

Die vollständige Referenzimplementierung liegt in `lib/features/body/`:

| Datei | Rolle |
|---|---|
| `domain/weight_input.dart`, `weight_validation.dart` | strenger Parser, Validierung, deutsche Feldfehler |
| `domain/weight_calculations.dart`, `weight_overview.dart` | reine Berechnungen und das Übersichtsmodell |
| `domain/weight_entry.dart` | Domainmodell und Entwurf (`WeightDraft`) |
| `data/weight_repository.dart` | Lesen (Streams) und Commands (create/update/delete/undo) |
| `application/weight_providers.dart` | Riverpod-Provider (Einträge, Auswahl, Übersicht) |
| `application/weight_form_controller.dart` | Formularzustand, Submit-Sperre, Command-ID-Wiederverwendung, Duplikat-Hinweis |
| `test/features/body/...` | Parser-, Berechnungs-, Repository-, Controller- und Provider-Tests |

Regeln für jede Mutation: erst `validate...` (wirft `ValidationFailure` mit Feldern), dann prüfen (Duplikate, Version), dann schreiben, Einfrieren von Datum/Zone über `ctx.freeze`, `affectedDays` angeben (bei verschobenem Datum alt **und** neu), `UndoAction` zurückgeben (Create -> Soft-Delete mit `row_version` 1, Update -> Werte zurück mit neuer Version, Delete -> Wiederherstellen derselben ID).

## 9. Tests

`DataHarness` (`lib/core/testing/data_harness.dart`) liefert eine echte In-Memory-Datenbank, `FakeClock` (Europe/Berlin), deterministische IDs, Command-Runner und einen `ProviderContainer`. Mit `realProjection: true` laufen Snapshots und XP wie in der App; `seedOnboarded()` legt den Zustand nach dem Onboarding an. Test-Fixtures verwenden ausschließlich synthetische Daten.

## 10. iOS-Vorbereitung

Keine Android-Imports in Domain und Daten; Benachrichtigungen und Dateien liegen hinter Schnittstellen; Projektdateien für iOS sind vorhanden. Es gibt keinen iOS-Build und keine iOS-Prüfung (siehe [known-limitations.md](known-limitations.md)).
