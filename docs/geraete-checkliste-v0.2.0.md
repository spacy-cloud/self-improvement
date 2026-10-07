# Geräte-Checkliste für v0.2.0

Prüfpunkte für das **Samsung S25** (Android, TalkBack) und das **iPhone** (iOS, VoiceOver). Die Liste fasst die Geräte-Checklisten der Tickets und der Screen-Dokumente zusammen, ohne Doppelungen und nach Funktionen geordnet. **Es ist noch kein Punkt geprüft:** Alle Ergebnisspalten sind leer, die Host-Tests und der CI-Build belegen die Logik und die Oberfläche mit Fakes, nicht das Verhalten auf einem Gerät ([test-report.md](test-report.md), Abschnitt 7).

## So wird die Liste benutzt

- **Ergebnis** je Punkt und Gerät in den Spalten „S25“ und „iPhone“: `ok`, `Fehler` (mit einer Beschreibung in „Hinweis“) oder `nicht geprüft`. Eine leere Zelle heißt: noch nicht eingetragen. Ein `–` heißt: Der Punkt gilt für dieses Gerät nicht.
- **Hinweis:** was aufgefallen ist (Beobachtung, Version, Bildschirmaufnahme, Ticket). Befunde werden eigene Tickets; das Ergebnis geht danach in [test-report.md](test-report.md) (Abschnitt 7) und, wenn es eine Grenze ist, in [known-limitations.md](known-limitations.md).
- **Daten:** Nur eigene Testdaten oder die synthetischen Demo-Daten ([erste-tests.md](erste-tests.md)); keine echten Gesundheitsdaten in Hinweise, Bildschirmaufnahmen oder Tickets schreiben.
- Die Erwartungen stammen aus den Screen-Dokumenten und den Entscheidungen ([implementation-decisions.md](implementation-decisions.md)); weicht das Gerät ab, ist das ein Befund, nicht ein Fehler der Liste.

| Angabe | S25 | iPhone |
|---|---|---|
| Gerät und Systemversion | | |
| App-Stand (Quelle, Version, Datum) | | |
| Schrift, Design, Bedienhilfe beim Prüfen | | |
| Geprüft am | | |

## 0. Vorab

Diese Schritte stehen vor allem anderen:

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| V1 | In der installierten Version v0.1.0 eine **Sicherung exportieren** (Profil, Zahnrad, „Daten & Sicherung“, „Jetzt exportieren“) und die Datei außerhalb der App ablegen. Schema 2 liest v0.1.0 nicht, ein Zurück gibt es nicht. | Die Datei `self-improvement-backup-…json` liegt außerhalb der App. | | | |
| V2 | **Update über die vorhandene Installation:** Android die APK (Artefakt `debug-apk`) mit `adb install -r` installieren, iPhone die IPA (Artefakt `ios-ipa-unsigned`) mit SideStore. | Die App startet, Daten und Einstellungen sind wie vorher. Lehnt das System das Update ab (andere Signatur), ist das ein Befund: Dann deinstallieren, installieren und die Sicherung importieren (U3). | | | |
| V3 | **Health Connect** gibt es nur auf Android. Auf dem S25 prüfen, ob Health Connect installiert ist und Samsung Health Schritte dorthin schreibt (Samsung Health, Einstellungen, Health Connect). | Health Connect ist vorhanden; die Schritte erscheinen dort. | | – | |
| V4 | Daten für die Prüfung bereithalten: ein Profil, das älter als sieben Tage ist, an mehreren Tagen Einträge, mindestens ein erreichtes und ein offenes Tagesziel, eine Gewohnheit und zwei Aufgaben. Am schnellsten: die Demo-Daten importieren. | Home zeigt Ring, Karten und die Tage davor. | | | |

## 1. Update und Daten (BS-98)

Bezug: Datenvertrag v2 (Schema 2, Backup 2), [backup-format.md](backup-format.md), [known-limitations.md](known-limitations.md).

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| U1 | Nach dem Update alle Bereiche ansehen: Profil, Gewicht, Wasser, Schritte, Mahlzeiten, Workouts, Aufgaben, Gewohnheiten, Ziele, Module, Reihenfolge der Karten. | Alles ist wie vor dem Update. | | | |
| U2 | Die neuen Felder prüfen: vorhandene Schrittwerte, Schalter „Schritte aus Health übernehmen“, eine Aufgabe, ein früherer Tag. | Schrittwerte stehen als „Von Hand“, der Health-Schalter ist aus (nur Android), keine Aufgabe hat eine Erinnerung, kein Tag ist als Ruhetag oder übersprungen markiert. | | | |
| U3 | Auf einer frischen Installation die Sicherung aus v0.1.0 importieren („Daten & Sicherung“, „Sicherung auswählen“). | Die Vorschau zeigt als Format „Version 1“; nach „Ersetzen und wiederherstellen“ sind die Daten da. | | | |
| U4 | In v0.2.0 exportieren und dieselbe Datei wieder importieren. | Der Export öffnet das Teilen-Menü (iPhone: Teilen-Blatt); die Dateiauswahl findet die Datei; die Daten sind danach unverändert. | | | |
| U5 | Die App aus der Übersicht wegwischen und neu öffnen. | Daten und Einstellungen bleiben (echtes Prozessende). | | | |
| U6 | „Über die App“ öffnen (Einstellungen, Zeile „Version“). | „Daten-Schema 2 · Backup-Format 2“. | | | |

## 2. Ziele heute und Tagesring (BS-100, BS-103 bis BS-105, BS-121)

Bezug: [screens/dashboard-gamification.md](screens/dashboard-gamification.md) Abschnitt 12 und Abschnitt 6, Entwürfe in [design-handoff.md](design-handoff.md) Abschnitt 10. Voraussetzung: Profil nicht am ersten Tag, mindestens ein Ziel erreicht und eines offen, eine Gewohnheit angelegt.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| Z1 | Home mit dem Screenreader durchwischen (TalkBack, VoiceOver). | Reihenfolge: Datum, „Dein Tag im Überblick“ als Überschrift, die Karte, danach die Karten der Module. Die Karte ist **ein** Element (kein Ring, Titel und Satz einzeln). | | | |
| Z2 | Die Karte ansagen lassen. | „Ziele heute, 2 von 4 erreicht, Details öffnen“ (mit den echten Zahlen), Rolle Schaltfläche. | | | |
| Z3 | Die Karte per Doppeltipp öffnen. | Die Seite „Ziele heute“ öffnet; der Fokus liegt am Anfang der Seite. | | | |
| Z4 | Die Seite durchwischen. | Zurück, „Ziele heute“, die Kopfkarte als ein Element, „Tagesziele“, die Zeilen in der Reihenfolge Wasser, Schritte, Fokus, Gewicht, (Workout), Aufgabe, Gewohnheiten, dann „Wochenziel · nicht im Tagesring“ mit seiner Zeile, zuletzt „Ziele bearbeiten“. | | | |
| Z5 | Eine Zeile ansagen lassen. | Zum Beispiel „Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen, öffnen“, Rolle Schaltfläche; Balken, Status-Wort und Symbol werden nicht einzeln angesagt. | | | |
| Z6 | Die Zeile „Wasser“ öffnen, einen Eintrag speichern, zurückgehen (Schaltfläche und Zurück-Geste). | Zurück führt zur Seite „Ziele heute“; die Zahlen sind aktuell; der Fokus ist nicht verloren. | | | |
| Z7 | „Aufgabe erledigen“ oder eine Gewohnheit öffnen. | Der Tab „Habits“ öffnet; Zurück führt nach Home (dokumentierte Grenze). | | | |
| Z8 | „Ziele bearbeiten“ öffnen und zurückgehen. | Der Zieleditor öffnet; Zurück zeigt „Ziele heute“. | | | |
| Z9 | Mit eingeschaltetem „Workout heute“ und einem Ruhetag die Seite ansehen. | Zeile „Workout heute“ mit „Ruhetag“, angesagt als „Workout heute, Ruhetag, zählt als erreicht, keine XP, die Streak bleibt, öffnen“. | | | |
| Z10 | Von „Ziele heute“ zurück nach Home. | Home steht wie vorher (gleiche Scrollposition), die Zahlen stimmen. | | | |
| Z11 | Eine Zeile mit dem Finger halten und wegziehen. | Es öffnet sich nichts. | | | |
| Z12 | Den Tagesring bei 0, bei teilweise und bei allen erreichten Zielen ansehen (Hell, Dunkel, OLED). | 0 erreicht: grauer Ring ohne Bogen; teilweise: gelber Bogen; alle erreicht: voller grüner Ring; der Titel der Karte passt zum Stand; „x von y“ im Ring und der Satz darunter sagen dasselbe wie die Farbe. | | | |
| Z13 | Den gedrückten Zustand der Karte beim Halten ansehen. | Grüne Tönung und grüner Rand sind sichtbar. | | | |
| Z14 | Das Ringgrün in Hell gegen die Kartenfläche ansehen. | Der Ring ist erkennbar (gerechnet 2,66:1, unter 3:1); ist er es nicht, ist das ein Befund zu D-026. | | | |

## 3. Home blättert durch die Tage (BS-93)

Bezug: [screens/dashboard-gamification.md](screens/dashboard-gamification.md) Abschnitt 13. Voraussetzung: Profil seit mehr als sieben Tagen, an mehreren Tagen Einträge in den Karten, ein Ruhetag mit „Workout heute“.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| T1 | Home öffnen, Datum und Pfeile ansehen. | Zeile mit Datum und zwei Pfeilen, darunter „Dein Tag im Überblick“; der Pfeil nach rechts ist deaktiviert. | | | |
| T2 | Mit dem Finger nach rechts wischen. | Der Vortag erscheint mit „Nicht heute“ und „Zurück zu heute“; die Karten zeigen den Vortag; der Tag blendet kurz von links ein. | | | |
| T3 | Nach links wischen. | Zurück zum heutigen Tag, der Hinweis verschwindet. | | | |
| T4 | Senkrecht scrollen und schräg ziehen. | Die Seite scrollt, es wechselt kein Tag. | | | |
| T5 | Sieben Tage zurück, dann weiter. | Beim ältesten Tag (vor 7 Tagen) stoppt der Wisch, der linke Pfeil ist deaktiviert. | | | |
| T6 | Vom linken Rand wischen (Systemgeste Zurück). | Das System handelt, Home wechselt keinen Tag. | | | |
| T7 | Mit dem Screenreader den Pfeil „Vorheriger Tag“ per Doppeltipp auslösen. | Der Tag wechselt, die Ansage nennt ihn („Freitag, 2. Oktober, gestern“), der Fokus bleibt am Pfeil. | | | |
| T8 | Mit dem Screenreader durch den vergangenen Tag wischen. | Datum (Überschrift), Hinweis, der Ring als **ein** Knopf („Ziele dieses Tages, …“), Karten ohne Schnellzugriffe. | | | |
| T9 | „Zurück zu heute“ per Doppeltipp auslösen. | Heute erscheint, der Fokus liegt am Datum, die Ansage nennt „heute“. | | | |
| T10 | VoiceOver: den Rotor „Überschriften“ benutzen. | Das Datum ist über den Rotor erreichbar. | – | | |
| T11 | Karten an einem vergangenen Tag antippen (Wasser, Schritte, Gewicht, Workout, Fokus, Ernährung, XP). | Die Seite des Moduls öffnet; auf der Karte selbst gibt es nichts zum Eintragen. | | | |
| T12 | Den Ring antippen, auf „Ziele heute“ „Zurück zu heute“ wählen. | Die Seite zeigt den Tag mit „Nicht heute“, danach heute; Zurück führt nach Home auf heute. | | | |
| T13 | Ein Ziel „ab morgen“ ändern und am nächsten Tag den Vortag ansehen. | Der Vortag behält seine Ziele (Ring, Karte, „Ziele heute“). | | | |
| T14 | Die App über Mitternacht im Hintergrund lassen, zurückkehren. | Home zeigt den neuen Tag, nicht den gestern gewählten. | | | |

## 4. Heute abhaken (BS-110)

Bezug: [screens/tasks-habits.md](screens/tasks-habits.md) Abschnitt 2a. Voraussetzung: zwei Aufgaben und drei Gewohnheiten.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| H1 | Home ansehen. | Zwischen „Fokus“ und „Ernährung“ steht „Heute abhaken“; Aufgaben mit eckigem Kästchen und Chip „Aufgabe“, Gewohnheiten mit rundem Kästchen, Chip „Gewohnheit“ und Serie darunter. | | | |
| H2 | Eine Gewohnheit auf Home abhaken. | Das Kästchen füllt sich, die Snackbar „Abgehakt“ mit „Rückgängig“ (8 s) erscheint, der Zähler „x von y erledigt“ steigt; „Rückgängig“ nimmt es zurück; die XP-Karte folgt (+5 und zurück). | | | |
| H3 | Den Tab „Habits“ öffnen, dort eine andere Gewohnheit abhaken, zurück zu Home. | Beide Orte zeigen denselben Stand. | | | |
| H4 | Zweimal schnell auf dasselbe Kästchen tippen. | Genau ein Haken und eine Snackbar. | | | |
| H5 | Eine Aufgabe auf Home erledigen, das Kästchen erneut tippen. | Durchgestrichen mit „Erledigt um hh:mm“ und Snackbar „Aufgabe erledigt“; der zweite Tipp öffnet sie wieder. | | | |
| H6 | Eine Zeile (nicht das Kästchen) tippen. | Die Aufgabe zum Bearbeiten oder das Gewohnheitsdetail öffnet; Zurück führt zu Home mit demselben Stand. | | | |
| H7 | Mit dem Screenreader die Karte durchgehen. | Überschrift „Heute abhaken“; je Zeile ein Kontrollkästchen („Gewohnheit Lesen, heute offen“, Doppeltippen schaltet) und eine Schaltfläche („… Öffnet die Gewohnheit“); Aufgaben entsprechend mit „Aufgabe …“. | | | |
| H8 | Systemschrift auf die größte Stufe. | Kästchen und Chip stehen in der ersten Zeile, der Titel darunter, kein Wort bricht mitten im Wort, alles lässt sich antippen. | | | |
| H9 | Dunkel und OLED. | Kästchen, Chips und Linien sind lesbar. | | | |
| H10 | Sechs oder mehr Gewohnheiten und mehr als drei offene Aufgaben anlegen. | Fünf Gewohnheitszeilen und „und N weitere Gewohnheiten“ (öffnet den Tab), drei Aufgaben und „und N weitere Aufgaben“ (öffnet die Liste). | | | |
| H11 | Ohne Gewohnheit (nur Aufgaben), dann ohne alles. | Hinweis „Noch keine Gewohnheit“ mit „Gewohnheit anlegen“; ohne alles ein Text mit beiden Aktionen. | | | |
| H12 | Das Modul „Aufgaben und Gewohnheiten“ ausschalten und einschalten; „Karten anpassen“ ansehen. | Die Karte verschwindet und kommt mit dem alten Stand zurück; in „Karten anpassen“ heißt sie „Aufgaben und Gewohnheiten“. | | | |
| H13 | Über Mitternacht offen lassen (oder den Tag wechseln). | Gewohnheiten sind wieder offen, gestern erledigte Aufgaben sind weg. | | | |
| H14 | Nach dem Abhaken die Karte am unteren Rand weiter bedienen. | Die Snackbar verdeckt keine Tippfläche dauerhaft. | | | |

## 5. Workout heute (BS-99)

Bezug: [screens/focus-workouts.md](screens/focus-workouts.md) Abschnitt 9. Das Tagesziel ist standardmäßig aus und gilt nach dem Einschalten ab morgen.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| W1 | Profil, „Meine Ziele“: den Schalter „Workout heute“ einschalten. | Er steht zwischen „Gewicht erfassen“ und „Aufgabe erledigen“; Meldung „Ziele gespeichert. Sie gelten ab morgen.“ | | | |
| W2 | Am nächsten Tag Home ansehen. | Die Workout-Karte zeigt den Tag („Noch kein Training“, „Heute offen“) und die Aktion „Wie war dein Tag?“, keine Wochenzahlen. | | | |
| W3 | Das Sheet „Wie war dein Tag?“ öffnen und schließen (Schließen-Taste, Tipp daneben, Zurück). | Drei Antworten (Training eintragen, Ruhetag, Heute überspringen); Schließen ohne Antwort ändert nichts. | | | |
| W4 | „Ruhetag“ wählen. | Snackbar „Ruhetag eingetragen“ mit „Rückgängig“; die Karte zeigt „Ruhetag“ mit „Zählt als erreicht, keine XP. Die Streak bleibt.“; „Rückgängig“ auf der Karte nimmt es zurück. | | | |
| W5 | Ein Training eintragen. | Die Karte zeigt das Training mit Häkchen; Ruhetag und Überspringen werden nicht mehr angeboten. | | | |
| W6 | Den Workout-Bereich öffnen. | Über der Wochenkarte steht die Karte „Heute“, unten die Zeile „Tagesziel „Workout heute““; das Wochenziel zählt nur echte Workouts. | | | |
| W7 | Mit dem Screenreader Karte und Sheet bedienen. | Die Karte wird als eine Schaltfläche mit Zustand gelesen; das Sheet ist ein benannter Bereich, jede Antwort eine Schaltfläche. | | | |
| W8 | Beim Markieren auf die Reihenfolge von Snackbar und Sheet achten. | Die Snackbar verdeckt nichts und wird nicht verschluckt (offene Frage der Doku). | | | |

## 6. Plus-Menü nach Zielen (BS-117)

Bezug: [screens/shell.md](screens/shell.md) Abschnitt 6, D-022.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| P1 | Das Plus öffnen, wenn alle Ziele an sind. | Alle acht Einträge in fester Reihenfolge: Gewicht, Workout, Wasser, Schritte, Fokus, Aufgabe, Gewohnheit, Mahlzeit. | | | |
| P2 | Unter „Meine Ziele“ ein Ziel ausschalten (zum Beispiel Wasser), das Plus erneut öffnen. | Der Eintrag fehlt, darunter steht „Nicht dabei? Unter Profil · Meine Ziele legst du fest, was hier erscheint.“ | | | |
| P3 | Das Ziel wieder einschalten. | Der Eintrag steht an seiner gewohnten Stelle. | | | |
| P4 | Alle Ziele ausschalten. | Leerzustand „Noch nichts zum Eintragen“ mit „Meine Ziele öffnen“; die Schaltfläche öffnet die Zielseite, Zurück führt zum Tab. | | | |
| P5 | Den Leerzustand mit dem Screenreader lesen. | Titel und Erklärung als ein Block, „Meine Ziele öffnen“ als beschriftete Schaltfläche. | | | |
| P6 | Nur „Workout heute“ einschalten, das Wochenziel ausschalten. | Der Eintrag „Workout“ erscheint. | | | |
| P7 | Ein Ziel ändern und das Plus erneut öffnen, ohne die App neu zu starten. | Das Menü folgt dem gespeicherten Stand der Ziele ohne Neustart (auch wenn die Änderung erst ab morgen für den Tagesring gilt). | | | |
| P8 | Systemschrift auf die größte Stufe, Leerzustand ansehen. | Hinweis und Schaltfläche sind erreichbar, das Sheet scrollt. | | | |
| P9 | Das Symbol der Zielscheibe im Leerzustand gegen den Entwurf ansehen. | Erkennbar als Ziel; die Optik des Material-Symbols ist akzeptabel (Abweichung zum Figma-Vektor). | | | |

## 7. Erinnerungen und Erinnerung je Aufgabe (BS-111, BS-113)

Bezug: [screens/tasks-habits.md](screens/tasks-habits.md) Abschnitt 2, [screens/data-reminders.md](screens/data-reminders.md), [known-limitations.md](known-limitations.md). Vorbereitung: frische Installation, Onboarding abschließen. Erinnerungen sind „ungefähr zur Zeit“; einige Minuten Abweichung sind kein Fehler.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| E1 | Eine Aufgabe anlegen und „Morgen 09:00“ wählen (Erinnerungen sind noch aus). | Hinweis „Erinnerungen sind ausgeschaltet“; „Einstellungen öffnen“ führt zu den Einstellungen, Zurück ins Formular mit unveränderter Eingabe; Speichern geht. | | | |
| E2 | In den Einstellungen „Erinnerungen“ einschalten, im Sheet „Weiter zur Systemabfrage“ wählen, die Abfrage erlauben. | Die Texte nennen weder Android noch iOS; zurück im Formular ist der Hinweis weg, es steht „Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.“ | | | |
| E3 | Die Abfrage ablehnen oder die Erlaubnis in den Systemeinstellungen entziehen. | „Benachrichtigungen sind nicht erlaubt“; „Systemeinstellungen öffnen“ öffnet die Einstellungen dieser App; nach dem Erlauben und Zurückkehren verschwindet der Hinweis; die Aufgabe hat ihre Erinnerung behalten. | | | |
| E4 | Eine Erinnerung auf etwa zwei Minuten später stellen (Dialoge für Datum und Uhrzeit). Je einmal bei App im Vordergrund, im Hintergrund und nach Wegwischen aus der Übersicht abwarten. | Benachrichtigung „Erinnerung an deine Aufgabe“, **kein Aufgabentitel**, auch auf dem Sperrbildschirm; auf dem iPhone prüfen, ob im Vordergrund ein Banner erscheint. | | | |
| E5 | Die Benachrichtigung antippen (in allen drei Fällen). | Die App öffnet im Formular „Aufgabe bearbeiten“ dieser Aufgabe; Zurück führt zum Dashboard (Kaltstart) beziehungsweise zur vorherigen Seite; bei einem offenen Formular derselben Aufgabe passiert nichts, eine Eingabe bleibt. | | | |
| E6 | Vor dem Zeitpunkt die Aufgabe erledigen, „Rückgängig“ tippen, löschen, „Rückgängig“ tippen, eine erledigte Aufgabe wieder öffnen. | Erledigen und Löschen: keine Benachrichtigung; „Rückgängig“ und Wiederöffnen: sie ist wieder geplant. | | | |
| E7 | Die Zeit ändern; „Erinnerung entfernen“ und speichern; „Rückgängig“ in der Snackbar. | Nur die neue Zeit zählt; nach dem Entfernen keine Benachrichtigung; „Rückgängig“ bringt sie zurück. | | | |
| E8 | Eine angezeigte Benachrichtigung stehen lassen, die Aufgabe löschen, die Benachrichtigung antippen. | Die Aufgabenliste (Ansicht „Aufgaben“) öffnet. | | | |
| E9 | In den Einstellungen „Geplante Erinnerungen“ ansehen und eine Zeile antippen. | Die Erinnerung steht mit dem Symbol der Aufgabe da, der Tipp öffnet das Formular. | | | |
| E10 | Die Zeitzone des Geräts wechseln; am Gerätedatum 29.03. eine Uhrzeit wählen, die es nicht gibt (02:30). | Die Erinnerung kommt zum selben Zeitpunkt (andere Ortszeit), das Formular zeigt die neue Ortszeit; bei 02:30 die Meldung „Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. …“. | | | |
| E11 | Eine Aufgabe mit Erinnerung anlegen, exportieren, alle Daten zurücksetzen, die Sicherung importieren. | „Geplante Erinnerungen“ zeigt die Erinnerung wieder, sie wird zugestellt (die Berechtigung kommt vom System, nicht aus der Datei). | | | |
| E12 | Das Gerät neu starten; danach die App beenden erzwingen und öffnen. | Android: Die Erinnerung bleibt nach dem Neustart; nach dem erzwungenen Beenden wird sie beim Öffnen neu geplant und zugestellt. iPhone: nur der Neustart. | | | |
| E13 | Alle fünf Trink-Uhrzeiten, mehrere Gewohnheiten mit Uhrzeit und eine Aufgabe in zehn Tagen einstellen. | In den Einstellungen und im Formular erscheint „Bei sehr vielen Erinnerungen wird nur ein Teil im Voraus geplant …“; nach einigen Tagen mit geöffneter App wird die ferne Erinnerung geplant. | | | |
| E14 | Energiesparen (Samsung): Ruhezustand und „Schlafende Apps“ prüfen. | Die Zustellung kann sich verzögern oder ausbleiben (Grenze der lokalen Erinnerungen). | | – | |
| E15 | Den ganzen Ablauf der Berechtigung lesen (Sheet, Banner, Meldungen, Fußzeile). | Nirgends steht „Android“, „iOS“, „iPhone“ oder „iPad“; es heißt „System“ oder „Gerät“. | | | |
| E16 | Mit dem Screenreader und bei größter Systemschrift den Block „Erinnerung“ im Formular bedienen. | Der Block wird als Gruppe gelesen (Chips mit Auswahlzustand, das Feld als Schaltfläche, der Hinweis als eine Nachricht); alle Ziele sind gut zu treffen; Dunkel und OLED. | | | |

## 8. Schritte aus Health und Schritte-Karte (BS-97, BS-108)

Bezug: [screens/body-weight-steps.md](screens/body-weight-steps.md) Abschnitt 2.3, [known-limitations.md](known-limitations.md). Die Health-Anbindung gibt es nur auf Android (Health Connect).

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| S1 | Die Einstellungen auf dem iPhone ansehen. | Die Gruppe „Schritte“ mit dem Schalter fehlt. | – | | |
| S2 | App starten, Einstellungen öffnen. | Die Gruppe „Schritte“ mit dem Schalter „Schritte aus Health übernehmen“ ist da und aus; es gab keine Abfrage. | | – | |
| S3 | Den Schalter einschalten und im Erklärtext „Nicht jetzt“ wählen. | Der Erklärtext erscheint vor jedem Systemdialog; der Schalter bleibt aus; kein Systemdialog. | | – | |
| S4 | Den Schalter einschalten und „Weiter zur Systemabfrage“ wählen. | Der Dialog von Health Connect nennt nur „Schritte“ und nur Lesen (kein Schreiben, kein anderer Datentyp). | | – | |
| S5 | Den Dialog bestätigen. | Die letzten sieben Tage erscheinen in „Meine Schritte“; je Tag gleicht der Wert der Tagessumme in Health Connect (Abweichung nur durch den Zeitpunkt). | | – | |
| S6 | Handy und Uhr (oder zwei Apps) schreiben Schritte für denselben Tag. | Der Tageswert gleicht der Summe in Health Connect und zählt nichts doppelt. | | – | |
| S7 | Schritte um 23:55 und um 00:05 gehen; am Tag der Zeitumstellung vergleichen. | Sie stehen an zwei verschiedenen Tagen; am Tag der Zeitumstellung gleicht der Tageswert der Summe in Health Connect. | | – | |
| S8 | Einen Tag von Hand überschreiben, danach aktualisieren. | Der Wert von Hand bleibt, die Quelle ist „Von Hand“; andere Tage aktualisiert Health weiter. | | – | |
| S9 | Die App in den Hintergrund, 500 Schritte gehen, die App öffnen. | Der heutige Wert ist ohne Aktion aktualisiert; die Aktion „Aktualisieren“ macht dasselbe. | | – | |
| S10 | In Health Connect den Zugriff der App entziehen, die App öffnen. | Der Hinweis „Kein Zugriff“ erscheint, die Werte bleiben; „Zugriff erlauben“ führt zum Dialog oder (nach zwei Ablehnungen) in die Einstellungen von Health Connect. | | – | |
| S11 | Health Connect fehlt oder ist veraltet (Gerät mit Android 13 oder älter). | Der Hinweis nennt den Zustand ehrlich; „Health Connect installieren“ öffnet den Store. | | – | |
| S12 | Im Systemdialog „Datenschutzrichtlinie“ antippen. | Die Seite „Schritte aus Health Connect“ öffnet sich (Datenschutz-Erklärung der App). | | – | |
| S13 | Eine Sicherung exportieren, auf demselben Gerät importieren, danach den Zugriff entziehen. | Der Schalter bleibt an, der Zustand folgt dem Zugriff dieses Geräts; nach dem Entziehen steht „Kein Zugriff“. | | – | |
| S14 | Den Schalter ausschalten. | Nichts liest mehr; vorhandene Werte bleiben. | | – | |
| S15 | `adb shell dumpsys package de.lf10.selfimprovement` ausführen. | Als angeforderte Rechte stehen nur Benachrichtigungen, die Wiederherstellung nach dem Neustart und `android.permission.health.READ_STEPS`; kein Internet. | | – | |
| S16 | Die Karte „Schritte“ auf Home mit einem Wert aus Health ansehen. | Quelle „Health · Uhrzeit“, die Aktualisieren-Taste (48 x 48) gleicht ab, ein Tipp auf den Kartenkörper öffnet „Meine Schritte“. | | – | |
| S17 | Auf allen Geräten: nach dem ersten Schritteeintrag des Tages die Karte ansehen (BS-108). | Die Aktion bleibt sichtbar und heißt „Schritte aktualisieren“ (ohne Plus); sie öffnet das Formular für heute, Speichern ersetzt den Wert. | | | |
| S18 | Einen Tag aus Health im Formular öffnen. | Die Hinweiskarte nennt Health und dass dein Wert danach gilt; nach „Tageswert ersetzen“ steht „Von Hand“. | | – | |
| S19 | TalkBack: Schalter, Erklärtext, Hinweiskarten und Karte auf Home durchgehen. | Der Schalter heißt „Schritte aus Health übernehmen“ mit seinem Zustand, der Erklärtext wird mit seiner Frage als Name angesagt, Hinweise werden beim Erscheinen angesagt, die Aktualisieren-Taste nennt „Schritte aus Health Connect aktualisieren“. | | – | |
| S20 | Systemschrift auf 200 %, Hell, Dunkel und OLED. | Gruppe, Sheet, Hinweise und Karten brechen um, nichts wird abgeschnitten, Warnungen tragen Symbol und Text. | | – | |

## 9. Über die App und Lizenz (BS-118, BS-120)

Bezug: [screens/profile-settings.md](screens/profile-settings.md), D-020, D-021.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| I1 | Die Einstellungen ansehen. | Die Zeile „Version“ zeigt die Versionsnummer, einen Pfeil und lässt sich antippen (auch bei größter Schrift). | | | |
| I2 | Die Zeile „Version“ antippen. | Die Seite „Über die App“: App-Symbol, Name, Version mit Build, Autor, Website, Datenschutz, technische Angaben, Lizenzen; ganz unten der Lizenztext. Zurück führt in die Einstellungen. | | | |
| I3 | „Website“ antippen. | Der Browser öffnet `https://spacy.cloud/self-improvement`; Zurück führt in die App. | | | |
| I4 | Wenn möglich ohne Browser prüfen. | „Kein Browser gefunden. Die Adresse spacy.cloud/self-improvement wurde kopiert.“ | | | |
| I5 | „Lizenzen“ antippen. | Die Seite „Lizenzen“ öffnet. | | | |
| I6 | Den Lizenztext ganz unten bei Systemschrift 200 % lesen. | Er ist lesbar und scrollt bis zur letzten Zeile. | | | |
| I7 | Mit dem Screenreader die Seite bedienen. | Überschriften sind erreichbar; die Zeile „Website“ heißt „Website, spacy.cloud/self-improvement, öffnet im Browser“; der englische Lizenztext wird mit passender Stimme gelesen (Sprachmarkierung). | | | |
| I8 | Hell, Dunkel, OLED und „Reduzierte Bewegung“. | Alles lesbar; der Seitenwechsel folgt dem Schalter. | | | |

## 10. Tastatur und Ausrichtung (BS-112, BS-114)

Bezug: [screens/forms-keyboard.md](screens/forms-keyboard.md), D-018, D-019. Vor allem für das iPhone, dessen Zifferntastatur keine Eingabetaste hat.

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| K1 | „Gewicht eintragen“ öffnen, das Zahlenfeld fokussieren, neben das Feld tippen. | Die Tastatur schließt. | | | |
| K2 | Bei offener Tastatur die Seite ziehen (Start neben dem Cursor). | Die Tastatur schließt. | | | |
| K3 | Ein leeres, zentriertes Zahlenfeld (Gewicht, Wasser „Eigene Menge“) fokussieren und genau auf dem Cursor ziehen. | iPhone: Die Seite scrollt nicht, die Tastatur bleibt (dokumentierte Grenze); Tippen daneben schließt immer. Android: Schließen. | | | |
| K4 | Bei offener Tastatur „Speichern“ tippen. | Die Schaltfläche wirkt beim ersten Tipp. | | | |
| K5 | Zwischen zwei Feldern wechseln. | Die Tastatur verschwindet und erscheint nicht zwischendurch. | | | |
| K6 | Reicht die Zifferntastatur ohne „Fertig“-Leiste? | Antwort im Hinweis (ja oder Befund). | – | | |
| K7 | Android: die Zurück-Geste bei offener Tastatur. | Die Tastatur schließt. | | – | |
| K8 | Mit dem Screenreader eine Schaltfläche bei offener Tastatur aktivieren. | Die Schaltfläche arbeitet; die Tastatur schließt nicht von selbst (abgeleitet, nicht gesehen). | | | |
| Q1 | Das iPhone drehen und mehrere Seiten, ein Formular und das Plus-Menü ansehen. | Technisch bedienbar, kein Überlauf; ein Formular ist per Scrollen erreichbar und speicherbar; Drehen mitten in der Eingabe erhält sie. | – | | |
| Q2 | Im Querformat bei offener Tastatur ein Formular ansehen; die Höhe der Tastatur notieren. | Ab etwa 250 px Tastaturhöhe läuft die Seite über (dokumentierte Grenze); die echte Höhe steht im Hinweis. | – | | |
| Q3 | Notch und Dynamic Island im Hoch- und Querformat ansehen. | Nichts Wichtiges wird verdeckt (die Aussage des iOS-Testers war mehrdeutig). | – | | |

## 11. Allgemein: Darstellung, Barrierefreiheit, Bedienung

| Nr. | Schritt | Erwartung | S25 | iPhone | Hinweis |
|---|---|---|---|---|---|
| B1 | Die Systemschrift auf die größte Stufe stellen (Android: Schriftgröße und Anzeigegröße; iPhone: Größerer Text) und Home, ein Formular, ein Sheet ansehen. | Nichts wird abgeschnitten oder überlappt, alle Aktionen sind erreichbar, der Inhalt scrollt. | | | |
| B2 | Design Hell, Dunkel, OLED und System durchschalten. | Text ist überall lesbar; „System“ wählt nie OLED. | | | |
| B3 | „Reduzierte Bewegung“ einschalten, Seitenwechsel, Sheets und Snackbars ansehen. | Wechsel ohne Übergang (Datums- und Zeitwähler des Systems folgen nur dem Systemflag). | | | |
| B4 | Mit TalkBack beziehungsweise VoiceOver Home, ein Formular und das Plus-Menü durchgehen. | Beschriftungen, Zustände und Lesereihenfolge stimmen; Fehler werden angesagt. | | | |
| B5 | Android: den Systemzurück-Weg durchgehen (Modal, Unterseite, Home-Tab, System). | Die Reihenfolge stimmt; das vorhersagende Zurück ist nicht aktiv (Android 16). | | – | |
| B6 | Mit externer Tastatur oder Schalterzugriff Karten und Zeilen per Tab erreichen und mit Enter auslösen. | Karte, Zeilen, „Ziele bearbeiten“ und Zurück sind erreichbar, der Fokusrahmen ist sichtbar. | | | |
| B7 | Start und Scrollen der App beobachten. | Kein Ruckeln, der Start dauert nicht merklich länger als etwa 3 s (Planungsziel, nicht gemessen). | | | |

## 12. Zusammenfassung: noch nicht geprüft

Stand dieser Datei: **kein Punkt ist auf einem Gerät geprüft.** Die Zeilen zählen die Punkte je Bereich (ein `–` zählt nicht); wer Ergebnisse einträgt, aktualisiert diese Tabelle.

| Bereich | Punkte S25 | Punkte iPhone | Stand |
|---|---:|---:|---|
| 0. Vorab | 4 | 3 | nicht geprüft |
| 1. Update und Daten | 6 | 6 | nicht geprüft |
| 2. Ziele heute und Tagesring | 14 | 14 | nicht geprüft |
| 3. Home blättert durch die Tage | 13 | 14 | nicht geprüft |
| 4. Heute abhaken | 14 | 14 | nicht geprüft |
| 5. Workout heute | 8 | 8 | nicht geprüft |
| 6. Plus-Menü nach Zielen | 9 | 9 | nicht geprüft |
| 7. Erinnerungen und Erinnerung je Aufgabe | 16 | 15 | nicht geprüft |
| 8. Schritte aus Health und Schritte-Karte | 19 | 2 | nicht geprüft |
| 9. Über die App und Lizenz | 8 | 8 | nicht geprüft |
| 10. Tastatur und Ausrichtung | 7 | 10 | nicht geprüft |
| 11. Allgemein | 7 | 6 | nicht geprüft |

Auch mit dieser Liste nicht geprüft und nicht Teil der Zusage:

- Der **Release-Build** (mit Debug-Signatur) zur Laufzeit; weitere Geräte, Android-Versionen und iOS-Versionen.
- **Messwerte der Leistung** (Start etwa 3 s, Commit 300 ms, Scrollen mit 60 Hz, [AT36](requirements-matrix.md)): Punkt B7 ist eine Beobachtung, keine Messung.
- Ein **automatischer Bildvergleich** mit Figma: Die Entwürfe sind noch nicht freigegeben, der Sichtvergleich ist ein Augenschein.
- Das **Verhalten des Betriebssystems** im Energiesparmodus über Tage und die Zustellung bei sehr vielen Erinnerungen.
