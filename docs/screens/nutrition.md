# Ernährung: Wasser und Mahlzeiten (BS-62, BS-59)

Oberfläche des Moduls `nutrition`: ein gemeinsamer Wasser-Screen, die Mahlzeitenübersicht, die Formulare, zwei Dashboard-Karten und zwei Plus-Menü-Einträge. Fachlogik, Datenschicht und Tests der Engine liegen unverändert in `lib/features/nutrition/{domain,data,application}`; die Oberfläche steht in `lib/features/nutrition/presentation`, die Modulregistrierung in `lib/features/nutrition/nutrition_module.dart`.

## 1. Screens, Routen und Figma-Knoten

Figma-Datei `K4IWQEjnzuNkRUzkq8JaKz`, Light-Knoten. Dark und OLED ergeben sich aus den Token-Modi.

| Screen | Route | Figma | Datei |
|---|---|---|---|
| Wasser eintragen (Tagesstand, Schnellwahl, Tagesziel, Verlauf) | `/water` | `4021:2`, 360 px `4057:92`, 320 px `4057:208` | `water_screen.dart` |
| Eigene Menge (Sheet auf `/water`) | Zustand von `/water` | `4055:25` | `water_custom_sheet.dart` |
| Tagesziel ändern (Sheet auf `/water`) | Zustand von `/water` | kein eigener Frame (Muster `4055:25`) | `water_goal_sheet.dart` |
| Wassereintrag bearbeiten, löschen, rückgängig | `/water/:id` | Muster Gewicht `4053:314`, `4053:422`, `4053:541` | `water_edit_screen.dart` |
| Ernährung (Übersicht, Verlauf) | `/nutrition` | `4041:2` | `meals_screen.dart` |
| Mahlzeit eintragen und bearbeiten | `/nutrition/new`, `/nutrition/:id` | `4041:136`, Bearbeiten nach Muster Gewicht | `meal_form_screen.dart` |
| Dashboard-Karte Wasser | Karte `water` | Wasserkarte in Home `2013:2` | `water_dashboard_card.dart` |
| Dashboard-Karte Ernährung | Karte `nutrition` | kein Frame (Muster Gewichtskarte) | `nutrition_dashboard_card.dart` |

Routenreihenfolge in `NutritionModule.routes`: `/water`, `/water/:id`, `/nutrition`, `/nutrition/new`, `/nutrition/:id` (statisch vor parametrisch, damit `/nutrition/new` nie als Mahlzeit-ID gelesen wird). Plus-Menü: `water` (Position 2, Route `/water`) und `meal` (Position 7, Route `/nutrition/new`). Es gibt keine Wasser-Detailseite; `/water/:id` ist nur der Editor eines einzelnen Eintrags.

## 2. Verhalten

### Wasser

- **Schnellwahl** 250 ml und 500 ml: ein Tippen ist genau ein Befehl mit neuer Command-ID und speichert sofort einen echten Eintrag zur aktuellen Zeit. Zwei Tippen sind zwei Einträge. Die Erfolgsmeldung mit „Rückgängig“ (8 s) erscheint erst nach dem Commit.
- **Fehler** beim Schnellwahl-Speichern: nichts wird gespeichert (weder Menge noch XP). Eine Meldung im Screen bzw. in der Karte und die Snackbar bieten „Erneut versuchen“; der Wiederholungsversuch nutzt dieselbe Command-ID und erzeugt nie einen zweiten Eintrag.
- **Zwei Bedienaktionen vom Dashboard**: die Wasserkarte trägt die Buttons „+ 250 ml“ und „+ 500 ml“ direkt (eine Aktion bis zum Commit). Die Buttons liegen außerhalb der Kartenfläche und öffnen den Screen nicht; ein Tippen auf die Kartenfläche öffnet `/water`.
- **Eigene Menge** (Sheet): 50 bis 2000 ml, ganze Zahl, Plus/Minus in 10-ml-Schritten (leeres Feld startet bei 250), Zeitpunkt (Datums- und Zeitwähler, keine Zukunft) und Notiz bis 500 Zeichen. Der Button nennt die Menge („330 ml hinzufügen“). Fehler stehen im Sheet (es verdeckt die Snackbar) und erhalten die Eingabe; erneutes Tippen ist derselbe Befehl.
- **Verlauf**: „Heute getrunken“ und frühere Tage mit Tagessumme in Litern (`formatLiters`, bis zu zwei Nachkommastellen ohne unnötige Nullen), Einträge in ml. Zeile antippen bearbeitet, die Taste „✕“ löscht nach Bestätigung (mit Undo). „Ältere Tage anzeigen“ erweitert das Fenster um 30 Tage, bis nichts Älteres mehr kommt.
- **Tagesziel**: Sheet mit 250 bis 10000 ml in 50-ml-Schritten, Hinweis „gilt ab morgen“ (heute bleibt der eingefrorene Schwellenwert), gespeichert über `GoalsCommands`. Die Zeile „Tagesziel“ zeigt, was heute und ab morgen gilt.
- **Fortschritt**: Ring und Dashboard-Balken sind auf 100 % begrenzt, die echte Menge und der echte Prozentwert (z. B. 112 %) bleiben als Text sichtbar. Ohne aktives Ziel gibt es nur die echte Summe. Das Erreichen des Ziels erzeugt keinen Datensatz.

### Mahlzeiten

- **Übersicht**: Anzahl der heutigen Mahlzeiten und Summe der **bekannten** Kalorien. Fehlt mindestens eine Angabe, steht „Kalorien unvollständig: n Mahlzeiten ohne Kalorienangabe“; fehlt jede Angabe, gibt es keine Kalorienzahl („Keine Kalorien angegeben“, nie „0 kcal“). Eine bewusste 0 ist ein Wert („0 kcal“) und macht die Summe nicht unvollständig. Zeilen ohne Wert zeigen „Keine Angabe“. Frühere Tage folgen mit eigener Zusammenfassung.
- **Formular**: Name 1 bis 80 Zeichen nach Trim (Pflicht), Kalorien optional als ganze Zahl 0 bis 5000 (leer heißt unbekannt, 0 ist gültig), Zeitpunkt, Notiz bis 500 Zeichen. Alle Fehlerhinweise erscheinen zugleich, die Eingabe bleibt erhalten, ein Doppeltipp speichert einmal, ein Fehler lässt „Erneut“ mit derselben Command-ID zu.
- **Bearbeiten und Löschen** nach dem Gewichtsmuster: Speichern bleibt aus, bis etwas geändert ist; Löschen fragt nach, meldet nach dem Commit und bietet Undo (stellt dieselbe ID wieder her). In der Liste öffnet das Menü „⋮“ ein Sheet mit Bearbeiten und Löschen.
- Keine Ernährungsbewertung, kein Kalorienziel, keine XP für Mahlzeiten, keine Demo-Einträge.

### Dashboard-Karten

- **Wasser**: echte Summe mit Ziel („1,5 / 2,5 l“), Balken, Prozent- bzw. Zielstatus als Text, Schnellwahl-Buttons, bei einem Fehler Hinweis mit „Erneut versuchen“.
- **Ernährung**: Anzahl der Mahlzeiten, bekannte Kalorien bzw. „Kalorien unvollständig“, Aktion „Mahlzeit eintragen“. Ohne Mahlzeit nur „–“ und der Weg zum Eintragen.

## 3. Abweichungen vom Figma-Entwurf und Gründe

| Abweichung | Grund |
|---|---|
| Schnellwahl ohne „Groß 750 ml“; „Eigene Menge“ als volle Zeile unter Glas und Flasche | Spezifikation und Ticket kennen nur 250/500 ml. |
| Eigene Menge: Hinweis „50 bis 2.000 ml“ statt „10 bis 2.000 ml“; zusätzlich Zeitpunkt und Notiz; Button fest unten | Spezifikation (50 bis 2000 ml) und Ticket (Zeitpunkt, Notiz); der feste Button bleibt bei Tastatur und 200 % Schrift erreichbar. |
| Verlaufszeilen zeigen Uhrzeit und Menge, nicht „Glas“/„Flasche“ | Das Datenmodell hat keinen Namen; ein Name aus der Menge wäre erfunden. |
| „Noch 1 l bis zum Ziel“ statt „Noch 1,0 l“ | Spezifikation: Liter ohne unnötige Nullen. |
| Mahlzeit ohne die Chips „Art“ (Frühstück, Mittag, Abend, Snack); Zeilenuntertitel nur mit Uhrzeit | Das Datenmodell kennt nur Name, Kalorien, Zeit, Notiz. |
| Hinweis „Kalorien unvollständig: …“ statt „Unvollständig: …“ | Wortlaut der Spezifikation. |
| Zeitpunkt als Listenzeile mit Datums- und Zeitwähler (wie das Gewichtsformular) statt Eingabefeld mit Kalender-Symbol | Konsistenz mit dem Referenzformular; Datum und Zeit sind getrennt wählbar. |
| Kalorien-Einheit im Label („Kalorien in kcal“) statt als Suffix im Feld | Ein Suffix im zusammengeführten Textfeld löst in scrollenden Formularen eine Semantics-Assertion des Frameworks aus. |
| Wasserkarte im Dashboard mit zwei Schnellwahl-Buttons | Im Home-Frame nicht gezeichnet; Spezifikation verlangt höchstens zwei Bedienaktionen. In der halbbreiten Karte stehen die Buttons untereinander. |
| Symbole der Schnellkacheln: Glas `local_drink`, Flasche `water_drop` | Nächste Material-Entsprechungen (keine Flaschenform vorhanden). |
| Zielzeile und Ziel-Sheet im Wasser-Screen | Kein Frame; das Ticket verlangt die Zieländerung „ab morgen“ in diesem Umfang. |
| Fehlerzustand der Dashboard-Karten als `MetricCard` mit Aktion statt `ErrorState` | `ErrorState` misst seine Breite mit einem `LayoutBuilder`; das Kartenraster (`AdaptiveGrid`, gleiche Zeilenhöhe) kann das nicht messen. |

## 4. Konflikte zwischen Spezifikation, Handoff und Frames

- **Routen**: Die Spezifikation nennt `/nutrition/water` und `/nutrition/meals`; Handoff und Aufgabe nennen `/water`, `/nutrition`, `/nutrition/new`. Die Handoff-Routen gelten.
- **Mindestmenge** 10 ml im Frame, 50 ml in der Spezifikation: Spezifikation gewinnt.
- **Schnellwahl** 750 ml im Frame, 250/500 ml in Spezifikation und Ticket: Spezifikation gewinnt.
- **Anzeige** „1,0 l“ im Frame, „ohne unnötige Nullen“ in der Spezifikation: Spezifikation gewinnt.
- **Undo-Dauer** 5 s in einer Figma-Notiz, 8 s in der Aufgabe: 8 s (Design-System-Wert).

## 5. Barrierefreiheit

- Tippflächen mindestens 48 x 48 (geprüft mit `androidTapTargetGuideline`, `labeledTapTargetGuideline`), alle Icon-Tasten mit deutschem Label („Eintrag von 09:00 Uhr, 250 ml, löschen“, „Aktionen für Apfel“, „um 10 Milliliter erhöhen“, „Schließen“).
- Ring und Dashboard-Balken sprechen die echte Fortschrittszeile („Wasser heute: 2,8 l von 2,5 l, 112 Prozent erreicht, Tagesziel erreicht.“); der Zielstatus ist Text mit Symbol, nie nur Farbe.
- Fehler stehen neben dem Feld und werden als Live-Region angekündigt; die Eingabe bleibt erhalten.
- Sheets sind eigene Routen mit Titel, sichtbarer Schließen-Taste und Android-Zurück; sie lassen sich nicht wegwischen, wenn Eingaben offen sind (Nachfrage „Änderungen verwerfen?“).
- Text skaliert bis 200 % ohne Abschneiden (Inhalt scrollt, Karten und Zeilen brechen um, Ring wächst mit); der große Zahlenwert ist auf 130 % begrenzt und schrumpft bei Platzmangel. Geprüft bei 320, 360, 393 und 430 px mit 100 % und 200 %.
- Aktionsleisten (Fertig, Speichern, Hinzufügen) bleiben über der Tastatur sichtbar; kein Wisch-Gesten-Zwang, jede Aktion hat eine Taste.
- Bewegung nur über die Design-System-Dauern; kein Dauerlauf.

## 6. Tests

`test/features/nutrition/presentation/` (Widget-Tests mit In-Memory-Datenbank, fester Uhr 2026-10-03 Europe/Berlin) und `test/features/nutrition/nutrition_module_test.dart`.

| Datei | Inhalt | Abnahme-IDs |
|---|---|---|
| `water_screen_test.dart` | Daten-, Leer-, Fehler-, Ladezustand, Ring bei 112 %, Schnellwahl mit Undo und XP, unabhängige Klicks, Fehlschlag mit Wiederholung derselben ID, Löschen mit Undo, Verlauf, Tagesziel ab morgen | AT10, AT11, AT12, AT23, AT24, AT27, N01, C05, G01, A01 |
| `water_custom_sheet_test.dart` | Grenzen 49/50/2000/2001 ml, Schrittschalter, Speichern mit Notiz und Zeit, Doppeltipp, Fehlschlag mit Wiederholung, Verwerfen-Abfrage, Tastatur bei 200 % | AT12, AT27, N01, C05 |
| `water_edit_screen_test.dart` | Bearbeiten, Validierung, Konflikt, Löschen mit Undo, Verwerfen, nicht gefunden, Lade- und Fehlerzustand | AT10, AT12, AT23, AT27 |
| `meals_screen_test.dart` | Anzahl und bekannte Summe, „Kalorien unvollständig“, nur fehlende Werte, bewusste 0, Leerzustand, Verlauf, Menü, Löschen mit Undo | AT14, AT23, N02, A01 |
| `meal_form_screen_test.dart` | Anlegen ohne kcal, Grenzen Name 80/81 und kcal -1/0/5000/5001, Fehlermeldungen, Doppeltipp, Fehlschlag mit Wiederholung, Verwerfen-Abfrage, Bearbeiten, Löschen mit Undo | AT12, AT14, AT23, AT27, N02, C05 |
| `dashboard_cards_test.dart` | Wasserkarte (eine Aktion bis zum Commit, Detail bleibt zu, Fehlschlag, Ziel überschritten), Ernährungskarte, Raster bei 320 bis 430 px | AT10, AT12, AT14, AT27, N01, N02 |
| `responsive_accessibility_test.dart` | 10 Zustände x 4 Breiten x 2 Schriftgrößen ohne Überlauf, Tap-Ziele und Labels, Semantics, Dark/OLED | AT33, AT34 (Teil) |
| `nutrition_module_test.dart` | Routenreihenfolge, Karten-IDs und Ränge, Plus-Menü | - |
| `visual_check_test.dart` | schreibt PNGs unter `build/` für den Vergleich mit den Frames | - |

Befehle: `flutter test test/features/nutrition` (607 Tests, davon 243 der Oberfläche, die übrigen sind die Engine-Tests) und `flutter test` (Gesamtlauf, 4341 Tests grün). `dart run tool/at_coverage.dart` ordnet die Tests den Abnahmefällen AT10, AT11, AT12, AT14, AT23, AT24 und AT27 zu.

## 7. Offene Punkte

- Die Karten und Routen erscheinen in der App erst, wenn die Shell `NutritionModule` zentral registriert (Routen, Karten, Plus-Menü).
- `ErrorState` kann in einer Zelle des `AdaptiveGrid` nicht gemessen werden (betrifft auch die Gewichtskarte); die Nutrition-Karten umgehen das, eine Korrektur im Design-System steht aus.
- TalkBack, Systemschrift und Tastatur auf einem echten Gerät sind hier nicht prüfbar (kein SDK); geprüft sind Host-Tests für Semantics, Tap-Ziele und Skalierung.
- Ein Mahlzeitentyp (Frühstück, Mittag, ...) würde eine Schemaerweiterung brauchen und ist nicht Teil von V1.
- Datums- und Zeitwähler sind die Material-Dialoge; ein eigenes Design dafür gibt es nicht.
