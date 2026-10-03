# Dashboard, Streak und Fortschritt

Umsetzung von BS-74 (Dashboard und gemeinsame Live-Projektionen), BS-58 (Kartenkonfiguration) sowie den UI-Anteilen von BS-68 und BS-69 (Fortschritt und Streak). Quelle des Designs sind die freigegebenen Figma-Frames (V1); Fachregeln stammen aus der Spezifikation (Abschnitte 5.1, 10 und 11). Dieses Dokument beschreibt Umfang, Abweichungen, Entscheidungen und Nachweise dieses Arbeitspakets.

## 1. Screens, Routen und Figma-Nodes

| Screen | Route | Figma-Node (Light) | Umsetzung |
|---|---|---|---|
| Dashboard | `/` | `2013:2` (Dark `4044:188`, OLED `4044:344`) | `HomeScreen` |
| Dashboard, erster Tag | `/` | `4045:2` | `FirstDaySection` im `HomeScreen` |
| Dashboard nach Speichern | `/` | `4053:663` | gleiche Seite, Zahlen aktualisieren sich live; die Snackbar stammt aus dem speichernden Ablauf |
| Karten anpassen | ohne eigene Route | kein Frame (Spezifikation 5.1 verlangt den Bearbeitungsmodus, der Entwurf hält ihn nicht fest) | `DashboardCardsScreen`, geöffnet über den Root-Navigator |
| Streak | `/streak` | `4004:2` (Dark `4056:1046`) | `StreakScreen` |
| Fortschritt | `/progress` | `4042:2` | `ProgressScreen` |

Dark und OLED entstehen aus den Theme-Tokens, es gibt keine eigenen Varianten im Code.

## 2. Aufbau und Datenfluss

- Das Dashboard rendert die Karten der aktiven Module (`SelfImprovementModule.dashboardCards`) in der gespeicherten Reihenfolge und Sichtbarkeit (`DashboardCardRepository`). Es baut keine Karte eines anderen Moduls. Die einzige eigene Karte ist die XP- und Level-Karte (`xp`) des Moduls Fortschritt.
- Quellen sind ausschließlich vorhandene Datenbank-Streams und gemeinsame Projektionen: Kartenkonfiguration, Modulstatus, Tagesstatus (`todayStatusProvider`), Streak (`streakProvider`), XP und Badges (`gamificationSummaryProvider`). Das Widget rechnet nichts neu. Die einzige neue Abfrage ist `hasAnyEntryProvider` (existiert irgendein Datensatz?), sie steuert den Willkommenszustand.
- Datum und Tageswechsel laufen über `todayProvider` und die injizierte Uhr, nie über `DateTime.now()`.
- Das Raster (`DashboardCardGrid`) setzt kleine Karten zu zweit in eine Reihe (ab 360 px und Textskalierung bis 1,3), große Karten (`fullWidth`) nehmen eine eigene Reihe und beenden die laufende Gruppe, damit die Reihenfolge des Nutzers immer erhalten bleibt. Jede Karte baut sich in einem eigenen `Consumer`, eine Datenänderung baut nur diese Karte neu.
- Das Modul `GamificationModule` liefert die Routen `/streak` und `/progress` und die Karte `xp` (volle Breite, Rang 7), aber keinen Plus-Eintrag.

## 3. Zustände des Dashboards

| Zustand | Verhalten |
|---|---|
| Laden | Nichts, erst nach 300 ms eine ruhige Textzeile "Daten werden geladen …" (Live-Region, kein Spinner) |
| Fehler | `ErrorState` mit "Erneut versuchen"; Wiederholen liest Karten, Module, Tagesstatus und Aktivität neu |
| Erster Tag | Nur wenn heute der Profilstart ist und noch kein Datensatz existiert: Begrüßung (mit Namen, falls vorhanden), "Ersten Eintrag hinzufügen" und "Schnell starten" (Gewicht, Wasser, erstes Habit, jeweils nur bei aktivem Modul). Weder Ring noch Zahlen noch Streak |
| Leerer Folgetag | Datum, Tagesring bei 0, ehrliche Leerzustände der Karten, Streak 0, XP 0 |
| Kein anwendbares Tagesziel | Karte "Noch keine Tagesziele" mit "Ziele festlegen", niemals ein Ring "0 von 0" |
| Alle Module aus | Leerzustand "Alle Module sind ausgeschaltet" mit "Module auswählen" (kein Ring, keine Karten) |
| Alle Karten ausgeblendet | Leerzustand mit "Karten anpassen"; Ring bleibt |
| Normal | Datum, "Dein Tag im Überblick", Tagesring mit einem der fünf festen neutralen Texte, Karten, "Karten anpassen" |
| Nach Speichern | Ring, Streak, XP und Karten aktualisieren sich aus der Datenbank; das Dashboard zeigt selbst keine Rückmeldung, diese kommt nur aus den speichernden Abläufen |
| Level-up | Ruhige Karte "Level n erreicht" über dem Ring, schließbar |

Streak-Einstieg, XP-Karte und Level-up-Hinweis erscheinen nur bei aktivem Modul Fortschritt. Tagesring und Streak-Berechnung laufen auch bei ausgeschaltetem Modul weiter.

## 4. Karten anpassen (BS-58)

- Pro Karte ein Schalter (Sichtbarkeit), ein Ziehgriff und die sichtbaren Tasten "nach oben" und "nach unten". Ziehen ist nie der einzige Weg.
- Jede Änderung ist ein gespeicherter Befehl über `DashboardCardRepository` und gilt sofort auf dem Dashboard und nach einem Neustart. Wiederholen nach einem Fehler verwendet dieselbe Befehls-ID, eine Änderung wird nie doppelt angewendet; zwei schnelle Taps wenden sie einmal an.
- Karten ausgeschalteter Module werden nicht aufgelistet, ihre Einstellung bleibt erhalten und kommt mit dem Modul zurück. Die Seite nennt die Anzahl und führt zu "Module verwalten". Verschieben orientiert sich an den aufgelisteten Nachbarn, auch wenn dazwischen unsichtbare Karten liegen.
- Fehler zeigen die Rückmeldung des `FeedbackService` mit "Erneut"; die Reihenfolge bleibt unverändert. Screenreader erhalten nach jeder Änderung eine Ansage mit der neuen Position.

## 5. Streak und Fortschritt

- Streak: aktuelle Serie, Wochenleiste der letzten sieben Tage mit Datum und Status in Worten, längste Serie, aktive Tage, nächster Meilenstein (3, 7, 14, 30, 60, 100, danach alle 100) mit Balken, Erklärung der Regel. Alle Zahlen kommen aus der berechneten Streak-Zusammenfassung.
- Fortschritt: Gesamt-XP, Level mit Balken (XP im Level von 100), die drei Badges "Erster Schritt", "Eine Woche dran", "Fokus gesammelt" mit Zustandswort ("Erreicht" oder "Gesperrt"), Link zur Streak. Ein Badge kann nach dem Löschen von Daten wieder gesperrt sein.
- Level-up: Die Engine meldet es nur nach dem Commit (`levelUpProvider`). Der Hinweis lebt nur im Speicher, wird nach einem Neustart nie wiederholt, verschwindet am Folgetag oder wenn die XP durch eine Korrektur unter das Level fallen.

## 6. Abweichungen von Figma und Gründe

1. Motivationsbanner: Die Spezifikation verlangt fünf feste neutrale Texte (Tag des Jahres modulo 5). Statt "Stark unterwegs!" und der Pokalzeile "Weiter so!" steht dort der Tagestext und ein sachlicher Satz zum Stand der Ziele.
2. Erster Tag: Die Hauptaktion öffnet direkt den ersten sinnvollen Eintrag (Gewicht, sonst Wasser, sonst Habit, sonst der erste Plus-Eintrag), nicht das Plus-Menü, weil dieses zur Shell gehört. "+250 ml Wasser" heißt "Wasser eintragen" und öffnet die Wasser-Seite: Das Dashboard speichert nie ohne Bestätigung. Wie im Frame fehlen Datum, Ring und Streak-Einstieg im Willkommenszustand.
3. Streak: Die Kacheln "Längste Streak" und "Aktive Tage gesamt" nutzen `MetricCard` (Titel neben dem Symbol statt Symbolkachel darüber). Der heutige Tag ist wie die anderen aktiven Tage gezeichnet und nur durch "Heute" hervorgehoben (Figma: andere Farbe). Marker tragen die Zustände über die Form (Haken, Ring, Strich, leerer Umriss) und nutzen die kontrastgeprüfte Textfarbe des Streak-Akzents. Zusätzlich zeigt die Leiste das Datum (Spezifikation 10.2).
4. Fortschritt: Die Level-Kachel ist eine umrandete Kachel ohne Verlauf. Die Frame-Werte (Level 4, 640 von 800 XP) sind Platzhalter; gerechnet wird mit 100 XP pro Level. Die Badge-Namen "Dranbleiber" und "Marathon" gibt es nicht, es gelten die drei der Spezifikation (11.3). Die Liste "Heute verdient" ist nicht umgesetzt (siehe offene Punkte). Zusätzlich vorhanden: Streak-Link und der Hinweis "So sammelst du XP" (ohne Zahlenwerte aus dem Widget).
5. Rückmeldung bei Level-up: eine Karte statt einer Snackbar, siehe Abschnitt 7.
6. Platzhalterzahlen der Frames (71,5 kg, Streak 11, "3 von 4 Zielen") werden nirgends angezeigt, es sei denn, sie sind aus echten Daten berechnet.

## 7. Spezifikationskonflikte und Entscheidung

| Konflikt | Entscheidung |
|---|---|
| Spezifikation 5.1: Streak-Einstieg nur bei sichtbarem Modul Fortschritt; Frame `4045:2` zeigt ihn nicht | Die Spezifikation gilt, außer im Willkommenszustand (dort wäre es nur eine "0") |
| Spezifikation 11.2 erlaubt ein UI-Ereignis nach dem Commit für Level-up; die Snackbar ersetzt die jeweils vorherige und würde das "Rückgängig" des auslösenden Speicherns verdrängen | Level-up als ruhige Karte im Dashboard |
| Spezifikation 11.1: Kein XP-Text darf einen Wert aus dem Feature-Widget übernehmen | XP, Level und Badge-Schwellen kommen aus Engine und Domain-Konstanten, die Hinweistexte nennen nur `xpPerLevel`, `badgeStreakDays` und `badgeFocusSeconds` |
| Frame `4004:2` zeigt "Noch 3 Tage bis zu deinem Rekord" als festen Satz | Der Satz folgt den Streak-Regeln (offener Tag verlängert die Serie, kein Verlust-Text) |
| Aufgabenkarte "bis zu drei offene Aufgaben" und Wasser-Schnellaktionen (Spezifikation 5.1) | Sache der Modulkarten; das Raster stört sie nicht (Quick-Actions lösen den Kartenklick nicht aus, erreichbar bei 320 px und 200 % Text) |

## 8. Barrierefreiheit

- Tippflächen mindestens 48 x 48 px; `androidTapTargetGuideline` und `labeledTapTargetGuideline` sind für Dashboard (alle Zustände), Karten anpassen, Streak und Fortschritt bei 320, 360, 393 und 430 px mit Textskalierung 1,0 und 2,0 grün (Messung an einer hohen Ansicht, damit angeschnittene Elemente die Messung nicht verfälschen).
- Text bis 200 %: Inhalt scrollt, Reihen und Raster stapeln sich (Streak-Wochenleiste wird zur Liste mit Datum und Statuswort, Karten anpassen legt die Pfeile in eine eigene Zeile, Ring und Text stapeln).
- Zustand nie nur über Farbe: Wochenleiste (Haken, Ring, Strich, Umriss plus Text), Badges ("Erreicht", "Gesperrt"), Karten ("Sichtbar", "Ausgeblendet").
- Semantics: Ring ("n von m Zielen erreicht"), Streak-Einstieg, jede Zeile der Wochenleiste mit vollem Datum und Status, Balken mit Zahlen, Pfeiltasten und Schalter mit Kartennamen, Level-up als Live-Region, Ansage nach dem Verschieben.
- Fokus und Modale: Karten anpassen schließt mit Zurück und Android-Zurück; Streak und Fortschritt führen bei Direktaufruf (Deep Link) zum Dashboard statt in eine Sackgasse.
- Bewegung: nur `AppMotion` (150 bis 250 ms), bei reduzierter Bewegung sofortiger Zustandswechsel, keine Endlosanimation.
- Kontrast: `textContrastGuideline` ist für Dashboard, Streak, Fortschritt und Karten anpassen in Light, Dark und OLED grün.

## 9. Tests und Abnahme-IDs

Befehl: `flutter test test/features/dashboard test/features/gamification/presentation` (198 Testfälle, grün).

| Datei | Fälle | Abnahme-IDs |
|---|---:|---|
| `test/features/dashboard/presentation/home_states_test.dart` | 19 | AT01, AT03, AT04, AT10, AT26, AT27, C01, C02, C03, C04, Q03 |
| `.../home_live_data_test.dart` | 9 | AT01, AT02, AT10, AT13, AT20, AT22, AT23, C04 |
| `.../home_responsive_test.dart` | 16 | AT01, AT04, AT10, AT33, C04, Q02 |
| `.../home_real_modules_test.dart` | 9 | AT03, AT10, C02, C03, C04, Q02 |
| `.../home_themes_test.dart` | 4 | AT35, C06 |
| `.../dashboard_cards_screen_test.dart` | 21 | AT02, AT03, AT27, AT33, AT34, C03, C04, C06 |
| `.../level_up_notice_test.dart` | 8 | AT23, AT26, AT27, C04, G02 |
| `.../day_overview_card_test.dart` | 9 | AT33, C04 |
| `.../screenshots_test.dart` | 5 | AT33, Q03 |
| `test/features/dashboard/application/dashboard_cards_controller_test.dart` | 9 | AT02, AT03, AT27, C03, C04 |
| `test/features/dashboard/data/dashboard_activity_repository_test.dart` | 11 | AT01 |
| `test/features/dashboard/domain/card_configuration_test.dart` | 9 | C03, C04 |
| `test/features/dashboard/domain/first_entry_action_test.dart` | 8 | C03 |
| `test/features/gamification/presentation/streak_screen_test.dart` | 19 | AT01, AT22, AT23, AT27, AT33, G02, Q02, C02 |
| `.../progress_screen_test.dart` | 16 | AT01, AT23, AT27, AT33, G02, Q02, C02 |
| `.../xp_dashboard_card_test.dart` | 4 | G02 |
| `.../gamification_module_test.dart` | 4 | C02 |
| `.../gamification_labels_test.dart` | 18 | AT22, G02 |

Die Modul- und Kartenmatrix (alle Module an, alle aus, eines an, Körpermodul aus und wieder an, Gamification aus und an, alle Karten ausgeblendet) steckt in `home_states_test.dart` und `home_real_modules_test.dart`. Der Neustart wird mit einem zweiten Container über derselben Datenbank nachgestellt, der Tageswechsel mit der `FakeClock`, ein Schreibfehler mit einem Datenbank-Trigger, der das Schreiben abbricht (nichts wird gespeichert, die Wiederholung verwendet dieselbe Befehls-ID).

Visueller Vergleich (Q03): `screenshots_test.dart` schreibt PNGs der Zustände (393 x 852 in Light und Dark, 320 px bei 200 % Text) in den Ordner `build/dashboard_shots`; sie wurden gegen die Nodes `2013:2`, `4045:2`, `4004:2` und `4042:2` geprüft, die Abweichungen stehen in Abschnitt 6.

## 10. Offene Punkte

- Fortschrittsseite: "Heute verdient" (Einzelvergaben des Tages) fehlt, weil kein Lesemodell für die Vergaben des Tages existiert. Der Auftrag nennt die Liste nicht; bei Bedarf wäre eine Abfrage auf `xp_awards` nach lokalem Datum nötig.
- Die Karte `weight` stürzt ab, wenn die letzte Messung älter als sieben Tage ist: `WeightSparkline` ruft `reduce` auf eine leere Punkteliste auf. Das gehört zum Körpermodul und muss dort behoben werden (leere Punkte abfangen).
- Die Seite "Karten anpassen" wird mit einer ungetypten Navigator-Route über dem Root-Navigator geöffnet, weil die Shell nur `/`, `/streak` und `/progress` kennt. Android-Zurück ist im Zusammenspiel mit der Shell auf dem Gerät zu prüfen; alternativ kann `DashboardCardsScreen` als eigene Route registriert werden.
- `GamificationModule.routes` registriert `/streak` und `/progress` bereits; die Shell darf sie nicht ein zweites Mal registrieren (oder muss die Modulrouten verwenden).
- Stand dieses Branches liefern die Module Fokus und Aufgaben ihre Dashboard-Karten noch nicht (Körper, Ernährung und Fortschritt schon); bis dahin fehlen Workout, Fokus und Aufgaben auf dem Dashboard.
- Die Karten der Module sind nicht Teil dieses Pakets. Getestet ist ihr Zusammenspiel mit dem Raster: Quick-Actions lösen den Kartenklick nicht aus und sind bei 320 px und 200 % Text erreichbar; die echte Wasserkarte speichert mit einem Tap und das Rückgängig nimmt Menge und XP zurück.
