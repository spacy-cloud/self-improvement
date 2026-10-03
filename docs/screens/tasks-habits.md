# Aufgaben und Gewohnheiten (Screens)

Oberfläche des Moduls `tasks` für [BS-65](https://spacy-cloud.atlassian.net/browse/BS-65) (Aufgaben, P0) und [BS-63](https://spacy-cloud.atlassian.net/browse/BS-63) (tägliche Gewohnheiten, P1). Die Engine (Domain, Daten, Application) war vorhanden; hier entstehen Screens, Modul-Registrierung, Dashboard-Karte und Widget-Tests. Alle Texte sind Deutsch, alle Zahlen und Daten kommen aus echten Daten.

## 1. Screens, Figma-Knoten und Routen

| Screen | Figma-Knoten | Route | Dateien in `lib/features/tasks/presentation/` |
|---|---|---|---|
| Habits-Tab, Ansicht Gewohnheiten | `4023:2` | `/habits` (Shell) | `habits_tab_screen.dart`, `habits_day_view.dart` |
| Habits-Tab, Ansicht Aufgaben | `4036:2` | `/habits?tab=tasks` (Shell) | `tasks_list_view.dart`, `task_row.dart` |
| Aufgabe anlegen | `4040:2` (Tastatur `4057:324`, Verwerfen `4053:929`) | `/tasks/new` | `task_form_screen.dart` |
| Aufgabe bearbeiten, löschen, Undo | Muster Gewicht `4053:314`, `4053:422`, `4053:541` | `/tasks/:id` | `task_form_screen.dart` |
| Gewohnheit anlegen | `4053:2` | `/habits/new` | `habit_form_screen.dart` |
| Gewohnheit bearbeiten | Muster Gewicht | `/habits/:id/edit` | `habit_form_screen.dart` |
| Gewohnheit Detail | `4053:109` | `/habits/:id` | `habit_detail_screen.dart` |
| Dashboard-Karte `tasks` | Home `2013:2` (Kachel Aufgaben) | Karte auf `/` | `tasks_dashboard_card.dart` |

`TasksModule` (`lib/features/tasks/tasks_module.dart`) liefert die Routen (statische Pfade vor den parametrischen: `/tasks/new`, `/tasks/:id`, `/habits/new`, `/habits/:id` mit dem Unterpfad `edit`), die Karte `tasks` (volle Breite, Rang laut Standardreihenfolge) und die Plus-Einträge `task` (Position 5, `/tasks/new`) und `habit` (Position 6, `/habits/new`). `/habits` selbst gehört der Shell; sie baut `HabitsTabScreen(showTasks: ...)`. Der gewählte Segmentwert wird über `GoRouter.go` in die Route zurückgeschrieben, damit ein wiederholter Deep Link `?tab=tasks` immer auf der Aufgabenliste landet.

## 2. Verhalten

**Habits-Tab.** Kopf mit Plus (legt je nach Ansicht Gewohnheit oder Aufgabe an) und Umschalter Aufgaben / Gewohnheiten mit Zählern ("3 offen", "2/5"). Ansicht Gewohnheiten: Wochenleiste der letzten sieben Tage, Fortschrittskarte des gewählten Tages, Liste "Deine Habits" mit runder Checkbox je Gewohnheit, darunter "Archiviert" (beendete Gewohnheiten, nur lesbar). Ein Tipp auf die Checkbox setzt den Zustand (Soll-Zustand, kein blindes Toggle) und zeigt erst nach dem Commit "Abgehakt" mit "Rückgängig" (8 s). Ein Tag der Leiste zeigt die Gewohnheiten dieses Tages und erlaubt Nachtragen oder Entfernen; "Zurück zu heute" und der Tageswechsel setzen die Auswahl zurück. Zukunft, Tage vor dem Start und ab dem Archivdatum sind nicht wählbar (Regeln der Engine, `checkDateError`).

**Aufgabenliste.** Segmente Offen / Erledigt / Alle, Suche in Titel und Beschreibung, Prioritätsfilter (Hoch, Normal, Niedrig, Alle), Reihenfolge der Engine (Priorität hoch zuerst, dann Fälligkeit aufsteigend, ohne Datum zuletzt, dann Erstellzeit und ID). Zeilen werden lazy gebaut. Jede Zeile hat Checkbox (Erledigen/Wiederöffnen als Soll-Zustand), Textbereich (öffnet die Bearbeitung) und Menü (Bearbeiten, Als erledigt markieren oder Wieder öffnen, Löschen). Überfällig steht als Text ("Überfällig seit 02.10.2026") plus rotem Rahmen. Löschen fragt per Sheet nach und bietet danach Undo, das den exakten Zustand inklusive Erledigt-Flag wiederherstellt. Leere Zustände: keine Aufgaben, nichts offen, nichts erledigt, keine Treffer (mit "Suche zurücksetzen"); Ladefehler mit `ErrorState` und erneutem Lesen. Der Filterzustand bleibt beim Tabwechsel erhalten.

**Formulare.** Aufgabe: Titel (1 bis 120), Priorität, Fälligkeit (Heute, Morgen, Kein Datum oder Datumsauswahl, auch in der Vergangenheit), bis zu fünf Tags (Trim, Groß-/Kleinschreibung egal, Hinweise bei Doppelten, Limit und Länge; Vorschläge aus vorhandenen Aufgaben), Beschreibung (bis 1.000). Gewohnheit: Name (1 bis 80), sechs Symbole (Buch, Mond, Tropfen, Haken, Flamme, Herz, Standard Buch) mit gekoppeltem Akzent, nur "Täglich", optionale Erinnerung (Standard aus, Uhrzeit nur bei Aktivierung). Beide: Speichern angepinnt über der Tastatur, Doppeltipp sperrt, Fehler behalten die Eingabe und bieten "Erneut" mit derselben Command-ID, Änderungen verwerfen per Sheet (Header-Zurück und Android-Zurück), Bearbeiten ist erst nach einer Änderung speicherbar und bietet Löschen mit Bestätigung und Undo.

**Gewohnheit Detail.** Serie, Tage erfüllt, Quote, längste Serie, Erinnerungstext; Verlauf der letzten 30 Tage als Raster (Tippen setzt oder entfernt den Haken) oder als Liste ("Als Liste"); Aktionen Bearbeiten, Archivieren (Bestätigung, danach "Ab morgen archiviert", kein Undo, keine Reaktivierung), Löschen (Bestätigung, Undo mit gleicher ID und Verlauf). Beendete Gewohnheiten sind nur lesbar und löschbar.

**Dashboard-Karte.** Volle Breite, bis zu drei heute anwendbare offene Aufgaben (ohne Datum oder bis heute) mit eigener Checkbox: Erledigen in einem Tipp, ohne das Detail zu öffnen. "und N weitere", Kopf und Rest führen zur Liste, leerer Zustand mit "Aufgabe anlegen".

## 3. Abweichungen vom Figma-Entwurf

| Abweichung | Grund |
|---|---|
| Aufgabenliste ohne Gruppen "Überfällig / Heute / Diese Woche", stattdessen flache Liste in der festgelegten Reihenfolge | Gruppen nach Fälligkeit widersprechen "hohe Priorität zuerst"; die Reihenfolge ist verbindlich. Überfälligkeit steht je Zeile als Text. |
| Prioritätsbezeichnung "Normal" statt "Mittel" | Schlüssel `normal` und Label der Engine. |
| Auswahlchips (Offen, Heute, ...) im Designsystem-Stil (grüner Ton, Haken) statt schwarzer Pille | Komponente des Designsystems; der Zustand ist nicht nur farbig. |
| "Bestimmte Tage" und "Morgens" entfernt, "Wann?" zeigt nur "Täglich"; Untertitel der Zeilen "Täglich · N Tage in Folge" | Ticket BS-63: V1 ist ausschließlich täglich. |
| Erinnerung beim Anlegen standardmäßig aus (Figma: an, 21:00) | Ticket: "zunächst aus". |
| Link "Bearbeiten" neben "Deine Habits" fehlt | Es gibt keinen eigenen Bearbeitungsmodus; Zeilen öffnen das Detail mit Bearbeiten, Archivieren und Löschen. |
| Feld "Beschreibung" statt "Notiz"; Tags mit sichtbarem Eingabefeld und Vorschlägen statt Chip "+ Tag" | Die Engine nennt das Feld Beschreibung; das Eingabefeld macht Tags ohne versteckte Geste erreichbar. |
| Wochenleiste scrollt auf 320 px seitlich | Sieben Ziele zu je 48 px passen nicht in 288 px. |
| Verlaufsraster: Spaltenzahl folgt der Breite (6 Spalten bei 393 px, 4 bei 320 px), Zellen zeigen Tageszahl und Haken | Jede Zelle muss mindestens 48 x 48 px groß sein; die Zahl ersetzt den Datumsbereich als Orientierung. |
| Hinweis "Fast geschafft!" nur heute und bei genau einer offenen Gewohnheit (mindestens zwei), sonst "Alles geschafft!" | Ehrliche Zustandswörter statt fester Beispieltexte. |
| Dashboard: volle Breite mit drei Aufgaben statt halber Kachel "Aufgaben 4 offen" | BS-65: Erledigen in höchstens zwei Aktionen ohne Detail; Vorgabe "Übersichtskarten Aufgaben und XP in voller Breite". |
| Snackbar-Text ohne "+10 XP" | XP haben Tageslimits (5 Aufgaben, 5 Habit-Checks); die UI erfindet keine Beträge. Es gelten die Texte der Engine. |
| Abschnitt "Archiviert" am Ende der Habit-Liste | Ohne ihn wären beendete Gewohnheiten (Verlauf, Löschen) nicht mehr erreichbar. |
| Bei großer Schrift (über 130 %) liegen Umschalter, Prioritätssegmente, Zeilensteuerung und Statistik untereinander | Wörter brechen sonst mitten im Wort; Inhalt scrollt. |
| Text im Verwerfen-Sheet "Deine Eingaben in diesem Formular gehen verloren." | Wortlaut aus Figma `4053:929`; die Gewicht-Referenz nutzt noch einen anderen Satz. |

## 4. Konflikte und Entscheidung

- **Sortierung gegen Figma-Gruppen:** Aufgabentext und Spezifikation gewinnen (flache Liste).
- **Nur täglich gegen Figma "Bestimmte Tage" und "Morgens":** Ticket gewinnt (entfernt).
- **Erinnerung an gegen aus:** Ticket gewinnt (aus).
- **Archivierung:** wirkt ab morgen mit Hinweis "Ab morgen archiviert", heute gilt die Gewohnheit weiter; nicht reaktivierbar, eine neue Gewohnheit bekommt eine neue ID.
- **Nachtragen:** höchstens 30 Tage zurück, nicht in die Zukunft, nicht vor dem Start, nicht ab dem Archivdatum. Die Wochenleiste zeigt sieben, das Detail 30 Tage.
- **Erledigen im Bearbeiten-Formular:** nicht angeboten. Eine Änderung der Zeilenversion durch Erledigen würde das offene Formular beim Speichern in einen Versionskonflikt führen; Erledigen und Wiederöffnen gibt es in Liste, Menü und Dashboard.

## 5. Barrierefreiheit

- Alle Ziele mindestens 48 x 48 px (Checkboxen, Tage der Leiste, Rasterzellen, Chips, Menü, Textaktionen); geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` bei 320 und 430 px, 100 % und 200 % Text.
- Jede reine Icon-Schaltfläche hat ein deutsches Label ("Gewohnheit hinzufügen", "Suche und Filter einblenden", "Weitere Aktionen: Titel", "Gewohnheit bearbeiten").
- Zustand nie nur farbig: Checkbox spricht "erledigt/offen", Zeilen lesen Titel, Zustand, Serie und Hinweise; Überfälligkeit und Priorität stehen als Wort; Wochentage lesen "3 von 5 erledigt"; Rasterzellen lesen Datum und Zustand ("erledigt", "offen", "noch nicht begonnen", "archiviert") und tragen Zahl und Haken; die Auswahl eines Symbols hat Rahmen, Haken und `selected`.
- Aktionen ohne Geste: kein Swipe, jede Aktion über Button oder Menü; das Raster hat die Alternative "Als Liste".
- Fehler stehen am Feld (Label, Hinweis und Fehler werden zusammen gelesen), der erste fehlerhafte Wert erhält den Fokus; Meldungen ohne Textfeld sind Live-Regionen.
- Modale Sheets (Löschen, Archivieren, Verwerfen) kommen aus dem Designsystem: "Abbrechen" ist Standardfokus, schließt auch per Android-Zurück.
- 200 % Text: Inhalt scrollt, angepinnte Aktion bleibt über der Tastatur erreichbar; Zeilen, Segmente und Statistik stapeln. Reduzierte Bewegung nutzt `AppMotion`.
- Kontrast: die verwendeten Token-Paare werden in Light, Dark und OLED auf 4,5:1 (Text) und 3:1 (Symbole) geprüft.

## 6. Tests

Befehle: `flutter test test/features/tasks` (808 Tests: 470 Engine, 338 UI), `flutter test` (gesamt), `dart run tool/at_coverage.dart`.

| Datei in `test/features/tasks/` | Inhalt | Akzeptanz |
|---|---|---|
| `domain/habit_day_test.dart`, `domain/task_tag_suggestions_test.dart` | Tagesmodell, Wochenleiste, Vorschläge | T02 |
| `presentation/habits_tab_test.dart` (22) | Fortschritt, Abhaken und Undo, Doppeltipp, Fehler mit Retry, Leer- und Fehlerzustand, Wochenleiste, Nachtragen, Archiv ab morgen, Tageswechsel, Umschalter und Deep Link, große Schrift | AT12, AT21, AT23, AT24, AT25, AT27, AT33 |
| `presentation/tasks_list_test.dart` (20) | Reihenfolge, Überfällig als Text, Segmente, Suche, Prioritätsfilter, Erledigen ohne XP-Anhäufung, Menü, Löschen mit exaktem Undo, Fehlerfälle, große Schrift | AT12, AT13, AT25, AT27, AT33, T01, G01 |
| `presentation/task_form_test.dart` (24) | Speichern, Fälligkeit, Tag-Regeln, Validierung, Sperre, Retry, Verwerfen, Bearbeiten, Konflikt, Tastatur und 200 % | AT12, AT27, AT33, T01, C05 |
| `presentation/habit_form_test.dart` (18) | Symbole, nur täglich, Erinnerung, Validierung, Retry, Verwerfen, Bearbeiten, Löschen mit Undo | AT12, AT27, AT33, T02, C08 |
| `presentation/habit_detail_test.dart` (14) | Serie und Quote, Nachtragen und Undo, gesperrte Tage, Liste, Archivieren, beendete Gewohnheit | AT12, AT21, AT23, AT24, AT27, T02, G01, G02, C08 |
| `presentation/tasks_dashboard_card_test.dart` (13) | drei Aufgaben, Erledigen in einem Tipp, Undo, Fehler, leer, Tageswechsel | AT12, AT13, AT25, AT27, AT33, T01 |
| `presentation/tasks_module_test.dart` (7) | Karte, Plus-Einträge, Routenreihenfolge (`/tasks/new` ist nie eine ID) | BS-53 |
| `presentation/responsive_a11y_test.dart` (100) | alle Screens bei 320, 360, 393, 430 px mit 100 % und 200 % Text ohne Überlauf, Tap-Ziele und Labels, Themes Light, Dark und OLED, Screenreader-Texte, reduzierte Bewegung | AT33 |
| `presentation/contrast_test.dart` (120) | Kontrast der verwendeten Farbpaare in drei Themes | AT33 |

Visuelle Prüfung: jeder Screen wurde als Widget-Test bei 393 x 852 (Light) und 320 px mit 200 % Text als PNG gerendert und mit dem Figma-Screenshot verglichen; die Abweichungen stehen oben. Ein Gerät oder Emulator stand nicht zur Verfügung.

## 7. Engine-Erweiterungen (minimal)

`lib/features/tasks/domain/habit_day.dart` (Tagesliste und Wochenleiste), `domain/task_tag_suggestions.dart`, `application/habit_day_providers.dart` (gewählter Tag, wird beim Tageswechsel verworfen) und `TaskFormController.clearTagError()` (mit Test).

## 8. Offene Punkte

- Swipe-Aktionen sind nicht umgesetzt (optional laut Ticket, das Menü ersetzt sie).
- Die Uhrzeitauswahl der Erinnerung (Material-Dialog) ist nur durch Öffnen und Abbrechen getestet; das Setzen einer Uhrzeit ist manuell zu prüfen.
- Die Erlaubnis für Benachrichtigungen fragt das Formular nicht an; sie gehört zu den Einstellungen (Hinweis im Formular).
- TalkBack, Systemschrift und Zeitzonenwechsel auf einem Gerät sind nicht prüfbar.
- Die Shell muss `HabitsTabScreen` auf `/habits` registrieren und die Modulrouten zentral absichern.
