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
| Dashboard-Karten `focus` und `workout` | (Home) | Home `2013:2` | Fokus: Tagesstand oder offene Sitzung mit "Fokus fortsetzen"; Workout: Wochenring mit echtem Stand |

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
| `presentation/focus_history_screens_test.dart` | 22 | Verlauf, Zonen, seitenweise Laden, Notiz, Löschen mit Rückgängig, Konflikte, Verwerfen-Dialog (AT23, AT25, AT27, AT36, F02) |
| `presentation/workout_form_screen_test.dart` | 26 | leeres Formular, Grenzen 0/1/600/601, optionale Felder, Fehler, Wiederholung, Bearbeiten, Löschen (AT12, AT20, AT23, AT27, F03) |
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

Erledigt (Stand `c0ce096`): `FocusModule` ist in `bundledModules` registriert (Routen, Karten, Plus-Einträge); `initialize` läuft über den Modul-Lebenszyklus beim Start und bei Reaktivierung; die Dashboard-Karte hält `focusCountdownProvider` am Leben, sodass der Übergang in die Bestätigung auch ohne Fokusbildschirm stattfindet; die Modulverwaltung führt bei `MustResolveFirst` zu `/focus/session` (`focusDeactivationResolveRoute`); `feedbackServiceProvider` ist mit der Snackbar überschrieben; "Wochenziel ändern" öffnet den Zieleditor `/goals`; das Plus-Menü springt bei offener Sitzung direkt zu `/focus/session` (Abschnitt 5).

Offen:

- Tagesziel-Hinweis "ab morgen" gehört in den Zieleditor; die Workout-Übersicht verweist darauf.
- Erinnerung zum Fokus-Ende gehört zur Reminder-Engine (Zustandsänderung `FocusStateChanged`) und ist nicht Teil dieser Oberfläche.
- Verbleibende Sichtabweichungen siehe Abschnitt 4; die Frames wurden für Light verglichen, Dark wurde auf Lesbarkeit geprüft.
- Auf einem Gerät nicht geprüft: Hintergrundphasen und Prozessende, TalkBack, Systemschrift, echte Tastatur.
