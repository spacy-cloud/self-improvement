# Backup-Format (Version 2)

Dieses Dokument beschreibt die lokale Sicherung der App: den Dateiaufbau, jedes Feld, die Importregeln und das Verhalten beim Ersetzen und Zurücksetzen. Es ist aus der Implementierung (`lib/core/backup/`) und dem Datenbankschema (`lib/core/database/`) abgeleitet; die Tests in `test/core/backup/` prüfen, dass Dokument, DTOs und Schema übereinstimmen.

Die App schreibt **Version 2** und liest zusätzlich **Version 1** (Dateien aus v0.1.0) über einen ausdrücklichen, getesteten Aufwärtsschritt (Abschnitt „Aufwärtsschritt von Version 1 auf 2“). Version 2 gehört zum Datenvertrag des Releases v0.2.0 (Jira-Epic [BS-98](https://spacy-cloud.atlassian.net/browse/BS-98), Entscheidungen D-015 und D-016 in [implementation-decisions.md](implementation-decisions.md)).

## Überblick

- Eine Sicherung ist **eine UTF-8-codierte JSON-Datei** (ein Byte-Order-Mark am Anfang wird toleriert).
- Dateiname: `self-improvement-backup-YYYY-MM-DD-HHmm.json`. Datum und Uhrzeit sind die **lokale Zeit des Exports** in der aktuellen Zeitzone des Geräts (zweistellig mit führenden Nullen, Beispiel `self-improvement-backup-2026-07-15-2330.json`).
- Das Format ist ein stabiler Vertrag: Es gibt typisierte DTO-Klassen mit strengem `fromJson` und `toJson`, kein loses JSON. Felder heißen wie die Spalten des Datenbankschemas (`snake_case`, englisch).
- Die Datei enthält **persönliche Daten im Klartext** (Name, Gewicht, Notizen, Mahlzeiten, Aufgaben). Sie ist weder verschlüsselt noch signiert. Wer sie erhält, kann sie lesen und – nach dem Import in diese App – als Datenbestand verwenden.
- Die Datei wird kompakt geschrieben (keine Einrückung, damit das Limit von 10 MiB nicht von Leerraum verbraucht wird). Gleiche Daten ergeben **byte-identische** Dateien: Schlüssel- und Zeilenreihenfolge sind festgelegt. Das gilt auch für den Rundlauf Export, Import, Export.
- Der Marker `levelup_life_backup` ist seit Version 1 unverändert; nur `schemaVersion` unterscheidet die Versionen.

## Root-Objekt

Alle Felder sind Pflicht, weitere Felder werden abgelehnt.

| Feld | Typ | Regel |
|---|---|---|
| `format` | Text | genau `levelup_life_backup` (technische Kennung, kein sichtbarer Markenname) |
| `schemaVersion` | Ganzzahl | `2` in jeder Datei, die die App schreibt; der Import liest außerdem `1` (siehe „Aufwärtsschritt von Version 1 auf 2“); jede andere Version, auch `3` und höher, wird abgelehnt |
| `exportedAtUtc` | Zeitpunkt | Zeitpunkt des Exports (UTC, Millisekunden) |
| `appVersion` | Text | 1–32 Zeichen aus `A-Z a-z 0-9 . + -`, beginnt mit Buchstabe oder Ziffer; informativ, wird nicht gegen die laufende App geprüft |
| `data` | Objekt | die 17 Abschnitte (in Version 1: 16), siehe unten |

## Datentypen und Konventionen

| Typ | Darstellung |
|---|---|
| UUID | kleingeschriebene Standardform `8-4-4-4-12` Hexziffern, z. B. `00000000-0000-4000-8000-000000000001` |
| Zeitpunkt | ISO-8601 in UTC mit genau drei Nachkommastellen und `Z`: `2026-03-03T06:45:10.250Z`. Keine Offsets, kein fehlender Millisekundenteil, keine Sekunde 60, keine Stunde 24 |
| Datum | `YYYY-MM-DD`, ein echtes Kalenderdatum (kein 30. Februar) |
| Uhrzeit | `HH:mm` (`00:00` bis `23:59`) |
| Ganzzahl | JSON-Zahl ohne Nachkommaanteil; `71500.0` ist **keine** Ganzzahl |
| Wahrheitswert | JSON `true` oder `false` (nicht `0`, `1` oder `"true"`) |
| optional | Ein fehlender Wert steht als JSON `null`. Das Feld selbst muss immer vorhanden sein |
| Liste von Texten | echtes JSON-Array von Texten, nicht ein Text, der ein Array enthält |
| Zeitzone | IANA-Name, den die App kennt (z. B. `Europe/Berlin`, `UTC`) |
| Textlänge | Anzahl der Unicode-Zeichen (Code Points), wie SQLite `length()` sie zählt: ein Emoji zählt als 1. Das Zeichen NUL und unpaarige Surrogate sind ungültig |

Gewichte sind ganze Gramm in 100-g-Schritten, Wassermengen ganze Milliliter. Die Dateien enthalten **keine** gespeicherten XP- oder Streak-Zähler.

## Abschnitte von `data`

Alle 17 Schlüssel müssen vorhanden sein (eine Datei der Version 1 hat 16, siehe „Aufwärtsschritt von Version 1 auf 2“). `profile` und `app_settings` sind einzelne Objekte (Singletons), alle anderen Arrays (auch leer). Die Spalte „null“ zeigt, ob `null` erlaubt ist. Alle Zeitpunkte sind UTC, alle Uhrzeiten `HH:mm`. Felder und Abschnitte, die Version 2 neu eingeführt hat, sind in den Tabellen mit „(neu in Version 2)“ gekennzeichnet; in einer Datei der Version 2 sind sie Pflicht.

Es werden nur **aktive** Fachdatensätze exportiert. Weich gelöschte Zeilen (`deleted_at_utc`) sind nicht Teil des Formats; das Feld `deleted_at_utc` ist unbekannt und wird abgelehnt.

### `profile`

Genau ein Objekt. In der Datenbank hat die Zeile die feste ID `local`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | Text | nein | genau `local` |
| `display_name` | Text | ja | 1–40 Zeichen |
| `started_local_date` | Datum | nein | erster Tag dieser Installation |
| `height_cm` | Ganzzahl | ja | 100–250 |
| `age_years` | Ganzzahl | ja | 18–120 |
| `start_weight_grams` | Ganzzahl | ja | 20000–350000, Vielfaches von 100 |
| `target_weight_grams` | Ganzzahl | ja | 20000–350000, Vielfaches von 100 |
| `motivation_goals` | Liste von Texten | nein | bekannte Schlüssel (`lose_weight`, `get_fitter`, `move_more`, `live_healthier`, `build_habits`), ohne Duplikate, gegebenenfalls leer |
| `onboarding_completed` | Wahrheitswert | nein | |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `app_settings`

Genau ein Objekt (Datenbank-ID `app`).

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | Text | nein | genau `app` |
| `theme_mode` | Text | nein | `system`, `light`, `dark`, `oled` |
| `reduce_motion` | Wahrheitswert | nein | |
| `haptics` | Wahrheitswert | nein | |
| `notifications_enabled` | Wahrheitswert | nein | **Wunschzustand**; die echte Berechtigung kommt nie aus der Datei |
| `last_known_timezone` | Text | ja | bekannte Zeitzone |
| `health_steps_sync_enabled` | Wahrheitswert | nein | (neu in Version 2) **Wunschzustand** des Schalters „Schritte aus Health übernehmen“, ohne den Schalter ist er `false`; die echte Berechtigung der Health-Schnittstelle kommt nie aus der Datei |
| `health_steps_last_sync_at_utc` | Zeitpunkt | ja | (neu in Version 2) Ende des letzten Abgleichs mit der Health-App; `null`, solange keiner lief; nur zur Anzeige |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `module_status_history`

Historie der Modulaktivierung, sortiert nach `effective_at_utc`, dann `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig in diesem Abschnitt |
| `module_id` | Text | nein | `body`, `nutrition`, `focus`, `tasks`, `gamification` |
| `effective_at_utc` | Zeitpunkt | nein | |
| `local_date` | Datum | nein | Tag der Änderung |
| `enabled` | Wahrheitswert | nein | |

### `dashboard_cards`

Sichtbarkeit und Reihenfolge der Karten, sortiert nach `sort_index`, dann `card_id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `card_id` | Text | nein | `steps`, `water`, `weight`, `workout`, `focus`, `tasks`, `nutrition`, `xp`; eindeutig |
| `module_id` | Text | nein | muss zur Karte passen: `steps` und `weight` gehören zu `body`, `water` und `nutrition` zu `nutrition`, `workout` und `focus` zu `focus`, `tasks` zu `tasks`, `xp` zu `gamification` |
| `visible` | Wahrheitswert | nein | |
| `sort_index` | Ganzzahl | nein | ≥ 0 |

### `goal_versions`

Zielwerte mit Gültigkeit ab einem Datum, sortiert nach `effective_from_date`, `goal_type`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `goal_type` | Text | nein | `water`, `steps`, `weight_entry`, `focus_minutes`, `task_completion`, `workout_weekly`, `workout_daily` (neu in Version 2: das optionale Tagesziel „Workout heute“ des Moduls `focus`; ohne Version ist es aus) |
| `target_integer` | Ganzzahl | ja | ≥ 1 |
| `enabled` | Wahrheitswert | nein | |
| `effective_from_date` | Datum | nein | `goal_type` und Datum sind zusammen eindeutig |
| `created_at_utc` | Zeitpunkt | nein | |

### `daily_goal_snapshots`

Welche Ziele an einem Tag galten (eingefrorene Schwellen); ob ein Ziel erfüllt wurde, steht nie in der Datei. Sortiert nach `local_date`, `goal_key`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `local_date` | Datum | nein | |
| `goal_key` | Text | nein | ein Zielart-Schlüssel (siehe `goal_versions`) oder `habit:<UUID der Gewohnheit>`; Datum und Schlüssel sind zusammen eindeutig |
| `module_id` | Text | nein | bekanntes Modul |
| `target_integer` | Ganzzahl | ja | ≥ 0 |
| `applicable` | Wahrheitswert | nein | |

Ein Snapshot darf auf eine Gewohnheit verweisen, die inzwischen gelöscht wurde und deshalb nicht in `habits` steht: er bleibt als Historie erhalten.

### `weight_entries`

Sortiert nach `occurred_at_utc`, dann `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `weight_grams` | Ganzzahl | nein | 20000–350000, Vielfaches von 100 |
| `occurred_at_utc` | Zeitpunkt | nein | als Messzeitpunkt in diesem Abschnitt eindeutig |
| `local_date` | Datum | nein | beim Erfassen eingefrorener Tag |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `before_toilet` | Wahrheitswert | nein | |
| `after_drinking` | Wahrheitswert | nein | |
| `after_eating` | Wahrheitswert | nein | |
| `note` | Text | ja | höchstens 500 Zeichen |
| `gamification_eligible` | Wahrheitswert | nein | beim Erfassen eingefroren |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `step_days`

Eine Schrittsumme je Tag (von Hand eingetragen oder aus der Health-App übernommen), sortiert nach `local_date`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `local_date` | Datum | nein | eindeutig (ein Tageswert je Datum) |
| `steps` | Ganzzahl | nein | 0–100000 |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `reached_goal_eligible` | Wahrheitswert | ja | `null`, bis das Tagesziel erstmals erreicht wurde |
| `xp_goal_target_steps` | Ganzzahl | ja | erreichte Schwelle, ≥ 1; `null` genau dann, wenn `reached_goal_eligible` `null` ist |
| `source` | Text | nein | (neu in Version 2) Quelle des Tageswerts: `manual` (von Hand eingetragen) oder `health` (aus der Health-App übernommen) |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `water_entries`

Sortiert nach `occurred_at_utc`, dann `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `amount_ml` | Ganzzahl | nein | 50–2000 |
| `occurred_at_utc` | Zeitpunkt | nein | |
| `local_date` | Datum | nein | |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `note` | Text | ja | höchstens 500 Zeichen |
| `gamification_eligible` | Wahrheitswert | nein | |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `meal_entries`

Mahlzeiten ohne Ziele und ohne XP (deshalb kein Eligibility-Feld), sortiert nach `occurred_at_utc`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `name` | Text | nein | 1–80 Zeichen |
| `kcal` | Ganzzahl | ja | 0–5000; `null` heißt „nicht angegeben“, `0` ist ein echter Wert |
| `occurred_at_utc` | Zeitpunkt | nein | |
| `local_date` | Datum | nein | |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `note` | Text | ja | höchstens 500 Zeichen |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `focus_sessions`

Fokus-Sitzungen, sortiert nach `started_at_utc`, `id`. **Eine laufende Sitzung wird als `paused` exportiert**: `accumulated_seconds` ist die bisherige Zeit plus die seit Segmentbeginn verstrichenen Sekunden zum Exportzeitpunkt, begrenzt auf `planned_seconds` (eine zurückgestellte Uhr zählt als 0 zusätzliche Sekunden); `segment_started_at_utc` ist `null`. Die laufende Sitzung in der Datenbank bleibt dabei unverändert; alle übrigen Felder, auch `updated_at_utc` und `row_version`, stehen so in der Datei, wie sie gespeichert sind. Erreicht die berechnete Zeit die Planzeit, bleibt der Status `paused`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `category` | Text | nein | `reading`, `learning`, `programming`, `meditation`, `other` |
| `planned_seconds` | Ganzzahl | nein | 300–10800 |
| `accumulated_seconds` | Ganzzahl | nein | ≥ 0 und ≤ `planned_seconds` |
| `segment_started_at_utc` | Zeitpunkt | ja | in Version 1 immer `null` |
| `started_at_utc` | Zeitpunkt | nein | |
| `ended_at_utc` | Zeitpunkt | ja | nicht vor `started_at_utc` |
| `completed_local_date` | Datum | ja | genau dann gesetzt, wenn `status` `completed` ist |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `status` | Text | nein | `paused`, `awaiting_confirmation`, `completed`, `discarded`; `running` ist in einer Datei ungültig |
| `note` | Text | ja | höchstens 500 Zeichen |
| `gamification_eligible` | Wahrheitswert | nein | beim Abschluss eingefroren |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

Höchstens **eine** Sitzung darf offen sein (`paused` oder `awaiting_confirmation`). Eine importierte offene Sitzung bleibt pausiert und muss ausdrücklich fortgesetzt werden.

### `workout_entries`

Sortiert nach `occurred_at_utc`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `training_category` | Text | nein | `strength`, `cardio`, `mobility`, `sport` |
| `title` | Text | ja | 1–80 Zeichen |
| `duration_minutes` | Ganzzahl | nein | 1–600 |
| `muscle_groups` | Liste von Texten | nein | bekannte Schlüssel (`chest`, `shoulders`, `back`, `biceps`, `triceps`, `legs`, `core`, `full_body`), ohne Duplikate, gegebenenfalls leer |
| `intensity` | Text | ja | `low`, `moderate`, `high` |
| `occurred_at_utc` | Zeitpunkt | nein | |
| `local_date` | Datum | nein | |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `note` | Text | ja | höchstens 500 Zeichen |
| `gamification_eligible` | Wahrheitswert | nein | |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `workout_day_marks`

(Abschnitt neu in Version 2.) Ein Tag, den die Nutzerin oder der Nutzer als Ruhetag oder als übersprungenes Workout markiert hat; das tägliche Workout-Ziel zählt einen solchen Tag als erreicht, ohne XP. Sortiert nach `local_date`, `id`. Höchstens **eine** Markierung je Tag.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `local_date` | Datum | nein | der markierte lokale Tag; eindeutig (eine Markierung je Datum) |
| `kind` | Text | nein | `rest` (Ruhetag) oder `skipped` (Workout übersprungen) |
| `timezone_id` | Text | nein | bekannte Zeitzone, beim Markieren eingefroren |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `tasks`

Sortiert nach `created_at_utc`, `id`. Offen heißt: die drei Abschlussfelder sind alle `null`. Die optionale Erinnerung (drei Felder, neu in Version 2) ist unabhängig vom Abschluss.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `title` | Text | nein | 1–120 Zeichen |
| `description` | Text | ja | höchstens 1000 Zeichen |
| `priority` | Text | nein | `low`, `normal`, `high` |
| `due_local_date` | Datum | ja | |
| `tags_json` | Liste von Texten | nein | höchstens 5 Tags zu je 1–20 Zeichen, ohne Leerzeichen am Rand, ohne Duplikate (Groß-/Kleinschreibung ignoriert) |
| `completed_at_utc` | Zeitpunkt | ja | alle drei Abschlussfelder sind gemeinsam gesetzt oder gemeinsam `null` |
| `completed_local_date` | Datum | ja | siehe oben |
| `timezone_id` | Text | ja | bekannte Zeitzone |
| `completion_eligibility` | Wahrheitswert | ja | beim Abschluss eingefroren; siehe oben |
| `reminder_at_utc` | Zeitpunkt | ja | (neu in Version 2) Zeitpunkt der Erinnerung an die Aufgabe (UTC); die drei `reminder_*`-Felder sind gemeinsam gesetzt oder gemeinsam `null` |
| `reminder_local_date` | Datum | ja | (neu in Version 2) lokaler Tag der Erinnerung, beim Setzen eingefroren; siehe oben |
| `reminder_timezone_id` | Text | ja | (neu in Version 2) bekannte Zeitzone, beim Setzen eingefroren; siehe oben |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `habits`

Tägliche Ja/Nein-Gewohnheiten, sortiert nach `created_at_utc`, `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `title` | Text | nein | 1–80 Zeichen |
| `started_local_date` | Datum | nein | |
| `archived_from_date` | Datum | ja | erster Tag ohne Anwendbarkeit; nicht vor `started_local_date` |
| `reminder_local_time` | Uhrzeit | ja | |
| `icon_key` | Text | nein | `book`, `moon`, `drop`, `check`, `flame`, `heart` |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `habit_checks`

Sortiert nach `local_date`, `habit_id`, `id`. Checks einer gelöschten Gewohnheit werden nicht exportiert.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `habit_id` | UUID | nein | muss eine Gewohnheit aus `habits` sein (Fremdschlüssel) |
| `local_date` | Datum | nein | je Gewohnheit und Datum höchstens ein Check |
| `checked_at_utc` | Zeitpunkt | nein | |
| `timezone_id` | Text | nein | bekannte Zeitzone |
| `eligibility` | Wahrheitswert | nein | beim Abhaken eingefroren |
| `created_at_utc` | Zeitpunkt | nein | |
| `updated_at_utc` | Zeitpunkt | nein | |
| `row_version` | Ganzzahl | nein | ≥ 1 |

### `reminder_rules`

Sortiert nach `id`.

| Feld | Typ | null | Regel |
|---|---|---|---|
| `id` | UUID | nein | eindeutig |
| `module_id` | Text | nein | bekanntes Modul |
| `kind` | Text | nein | `water`, `habit`, `focus_end` |
| `local_time` | Uhrzeit | ja | |
| `enabled` | Wahrheitswert | nein | |
| `route` | Text | nein | App-Route: 1–200 Zeichen, beginnt mit genau einem `/`, nur URL-Pfadzeichen (`A-Z a-z 0-9 _ - . / ? = & % : ~ + @`), kein Schema, kein Host |

## Was nicht exportiert wird – und warum

| Tabelle | Grund |
|---|---|
| `xp_awards` | abgeleitete Werte. XP, Level und Streak werden nach dem Import aus den Fakten neu berechnet; die Datei enthält keinen Zähler, der der Wahrheit widersprechen könnte |
| `command_receipts` | technische Idempotenz-Quittungen der Befehlsausführung, auf einer anderen Installation bedeutungslos |
| `scheduled_notifications` | technische Projektion der beim Betriebssystem geplanten Erinnerungen (mit lokalen IDs); sie wird nach dem Import aus `reminder_rules` neu geplant |
| weich gelöschte Zeilen | keine Papierkorb-Funktion in Version 1; gelöschte Einträge sind nicht Teil der Sicherung |

Tabellen dieser Liste im Abschnitt `data` werden beim Import abgelehnt.

Aufgenommen werden dagegen alle Daten **deaktivierter Module** sowie die benötigte Historie: Modulstatus-Verlauf, Zielversionen und Tagesziel-Snapshots.

## Importregeln

Der Import **ersetzt** den gesamten Datenbestand, er führt nie zusammen (kein Merge). Vor jeder Änderung wird die komplette Datei geprüft; erst wenn alles gültig ist, zeigt die App eine Vorschau.

Prüfstufen (jede meldet alle ihre Probleme):

1. **Datei:** höchstens 10 MiB (10 485 760 Bytes, einschließlich), gültiges UTF-8, gültiges JSON, Wurzel ist ein Objekt.
2. **Wurzel:** Format-Kennung und Schema-Version (1 oder 2); sind sie falsch, wird die Datei nicht weiter gelesen. Eine Datei der Version 1 durchläuft danach den Aufwärtsschritt (siehe unten) und wird ab hier wie eine Datei der Version 2 gelesen. Danach `exportedAtUtc`, `appVersion` und `data`; unbekannte Felder werden abgelehnt.
3. **Abschnitte:** alle 17 vorhanden, `profile` und `app_settings` als einzelnes Objekt, die übrigen als Array. Höchstens **50 000 Datensätze** insgesamt (jedes Array-Element zählt, die beiden Singletons je 1); wird das Limit überschritten, wird kein Datensatz mehr gelesen.
4. **Datensätze:** Typen, Pflichtfelder, UUID-Form, Datums- und Zeitformate, Grenzen, bekannte Schlüssel (Modul, Dashboard-Karte, Kategorien, Prioritäten, Quelle eines Schrittwerts, Art einer Markierung, …), Textlängen, JSON-Arrays, die Abschlussregeln von Aufgaben und Fokus-Sitzungen, die Erinnerungsregel von Aufgaben (alle drei `reminder_*`-Felder oder keines), „Ende nicht vor Start“, „keine laufende Sitzung“. Die Grenzen entsprechen den CHECK-Regeln der Datenbank.
5. **Beziehungen:** IDs je Abschnitt eindeutig, eindeutige Messzeitpunkte beim Gewicht, ein Schrittwert je Datum, eine Markierung je Datum (`workout_day_marks`), ein Check je Gewohnheit und Tag, Zielversionen je Zielart und Datum, Snapshots je Datum und Schlüssel, Fremdschlüssel `habit_checks.habit_id`, höchstens eine offene Sitzung.
6. **Snapshot-Konsistenz** (optionaler Erweiterungspunkt `SnapshotConsistencyChecker`): Abgleich der Tages-Snapshots mit Ziel-, Modul- und Gewohnheitshistorie; nur für sonst gültige Dateien.

Die Prüfung meldet bis zu **20 Probleme** auf Deutsch, z. B. `weight_entries[3]: Gewicht außerhalb des erlaubten Bereichs`. Die Meldungen enthalten **keine Werte aus der Datei** (auch keine Namen unbekannter Felder). Positionen zählen ab 0 wie im Array.

Bekannte Grenze: Doppelte Schlüssel innerhalb eines JSON-Objekts erkennt der JSON-Parser nicht; der zuletzt genannte gewinnt.

## Ersetzen (Replace)

1. Die Vorschau zeigt Profilname (oder den Standardnamen „Mein Profil“), Zahl der Einträge je Bereich, Exportzeitpunkt, App-Version und die Format-Version **der Datei** (eine Datei aus v0.1.0 zeigt „Version 1“). Ohne ausdrückliche Bestätigung („Vorhandene App-Daten ersetzen“) ändert sich nichts.
2. Nach der Bestätigung läuft **eine einzige Transaktion**: alle Zeilen aller Tabellen löschen (auch `xp_awards`, `command_receipts`, `scheduled_notifications`), die Datensätze der Datei mit unveränderten IDs, Zeitstempeln und Zeilenversionen einfügen (weiche Löschmarken bleiben `null`), danach die XP-Auszeichnungen über den Projektions-Synchronisierer für **alle Tage mit Fakten** neu berechnen (Gewicht, Schritte, Wasser, Workouts, Habit-Checks, Abschlusstage von Aufgaben und Fokus-Sitzungen; Mahlzeiten zählen nicht).
   `workout_day_marks` ist eine Tabelle ohne Fremdschlüssel und Teil dieser Löschung und dieses Einfügens; Ruhetage und übersprungene Tage vergeben keine XP und lösen deshalb keine XP-Neuberechnung aus.
3. Jeder Fehler – auch ein Fehler erst beim Einfügen oder in der Projektion – macht die Transaktion rückgängig. Der bisherige Bestand bleibt vollständig erhalten.
4. Nach dem erfolgreichen Abschluss storniert die App alle geplanten Betriebssystem-Benachrichtigungen und benachrichtigt die App-Oberfläche (Provider neu laden, Erinnerungen aus den importierten Regeln neu planen). Schlägt einer dieser Folgeschritte fehl, bleibt der Import bestehen; das Ergebnis des Imports meldet es, damit die Oberfläche darauf hinweisen kann.
5. Die Berechtigung für Benachrichtigungen kommt immer vom Gerät, nie aus der Datei. `notifications_enabled` ist nur ein Wunschzustand.

Eine importierte offene Fokus-Sitzung ist pausiert.

## Zurücksetzen

„Alle App-Daten löschen“ verlangt eine eigene Bestätigung mit dem Wort `LÖSCHEN` (Groß-/Kleinschreibung und Leerzeichen am Rand egal). Dann löscht **eine Transaktion** alle Zeilen aller Tabellen und legt die beiden Singletons (`profile`, `app_settings`) wie bei einer Neuinstallation neu an: Das Onboarding beginnt von vorn. Nach dem Abschluss werden die Betriebssystem-Benachrichtigungen storniert, zwischengespeicherte Export-Dateien gelöscht und die Oberfläche benachrichtigt; ein Fehler dabei macht das Zurücksetzen nicht rückgängig. Zurücksetzen wird nie durch das Deaktivieren eines Moduls, einen Migrations- oder Datenbankfehler oder einen abgelehnten oder fehlgeschlagenen Import ausgelöst.

## Export und Weitergabe

Der Export liest alle Tabellen in **einer** Lese-Transaktion (ein konsistenter Stand), schreibt die Datei in den Cache-Ordner der App und öffnet das System-Teilen-Menü. Es gibt keine automatische Übertragung in eine Cloud; die Nutzerin oder der Nutzer entscheidet über das Ziel. Die temporäre Datei wird nach dem Teilen und beim nächsten Start gelöscht. Das Abbrechen des Teilens ändert keine Daten.

Eine Sicherung, die diese App selbst nicht wieder importieren würde (z. B. wegen der Grenzen oder einer ungültigen Datenlage), wird trotzdem erstellt, aber als nicht wiederherstellbar gekennzeichnet, damit die Oberfläche warnen kann.

## Aufwärtsschritt von Version 1 auf 2

Dateien der Version 1 (geschrieben von v0.1.0) werden vor dem strengen Lesen in die Form der Version 2 gebracht. Der Schritt ist eine reine Funktion auf dem decodierten JSON (`BackupUpgrade` in `lib/core/backup/backup_upgrade.dart`): Er verändert seine Eingabe nicht, und alles, was der Leser über ältere Dateien weiß, steht dort an einer Stelle. Danach liest derselbe strenge Leser die Datei wie eine der Version 2; das Ergebnis ist ein Dokument der aktuellen Form, das beim Export als Version 2 geschrieben wird (`BackupDocument.sourceSchemaVersion` merkt sich die Version der Datei, die Import-Vorschau zeigt sie an).

Was eine Datei der Version 1 in Version-2-Begriffen bedeutet, trägt der Schritt ein:

| Abschnitt | Neu in Version 2 | Wert für eine Datei der Version 1 |
|---|---|---|
| `workout_day_marks` | ganzer Abschnitt | `[]` (kein Tag war markiert) |
| `step_days` | Feld `source` | `manual` (jeder Tageswert wurde von Hand eingetragen) |
| `app_settings` | Feld `health_steps_sync_enabled` | `false` (der Abgleich mit der Health-App war aus) |
| `app_settings` | Feld `health_steps_last_sync_at_utc` | `null` (kein Abgleich lief) |
| `tasks` | Felder `reminder_at_utc`, `reminder_local_date`, `reminder_timezone_id` | alle drei `null` (keine Aufgabe hatte eine Erinnerung) |

Alle übrigen Werte der Datei bleiben unverändert (IDs, Zeitstempel, Zeilenversionen, eingefrorene Eignungs-Flags). XP und Streak stehen nicht in der Datei und werden nach dem Import wie bisher aus den Fakten neu berechnet.

**Eine Datei der Version 1 mit Inhalt der Version 2 wird abgelehnt.** Enthält sie den Abschnitt `workout_day_marks` („Unbekannter Abschnitt“) oder eines der neuen Felder in einem Datensatz („Unbekanntes Zusatzfeld“, mit Abschnitt und Position, ohne den Wert), ist die Datei beschädigt oder zusammengesetzt und wird wie jede andere Datei mit unbekannten Feldern abgelehnt; es wird nichts halb geglaubt. Andere Probleme einer Version-1-Datei haben dieselben Meldungen und Positionen wie vor Version 2. Umgekehrt braucht eine Datei der Version 2 alle neuen Felder und den neuen Abschnitt (Pflicht). Jede andere `schemaVersion` wird abgelehnt: `0`, `3` und höher, eine Zahl mit Nachkommaanteil, ein Text oder ein fehlender Wert (Meldung „unterstützt: Version 1 und 2“).

Das Gegenstück in der Datenbank sind die benannten, einzeln getesteten Migrationsschritte von Schema 1 auf 2 (`lib/core/database/schema_migrations.dart`, Entscheidung D-016). Beide Wege führen zum selben Ergebnis: Eine mit dem neuen Code geöffnete v0.1.0-Datenbank und eine importierte v0.1.0-Sicherung derselben Daten exportieren byte-identische Dateien der Version 2 (`test/core/backup/backup_v1_import_test.dart`).

## Versionspolitik

- `schemaVersion` ist `2`. Der Import liest `1` und `2`; eine **unbekannte Version wird abgelehnt**, auch eine neuere. Es gibt **keine stillschweigende Migration** beliebiger Dateien.
- Eine künftige Änderung des Formats erhöht die Version; eine neue App-Version darf ältere Versionen nur über ausdrücklich implementierte, getestete Schritte einlesen (der nächste Schritt bekommt eine eigene Funktion und eigene Tests, die Kette Version 1, 2, 3 läuft nacheinander).
- Version 2 ist **nicht abwärtskompatibel**: Die App v0.1.0 kann Sicherungen der Version 2 nicht lesen (sie lehnt die `schemaVersion` ab und ändert nichts), und eine Datenbank der Schema-Version 2 öffnet v0.1.0 nicht. Vor dem Update auf v0.2.0 sollte eine Sicherung exportiert werden; sie bleibt in v0.2.0 lesbar.
- Unbekannte Zusatzfelder sind ein Fehler (in jeder Version), damit fremde oder beschädigte Dateien früh auffallen.
- `appVersion` ist rein informativ.

## Fixtures aus Version 1

Die Tests der Aufwärtsschritte lesen Dateien, die der **unveränderte Code von v0.1.0** geschrieben hat (der Stand, auf dem die Fixtures entstanden, Commit `26243de` des iOS-Branches, hat dieselben `lib/`, `test/` und `pubspec.*` wie der Tag `v0.1.0`), nicht von Hand gebaute Beispiele. Sie liegen in `test/fixtures/v1/`, nur mit synthetischen Daten („Mia Muster“, kein Personenbezug):

| Datei | Inhalt | Entstehung |
|---|---|---|
| `v1-database.sql` | SQL-Textdump der Datenbank (Schema 1, `user_version` 1): zehn Tage über alle Module, alle 19 Tabellen mit Zeilen, auch weich gelöschte, XP-Vergaben, Quittungen und geplante Benachrichtigungen | Die echten Repositories und Commands (`DataHarness` mit echter Projektion, feste Uhr, deterministische IDs, Fake der Benachrichtigungs-Plattform) bauten die Daten auf; der Dump schreibt Schema und Zeilen in Erstellungsreihenfolge |
| `v1-database-backup.json` | die Sicherung, die der Exporter von v0.1.0 von genau dieser Datenbank am Ende des Ablaufs machte | derselbe Lauf |
| `demo-backup-v1-90-tage.json` | die 90-Tage-Beispielsicherung des Demo-Generators (`test/tool/demo_backup_test.dart`, 394 KB) | `DEMO_TODAY=2026-03-31 flutter test test/tool/demo_backup_test.dart`, Datei aus `build/demo-backup/` |
| `rich-backup-v1.json` | jedes Feld mit einem Wert ungleich dem Standard, Sonderzeichen in Texten | `richBackupJson()` der Testhilfen |
| `fresh-install-backup-v1.json` | Sicherung einer frischen Installation (leere Arrays, Standard-Einstellungen) | Export einer frisch angelegten Datenbank |

Das Erzeugungsskript steht als Text daneben (`generate_v1_fixtures.dart.txt`; es gilt nur auf Code der Schema-Version 1) und liefert bei jedem Lauf dieselben Bytes. Die Fixtures werden nie neu erzeugt, wenn sich das Schema ändert: Sie sind der feste Ausgangspunkt der Migrationstests.

## Beispiel (synthetische Daten)

Frei erfundene Person und Werte. Zur Lesbarkeit steht je Datensatz eine Zeile; die echte Datei ist kompakt. Der Beispielinhalt wird von den Tests mit dem echten Validator geprüft.

```json
{
  "format": "levelup_life_backup",
  "schemaVersion": 2,
  "exportedAtUtc": "2026-03-04T18:30:00.000Z",
  "appVersion": "1.0.0",
  "data": {
    "profile": {"id":"local","display_name":"Mia Muster","started_local_date":"2026-02-02","height_cm":168,"age_years":34,"start_weight_grams":78000,"target_weight_grams":70000,"motivation_goals":["move_more","build_habits"],"onboarding_completed":true,"created_at_utc":"2026-02-02T09:00:00.000Z","updated_at_utc":"2026-03-01T17:00:00.000Z","row_version":3},
    "app_settings": {"id":"app","theme_mode":"dark","reduce_motion":false,"haptics":true,"notifications_enabled":true,"last_known_timezone":"Europe/Berlin","health_steps_sync_enabled":true,"health_steps_last_sync_at_utc":"2026-03-04T18:00:00.000Z","created_at_utc":"2026-02-02T09:00:00.000Z","updated_at_utc":"2026-02-20T08:00:00.000Z","row_version":2},
    "module_status_history": [
      {"id":"00000000-0000-4000-8000-000000000001","module_id":"body","effective_at_utc":"2026-02-02T09:00:00.000Z","local_date":"2026-02-02","enabled":true},
      {"id":"00000000-0000-4000-8000-000000000002","module_id":"nutrition","effective_at_utc":"2026-02-02T09:00:00.000Z","local_date":"2026-02-02","enabled":true},
      {"id":"00000000-0000-4000-8000-000000000003","module_id":"focus","effective_at_utc":"2026-02-02T09:00:00.000Z","local_date":"2026-02-02","enabled":true},
      {"id":"00000000-0000-4000-8000-000000000004","module_id":"tasks","effective_at_utc":"2026-02-02T09:00:00.000Z","local_date":"2026-02-02","enabled":true},
      {"id":"00000000-0000-4000-8000-000000000005","module_id":"gamification","effective_at_utc":"2026-02-02T09:00:00.000Z","local_date":"2026-02-02","enabled":true}
    ],
    "dashboard_cards": [
      {"card_id":"steps","module_id":"body","visible":true,"sort_index":0},
      {"card_id":"water","module_id":"nutrition","visible":true,"sort_index":1},
      {"card_id":"weight","module_id":"body","visible":false,"sort_index":2}
    ],
    "goal_versions": [
      {"id":"00000000-0000-4000-8000-000000000011","goal_type":"steps","target_integer":8000,"enabled":true,"effective_from_date":"2026-02-02","created_at_utc":"2026-02-02T09:00:00.000Z"},
      {"id":"00000000-0000-4000-8000-000000000012","goal_type":"water","target_integer":2500,"enabled":true,"effective_from_date":"2026-02-02","created_at_utc":"2026-02-02T09:00:00.000Z"},
      {"id":"00000000-0000-4000-8000-000000000013","goal_type":"workout_daily","target_integer":1,"enabled":true,"effective_from_date":"2026-03-04","created_at_utc":"2026-03-03T20:00:00.000Z"}
    ],
    "daily_goal_snapshots": [
      {"id":"00000000-0000-4000-8000-000000000021","local_date":"2026-03-03","goal_key":"water","module_id":"nutrition","target_integer":2500,"applicable":true},
      {"id":"00000000-0000-4000-8000-000000000022","local_date":"2026-03-03","goal_key":"habit:00000000-0000-4000-8000-000000000071","module_id":"tasks","target_integer":null,"applicable":true}
    ],
    "weight_entries": [
      {"id":"00000000-0000-4000-8000-000000000031","weight_grams":71800,"occurred_at_utc":"2026-03-02T06:41:00.000Z","local_date":"2026-03-02","timezone_id":"Europe/Berlin","before_toilet":true,"after_drinking":false,"after_eating":false,"note":null,"gamification_eligible":true,"created_at_utc":"2026-03-02T06:41:05.120Z","updated_at_utc":"2026-03-02T06:41:05.120Z","row_version":1},
      {"id":"00000000-0000-4000-8000-000000000032","weight_grams":71500,"occurred_at_utc":"2026-03-03T06:45:10.250Z","local_date":"2026-03-03","timezone_id":"Europe/Berlin","before_toilet":true,"after_drinking":false,"after_eating":false,"note":"nach dem Aufstehen","gamification_eligible":true,"created_at_utc":"2026-03-03T06:45:12.000Z","updated_at_utc":"2026-03-03T06:46:00.500Z","row_version":2}
    ],
    "step_days": [
      {"id":"00000000-0000-4000-8000-000000000041","local_date":"2026-03-03","steps":7450,"timezone_id":"Europe/Berlin","reached_goal_eligible":null,"xp_goal_target_steps":null,"source":"manual","created_at_utc":"2026-03-03T19:00:00.000Z","updated_at_utc":"2026-03-03T19:00:00.000Z","row_version":1},
      {"id":"00000000-0000-4000-8000-000000000042","local_date":"2026-03-04","steps":8420,"timezone_id":"Europe/Berlin","reached_goal_eligible":true,"xp_goal_target_steps":8000,"source":"health","created_at_utc":"2026-03-04T17:55:00.000Z","updated_at_utc":"2026-03-04T18:00:00.000Z","row_version":2}
    ],
    "water_entries": [
      {"id":"00000000-0000-4000-8000-000000000051","amount_ml":250,"occurred_at_utc":"2026-03-03T07:10:00.000Z","local_date":"2026-03-03","timezone_id":"Europe/Berlin","note":null,"gamification_eligible":true,"created_at_utc":"2026-03-03T07:10:00.000Z","updated_at_utc":"2026-03-03T07:10:00.000Z","row_version":1}
    ],
    "meal_entries": [
      {"id":"00000000-0000-4000-8000-000000000061","name":"Haferbrei mit Beeren","kcal":380,"occurred_at_utc":"2026-03-03T06:55:00.000Z","local_date":"2026-03-03","timezone_id":"Europe/Berlin","note":null,"created_at_utc":"2026-03-03T06:56:00.000Z","updated_at_utc":"2026-03-03T06:56:00.000Z","row_version":1}
    ],
    "focus_sessions": [
      {"id":"00000000-0000-4000-8000-000000000081","category":"reading","planned_seconds":1500,"accumulated_seconds":600,"segment_started_at_utc":null,"started_at_utc":"2026-03-04T17:50:00.000Z","ended_at_utc":null,"completed_local_date":null,"timezone_id":"Europe/Berlin","status":"paused","note":null,"gamification_eligible":false,"created_at_utc":"2026-03-04T17:50:00.000Z","updated_at_utc":"2026-03-04T18:00:00.000Z","row_version":2}
    ],
    "workout_entries": [
      {"id":"00000000-0000-4000-8000-000000000091","training_category":"strength","title":"Oberkörper","duration_minutes":45,"muscle_groups":["chest","shoulders"],"intensity":"moderate","occurred_at_utc":"2026-03-03T16:30:00.000Z","local_date":"2026-03-03","timezone_id":"Europe/Berlin","note":null,"gamification_eligible":true,"created_at_utc":"2026-03-03T17:20:00.000Z","updated_at_utc":"2026-03-03T17:20:00.000Z","row_version":1}
    ],
    "workout_day_marks": [
      {"id":"00000000-0000-4000-8000-000000000095","local_date":"2026-03-04","kind":"rest","timezone_id":"Europe/Berlin","created_at_utc":"2026-03-04T17:00:00.000Z","updated_at_utc":"2026-03-04T17:00:00.000Z","row_version":1}
    ],
    "tasks": [
      {"id":"00000000-0000-4000-8000-0000000000a1","title":"Steuerunterlagen sortieren","description":"Belege des letzten Jahres","priority":"high","due_local_date":"2026-03-10","tags_json":["Finanzen"],"completed_at_utc":null,"completed_local_date":null,"timezone_id":null,"completion_eligibility":null,"reminder_at_utc":"2026-03-09T07:30:00.000Z","reminder_local_date":"2026-03-09","reminder_timezone_id":"Europe/Berlin","created_at_utc":"2026-03-01T10:00:00.000Z","updated_at_utc":"2026-03-01T10:00:00.000Z","row_version":1},
      {"id":"00000000-0000-4000-8000-0000000000a2","title":"Altpapier rausbringen","description":null,"priority":"low","due_local_date":null,"tags_json":[],"completed_at_utc":"2026-03-03T17:45:10.500Z","completed_local_date":"2026-03-03","timezone_id":"Europe/Berlin","completion_eligibility":true,"reminder_at_utc":null,"reminder_local_date":null,"reminder_timezone_id":null,"created_at_utc":"2026-03-02T09:00:00.000Z","updated_at_utc":"2026-03-03T17:45:10.500Z","row_version":2}
    ],
    "habits": [
      {"id":"00000000-0000-4000-8000-000000000071","title":"Lesen","started_local_date":"2026-02-02","archived_from_date":null,"reminder_local_time":"20:30","icon_key":"book","created_at_utc":"2026-02-02T09:30:00.000Z","updated_at_utc":"2026-02-02T09:30:00.000Z","row_version":1}
    ],
    "habit_checks": [
      {"id":"00000000-0000-4000-8000-000000000072","habit_id":"00000000-0000-4000-8000-000000000071","local_date":"2026-03-03","checked_at_utc":"2026-03-03T20:45:00.000Z","timezone_id":"Europe/Berlin","eligibility":true,"created_at_utc":"2026-03-03T20:45:00.000Z","updated_at_utc":"2026-03-03T20:45:00.000Z","row_version":1}
    ],
    "reminder_rules": [
      {"id":"00000000-0000-4000-8000-0000000000b1","module_id":"nutrition","kind":"water","local_time":"10:00","enabled":true,"route":"/nutrition/water"}
    ]
  }
}
```

## Hinweise zum Datenschutz

- Die App sendet nichts über ein Netzwerk; die Sicherung entsteht nur lokal und verlässt das Gerät erst, wenn die Nutzerin oder der Nutzer sie im Teilen-Menü weitergibt. Die Oberfläche soll vor dem Export darauf hinweisen, dass die Sicherung persönliche Einträge enthält.
- Protokolle und Fehlermeldungen der Backup-Funktionen enthalten nur Fehlerarten und Anzahlen, nie Namen, Messwerte, Notizen oder Dateiinhalte.
- Die lokale SQLite-Datenbank ist nicht zusätzlich verschlüsselt; Schutz bieten Geräte-Sandbox und Gerätesperre.
- Die Felder `health_steps_*` und `source` machen die App nicht netzfähig: Der Abgleich mit der Health-App liest nur lokal auf dem Gerät (BS-97) und die Sicherung enthält nur den Wunschzustand und den Zeitpunkt, nie Rohdaten der Health-App.
