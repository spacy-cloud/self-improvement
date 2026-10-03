# Demo-Skript (15 Minuten)

Ablauf für die Vorführung der App (Arbeitstitel „App-Name“): Vorbereitung, ein Weg durch die Screens mit je einem Satz zum Sagen, welche Anforderung oder welcher Abnahmefall der Schritt zeigt, was bei einem Fehler zu tun ist und was die Vorführung nicht behaupten darf. Alle Bezeichnungen stammen aus der laufenden App und den [Screen-Dokumenten](screens/); die Kürzel (C01, AT05 …) erklärt die [Anforderungsmatrix](requirements-matrix.md). Installation und Rundgang für eigene Tests beschreibt [erste-tests.md](erste-tests.md).

## 1. Vorbereitung

Rund eine halbe Stunde vorher, mit einem Probelauf des ganzen Weges (Zeit stoppen).

1. **Gerät.** Ein Android-Gerät oder ein Emulator (Android 8 oder neuer, empfohlen API 34), Systemsprache Deutsch, Schriftgröße Standard, Helligkeit hoch, Bitte-nicht-stören an. Die Vorführung ersetzt alle App-Daten: kein Gerät mit eigenen Daten verwenden. Bildschirmspiegelung für das Publikum einrichten.
2. **App installieren** (siehe [erste-tests.md](erste-tests.md), Weg A oder B). Eine frühere Version vorher deinstallieren, damit der Erststart mit dem Onboarding beginnt. Die Benachrichtigungs-Berechtigung nicht vorab erteilen.
3. **Demo-Daten besorgen.** Die Sicherungsdatei `demo-daten-90-tage.json` enthält 90 Tage synthetischer Daten über alle Module: Profil „Demo“, Gewicht (82 Einträge), Schritte (68 Tage), Wasser (280), Mahlzeiten (144), Fokus-Sitzungen (45), Workouts (26), Aufgaben (31), die Gewohnheiten „Lesen“, „Dehnen“ und „Spazieren“ mit 154 Haken. Die 90 Tage enden am Erzeugungstag: Am Tag der Vorführung lokal erzeugen, damit die Analyse-Zeiträume gefüllt sind (das CI-Artefakt `demo-backup` ist älter).

   ```bash
   flutter test test/tool/demo_backup_test.dart     # schreibt build/demo-backup/demo-daten-90-tage.json
   adb push build/demo-backup/demo-daten-90-tage.json /sdcard/Download/
   ```

4. **Rückfallebene.** Bildschirmaufnahme oder Screenshots des Probelaufs bereithalten. Die App braucht kein Netzwerk; ein WLAN ist nicht nötig.
5. **Ausgangszustand prüfen.** Die App startet auf dem Onboarding, die Datei liegt im Ordner „Download“ des Geräts, das Design steht auf „System“ (hell).

## 2. Ablauf

Die Zeiten sind Richtwerte; Schritte mit „optional“ entfallen bei Zeitnot.

| Min. | Schritt | Zum Sagen | Zeigt | Falls es hakt |
|---|---|---|---|---|
| 0:00 bis 1:30 | **Erststart und Onboarding.** App öffnen: neutrale Ladeseite, dann „Los geht’s“. Die vier Schritte (Ziele, Module, Körperdaten, Tagesziele) mit „Weiter“ durchgehen, einmal „Zurück“ (die Eingaben bleiben), mit „Fertig – los geht’s“ abschließen. Danach das leere Dashboard. | „Alles läuft lokal und offline. Das Onboarding ist freiwillig, speichert erst am Ende und zeigt keine erfundenen Werte.“ | C01, C02, C03, C07; AT01, AT02, AT04 | Bei Zeitnot auf dem Willkommen-Screen „Überspringen“ (speichert die Standardwerte). |
| 1:30 bis 3:00 | **Demo-Daten importieren.** Tab „Profil“, Zahnrad oben rechts, „Daten & Sicherung“, „Sicherung auswählen“, die Datei wählen. Die Vorschau zeigen (Erstellzeitpunkt, Zahl der Einträge, Inhalt je Bereich, Warnung „Vorhandene App-Daten (N Einträge) werden vollständig ersetzt“), dann „Ersetzen und wiederherstellen“. | „Die Sicherung ist eine strikt geprüfte JSON-Datei. Erst nach der Vorschau wird in einer Transaktion ersetzt, eine ungültige Datei ändert nichts.“ | C09; AT30, AT31 | Siehe „Import nicht möglich“ in Abschnitt 3. |
| 3:00 bis 5:00 | **Dashboard.** Tab „Home“: Tagesring, die Karten (Schritte, Wasser, Gewicht, Workout, Fokus, Aufgaben, Ernährung, XP), Streak. Am Ende „Karten anpassen“: eine Karte mit den Pfeiltasten verschieben, eine ausblenden und wieder einblenden. | „Alle Zahlen kommen aus der lokalen Datenbank und aktualisieren sich live. Karten lassen sich auch ohne Ziehen sortieren.“ | C04, C03; G02; AT02, AT34 (Teil: Sortieren ohne Geste) | Ist die Datei nicht vom Vorführtag, sind die Zeiträume der Analyse später teilweise leer: Datei neu erzeugen und erneut importieren. |
| 5:00 bis 7:30 | **Erfassen über das Plus.** Das Plus „Eintrag hinzufügen“ öffnen: acht Einträge. (a) Wasser: auf der Wasserkarte „+ 250 ml“ tippen, die Snackbar mit „Rückgängig“ zeigen (8 s) und einmal rückgängig machen: Menge und XP gehen zurück. (b) Gewicht: erst `71,55` (Hinweis am Feld), dann `71,5` mit „Eintrag speichern“. (c) Schritte: einen Wert eintragen; hat der Tag schon einen, steht dort „Beim Speichern wird der Tageswert ersetzt, nicht addiert.“ (d) Mahlzeit nur mit Name, ohne Kalorien. | „Jede Speicherung ist ein atomarer Befehl mit Rückgängig. Ungültige Eingaben bleiben am Feld stehen, nichts wird still gerundet.“ | N01, N02, W01, W03, C05; AT05, AT10, AT12, AT15 | Läuft die Snackbar ab, die Aktion wiederholen. Bei Zeitnot nur (a) und (b). |
| 7:30 bis 9:00 | **Fokus-Timer.** Plus, „Fokus“: Dauer und Kategorie, „Fokus starten“, auf dem Sitzungsbildschirm „Pausieren“ und „Fortsetzen“. Das Plus zeigt jetzt „Fokus fortsetzen“. „Beenden“ öffnet „Sitzung beenden?“ mit „Zeit speichern“, „Verwerfen“, „Weiter fokussieren“; „Zeit speichern“ nach unter fünf Minuten zeigt: Zeit gespeichert, keine XP. | „Der Timer rechnet aus gespeicherten Zeitsegmenten, nicht aus einem laufenden Zähler. Unter fünf Minuten gibt es Zeit, aber keine XP.“ | F01, F02; AT16, AT18 | App in den Hintergrund und zurück nur zeigen (optional), wenn es im Probelauf geklappt hat: Auf einem Gerät ist das nicht geprüft. Notfalls den Sitzungsbildschirm über „Fokus fortsetzen“ öffnen. |
| 9:00 bis 10:00 | **Habits und Aufgaben.** Tab „Habits“: eine Gewohnheit (zum Beispiel „Lesen“) abhaken, „Rückgängig“; Umschalter auf die Aufgaben, eine Aufgabe über das Plus anlegen („Aufgabe speichern“) und erledigen. | „Abhaken ist ein Soll-Zustand: Wieder öffnen und erneut abschließen häuft keine XP an.“ | T01, T02, G01; AT13, AT21 | Keine Aufgabe sichtbar: Filter „Offen“ oder „Alle“ wählen. |
| 10:00 bis 11:30 | **Analyse.** Tab „Analyse“: 7, 30 und 90 Tage, Vergleich mit der gleich langen Vorperiode, Abdeckung (zum Beispiel „5/7 Tage erfasst“), „Als Tabelle“. Bei Ernährung „Kalorien unvollständig“ (aus der Mahlzeit ohne Kalorien). | „Fehlende Tage zählen nie als Null, und jede Karte sagt, wie viele Tage erfasst sind.“ | A01; AT08, AT14, AT15, AT20, AT23 | Leere Karten ohne Daten sind ehrlich („Noch keine Daten“), kein Fehler. |
| 11:30 bis 12:30 | **Module und Ziele.** Zahnrad, „Module verwalten“: „Aufgaben & Gewohnheiten“ ausschalten. Im Tab „Habits“ steht „Aufgaben und Gewohnheiten sind ausgeschaltet“ mit „Aufgaben und Gewohnheiten aktivieren“, die Einträge bleiben. Wieder einschalten. Optional: „Meine Ziele“, die Änderung gilt ab morgen. | „Module lassen sich ausschalten, ohne dass Daten verloren gehen. Zieländerungen gelten ab morgen, nie rückwirkend.“ | C03, C07; AT03, AT04, AT19, AT24 | Läuft noch eine Fokus-Sitzung, wird das Ausschalten von „Fokus & Workouts“ mit einem Hinweis und dem Weg zur Sitzung verweigert; das ist gewollt und zeigt AT19. |
| 12:30 bis 13:30 | **Darstellung.** Einstellungen, „Design“: Hell, Dunkel, OLED, System; „Reduzierte Bewegung“ einschalten und einen Seitenwechsel zeigen. Optional die Systemschrift auf das Maximum stellen und Home zeigen. | „Drei Themes aus denselben Tokens; große Schrift lässt den Inhalt scrollen statt abzuschneiden.“ | C06, Q02, Q03; AT33, AT35 (nur Host-Teil belegt) | Die System-Datums- und Zeitwähler folgen nur dem Systemflag, nicht dem App-Schalter. |
| 13:30 bis 14:30 | **Export und Zurücksetzen (optional).** „Daten & Sicherung“, „Jetzt exportieren“: der Hinweis auf eine unverschlüsselte Datei, dann das Teilen-Menü zeigen und abbrechen. „Zurücksetzen …“: Das Wort `LÖSCHEN` eingeben, „Alles löschen“, danach das Onboarding. | „Die Sicherung verlässt das Gerät nur über das Teilen-Menü, die App lädt nichts hoch. Zurücksetzen verlangt das getippte Wort.“ | C09; AT30, AT32 | Nur als letzten Schritt: Das Zurücksetzen löscht die Demo-Daten. |
| 14:30 bis 15:00 | **Grenzen nennen** (Abschnitt 4) und Fragen. | „Das ist der Stand auf dem Rechner und im CI; ein Gerätetest steht noch aus.“ | Q01, Q02 | – |

## 3. Wenn etwas schiefgeht

| Problem | Was tun |
|---|---|
| Die App zeigt „Daten konnten nicht geöffnet werden“ | „Erneut versuchen“. Hilft das nicht: App neu installieren (die lokale Datenbank ist weg) und die Demo-Daten erneut importieren. Das ist kein Grund, Zahlen zu erklären, die nicht stimmen. |
| „Import nicht möglich“ in der Vorschau | Die Gründe nennen (die App zeigt Bereich und Position), über „Andere Datei wählen“ die Datei erneut wählen. Fehlt die Datei, per `adb push` erneut ablegen. Ohne Datei: das Dashboard mit zwei bis drei von Hand erfassten Einträgen (Wasser, Gewicht) vorführen und die Analyse auslassen. |
| Das System fragt unerwartet nach Benachrichtigungen | „Ablehnen“. Die App bleibt voll nutzbar und zeigt den Zustand ehrlich („Im System blockiert“ unter „Erinnerungen“); Erinnerungen sind in dieser Vorführung kein Thema. |
| Die Snackbar „Rückgängig“ ist verschwunden | Sie bleibt 8 Sekunden. Die Aktion einmal wiederholen. |
| Der Timer wirkt nach der Rückkehr aus dem Hintergrund falsch | Den Sitzungsbildschirm öffnen („Fokus fortsetzen“ im Plus-Menü): Dort baut die App den Stand aus den gespeicherten Segmenten neu auf. Nicht als Beweis für Hintergrundverhalten verwenden. |
| Die Analyse zeigt leere Zeiträume | Die Datei stammt nicht vom Vorführtag. Neu erzeugen (Abschnitt 1) und wieder importieren, oder den Zeitraum „7 Tage“ zeigen. |
| Die App ruckelt oder stürzt ab | Die App neu öffnen (die Daten sind lokal gespeichert). Zur Leistung nichts behaupten (Abschnitt 4); notfalls mit der Bildschirmaufnahme des Probelaufs weitermachen. |
| Zeitnot | Die Schritte „optional“ und in Schritt 4 (c) und (d) weglassen; Reihenfolge der übrigen bleibt. |

## 4. Was nicht behauptet wird

- **Keine Messwerte von einem Gerät.** Die Lastzahlen (zum Beispiel Projektions-Neuaufbau und Gewichts-Commit mit mehr als 10.000 synthetischen Datensätzen) stammen von einem Rechner mit In-Memory-Datenbank und vom CI-Runner. Die Planungsziele für ein Gerät (Start etwa 3 s, einfacher Commit 300 ms, Scrollen mit 60 Hz) sind nicht gemessen. Wörter wie „schnell“ oder „flüssig“ sind keine belegte Aussage.
- **iOS ist nicht gebaut und nicht getestet.** Die Projektdateien sind nur vorbereitet.
- **Keine Cloud, keine Konten, keine Telemetrie.** Alle Daten liegen auf dem Gerät; die Sicherungsdatei ist unverschlüsselt, und wohin sie geht, entscheidet die Nutzerin im Teilen-Menü. Es gibt keine Health-Anbindung und keine automatische Schrittzählung: Schritte werden von Hand eingetragen.
- **Kein Gerätetest der Barrierefreiheit.** Tippflächen, Beschriftungen, Layout bei 200 % Text und Kontraste sind im Host-Test belegt; TalkBack und die echte Systemschrift wurden nicht geprüft.
- **Erinnerungen:** Zustellung, Systemdialog und das Verhalten nach Force-Stop sind nicht auf einem Gerät geprüft; die Zustellung ist ungenau getaktet.
- **Der Release-Build** wird in der CI gebaut (mit Debug-Schlüssel signiert), aber nirgends gestartet.
- **Keine Abnahme.** Kein Ticket ist abgenommen, die Abnahme entscheidet das Team; der Name „App-Name“ ist ein Platzhalter. Zu den Tests gilt nur, was die Befehle im [Testbericht](test-report.md) zeigen: lokal laufen alle Host-Tests grün (kein Gerätetest), das CI-Ergebnis steht im Pull Request.
- **XP und Streak sind ein lokaler Motivationsmechanismus.** Die Uhr des Geräts ist ohne Server nicht manipulationssicher.
- **Die Demo-Daten sind synthetisch.** Die gezeigten Werte beschreiben keine Person.
