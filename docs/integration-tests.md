# Flowtests auf dem Emulator (BS-76)

Dieselben sieben Abläufe laufen an drei Stellen: schnell auf dem Host mit Fakes (lokal, ohne Emulator), im Host-Prozess mit dem Produktionsstart (echte SQLite-Datei, nachgebaute Plattformkanäle) und auf einem Android-Emulator mit dem **echten Produktionsstart** der App (`SelfImprovementApp()` ohne Überschreibungen: echte SQLite-Datei, echte Gerätezeitzone, echtes Benachrichtigungs-Plugin, echte Uhr). Der alte Smoke-Test (`integration_test/app_smoke_test.dart`) startet dagegen auf einer In-Memory-Datenbank mit Fake-Plattform und bleibt als schneller Start-Check bestehen.

Die Abläufe F2 bis F6 beginnen mit „Überspringen“ im Onboarding (ein Tipp, Standardwerte); nur F1 geht alle fünf Screens ohne Eingabe durch.

## Aufbau

| Datei | Aufgabe |
|---|---|
| `integration_test/flows/*_flow.dart` | Die Abläufe als Funktionen mit einem `FlowContext`. Sie nutzen nur `WidgetTester`, Finder, deutsche UI-Texte und begrenzte Pump-Schleifen. |
| `integration_test/flows/flow_context.dart` | `FlowContext` (warten, tippen, tippen und eingeben, Neustart) und `FlowEnvironment`, die kleine Schnittstelle zu allem, was sich zwischen Host und Emulator unterscheidet. |
| `integration_test/flows/flow_steps.dart` | Gemeinsame Schritte (Onboarding überspringen, Plus-Menü, Tabs, Zurück). |
| `integration_test/app_flows_test.dart` | Emulator-Einstieg (eine Datei, damit die CI nur einmal nativ baut). |
| `test/app/flows/app_flows_host_test.dart` | Host-Einstieg mit `pumpFullApp` (In-Memory-Datenbank, Fake-Uhr, Fake-Plattform). |
| `test/app/flows/app_flows_production_start_host_test.dart` | Führt den Emulator-Einstieg im Host-Prozess aus: Produktionsstart, echte SQLite-Datei in einem Temp-Verzeichnis, echte Frames. Nur die nativen Seiten von `path_provider`, `flutter_timezone` und `flutter_local_notifications` fehlen und werden über ihre Plattformkanäle nachgebaut. Dauert etwa eine Minute. |
| `test/app/flows/flow_rules_test.dart` | Wächter: beide Einstiege führen dieselben Abläufe unter denselben Namen aus; Flow-Dateien warten nie mit `pumpAndSettle` oder festen Pausen und kennen den Ort der Ausführung nicht. |

Gewartet wird nie mit `pumpAndSettle` (ein blinkender Cursor oder ein Ladekreis hält es endlos offen), sondern mit `waitFor` und Verwandten: eine Schleife aus kurzen Pumps mit Echtzeit-Frist (30 s, beim ersten Start 90 s). Bei einem Fehler nennt die Meldung die erwartete Stelle und die Texte, die gerade auf dem Bildschirm stehen. Jede Flow-Zeile mit `ctx.log` erscheint mit Zeitstempel im Testlog.

## Abläufe

| Flow | Abnahme | Prüft |
|---|---|---|
| F1 | AT01 | Frische Installation zeigt das Onboarding; fünf Screens ohne Eingabe führen zum Home mit vier Tabs; Leerzustände, keine erfundenen Werte (kein kg, kein Level, keine XP, keine Streak). |
| F2 | AT02, AT06 | Gewicht `71,5` über das Plus-Menü, sichtbar auf Dashboard-Karte und Gewichts-Screen; App beenden und neu starten: Wert und Onboarding-Zustand sind noch da. |
| F3 | AT10 | +250 ml in zwei Aktionen vom Home (Schnellstart, Glas), danach in einer Aktion über die Karte; Home zeigt Menge und XP; Rückgängig nimmt Menge und XP zurück, genau einmal. |
| F4 | AT13 | Aufgabe anlegen, abschließen, wieder öffnen, erneut abschließen: am Ende 10 XP, nicht 20. |
| F5 | AT16 | Fokus starten, pausieren (Zeit steht), fortsetzen, App mitten in der Sitzung beenden und später neu starten: Sitzung läuft, die vergangene Zeit ist nachgeholt; Zeit speichern. |
| F6 | AT32 | Zurücksetzen abbrechen ändert nichts; mit `LÖSCHEN` bestätigt, kehrt die App zum Onboarding zurück (auch nach Neustart); danach leer, der Timer ist weg. |
| F7 | – | Nach dem Start: Datenbankdatei im App-Support-Verzeichnis, Gerätezone ist eine gültige IANA-ID und die Uhr der App nutzt sie, `reminderPlatform.initialize()` läuft zweimal fehlerfrei, Berechtigungsstatus und offene Benachrichtigungen sind lesbar. |

F7 prüft nur, was auf einem frischen Emulator feststeht: der Berechtigungsstatus wird gelesen, aber nicht auf einen Wert festgelegt (`granted` oder `denied`, nie `unavailable`).

## Ausführen

```bash
flutter test test/app/flows/app_flows_host_test.dart     # Host, schnelle Schleife, etwa 15 Sekunden
flutter test test/app/flows                              # alle Host-Tests der Flows, etwa 1,5 Minuten
flutter devices                                          # Geräte-ID ablesen
flutter test integration_test -d <deviceId>              # Emulator: Flows und Smoke-Test
flutter test integration_test/app_flows_test.dart -d <deviceId>   # nur die Flows
dart run tool/at_coverage.dart                           # welche Abnahme-IDs ein Test nennt
```

Die CI führt `flutter test integration_test` im Job `android-integration` auf einem Emulator mit API 34 aus.

**Warnung:** Die Flowtests löschen vor jedem Test die Datenbankdatei der App (`self_improvement*` im App-Support-Verzeichnis), damit jeder Test wie eine frische Installation startet. Nur auf einem Emulator oder Testgerät ausführen, dessen App-Daten verloren gehen dürfen, nie auf einem Gerät mit echten Einträgen.

## Was Host und Emulator unterscheidet

Alle Unterschiede stehen in den Einstiegen, nie in den Abläufen:

| | Host | Emulator |
|---|---|---|
| Start | `pumpFullApp`, Datenbank im Speicher | `SelfImprovementApp()` mit Standardstarter, Datei im App-Support-Verzeichnis |
| Uhr, Zeit vergeht | Fake-Uhr springt um Minuten | echte Uhr, die Flows warten höchstens 4 s echt |
| Fokus-Takt | folgt der Fake-Uhr | echter `Stopwatch`-Takt |
| Benachrichtigungen | `FakeReminderPlatform` | echtes Plugin |
| Zeitzone | fest `Europe/Berlin` | `flutter_timezone` |
| Neustart | Baum entsorgen, neu starten auf derselben Datenbank | Baum entsorgen, neu starten auf derselben Datei |
| Frames | nur gepumpte Frames | jeder Frame, den die App anfordert (`fullyLive`) |

## Nicht automatisiert (manuell prüfen)

- Dateiauswahl und Teilen-Menü (Export, Import, AT30 und AT31 am Gerät).
- Systemdialog der Benachrichtigungsberechtigung, Ablehnen und späteres Erlauben, Systemeinstellungen öffnen (AT28).
- Echte Zustellung von Erinnerungen, Antippen einer Benachrichtigung, Kaltstart aus einer Benachrichtigung (AT29), Verhalten nach Force-Stop.
- TalkBack, Tastatur, Schrift 200 % (AT33, AT34), Sichtvergleich Light, Dark, OLED und reduzierte Bewegung (AT35).
- Flugmodus (AT01): die App nutzt kein Netz, der Schalter wird aber nicht gesetzt.
- Zeitzonen- und Sommerzeitwechsel am Gerät (AT25), Hintergrund und Fortsetzen, harte Prozessbeendigung, Gerätestart.
- Messung mit 10.000 Einträgen am Gerät (AT36).

## Ehrliche Grenzen

- Die CI (Emulator API 34, x86_64, Google APIs) ist die einzige Geräteprüfung; es gibt keine Prüfung auf einem echten Gerät. Herstellerbesonderheiten (Akkusparer, andere Tastaturen, andere Bildschirme) sind nicht abgedeckt.
- „App beenden“ heißt: Widget-Baum und Datenbankverbindung werden geschlossen, die App startet im selben Prozess neu. Ein hartes Beenden des Prozesses ist das nicht.
- Auf dem Emulator vergehen Sekunden statt Minuten; die Erwartungen folgen der Zeit, die wirklich verging.
- Der Emulator-Einstieg lief nie auf einem Gerät; lokal laufen Format, Analyse und der Host-Lauf des Einstiegs mit nachgebauten Plattformkanälen (`app_flows_production_start_host_test.dart`). Das prüft den Produktionsstart gegen eine echte Datei und echte Frames, ersetzt aber keinen Emulatorlauf: native Seiten der Plugins, die sqlite-Bibliothek der APK, Tastatur, Bildschirmgröße und echte Berechtigungen bleiben ungeprüft.
- Die Flows prüfen Ergebnisse auf dem Bildschirm. Sie ersetzen weder die Domänentests noch die Widget-Tests der Features; sie weisen nach, dass Start, Datenbankdatei und die Kernabläufe zusammen funktionieren.

## Beobachtung zum Zurücksetzen (Stand BS-76)

Löscht das Zurücksetzen das Profil, schickt der Router die App sofort ins Onboarding und entfernt dabei das Bestätigungs-Sheet. Ist es zu diesem Zeitpunkt schon weg, kommt `showResetSheet` mit „abgebrochen“ zurück und die Meldung „Alle App-Daten wurden gelöscht.“ erscheint nicht; trifft das späte `Navigator.pop` des Sheets dagegen die Onboarding-Seite, meldet go_router „popped the last page“. F6 prüft deshalb das Ergebnis (Onboarding, leere Daten, Timer weg), nicht die Meldung.
