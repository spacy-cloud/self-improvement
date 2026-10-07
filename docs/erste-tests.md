# Erste Tests: App starten und ausprobieren

Diese Anleitung ist für die ersten eigenen Tests auf einem Emulator oder einem Handy. Sie beschreibt zwei Wege, das Update von v0.1.0, einen Rundgang durch die App (mit einem eigenen Teil für die neuen Funktionen von v0.2.0) und die ehrlichen Grenzen des bisherigen Prüfstands. Die ausführliche Liste für das Samsung S25 und das iPhone steht in der [Geräte-Checkliste](geraete-checkliste-v0.2.0.md).

## Was bisher geprüft ist und was nicht

| Geprüft | Wie |
|---|---|
| Fachlogik, Datenbank, Oberflächen, Barrierefreiheit-Grundlagen | automatische Tests auf dem Entwicklungsrechner (siehe [test-report.md](test-report.md)) |
| App baut als Debug-APK; auf einem Android-Emulator (API 34) laufen der Smoke-Test und sieben Kernabläufe mit dem echten Produktionsstart (Erststart, Gewicht, Wasser, Aufgabe, Fokus mit Neustart, Zurücksetzen, Datenbankdatei und Zeitzone), siehe [integration-tests.md](integration-tests.md) | GitHub Actions, Jobs „Android debug APK“ und „Android emulator integration tests“; was sie beweisen, steht in [test-report.md](test-report.md) |
| Lasttest mit mehr als 10.000 synthetischen Einträgen | nur auf einem CI-Rechner, nicht auf einem Gerät |

| Noch nicht geprüft | Folge für dich |
|---|---|
| Echtes Gerät, Gefühl bei Start und Scrollen | dein Test ist die erste echte Geräteprüfung |
| Zustellung von Erinnerungen, System-Berechtigungsdialog | auf dem Gerät prüfen (Abschnitt „Rundgang“) |
| Teilen-Menü und Dateiauswahl für Export und Import | auf dem Gerät prüfen |
| TalkBack, 200 % Schriftgröße, echte Tastatur | im Rundgang kurz anschauen |
| Release-Build, iOS | Release-Build nicht geprüft; iOS: unsignierte IPA aus der CI (BS-95); den Stand v0.1.0 hat der iOS-Tester auf einem iPhone 15 Pro getestet (BS-96, ohne blockierende Fehler, Folgetickets BS-112 bis BS-114, die v0.2.0 umsetzt oder entscheidet); **v0.2.0 ist auf keinem iPhone geprüft** |
| Alle Funktionen von v0.2.0 (Ziele heute, Tage blättern, Heute abhaken, Plus-Menü nach Zielen, Erinnerung je Aufgabe, Über die App, Schritte aus Health) | Host-Tests und CI-Build; **auf keinem Gerät geprüft** (Rundgang unten und [Geräte-Checkliste](geraete-checkliste-v0.2.0.md)) |
| Update einer echten v0.1.0-Installation auf v0.2.0 (Datenbank-Migration) | nur Host-Tests mit Fixtures aus dem Code von v0.1.0; **auf keinem Gerät geprüft** (Abschnitt „Update von v0.1.0“) |
| Schritte aus Health (nur Android, Health Connect) | nur Host-Tests mit einer Fake-Quelle; **kein Lauf mit echten Schrittdaten** |

## Weg A: fertiges APK aus der CI auf das Handy (am schnellsten)

Du brauchst kein Android Studio und kein Flutter.

1. GitHub öffnen: Repository `spacy-cloud/self-improvement`, Reiter **Actions**, den neuesten grünen Lauf des Workflows „CI“ auf dem Branch `dev` wählen (der Entwicklungsbranch; `main` ist die Produktion). Solange die Pull Requests des Releases v0.2.0 nicht in `dev` gemergt sind, steckt der Stand v0.2.0 nur im Lauf auf dem Branch des letzten Pull Requests der Kette (jeder Branch der Kette enthält alle seine Vorgänger; die Reihenfolge steht in [test-report.md](test-report.md) Abschnitt 6).
2. Unten bei **Artifacts** `debug-apk` herunterladen (ZIP, enthält `app-debug.apk`, etwa 100 MB). Artefakte werden nach 14 Tagen gelöscht.
3. Die APK aufs Handy bringen (USB, Cloud-Ordner oder `adb install -r app-debug.apk`).
4. Auf dem Handy die Installation aus dieser Quelle erlauben und die APK öffnen. Das Debug-Paket ist mit einem Debug-Schlüssel signiert und nur zum Testen gedacht.

Mit der GitHub-CLI geht dasselbe in der Konsole:

```bash
gh run list --repo spacy-cloud/self-improvement --branch dev --workflow CI --limit 3
gh run download RUN_ID --repo spacy-cloud/self-improvement -n debug-apk -D ./apk
adb install -r ./apk/app-debug.apk
```

Zusätzlich gibt es das Artefakt `release-apk` (ebenfalls mit Debug-Schlüssel signiert, schneller und kleiner). Es ist **nicht** auf einem Gerät geprüft; nimm für die ersten Tests das Debug-Paket und das Release-Paket nur zum Vergleich der Geschwindigkeit.

## Weg B: in Android Studio starten

Voraussetzungen:

- Aktuelle stabile Version von Android Studio mit dem Flutter-Plugin (das Projekt nutzt das Android-Gradle-Plugin 9.1.0 und Gradle 9.3.1; ältere Studio-Versionen melden sonst eine Inkompatibilität).
- Flutter **3.47.6** (stable, Dart 3.13.5). `flutter --version` muss das zeigen.
- Android SDK (Studio installiert es beim ersten Start); JDK ist das mitgelieferte der Studio-Version (JDK 17 oder neuer).

Schritte:

1. Repository klonen und den Branch `dev` auschecken (solange die Kette von v0.2.0 nicht gemergt ist: den Branch ihres letzten Pull Requests). In Android Studio den **Projektordner** öffnen (der mit `pubspec.yaml`).
2. Im Terminal von Android Studio (im Projektordner):

   ```bash
   flutter pub get
   dart run build_runner build
   ```

   Der zweite Befehl ist Pflicht: Die Datenbankdateien (`*.g.dart`) werden nicht eingecheckt, ohne sie meldet der Compiler „Target of URI doesn't exist“.
3. Gerät wählen: entweder einen Emulator anlegen (Device Manager, zum Beispiel Pixel 6 mit API 34 oder neuer) oder ein Handy per USB anschließen (Entwickleroptionen, USB-Debugging aktiv).
4. Oben die Konfiguration `main.dart` wählen und auf **Run** drücken. Die erste Gradle-Synchronisierung lädt Gradle und Abhängigkeiten und dauert mehrere Minuten.

Ohne Android Studio geht es auch mit `flutter run` im Projektordner, sobald ein Gerät verbunden ist.

Neuen Stand holen, wenn es Änderungen auf dem Branch gibt:

```bash
git pull
flutter pub get
dart run build_runner build
```

Danach die App in Android Studio mit **Stop** und **Run** neu starten (ein Hot Reload reicht für neue Dateien nicht). Die Daten der App bleiben dabei erhalten, solange du sie nicht deinstallierst.

**Achtung bei den Integrationstests:** `flutter test integration_test` (die Emulator-Abläufe aus [integration-tests.md](integration-tests.md)) löscht die Datenbank der App auf dem Zielgerät, damit jeder Ablauf wie eine frische Installation startet. Die Abläufe starten deshalb nur mit `--dart-define=WIPE_APP_DATA=yes`. Nie auf einem Handy mit echten Daten, und nicht auf dem Emulator, auf dem du von Hand testest, solange du die Einträge behalten willst.

## Update von v0.1.0 auf v0.2.0

v0.2.0 hebt die lokale Datenbank auf Schema 2 und die Sicherung auf Version 2 an. Ein Zurück auf v0.1.0 gibt es nicht: v0.1.0 öffnet die neue Datenbank nicht und liest keine Sicherung der Version 2. Das Update einer echten Installation ist auf keinem Gerät geprüft (nur Host-Tests mit Fixtures aus dem Code von v0.1.0, siehe [test-report.md](test-report.md)).

1. In der alten Version eine Sicherung exportieren: Tab **Profil**, Zahnrad oben rechts, **Daten & Sicherung**, **Jetzt exportieren**, im Teilen-Menü speichern. Sie bleibt in v0.2.0 lesbar (der Import hebt sie auf Version 2 an).
2. Die neue APK über die vorhandene Installation installieren (`adb install -r`). Die Daten bleiben nur erhalten, wenn beide APKs mit demselben Schlüssel signiert sind; APKs aus verschiedenen CI-Läufen sind es vermutlich nicht (nicht geprüft, siehe [known-limitations.md](known-limitations.md)).
3. Lehnt Android das Update ab: die App deinstallieren, die neue APK installieren und die Sicherung importieren (**Daten & Sicherung**, **Sicherung auswählen**).
4. Danach prüfen: Profil, Einträge, Ziele und Module sind wie vorher, und die Seite „Über die App“ (Einstellungen, Zeile „Version“) nennt „Daten-Schema 2 · Backup-Format 2“. Neue Felder haben Standardwerte, keine Geschichte: vorhandene Schrittwerte gelten als von Hand eingetragen, der Abgleich mit Health ist aus, keine Aufgabe hat eine Erinnerung, kein Tag ist als Ruhetag oder übersprungen markiert.

## Demo-Daten laden (optional, empfohlen für Diagramme und Analyse)

Eine frische Installation ist leer. Für Diagramme, Serien und den Analyse-Vergleich gibt es eine Sicherungsdatei mit 90 Tagen synthetischer Daten (keine echten Daten). Sie läuft über den normalen Import der App und prüft damit nebenbei die Wiederherstellung.

1. Datei besorgen: CI-Artefakt `demo-backup` (enthält `demo-daten-90-tage.json`) herunterladen **oder** lokal erzeugen:

   ```bash
   flutter test test/tool/demo_backup_test.dart
   ```

   Das schreibt `build/demo-backup/demo-daten-90-tage.json`. Die 90 Tage enden am heutigen Datum; importiere die Datei am Tag der Erzeugung, damit die Analyse-Zeiträume gefüllt sind.
2. Datei aufs Gerät legen, zum Beispiel `adb push build/demo-backup/demo-daten-90-tage.json /sdcard/Download/`.
3. In der App: Tab **Profil**, Zahnrad oben rechts, **Daten & Sicherung**, **Sicherung auswählen**, Datei wählen, Vorschau prüfen, **Ersetzen und wiederherstellen**.

Achtung: Der Import ersetzt alle vorhandenen App-Daten (die App warnt davor). Zurück zum leeren Zustand: **Daten & Sicherung**, **Zurücksetzen …**, das Wort `LÖSCHEN` eingeben.

## Rundgang (etwa 20 Minuten)

1. **Erststart:** kurze neutrale Ladeseite, dann Onboarding (Willkommen, vier freiwillige Schritte, alles überspringbar). Danach das Dashboard, auf einer leeren Installation ohne erfundene Werte.
2. **Plus-Menü** (Plus-Button „Eintrag hinzufügen“ in der Mitte der Navigationsleiste; auf einer frischen Installation alle acht Einträge, seit v0.2.0 nur die zu eingeschalteten Zielen, siehe den Rundgang unten): je einen Eintrag anlegen.
   - Gewicht: `71,5` und `71.5` sind gültig, `71,55` und `19,9` werden abgewiesen.
   - Wasser: `+250`; nach dem Speichern 8 Sekunden lang „Rückgängig“.
   - Schritte: erst 7.450, dann 8.000 eintragen: der Tageswert ist 8.000, nicht 15.450.
   - Mahlzeit ohne Kalorien: die Analyse nennt „Kalorien unvollständig“.
   - Aufgabe und Gewohnheit anlegen und abhaken (Tab **Habits**).
   - Workout eintragen.
   - Fokus: Timer starten, App in den Hintergrund oder wegwischen, wieder öffnen: die Restzeit stimmt.
3. **Dashboard:** Karten und Zahlen aktualisieren sich sofort; Sichtbarkeit und Reihenfolge der Karten über den Button „Karten anpassen“ am Ende des Dashboards; Streak und Fortschritt öffnen (Profil, Fortschritt).
4. **Analyse:** 7, 30 und 90 Tage, „Als Tabelle“, Vergleich mit dem Zeitraum davor.
5. **Module verwalten** (Profil, Zahnrad): ein Modul ausschalten, Karten und Plus-Einträge verschwinden, die Einträge bleiben; wieder einschalten.
6. **Darstellung:** Hell, Dunkel, OLED, System; „Reduzierte Bewegung“; „Haptisches Feedback“ (leichte Vibration beim Speichern, wenn eingeschaltet).
7. **Erinnerungen** (Zahnrad, Einstellungen): einschalten, der Systemdialog für Benachrichtigungen erscheint ab Android 13. Mit „Zulassen“ eine Trink-Uhrzeit wählen; die Zustellung ist ungenau getaktet. Mit „Ablehnen“ bleibt die App voll nutzbar und zeigt den Zustand ehrlich an.
8. **Export und Import:** Daten & Sicherung, **Jetzt exportieren**, im Teilen-Menü in einem Ordner speichern; danach zurücksetzen und die Datei wieder importieren.
9. **Prozess beenden** (App aus der Übersicht wischen) und neu starten: Daten und Einstellungen bleiben erhalten.
10. **Barrierefreiheit kurz:** Systemeinstellung Schriftgröße auf das Maximum, die wichtigsten Seiten ansehen; TalkBack einschalten und Home, Formular und Plus-Menü anhören.

## Rundgang durch die neuen Funktionen (v0.2.0, etwa 25 Minuten)

Voraussetzung sind einige Tage Daten; am schnellsten liefern sie die Demo-Daten (siehe oben, der Import ersetzt alle App-Daten). Zieländerungen gelten ab morgen (nur das Zielgewicht gilt sofort); das Plus-Menü folgt dagegen dem gespeicherten Stand sofort.

1. **Ziele heute:** Auf Home die Karte „Dein Tag im Überblick“ antippen. Die Seite nennt „x von y erreicht“ und zeigt je Tagesziel eine Zeile mit Stand, Ziel und Status („Offen“, „Erreicht“, „Ruhetag“, „Übersprungen“). Das Wochenziel der Workouts steht getrennt darunter und zählt im Ring nicht mit. Eine Zeile antippen öffnet die Seite des Moduls, Zurück führt zur Übersicht (bei „Aufgabe erledigen“ und den Gewohnheiten zum Tab „Habits“, von dort nach Home); „Ziele bearbeiten“ öffnet die Zielseite.
2. **Tage blättern:** Auf Home nach rechts wischen oder den linken Pfeil tippen: Der Vortag erscheint mit dem Hinweis „Nicht heute“ und „Zurück zu heute“. Ring, Ziele und Karten zeigen die Zahlen dieses Tages, nur lesend und ohne Schnellzugriffe. Es sind höchstens sieben Tage zurück und nie Tage vor dem Profilstart; die Pfeile sind auch ohne Wischen bedienbar.
3. **Gewohnheiten abhaken:** Die Karte „Heute abhaken“ auf Home zeigt Aufgaben (eckiges Kästchen, Chip „Aufgabe“) und Gewohnheiten (rundes Kästchen, Chip „Gewohnheit“, Serie darunter). Ein Tipp aufs Kästchen hakt ab, „Rückgängig“ (8 Sekunden) nimmt es zurück; der Tab „Habits“ zeigt denselben Stand.
4. **Workout heute:** Tab **Profil**, „Meine Ziele“, den Schalter „Workout heute“ einschalten (gilt ab morgen). Am nächsten Tag zeigt die Workout-Karte auf Home den Tag; „Wie war dein Tag?“ bietet „Training eintragen“, „Ruhetag“ und „Heute überspringen“ (Ruhetag und Überspringen zählen als erreicht, geben keine XP, die Streak bleibt).
5. **Plus-Menü:** Das Plus zeigt nur Einträge zu eingeschalteten Zielen. Unter **Profil**, „Meine Ziele“ ein Ziel ausschalten (zum Beispiel Wasser): Beim nächsten Öffnen fehlt der Eintrag, darunter steht „Nicht dabei? …“. Sind alle Ziele aus, erscheint „Noch nichts zum Eintragen“ mit „Meine Ziele öffnen“. Die Ziele danach wieder einschalten.
6. **Erinnerung je Aufgabe:** In den Einstellungen „Erinnerungen“ einschalten (Systemdialog). Dann Plus, „Aufgabe“, im Block „Erinnerung“ einen Zeitpunkt in wenigen Minuten wählen und speichern. Die Benachrichtigung heißt „Erinnerung an deine Aufgabe“ und nennt den Titel der Aufgabe nicht; ein Tipp darauf öffnet die Aufgabe. Wird die Aufgabe vorher erledigt, kommt keine Benachrichtigung. Die Zustellung ist ungenau getaktet.
7. **Schritte aus Health (nur Android):** In den Einstellungen die Gruppe „Schritte“ mit dem Schalter „Schritte aus Health übernehmen“. Erst erscheint ein Erklärtext, dann der Systemdialog von Health Connect (nur Schritte, nur lesen); danach stehen die letzten sieben Tage in „Meine Schritte“ mit der Quelle „Aus Health“, von Hand eingetragene Tage haben Vorrang. Fehlt Health Connect oder ist es veraltet, sagt die Gruppe das und verweist auf den Store. Auf dem iPhone gibt es die Gruppe nicht.
8. **Über die App:** In den Einstellungen die Zeile „Version“ antippen: Autor, Website (öffnet den Browser), Datenschutz, technische Angaben („Daten-Schema 2 · Backup-Format 2“), die Lizenzen der Pakete und ganz unten der Lizenztext.

Was davon auf einem Gerät geprüft wurde: nichts. Die Host-Tests belegen die Logik und die Oberfläche mit Fakes; die Punkte der [Geräte-Checkliste](geraete-checkliste-v0.2.0.md) sind der Rest.

## Bekannte Grenzen

Eine laufend gepflegte Liste steht in [known-limitations.md](known-limitations.md). Das Wichtigste vorab:

- Der App-Name ist ein Platzhalter („App-Name“).
- Es gibt keine Cloud, keine Konten und keine Synchronisierung; alle Daten liegen nur auf dem Gerät.
- Sehr lange einzelne Wörter in Titeln können bei 320 px Breite und 200 % Schrift mitten im Wort umbrechen.
- Die Zeitraumauswahl der Analyse wird nach einem Neustart auf 7 Tage zurückgesetzt.

## Wenn etwas nicht klappt

| Problem | Lösung |
|---|---|
| `Target of URI doesn't exist: ...g.dart` | `dart run build_runner build` im Projektordner ausführen |
| Der Build oder `flutter test` bricht mit einem Fehler im Build-Hook von `sqlite3` ab | Der Hook lädt beim ersten Build die vorgebaute SQLite-Bibliothek von GitHub (Version aus `pubspec.lock`) und braucht dafür Netz und erreichbares GitHub; bei einer Störung (auch eine HTML-Fehlerseite statt der Bibliothek) den Befehl später wiederholen, das geladene Ergebnis liegt danach im Projektordner (`.dart_tool`) |
| Gradle meldet ein falsches JDK | Android Studio, Einstellungen, Build Tools, Gradle: **Gradle JDK** auf das eingebettete JDK (21) stellen |
| Gerät wird nicht erkannt | USB-Debugging prüfen, `flutter devices` und `flutter doctor` ausführen |
| SDK-Lizenzen fehlen | `flutter doctor --android-licenses` |
| App startet nicht oder stürzt ab | Logs sichern (siehe unten), App deinstallieren und neu installieren |

Fehler melden: bitte Gerät und Android-Version, Debug- oder Release-Paket, die Schritte bis zum Fehler und, wenn möglich, einen Screenshot angeben. Logs der App mit Android Studio (Fenster Run oder Logcat) oder in der Konsole:

```bash
adb logcat -d | grep -i "flutter\|AndroidRuntime"
```

Ein Release-Paket protokolliert bei unbekannten Fehlern nur den Fehlertyp und die Bibliothek. Ein Debug-Build (die Variante zum Ausprobieren in Android Studio) gibt zusätzlich den vollständigen Bericht des Frameworks aus; der kann Texte aus deinen Eingaben enthalten. Schau Logs deshalb an, bevor du sie weitergibst.
