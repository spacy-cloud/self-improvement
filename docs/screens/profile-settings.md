# Profil, Ziele und Einstellungen (BS-70)

Dieses Dokument beschreibt die Oberfläche des lokalen Profils, des Ziele-Editors, der Einstellungen, der Seite „Über die App“ (BS-118) und der Lizenzseite. Verbindlich waren in dieser Reihenfolge: die Regeln des Arbeitsauftrags, der Designstand (`docs/design-handoff.md`), die fachliche Spezifikation. Zahlen und Namen aus Figma sind Platzhalter; alle gezeigten Werte stammen aus der Datenbank.

## 1. Screens und Figma-Knoten

| Screen | Route | Figma (Light) | Klasse |
|---|---|---|---|
| Profil (Tab) | `/profile` | `4007:2` | `ProfileScreen` |
| Profil bearbeiten | `/profile/edit` | `4043:166` | `ProfileEditScreen` |
| Ziele bearbeiten | `/goals` | `4043:2` | `GoalsScreen` |
| Einstellungen | `/settings` | `4024:2`, Variante Erinnerungen verweigert `4055:416` (nur Bildvorlage des fremden Erinnerungsblocks), Zeile „Version“ antippbar `4119:254` (BS-118) | `SettingsScreen` |
| Über die App | `/settings/about` | `4119:418`, Dunkel `4119:512`, OLED `4119:606` (Seite „v0.2.0 – Neue Screens“, BS-118) | `AboutScreen` |
| Lizenzen | `/settings/licenses` | `4056:558` | `LicensesScreen` |

Dark und OLED stammen aus den Token-Modi; es gibt keine eigenen Frames dafür (Ausnahme: „Über die App“ hat eigene Frames, die mit den Token-Modi verglichen wurden). Die Routen `/settings/modules` und `/settings/data` gehören anderen Arbeitspaketen, die Einstellungen verlinken nur dorthin.

Code: `lib/features/profile/{domain,application,presentation}` und `lib/features/settings/{application,presentation}`. Die Fachlogik liegt in reinen Dart-Funktionen (`profile_input`, `goal_editor`, `profile_overview`), die Widgets enthalten keine Regeln und keinen SQL-Code. Gespeichert wird ausschließlich über die vorhandenen Commands (`ProfileCommands`, `GoalsCommands`, `SettingsCommands`) mit dem `SubmissionTracker`-Muster: gleicher Inhalt beim Wiederholen ergibt dieselbe Command-ID, ein zweiter Tipp während des Speicherns wird ignoriert.

## 2. Verhalten je Screen

**Profil.** Karte mit Initialen (höchstens zwei Namensteile) oder neutralem Profilsymbol, Name oder „Mein Profil“, „Dabei seit Monat Jahr“. Kennzahlen nur mit Daten: „Tage Streak“ und „Aktive Tage“ (nur bei eingeschalteter Gamification, Streak ist ein Link), „seit Start“ nur mit ausdrücklichem Startgewicht und aktueller Messung. Zeile „Fortschritt“ (Level und XP) nur bei eingeschalteter Gamification. „Meine Ziele“ zeigt die Ziele der eingeschalteten Module, ein Ziel mit Änderung ab morgen zeigt „Ab morgen: …“. „Körperdaten“ erscheint nur, wenn Größe, Startgewicht oder Alter vorhanden sind; es gibt keinen BMI. Zustände: Laden (neutral), Fehler mit „Erneut versuchen“, leer (alle Module aus: „Keine Ziele sichtbar“ mit Weg zur Modulverwaltung). Links: Bearbeiten, Ziele, Streak, Fortschritt, Einstellungen.

**Profil bearbeiten.** Name (optional, höchstens 40 Zeichen nach Trimmen, leer bedeutet „Mein Profil“), Größe 100 bis 250 cm, Alter 18 bis 120 Jahre, Start- und Zielgewicht 20,0 bis 350,0 kg mit einer Nachkommastelle (Komma oder Punkt). Alles ist optional. Die Initialen-Vorschau folgt dem Namen live. Das Zielgewicht gilt sofort. Wird ein Zielgewicht neu gesetzt oder geändert und gibt es kein Startgewicht, schlägt die Seite die letzte Messung vor („Als Startgewicht übernehmen“); erst der Tipp trägt den Wert ins Formular ein, gespeichert wird mit dem Formular. Profilwerte werden nie zu Messungen und Messungen nie still zu Profilwerten. Ist das Körpermodul aus, sind die Körperfelder ausgeblendet und ihre gespeicherten Werte bleiben unverändert.

**Ziele bearbeiten.** Wasser (250 bis 10.000 ml in 50er-Schritten), Schritte (100 bis 100.000), Fokus (5 bis 180 Minuten), „Gewicht erfassen“ und „Aufgabe erledigen“ (Schalter), Workouts pro Woche (1 bis 14). Wasser, Schritte und Fokus haben je einen eigenen Schalter; ein ausgeschaltetes Ziel behält seinen Wert und meldet in Worten „Ausgeschaltet: zählt nicht für den Tagesring.“ Alle Zielwerte und Schalter gelten ab morgen (Hinweisbox mit Datum, Gruppentitel „… · ab morgen“, Erfolgsmeldung „… gelten ab morgen“). Eine heute bereits gespeicherte Änderung wird beim Öffnen angezeigt („Heute noch: …“). Das Zielgewicht gilt sofort (Gruppe „Körperziel · gilt sofort“) und wird über `ProfileCommands` gespeichert; die Erfolgsmeldung nennt, was wann gilt. Speichern von Zielen und Zielgewicht sind zwei Commands: gelingt das erste und scheitert das zweite, bleibt das erste gespeichert, die Meldung sagt das, und die Wiederholung sendet nur noch das zweite. Ziele ausgeschalteter Module sind ausgeblendet, bleiben gespeichert und werden nicht validiert.

**Einstellungen.** Profil-Eintrag („Nur lokal“), Design (Auswahlblatt mit System, Hell, Dunkel, OLED; „System“ wird bei dunklem Gerät Dunkel, OLED nur ausdrücklich), Reduzierte Bewegung, Haptisches Feedback, Erinnerungsblock (`RemindersSection`, gebaut vom Erinnerungs-Paket, siehe [data-reminders.md](data-reminders.md)), Module („N von 5“), Daten & Sicherung, Version (Wert, Pfeil, antippbar, öffnet „Über die App“) und Lizenzen. Außerhalb des Erinnerungsblocks gibt es genau zwei Schalter und keine Konto- oder Cloud-Elemente. Jede Änderung ist ein eigener Command; scheitert das Schreiben, bleibt der Schalter auf dem gespeicherten Wert und eine Fehlermeldung bietet „Erneut“ an.

**Über die App (BS-118).** Öffnet über die Zeile „Version“ der Einstellungen; Zurück und Android-Zurück führen in die Einstellungen (ohne Seite darunter, zum Beispiel nach einem Sprung von außen, führt Zurück nach `/settings`). Von oben nach unten: App-Symbol (das Zeichen des Onboardings, nur Dekoration), App-Name (`AppConfig.appName`) und „Version 1.0.0 (Build 1)“ aus `AppConfig.appVersion` und `AppConfig.buildNumber`; die Gruppe „Über die App“ mit „Autor“ („Spacy.cloud“), „Website“ („spacy.cloud/self-improvement“, antippbar), „Datenschutz“ („Alle Daten bleiben auf dem Gerät. Kein Konto, keine Cloud, keine Telemetrie.“) und „Technische Angaben“ („Daten-Schema N · Backup-Format M“ aus `AppDatabase.currentSchemaVersion` und `BackupFormat.schemaVersion`, für Support und Import); darunter eine eigene Gruppe mit „Lizenzen“ („Lizenzen der verwendeten Pakete“), die zur Seite „Lizenzen“ springt. Es gibt keinen GitHub-Link, keinen Namen einer Einzelperson und kein „Team IA24“. Ganz unten steht der Abschnitt „Lizenz“ (siehe unten, BS-120). Die Seite ist eine Unterseite mit scrollendem Inhalt.

Die Zeile „Website“ übergibt `https://spacy.cloud/self-improvement` an den Browser des Systems (`ExternalLinkOpener`, Paket `url_launcher`, Modus `externalApplication`, kein `canLaunchUrl`; Entscheidung D-020 in [implementation-decisions.md](../implementation-decisions.md)). Nimmt kein Browser die Adresse an, kopiert die Seite sie in die Zwischenablage und zeigt „Kein Browser gefunden. Die Adresse spacy.cloud/self-improvement wurde kopiert.“; scheitert auch das Kopieren, zeigt sie „Die Adresse konnte nicht geöffnet werden: spacy.cloud/self-improvement“. Ein zweiter Tipp, solange der erste noch läuft, wird ignoriert; die Antwort erreicht den Nutzer auch, wenn er die Seite inzwischen verlassen hat. Die App selbst lädt nichts aus dem Netz: Das Release-Manifest hat kein INTERNET, die Adresse geht nur nach einem Tipp an den Browser. Die Version hat eine Quelle, die `version` der `pubspec.yaml` (Android `versionName`, iOS `CFBundleShortVersionString`); ein Test gleicht `AppConfig.appVersion` und `AppConfig.buildNumber` damit ab, und die Einstellungen, die Seite und das Backup-Feld `appVersion` lesen dieselben Konstanten.

**Lizenz (BS-120).** Der Abschnitt „Lizenz“ ganz unten auf „Über die App“ zeigt den vollständigen Lizenztext des eigenen Codes: die MIT-Lizenz mit der Zeile „Copyright (c) 2026 Spacy.cloud“. Die eine Quelle ist die Datei `LICENSE` im Repository: Sie ist als Asset in der `pubspec.yaml` eingetragen und wird mit `rootBundle` geladen (`own_license.dart`, Entscheidung D-021 in [implementation-decisions.md](../implementation-decisions.md)); es gibt keine Konstante und keine zweite Kopie des Textes. Die Seite zerlegt die Datei an den Leerzeilen in Absätze und setzt jeden Absatz in eine Zeile (die Datei bricht bei 80 Zeichen um); kein Wort wird geändert, hinzugefügt oder ausgelassen. Der Kartentitel ist die erste Zeile der Datei („MIT License“), darunter stehen die Copyright-Zeile und die drei Absätze der Lizenz in der kleinen Schrift des Entwurfs (12 px, Sekundärfarbe, 10 px Abstand). Der Text ist die englische Originalfassung und als Englisch markiert (`Semantics.localeForSubtree`), damit ein Screenreader die passende Stimme wählen kann. Zustände: „Lizenztext wird geladen …“ (Live-Region); bei einem Lesefehler oder einer Datei ohne Text der Fehlerzustand „Lizenztext konnte nicht geladen werden“ mit „Erneut versuchen“, der Rest der Seite bleibt bedienbar. Der Rechteinhaber „Spacy.cloud“ steht seit BS-120 in `LICENSE` und in der README (Abschnitt Lizenz); die Herkunftsangaben (README Zeile 3, `docs/design-handoff.md`, Beschreibung in der `pubspec.yaml`) bleiben unverändert.

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
| Einstellungen und Über die App, Version | „0.2.0“ und „Version 0.2.0 (Build 2)“ | zeigt `AppConfig.appVersion` und `AppConfig.buildNumber`, derzeit „1.0.0“ und „Version 1.0.0 (Build 1)“ | Die Anhebung auf 0.2.0+2 gehört in den Release-PR; die Anzeige liest nur die Konstanten, die ein Test mit der `pubspec.yaml` abgleicht. |
| Über die App, Technische Angaben | „Daten-Schema 2 · Backup-Format 2“ | liest `AppDatabase.currentSchemaVersion` und `BackupFormat.schemaVersion`, auf diesem Stand 1 und 1 | Die 2 des Entwurfs ist der Stand des Datenvertrags (BS-98); nichts ist fest verdrahtet, die Seite folgt den Konstanten, sobald der Datenvertrag gemergt ist. |
| Über die App, Lizenztext | Kartentitel „MIT-Lizenz“ | Kartentitel „MIT License“, die erste Zeile der Datei `LICENSE` | Eine Quelle: Die Anzeige ist die Datei, ohne eine zweite, deutsche Überschrift im Code; der Abschnittskopf „Lizenz“ ist deutsch. |
| Über die App, Zeilen | Innenabstand 12 px oben und unten, Pfeile 16 px | `EntryListTile`: 8 px, Pfeil und Symbol 20 px; Trennlinien über die ganze Kartenbreite wie im Entwurf | Es gelten die Maße der vorhandenen Komponente (Mindesthöhe 56 wie im Entwurf); mehrzeilige Zeilen sind dadurch bis zu 8 px niedriger. |
| Über die App, Symbole | `icon/user`, `icon/globe`, `icon/ext`, `icon/shield`, `icon/db`, `icon/doc` | `Icons.person_outline_rounded`, `Icons.language_rounded`, `Icons.open_in_new_rounded`, `Icons.shield_outlined`, `Icons.storage_rounded`, `Icons.description_outlined` | Material-Entsprechungen wie im Designstand (Abschnitt 8.3); für die Datenbank gibt es kein Zylindersymbol, `storage` ist das nächste. |
| Über die App, App-Symbol | im Dunkel- und OLED-Entwurf dasselbe Grün wie in Hell | Verlauf aus den Token-Farben des Themes (`primary` zu `primaryButton`), wie das Zeichen im Onboarding | Eine Quelle für das Zeichen in allen Themes; in Dunkel und OLED ist das Grün der Token etwas heller als im Entwurf. |
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
| Ticket BS-118 nennt beim Datenschutz einen zweiten Satz („Die App selbst greift nicht aufs Netz zu, die Website wird nur auf Tipp im externen Browser geöffnet“), der Entwurf zeigt nur den ersten | Entwurf: nur der erste Satz. Die Zeile „Website“ sagt „öffnet im Browser“; dass die App selbst nichts lädt, belegen das Manifest (kein INTERNET) und ein Test. |
| Ticket BS-118: TalkBack liest „Website, öffnet im Browser“; der gesprochene Name soll aber den sichtbaren Text enthalten (WCAG 2.5.3) | Die Zeile spricht zusätzlich die sichtbare Adresse: „Website, spacy.cloud/self-improvement, öffnet im Browser“. |

## 5. Barrierefreiheit

- Tippziele mindestens 48 x 48, geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` bei 320, 360, 393 und 430 px und den Textskalen 1,0 und 2,0 für alle sechs Screens (mit „Über die App“) und das Auswahlblatt.
- Jede Icon-Taste, jeder Schalter, jeder Stepper hat ein deutsches Label („Wasser um 250 Milliliter erhöhen“); Schalter sprechen ihren Zustand, das Auswahlblatt nennt „ausgewählt“, Zustände stehen immer auch im Text (zum Beispiel „Ausgeschaltet: zählt nicht für den Tagesring.“).
- Fehler stehen mit Symbol und Text am Feld; nach einem abgelehnten Speichern bekommt das erste fehlerhafte Feld den Fokus (der Screenreader liest Feld und Meldung zusammen) und eine Zusammenfassung erscheint als Live-Region direkt über dem Speichern-Button. Die Eingabe bleibt in jedem Fehlerfall erhalten.
- Die Speichern-Taste ist am unteren Rand festgesetzt und liegt bei geöffneter Tastatur darüber (getestet mit 300 px Tastaturhöhe bei Skala 2,0). Der Inhalt scrollt; es gibt keine reinen Gesten.
- Ungespeicherte Änderungen fragen „Änderungen verwerfen?“ (Standard „Weiter bearbeiten“, Android-Zurück eingeschlossen). Das Auswahlblatt hat „Schließen“ und schließt auch mit Android-Zurück.
- Bewegung folgt `AppMotion` (der Schalter animiert 150 ms, bei reduzierter Bewegung sofort). Haptik hängt am Schalter und beeinflusst die Bewegungseinstellung nicht.
- Über die App: Seitentitel, App-Name und Gruppenkopf sind Überschriften. Die Zeile „Website“ ist eine Schaltfläche mit „Website, spacy.cloud/self-improvement, öffnet im Browser“, die Zeile „Lizenzen“ eine mit „Lizenzen der verwendeten Pakete“, die Zeile „Version“ der Einstellungen eine mit „Version 1.0.0, Details öffnen“ (die Nummer folgt der Konstanten). Die übrigen Zeilen sind Text („Autor, Spacy.cloud“, „Technische Angaben, Daten-Schema 1, Backup-Format 1“, gesprochen ohne Mittelpunkt); das App-Symbol ist Dekoration ohne Semantik. Die Seite scrollt bei 200 % Schrift bis zur letzten Karte, die untere Kartenkante bleibt 16 px über dem Rand; der Seitenwechsel folgt wie bei „Lizenzen“ dem Schalter „Reduzierte Bewegung“ (`about_route_test.dart`).
- Lizenz: Der Gruppenkopf „Lizenz“ ist eine Überschrift, jeder Absatz der Lizenz ein eigener Knoten mit seinem Text (zum Vorlesen Absatz für Absatz), der englische Text ist als Englisch markiert. Bei 200 % Schrift ist der letzte Absatz höher als der Bildschirm; die Seite scrollt bis zu seinem Ende, die Karte endet 16 px über dem Rand. Die Karte hat keine Bedienelemente; Farben und Schriften kommen aus den Tokens des Themes (Hell, Dunkel, OLED).

## 6. Tests

Befehle: `flutter test test/features/profile test/features/settings`. Von den 459 Tests dieser Verzeichnisse gehören 370 zu diesem Paket (profile/domain 53, profile/application 52, profile/presentation 104, settings/application 51, settings/presentation 107, Architekturtest 3; seit BS-118 und BS-120 kommen 73 Tests dazu, im Verzeichnis `test/app` und in `test/platform` stehen weitere, siehe unten); die übrigen 89 unter `settings/data` gehören zur Daten-Oberfläche ([data-reminders.md](data-reminders.md)). Den Gesamtstand und die Ergebnisse von `flutter analyze` und `dart format` nennt [test-report.md](../test-report.md).

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
| `test/features/settings/presentation/settings_screen_test.dart` | Inhalt ohne funktionslose Elemente, Zeile „Version“ als Link (auch bei 200 % Schrift), Auswahlblatt, Schalter, Fehler, Links, Light, Dark und OLED | AT02, AT28, AT34, AT35, C06 |
| `.../licenses_screen_test.dart` | Liste, Texte, Paketliste, langer Text bei 320 px und 200 %, Laden, Fehler, leer | AT34 |
| `.../about_screen_test.dart` | Seite „Über die App“ (BS-118): Inhalt aus den Konstanten, keine Namen und keine GitHub-Adresse, Navigation (Version-Zeile, Zurück, Android-Zurück, Sprung von außen, Lizenzen), Website (Öffnen, Kopieren, Kopieren scheitert, Doppeltipp, Antwort nach dem Verlassen), Semantik und Überschriften, 200 % mit Platz unten, drei Themes | AT33, AT34, AT35 |
| `.../about_license_test.dart` | Abschnitt „Lizenz“ (BS-120): Überschrift und Karte am Ende der Seite, voller Text der Datei in Reihenfolge, je Absatz ein Text, die Anzeige folgt der Quelle (keine zweite Kopie), Stile, Laden, Fehler mit Wiederholen, Datei ohne Text, Semantik und Sprache, 200 % bis zur letzten Zeile, drei Themes | AT33, AT34, AT35 |
| `.../responsive_test.dart` | Einstellungen, Auswahlblatt, Über die App (bis zur letzten Zeile der Lizenz) und Lizenzen in der Größenmatrix | AT33 |
| `test/features/settings/application/about_actions_test.dart` | `AboutInfo` (Zeilen aus den Konstanten), `AboutActions` mit Fake-Opener (BS-118), der echte Adapter am Plattformkanal von `url_launcher`: externer Modus, kein `canLaunchUrl`, Fehlschlag ohne Ausnahme | – |
| `test/features/settings/application/own_license_test.dart` | Zerlegung in Absätze (Zeilenumbrüche, Windows-Zeilenenden, Datei ohne Text); `LICENSE` nennt Spacy.cloud und enthält sonst den Standardtext der MIT-Lizenz; die README nennt Spacy.cloud; keine Zeile mit „Copyright“ nennt im ganzen Repository den alten Inhaber; das Asset in der `pubspec.yaml` und im App-Bundle ist die Datei (BS-120) | – |
| `test/features/settings/architecture_test.dart` | Profil und Einstellungen fragen nie selbst eine Berechtigung an; keine festen Farben; Web-Adressen nur über einen Adapter, im externen Modus und ohne `canLaunchUrl` | AT28 |
| `test/app/about_route_test.dart` | die Seite in der laufenden App: Zeile „Version“, Zurück, keine Navigationsleiste, Übergang mit und ohne reduzierte Bewegung (BS-118) | AT35 |
| `test/app/route_sweep_test.dart`, `router_guards_test.dart`, `route_guard_test.dart` | `/settings/about` im Routen-Durchlauf (fünf Größen, mit Daten, Dark und OLED), in der Routentabelle und bei den Kernrouten | AT33, AT35, C02 |
| `test/core/config/app_config_test.dart` | `AppConfig.appVersion` und `AppConfig.buildNumber` gleichen die `version` der `pubspec.yaml` ab (BS-118) | – |
| `test/platform/url_launcher_manifest_test.dart` | das Manifest des Android-Teils von `url_launcher` enthält keine Berechtigung (kein INTERNET) und keine `<queries>`; Paket und Plattformteile stehen im Lockfile | – |

Gewichte in den Tests sind Testdaten (71,5 kg, 74,0 kg, 68,0 kg) ohne Personenbezug; Uhr und Zone sind fix (Europe/Berlin). AT28 betrifft hier nur den Teil dieser Seiten (die Einstellungen bleiben bedienbar und fragen nichts an); Berechtigungsstatus und Planung gehören zum Erinnerungsblock.

## 7. Schnittstellen für andere Arbeitspakete

- **Shell:** Das Theme und die reduzierte Bewegung gehören in `MaterialApp` (`theme`, `darkTheme` = Dark oder OLED, `themeMode`) und in `ReducedMotionScope`. Das ist verdrahtet: `_AppView` in `lib/app/app.dart` liest `appSettingsProvider` und wendet beide Werte an (`appThemeModeProvider` und `reduceMotionProvider` sind Lesehilfen im Settings-Feature). Die Reichweite des Schalters für reduzierte Bewegung beschreibt [shell.md](shell.md), Abschnitt 2.
- **Haptik:** `appHapticsProvider.confirm()` ist der einzige Weg zu Vibration; Check-offs, Quick-Add und ähnliche Aktionen anderer Pakete rufen es nach dem Commit auf.
- **Erinnerungen:** Die Einstellungen setzen `RemindersSection` zwischen „Darstellung“ und „Module“ ein, ohne eigene Gruppenüberschrift; die Hauptzeile der Karte des Blocks heißt „Erinnerungen“ (Einzelheiten in [data-reminders.md](data-reminders.md)).
- **Routen:** `/profile`, `/profile/edit`, `/goals`, `/settings`, `/settings/licenses` und `/settings/about` (hier gebaut) sowie `/settings/modules`, `/settings/data`, `/streak`, `/progress` (Ziele von Links).

## 8. Offene Punkte

- Auf einem echten Gerät nicht prüfbar (kein SDK): TalkBack, tatsächliche Vibration, Größe und Ladezeit der echten Lizenzliste, Systemschrift.
- Lizenz, auf keinem Gerät geprüft (Abnahme ausstehend, BS-120): Lesbarkeit des Textes ganz unten bei 200 % Schrift auf S25 und iPhone, die Wirkung der Sprachmarkierung (`localeForSubtree`) und die Aussprache des englischen Textes mit TalkBack und VoiceOver.
- Über die App, auf keinem Gerät geprüft (Abnahme ausstehend, BS-118): dass ein Tipp auf „Website“ den Browser mit `https://spacy.cloud/self-improvement` öffnet und Zurück in die App führt, das Verhalten ohne Browser, TalkBack und VoiceOver. Der Host-Test belegt den Aufruf (Adresse, externer Modus) am Plattformkanal, nicht den Browser. Das gemergte Android-Manifest ist nur nach einem Android-Build prüfbar (CI).
- Designsystem: `AppTextField` mit `suffixText` und gefülltem Text löst bei aktiver Semantik die Assertion `node.isMergedIntoParent` aus (hier umgangen, andere Formulare mit Suffix sollten es prüfen). `AppHeader` bricht den langen Titel „Einstellungen“ bei 320 px und 200 % mitten im Wort. `EntryListTile.value` läuft bei langem Wert, 320 px und 200 % über (hier lokal gestapelt).
- Der Ziele-Editor arbeitet mit dem Stand beim Öffnen; ein über Mitternacht offener Editor zeigt „Heute noch“ bis zum erneuten Öffnen veraltet, gespeichert wird immer gegen den dann aktuellen Tag.
- Sehr lange Namen ohne Leerzeichen brechen bei 320 px und 200 % im Wort.
