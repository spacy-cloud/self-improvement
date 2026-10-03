# Onboarding (BS-57)

Fünf Screens beim ersten Start: Willkommen und vier nummerierte Schritte (Ziele, Module, Körperdaten, Tagesziele). Alles ist freiwillig und überspringbar. Es werden keine Beispielperson, keine Messwerte und keine Konten gezeigt oder gespeichert. Die App läuft dabei vollständig offline.

## 1. Screens und Figma-Nodes

Alle fünf Screens liegen in **einem** Widget `OnboardingScreen` (`lib/features/onboarding/presentation/onboarding_screen.dart`), das der Router unter `/onboarding` registriert. Die Schritte werden intern gewechselt (kurzes Überblenden mit leichtem Schieben, 200 ms, bei reduzierter Bewegung sofort); es gibt keine weiteren globalen Routen. Nach Abschluss oder Überspringen geht die App per `go_router` zu `/` (Dashboard). Der Austrittspunkt ist über `onboardingExitProvider` ersetzbar (Tests).

| Screen | Node (Light) | Inhalt |
|---|---|---|
| Willkommen | `4028:2` | App-Name, Untertitel, drei Merkkarten, „Los geht’s“, „Überspringen“ |
| Ziele („Schritt 1 von 4“) | `4028:59` | fünf freiwillige Mehrfachpräferenzen, keine Vorauswahl |
| Module („Schritt 2 von 4“) | `4036:278` | fünf Modulkarten mit Schalter, alle zunächst an, auch alle aus erlaubt |
| Körperdaten („Schritt 3 von 4“) | `4028:137` | Name, Alter, Größe, Startgewicht, alles optional |
| Tagesziele („Schritt 4 von 4“) | `4028:246` | vorgeschlagene Ziele mit Plus/Minus bzw. Schalter, Hinweis zu Erinnerungen |

Dark und OLED kommen aus den Theme-Tokens (kein eigener Frame).

## 2. Ablauf und Speicherung

- Alle Eingaben liegen nur im Arbeitsspeicher (`OnboardingController`, Riverpod). **Vor dem Abschluss wird nichts geschrieben.** Zurückgehen behält jede Eingabe; die Textfelder spiegeln den Controller-Zustand und werden beim Wiederöffnen eines Schritts daraus befüllt.
- „Fertig – los geht’s“ und „Überspringen“ führen **genau einen** Befehl aus: `OnboardingRepository.complete` (eine Transaktion: Profil, Modulhistorie, Zielversionen ab heute, Standard-Dashboardkarten). `onboarding_completed` wird erst mit diesem Commit wahr.
- Überspringen speichert die Standardwerte (`OnboardingDraft.skipped()`): alle fünf Module, vorgeschlagene Ziele, kein Name, keine Körperdaten, keine Zielpräferenzen. Vorhandene Eingaben werden verworfen; deshalb fragt die App vorher nach („Einrichtung überspringen?“, „Weiter einrichten“), sobald etwas eingegeben wurde. Auf dem Willkommen-Screen ohne Eingabe wird sofort übersprungen.
- Command-ID: gleiche Inhalte (Wiederholen, Doppeltipp) verwenden dieselbe ID (`SubmissionTracker`), geänderte Inhalte eine neue. Ein zweiter Tipp während des Speicherns wird ignoriert (Sperre im Controller, Button zeigt „Wird gespeichert …“).
- Zielpräferenzen werden mit den stabilen IDs `lose_weight`, `get_fitter`, `move_more`, `live_healthier`, `build_habits` in Anzeigereihenfolge als `motivation_goals` gespeichert. Daraus wird nichts berechnet oder empfohlen.
- Körperwerte (Name, Größe, Alter, Startgewicht) sind reine Profildaten. Es entsteht **keine Gewichtsmessung**, kein BMI und kein Zielgewicht.
- Erinnerungen bleiben aus. Der Schritt „Tagesziele“ zeigt nur einen Hinweis; es gibt keinen Schalter und keine Berechtigungsabfrage des Systems.
- Tagesziele: Schritte (100 bis 100000, Schritt 500, Start 10.000), Wasser (250 bis 10000 ml, Schritt 250 ml, Start 2500 ml, Anzeige in Litern), Fokus (5 bis 180 Min., Schritt 5, Start 25), Workouts (1 bis 14 pro Woche, Schritt 1, Start 3) mit Plus/Minus. Aufgaben („mindestens 1 pro Tag“) und Gewichtseintrag („1 pro Tag“) haben den festen Zielwert 1 und sind je ein Schalter, der Start ist an. Jedes Ergebnis besteht `GoalType.validateTarget`; an den Grenzen ist der jeweilige Button deaktiviert. Es werden nur Ziele der gewählten Module angezeigt; bei keinem Modul erklärt ein Hinweis, dass es dann keine Tagesziele gibt.

## 3. Fehlerverhalten

- Schlägt der Befehl fehl (zum Beispiel Datenbankfehler), wird er vollständig zurückgerollt, das Onboarding bleibt offen, alle Eingaben bleiben, und über dem Button erscheint ein dauerhafter Hinweis („Die Einrichtung konnte nicht gespeichert werden. Deine Eingaben bleiben erhalten.“) mit „Erneut versuchen“ (gleiche Command-ID, Live-Region). Eine Änderung danach macht den alten Versuch hinfällig.
- Ungültige Körperwerte (Alter 18 bis 120, Größe 100 bis 250 cm, Gewicht 20,0 bis 350,0 kg in 0,1-Schritten, Name höchstens 40 Zeichen) halten „Weiter“ am Körperdaten-Schritt an. Die Fehlermeldung steht am Feld (Symbol und Text, Live-Region), der Fokus springt auf das erste fehlerhafte Feld, die Eingabe bleibt; die Meldung verschwindet beim Ändern des Feldes.
- Ist das Profil schon abgeschlossen (zum Beispiel veralteter Screen), verlässt der Flow das Onboarding, ohne etwas zu überschreiben.
- Erfolgsmeldungen per Snackbar gibt es bewusst nicht: Der Wechsel zum Dashboard ist die Rückmeldung.

## 4. Android-Zurück

1. Schritt 1 bis 4: zurück zum vorherigen Schritt, Entwürfe bleiben.
2. Willkommen-Screen ohne Eingaben: Android-Konvention für einen Wurzel-Screen, das System beendet die App ohne Rückfrage.
3. Willkommen-Screen mit Eingaben (Nutzer ist über Zurück zum Anfang gegangen): Rückfrage „Einrichtung abbrechen?“ mit „App schließen“ und „Weiter einrichten“, weil ungespeicherte Eingaben verloren gingen.
4. Während des Speicherns wirkt Zurück nicht. Die Rückfragen sind Modal-Sheets und schließen mit Zurück.

Entwürfe überleben das Zurückgehen, aber nicht das Beenden des Prozesses. Das ist gewollt: Vor dem Abschluss wird nichts persistiert, ein Neustart beginnt wieder beim Willkommen-Screen.

## 5. Abweichungen von Figma

| Figma | Umsetzung | Grund |
|---|---|---|
| „Ich habe schon ein Konto“ | entfällt, an dieser Stelle „Überspringen“ | keine Konten in V1; Überspringen ist Pflicht (Ticket) |
| Ziele „Abnehmen“ und „Fitter werden“ vorgewählt | keine Vorauswahl | Ticket und Spezifikation |
| „Trinken, Schlaf und Ernährung“ | „Trinken und Ernährung“ | Schlaf entfällt in V1 |
| Körperdaten mit Beispielwerten (22 Jahre, 180 cm, 74,0 kg, Ziel 68,0 kg) | leere Felder mit Platzhalter „optional“ | keine Beispielperson, keine Daten ohne Eingabe |
| Zielgewicht und grüne Zeile „6,0 kg bis zu deinem Ziel – gut machbar!“ | entfallen | der Entwurf kennt kein Zielgewicht im Onboarding; Zielgewicht wird später im Gewichtsbereich gesetzt und bestätigt; keine berechnete Bewertung |
| „Aktuelles Gewicht“ | „Startgewicht“ | gespeichert wird der Profil-Startwert, keine Messung |
| kein Namensfeld | Zeile „Name“ (optional, 1 bis 40 Zeichen) über den Zahlenfeldern | Spezifikation 3: Name optional, leer heißt „Mein Profil“ |
| Untertitel „…damit wir deine Ziele … richtig berechnen können“ | „Alle Angaben sind freiwillig …“ | aus den Körperdaten wird nichts berechnet |
| Hinweis „Deine Daten sind nur für dich sichtbar …“ | „Deine Angaben bleiben auf diesem Gerät. Sie werden nicht als Messung eingetragen …“ | ohne Konto präziser, benennt die Messung |
| Tagesziele: Schritte, Wasser, Workouts | zusätzlich Fokus, Aufgaben, Gewichtseintrag (sechs Ziele) | Ticket verlangt alle sechs vorgeschlagenen Ziele sichtbar |
| „Passende Startwerte“ | „Startwerte“ | Planungsstandard, keine persönliche Empfehlung (Spezifikation 3) |
| Schalter „Erinnerungen aktivieren“ (an) | Hinweis „Erinnerungen sind ausgeschaltet …“ | Erinnerungen starten aus, keine frühe Berechtigungsabfrage |
| Textfelder als Zeilen mit Wert rechts | gleiche Zeilen, bei großer Schrift oder schmaler Breite Beschriftung über dem Wert | nichts darf abgeschnitten werden |
| Hero-Kreis und App-Zeichen als Figma-Assets | gezeichnet mit Tokens (`CustomPaint`, Verlauf) | keine temporären Figma-URLs zur Laufzeit |
| Seitenpunkte auf dem Willkommen-Screen (4) | dekorativ übernommen, ohne Semantik | Gestaltung; „Schritt N von 4“ trägt die Information |

Statusleiste, Dynamic Island und Home-Indikator sind nur Figma-Rahmen und werden nicht gebaut.

## 6. Konflikte zwischen Vorgaben und Entscheidung

| Konflikt | Entscheidung |
|---|---|
| Spezifikation 3: dreiseitige Einführung; Handoff und Ticket: fünf Screens | fünf Screens (Aufgabentext und Handoff vor Spezifikation) |
| Handoff-Route `/onboarding/*`; Router-Vertrag: eine Route `/onboarding` | eine Route, Schritte intern |
| Figma: Zielgewicht im Onboarding; Spezifikation 6.2: Zielgewicht optional, später mit Bestätigung | kein Zielgewicht im Onboarding (Spezifikation) |
| Figma-Ziele nur drei; Ticket: sechs sichtbar | sechs Ziele (Ticket); Schalter statt Stepper für die festen Ziele 1 |

## 7. Barrierefreiheit

- Tap-Ziele mindestens 48 x 48 (Zurück, Überspringen, Plus/Minus, Karten, Schalter, Felder); geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` bei 393 px (Schrift 1,0) und 320 px (Schrift 2,0).
- Jeder Schritt hat eine Überschrift mit Live-Region („Schritt 2 von 4: Was willst du nutzen?“); der Fortschrittsbalken ist dekorativ und ohne Semantik.
- Zielkarten sind Kontrollkästchen („ausgewählt“ / „nicht ausgewählt“), Modul- und Zielschalter sind Umschalter („ein“ / „aus“); Textfelder tragen deutsche Beschriftungen mit Einheit und „optional“; Plus/Minus haben je Ziel eigene Beschriftungen; Werte werden als Satz vorgelesen („2,5 Liter pro Tag“) und als Live-Region angesagt.
- Zustände nie nur über Farbe: ausgewählte Karten haben Häkchen oder Schalterstellung, Fehler haben Symbol und Text, Fokus hat dickeren Rand.
- Große Schrift bis 200 Prozent: Inhalt scrollt, der Primärbutton bleibt unten sichtbar und wächst mit; ab 160 Prozent entfallen dekorative Symbole, und Modul- und Schalterkarten setzen den Schalter unter den Text; Zielzeilen, Körperdatenzeilen und die obere Leiste stapeln, sobald die Breite nicht mehr reicht. Der Primärbutton liegt oberhalb der Tastatur.
- Bewegung nur über `AppMotion` (150 bis 250 ms), sofort bei reduzierter Bewegung; keine Endlosanimation.
- Farben nur aus den Tokens, keine neue Farbkombination. Nachgerechnet für Light: Platzhalter „optional“ auf der Feldkarte 5,7 : 1, Hinweisbox 4,9 : 1, Untertitel 7,5 : 1 (jeweils mindestens 4,5 : 1); Light, Dark und OLED rendern ohne Fehler.

## 8. Tests

Befehle (im Repository-Wurzelverzeichnis):

```bash
flutter test test/features/onboarding            # 97 Tests
flutter test test/features/onboarding/domain      # 25
flutter test test/features/onboarding/application # 20
flutter test test/features/onboarding/presentation # 52 (Screen 28, Barrierefreiheit und Responsive 24)
```

| Bereich | Datei | Abnahme-IDs |
|---|---|---|
| Domänenregeln: Stepper-Grenzen auf beiden Seiten, Körperwerte, Texte, Optionen (kein Schlaf, IDs wie im Schema) | `test/features/onboarding/domain/` | C07 |
| Controller: Zustand, Navigation, Entwürfe, atomares Speichern, Überspringen, Doppeltipp-Sperre, Datenbankfehler mit echtem Rollback und Wiederholung mit gleicher ID, Konflikt bei bereits abgeschlossenem Profil | `test/features/onboarding/application/onboarding_controller_test.dart` | AT01, AT02, AT04, C01, C02, C03, C05, C07 |
| Screen: Erststart, fünf Screens, keine Vorauswahl, alle/keine Module, fehlende Körperdaten, Validierung (alle Grenzen), Entwürfe beim Zurück, Android-Zurück (drei Fälle), Fehler und Wiederholen, Neustart mit gleicher Datenbank, Navigation zum Dashboard mit `go_router` | `test/features/onboarding/presentation/onboarding_screen_test.dart` | AT01, AT02, AT04, C01, C02, C03, C05, C07 |
| Barrierefreiheit: Semantik, Tap-Ziele und Beschriftungen, Matrix 320/360/393/430 px bei Schrift 1,0 und 2,0, Tastatur, Themes, Bewegung | `test/features/onboarding/presentation/onboarding_accessibility_test.dart` | C06, Q02 (Anforderungs-IDs der Spezifikation) |

Die Datenbanktests nutzen die In-Memory-Datenbank und ihre echte Transaktion. Mutationsprüfung von Hand: Vorauswahl eines Ziels, fehlender Name im Entwurf, „abgeschlossen“ nach Fehler, wechselnde Command-ID, Überspringen mit Eingabe, Zurück ohne Rückfrage, Ziele nicht modulgefiltert und die Rückfrage vor dem Überspringen lassen jeweils Tests fehlschlagen.

## 9. Offene Punkte

- Der Router registriert `/onboarding` und leitet beim ersten Start dorthin um (Shell-Paket, nicht Teil dieses Pakets). Die Rückmeldung nach dem Abschluss setzt den Guard voraus, der `/onboarding` nach dem Commit verlässt; der Screen funktioniert auch ohne ihn, weil er selbst zu `/` navigiert.
- Ehrliche Leerzustände des Dashboards nach Erststart und Überspringen gehören zum Dashboard-Paket (AT01 gesamt).
- Kein Gerätetest: Android-Gesten, Tastaturverhalten und TalkBack-Lesereihenfolge sind nur über Host-Tests abgedeckt und sollten einmal auf einem Gerät geprüft werden.
- Die Schrittweiten der Plus/Minus-Tasten (500 Schritte, 250 ml, 5 Minuten, 1 Workout) sind eine Entscheidung dieser Umsetzung; Spezifikation und Figma nennen nur Grenzen und Startwerte.
- Der Hinweis zu Erinnerungen verweist auf die Einstellungen; der Einstieg dort gehört zum Einstellungen-Paket.
- Auf 320 px bei 200 Prozent Schrift bleibt wenig Platz für scrollenden Inhalt, weil Kopfzeile und Primärbutton fest bleiben. Nichts wird abgeschnitten.
- Zur Konsolidierung durch die Koordination: Design-Handoff (Abweichungen Abschnitt 5, Route `/onboarding` statt `/onboarding/*`) und Anforderungsmatrix (C01, C02, C03, C07, AT01, AT02, AT04 nachgewiesen durch die Tests oben).
