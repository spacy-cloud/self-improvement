# Profil, Ziele und Einstellungen (BS-70)

Dieses Dokument beschreibt die Oberfläche des lokalen Profils, des Ziele-Editors, der Einstellungen und der Lizenzseite. Verbindlich waren in dieser Reihenfolge: die Regeln des Arbeitsauftrags, der Designstand (`docs/design-handoff.md`), die fachliche Spezifikation. Zahlen und Namen aus Figma sind Platzhalter; alle gezeigten Werte stammen aus der Datenbank.

## 1. Screens und Figma-Knoten

| Screen | Route | Figma (Light) | Klasse |
|---|---|---|---|
| Profil (Tab) | `/profile` | `4007:2` | `ProfileScreen` |
| Profil bearbeiten | `/profile/edit` | `4043:166` | `ProfileEditScreen` |
| Ziele bearbeiten | `/goals` | `4043:2` | `GoalsScreen` |
| Einstellungen | `/settings` | `4024:2`, Variante Erinnerungen verweigert `4055:416` (nur Bildvorlage des fremden Erinnerungsblocks) | `SettingsScreen` |
| Lizenzen | `/settings/licenses` | `4056:558` | `LicensesScreen` |

Dark und OLED stammen aus den Token-Modi; es gibt keine eigenen Frames dafür. Die Routen `/settings/modules` und `/settings/data` gehören anderen Arbeitspaketen, die Einstellungen verlinken nur dorthin.

Code: `lib/features/profile/{domain,application,presentation}` und `lib/features/settings/{application,presentation}`. Die Fachlogik liegt in reinen Dart-Funktionen (`profile_input`, `goal_editor`, `profile_overview`), die Widgets enthalten keine Regeln und keinen SQL-Code. Gespeichert wird ausschließlich über die vorhandenen Commands (`ProfileCommands`, `GoalsCommands`, `SettingsCommands`) mit dem `SubmissionTracker`-Muster: gleicher Inhalt beim Wiederholen ergibt dieselbe Command-ID, ein zweiter Tipp während des Speicherns wird ignoriert.

## 2. Verhalten je Screen

**Profil.** Karte mit Initialen (höchstens zwei Namensteile) oder neutralem Profilsymbol, Name oder „Mein Profil“, „Dabei seit Monat Jahr“. Kennzahlen nur mit Daten: „Tage Streak“ und „Aktive Tage“ (nur bei eingeschalteter Gamification, Streak ist ein Link), „seit Start“ nur mit ausdrücklichem Startgewicht und aktueller Messung. Zeile „Fortschritt“ (Level und XP) nur bei eingeschalteter Gamification. „Meine Ziele“ zeigt die Ziele der eingeschalteten Module, ein Ziel mit Änderung ab morgen zeigt „Ab morgen: …“. „Körperdaten“ erscheint nur, wenn Größe, Startgewicht oder Alter vorhanden sind; es gibt keinen BMI. Zustände: Laden (neutral), Fehler mit „Erneut versuchen“, leer (alle Module aus: „Keine Ziele sichtbar“ mit Weg zur Modulverwaltung). Links: Bearbeiten, Ziele, Streak, Fortschritt, Einstellungen.

**Profil bearbeiten.** Name (optional, höchstens 40 Zeichen nach Trimmen, leer bedeutet „Mein Profil“), Größe 100 bis 250 cm, Alter 18 bis 120 Jahre, Start- und Zielgewicht 20,0 bis 350,0 kg mit einer Nachkommastelle (Komma oder Punkt). Alles ist optional. Die Initialen-Vorschau folgt dem Namen live. Das Zielgewicht gilt sofort. Wird ein Zielgewicht neu gesetzt oder geändert und gibt es kein Startgewicht, schlägt die Seite die letzte Messung vor („Als Startgewicht übernehmen“); erst der Tipp trägt den Wert ins Formular ein, gespeichert wird mit dem Formular. Profilwerte werden nie zu Messungen und Messungen nie still zu Profilwerten. Ist das Körpermodul aus, sind die Körperfelder ausgeblendet und ihre gespeicherten Werte bleiben unverändert.

**Ziele bearbeiten.** Wasser (250 bis 10.000 ml in 50er-Schritten), Schritte (100 bis 100.000), Fokus (5 bis 180 Minuten), „Gewicht erfassen“ und „Aufgabe erledigen“ (Schalter), Workouts pro Woche (1 bis 14). Wasser, Schritte und Fokus haben je einen eigenen Schalter; ein ausgeschaltetes Ziel behält seinen Wert und meldet in Worten „Ausgeschaltet: zählt nicht für den Tagesring.“ Alle Zielwerte und Schalter gelten ab morgen (Hinweisbox mit Datum, Gruppentitel „… · ab morgen“, Erfolgsmeldung „… gelten ab morgen“). Eine heute bereits gespeicherte Änderung wird beim Öffnen angezeigt („Heute noch: …“). Das Zielgewicht gilt sofort (Gruppe „Körperziel · gilt sofort“) und wird über `ProfileCommands` gespeichert; die Erfolgsmeldung nennt, was wann gilt. Speichern von Zielen und Zielgewicht sind zwei Commands: gelingt das erste und scheitert das zweite, bleibt das erste gespeichert, die Meldung sagt das, und die Wiederholung sendet nur noch das zweite. Ziele ausgeschalteter Module sind ausgeblendet, bleiben gespeichert und werden nicht validiert.

**Einstellungen.** Profil-Eintrag („Nur lokal“), Design (Auswahlblatt mit System, Hell, Dunkel, OLED; „System“ wird bei dunklem Gerät Dunkel, OLED nur ausdrücklich), Reduzierte Bewegung, Haptisches Feedback, Erinnerungsblock (`RemindersSection`, gebaut vom Erinnerungs-Paket, siehe [data-reminders.md](data-reminders.md)), Module („N von 5“), Daten & Sicherung, Version und Lizenzen. Außerhalb des Erinnerungsblocks gibt es genau zwei Schalter und keine Konto- oder Cloud-Elemente. Jede Änderung ist ein eigener Command; scheitert das Schreiben, bleibt der Schalter auf dem gespeicherten Wert und eine Fehlermeldung bietet „Erneut“ an.

**Lizenzen.** Liest `LicenseRegistry` (lokal, ohne Netz) nach dem Registrieren der gebündelten Schriftlizenz (Inter, SIL OFL 1.1). Liste: Inter, Flutter SDK, „Open-Source-Pakete“ (mit echter Anzahl). Jeder Eintrag öffnet den vollständigen Text als träge Absatzliste, die bei jeder Schriftgröße umbricht und scrollt. Ein vorzeitiger Lesefehler zeigt die gelesenen Pakete mit Hinweis „unvollständig“.

## 3. Abweichungen vom Entwurf und Gründe

| Stelle | Entwurf | Umsetzung | Grund |
|---|---|---|---|
| Profil, Titel | „Mein Profil“ | „Profil“ | „Mein Profil“ ist der Standardname in der Karte; sonst stünde er doppelt. |
| Profil, Avatar | Grünverlauf | einfarbig Button-Grün | Weiß auf dem hellen Verlaufsende erreicht keine 4,5:1; einfarbig in allen Themes ausreichend. |
| Profil, „seit Start“ | grün | neutrale Textfarbe, Vorzeichen als Text | Keine Wertung von Zu- oder Abnahme. |
| Profil, Ziele | vier Zeilen | alle Ziele sichtbarer Module | Der Editor kann alle bearbeiten; die Zusammenfassung zeigt dasselbe. |
| Profil | – | Zeile „Fortschritt“ | Auftrag: Link zu Streak und Fortschritt bei aktiver Gamification. |
| Profil bearbeiten | Geburtsjahr | Alter in Jahren | Spezifikation 6.3: kein Geburtsdatum. |
| Profil bearbeiten | „Pflichtfeld“ am Namen | „optional“ | Spezifikation 3: Name optional. |
| Profil bearbeiten | Schalter „BMI anzeigen“ | entfällt | Es gibt keine gespeicherte Einstellung und Einstellungen ohne Wirkung sind ausgeschlossen; der BMI folgt auf der Gewichtsübersicht aus Größe, Alter und Messung. |
| Profil bearbeiten | – | Zielgewicht, Startgewicht-Vorschlag | Auftrag. |
| Profil bearbeiten | Einheit im Feld | Einheit im Label („Größe in cm“) | `AppTextField` mit `suffixText` und gefülltem Feld löst bei aktiver Semantik eine Framework-Assertion aus (siehe Offene Punkte). |
| Ziele | Stepper in der Titelzeile, nur Schalter für zwei Ziele | Titel mit Schalter, darunter Stepper; tippbarer Wert als reine Zahl | Spezifikation 10.1: jeder quantitative Zieltyp ist einzeln abschaltbar; bei 320 px und 200 % passt Titel plus Schalter plus Stepper nicht in eine Zeile. Exakte Eingabe in ml und Schritten. |
| Ziele | Workouts unter „gelten sofort“ | „Wochenziel · ab morgen“ | Der versionierte Vertrag (`GoalsCommands`) setzt jede Zieländerung ab morgen; „sofort“ wäre falsch. Nur das Zielgewicht gilt sofort. |
| Einstellungen, Daten | Export, Import, Zurücksetzen als drei Zeilen | eine Zeile „Daten & Sicherung“ | Der Datenscreen enthält alle drei; das Zurücksetzen bleibt hinter seiner eigenen Bestätigung. |
| Einstellungen, Design | Zeile mit Wert | Zeile öffnet ein Auswahlblatt mit Schließen-Taste | Der Entwurf zeigt kein Auswahlelement; Blatt mit eigener Schließen-Taste und Android-Zurück. |
| Lizenzen | „Liste wird beim Build erzeugt“, Symbole als eigene Entwürfe | echte Paketzahl; Material Icons (Apache 2.0) genannt | Wahrheitsgemäß: der Code nutzt Material Icons als Fallback (Designstand, Abschnitt 5). |
| Große Schrift | – | Identitätskarte, Wertzeilen der Zielliste und der Einstellungen stapeln sich ab Skala 1,3 | Sonst bricht der Titel mitten im Wort oder die Zeile läuft über. |

## 4. Konflikte zwischen Spezifikation, Entwurf und Auftrag

| Konflikt | Entscheidung |
|---|---|
| Entwurf „Geburtsjahr“ gegen Spezifikation „Alter“ | Spezifikation. |
| Entwurf „Pflichtfeld“ gegen „Name optional“ | Spezifikation. |
| Entwurf „BMI anzeigen“ gegen „keine unimplementierten Einstellungen“ | Schalter entfällt; es gibt weder gespeicherte Einstellung noch BMI im Profil. |
| Entwurf „Workouts gelten sofort“ gegen versionierten Zielvertrag | Auftrag und Vertrag: ab morgen; nur das Körperzielgewicht ist sofort. |
| Spezifikation Route `/modules` gegen Designstand und Auftrag `/settings/modules` | Designstand und Auftrag. |
| Entwurf „Konto“-nahe Bereiche gegen „keine Konten oder Cloud“ | Spezifikation und Designstand: nichts davon in den Einstellungen. |

## 5. Barrierefreiheit

- Tippziele mindestens 48 x 48, geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` bei 320, 360, 393 und 430 px und den Textskalen 1,0 und 2,0 für alle fünf Screens und das Auswahlblatt.
- Jede Icon-Taste, jeder Schalter, jeder Stepper hat ein deutsches Label („Wasser um 250 Milliliter erhöhen“); Schalter sprechen ihren Zustand, das Auswahlblatt nennt „ausgewählt“, Zustände stehen immer auch im Text (zum Beispiel „Ausgeschaltet: zählt nicht für den Tagesring.“).
- Fehler stehen mit Symbol und Text am Feld; nach einem abgelehnten Speichern bekommt das erste fehlerhafte Feld den Fokus (der Screenreader liest Feld und Meldung zusammen) und eine Zusammenfassung erscheint als Live-Region direkt über dem Speichern-Button. Die Eingabe bleibt in jedem Fehlerfall erhalten.
- Die Speichern-Taste ist am unteren Rand festgesetzt und liegt bei geöffneter Tastatur darüber (getestet mit 300 px Tastaturhöhe bei Skala 2,0). Der Inhalt scrollt; es gibt keine reinen Gesten.
- Ungespeicherte Änderungen fragen „Änderungen verwerfen?“ (Standard „Weiter bearbeiten“, Android-Zurück eingeschlossen). Das Auswahlblatt hat „Schließen“ und schließt auch mit Android-Zurück.
- Bewegung folgt `AppMotion` (der Schalter animiert 150 ms, bei reduzierter Bewegung sofort). Haptik hängt am Schalter und beeinflusst die Bewegungseinstellung nicht.

## 6. Tests

Befehle: `flutter test test/features/profile test/features/settings`. Von den 386 Tests dieser Verzeichnisse gehören 297 zu diesem Paket (profile/domain 53, profile/application 52, profile/presentation 104, settings/application 28, settings/presentation 58, Architekturtest 2); die übrigen 89 unter `settings/data` gehören zur Daten-Oberfläche ([data-reminders.md](data-reminders.md)). Den Gesamtstand und die Ergebnisse von `flutter analyze` und `dart format` nennt [test-report.md](../test-report.md).

| Datei | Inhalt | Akzeptanz |
|---|---|---|
| `test/features/profile/domain/profile_input_test.dart` | Grenzen beider Seiten für Name, Größe, Alter, Gewichte, Mehrfachfehler, Startgewicht-Vorschlag, Initialen | – |
| `.../goal_editor_test.dart` | Grenzen aller Ziele, Schrittlogik, heute gegen ab morgen, ausgeblendete Module | – |
| `.../profile_overview_test.dart` | kein erfundener Wert, Gewicht seit Start, Gamification und Module aus | AT09, W02 |
| `test/features/profile/application/profile_form_controller_test.dart` | Speichern, optionales Profil, Validierung, Abbruch, Wiederholung mit gleicher ID, Doppeltipp, Neustart | AT02, W02 |
| `.../goals_form_controller_test.dart` | ab morgen mit echten Tagesschnappschüssen, Schalter, Grenzen, Zielgewicht sofort, Vorschlag, Teilfehler | AT09, AT24, C07, W02 |
| `test/features/profile/presentation/profile_screen_test.dart` | leeres und volles Profil, Zielarten, Module, Links, Fehler, Gamification aus und an | AT02, AT09, AT24, AT26, AT34, W02 |
| `.../profile_edit_screen_test.dart` | Anzeige, Speichern nach Commit, Neustart, Validierung am Feld, Verwerfen, Fehler und Wiederholung, Vorschlag, Körpermodul aus | AT02, AT34, W02 |
| `.../goals_screen_test.dart` | Hinweis mit Datum, Stepper und Eingabe, Schalter, Grenzen, Zielgewicht, Verwerfen, Fehler, Editor bleibt bei fremden Änderungen stabil | AT24, AT34, C07 |
| `.../responsive_test.dart` | 320/360/393/430 px bei 1,0 und 2,0: Überlauf, Tippziele, Labels, Speichern über der Tastatur | AT33 |
| `test/features/settings/application/settings_actions_test.dart` | Theme gelangt über den Settings-Provider zu `AppTheme` (Einheitentest), Bewegung, Haptik, Neustart, Fehler, gleiche ID, Sperre | AT02, AT35, C06 |
| `.../license_providers_test.dart` | Gruppierung, Reihenfolge, Lesefehler, echte Registry mit Schriftlizenz | – |
| `test/features/settings/presentation/settings_screen_test.dart` | Inhalt ohne funktionslose Elemente, Auswahlblatt, Schalter, Fehler, Links, Light, Dark und OLED | AT02, AT28, AT34, AT35, C06 |
| `.../licenses_screen_test.dart` | Liste, Texte, Paketliste, langer Text bei 320 px und 200 %, Laden, Fehler, leer | AT34 |
| `.../responsive_test.dart` | Einstellungen, Auswahlblatt und Lizenzen in der Größenmatrix | AT33 |
| `test/features/settings/architecture_test.dart` | Profil und Einstellungen fragen nie selbst eine Berechtigung an; keine festen Farben | AT28 |

Gewichte in den Tests sind Testdaten (71,5 kg, 74,0 kg, 68,0 kg) ohne Personenbezug; Uhr und Zone sind fix (Europe/Berlin). AT28 betrifft hier nur den Teil dieser Seiten (die Einstellungen bleiben bedienbar und fragen nichts an); Berechtigungsstatus und Planung gehören zum Erinnerungsblock.

## 7. Schnittstellen für andere Arbeitspakete

- **Shell:** Das Theme und die reduzierte Bewegung gehören in `MaterialApp` (`theme`, `darkTheme` = Dark oder OLED, `themeMode`) und in `ReducedMotionScope`. Das ist verdrahtet: `_AppView` in `lib/app/app.dart` liest `appSettingsProvider` und wendet beide Werte an (`appThemeModeProvider` und `reduceMotionProvider` sind Lesehilfen im Settings-Feature). Die Reichweite des Schalters für reduzierte Bewegung beschreibt [shell.md](shell.md), Abschnitt 2.
- **Haptik:** `appHapticsProvider.confirm()` ist der einzige Weg zu Vibration; Check-offs, Quick-Add und ähnliche Aktionen anderer Pakete rufen es nach dem Commit auf.
- **Erinnerungen:** Die Einstellungen setzen `RemindersSection` zwischen „Darstellung“ und „Module“ ein, ohne eigene Gruppenüberschrift; die Hauptzeile der Karte des Blocks heißt „Erinnerungen“ (Einzelheiten in [data-reminders.md](data-reminders.md)).
- **Routen:** `/profile`, `/profile/edit`, `/goals`, `/settings`, `/settings/licenses` (hier gebaut) sowie `/settings/modules`, `/settings/data`, `/streak`, `/progress` (Ziele von Links).

## 8. Offene Punkte

- Auf einem echten Gerät nicht prüfbar (kein SDK): TalkBack, tatsächliche Vibration, Größe und Ladezeit der echten Lizenzliste, Systemschrift.
- Designsystem: `AppTextField` mit `suffixText` und gefülltem Text löst bei aktiver Semantik die Assertion `node.isMergedIntoParent` aus (hier umgangen, andere Formulare mit Suffix sollten es prüfen). `AppHeader` bricht den langen Titel „Einstellungen“ bei 320 px und 200 % mitten im Wort. `EntryListTile.value` läuft bei langem Wert, 320 px und 200 % über (hier lokal gestapelt).
- Der Ziele-Editor arbeitet mit dem Stand beim Öffnen; ein über Mitternacht offener Editor zeigt „Heute noch“ bis zum erneuten Öffnen veraltet, gespeichert wird immer gegen den dann aktuellen Tag.
- Sehr lange Namen ohne Leerzeichen brechen bei 320 px und 200 % im Wort.
