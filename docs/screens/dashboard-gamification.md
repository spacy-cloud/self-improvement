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
| Ziele heute | `/goals/today` | `4112:60` (Dark `4113:160`, OLED `4113:270`), alle Zustände in Abschnitt 12.1 | `GoalsTodayScreen` (v0.2.0, Abschnitt 12) |

Dark und OLED entstehen aus den Theme-Tokens, es gibt keine eigenen Varianten im Code.

## 2. Aufbau und Datenfluss

- Das Dashboard rendert die Karten der aktiven Module (`SelfImprovementModule.dashboardCards`) in der gespeicherten Reihenfolge und Sichtbarkeit (`DashboardCardRepository`). Es baut keine Karte eines anderen Moduls. Die einzige eigene Karte ist die XP- und Level-Karte (`xp`) des Moduls Fortschritt. Alle acht Karten sind vorhanden: `steps` und `weight` (Körper), `water` und `nutrition` (Ernährung), `workout` und `focus` (Fokus), `tasks` (Aufgaben und Gewohnheiten, ab v0.2.0 „Heute abhaken“, volle Breite) und `xp` (Fortschritt, volle Breite); die Standardreihenfolge ist Schritte, Wasser, Gewicht, Workout, Fokus, Aufgaben, Ernährung, XP.
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
| Kein anwendbares Tagesziel | Karte "Noch keine Tagesziele" mit "Ziele festlegen", niemals ein Ring "0 von 0" und kein Titel. Fragt trotzdem jemand danach, gilt es als "keins erreicht": `ProgressRing.goals` zeichnet nur die Spur und wird nie grün, `GoalsStanding.of` liefert `none` |
| Alle Module aus | Leerzustand "Alle Module sind ausgeschaltet" mit "Module auswählen" (kein Ring, keine Karten) |
| Alle Karten ausgeblendet | Leerzustand mit "Karten anpassen"; Ring bleibt |
| Normal | Datum, "Dein Tag im Überblick", Tagesring (grau, gelb oder grün nach dem Stand der Ziele) mit dem Titel des Standes (je Stand drei neutrale Texte, siehe Abschnitt 6, Punkt 1), Karten, "Karten anpassen" |
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

1. Tagesring und Titel der Karte (BS-121, Entscheidung D-026): Beides hängt vom Stand der Tagesziele ab. Die Frames "Ziele-Ring – Zustände" (`4127:316`, Dark `4127:365`, OLED `4127:414`) zeigen die vier Fälle 0 von 4, 2 von 4, 4 von 4 und 1 von 1.
   - Ring: 0 erreicht grau (nur die Spur, kein Bogen), 1 bis x minus 1 erreicht gelb (`dayRing`, `#E2D11E`), alle erreicht grün (`dayRingComplete`, Wert von `color/primary`, voller Ring). "Alle erreicht" heißt: mindestens ein Ziel gilt und keines fehlt, ein einziges Ziel (1 von 1) zählt. Die Farbe wählt allein `ProgressRing.goals`, die Karte übergibt keine Farbe: So sieht der Ring auf Home und in der Übersicht "Ziele heute" (BS-103) gleich aus. Die Farbe ist nie die einzige Information: "x von y" im Ring, der gesprochene Text ("4 von 4 Zielen erreicht") und der sachliche Satz darunter bleiben unverändert. Kontrast (Light 2,66:1 gegen die Kartenfläche, geprüfte Alternative `primary-button` mit 4,72:1, nicht gewählt): [design-handoff.md](../design-handoff.md) Abschnitt 8.4.
   - Titel: je Stand drei neutrale Texte, gewählt mit Tag des Jahres modulo 3 innerhalb der Liste des Stands (`motivationTextFor(date, fulfilled:, applicable:)`). Keins erreicht: "Heute ist ein guter Tag, um anzufangen." / "Jeder Tag ist ein neuer Anfang." / "Ein Eintrag nach dem anderen."; teilweise: "Stark unterwegs!" / "Kleine Schritte zählen." / "Bleib in deinem Tempo."; alle erreicht: "Geschafft!" / "Das war ein runder Tag." / "Heute hat alles geklappt." Kein Text einer anderen Liste erscheint im falschen Stand, an keinem Tag des Jahres. Die Wortlaute sind Standardwerte von Joern und dürfen geändert werden (ein Test hält sie fest). Sie ersetzen die fünf festen Texte der Spezifikation (Tag des Jahres modulo 5, die Spezifikation liegt nicht im Repository); die Pokalzeile "Weiter so!" des V1-Entwurfs gibt es weiter nicht.
   - Ohne anwendbares Ziel zeigt Home "Noch keine Tagesziele" (Abschnitt 3), keinen Ring und keinen Titel. Wird der Stand dennoch erfragt, gilt "keins erreicht": nur die Spur, nie grün, Titelliste "keins".
   - Vergangene Tage (BS-93, noch nicht gebaut): Die Titel nennen "heute" und gehören nur zum heutigen Tag. Ein vergangener Tag zeigt nur den sachlichen Satz zum Stand und keinen Titel: `DayOverviewCard` nimmt dafür `motivation: null` an, `motivationTextFor` wird für ihn nicht aufgerufen. Der Satz selbst ("Du hast heute …") ist noch an heute gebunden und wird mit BS-93 angepasst; die Ringfarbe nach Stand gilt dort ebenfalls.
   - Abweichungen im Entwurf (nicht umgesetzt, Figma nicht geändert): `4115:249` ("Home – Karte antippbar") zeigt weiter die Pokalzeile "Weiter so!" und den Zusatz "Bleib dran!"; die App zeigt nur Titel und sachlichen Satz. Die antippbare Karte (Chevron) gehört nicht zu BS-121. Auf den Tafeln steht "Zielen" in 12 px (Caption/Default) und der Abstand zwischen Ring und Text beträgt 20 px; die Karte nutzt wie bisher 14 px (Body/Regular) und 24 px.
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
- Zustand nie nur über Farbe: Tagesring (grau, gelb, grün plus "x von y" im Ring, gesprochener Text, Titel und sachlicher Satz), Wochenleiste (Haken, Ring, Strich, Umriss plus Text), Badges ("Erreicht", "Gesperrt"), Karten ("Sichtbar", "Ausgeblendet").
- Semantics: Ring ("n von m Zielen erreicht", unabhängig vom Stand und seiner Farbe; die Zahl in der Mitte wird nicht ein zweites Mal gelesen), Streak-Einstieg, jede Zeile der Wochenleiste mit vollem Datum und Status, Balken mit Zahlen, Pfeiltasten und Schalter mit Kartennamen, Level-up als Live-Region, Ansage nach dem Verschieben.
- Fokus und Modale: Karten anpassen schließt mit Zurück und Android-Zurück; Streak und Fortschritt führen bei Direktaufruf (Deep Link) zum Dashboard statt in eine Sackgasse.
- Bewegung: nur `AppMotion` (150 bis 250 ms), bei reduzierter Bewegung sofortiger Zustandswechsel, keine Endlosanimation.
- Kontrast: `textContrastGuideline` ist für Dashboard, Streak, Fortschritt und Karten anpassen in Light, Dark und OLED grün.

## 8a. v0.2.0: Karte „Heute abhaken“ (BS-110)

Ticket [BS-110](https://spacy-cloud.atlassian.net/browse/BS-110), Entscheidung D-028. Die Karte `tasks` (Modul `tasks`, volle Breite) zeigt die Aufgaben und die Gewohnheiten von heute in einer Liste und lässt beide mit einem Tipp abhaken; Zeilen, Zustände, Unterscheidung von Aufgabe und Gewohnheit und die Abweichungen vom Entwurf (`4116:421`, Dunkel `4116:822`, OLED `4116:1223`) stehen in [tasks-habits.md](tasks-habits.md) Abschnitt 2a. Für das Dashboard gilt:

- **Einbindung unverändert.** Die Karte kommt wie bisher aus `TasksModule.dashboardCards` (`cardId` `tasks`, Platz nach „Fokus“, `fullWidth`); `HomeScreen`, `DashboardCardGrid` und die Kartenkonfiguration sind nicht angefasst, es gibt keine neue Karten-ID (Karten-IDs gehören zum Datenvertrag, D-015). Neu ist nur der Name in „Karten anpassen“: „Aufgaben und Gewohnheiten“ statt „Aufgaben“, weil das Ausblenden der Karte beide ausblendet.
- **Modul-Tor wie bisher.** Ist das Modul „Aufgaben und Gewohnheiten“ aus, fehlt die Karte (`visibleDashboardEntries`): nichts wird gelesen, nichts geschrieben, die Einträge bleiben und sind mit dem Modul wieder da. Beides prüft ein Test auf dem echten Home (`test/features/tasks/presentation/home_checklist_test.dart`).
- **Ein Haken wirkt wie in den Listen.** Die Karte ruft dieselben Befehle auf wie der Tab und die Aufgabenliste; XP, Tageslimits, Tagesring und Streak folgen deshalb den Regeln der Engine und rechnen nichts auf der Karte. Der Zähler „x von y erledigt“ der Karte zählt, was heute abzuhaken ist, und ist nicht der Tagesring „Dein Tag im Überblick“, der die Tagesziele zählt.
- **Vergangene Tage (BS-93).** Die Karte kennt den Zustand „nur lesend“ (`TasksDashboardCard(readOnly: true)`); `DayOverviewCard`, Router und die Seite „Ziele heute“ (BS-100) sind nicht Teil dieses Tickets.

## 9. Tests und Abnahme-IDs

Befehl: `flutter test test/features/dashboard test/features/gamification/presentation` (270 Testfälle, grün). Der Stand des Gesamtlaufs steht in [test-report.md](../test-report.md).

| Datei | Fälle | Abnahme-IDs |
|---|---:|---|
| `test/features/dashboard/presentation/home_states_test.dart` | 21 | AT01, AT03, AT04, AT10, AT26, AT27, C01, C02, C03, C04, Q03 |
| `.../home_live_data_test.dart` | 9 | AT01, AT02, AT10, AT13, AT20, AT22, AT23, C04 |
| `.../home_responsive_test.dart` | 16 | AT01, AT04, AT10, AT33, C04, Q02 |
| `.../home_real_modules_test.dart` | 9 | AT03, AT10, C02, C03, C04, Q02 |
| `.../home_themes_test.dart` | 4 | AT35, C06 |
| `.../dashboard_cards_screen_test.dart` | 21 | AT02, AT03, AT27, AT33, AT34, C03, C04, C06 |
| `.../level_up_notice_test.dart` | 8 | AT23, AT26, AT27, C04, G02 |
| `.../day_overview_card_test.dart` | 49 | AT33, AT34, AT35, C04, C06, Q02, Q03 |
| `.../home_day_ring_test.dart` | 30 | AT35, C04, C06, Q02, Q03 |
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

Tagesring und Titel nach Stand (BS-121): Die Farbe wird an den Bögen gelesen, die `ProgressRing` auf die Zeichenfläche malt (`test/core/design/support/ring_arcs.dart`), nicht an einem Feld. `day_overview_card_test.dart` prüft die vier Zustände 0 von 4, 2 von 4, 4 von 4 und 1 von 1 in Light, Dark und OLED gegen die Tokens (nicht gegen feste Hex-Werte), dass die Karte und ein einzelnes `ProgressRing.goals` denselben Ring malen (Grundlage für "Ziele heute"), dass Ring und Titel bei jedem Zahlenpaar denselben Stand lesen, die gesprochenen Texte und die Richtlinien (Tippflächen, Beschriftung, Textkontrast) bei vier Breiten mit Textskala 1,0 und 2,0. `home_day_ring_test.dart` prüft die Zustände auf dem echten Home, den Titel je Stand an drei aufeinanderfolgenden Tagen (Tag des Jahres 276 bis 278), den Wegfall von Ring und Titel ohne anwendbares Ziel und einen Ablauf mit echten Daten (eine erledigte Aufgabe färbt das einzige Ziel grün, Wiederöffnen nimmt Farbe und Titel zurück). Die Regeln der Texte und Stände (alle Tage von 2026 und 2028, kein Titel im falschen Stand) stehen in `test/core/dashboard/motivation_test.dart`, die Token- und Kontrastwerte in `test/core/design/tokens_test.dart` und `contrast_test.dart`. Mutationsproben (lokal, nicht eingecheckt): Ohne die Farbwahl in `ProgressRing` scheitern 27 der neuen und geänderten Tests (4 von 4 und 1 von 1 in allen drei Themes, der Ablauf mit echten Daten), mit den alten fünf festen Texten statt der Liste des Stands 22. Auf einem Gerät ist nichts davon gesehen: Die Belege sind Host-Tests.

Visueller Vergleich (Q03): `screenshots_test.dart` schreibt PNGs der Zustände (393 x 852 in Light und Dark, 320 px bei 200 % Text) in den Ordner `build/dashboard_shots`; sie wurden gegen die Nodes `2013:2`, `4045:2`, `4004:2` und `4042:2` geprüft, die Abweichungen stehen in Abschnitt 6. Für BS-121 wurden die vier Zustände einmalig im Host in Light, Dark und OLED (393 px) gerendert und gegen die Tafeln `4127:316`, `4127:365` und `4127:414` verglichen: Farbe und Länge des Bogens und die Titel stimmen, die Unterschiede stehen in Abschnitt 6, Punkt 1 (die Bilder gehören nicht zum Repository).

## 10. Offene Punkte

- Fortschrittsseite: "Heute verdient" (Einzelvergaben des Tages) fehlt, weil kein Lesemodell für die Vergaben des Tages existiert. Der Auftrag nennt die Liste nicht; bei Bedarf wäre eine Abfrage auf `xp_awards` nach lokalem Datum nötig.
- Die Seite "Karten anpassen" wird imperativ über dem Root-Navigator geöffnet (`dashboard_cards_screen.dart`, `appPageRoute`), weil sie keine eigene Route hat. Der Seitenübergang folgt dem Schalter "Reduzierte Bewegung" und dem Systemflag. Android-Zurück ist im Zusammenspiel mit der Shell auf dem Gerät zu prüfen; alternativ kann `DashboardCardsScreen` als eigene Route registriert werden.
- Die Ansage nach dem Verschieben einer Karte ("an Position n von m verschoben") wird beim Tippen aus der angezeigten Position gebildet; wird ein zweiter Zug ignoriert, weil der erste noch läuft, nennt die Ansage trotzdem "verschoben". Bekannt, nicht behoben (siehe [known-limitations.md](../known-limitations.md)).
- Die Karten der Module sind nicht Teil dieses Pakets. Getestet ist ihr Zusammenspiel mit dem Raster (`home_real_modules_test.dart` mit den echten Modulen): Quick-Actions lösen den Kartenklick nicht aus und sind bei 320 px und 200 % Text erreichbar; die echte Wasserkarte speichert mit einem Tap und das Rückgängig nimmt Menge und XP zurück.
- Erledigt und deshalb keine offenen Punkte mehr: Die Gewichtskarte zeigt bei einer Messung, die älter als sieben Tage ist, "Zuletzt <Datum>" ohne Kurve und ohne Vergleich statt abzustürzen (`weight_dashboard_card_test.dart`); alle acht Karten kommen von den Modulen; `GamificationModule` liefert `/streak` und `/progress`, die Shell registriert sie nicht noch einmal (`findDuplicatePaths` prüft es).

## 11. v0.2.0: Tagesring und Streak mit dem Tagesziel „Workout heute“ (BS-99)

Ticket [BS-99](https://spacy-cloud.atlassian.net/browse/BS-99), Entscheidungen D-024 und D-025 ([../implementation-decisions.md](../implementation-decisions.md)); Karte, Sheet und Workout-Bereich stehen in [focus-workouts.md](focus-workouts.md), Abschnitt 9. Dieser Abschnitt beschreibt nur, was sich für den Tagesring, die Streak und die XP ändert; die Home-Dateien des Rings (Farbe, Titel) gehören BS-121 und sind hier nicht angefasst.

- **Tagesring.** `GoalType.workoutDaily` ist ein sechstes Tagesziel. Ausgeschaltet (Standard: kein Eintrag in `goal_versions`) steht es im Snapshot als nicht anwendbar und zählt nicht in „x von y“; der Nenner ändert sich für vorhandene Nutzer nicht. Eingeschaltet (ab morgen, wie jede Zieländerung) zählt es mit („x von 6“) und ist an einem Tag erreicht, wenn der Tag mindestens ein gültiges Workout, einen Ruhetag oder eine Überspringen-Markierung hat. Die Wochenzahl des Wochenziels hat keinen Einfluss (nur die Fakten des Tages gehen in `computeDayStatus` ein); das Wochenziel selbst ist weiter kein Tagesziel und steht nie im Ring.
- **Streak.** Ein Tag ist aktiv, wenn mindestens ein anwendbares Ziel erreicht ist; mit eingeschaltetem Ziel halten deshalb auch Ruhetag und Überspringen die Streak, wie ein Workout. Ohne das Ziel halten sie nichts (die Markierung hat dann keine Wirkung, die Oberfläche bietet sie nicht an). Löscht oder nimmt man die Markierung zurück, sinkt die Streak sofort wieder (alle Werte werden aus den Fakten neu gerechnet, auch nach einem Import).
- **XP.** Ruhetag und Überspringen vergeben keine XP und lösen beim Import keine Neuberechnung aus; ein Workout vergibt weiter 15 XP einmal pro Tag (Regeln unverändert).
- **Datenfluss.** `DayFactsSource` liest je Tag die Zahl der aktiven Workouts und die aktive Markierung; seine `tables` enthalten `workoutEntries` und `workoutDayMarks`, damit Tagesring und Streak neu laufen, wenn sich eines davon ändert. Der Snapshot eines Tages friert das Ziel mit ein (`goal_key` `workout_daily`), spätere Änderungen schreiben keinen vergangenen Tag um.
- **Home-Karte Workout.** Mit eingeschaltetem Ziel zeigt sie den Tag (offen, Training, Ruhetag, übersprungen), ohne das Ziel die Woche wie bisher.
- **Tests.** `test/core/goals/domain/day_status_test.dart`, `day_snapshot_test.dart`, `test/core/goals/data/workout_daily_goal_test.dart` (echte Datenbank: ein Workout bei Wochenziel 3 und 5, Ruhetag, Überspringen, Streak, kein XP, aus, ab morgen, Zeitzone, Streams), `test/core/backup/workout_day_marks_roundtrip_test.dart`.


## 12. v0.2.0: „Ziele heute“ und die antippbare Tageskarte (BS-100)

Ticket [BS-100](https://spacy-cloud.atlassian.net/browse/BS-100) (Bug: Die Kachel „Ziele“ auf Home ließ sich nicht antippen, Ziele und Fortschritt waren nicht einsehbar) mit den Teilaufgaben BS-103 (Seite „Ziele heute“) und BS-104 (Karte antippbar). BS-105 (Aktion „Ziele bearbeiten“, Sprung zum Modul je Ziel) und BS-106 (Host-Tests und Doku dazu) folgen im zweiten Pull Request. BS-101 (der Entwurf) liegt in der Figma-Datei LF10-Desing-App, Seite „v0.2.0 – Neue Screens“; seine Freigabe liegt bei Joern. BS-107 (Prüfung auf dem Gerät) ist offen. Entscheidung D-027 ([../implementation-decisions.md](../implementation-decisions.md)).

### 12.1 Route, Figma-Knoten und Dateien

| Zustand | Hell | Dunkel | OLED |
|---|---|---|---|
| Ziele heute, teilweise (2 von 5) | `4112:60` | `4113:160` | `4113:270` |
| nichts erreicht | `4112:186` | – | – |
| alle erreicht | `4112:304` | – | – |
| ein einziges Ziel | `4112:444` | – | – |
| kein Ziel | `4112:509` | – | – |
| 200 % Schrift, gestapelt | `4114:501` | – | – |
| Ruhetag als Workout-Ziel und Wochenziel (BS-99) | `4114:327` | – | – |
| vergangener Tag (BS-93) | `4114:186` | – | – |
| Home, Karte antippbar | `4115:249` | `4115:565` | `4115:881` |
| Home, Karte gedrückt | `4115:407` | `4115:723` | `4115:1039` |

Die Route `/goals/today` (`DashboardRoutes.goalsToday`) ist eine Kernseite über der Shell, registriert wie `/goals` (Abschnitt 3.1 in [shell.md](shell.md)); sie ist nicht durch ein Modul geschützt, weil der Tagesring auch bei ausgeschalteten Modulen läuft: ihre Zeilen kommen nur von aktiven Modulen. Dark und OLED entstehen aus den Theme-Tokens.

Dateien (alle unter `lib/features/dashboard/`): `domain/goals_day.dart` (Modell und Texte, rein), `application/goals_today_providers.dart` (`goalsTodayProvider`), `presentation/goals_today_screen.dart` (Seite), `presentation/widgets/goals_day_view.dart` (Inhalt), `goals_summary_card.dart` (Ring und Kopf), `goal_row_tile.dart` (eine Zeile), `goal_visuals.dart` (Symbol, Akzent und Balken je Ziel), `not_today_banner.dart` (Hinweis „Nicht heute“) und die Karte `day_overview_card.dart` (nur die Antippbarkeit). Geändert in gemeinsamen Dateien: `app_router.dart` (die Route), `dashboard_routes.dart` (die Konstante), `home_screen.dart` (eine Zeile: `onTap` der Karte).

### 12.2 Datenfluss: dieselben Zahlen wie der Ring

- `goalsTodayProvider` liest `dashboardViewProvider`, also `DashboardView.dayStatus` mit `DayStatus.goals`: dasselbe Objekt, das der Ring auf Home zählt. Das Modell `GoalsDay` übernimmt `DayStatus.fulfilledCount` und `applicableCount` unverändert („x von y“) und rechnet keine zweite Zahl. Ob eine Zeile „erreicht“ ist, entscheidet allein `GoalProgress.fulfilled`; die übrigen Quellen ändern nur Worte.
- Es erscheinen nur anwendbare Tagesziele (ausgeschaltete Ziele und Ziele ausgeschalteter Module sind im Tagesstatus nicht anwendbar), also gibt es genau y Zeilen und x erreichte. Zeigt Home einmal einen anderen Tag (BS-93), liest die Seite denselben Status und baut daraus den Zustand „Nicht heute“ (12.9).
- Drei weitere Quellen liefern Worte und das Wochenziel, nie Zahlen des Rings, und werden nur gelesen, wenn die Seite sie braucht: die Namen der Gewohnheiten (nur wenn ein Gewohnheitsziel gilt, `habitsProvider`), wie „Workout heute“ beantwortet wurde (Workout, Ruhetag oder Überspringen, nur wenn dieses Ziel heute gilt, `workoutDayStateProvider`) und die Workouts der Woche (nur wenn das Fokus-Modul an ist und ein Tagesziel gilt, `workoutWeekSummaryProvider`). Geladen wird erst, wenn alle da sind; ein Fehler in einer Quelle ist ein Fehler der Seite („Erneut versuchen“ liest alles neu).
- Die Seite hält keine Regel: Prozent, Einheiten und Texte stehen in `goals_day.dart`; Datum und Tageswechsel laufen über `todayProvider` und die injizierte Uhr.

### 12.3 Zustände

| Zustand | Verhalten |
|---|---|
| Laden | Nichts, erst nach 300 ms eine ruhige Textzeile „Daten werden geladen …“ (wie Home) |
| Fehler | `ErrorState` mit „Erneut versuchen“; die Wiederholung liest Status, Gewohnheiten, Workout und Woche neu |
| Nichts erreicht | grauer Ring (nur die Spur), „Noch nichts erreicht“, „Heute ist noch alles offen. Mach den ersten Schritt.“, alle Zeilen „Offen“ |
| Teilweise | gelber Bogen, „2 von 5 erreicht“, „Noch 3 Ziele offen. Bleib dran!“ („Noch 1 Ziel offen. Bleib dran!“) |
| Alle erreicht | voller grüner Ring, Pokal vor der Überschrift, „5 von 5 erreicht“, „Stark! Heute ist alles geschafft.“ |
| Ein einziges Ziel | „1 von 1 Ziel erreicht“ (erreicht) mit „Du hast dein Tagesziel erreicht.“, Kopf der Liste „Tagesziel“ im Singular |
| Kein Tagesziel | `EmptyState` „Noch keine Tagesziele“ mit „Ziele festlegen“ (öffnet `/goals`), kein Ring, nie „0 von 0“; gilt auch, solange noch kein Tagesstatus existiert (vor dem Profilstart) |
| Wochenziel | Gruppe „Wochenziel · nicht im Tagesring“ unter der Liste, wenn heute mindestens ein Tagesziel gilt und das Fokus-Modul an ist |
| Vergangener Tag (BS-93) | Hinweis „Nicht heute“ mit Datum und „Zurück zu heute“, Kopf „Du siehst die Werte dieses Tages.“, Zeilen mit Wörtern der Vergangenheit („Nicht gewogen“), kein Wochenziel; die Seite zeigt heute, bis BS-93 einen anderen Tag in `DashboardView` legt (12.9) |
| 200 % Schrift oder unter 300 px Kartenbreite | Ring über den Texten, Zeile gestapelt: Name, darunter das Status-Wort, dann Stand und Balken, ohne Pfeil (wie `4114:501`); die Seite scrollt |

### 12.4 Zeilen: Stand, Ziel und Status

Jede Zeile hat Symbol und Akzent des Moduls (wie auf seiner Karte auf Home, Gewohnheiten mit ihrem eigenen Symbol), den Namen aus dem Ziele-Editor, ein Status-Wort, Stand und Ziel mit Einheit und einen Balken (`AppProgressBar`, für Workout und Gewohnheiten derselbe Balken im Akzent über `AccentProgressBar`). Der Status steht nie nur in der Farbe: „Offen“ (ruhig), „Erreicht“ (Haken), „Ruhetag“ (Mond), „Übersprungen“ (Symbol wie im Sheet). Die Prozentzahl ist der wirkliche Wert, gerundet auf ganze Prozent, und nie 100 vor dem Ziel (9.950 von 10.000 sind 99 %); über dem Ziel steht der wirkliche Wert (112 %), der Balken bleibt voll. Das ist dieselbe Regel wie auf der Wasser- und der Schrittseite (ein Test vergleicht beide).

| Ziel | Reihenfolge | Zeile (Beispiel) |
|---|---|---|
| Wasser | 1 | „1,5 von 2,5 l · 60 %“ (Liter wie im ganzen Modul) |
| Schritte | 2 | „7.450 von 10.000 · 75 %“; ohne Eintrag „Noch keine Schritte eingetragen“ (eine erfasste 0 ist ein Wert: „0 von 10.000 · 0 %“) |
| Fokus | 3 | „45 von 60 Min. · 75 %“ (volle Minuten abgeschlossener Sitzungen) |
| Gewicht erfassen | 4 | „Noch nicht gewogen“ / „Heute gewogen“ / „Heute 3-mal gewogen“; leerer oder voller Balken |
| Workout heute (BS-99) | 5 | „Noch kein Training eingetragen“; „1 Training eingetragen“; „Ruhetag eingetragen · keine XP, Streak bleibt“ (Status „Ruhetag“, ohne Balken); „Training übersprungen · keine XP, Streak bleibt“ (Status „Übersprungen“, ohne Balken). Ruhetag und Überspringen zählen als erreicht |
| Aufgabe erledigen | 6 | „Noch keine Aufgabe erledigt“ / „1 Aufgabe erledigt“ / „2 Aufgaben erledigt“ |
| Gewohnheit | danach, in der Reihenfolge der Gewohnheitsliste | Name der Gewohnheit, „Noch nicht abgehakt“ / „Heute abgehakt“. Eine Zeile je Gewohnheit, weil der Ring jede einzeln zählt; ist eine Gewohnheit nicht bekannt, heißt die Zeile „Gewohnheit“ |
| Wochenziel „Workouts diese Woche“ | eigene Gruppe | „2 von 3 · 67 %“, wirkliche Zahl auch über dem Ziel („4 von 3 · 133 %“); zählt nie im Ring |

Die Reihenfolge ist die des Ziele-Editors (`goalDisplayOrder`).

### 12.5 Die Karte „Dein Tag im Überblick“ (BS-104)

- Die Karte ist antippbar (`DayOverviewCard.onTap`, auf Home `context.push('/goals/today')`): die ganze Karte ist eine Tippfläche, rechts oben steht ein Pfeil (Entwurf `4115:249`), gedrückt nimmt sie die grüne Tönung und den grünen Rand des Entwurfs (`4115:407`, aus den Tokens `primaryTint` und `primary`, in allen drei Themes). Ein Finger, der wegrutscht, löst nichts aus und nimmt den Zustand zurück.
- Für Screenreader ist die Karte **ein** Button: „Ziele heute, 2 von 4 erreicht, Details öffnen“. Ring, Titel und Satz darin werden nicht noch einmal vorgelesen; der Ring behält seinen eigenen Sprechtext überall, wo er allein steht (auf der Seite „Ziele heute“ ist die Kopfkarte ein Element mit Datum, Überschrift und Satz). Ohne `onTap` bleibt die Karte eine reine Anzeige mit dem Sprechtext des Rings.
- Ohne anwendbares Ziel bleibt „Noch keine Tagesziele“ mit „Ziele festlegen“ unverändert (`NoGoalsCard`).
- Zurück (Pfeil der Seite oder Android-Zurück) führt nach Home, mit unveränderter Scrollposition (die Seite liegt per `push` über der Shell); bei einem Direktaufruf ohne darunterliegende Seite führt Zurück nach Home statt in eine Sackgasse (`leaveToHome`).

### 12.6 Abweichungen vom Entwurf und Gründe (Q03)

Der Entwurf ist nicht freigegeben; Figma wurde nicht verändert. Bei einer Abweichung wurde nichts still entschieden:

1. Maße aus den Tokens statt der Frame-Werte: Seitenrand 16 px (Standard von `AppScaffold`, Entwurf 14 px), Balken 12 px (`AppProgressBar`, Entwurf 8 px), Trennlinien der Liste mit 14 px Einzug (`AppListGroup`, Entwurf über die volle Breite).
2. Reihenfolge: die des Ziele-Editors. „Workout heute“ steht dort vor „Aufgabe erledigen“; der Entwurf `4114:327` setzt es ans Ende.
3. „Aufgabe erledigen“ im Akzent der Aufgabenkarte auf Home (Gewohnheiten und Aufgaben, Violett) statt Grün im Entwurf, damit ein Ziel hier und auf seiner Karte gleich aussieht.
4. „Gewicht erfassen“ ohne Gewichtswert („Heute gewogen“ statt „Heute gewogen: 71,5 kg“): `DayStatus` kennt nur die Zahl der Einträge; der Wert käme aus einer zweiten Quelle neben dem Ring.
5. Prozent über dem Ziel: der wirkliche Wert wie auf der Wasser- und Schrittseite („2,6 von 2,5 l · 104 %“); der Entwurf `4114:186` zeigt hier 100 %.
6. Der Satz im Kopf „Ruhetag zählt mit, ohne XP. Die Streak bleibt.“ (`4114:327`) fehlt: Der Kopf sagt „Noch n Ziele offen“, die Zeile des Workout-Ziels sagt, was der Ruhetag wert ist.
7. Zustand „kein Ziel“ (`4112:509`): das Symbol ist der Spross des Leerzustands (der Symbolsatz hat keine Zielscheibe), Text und Schaltfläche wie im Entwurf.
8. Wochenziel: wie `4114:327` in jedem Zustand mit Tagesziel; die älteren Frames `4112:60` bis `4112:444` zeigen es nicht (Entscheidung: Wochenziel getrennt, zählt nicht mit). Ohne Tagesziel und an einem vergangenen Tag steht es nicht dort.
9. Stapeln: unter 300 px Kartenbreite stapelt die Zeile auch bei normaler Schrift (bei 320 px Bildschirmbreite), sonst bräche der Name in der Zeile mit dem Status-Wort.
10. Home-Karte `4115:249`: Der Entwurf zeigt noch die Pokalzeile „Weiter so!“ und „Bleib dran!“, die App zeigt Titel und sachlichen Satz (BS-121, Abschnitt 6 Punkt 1). Pfeil und gedrückter Zustand sind wie im Entwurf; die Rundung der Karte ist 16 statt 17 px (Abschnitt 8.4 in [design-handoff.md](../design-handoff.md)).

### 12.7 Barrierefreiheit

- Tippflächen mindestens 48 x 48: die ganze Karte auf Home, der Zurück-Pfeil, „Ziele festlegen“, „Zurück zu heute“; `androidTapTargetGuideline` und `labeledTapTargetGuideline` sind für die Seite in allen Zuständen (bis hin zu Workout, zwei Gewohnheiten und Wochenziel) bei 320, 360, 393 und 430 px mit Textskalierung 1,0 und 2,0 grün, ebenso für die Karte.
- Sprechtexte: Kopfkarte als ein Element („Samstag, 3. Oktober. 2 von 5 erreicht. Noch 3 Ziele offen. Bleib dran!“), jede Zeile als ein Element („Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen“, „Workout heute, Ruhetag, zählt als erreicht, keine XP, die Streak bleibt“), Überschriften der Gruppen als Überschriften; Balken, Status-Wörter und Symbole in einer Zeile werden nicht einzeln gelesen. Zustand nie nur über Farbe.
- Textkontrast (`textContrastGuideline`) ist in Light, Dark und OLED grün, auch mit gedrückter Karte, mit Status-Wörtern und mit dem Hinweis „Nicht heute“.
- Bewegung: der Ring und die Balken laufen über `AppMotion` (bei reduzierter Bewegung sofort); die Seite nutzt `appRoute`, der Seitenübergang folgt „Reduzierte Bewegung“.

### 12.8 Tests und Nachweise

Befehl: `flutter test test/features/dashboard test/app/route_sweep_test.dart test/app/route_guard_test.dart test/app/router_guards_test.dart`. Der Stand des Gesamtlaufs steht in [test-report.md](../test-report.md) (vom Koordinator geführt).

| Datei | Fälle | Abnahme-IDs |
|---|---:|---|
| `test/features/dashboard/domain/goals_day_test.dart` | 47 | C04 |
| `.../presentation/goals_today_screen_test.dart` | 54 | AT33, AT34, AT35, C04, C06, Q01, Q02 |
| `.../presentation/goals_today_flow_test.dart` | 14 | AT23, AT33, C02, C03, C04 |
| `.../presentation/day_overview_card_tap_test.dart` | 26 | AT33, AT34, AT35, C04, Q02 |
| `test/app/route_sweep_test.dart` (die neue Route) | 19 | AT33, AT35 |
| `test/app/router_guards_test.dart` (neuer Fall `/goals/today`) | 1 | C02 |

- Die Zahlen: `goals_day_test.dart` prüft das Modell rein (fünf Stände, anwendbare und nicht anwendbare Ziele, Gewohnheiten, Reihenfolge, Texte jedes Standes und der Vergangenheit, Workout in allen Zuständen, Wochenziel getrennt), darunter einen Eigenschaftstest über den ganzen Bereich („100 %“ steht genau dann, wenn das Ziel erreicht ist) und den Vergleich der Prozentregel mit `waterPercent` und `StepsProgress.percent`. `goals_today_screen_test.dart` zeigt die Seite in allen Zuständen mit Tagesstatus-Überschreibung (Texte, Ring-Bögen, Zeilen), mit Ruhetag, Überspringen, Workout, Gewohnheiten und Wochenziel, die Sprechtexte, vier Breiten bei 100 und 200 % mit den Richtlinien, drei Themes mit `textContrastGuideline`, Laden, Fehler mit Wiederholen und den Zustand „Nicht heute“. `goals_today_flow_test.dart` läuft in der echten App: Tipp auf die Karte, Zurück (Pfeil, Systemzurück, Direktaufruf, Scrollposition), Home und Seite sagen in jedem Stand dasselbe „x von y“ und malen denselben Ring (die Bögen werden gelesen, wie sie gemalt werden), ein gespeichertes Gewicht ändert Ring und Seite zugleich, ein ausgeschaltetes Modul nimmt sein Ziel aus Ring und Seite.
- Der Routen-Durchlauf (`route_sweep_test.dart`) enthält `/goals/today` in der Liste der Kernrouten (fünf Größen, zwei davon mit einem Monat Daten, dunkel und OLED) und in der Gruppe der Seiten, die sich mit „Workout heute“ ändern (Ruhetag, Überspringen, Workout und offen, bei 320 px mit 200 % und bei 393 px, dunkel und OLED).
- Mutationsproben (lokal, nicht eingecheckt; Produktivcode vorübergehend geändert, danach mit `git checkout` zurückgesetzt). Zahlen: „anwendbar“ zählt alle Ziele statt der anwendbaren (5 scheiternde Tests), Zeilen enthalten auch nicht anwendbare Ziele (4), „erreicht“ fällt um eins zu klein aus (31), das Wochenziel zählt im Ring mit (26), Prozent liest 100 vor dem Ziel (4), Wasser in Millilitern statt Litern (8), Zeilen in der Reihenfolge des Tagesstatus statt des Editors (2), der Ruhetag behält den Status „Erreicht“ (2), Gewohnheiten fehlen (15). Navigation: die Karte ohne Tippaktion (11), der Zurück-Pfeil der Seite ohne Wirkung (mindestens 1, danach hing der Lauf), die Route nicht registriert (2 in den Routentabellen, danach hing der Lauf), „Ziele festlegen“ ohne Ziel (1). Karte: der Ring wird zusätzlich vorgelesen (4), kein gedrückter Zustand (4), kein Pfeil (9), der Sprechtext ohne Zahlen (7). Bei den beiden Mutationen mit scheiternden Tests der echten App endete der Lauf von `flutter test` nicht (er blockierte nach den ersten Fehlern und wurde nach 75 Sekunden abgebrochen); gezählt sind die bis dahin gemeldeten Fehler.
- Visueller Vergleich (Q03): `goals_today_visual_test.dart` schreibt mit `GOALS_TODAY_PNG=1` Bilder nach `build/goals_today/` (Hell, Dunkel, OLED, 200 % bei 320 und 393 px, mit Ruhetag und Wochenziel, ohne Ziel, vergangener Tag, Karte auf Home und gedrückt); sie wurden gegen die Knoten aus 12.1 verglichen, die Abweichungen stehen in 12.6.

### 12.9 Übergabe an BS-93 (vergangene Tage) und offene Punkte

- BS-93 baut auf der Seite auf: `buildGoalsDay` nimmt den Status **irgendeines** Tages (`isToday` folgt aus Datum und heute), `GoalsDayView` zeigt für einen anderen Tag den Hinweis „Nicht heute“ und nimmt `onBackToToday`. Offen für BS-93: `DashboardView.dayStatus` für den gewählten Tag füllen, `onBackToToday` an der Seite verdrahten und für den Tag die Quellen von Workout (`workoutOutcome`) und Gewohnheiten liefern; ohne `workoutOutcome` sagt eine erreichte Workout-Zeile „Eintrag vorhanden“. Der Satz „Du hast heute …“ der Home-Karte ist an heute gebunden (BS-121).
- Nur Host-Tests: nichts davon ist auf einem Gerät gesehen (TalkBack, VoiceOver, Systemschrift); BS-107 bleibt offen. Der Sichtvergleich mit Figma war per Augenschein an im Host gerenderten Bildern (Hell, Dunkel, OLED mit 393 px, 200 % mit 320 und 393 px), kein Pixelvergleich; `goals_today_visual_test.dart` schreibt die Bilder mit `GOALS_TODAY_PNG=1` nach `build/goals_today/` (nicht im Repository).
