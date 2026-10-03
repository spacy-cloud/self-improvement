# Analyse (BS-71)

Der Tab „Analyse“ vergleicht 7, 30 oder 90 lokale Kalendertage (heute eingeschlossen) mit der gleich langen Periode direkt davor. Die Oberfläche rechnet nichts selbst: Zahlen, Vergleiche, Texte und Sprechtexte kommen aus der Analyse-Engine (`lib/core/analysis`, Provider `analysisReportProvider`).

## Screens und Figma-Knoten

| Screen | Figma (Light) | Einstieg | Datei |
|---|---|---|---|
| Analyse | `4033:2` (Dark `4056:2285`, OLED `4056:4092` über die Token-Modi) | `/analysis`, Klasse `AnalysisScreen` | `lib/features/analysis/presentation/analysis_screen.dart` |
| Analyse als Tabelle | `4056:421` | Link „Als Tabelle“, Seite über dem Tab ohne Navigationsleiste | `lib/features/analysis/presentation/analysis_table_screen.dart` |

Analyse ist kein eigenes Modul (keine Modulklasse, Karte oder Schnellaktion).

## Aufbau

1. Zeitraumwahl (`PeriodSelector`), Auswahl im Provider `analysisPeriodProvider` (überlebt Drehung, neuen Widget-Baum und Tabwechsel; nach einem Prozess-Neustart wieder 7 Tage).
2. Datumstext (`27.09. bis 03.10.2026, inklusive heute`), Link „Als Tabelle“, Vergleichszeitraum (`Vorherige 7 Tage: 20.09. bis 26.09.2026`); ist ein Vergleich noch nicht möglich, steht ein Hinweis mit Datum da.
3. Hero „Tagesziele komplett“ (`3 von 6 Tagen`, Veränderung in Prozentpunkten, aktive Tage, Definitionen); für 7 Tage der Wochenstreifen (Haken, Ring, Strich, Wochentag) aus `AnalysisReport.goalDays`.
4. Kartenraster der aktiven Module (Schritte, Wasser, Workouts, Fokuszeit, Aufgaben, Gewohnheiten, Gewicht, Mahlzeiten) mit Abdeckung (`5/7 Tage erfasst`), Vergleich (`gegenüber den vorherigen 7 Tagen`), weiteren Kennzahlen, Definitionen und Status (`Kalorien unvollständig`).
5. Separate Workout-Wochenkarte (Montag bis heute gegen dieselben Wochentage der Vorwoche, Ring beim Wochenziel, unabhängig vom Zeitraum).
6. „Verlauf“: je Reihe mit Daten eine `ChartSummary` (Diagramm, Zusammenfassung, Tabelle mit denselben Tageswerten).

Tabellenseite: je Kennzahl eine Zeile (aktuell, vorherige, Veränderung, Erfassung beider Zeiträume), Wochentabelle und hinter dem Schalter „Werte pro Tag“ alle Tage; die Zeilen sind dieselben `AnalysisFigure`-Objekte wie die Karten.

## Zustände

- Laden: neutraler Text.
- Fehler: `ErrorState` mit „Erneut versuchen“ (`ref.invalidate`), Live-Region.
- Zeitraumwechsel: der alte Bericht wird abgeblendet mit „Wird aktualisiert …“ angezeigt.
- Keine Daten: „Noch keine Daten“, nie eine erfundene 0.
- Kein Modul mit Analysedaten aktiv (alle aus oder nur Fortschritt): „Kein Modul für die Analyse aktiv“ mit „Module verwalten“ (`/settings/modules`).
- Kein Vergleich möglich: `Noch kein Vergleich` mit einmaliger Begründung.

## Abweichungen vom Figma

- Veränderung grün/rot wird neutral mit Pfeil und Vorzeichen dargestellt (die Analyse wertet nicht, Farbe ist nie alleiniger Träger).
- „ggü. Vorwoche“ heißt „gegenüber den vorherigen N Tagen“ (30/90 Tage sind keine Wochen).
- Hero „+1 Tag“ wird in Prozentpunkten angegeben (die Nenner der Perioden können verschieden sein).
- Datumstext der Engine statt „8.–14. September“; Gewohnheiten als Prozent mit Zähler/Nenner-Zeile; Titel „Gewohnheiten“, „Mahlzeiten“, „Fokuszeit“.
- Zusätzlich Abdeckung x/N, Gesamtwerte und Definitionen (freigegebene Abweichung).
- Diagramme stehen unter „Verlauf“ (der Frame zeigt keine); die Wochenkarte ist eine eigene Karte.
- Tabelle: Bezeichnung, darunter drei Spalten (lange Formelnamen); unter 280 px Kartenbreite und ab 130 % Text als Blöcke. Das Raster ist zweispaltig ab etwa 344 px und bis 130 % Text.
- Kein zusätzlicher Modulfilter-Chip: die Filterung nach Modulstatus erfolgt automatisch.

## Spezifikationskonflikte

Spezifikation 12 „Schritte als Summe“ gegen Ticket BS-71 „Durchschnitt über erfasste Tage“: das Ticket gilt; Durchschnitt und Summe werden gezeigt, ohne Nullauffüllung.

## Änderungen an der Engine

`domain/goal_days.dart` (neu), `AnalysisReport.goalDays`, `AnalysisReport.hasAnalysedModule`, `AnalysisMetric.analysedModules`; Tests `goal_days_test.dart` und `analysed_modules_test.dart`; die 266 bestehenden Tests blieben unverändert grün.

## Barrierefreiheit

Karte, Wochenkarte und Tabellenzeile sind je ein Block mit dem Sprechsatz der Engine; der Wochenstreifen nennt jeden Tag in Worten. Diagramme sind dekorativ ausgeschlossen, Zusammenfassung und Tabelle tragen die Bedeutung, leere Plätze und erfasste Nullen unterscheiden sich im Bild und im Text. Ein Zustand wird nie nur durch Farbe vermittelt. Tap-Ziele sind mindestens 48 px groß (`androidTapTargetGuideline`, `labeledTapTargetGuideline`), Labels sind deutsch, Text bis 200 % wird nicht abgeschnitten, Bewegung läuft nur über `AppMotion`.

## Tests

`flutter test test/features/analysis` (123):

- `analysis_screen_test.dart` (48; A01, AT03, AT04, AT08, AT14, AT15, AT20, AT34, Q02, Q03)
- `analysis_table_screen_test.dart` (17; AT20, AT34, Q02)
- `analysis_accessibility_test.dart` (48; AT33 mit 320/360/393/430 px bei 100 % und 200 %, Tap-Ziele, Sprechtexte AT34, Themen und reduzierte Bewegung AT35, Q03)
- `analysis_acceptance_test.dart` (10; Ende-zu-Ende mit echter In-Memory-Datenbank: AT15, AT08, AT14, AT20, AT23, Grenztage, AT03/AT04, neuer Tag)

Engine: `flutter test test/core/analysis` (279). Feste Uhr 2026-10-03 Europe/Berlin, synthetische Daten.

## Offene Punkte

- Die Tabellenseite wird über den Root-Navigator geöffnet (kein Routeneintrag); für einen Deep Link `/analysis/table` registrieren und `context.push` nutzen.
- Der Wochenstreifen existiert nur für 7 Tage.
- Der Zeitraum wird nicht über einen Prozess-Neustart gespeichert.
- `analysisReportProvider` wird nach dem ersten Lesen nicht verworfen.
- Android-Zurück auf der Tabellenseite wurde nur mit `MaterialApp` getestet, nicht mit der echten Shell.
- Der Kontrast in Dark/OLED wurde nicht gesondert gemessen.
