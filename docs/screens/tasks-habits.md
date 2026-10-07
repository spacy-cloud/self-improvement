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
| Dashboard-Karte `tasks`, ab v0.2.0 „Heute abhaken“ mit Aufgaben und Gewohnheiten (BS-110) | Home `4116:421` (Dunkel `4116:822`, OLED `4116:1223`); in V1 Home `2013:2` (Kachel Aufgaben) | Karte auf `/` | `tasks_dashboard_card.dart`, `checklist_row.dart` |

`TasksModule` (`lib/features/tasks/tasks_module.dart`) liefert die Routen (statische Pfade vor den parametrischen: `/tasks/new`, `/tasks/:id`, `/habits/new`, `/habits/:id` mit dem Unterpfad `edit`), die Karte `tasks` (volle Breite, Rang laut Standardreihenfolge) und die Plus-Einträge `task` (Position 5, `/tasks/new`) und `habit` (Position 6, `/habits/new`). `/habits` selbst gehört der Shell; sie baut `HabitsTabScreen(showTasks: ...)`. Der gewählte Segmentwert wird über `GoRouter.go` in die Route zurückgeschrieben, damit ein wiederholter Deep Link `?tab=tasks` immer auf der Aufgabenliste landet.

## 2. Verhalten

**Habits-Tab.** Kopf mit Plus (legt je nach Ansicht Gewohnheit oder Aufgabe an) und Umschalter Aufgaben / Gewohnheiten mit Zählern ("3 offen", "2/5"). Ansicht Gewohnheiten: Wochenleiste der letzten sieben Tage, Fortschrittskarte des gewählten Tages, Liste "Deine Habits" mit runder Checkbox je Gewohnheit, darunter "Archiviert" (beendete Gewohnheiten, nur lesbar). Ein Tipp auf die Checkbox setzt den Zustand (Soll-Zustand, kein blindes Toggle) und zeigt erst nach dem Commit "Abgehakt" mit "Rückgängig" (8 s). Ein Tag der Leiste zeigt die Gewohnheiten dieses Tages und erlaubt Nachtragen oder Entfernen; "Zurück zu heute" und der Tageswechsel setzen die Auswahl zurück. Zukunft, Tage vor dem Start und ab dem Archivdatum sind nicht wählbar (Regeln der Engine, `checkDateError`). Ist das Aufgabenmodul ausgeschaltet, zeigt der Tab statt dieses Inhalts nur "Aufgaben und Gewohnheiten sind ausgeschaltet" mit "Aufgaben und Gewohnheiten aktivieren" und "Module verwalten"; es gibt dann weder Daten noch eine Schreibaktion, die Einträge bleiben erhalten.

**Aufgabenliste.** Segmente Offen / Erledigt / Alle, Suche in Titel und Beschreibung, Prioritätsfilter (Hoch, Normal, Niedrig, Alle), Reihenfolge der Engine (Priorität hoch zuerst, dann Fälligkeit aufsteigend, ohne Datum zuletzt, dann Erstellzeit und ID). Zeilen werden lazy gebaut. Jede Zeile hat Checkbox (Erledigen/Wiederöffnen als Soll-Zustand), Textbereich (öffnet die Bearbeitung) und Menü (Bearbeiten, Als erledigt markieren oder Wieder öffnen, Löschen). Überfällig steht als Text ("Überfällig seit 02.10.2026") plus rotem Rahmen. Löschen fragt per Sheet nach und bietet danach Undo, das den exakten Zustand inklusive Erledigt-Flag wiederherstellt. Leere Zustände: keine Aufgaben, nichts offen, nichts erledigt, keine Treffer (mit "Suche zurücksetzen"); Ladefehler mit `ErrorState` und erneutem Lesen. Der Filterzustand bleibt beim Tabwechsel erhalten.

**Formulare.** Aufgabe: Titel (1 bis 120), Priorität, Fälligkeit (Heute, Morgen, Kein Datum oder Datumsauswahl, auch in der Vergangenheit), bis zu fünf Tags (Trim, Groß-/Kleinschreibung egal, Hinweise bei Doppelten, Limit und Länge; Vorschläge aus vorhandenen Aufgaben), Beschreibung (bis 1.000). Gewohnheit: Name (1 bis 80), sechs Symbole (Buch, Mond, Tropfen, Haken, Flamme, Herz, Standard Buch) mit gekoppeltem Akzent, nur "Täglich", optionale Erinnerung (Standard aus, Uhrzeit nur bei Aktivierung). Beide: Speichern angepinnt über der Tastatur, Doppeltipp sperrt, Fehler behalten die Eingabe und bieten "Erneut" mit derselben Command-ID, Änderungen verwerfen per Sheet (Header-Zurück und Android-Zurück), Bearbeiten ist erst nach einer Änderung speicherbar und bietet Löschen mit Bestätigung und Undo.

**Gewohnheit Detail.** Serie, Tage erfüllt, Quote, längste Serie, Erinnerungstext; Verlauf der letzten 30 Tage als Raster (Tippen setzt oder entfernt den Haken) oder als Liste ("Als Liste"); Aktionen Bearbeiten, Archivieren (Bestätigung, danach "Ab morgen archiviert", kein Undo, keine Reaktivierung), Löschen (Bestätigung, Undo mit gleicher ID und Verlauf). Beendete Gewohnheiten sind nur lesbar und löschbar.

**Dashboard-Karte.** Volle Breite, ab v0.2.0 „Heute abhaken“: die Aufgaben und die Gewohnheiten von heute in einer Liste, jede Zeile mit einem eigenen Kästchen: Erledigen oder Abhaken in einem Tipp, ohne das Detail zu öffnen, mit "Rückgängig". In V1 zeigte die Karte nur bis zu drei offene Aufgaben (ohne Datum oder bis heute) mit "und N weitere" und dem Kopf als Weg zur Liste; was heute gilt, steht in Abschnitt 2a.

## 2a. v0.2.0: Home zeigt Aufgaben und Gewohnheiten (BS-110)

Ticket [BS-110](https://spacy-cloud.atlassian.net/browse/BS-110), Entscheidung D-028 ([../implementation-decisions.md](../implementation-decisions.md)), Entwurf Figma `4116:421` (Dunkel `4116:822`, OLED `4116:1223`). Die Karte `tasks` ist jetzt „Heute abhaken“: die Aufgaben und die Gewohnheiten von heute in einer Liste, abhakbar mit einem Tipp. Karten-ID, Modul, volle Breite und Platz in der Reihenfolge (nach „Fokus“) bleiben; im Dialog „Karten anpassen“ heißt sie „Aufgaben und Gewohnheiten“, weil das Ausblenden beide ausblendet. Eine eigene Karte für Gewohnheiten gibt es nicht: Karten-IDs gehören zum Datenvertrag (D-015).

**Zeilen.** Überschrift „Heute abhaken“, rechts „x von y erledigt“ (die heute erledigten Aufgaben und die abgehakten Gewohnheiten gegen alles von heute, auch gegen das, was nicht in der Liste steht); sind alle erledigt, steht ein Haken vor der grünen Zahl. Darunter eine Karte mit den Zeilen, Aufgaben zuerst:

- **Aufgaben:** die offenen Aufgaben von heute (ohne Datum oder fällig bis heute), höchstens drei, in der Reihenfolge der Aufgabenliste (Regel `buildDashboardTasks`, unverändert), dazu die heute erledigten Aufgaben an ihrem Platz in dieser Reihenfolge: durchgestrichen, ruhige Farbe, „Erledigt um 08:15“ (Uhrzeit in der Zone der Erledigung, ohne bekannte Zone nur „Erledigt“). Eine überfällige Aufgabe sagt es in Worten und mit Symbol („Überfällig seit 01.10.2026“). Was nicht in die drei passt, steht hinter „und N weitere Aufgaben“ (öffnet die Aufgabenliste). Eine Aufgabe, die an einem früheren Tag erledigt wurde, steht nicht mehr da; um Mitternacht verlassen die heute erledigten die Karte.
- **Gewohnheiten:** alle Gewohnheiten, die heute gelten, abgehakte eingeschlossen, höchstens fünf, in der Reihenfolge des Gewohnheiten-Tabs (älteste zuerst); Untertitel wie im Tab: die Serie („5 Tage in Folge“, „Noch keine Serie“), abgehakt „… · erledigt“, dazu „Ab morgen archiviert“. Der Rest steht hinter „und N weitere Gewohnheiten“ (öffnet den Tab „Habits“).

**Abhaken.** Das Kästchen setzt den Soll-Zustand über dieselben Befehle wie die Listen (`setTaskCompleted`, `setHabitChecked` aus `action_feedback.dart`, darunter `TaskActionsController` und `HabitActionsController`): idempotent, mit Befehls-ID, bei laufendem Befehl gesperrt (ein Doppeltipp läuft einmal), nach einem Fehler „Erneut“ mit derselben ID, „Rückgängig“ (8 s) in der Snackbar erst nach dem Commit. Ein Tipp auf ein abgehaktes Kästchen nimmt den Haken zurück („Haken entfernt“, „Aufgabe wieder geöffnet“), auch das mit Rückgängig. Ein Tipp auf den Rest der Zeile öffnet die Aufgabe (Bearbeiten) oder die Gewohnheit (Detail). XP und Tageslimits sind die der Listen, die Karte rechnet nichts.

**Gleicher Stand wie der Tab.** `todayChecklistProvider` (`lib/features/tasks/application/today_checklist_providers.dart`) liest `tasksProvider`, `habitsProvider` und `habitTodayProvider`; dieser ist dasselbe Lesemodell (`buildHabitDay`) aus denselben Streams (`habitsProvider`, `habitCheckIndexProvider`, `todayProvider`) wie `habitDayProvider` des Tabs, nur immer für heute. Ohne gewählten Tag ist der Tab genau diese Liste. Wählt man im Tab einen vergangenen Tag, bleibt die Karte bei heute, und ein Tipp auf der Karte gilt heute; die Auswahl des Tabs bleibt unberührt. Ein Haken auf Home steht sofort im Tab, ein Haken im Tab sofort auf Home, ebenso Rückgängig. Die Listenlogik steht in `domain/today_checklist.dart` (reine Funktion `buildTodayChecklist`).

**Aufgabe und Gewohnheit unterscheiden** (auch ohne Farbe):

| Merkmal | Aufgabe | Gewohnheit |
|---|---|---|
| Form des Kästchens | eckig (Radius 8) | rund |
| Typ-Chip mit Symbol | „Aufgabe“, Symbol `task`, grün auf Grünton (`primaryText` auf `primaryTint`) | „Gewohnheit“, Symbol `habit`, Violett auf der ruhigen Fläche (`moduleHabits` auf `surfaceMuted`) |
| Zeile darunter | Fälligkeit („Heute fällig“) oder „Erledigt um 08:15“ | Serie („5 Tage in Folge“), abgehakt mit „· erledigt“ |
| Bildschirmleser, Kästchen | „Aufgabe Steuer machen“, Wert „offen“ oder „erledigt“ | „Gewohnheit Lesen“, Wert „heute offen“ oder „heute erledigt“ |
| Bildschirmleser, Zeile (Button, Hinweis „Öffnet die Aufgabe zum Bearbeiten“ bzw. „Öffnet die Gewohnheit“) | „Aufgabe Steuer machen, Priorität Hoch, Heute fällig, offen“ | „Gewohnheit Lesen, heute offen, 5 Tage in Folge“ |

Der Chip ist für den Bildschirmleser Zierde (die Zeile nennt den Typ). Das Kästchen hat die Semantik eines Kontrollkästchens mit Zustand, es ist 48 x 48 groß, die Zeile mindestens 64 hoch. Der erledigte Zustand ist nie nur Farbe: gefülltes Kästchen mit Haken, durchgestrichener Titel, Wort „erledigt“.

**Zustände der Karte.**

| Zustand | Verhalten |
|---|---|
| Laden | Überschrift und eine leere Karte, kein Zähler |
| Fehler | `ErrorState` mit „Erneut versuchen“ (liest Aufgaben, Gewohnheiten und Haken neu) |
| Weder Aufgabe noch Gewohnheit für heute | „Für heute ist nichts offen. Neue Aufgaben und Gewohnheiten erscheinen hier.“ mit „Aufgabe anlegen“ und „Gewohnheit anlegen“; kein Zähler („0 von 0“ gibt es nie) |
| Aufgaben, aber keine Gewohnheit angelegt | die Aufgaben, darunter „Noch keine Gewohnheit“ mit „Gewohnheit anlegen“; sind alle Gewohnheiten archiviert: „Keine aktive Gewohnheit“ mit demselben Weg |
| Gewohnheiten, aber keine Aufgabe | nur die Gewohnheiten |
| Viele | drei offene Aufgaben und fünf Gewohnheiten, je Art eine Zeile „und N weitere …“ („und 1 weitere Gewohnheit“) zur Liste; der Zähler zählt alles |
| Alles erledigt | alle Kästchen gefüllt, Haken vor „5 von 5 erledigt“ in Grün |
| Neuer Tag | ohne Neustart: Gewohnheiten wieder offen (die Serie bleibt, bis der Tag vergeht), gestern erledigte Aufgaben weg, neue fällige Aufgaben da |
| Große Schrift (über 130 %) | Kästchen und Chip stehen in der ersten Zeile, der Titel darunter mit voller Breite, der Zähler unter der Überschrift; nichts bricht mitten im Wort |
| Dunkel, OLED | aus den Tokens, keine festen Farbwerte |
| Modul „Aufgaben und Gewohnheiten“ aus | die Karte fehlt wie bisher (Modul-Tor des Dashboards), kein Lesen, kein Schreiben, die Einträge bleiben und kommen mit dem Modul zurück |
| Nur lesend (vergangene Tage, BS-93) | `TasksDashboardCard(readOnly: true)`: der Stand wird gezeigt, die Kästchen sind gesperrt (kein Befehl), es gibt keine Aktion zum Anlegen; die Zeilen öffnen weiter |

**Abweichungen vom Entwurf** (Figma nicht geändert):

| Abweichung | Grund |
|---|---|
| Der Entwurf zeichnet unter der Karte „Dein Tag im Überblick“ die V1-Kachelzeile „Fokus und Aufgaben“ (Kachel „Aufgaben 4 offen“); die App hat sie nicht | Die Aufgabenkarte der App war schon in V1 eine Karte in voller Breite; „Heute abhaken“ ersetzt sie. Die Karte „Fokus“ bleibt eine eigene Karte. |
| Der Kopf der alten Karte (Symbol, „Aufgaben“, „N Aufgaben für heute“, Chevron als Weg zur Liste) entfällt; die Überschrift ist wie im Entwurf ohne Link | Der Entwurf zeichnet keinen Weg zur Liste. Er bleibt über die Zeilen „und N weitere …“ und den Tab „Habits“. |
| Begrenzung auf drei offene Aufgaben und fünf Gewohnheiten mit den Zeilen „und N weitere …“ | Der Entwurf zeigt fünf Zeilen und keine Begrenzung; das Ticket nennt keine Grenze (D-028). |
| Leerzustand, Hinweis „Noch keine Gewohnheit“, Zustand „Nur lesend“, 200 % Schrift | nicht im Entwurf; Texte und Aufbau wie in den Leerzuständen des Tabs |
| Der Titel einer Zeile bricht um statt abgeschnitten zu werden; bei 393 px bricht „Figma-Prototyp verlinken“ in zwei Zeilen | Seitenrand 16 px statt 14 px im Entwurf (365 px breite Karte), Wörter nie abschneiden |
| Untertitel einer Aufgabe ohne Fälligkeit: keine zweite Zeile; Untertitel einer Gewohnheit ohne „Täglich“ und ohne Flamme, mit „Ab morgen archiviert“, wo es gilt | der Entwurf zeichnet nur Aufgaben mit Fälligkeit; „Täglich“ und die Flamme zeigt der Tab, die Karte folgt dem Entwurf |
| Chip-Symbole sind die Material-Entsprechungen `Icons.check_box_outlined` und `Icons.checklist_rounded` (`AppIcon.task`, `AppIcon.habit`) | wie bei allen Symbolen der App (design-handoff.md) |
| Die in V1 beim Erledigen verschwundene Aufgabe bleibt für den Rest des Tages stehen | der Entwurf zeigt erledigte Aufgaben und den Zähler „2 von 5“; ohne sie sänke der Nenner beim Erledigen. Rücknahme mit dem Kästchen oder „Rückgängig“ |

Der Sichtvergleich war ein Augenschein an im Host gerenderten Bildern (393 px in Hell, Dunkel und OLED, 320 px bei 200 %) gegen die drei Entwurfsframes, kein Pixelvergleich und nichts auf einem Gerät.

**Tests** (Befehl: `flutter test test/features/tasks`, 144 neue Tests, Einzelheiten in Abschnitt 6): die reine Funktion `buildTodayChecklist` (Reihenfolge, Grenzen, Zählung, Sprechtexte), die Provider (ein Lesemodell mit dem Tab, die Karte unabhängig vom gewählten Tag), die Karte mit Aufgaben und Gewohnheiten (Abhaken, Rückgängig, Doppeltipp, Wiederholung mit gleicher ID, Gleichstand mit dem Tab in beide Richtungen, Typen und Sprechtexte, Zustände, nur lesend, große Schrift), das echte Home mit dem echten Tab (Modul-Tor, vier Breiten, Dunkel und OLED), vier neue Kartenzustände in `responsive_a11y_test.dart` und sieben neue Farbpaare je Theme in `contrast_test.dart`. `habits_dashboard_card_visual_test.dart` schreibt nur mit `CHECKLIST_PNG=1` PNGs nach `build/habits_dashboard_card/` für den Sichtvergleich. Der Routen-Durchlauf `test/app/route_sweep_test.dart` deckt Home mit der Karte schon ab (kein neuer Pfad) und läuft grün.

**Mutationsproben** (lokal, nicht eingecheckt, danach mit `git checkout` zurückgenommen; gelaufen über die vier Karten- und Modelldateien, das Modul-Tor über das echte Home): Liest die Karte den Stand der Gewohnheiten nur einmal (`ref.read` statt `ref.watch`), scheitern 60 von 95 Tests, darunter alle fünf „in step with the habits tab“ (der Lauf des echten Home bleibt hängen, weil die Karte nie lädt). Schreibt die Karte an den Befehlen vorbei (eigene Befehls-ID, keine Sperre), scheitern 12 (Doppeltipp, Sperre, Wiederholung mit gleicher ID, Rückgängig, Gleichstand); nur ohne die Sperre am Kästchen scheitert 1 (der Controller fängt den Doppeltipp dann noch ab). Gleiche Kästchenform für beide Arten: 2; ohne die Art im Sprechtext des Kästchens: 21, der Zeile: 4; ohne Grenze für Gewohnheiten: 4; ohne die heute erledigten Aufgaben: 18; Karte folgt dem gewählten Tag des Tabs: 2; „nur lesend“ ignoriert: 2; Zähler ohne Aufgaben: 11, nur mit den gezeigten Gewohnheiten: 3; Modul-Tor ignoriert: 1 (auf dem echten Home).

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
| Dashboard: volle Breite mit drei Aufgaben statt halber Kachel "Aufgaben 4 offen" (ab v0.2.0 „Heute abhaken“ mit Aufgaben und Gewohnheiten, Abschnitt 2a) | BS-65: Erledigen in höchstens zwei Aktionen ohne Detail; Vorgabe "Übersichtskarten Aufgaben und XP in voller Breite". |
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

Befehle: `flutter test test/features/tasks` (952 Tests: 511 Engine, 441 UI), `flutter test` (gesamt), `dart run tool/at_coverage.dart`.

| Datei (unter `test/features/tasks/`, sonst mit Pfad) | Inhalt | Akzeptanz |
|---|---|---|
| `domain/habit_day_test.dart`, `domain/task_tag_suggestions_test.dart` | Tagesmodell, Wochenleiste, Vorschläge | T02 |
| `presentation/habits_tab_test.dart` (22) | Fortschritt, Abhaken und Undo, Doppeltipp, Fehler mit Retry, Leer- und Fehlerzustand, Wochenleiste, Nachtragen, Archiv ab morgen, Tageswechsel, Umschalter und Deep Link, große Schrift | AT12, AT21, AT23, AT24, AT25, AT27, AT33 |
| `presentation/tasks_list_test.dart` (20) | Reihenfolge, Überfällig als Text, Segmente, Suche, Prioritätsfilter, Erledigen ohne XP-Anhäufung, Menü, Löschen mit exaktem Undo, Fehlerfälle, große Schrift | AT12, AT13, AT25, AT27, AT33, T01, G01 |
| `presentation/task_form_test.dart` (24) | Speichern, Fälligkeit, Tag-Regeln, Validierung, Sperre, Retry, Verwerfen, Bearbeiten, Konflikt, Tastatur und 200 % | AT12, AT27, AT33, T01, C05 |
| `presentation/habit_form_test.dart` (18) | Symbole, nur täglich, Erinnerung, Validierung, Retry, Verwerfen, Bearbeiten, Löschen mit Undo | AT12, AT27, AT33, T02, C08 |
| `presentation/habit_detail_test.dart` (14) | Serie und Quote, Nachtragen und Undo, gesperrte Tage, Liste, Archivieren, beendete Gewohnheit | AT12, AT21, AT23, AT24, AT27, T02, G01, G02, C08 |
| `presentation/tasks_dashboard_card_test.dart` (17) | die Aufgaben auf der Karte „Heute abhaken“: drei offene, Erledigen in einem Tipp (die Aufgabe bleibt, durchgestrichen, „Erledigt um 08:15“), Wiederöffnen, Undo, Fehler, leer, Tageswechsel | AT12, AT13, AT25, AT27, AT33, T01 |
| `domain/today_checklist_test.dart` (31) | Liste der Karte als reine Funktion: Reihenfolge, Grenzen, Zählung, Sprechtexte | AT21, T01, T02 |
| `application/today_checklist_providers_test.dart` (10) | Karte folgt Haken, Aufgaben, Tageswechsel, Fehler; ein Lesemodell mit dem Tab, die Karte unabhängig vom gewählten Tag | AT25, C04 |
| `presentation/habits_dashboard_card_test.dart` (37) | Gewohnheiten auf der Karte: Abhaken, Rückgängig, Doppeltipp, Wiederholung mit gleicher ID, Gleichstand mit dem Tab in beide Richtungen, Typen und Sprechtexte, Zustände, nur lesend, große Schrift | AT12, AT21, AT25, AT27, AT33, AT34, C04, T02 |
| `presentation/home_checklist_test.dart` (13) | echtes Home mit echtem Tab: Platz der Karte, Gleichstand über die Navigation, XP, Weg zur ersten Gewohnheit, Modul-Tor, Breiten, Dunkel und OLED | AT03, AT21, AT33, AT35, C04 |
| `presentation/tasks_module_test.dart` (7) | Karte, Plus-Einträge, Routenreihenfolge (`/tasks/new` ist nie eine ID) | BS-53 |
| `presentation/responsive_a11y_test.dart` (128) | alle Screens bei 320, 360, 393, 430 px mit 100 % und 200 % Text ohne Überlauf, Tap-Ziele und Labels, Themes Light, Dark und OLED, Screenreader-Texte, reduzierte Bewegung | AT33 |
| `presentation/contrast_test.dart` (141) | Kontrast der verwendeten Farbpaare in drei Themes | AT33 |
| `test/app/module_tab_gate_test.dart` (2) | Habits-Tab bei ausgeschaltetem Aufgabenmodul: Hinweis, keine Daten, keine Schreibaktion, Aktivieren bringt die Einträge zurück | AT03 |

Visuelle Prüfung: jeder Screen wurde als Widget-Test bei 393 x 852 (Light) und 320 px mit 200 % Text als PNG gerendert und mit dem Figma-Screenshot verglichen; die Abweichungen stehen oben. Ein Gerät oder Emulator stand nicht zur Verfügung.

## 7. Engine-Erweiterungen (minimal)

`lib/features/tasks/domain/habit_day.dart` (Tagesliste und Wochenleiste), `domain/task_tag_suggestions.dart`, `application/habit_day_providers.dart` (gewählter Tag, wird beim Tageswechsel verworfen) und `TaskFormController.clearTagError()` (mit Test).

## 8. Offene Punkte

- Swipe-Aktionen sind nicht umgesetzt (optional laut Ticket, das Menü ersetzt sie).
- Die Uhrzeitauswahl der Erinnerung (Material-Dialog) ist nur durch Öffnen und Abbrechen getestet; das Setzen einer Uhrzeit ist manuell zu prüfen.
- Die Erlaubnis für Benachrichtigungen fragt das Formular nicht an; sie gehört zu den Einstellungen (Hinweis im Formular).
- TalkBack, Systemschrift und Zeitzonenwechsel auf einem Gerät sind nicht prüfbar.
- Home „Heute abhaken“ (BS-110): nur Host-Tests; Sprechtexte, Systemschrift, Daumenreichweite und das Verhalten der Snackbar über der Navigation sind auf keinem Gerät gesehen. Die Grenzen drei Aufgaben und fünf Gewohnheiten sind Standardwerte (D-028), das Ticket nennt keine.
- Vergangene Tage auf Home (BS-93, später): die Karte hat den Zustand „nur lesend“ (`readOnly`), aber noch keinen Parameter für einen anderen Tag; der Leerzustand und die Überschrift sagen „heute“. BS-93 muss beides anpassen und die Liste für einen Tag bauen (`buildTodayChecklist` nimmt die Gewohnheitsliste von heute).
- Die Shell registriert `HabitsTabScreen` auf `/habits` und sichert die Modulrouten zentral ab (`guardModuleRoutes`). Bei ausgeschaltetem Aufgabenmodul ersetzt `ModuleTabGate` den Tab-Inhalt (siehe [shell.md](shell.md), Abschnitt 4).
