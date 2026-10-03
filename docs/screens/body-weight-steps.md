# Gewicht und Schritte (BS-61, BS-60)

Oberfläche des Moduls `body`: Gewicht ([BS-61](https://spacy-cloud.atlassian.net/browse/BS-61), P0) und manuell erfasste Schritte ([BS-60](https://spacy-cloud.atlassian.net/browse/BS-60), P1). Fachliche Regeln liegen als reine Dart-Funktionen in `domain/`, Lesen und Befehle in `data/`, Zustand in `application/`, die Oberfläche in `presentation/`. Code: `lib/features/body/` (Gewicht) und `lib/features/body/steps/` (Schritte), Registrierung in `lib/features/body/body_module.dart`. Die Screens enthalten weder SQL noch Regeln; jeder gezeigte Wert stammt aus der Datenbank. Beschrieben ist der Code-Stand `c0ce096`.

## 1. Screens, Routen und Figma-Knoten

Figma-Datei `K4IWQEjnzuNkRUzkq8JaKz`, Light-Knoten. Dark und OLED ergeben sich aus den Token-Modi.

| Screen | Route | Figma | Klasse (Datei) |
|---|---|---|---|
| Gewicht, Übersicht „Mein Gewicht“ | `/weight` | `4006:2` (Dark `4056:928`, OLED `4056:2735`); Ladefehler `4045:340` | `WeightOverviewScreen` (`weight_overview_screen.dart`) |
| Gewicht, Alle Messungen | `/weight/all` | `4056:39` | `WeightHistoryScreen` (`weight_history_screen.dart`) |
| Gewicht eintragen | `/weight/new` | `2093:2` (Dark `4044:500`, OLED `4056:4276`); Validierungsfehler `4045:232`; Speicherfehler `4053:821` | `WeightFormScreen` (`weight_form_screen.dart`) |
| Messung bearbeiten, löschen, rückgängig | `/weight/:id` | `4053:314`; Löschen bestätigen `4053:422`; nach Löschen mit Undo `4053:541` | `WeightFormScreen(entryId)` |
| Dashboard-Karte Gewicht | Karte `weight` | Gewichtskarte im Home-Frame `2013:2` | `WeightDashboardCard` (`weight_dashboard_card.dart`) |
| Schritte, Übersicht „Meine Schritte“ | `/steps` | `4026:2` (Dark `4056:2056`, OLED `4056:3863`) | `StepsOverviewScreen` (`steps/presentation/steps_overview_screen.dart`) |
| Schritte eintragen | `/steps/new`, mit Datum `/steps/new?date=YYYY-MM-DD` | `4040:141` (200 % Schrift `4057:39`) | `StepsFormScreen` (`steps_form_screen.dart`) |
| Dashboard-Karte Schritte | Karte `steps` | Schrittekarte im Home-Frame `2013:2` | `StepsDashboardCard` (`steps_dashboard_card.dart`) |

`BodyModule` heißt „Gewicht & Körper“ („Gewicht, Zielgewicht, Schritte“) und registriert die Routen in der Reihenfolge `/weight`, `/weight/new`, `/weight/all`, `/weight/:id`, `/steps`, `/steps/new`: statische Pfade vor dem Muster `:id`, damit `/weight/new` und `/weight/all` nie als Kennung gelesen werden. Plus-Menü: `weight` (Position 0, Route `/weight/new`) und `steps` (Position 3, Route `/steps/new`). Dashboard-Karten: `steps` (Rang 0) und `weight` (Rang 2). Eine ungültige Kennung in `/weight/:id` zeigt die Seite „Nicht gefunden“ (Guard der Shell); eine gültige, aber unbekannte Kennung zeigt „Eintrag nicht gefunden“ mit „Zur Übersicht“.

## 2. Verhalten

### 2.1 Gewicht

**Übersicht „Mein Gewicht“.** Von oben nach unten:

1. Karte „Aktuell“: der aktuelle Wert (die zeitlich letzte Messung, bei gleicher Zeit nach Kennung), dazu „Heute, 08:32“, eine neutrale Plakette mit dem Wochenvergleich („↓ −0,3 kg seit letzter Woche“) oder „Noch kein Wochenvergleich“. Gibt es ein Start- und ein Zielgewicht im Profil, folgen ein Fortschrittsbalken mit „Start“, dem Rest („Noch 3,5 kg“) oder „Ziel erreicht“ und dem Ziel; sonst die Zeile „Zielgewicht festlegen“ (führt zu `/profile/edit`).
2. „Verlauf“: Liniendiagramm mit einem Punkt je Tag (die letzte Messung des Tages), Zeitraum „7 T“, „30 T“ oder „3 M“ (90 Tage), Zusammenfassungssatz und Tabelle derselben Werte. Der Zeitraum ist zunächst 7 Tage, bleibt während der Laufzeit der App gewählt und ist nach einem Prozess-Neustart wieder 7 Tage.
3. „Letzte Einträge“: fünf Zeilen mit relativem Datum, Uhrzeit, Bedingungen, Wert und Veränderung zur vorherigen Messung; „Alle anzeigen“ (zu `/weight/all`) erscheint nur bei mehr als fünf Einträgen. Die zeitlich erste Messung trägt „Startgewicht“, wenn ihr Wert dem ausdrücklichen Startgewicht des Profils entspricht (in der Übersicht nur, solange sie unter den fünf letzten steht, in „Alle Messungen“ immer).
4. Rechnerischer BMI als Karte („Rein rechnerischer Wert aus Gewicht und Größe, ohne Bewertung und ohne Aussage über deine Gesundheit.“) oder, ohne Größe und Alter im Profil, die Zeile „BMI anzeigen“ mit dem Weg zum Profil.

Die Aktion „Gewicht eintragen“ ist unten angeheftet, sobald es Einträge gibt; ohne Eintrag zeigt die Seite „Noch keine Messung“ mit eigener Aktion. Laden zeigt „Wird geladen …“, ein Lesefehler `ErrorState` mit „Erneut versuchen“.

**Alle Messungen.** Alle aktiven Messungen, neueste zuerst, nach Monat gruppiert („Oktober 2026“). Die Zeilen werden lazy gebaut, Tausende Einträge scrollen ohne Blockade. Die Fußzeile erklärt, dass ein Tippen auf einen Eintrag das Bearbeiten und Löschen öffnet. Leer- und Fehlerzustand scrollen auf kleinen Bildschirmen.

**Formular „Gewicht eintragen“ und „Eintrag bearbeiten“.** Der große Wert steht zwischen Minus und Plus (0,1 kg je Schritt, Start beim getippten Wert oder beim Vorschlag) und ist direkt tippbar (Ziffern, Komma, Punkt). Ist das Feld leer und gibt es eine frühere Messung, bietet „Letzten Wert übernehmen (71,5 kg)“ sie als unbestätigten Vorschlag an; sie wird nur gespeichert, nachdem sie übernommen oder mit Plus und Minus in das Feld geschrieben wurde. Bei gültigem Wert zeigt eine neutrale Plakette die Veränderung „seit dem letzten Eintrag“ (gegen die letzte frühere Messung, beim Bearbeiten ohne den bearbeiteten Eintrag). Die Zeile „Messzeitpunkt“ öffnet den Datumswähler „Messdatum“ und danach den Zeitwähler „Messzeit“. Unter „Messbedingungen“ stehen drei Zeilen mit Häkchenfeld (Mehrfachauswahl): „Vor dem Klo“, „Nach dem Trinken“, „Nach dem Essen“. „Notiz“ ist optional (bis 500 Zeichen). Eine Hinweiskarte „Tipp für genaue Werte“ („Am besten morgens, nüchtern und nach dem Klo wiegen.“) schließt den Inhalt ab; beim Bearbeiten folgt „Eintrag löschen“.

- „Eintrag speichern“ (neu) oder „Änderungen speichern“ (bearbeiten) ist erst aktiv, wenn ein Wert getippt und kein Feldfehler sichtbar ist; beim Bearbeiten außerdem erst nach einer Änderung. Ein zweiter Tipp während des Speicherns wird ignoriert.
- Nach dem Commit meldet die Snackbar „Gewicht gespeichert“ oder „Gewicht aktualisiert“ mit „Rückgängig“ (8 s), die Seite schließt sich. Fehlgeschlagene Speicherungen lassen die Seite offen, behalten alle Eingaben und bieten „Erneut“ mit derselben Befehls-ID an („Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.“). Ein Versionskonflikt (die Messung wurde inzwischen geändert) zeigt seine Meldung ohne Wiederholen und überschreibt nichts.
- Feldfehler stehen direkt am Feld (Symbol und Text, Rand in der Fehlerfarbe) und verschwinden beim Ändern des Feldes; das erste ungültige Feld (Gewicht, sonst Notiz) bekommt den Fokus.
- Gibt es zu genau dieser Messzeit schon einen aktiven Eintrag, erscheint „Für diesen Messzeitpunkt gibt es schon einen Eintrag.“ mit „Bestehenden Eintrag bearbeiten“; es wird kein zweiter angelegt. Ein anderer Zeitpunkt am selben Tag ist erlaubt.
- Beim Bearbeiten öffnet „Eintrag löschen“ das Bestätigungs-Sheet „Messung vom 3. Okt. löschen?“ („Du kannst es direkt danach rückgängig machen.“); danach meldet die Snackbar „Messung gelöscht“ mit „Rückgängig“, das den Eintrag mit derselben Kennung zurückholt.
- Ein Formular mit Eingaben fragt vor dem Verlassen „Änderungen verwerfen?“ (Weiter bearbeiten oder Verwerfen), auch bei Android-Zurück.

**Dashboard-Karte.** Ohne Messung: „–“, „Noch keine Messung“ und die Aktion „Gewicht eintragen“. Mit einer Messung heute oder in den sechs Tagen davor: Wert in kg, eine kleine Kurve dieser sieben Tage und der Wochenvergleich („↓ −0,3 kg in 7 Tagen“ oder „Noch kein Wochenvergleich“). Liegt die letzte Messung sieben Tage oder länger zurück, steht „Zuletzt So., 20. Sep.“ ohne Kurve und ohne Vergleich. Die Karte folgt nicht dem Zeitraum der Übersicht.

**Fachregeln.**

- Eingabe in Kilogramm mit Komma oder Punkt und höchstens einer Nachkommastelle; `71`, `71,5` und `71.5` sind gültig, `71,55` ist ein Korrekturhinweis (nie stilles Runden); Tausendertrennzeichen, Exponenten, Vorzeichen, `NaN` und Unendlich sind ungültig. Das Eingabefeld lässt nur Ziffern, Komma und Punkt zu (höchstens acht Zeichen). Bereich 20,0 bis 350,0 kg einschließlich der Grenzen. Gespeichert wird in ganzen Gramm (71,5 kg sind 71500).
- Die Messzeit darf nicht in der Zukunft und nicht vor dem 01.01.2000 liegen. Ohne Änderung der Zeit gilt beim Speichern eines neuen Eintrags der Zeitpunkt des Speicherns. Eine Uhrzeit in der Lücke der Zeitumstellung wird nicht verschoben, sondern mit „Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. Bitte wähle HH:MM Uhr oder später.“ erklärt.
- Geschäftsdatum und Zone werden beim Anlegen eingefroren. Eine Änderung der Notiz oder der Bedingungen verschiebt nie das Datum; nur eine geänderte Messzeit friert Datum und Zone neu ein.
- Je exakter Messzeit gibt es höchstens eine aktive Messung (auch als partieller Unique-Index der Datenbank).
- Veränderung zur vorherigen Messung: zeitlich geordnet; die erste Messung hat keinen Vorgänger und zeigt keine Veränderung.
- Wochenvergleich: aktuelles Gewicht minus die letzte Messung, die am oder vor „heute minus 7 Tage“ liegt; ohne diesen Anker „Noch kein Wochenvergleich“. Das gilt auch, wenn die aktuelle Messung selbst der Anker wäre (Abschnitt 4).
- Diagrammpunkte: je Tag die letzte Messung, aufsteigend nach Datum, gerade Linien, keine Glättung, keine Prognose, nie eine künstliche Null für Tage ohne Messung; bei einem einzigen Punkt nur Marker und Wert.
- Ziel: Fortschritt `(aktuell − Start) / (Ziel − Start)` auf 0 bis 1 begrenzt, für Ab- und Zunahme; ist Start gleich Ziel, ist der Fortschritt 1 nur, wenn das aktuelle Gewicht dem Ziel entspricht. Der Rest ist der Betrag der Differenz und 0, sobald das Ziel in seiner Richtung erreicht oder überschritten ist („Ziel erreicht“, nie ein negativer Rest). Start- und Zielgewicht sind ausdrückliche Profilwerte; es entsteht keine Messung aus ihnen.
- BMI nur mit Größe (100 bis 250 cm), Alter (18 bis 120 Jahre) und aktueller Messung, in ganzen Zahlen mit einer Nachkommastelle halb aufgerundet, ohne Bewertung.
- XP: Ein Tag mit mindestens einer berechtigten Messung vergibt einmal 10 XP; eine Abnahme vergibt nichts. Das Tagesziel „Gewicht erfassen“ zählt für den Tagesring. Die Berechtigung wird beim Anlegen eingefroren.
- Undo ist ein neuer Befehl mit eigener Befehls-ID und Prüfung der Zeilenversion: Das Anlegen wird durch Soft-Delete rückgängig gemacht, eine Änderung durch das Zurücksetzen der Werte, ein Löschen durch das Wiederherstellen derselben Kennung. Wurde der Eintrag inzwischen geändert, entsteht ein Konflikt statt eines stillen Überschreibens.

### 2.2 Schritte

**Übersicht „Meine Schritte“.** Karte „Heute“ mit dem heutigen Tageswert (oder „–“ und „Heute noch nicht eingetragen“), dem Tagesziel („/ 10.000“), der Plakette „Noch 2.550“ oder „Ziel erreicht“, dem Fortschrittsbalken, „75 % vom Tagesziel“ (ohne anwendbares Ziel „Kein Tagesziel aktiv“) und dem Hinweis „Quelle: Manuell“. Darunter „Verlauf“ (Säulendiagramm, Zeitraum „7 T“, „30 T“ oder „3 M“, Zusammenfassungssatz, Tabelle mit den Spalten „Schritte“ und „Ziel“ für jeden Tag des Zeitraums, auch „Nicht erfasst“), drei Kennzahlen („Ø pro Tag“, „Bester Tag (Sa)“ beziehungsweise mit Datum bei längeren Zeiträumen, „Ziel erreicht n / N“ oder „Kein Tagesziel“), „Eingetragene Tage“ (die letzten zehn erfassten Tage des gewählten Zeitraums; ein Tipp öffnet das Formular für diesen Tag) und der Hinweis „Einmal am Tag eintragen“. Die Aktion „Schritte eintragen“ ist unten angeheftet.

**Formular „Schritte eintragen“.** Ein Datumswähler mit den Tasten „Einen Tag zurück“ und „Einen Tag weiter“ (die Zukunft ist nicht erreichbar) und einem Tipp auf das Datum für den Datumswähler; das Feld „Schritte gesamt“ (0 bis 100.000, beim Tippen mit Punkten gegliedert: `8120` wird `8.120`); der Link `?date=` öffnet einen früheren Tag zur Korrektur.

- Gibt es für den Tag schon einen Wert, sagt eine Hinweiskarte „Für heute sind schon 7.450 eingetragen“ und „Beim Speichern wird der Tageswert ersetzt, nicht addiert.“, der Button heißt „Tageswert ersetzen“ (sonst „Schritte speichern“) und „Tageswert löschen“ erscheint.
- Nach dem Commit meldet die Snackbar „Schritte gespeichert“, „Schritte aktualisiert“ oder „Tageswert gelöscht“ mit „Rückgängig“ (8 s). Ein Fehler behält die Eingabe und bietet „Erneut“ an. Das Verwerfen ungespeicherter Eingaben wird erfragt.

**Dashboard-Karte.** Vor dem ersten Eintrag des Tages „–“, „Heute noch nicht eingetragen“ und die Aktion „Schritte eintragen“. Danach der Tageswert mit Ziel, Fortschrittsbalken und „75 % erreicht“, „Ziel erreicht“ oder „Kein Tagesziel aktiv“; ein Tipp öffnet die Übersicht.

**Fachregeln.**

- Ganze Zahlen von 0 bis 100.000 einschließlich der Grenzen; Punkte als Tausendertrenner (`10.000`) sind erlaubt, Dezimalstellen, Vorzeichen, Exponenten und Leerzeichen nicht. Das Datum darf nicht in der Zukunft und nicht vor dem 01.01.2000 liegen.
- Es gibt je Datum einen aktiven Wert. Erneutes Speichern ersetzt ihn: 7.450 und danach 8.000 ergeben 8.000, nie 15.450.
- Eine erfasste 0 ist ein Wert und etwas anderes als „Nicht erfasst“ (kein Datensatz).
- Das Tagesziel kommt aus dem Tages-Snapshot des jeweiligen Tages; „erreicht“ ändert sich rückwirkend nie, wenn ein Ziel später geändert wird (Zieländerungen gelten ab morgen). Der Prozentwert ist der echte Wert, halb aufgerundet und auch über 100 %, ist aber nie 100, solange das Ziel nicht erreicht ist (9.950 von 10.000 zeigt 99). Der Balken ist bei 100 % gedeckelt.
- Kennzahlen eines Zeitraums: erfasste Tage; Durchschnitt nur über die erfassten Tage (halb aufgerundet), fehlende Tage zählen weder als 0 noch im Durchschnitt; bester Tag (bei Gleichstand der jüngste); „Ziel erreicht“ als Zahl der erfassten Tage, an denen das damals geltende Ziel erreicht war, gegen die Tage des Zeitraums.
- XP: Einmal je Tag 10 XP, wenn die beim ersten Erreichen eingefrorene Schwelle erreicht ist. Spätere Korrekturen behalten die Entscheidung, die Vergabe gilt nur, solange der Wert die eingefrorene Schwelle noch erreicht; ein Wert, der bei ausgeschalteter Gamification erreicht wurde, wird nie nachträglich vergütet.
- Löschen ist ein Soft-Delete („Nicht erfasst“, die XP werden zurückgenommen); Undo stellt die Zeile wieder her, sofern der Tag nicht inzwischen neu gefüllt wurde.

## 3. Abweichungen vom Figma-Entwurf und Gründe

| Entwurf | Umsetzung | Grund |
|---|---|---|
| Hinweistext zum Gewicht mit Obergrenze 400 kg | 20,0 bis 350,0 kg | Spezifikation; die Abnahmefälle weisen 19,9 und 350,1 ab |
| Veränderungen grün oder rot | Neutrale Plakette mit Pfeil, Vorzeichen und echtem Minuszeichen; grün nur bei „Ziel erreicht“ | Eine Zu- oder Abnahme ist weder gut noch schlecht (Spezifikation 6.2); Farbe trägt nie allein eine Aussage |
| Undo-Hinweis von 5 s in der Komponente | 8 Sekunden | Vorgabe des Auftrags, siehe [design-handoff.md](../design-handoff.md) Abschnitt 8.4 |
| Messbedingungen als Auswahl-Chips | Zeilen mit Titel, Erklärtext und Häkchenfeld, `EntryListTile.check` mit abgerundetem Quadrat wie im Frame `2093:2` | Mehrfachauswahl mit Zustand als Text und Semantik und mit 48 px Tippfläche |
| Kein Notizfeld | Optionales Feld „Notiz“ bis 500 Zeichen | Datenmodell und Anforderung |
| Dashboard-Karte mit Kurve und Wochenvergleich | Ohne Messung heute oder in den sechs Tagen davor „Zuletzt <Datum>“ ohne Kurve und Vergleich | Ehrlicher Zustand; aus einer leeren Punktliste lässt sich keine Kurve zeichnen |
| Beispielzahlen (71,5 kg, Start 74,0 kg, Ziel 68,0 kg) | Nirgends angezeigt; alles aus der Datenbank | Keine erfundenen Werte |
| Zusatzwerte zu den Schritten (Kilometer, Kalorien, Aktivminuten) | Entfallen | Keine Datenquelle ([design-handoff.md](../design-handoff.md) Abschnitt 6) |

## 4. Konflikte und Entscheidungen

| Konflikt oder Frage | Entscheidung |
|---|---|
| Wochenvergleich: Die Spezifikation setzt als Anker die letzte Messung am oder vor „heute minus 7 Tage“. Wurde in den letzten sieben Tagen nichts gemessen, wäre die aktuelle Messung selbst der Anker und „0,0 kg in 7 Tagen“ behauptete ein unverändertes Gewicht | Entscheidung der Koordination: Eine Messung wird nie mit sich selbst verglichen, es steht „Noch kein Wochenvergleich“. Das ist eine Auslegung des Sonderfalls. Sonst bleibt es beim Wortlaut der Spezifikation, der Anker kann also auch länger als sieben Tage zurückliegen |
| Hinweistext 400 kg gegen Spezifikation 350 kg | Spezifikation |
| Undo 5 s in der Komponente gegen 8 s im Auftrag | 8 s |
| Der Zeitpunkt eines neuen Eintrags mit unberührter Zeit ist „jetzt“ beim Speichern. Würde er bei einer Wiederholung nach einem Fehler neu gelesen, wäre der Inhalt ein anderer und die Befehls-ID neu | `AttemptClock` friert den Zeitpunkt des ersten Versuchs für denselben Inhalt ein; geänderter Inhalt liest ein neues „jetzt“. Das gilt auch im Workout-Formular. Eine Wiederholung ist damit nie ein zweiter Datensatz |
| „nüchtern“ als eigene Bedingung oder abgeleitet | Nur ein abgeleiteter Kurztext: erscheint, wenn weder „Nach dem Essen“ noch „Nach dem Trinken“ gesetzt ist; „Vor dem Klo“ wird getrennt genannt. Die App macht keine Aussage über die Messqualität |
| Der gerundete Schritte-Prozentwert kann bei knapp unter dem Ziel „100“ zeigen | Höchstens 99, solange das Ziel nicht erreicht ist; über 100 bleibt der echte Wert sichtbar |
| Schritte-Kennzahl „Durchschnitt über erfasste Tage“ gegen eine Summe | Durchschnitt über die erfassten Tage ohne Null-Auffüllung, wie in der [Analyse](analysis.md) |
| Eine Uhrzeit in der Lücke der Zeitumstellung | Wird nicht stillschweigend verschoben; die Eingabe bleibt mit einem Hinweis, welche Zeit gilt |

## 5. Barrierefreiheit

- Tippflächen mindestens 48 x 48 und deutsche Beschriftungen an jeder Schaltfläche (`androidTapTargetGuideline`, `labeledTapTargetGuideline`, geprüft für Übersicht und Formular des Gewichts sowie Übersicht, Formular und Karte der Schritte).
- Gewichtsfeld: Beschriftung „Gewicht in Kilogramm“, Plus und Minus heißen „um 0,1 Kilogramm erhöhen“ und „um 0,1 Kilogramm verringern“. Der große Zahlenwert skaliert bis 130 % und schrumpft darüber auf die verfügbare Breite; alles andere skaliert ohne Grenze.
- Fehler stehen mit Symbol und Text am Feld (Live-Region) und der Rand wechselt in die Fehlerfarbe: Farbe ist nie der einzige Hinweis. Nach einem abgelehnten Speichern bekommt das erste ungültige Feld des Gewichtsformulars den Fokus, damit der Screenreader Beschriftung und Hinweis zusammen liest.
- Das Diagramm ist für Screenreader ausgeblendet; der Zusammenfassungssatz („2 Messtage in 7 Tagen. Zuerst 71,8 kg, zuletzt 71,5 kg (−0,3 kg).“) und die Tabelle tragen die Bedeutung. Veränderungen werden in Worten gelesen („minus 0,3 Kilogramm“, „plus“, „unverändert“); Pfeil und Minuszeichen sind zusätzlich sichtbar.
- Fortschrittsbalken tragen ihren Wert („Fortschritt zum Zielgewicht: 70 Prozent“, „Zielgewicht erreicht“, „Fortschritt zum Tagesziel: 75 Prozent“). Zeilen lesen Datum, Bedingungen, Wert, Veränderung und „Tippen zum Bearbeiten“. Die Häkchenzeilen sind Kontrollkästchen mit Zustand (`checked`) und tragen ihre Erklärung im Label.
- Das Datum der Schritte hat die Tasten „Einen Tag zurück“ und „Einen Tag weiter“ und eine Taste „Datum: Heute, 3. Oktober. Tippen zum Ändern“; die Ersetzen-Hinweiskarte ist eine Live-Region. Alle Aktionen haben sichtbare Schaltflächen, es gibt keine reine Geste.
- Text bis 200 %: Inhalt scrollt, die angeheftete Aktion bleibt über der Tastatur erreichbar, geprüft bei 320, 360, 393 und 430 px mit Skala 1,0 und 2,0; im Gewichtsformular zusätzlich bei 360 px Breite, Skala 2,0 und 300 px Tastaturhöhe.
- Bewegung nur über `AppMotion`; die Diagramme folgen reduzierter Bewegung.

## 6. Tests

Befehle: `flutter test test/features/body` (239 Tests, grün), davon `flutter test test/features/body/steps` (79) für die Schritte und 160 für das Gewicht (`application`, `data`, `domain`, `presentation`). Echte In-Memory-Datenbank, feste Uhr 2026-10-03 Europe/Berlin, nur synthetische Gewichte und Schritte. `dart run tool/at_coverage.dart` ordnet die Tests den Abnahmefällen AT05 bis AT09, AT12, AT15, AT23 bis AT27, AT33 und AT34 zu.

| Datei in `test/features/body/` | Tests | Schwerpunkt (Abnahme-IDs) |
|---|---:|---|
| `domain/weight_input_test.dart` | 10 | Parser (Komma und Punkt, Grenzen beidseitig, zwei Nachkommastellen, Format), Plus und Minus (AT05) |
| `domain/weight_calculations_test.dart` | 25 | aktuelles Gewicht, Veränderungen, Vorschau, Wochenvergleich (Grenze −7 und −6 Tage, nie mit sich selbst), Diagrammpunkte ohne Nullen, Zielfortschritt, BMI (AT08, AT09) |
| `domain/weight_card_test.dart` | 4 | Modell der Dashboard-Karte (AT08) |
| `application/weight_form_controller_test.dart` | 24 | neuer Eintrag, Messzeit und Lücke der Zeitumstellung, gleiche Zeit, Doppeltipp, Wiederholung mit derselben ID und eingefrorenem „jetzt“, Bearbeiten, Versionskonflikt, Löschen und Undo (AT05, AT07, AT12, AT27) |
| `application/weight_overview_test.dart` | 6 | Übersichtsmodell: leer, Zeitraum, Ziel und BMI nur mit Voraussetzungen, neuer Tag, gelöschte Messung |
| `data/weight_repository_test.dart` | 34 | Anlegen mit Bedingungen, Grenzen, gleiche Messzeit, Bearbeiten (Version, Konflikt, eingefrorenes Datum), Löschen und Undo mit derselben Kennung, Atomarität, Lesen (AT05, AT06, AT07, AT12, AT23, AT26, AT27) |
| `presentation/weight_labels_test.dart` | 11 | Bedingungstexte, neutrale Veränderungstexte, Ziel- und Zeitraumtexte, Textalternative des Diagramms (AT06, AT08, AT09) |
| `presentation/weight_dashboard_card_test.dart` | 4 | leer, aktuelle Messung, Messung älter als eine Woche ohne Kurve, Navigation |
| `presentation/weight_screens_test.dart` | 42 | Formular (Eingaben, Feldfehler mit Fokus, Doppelanlage, Verwerfen), Bearbeiten und Löschen mit Undo, Übersicht (leer, ein Punkt, mehrere, Ziele), Alle Messungen, Layout, Tastatur, Tippflächen, Semantik (AT05 bis AT09, AT27, AT33, AT34) |
| `steps/steps_input_test.dart` | 8 | Parser, Datumsregeln, Fortschritt (nie 100 vor dem Ziel) |
| `steps/steps_stats_test.dart` | 14 | Kennzahlen und Texte, erfasste 0, bester Tag, Ziel je Tag (AT15) |
| `steps/steps_repository_test.dart` | 20 | Ersetzen statt Addieren, erfasste 0, XP mit eingefrorener Schwelle, Löschen und Undo, Atomarität (AT15, AT24, AT26, AT27) |
| `steps/steps_application_test.dart` | 9 | Heute-Karte und Verlauf live, Formular-Controller |
| `steps/steps_screens_test.dart` | 28 | Formular, Übersicht, Karte, Modulrouten, Layout 320 bis 430 px, Semantik (AT15, AT24, AT26, AT27, AT33, AT34) |

Sichtvergleich: Das gerenderte Gewichtsformular wurde mit dem Frame `2093:2` verglichen (Anlass der quadratischen Häkchenfelder); einen automatisierten Bildvergleich gegen Figma gibt es nicht.

## 7. Offene Punkte

- Auf einem Gerät nicht geprüft: TalkBack (Beschriftungen, Lesereihenfolge, Ansage der Fehlermeldungen), echte Systemschrift bis 200 %, echte Tastatur, die Material-Dialoge für Datum und Zeit und die Darstellung der Diagramme. Die Host-Tests prüfen Semantics, Tippflächen und Überlauf.
- Das Schritteformular setzt nach einem abgelehnten Speichern den Fokus nicht auf das Feld; die Meldung steht als Live-Region am Feld. Im Gewichtsformular (Gewicht, Notiz) tut es der Fokussprung; beim Schritteformular ist das nicht umgesetzt.
- Der Anker des Wochenvergleichs kann beliebig weit zurückliegen (Wortlaut der Spezifikation), die Beschriftung „seit letzter Woche“ beziehungsweise „in 7 Tagen“ sagt das nicht.
- Der gewählte Diagrammzeitraum von Gewicht und Schritten wird nicht über einen Prozess-Neustart gespeichert (immer 7 Tage).
- Die System-Datums- und Zeitwähler (Material-Dialoge) folgen bei reduzierter Bewegung nur dem Systemflag, nicht dem Schalter der App.
- Ein einheitlicher Wortlaut des Verwerfen-Sheets über alle Formulare ist offen (siehe [design-handoff.md](../design-handoff.md) Abschnitt 9).
