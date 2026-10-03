# Erste Tests: App starten und ausprobieren

Diese Anleitung ist für die ersten eigenen Tests auf einem Emulator oder einem Handy. Sie beschreibt zwei Wege, einen Rundgang durch die App und die ehrlichen Grenzen des bisherigen Prüfstands.

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
| Release-Build, iOS | nicht geprüft; iOS ist nur vorbereitet |

## Weg A: fertiges APK aus der CI auf das Handy (am schnellsten)

Du brauchst kein Android Studio und kein Flutter.

1. GitHub öffnen: Repository `spacy-cloud/self-improvement`, Reiter **Actions**, den neuesten grünen Lauf auf dem Branch `feature/BS-51-android-v1` wählen.
2. Unten bei **Artifacts** `debug-apk` herunterladen (ZIP, enthält `app-debug.apk`, etwa 100 MB). Artefakte werden nach 14 Tagen gelöscht.
3. Die APK aufs Handy bringen (USB, Cloud-Ordner oder `adb install -r app-debug.apk`).
4. Auf dem Handy die Installation aus dieser Quelle erlauben und die APK öffnen. Das Debug-Paket ist mit einem Debug-Schlüssel signiert und nur zum Testen gedacht.

Mit der GitHub-CLI geht dasselbe in der Konsole:

```bash
gh run list --repo spacy-cloud/self-improvement --branch feature/BS-51-android-v1 --limit 3
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

1. Repository klonen und den Branch `feature/BS-51-android-v1` auschecken. In Android Studio den **Projektordner** öffnen (der mit `pubspec.yaml`).
2. Im Terminal von Android Studio (im Projektordner):

   ```bash
   flutter pub get
   dart run build_runner build
   ```

   Der zweite Befehl ist Pflicht: Die Datenbankdateien (`*.g.dart`) werden nicht eingecheckt, ohne sie meldet der Compiler „Target of URI doesn't exist“.
3. Gerät wählen: entweder einen Emulator anlegen (Device Manager, zum Beispiel Pixel 6 mit API 34 oder neuer) oder ein Handy per USB anschließen (Entwickleroptionen, USB-Debugging aktiv).
4. Oben die Konfiguration `main.dart` wählen und auf **Run** drücken. Die erste Gradle-Synchronisierung lädt Gradle und Abhängigkeiten und dauert mehrere Minuten.

Ohne Android Studio geht es auch mit `flutter run` im Projektordner, sobald ein Gerät verbunden ist.

**Achtung bei den Integrationstests:** `flutter test integration_test` (die Emulator-Abläufe aus [integration-tests.md](integration-tests.md)) löscht die Datenbank der App auf dem Zielgerät, damit jeder Ablauf wie eine frische Installation startet. Die Abläufe starten deshalb nur mit `--dart-define=WIPE_APP_DATA=yes`. Nie auf einem Handy mit echten Daten, und nicht auf dem Emulator, auf dem du von Hand testest, solange du die Einträge behalten willst.

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
2. **Plus-Menü** (Plus-Button „Eintrag hinzufügen“ in der Mitte der Navigationsleiste, acht Einträge): je einen Eintrag anlegen.
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
| Gradle meldet ein falsches JDK | Android Studio, Einstellungen, Build Tools, Gradle: **Gradle JDK** auf das eingebettete JDK (21) stellen |
| Gerät wird nicht erkannt | USB-Debugging prüfen, `flutter devices` und `flutter doctor` ausführen |
| SDK-Lizenzen fehlen | `flutter doctor --android-licenses` |
| App startet nicht oder stürzt ab | Logs sichern (siehe unten), App deinstallieren und neu installieren |

Fehler melden: bitte Gerät und Android-Version, Debug- oder Release-Paket, die Schritte bis zum Fehler und, wenn möglich, einen Screenshot angeben. Logs der App mit Android Studio (Fenster Run oder Logcat) oder in der Konsole:

```bash
adb logcat -d | grep -i "flutter\|AndroidRuntime"
```

Die Logs der App enthalten nur Fehlertypen, keine Eingaben.
