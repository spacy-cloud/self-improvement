# Fokus-Timer und Workouts: Bildschirme (BS-66, BS-64)

Oberfläche des Moduls `focus` auf den vorhandenen Engines (Domain, Daten, Application). Dieses Dokument beschreibt Bildschirme, Entwurfsbezug, Abweichungen, Entscheidungen bei Konflikten, Barrierefreiheit, Tests und offene Punkte.

## 1. Umfang und Dateien

| Bereich | Dateien (unter `lib/features/focus/`) |
|---|---|
| Modul | `focus_module.dart`: Routen, Dashboard-Karten, Plus-Menü, `canDeactivate`, `initialize` |
| Fokus-Bildschirme | `presentation/focus_start_screen.dart`, `focus_session_screen.dart`, `focus_end_sheet.dart`, `focus_history_screen.dart`, `focus_session_detail_screen.dart`, `focus_session_tile.dart`, `focus_timer_widgets.dart`, `focus_dashboard_card.dart` |
| Workout-Bildschirme | `presentation/workout_form_screen.dart`, `workout_overview_screen.dart`, `workout_history_screen.dart`, `workout_widgets.dart`, `workout_dashboard_card.dart` |
| Gemeinsames | `presentation/focus_routes.dart`, `focus_labels.dart`, `workout_labels.dart`, `focus_widgets.dart` |
| Application (neu) | `application/focus_ui_providers.dart`, `workout_ui_providers.dart`; `WorkoutFormController.deleteEntry` ergänzt; die seitenweisen Listen-Provider sind jetzt auto-dispose |
| Domain (neu, rein) | `domain/focus_xp_preview.dart`, `muscle_recency.dart`, `workout_groups.dart` |

Die Bildschirme enthalten kein SQL und keine Geschäftsregeln: alle Aktionen laufen über `FocusSetupController`, `FocusSessionController`, `WorkoutFormController` und die Repositories. Zeit kommt ausschließlich über `ClockService` und `FocusTickSource`.

## 2. Bildschirme, Routen und Figma-Knoten

| Bildschirm | Route | Figma (Light) | Zustände |
|---|---|---|---|
| Fokus Start | `/focus` | `4038:2` | Einrichtung (Dauerring mit Minus/Plus, Kategorien, Start), Wiederaufnahme-Karte statt Einrichtung bei offener Sitzung, Karte "Heute", "Sitzungen heute", Laden, Fehler mit erneut versuchen |
| Fokus läuft / pausiert / Bestätigung | `/focus/session` | `4039:2`, `4039:106`, `4039:210` | `running`, `paused`, `awaiting_confirmation`, keine offene Sitzung (Leerzustand), Laden, Fehler, Uhr-zurückgestellt-Hinweis, Sheet "Sitzung beenden?" |
| Fokus-Verlauf | `/focus/history` | `4056:298` | nach Bestätigungstag gruppiert, seitenweise nachladen, leer, Fehler |
| Sitzung bearbeiten | `/focus/history/:id` | Muster Gewicht `4053:314`, `4053:422`, `4053:541` | Notiz ändern, Löschen mit Bestätigung und Rückgängig, Verwerfen-Dialog, nicht gefunden, noch nicht abgeschlossen |
| Workout eintragen / bearbeiten | `/workouts/new`, `/workouts/:id` | `4022:2` (Bearbeiten nach Muster Gewicht) | leer, Validierungsfehler, Speicherfehler, Löschen mit Bestätigung und Rückgängig, nicht gefunden |
| Workout Übersicht | `/workouts` | `4027:2` | Woche, "Zuletzt trainiert", letzte Trainings, Leerzustand, Laden, Fehler |
| Alle Trainings | `/workouts/all` | `4056:183` | nach Kalenderwoche (Montag bis Sonntag) gruppiert, seitenweise, leer, Fehler |
| Dashboard-Karten `focus` und `workout` | (Home) | Home `2013:2` | Fokus: Tagesstand oder offene Sitzung mit "Fokus fortsetzen"; Workout: Wochenring mit echtem Stand, bei eingeschaltetem Tagesziel „Workout heute“ der Tag (Abschnitt 9) |

Plus-Menü: `workout` (Position 1, Route `/workouts/new`) und `focus` (Position 4, Route `/focus`; während einer offenen Sitzung heißt der Eintrag "Fokus fortsetzen" und führt zu `/focus/session`).

Routen sind flach registriert, statische Pfade vor parametrischen (`/workouts/new` und `/workouts/all` vor `/workouts/:id`, `/focus/history` vor `/focus/history/:id`).

## 3. Verhalten

### 3.1 Fokus-Timer
- **Eine offene Sitzung.** Der Startbildschirm zeigt bei offener Sitzung eine Wiederaufnahme-Karte statt der Einrichtung; die Datenbank verweigert zusätzlich eine zweite Sitzung. Zurücknavigieren aus der laufenden Sitzung erlaubt keinen zweiten Start.
- **Einrichtung.** Dauer 5 bis 180 Minuten in Schritten von 5 (Standard 25), fünf Kategorien (Lesen, Lernen, Programmieren, Meditation, Sonstiges; vorgewählt ist "Sonstiges" wie in der Engine). Eine Eingabe unter 5 oder über 180 ist über die Oberfläche nicht erreichbar und wird von der Engine ohnehin abgewiesen.
- **Anzeige.** Der Bildschirm zeigt nur die persistierte Sitzung (`focusCountdownProvider`). Innerhalb einer Vordergrundphase zählt die monotone Tickquelle; es gibt keine Datenbankschreibzugriffe pro Sekunde. Nach Prozessende, Hintergrundphase oder Neustart wird die Phase aus den UTC-Segmenten neu aufgebaut. Bei jedem `resumed`-Lebenszyklusereignis stößt die Verdrahtung der Shell `FocusRestorer.restore()` an (`AppWiring`, idempotent), ebenso der geöffnete Sitzungsbildschirm; beim Start und bei der Reaktivierung des Moduls geschieht es über `FocusModule.initialize`. So wird der Countdown auch ohne geöffneten Sitzungsbildschirm (zum Beispiel nur mit der Dashboard-Karte) nach dem Schlafen des Geräts neu aus den gespeicherten Segmenten aufgebaut, und eine inzwischen abgelaufene Sitzung wird zur „Bestätigung ausstehend“. Getestet in `test/app/app_wiring_test.dart` (Host); auf einem Gerät nicht geprüft.
- **Ende der Zeit.** Die Engine persistiert genau einmal `awaiting_confirmation`. Bis zur Bestätigung gibt es weder XP noch eine Abschlusszeit noch Fokuszeit. Der Bildschirm sagt das ausdrücklich.
- **Speichern.** Doppeltes Speichern ergibt einen Abschluss (Sperre im Controller, gleiche Command-ID bei Wiederholung). Ab 1 Sekunde speicherbar; unter 300 Sekunden wird die Zeit gespeichert, aber ohne XP. Das XP-Hinweisfeld spiegelt die XP-Regel (zehn Punkte, höchstens vier berechtigte Sitzungen pro Tag, Mindestlänge 300 Sekunden) und erscheint nur bei eingeschalteter Gamification.
- **Beenden früher.** "Beenden" öffnet ein Sheet mit der bisherigen Zeit und drei Wegen: "Zeit speichern", "Verwerfen" (mit Rückgängig) und "Weiter fokussieren" (sicherer Standard, schließt auch mit Android-Zurück). Unter einer Sekunde wird Speichern nicht angeboten.
- **Verwerfen** aus der Bestätigung fragt vorher nach, die Meldung bietet Rückgängig.
- **Zeitsprünge.** Eine vorgestellte Uhr ändert die Anzeige nicht; eine zurückgestellte Uhr zeigt den Hinweis zur Prüfung der Sitzungsdauer. Mitternacht: die Sitzung zählt am Tag der Bestätigung und wird nicht geteilt; der Hinweistext "Speichern zählt ... zu deinem Tagesziel" rechnet mit dem neuen Tag. Zeitumstellung: gezählt werden echte Minuten (UTC), die Verlaufszeit wird in der eingefrorenen Zone der Sitzung angezeigt.
- **Verlauf und Detail.** Gruppiert nach Bestätigungstag; nur abgeschlossene Sitzungen. Im Detail ist nur die Notiz änderbar (Kategorie und Zeit sind Fakten). Löschen mit Bestätigung und Rückgängig entfernt Zeit und XP und stellt sie mit derselben ID wieder her.
- **Modul ausschalten.** `canDeactivate` blockiert bei offener Sitzung mit Meldung und Auflösungstext; die Sitzung wird auf `/focus/session` gespeichert oder verworfen (`focusDeactivationResolveRoute`). Nichts wird still gelöscht; der `ModuleManager` verweigert zusätzlich mit `ConflictFailure(openFocusSession)`.
- **Karte.** Ohne Sitzung: Minuten heute gegen das Tagesziel. Mit Sitzung: Zustand, Kategorie, Restzeit in ganzen Minuten (die Karte ändert sich einmal pro Minute, nicht pro Sekunde) und "Fokus fortsetzen". Die Karte hält den Countdown am Leben, sodass der Übergang in die Bestätigung auch auf dem Dashboard stattfindet.

### 3.2 Workouts
- **Formular.** Nichts ist vorausgewählt: keine Kategorie, keine Dauer, keine Muskelgruppen, keine Intensität; der Name ist optional (leer bedeutet Kategoriename). Pflicht sind Kategorie (Kraft, Cardio, Mobility, Sport) und Dauer 1 bis 600 Minuten; optional Muskelgruppen (Mehrfachauswahl ohne Duplikate, kanonische Reihenfolge), Intensität (Leicht, Mittel, Hart; erneutes Antippen entfernt), Zeitpunkt (nicht in der Zukunft) und Notiz. Keine Sätze, Wiederholungen oder Kalorien.
- **Fehler.** Fehlende Pflichtfelder und Grenzverletzungen erscheinen am Feld und behalten die Eingabe. Ein Speicherfehler behält alle Eingaben und bietet "Erneut" mit derselben Command-ID. Doppeltes Antippen speichert einmal. Verlassen mit Eingaben fragt "Änderungen verwerfen?" (auch mit Android-Zurück).
- **Übersicht.** "Diese Woche" (Montag bis Sonntag): echte Anzahl gegen das Wochenziel (1 bis 14, Standard 3), Ring bei 100 Prozent gedeckelt, Minuten, Durchschnitt, Fehlbetrag oder "Erreicht". "Zuletzt trainiert" zeigt nur Muskelgruppen aus Workouts der letzten 28 Tage. Das Wochenziel wird im Zieleditor geändert (Link "Wochenziel ändern" mit Hinweis "Änderungen gelten ab morgen").
- **Workouts zählen keine Fokuszeit** und umgekehrt; die Zahlen beider Karten sind getrennt.
- **Tagesziel, Ruhetag und Überspringen** (BS-99) sind in Abschnitt 9 beschrieben: Die Wochenzahlen dieses Abschnitts gelten für das Wochenziel; ein Ruhetag oder ein übersprungener Tag zählt dort nie als Workout.

## 4. Abweichungen vom Entwurf

| Entwurf | Umsetzung | Grund |
|---|---|---|
| Kategorien Lernen, Lesen, Arbeit, Sonstiges | Lesen, Lernen, Programmieren, Meditation, Sonstiges | Fachliche Vorgabe |
| Platzhalterwerte (45 / 60 Min., "+15 XP", "2 / 3", Zeiten) | nur aus echten Daten berechnet (Tagesziel Standard 25 Minuten, 10 XP) | keine Fake-Daten, XP-Regel |
| Start- und Weiter-Schaltfläche in Indigo | Standard-Primärbutton (grün) | Das Designsystem hat nur einen Primärbutton; ein Indigo-Button bräuchte eigene Kontrastwerte in Dark und OLED |
| Minus/Plus des Dauerrings in Indigo | `QuantityStepper` des Designsystems (grüne Tönung) | Komponente des Designsystems |
| Dauerring neben den Schaltflächen | bei schmaler Breite und großer Schrift Ring oben, Schaltflächen darunter mit Wert "25 Min." | Responsivität bis 320 px und 200 % Text |
| Aktionen "Pausieren/Beenden" ohne Zwischenschritt | "Beenden" öffnet ein Sheet (Speichern, Verwerfen, Weiter) | Früh beenden und Verwerfen brauchen eine bewusste Auswahl |
| Anzeige "Letzte 7 Tage" | "Diese Woche" (Montag bis Sonntag) | Spezifikation gewinnt |
| Wochenziel als drei Punkte | Ring (bei 100 Prozent gedeckelt) und Zahlen | Ring nach Anforderung, Ziel bis 14 |
| Muskelgruppe "Arme" in "Zuletzt trainiert" | Bizeps und Trizeps getrennt | Muskelgruppen laut Spezifikation |
| Kein Notizfeld im Workout-Frame | optionales Feld "Notiz" | Anforderung (Notiz) |
| Home-Karte Fokus kompakt ohne Fortschritt | Karte mit Fortschrittsbalken und Wiederaufnahme-Aktion | Anforderung (Wiederaufnahme) |
| Namensfeld mit Stiftsymbol | `AppTextField` mit Hinweistext | Designsystem |

## 5. Konflikte zwischen Entwurf, Spezifikation und Aufgabe

- **XP je Fokus-Sitzung:** der Entwurf zeigt 15, die Regel lautet 10 (Workout dagegen 15 einmal pro Tag). Entscheidung: Regel; der Wert wird aus `XpRules` gelesen.
- **Standard-Tagesziel Fokus:** der Entwurf zeigt 60 Minuten, der Standard der Engine ist 25. Entscheidung: Engine-Wert.
- **Plus-Menü "Fokus fortsetzen":** `QuickAction.route` ist statisch (`/focus`), ein dynamisches Ziel ist im Modulvertrag nicht vorgesehen. Entscheidung: Das Label wechselt per `dynamicLabel`, und die Shell kennt den Sonderfall: Läuft eine Sitzung (laufend, pausiert oder unbestätigt), heißt der Eintrag "Fokus fortsetzen" und führt direkt zu `/focus/session` (`resolvePlusEntries`, Tests `plus_entries_test.dart` und `app_shell_test.dart`); ohne Sitzung führt "Fokus" zu `/focus`. Der Startbildschirm zeigt bei offener Sitzung zusätzlich die Wiederaufnahme-Karte (zum Beispiel für den Weg über eine Dashboard-Karte). Ein `dynamicRoute` im Kernvertrag war dafür nicht nötig.
- **Vorauswahl:** für Workouts gilt "nichts vorausgewählt". Für den Fokus-Start bleibt die Engine-Vorgabe "Sonstiges" und 25 Minuten als sichtbare Startwerte; gespeichert wird erst mit dem Start.

## 6. Barrierefreiheit

- Tippziele mindestens 48 x 48 (geprüft mit der Android-Richtlinie), jede Schaltfläche und jedes Symbol hat ein deutsches Label (Richtlinie für beschriftete Ziele).
- **Timer ohne Sekundenansage:** der Ring ist keine Live-Region; sein Label ("Fokus läuft, Lernen. Noch 10 Minuten und 12 Sekunden von 25 Minuten.") wird nur beim Fokussieren gelesen. Live-Region ist nur die Statusanzeige ("Läuft", "Pausiert", "Geschafft!"), sie sagt Zustandswechsel genau einmal an. Die Dashboard-Karte aktualisiert sich nur einmal pro Minute.
- Zustand nie nur durch Farbe: Statusanzeigen haben Text und Symbol, Auswahlchips ein Häkchen, der Ring hat eine Textalternative.
- Der Dauerwert der Einrichtung ist eine Live-Region (Änderungen werden angesagt); Minus/Plus sind beschriftet und am Limit deaktiviert.
- Fehler stehen am Feld bzw. als Meldung mit Symbol (Live-Region); Sheets haben eigene Schließen-Aktion und schließen mit Android-Zurück.
- Text bis 200 Prozent: Inhalte scrollen, Schaltflächen stapeln bei großer Schrift, Ringe skalieren in die verfügbare Breite. Bei offener Tastatur und knapper Höhe wandert die Speichern-Aktion der Formulare ans Ende des scrollenden Inhalts, damit die Felder Platz behalten.
- Alle Aktionen haben sichtbare Schaltflächen (keine reinen Gesten).

## 7. Tests

Neue Testdateien unter `test/features/focus/` (240 neue Tests; der Gesamtstand steht in [test-report.md](../test-report.md)):

| Datei | Tests | Schwerpunkt (Abnahme-IDs) |
|---|---|---|
| `presentation/focus_start_screen_test.dart` | 26 | Einrichtung, Grenzen 4/5/180/181 Minuten, Start, Doppeltipp, Wiederaufnahme, Heute-Karte (AT12, AT16, AT25, AT27, F01, F02) |
| `presentation/focus_session_screen_test.dart` | 36 | laufend/pausiert/Bestätigung, Neustart, Uhrsprung, Mitternacht, Sommerzeit, XP, 299/300 Sekunden, Verwerfen, Fehler, Semantik (AT12, AT16-AT18, AT25, AT27, AT33, AT34, F01, G01) |
| `presentation/focus_history_screens_test.dart` | 23 | Verlauf, Zonen, seitenweise Laden, Notiz, Löschen mit Rückgängig, Konflikte, Verwerfen-Dialog (AT23, AT25, AT27, AT36, F02) |
| `presentation/workout_form_screen_test.dart` | 29 | leeres Formular, Grenzen 0/1/600/601, optionale Felder, Fehler, Wiederholung, Bearbeiten, Löschen (AT12, AT20, AT23, AT27, F03) |
| `presentation/workout_overview_screens_test.dart` | 24 | Woche Montag bis Sonntag, Ring bei 100 Prozent, Wochenwechsel, Liste, Zonen (AT20, AT23, AT25, AT36, F03, A01) |
| `presentation/focus_dashboard_cards_test.dart` | 16 | Karten, Wiederaufnahme, Übergang auf dem Dashboard, getrennte Zahlen (AT16, AT17, AT20, AT34) |
| `presentation/focus_module_test.dart` | 22 | Routen, Plus-Menü, `canDeactivate`, `initialize` (AT19) |
| `presentation/focus_responsive_test.dart` | 28 | alle Bildschirme bei 320, 360, 393, 430 px und Textskala 1,0 und 2,0, Tastatur (AT33, AT34) |
| `presentation/focus_labels_test.dart`, `workout_labels_test.dart` | 28 | reine Textfunktionen |
| `domain/muscle_recency_test.dart`, `workout_groups_test.dart` | 8 | reine Domainfunktionen |
| `application/workout_form_controller_test.dart` | +4 | `deleteEntry` |

Hilfen: `support/focus_ui_kit.dart` (Harness mit Fake-Uhr, Tickquelle, Feedback-Recorder, Neustart), `support/flaky_repositories.dart` (Schreibfehler).

Befehle:

```
flutter test test/features/focus
flutter test
dart run tool/at_coverage.dart
FOCUS_UI_PNG=1 flutter test test/features/focus/presentation/focus_visual_test.dart
```

Der letzte Befehl schreibt Bilder aller Bildschirme (Light, Dark, 320 px bei Textskala 2,0) nach `build/focus_ui/` für den Sichtvergleich mit den Figma-Frames; ohne die Variable registriert die Datei keinen Test.

Hinweis zum Testen: Aufrufe von `FocusRestorer.restore()` im Widget-Test laufen in der Testzone (nicht in `runAsync`), weil der Countdown-Stream seine Werte in der Fake-Zone zustellt; `restoreFocus` im Test-Kit kapselt das.

## 8. Offene Punkte und Integration

Erledigt (Stand `577a853`): `FocusModule` ist in `bundledModules` registriert (Routen, Karten, Plus-Einträge); `initialize` läuft über den Modul-Lebenszyklus beim Start und bei Reaktivierung; die Dashboard-Karte hält `focusCountdownProvider` am Leben, sodass der Übergang in die Bestätigung auch ohne Fokusbildschirm stattfindet; die Modulverwaltung führt bei `MustResolveFirst` zu `/focus/session` (`focusDeactivationResolveRoute`); `feedbackServiceProvider` ist mit der Snackbar überschrieben; "Wochenziel ändern" öffnet den Zieleditor `/goals`; das Plus-Menü springt bei offener Sitzung direkt zu `/focus/session` (Abschnitt 5).

Offen:

- Tagesziel-Hinweis "ab morgen" gehört in den Zieleditor; die Workout-Übersicht verweist darauf.
- Erinnerung zum Fokus-Ende gehört zur Reminder-Engine (Zustandsänderung `FocusStateChanged`) und ist nicht Teil dieser Oberfläche.
- Verbleibende Sichtabweichungen siehe Abschnitt 4; die Frames wurden für Light verglichen, Dark wurde auf Lesbarkeit geprüft.
- Auf einem Gerät nicht geprüft: Hintergrundphasen und Prozessende, TalkBack, Systemschrift, echte Tastatur.

## 9. v0.2.0: Tagesziel „Workout heute“, Ruhetag und Überspringen (BS-99)

Ticket [BS-99](https://spacy-cloud.atlassian.net/browse/BS-99) (Bug, High). Entscheidungen D-024 und D-025 in [../implementation-decisions.md](../implementation-decisions.md). Der Datenvertrag (Tabelle `workout_day_marks`, Zieltyp `workout_daily`) kommt aus PR 8 (D-015, D-016); dieses Paket ändert weder Schema noch Backup. Entwurf (Figma, Datei LF10-Desing-App, Seite „v0.2.0 – Neue Screens“, Stand Entwurf, Freigabe liegt beim Projektinhaber): Karten-Zustände `4123:316`, Sheet „Wie war dein Tag?“ Hell `4117:473`, Dunkel `4117:770`, OLED `4117:1067`, Ziele bearbeiten `4117:249` (aus) und `4117:361` (an), „Ziele heute“ mit Workout und Wochenziel `4114:327` (gebaut mit BS-100, [dashboard-gamification.md](dashboard-gamification.md) Abschnitt 12).

### 9.1 Was das Ticket verlangt und was V1 tat (Reproduktion)

Das Ticket sagt: Das tägliche Workout-Ziel gelte erst als erledigt, wenn das komplette Wochenziel erreicht ist. Reproduziert auf dem unveränderten Code (Host-Widget-Test mit synthetischen Daten, Karte aus `FocusModule().dashboardCards`, heute Samstag 2026-10-03, nacheinander je ein Workout heute):

| Wochenziel | nach 1 Workout | nach 2 | letzter Schritt |
|---|---|---|---|
| 3 | „1 / 3 Trainings“, Ring 33 %, Hantel | „2 / 3“, 67 % | „3 / 3“, 100 %, **Haken** |
| 5 | „1 / 5“, 20 % | „2 / 5“, 40 %; „3 / 5“, 60 %; „4 / 5“, 80 % | „5 / 5“, 100 %, **Haken** |

Der Haken, das einzige „erledigt“-Zeichen der Karte, erscheint also erst beim vollen Wochenziel; das ist das beschriebene Verhalten. Es gibt in V1 aber kein tägliches Workout-Ziel: Die Karte ist die Wochenkarte (`workout_weekly`, `isDaily: false`), und der Tagesstatus enthält nur fünf Ziele (`water`, `steps`, `weight_entry`, `focus_minutes`, `task_completion`). In jedem der Schritte oben steht er bei „0 von 5“, der Tag ist nicht aktiv und die Streak ist 0: Ein Workout bewegt weder Tagesring noch Streak (nur die XP). Die Beschreibung setzt ein „Wochenziel gleich Tagesziel“ voraus, das es so nicht gab; sie meint die Wochenkarte, die als Tagesziel gelesen wurde. Die Lösung ist deshalb kein Eingriff in die Wochenzahlen, sondern ein eigenes, optionales Tagesziel (D-024).

### 9.2 Verhalten

- **Ziel.** „Workout heute“ ist ein Schalter im Ziele-Editor, standardmäßig **aus**. Aus: die Workout-Karte zeigt die Woche wie bisher, nichts ändert sich für vorhandene Nutzer, das Ziel zählt nicht in „x von y“. An (ab morgen, wie jede Zieländerung): ein Workout, ein Ruhetag oder ein übersprungener Tag erfüllen das Ziel; die Zahl der Workouts der Woche spielt keine Rolle (getestet mit Wochenziel 3 und 5).
- **Karte auf Home bei eingeschaltetem Ziel** (`WorkoutDashboardCard`, vier Zustände; der Tipp auf den Kartenkörper öffnet weiter den Workout-Bereich):

| Zustand | Wert | Zeile darunter | Aktion |
|---|---|---|---|
| offen | „Noch kein Training“ | „Heute offen“ | „Wie war dein Tag?“ (öffnet das Sheet) |
| Training | Titel des letzten Workouts des Tages, Häkchen davor | Muskelgruppen, sonst Kategorie, Dauer und Intensität; bei mehreren „n Trainings heute“ | „+ Training eintragen“ |
| Ruhetag | „Ruhetag“, Mond davor | „Zählt als erreicht, keine XP. Die Streak bleibt.“ | „Rückgängig“ |
| übersprungen | „Übersprungen“, Überspringen-Symbol davor | wie Ruhetag | „Rückgängig“ |

  Bei eingeschaltetem Ziel steht keine Wochenzahl auf der Karte (Entwurf); der Wochenstand steht im Workout-Bereich.
- **Sheet „Wie war dein Tag?“** (`WorkoutDaySheet`): Kopfzeile „WORKOUT HEUTE“ und die Frage, eigene Schließen-Taste, drei Antworten (Training eintragen, hervorgehoben in der grünen Tönung; Ruhetag; Heute überspringen, beide „Zählt als erreicht, keine XP“) und der Satz „Das Wochenziel bleibt getrennt und zählt nur echte Workouts.“ „Training eintragen“ öffnet das Formular (`/workouts/new`), die beiden anderen markieren heute. Das Sheet schließt mit Schließen-Taste, Tipp daneben und Android-Zurück ohne Antwort. Es liegt auf dem Root-Navigator über der ganzen Seite (wie `ConfirmationSheet`).
- **Markieren und Zurücknehmen.** Nach dem Speichern meldet die Snackbar „Ruhetag eingetragen“ oder „Heute übersprungen“ mit „Rückgängig“ (8 s, nimmt die Markierung zurück). „Rückgängig“ auf der Karte oder im Workout-Bereich nimmt sie später zurück („Eintrag für heute zurückgenommen“, wieder mit „Rückgängig“). Ein zweiter Tipp während des Speicherns wird ignoriert. Eine zweite Markierung für heute (zum Beispiel aus einem offenen Sheet nach einer Markierung an anderer Stelle) scheitert mit „Für heute gibt es schon einen Eintrag.“ und ändert nichts; ein Speicherfehler sagt „Speichern fehlgeschlagen. Es wurde nichts geändert.“
- **Workout hat Vorrang.** Hat der Tag ein Workout, gilt er als Training, auch wenn vorher ein Ruhetag markiert wurde; die Markierung bleibt gespeichert und gilt wieder, wenn das Workout gelöscht wird. Die Rücknahme wird dann nicht angeboten (sie entschiede den Tag nicht).
- **Workout-Bereich** (`/workouts`): bei eingeschaltetem Ziel steht über der Wochenkarte die Karte „Heute“ (Ziel: Workout heute) mit demselben Stand und, je nach Zustand, der Schaltfläche „Wie war dein Tag?“ oder „Rückgängig“; sie erscheint auch neben dem Leerzustand ohne ein einziges Workout (ein Ruhetag braucht kein Workout). Unten führt die Zeile „Tagesziel „Workout heute““ zum Ziele-Editor und sagt, ob das Ziel aus ist („Aus. Einschalten bei den Zielen, gilt ab morgen.“), an ist, oder ab morgen an oder aus sein wird.
- **Tageswechsel und Zeitzone.** Die Karte folgt `todayProvider`: nach Mitternacht ist der neue Tag offen, die Markierung des Vortags bleibt gespeichert. Die Markierung friert Tag und Zeitzone beim Setzen ein; eine spätere Zeitzonenänderung verschiebt sie nie.

### 9.3 Abweichungen vom Entwurf und vom Ticket

| Entwurf oder Ticket | Umsetzung | Grund |
|---|---|---|
| Karte offen (`4123:316`): drei Aktionen auf der Karte („+ Training eintragen“, „Ruhetag“, „Überspringen“) | eine Aktion „Wie war dein Tag?“, die das Sheet öffnet; „Training eintragen“ steht im Sheet an erster Stelle | Der Auftrag verlangt das Sheet von der Karte aus; jede Fläche hat 48 dp, drei Pillen untereinander wären in einer Zelle von 158 px bei 200 % Schrift über 140 dp hoch. Ein Tipp mehr für „Training eintragen“, wenn das Ziel an ist; wer lieber direkt eintragen will, nutzt das Plus-Menü |
| Aktionen als Text „Rückgängig“ in Grün, Pillen „Ruhetag“ und „Überspringen“ in Grau | Pille `MetricCardAction` im Modul-Akzent in Inhaltsbreite | gemeinsame Komponente aller Karten (wie bei BS-108) |
| Zustand Training ohne Symbol | Häkchen vor dem Titel; „Tagesziel erreicht“ im Sprechtext | Das Ticket verlangt „als erledigt markiert“; ohne Zeichen wäre der Zustand nur am fehlenden „Heute offen“ zu erkennen |
| Werte in 16 halbfett (offen) und 17 fett (übrige); Mond grün, Überspringen-Symbol orange | durchgehend 16 halbfett (`titleCard`), beide Symbole im Modul-Akzent | „Übersprungen“ in 17 fett passt nicht neben das Symbol in eine halbe Karte; ein Stil für alle Zustände |
| „Brust, Schulter, …“ | „Brust, Schultern, …“ | Name der Muskelgruppe im Code |
| Sheet über Home mit geöffnetem Plus-Menü, Navigationsleiste sichtbar | modales Sheet über der ganzen Seite, geöffnet von der Karte oder vom Workout-Bereich | Das Plus-Menü gehört der Shell (BS-117 ändert es gleichzeitig); ein Sheet über der Navigationsleiste macht den Hintergrund inaktiv |
| Karte ohne Wochenstand (Ziel an) | wie im Entwurf | der Wochenstand steht im Workout-Bereich und auf „Ziele heute“ in der Gruppe „Wochenziel · nicht im Tagesring“ (BS-100) |
| Karte bei ausgeschaltetem Ziel nicht entworfen | die Wochenkarte wie bisher | Entscheidung D-024 (Standard aus) |
| Zeile „Tagesziel „Workout heute““ im Workout-Bereich, Karte „Heute“ dort | nicht im Entwurf | Standard aus: ohne die Zeile fände man das Ziel nur im Profil; Auftrag: Sheet vom Workout-Bereich aus erreichbar |
| „Ziele heute“ mit Workout und Wochenziel (`4114:327`) | nicht Teil von BS-99; gebaut mit BS-100 | Die Seite gehört zu BS-100; ihre Abweichungen vom Entwurf stehen in [dashboard-gamification.md](dashboard-gamification.md) 12.7 |

`MetricCard` (`lib/core/design/components/metric_card.dart`, gemeinsame Datei) hat zwei neue optionale Parameter: `valueStyle` (kleinerer Stil für einen Text statt einer Zahl) und `valueIcon` (Symbol vor dem Wert, in einem `Wrap`, damit ein langes Wort unter das Symbol rückt statt mitten im Wort zu brechen). Kein bestehender Aufruf ändert sich. Außerdem brauchen zwei Auswahlen über `GoalType` im Onboarding einen Zweig für den neuen Wert (`daily_goal_stepper.dart`, `goalTitle`, und `option_icons.dart`, `goalLook`); das Onboarding bietet das Ziel nicht an.

### 9.4 Dateien

| Bereich | Dateien |
|---|---|
| Ziel, Tagesstatus, Snapshot (`lib/core/goals/`) | `domain/goal_type.dart` (`workoutDaily`, `defaultEnabled`), `goal_version.dart`, `day_status.dart` (`DayFacts.workoutEntries` und `workoutDayMark`, Regel, `DayStatus.progressOf`), `workout_day_mark_kind.dart`, `data/day_facts_source.dart` |
| Markierungen (`lib/features/focus/`) | `data/workout_day_mark_repository.dart`, `domain/workout_day_mark.dart` (Markierung, Zustand des Tages), `domain/workout_daily_goal.dart` (Plan heute und morgen), `application/workout_day_providers.dart` (Provider, `WorkoutDayActionsController`, `markWorkoutDay`, `takeBackWorkoutDay`) |
| Oberfläche (`lib/features/focus/presentation/`) | `workout_day_sheet.dart`, `workout_dashboard_card.dart` (Wochenkarte und Tageskarte), `workout_overview_screen.dart` (Karte „Heute“, Zielzeile), `workout_labels.dart` |
| Editor und Profil (`lib/features/profile/`) | `domain/goal_editor.dart`, `profile_overview.dart`, `presentation/goals_screen.dart`, `profile_screen.dart` |
| Onboarding und Testhilfe | `lib/core/onboarding/onboarding_repository.dart` und `lib/core/testing/data_harness.dart` (keine eingeschaltete Zielversion für `workoutDaily`) |

### 9.5 Barrierefreiheit

- Jede Fläche mindestens 48 x 48: Aktionspille der Karte (36 sichtbar, 48 Tippfläche), die drei Antworten des Sheets (mindestens 64 hoch), „Rückgängig“ im Workout-Bereich (Standardbutton), Schließen-Taste (48). Geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` bei 320, 360, 393 und 430 px mit Textskala 1,0 und 2,0.
- Das Sheet ist ein benannter Bereich („Wie war dein Tag?“), die Frage eine Überschrift, jede Antwort eine Schaltfläche mit Titel und Erklärung („Ruhetag, Zählt als erreicht, keine XP“); die Zeile „WORKOUT HEUTE“ ist Dekor. Bei großer Schrift (ab Skala 1,3) rückt die Schließen-Taste in eine eigene Zeile über den Titel; der Inhalt scrollt.
- Die Karte wird als eine Schaltfläche mit ihrem Zustand gelesen („Workout, Ruhetag, Zählt als erreicht, keine XP. Die Streak bleibt., Tagesziel erreicht“); die Aktion ist eine eigene Schaltfläche („Ruhetag rückgängig machen“). Der Zustand steht immer in Worten und mit Symbol, nie nur in einer Farbe.
- Kontrast: die Farbpaare des Sheets (Text auf Fläche und auf der grünen Tönung, Symbole auf ihrer Kachel) sind in Hell, Dunkel und OLED gemessen (4,5 zu 1 für Text, 3 zu 1 für Symbole); die Framework-Richtlinie für Textkontrast misst hinter dem Schleier eines modalen Sheets falsch und wird dort nicht benutzt.

### 9.6 Tests

Alle Testnamen tragen den Ticketschlüssel `(BS-99)` und, wo einer passt, die Abnahme-ID (AT20, AT22 bis AT25, AT27, AT30, AT33 bis AT35).

| Datei | Tests | Schwerpunkt |
|---|---:|---|
| `test/core/goals/domain/day_status_test.dart` (Gruppe „daily workout goal“) | 9 | ein Workout reicht, Ruhetag und Überspringen, offener Tag, Wochenziel im Snapshot ignoriert, aus zählt nie, Ring, Streak-Aktivität |
| `test/core/goals/domain/day_snapshot_test.dart`, `goal_type_test.dart`, `goal_version_test.dart` | 9 neu, 12 angepasst (mit `projection_integration_test.dart`) | Snapshot mit sechstem Ziel (aus, ab morgen, Modul), Standard aus, Schlüssel gleich Schema |
| `test/core/goals/data/workout_daily_goal_test.dart` | 29 | echte Datenbank und Projektion: ein Workout bei Wochenziel 3 und 5, Ruhetag, Überspringen, kein XP, Streak, Ziel aus, ab morgen, Wochenziel getrennt, Zeitzone und Tageswechsel, Streams |
| `test/features/focus/data/workout_day_mark_repository_test.dart` | 22 | Commands, Konflikt, Wiederholung mit gleicher ID, Schreibfehler, Undo und Konflikte, Zeitzone, Datenbankregel |
| `test/features/focus/domain/workout_day_mark_test.dart` | 14 | Zustand des Tages, Vorrang, Plan des Ziels |
| `test/core/backup/workout_day_marks_roundtrip_test.dart` | 5 | Rundlauf mit den Commands: nur aktive Markierungen, Zeile für Zeile, Tage, Streak und XP nach dem Import, byte-gleicher Export |
| `test/features/focus/presentation/workout_day_sheet_test.dart` | 23 | Inhalt, Antworten, Schließen, Semantik, vier Breiten, zwei Textgrößen, drei Themes |
| `test/features/focus/presentation/workout_day_card_test.dart` | 33 | Karte in vier Zuständen, Wochenkarte bei aus, ab morgen, Sheet, Markieren, Undo, Konflikt, Fehler, Tageswechsel, Semantik, Breiten, Themes |
| `test/features/focus/presentation/workout_overview_day_test.dart` | 17 | Workout-Bereich: Karte „Heute“, Zielzeile, Leerzustand, Semantik, Breiten |
| `test/features/focus/presentation/workout_labels_test.dart` | 6 neu | Texte |
| `test/features/profile/**` (Domain, Controller, Editor, Profil) | 39 neu | Zeile im Editor, Reihenfolge, Notiz, Speichern ab morgen, Fehler und Wiederholung, Profilzeile |
| `test/core/onboarding/onboarding_repository_test.dart` | 4 neu | keine Zielversion für das Tagesziel |
| `test/core/design/components/display_test.dart` | 5 neu | `MetricCard.valueStyle` und `valueIcon` |
| `test/app/route_sweep_test.dart` | 30 neu | Home, Workout-Bereich und Editor mit eingeschaltetem Ziel in jedem Zustand des Tages |
| `test/features/focus/presentation/workout_day_visual_test.dart` | 0 | schreibt nur mit `WORKOUT_DAY_PNG=1` Bilder nach `build/workout_day/` (Sichtvergleich mit den Figma-Frames) |

Gesamtzahl: 245 neue Tests gegenüber der Basis (PR 8: 6657, danach 6902). Bestehende Tests, die über `GoalType.values` oder die fünf Tagesziele zählten, sind angepasst (17: Snapshot, Tagesstatus, Zieltypen, Zielversionen, Editor, Onboarding, Zeilenzahl der Zielzeilen im Workout-Bereich).

### 9.7 Offene Punkte und Grenzen

- Nur Host-Tests. Nicht auf einem Gerät geprüft: TalkBack, echte Systemschrift, Darstellung auf dem Telefon, die Reihenfolge der Snackbar mit dem Sheet.
- Ruhetag und Überspringen lassen sich nur für **heute** setzen und zurücknehmen; ein vergessener Tag in der Vergangenheit lässt sich in der Oberfläche nicht nachtragen (das Repository nimmt ein Datum entgegen, eine Oberfläche dafür gibt es nicht). Die Streak bleibt dann unterbrochen.
- Die Seite „Ziele heute“ (BS-100) liest `DayStatus.progressOf(GoalType.workoutDaily)` und `workoutDayStateProvider` (Zustand, Art, `takeBackMark`); für einen vergangenen Tag (BS-93) liest sie `workoutDayStateOnProvider` (Abschnitt 10).
- Das Plus-Menü führt für „Workout“ weiter direkt zum Formular.

## 10. v0.2.0: Karten an einem vergangenen Tag (BS-93)

Zeigt Home einen der letzten sieben Tage ([dashboard-gamification.md](dashboard-gamification.md) Abschnitt 13), bauen sich die Karten „Workout“ und „Fokus“ für diesen Tag und nur lesend (`WorkoutPastDayCard`, `FocusPastDayCard`; die Karten von heute sind unverändert).

- **Workout** zeigt, was der **Tag** war (`workoutDayStateOnProvider`: dieselbe Funktion `buildWorkoutDayState` wie bei `workoutDayStateProvider`, mit dem Tag): den Titel des neuesten Trainings und die Muskelgruppen, bei mehreren „2 Trainings an diesem Tag“, einen Ruhetag oder „Übersprungen“ mit dem Satz, was sie wert sind („Zählt als erreicht, keine XP. Die Streak bleibt.“), oder „–“ mit „Kein Training eingetragen“. Die Woche ist kein Tageswert und bleibt auf der Karte von heute. **Keine Aktion:** „Wie war dein Tag?“, „Training eintragen“ und „Rückgängig“ gibt es an einem vergangenen Tag nicht (Ruhetag und Überspringen lassen sich nur für heute setzen und zurücknehmen, 9.2); die Karte öffnet den Workout-Bereich.
- **Fokus** zeigt die gespeicherte Fokuszeit der an diesem Tag abgeschlossenen Sitzungen gegen das Ziel, das an diesem Tag galt (`focusDaySummaryProvider`, dieselbe Funktion `buildFocusTodaySummary`), mit Sätzen der Vergangenheit („Tagesziel erreicht“, „Es fehlten 5 Min. bis zum Tagesziel“); eine offene Sitzung gehört zur Gegenwart und fehlt, ebenso „Fokus fortsetzen“. Das Ziel kommt aus dem Snapshot dieses Tages, nicht aus den Zielversionen: `focusGoalMinutesOfDay` liest das Fokusziel aus `dayStatusProvider(tag)`, dem Status, den auch der Ring dieses Tages zeigt, wie die Karten für Wasser und Schritte. Galt das Fokusziel an dem Tag nicht (das Modul war aus oder das Ziel ausgeschaltet), steht „Kein Tagesziel an diesem Tag“ mit der Fokuszeit in Minuten, ohne „Es fehlten … Min.“ und ohne Balken (vorher hätte ein Tag mit ausgeschaltetem Modul das heutige Ziel gezeigt, während der Ring es nicht zählte). Ein Tag ohne Sitzung zeigt „–“ mit dem Ziel und „Keine Sitzung an diesem Tag“, keine „0 Min.“.
- Auf „Ziele heute“ für einen vergangenen Tag beantwortet `workoutDayStateOnProvider` die Zeile „Workout heute“ mit dem Workout und der Markierung **dieses** Tages.
