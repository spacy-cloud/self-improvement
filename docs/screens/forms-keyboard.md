# Formulare und Tastatur (BS-112)

Dieses Dokument beschreibt, wie die Tastatur in den Formularen der App geschlossen wird: durch Tippen neben das Feld und durch Ziehen. Anlass ist Tylers iOS-Test ([BS-96](https://spacy-cloud.atlassian.net/browse/BS-96), iPhone 15 Pro): Die Zifferntastatur von iOS hat keine Eingabetaste, und iOS hat keine Zurück-Geste, die sie schließt. Ticket: [BS-112](https://spacy-cloud.atlassian.net/browse/BS-112), Entscheidung D-018 in [implementation-decisions.md](../implementation-decisions.md). Es gibt keinen Figma-Entwurf: Das Verhalten hat keinen eigenen Bildschirm, kein Formular ändert Aussehen oder Fachlogik.

## 1. Verhalten

**Tippen neben das Feld schließt die Tastatur**, unter Android wie unter iOS. Flutter lässt die Tastatur bei einer Berührung auf einem Mobilgerät sonst stehen. `dismissKeyboardOnTapOutside` (`lib/core/design/components/app_text_field.dart`) nimmt den Fokus, wenn ein Finger außerhalb des fokussierten Feldes aufsetzt. Das tun `AppTextField` selbst und die sechs großen Zahlenfelder ohne Rahmen (Gewicht, Schritte, Dauer des Workouts, Wasser, Ziele, Zeilen im Onboarding), die kein `AppTextField` sind. Drei Eigenschaften sind gewollt und getestet:

- **Eine Schaltfläche wirkt beim ersten Tipp.** Die Funktion hört nur auf das Aufsetzen und nimmt nicht an der Gestenarena teil; sie verschluckt nichts. Die Tastatur geht beim Aufsetzen, die angeheftete Aktion rutscht nach unten, während der Finger noch darauf liegt, und der Tipp löst sie trotzdem aus (im Host-Test nachgestellt: Finger aufsetzen, Tastatur-Einzug wegnehmen, Finger heben).
- **Der Wechsel zwischen Feldern stört nicht.** Alle Textfelder gehören zu einer Tippgruppe: Ein Tipp auf ein anderes Textfeld ist nicht „daneben“, die Tastatur wird auf dem Weg nicht versteckt und wieder gezeigt (kein `TextInput.hide` im Protokoll). Die Karte einer Onboarding-Zeile fokussiert ihr Feld bei jedem Tipp und zählt deshalb als Teil des Feldes (`TextFieldTapRegion`).
- **Der Fokus ist nach einer abgelehnten Eingabe wieder richtig.** Tippt jemand bei offener Tastatur auf „speichern“ und die Eingabe wird abgelehnt, geht der Fokus auf das erste fehlerhafte Feld und die Tastatur kommt zurück (BS-86, BS-90; getestet mit dem Aufgabenformular, Testname mit BS-90).

**Ziehen schließt die Tastatur.** `keyboardDismissBehavior: onDrag` steht an allen Scrollbereichen, in denen ein Eingabefeld liegen kann: `AppScaffold` (alle Formularseiten), `FormSheetFrame` (Sheets des Moduls Ernährung), `AppSheetFrame` (Sheet „Zurücksetzen“) und die Aufgabenliste mit ihrem Suchfeld; im Onboarding stand es schon. Grenzen: Es wirkt nur, wenn die Seite scrollt (der Inhalt ist höher als der Platz über der Tastatur) und wenn der Finger auf dem Feld aufsetzt, denn wer irgendwo sonst aufsetzt, hat die Tastatur schon durch das Tippen daneben geschlossen. Ein kurzes Sheet, das ganz über die Tastatur passt, scrollt nicht; dort bleibt das Tippen daneben (bei 200 % Schrift scrollt auch das Sheet „Tagesziel ändern“).

**Grenze auf iOS: Ziehen genau auf dem Cursor.** Auf iOS scrollt ein Ziehen, das genau auf dem Cursor eines fokussierten Feldes beginnt, die Seite nicht und schließt die Tastatur nicht; es bewegt den Cursor. Ursache ist das Textfeld von Flutter auf iOS: Es legt auf den Cursor einen unsichtbaren Griff (mindestens 48 x 48 px, mittig um den Cursor), der ein Ziehen sofort annimmt und vor dem Scrollbereich gewinnt, so wie sich der Cursor auf dem iPhone ziehen lässt. Das trifft die großen, zentrierten Zahlenfelder von Gewicht und Wasser (eigene Menge): Ist das Feld leer, steht der Cursor in seiner Mitte, wo ein Finger zuerst aufsetzt. Beginnt das Ziehen weiter als etwa 24 px vom Cursor entfernt, auf dem Rest des Feldes oder auf einem anderen Feld, schließt es die Tastatur wie beschrieben. **Tippen daneben schließt immer**, auch dort, wo ein Ziehen auf dem Cursor nichts bewirkt. Unter Android gibt es diese Grenze nicht. Im Host mit dem Theme von iOS belegt (Test mit R1-01 im Namen in `form_keyboard_test.dart`), auf einem iPhone nicht gesehen.

**Android.** Die Zurück-Geste schließt die Tastatur weiter. Neu ist das Schließen durch Tippen daneben; Ziehen schloss sie im Onboarding schon, jetzt in allen Formularen. Das Ticket nennt Android „unverändert außer dem Schließen durch Tippen daneben“; die Formulare schließen beim Ziehen auf beiden Plattformen, weil eine plattformabhängige Regel für Scrollbereiche mehr Aufwand und mehr Fälle bedeutet als der Nutzen (D-018).

**Nicht umgesetzt:** die „Fertig“-Leiste über der Zifferntastatur, die das Ticket als Option nennt, falls das nicht reicht. Ob es reicht, zeigt die Prüfung auf dem iPhone.

## 2. Wo es gilt

| Eingabe | Datei | Feld | Scrollbereich |
|---|---|---|---|
| Gewicht (Wert, Notiz) | `lib/features/body/presentation/weight_form_screen.dart` | Zahlenfeld, `AppTextField` | `AppScaffold` |
| Schritte | `lib/features/body/steps/presentation/steps_form_screen.dart` | Zahlenfeld | `AppScaffold` |
| Wasser: eigene Menge, Tagesziel | `lib/features/nutrition/presentation/water_custom_sheet.dart`, `water_goal_sheet.dart`, `water_form_body.dart`, `nutrition_widgets.dart` | Zahlenfeld (`NumberDisplayField`), `AppTextField` für die Notiz | `FormSheetFrame` |
| Mahlzeit | `lib/features/nutrition/presentation/meal_form_screen.dart` | `AppTextField` | `AppScaffold` |
| Workout | `lib/features/focus/presentation/workout_form_screen.dart` | `AppTextField`, Zahlenfeld (Dauer) | `AppScaffold` |
| Aufgabe, Gewohnheit | `lib/features/tasks/presentation/task_form_screen.dart`, `habit_form_screen.dart` | `AppTextField` | `AppScaffold` |
| Ziele | `lib/features/profile/presentation/goals_screen.dart` | Zahlenfelder | `AppScaffold` |
| Profil | `lib/features/profile/presentation/profile_edit_screen.dart` | `AppTextField` | `AppScaffold` |
| Notiz der Fokus-Sitzung | `lib/features/focus/presentation/focus_session_detail_screen.dart` | `AppTextField` | `AppScaffold` |
| Zurücksetzen | `lib/features/settings/presentation/data_sheets.dart` (`ResetSheet`) | `AppTextField` | `AppSheetFrame` |
| Suche der Aufgabenliste | `lib/features/tasks/presentation/tasks_list_view.dart` | `AppTextField` | `CustomScrollView` der Liste |
| Onboarding (Name, Alter, Größe, Gewicht, Ziele) | `lib/features/onboarding/presentation/widgets/value_field_row.dart`, `step_page.dart` | Zahlenfeld und Text in der Zeilenkarte | `StepPage` |

Eine neue Formularseite braucht nichts: Sie ist eine Seite von `AppScaffold`, und ihre `AppTextField` tragen die Funktion selbst. Ein rohes `TextField` muss sie übergeben, sonst scheitert der Quelltext-Regeltest.

## 3. Entscheidungen

- **Eine Funktion an jedem Feld statt einer Aktion an der Wurzel.** Flutter erlaubt, das Verhalten für die ganze App über `EditableTextTapOutsideIntent` zu überschreiben. Das ginge ohne Änderung an den Formularen, wäre aber unsichtbar, und die Host-Tests der einzelnen Widgets sähen es nicht. Der Auftrag verlangt das Verhalten zentral im `AppTextField`; die sechs rohen Felder bekommen dieselbe Funktion mit je einer Zeile, und ein Regeltest stellt sicher, dass kein weiteres vergessen wird.
- **Dateibesitz.** Die sechs Zahlenfelder liegen in Formularseiten; dort ist nur dieser eine Parameter hinzugekommen (Aufruf, kein Layout, keine Logik).
- **Ziehen auf beiden Plattformen** (siehe oben). Eine Einschränkung auf iOS bleibt möglich, falls die Prüfung auf einem Android-Gerät etwas Störendes zeigt.
- **Die Grenze am Cursor bleibt.** Der Griff auf dem Cursor gehört zum Verhalten des iOS-Textfelds (Cursor ziehen); ihn zu umgehen hieße, in die Auswahl der Felder einzugreifen (Cursor ziehen, Einfügen). Das ist nicht Ziel von BS-112, und Tippen daneben bleibt der verlässliche Weg. Die Grenze steht deshalb in diesem Dokument, in D-018 und in den bekannten Grenzen, und ein eigener Test hält sie fest: Ändert eine neue Flutter-Version das Verhalten, scheitert er und die drei Stellen werden überprüft.

## 4. Fokus und Barrierefreiheit

- Nach dem Schließen ist das Feld für den Screenreader nicht mehr fokussiert; Beschriftung, Hinweis und Fehlertext bleiben, Tippflächen (48 x 48) und Beschriftungen bleiben wie vorher (Richtlinien im Host-Test geprüft).
- Bei eingeschaltetem Screenreader löst das Doppeltippen zum Aktivieren (TalkBack, VoiceOver) nach unserem Verständnis von Flutter eine Semantik-Aktion aus und keine Berührung. Dann läuft `onTapOutside` nicht: Die Schaltfläche arbeitet wie bisher (im Host-Test mit einer Semantik-Aktion geprüft), die Tastatur schließt nicht von selbst, sondern mit der Geste des Systems oder durch Ziehen. Das ist aus dem Verhalten von Flutter abgeleitet und auf keinem Gerät gesehen.
- Der Fokus nach abgelehnter Eingabe (BS-86, BS-90), die Anfangsfoki und die Fokusreihenfolge sind unverändert; alle bisherigen Tests laufen weiter.

## 5. Tests

Befehle: `flutter test test/app/form_keyboard_test.dart test/app/keyboard_rules_test.dart test/core/design/components/keyboard_dismiss_test.dart test/features/onboarding/presentation/value_field_row_keyboard_test.dart`. Der Host hat keine Tastatur: `testTextInput.isVisible` ist das, was die App vom System verlangt hat (zeigen oder verstecken). Das ist der Nachweis dieser Tests, nicht das Verhalten der Tastatur eines iPhones. „Android“ und „iOS“ sind in den Variantentests die Plattform, mit der die App läuft: Das Theme der App trägt die Plattform der Variante (`AppTheme` hält je Plattform ein eigenes Theme), damit Scrollverhalten und Gesten der Textfelder die der Plattform sind, in jeder Reihenfolge der Tests (BS-98, R1-01). Jede Variante läuft auch einzeln (`--plain-name`) und mit zufälliger Reihenfolge (`--test-randomize-ordering-seed`).

| Datei | Inhalt | Abnahme-IDs |
|---|---|---|
| `test/core/design/components/keyboard_dismiss_test.dart` | Bausteine mit Android und iOS als Plattform: Tippen neben das Feld (`AppTextField`, Zahlenfeld), Tippen hinein, Wechsel zwischen Feldern ohne `hide`, Schaltfläche beim ersten Aufsetzen auch wenn die Tastatur geht und die Schaltfläche wandert, Ziehen in `AppScaffold` (auch mit Android und iOS), Screenreader (Feld nicht mehr fokussiert, Richtlinien, Aktivieren der Schaltfläche mit einer Semantik-Aktion bei offener Tastatur) | AT33, AT34 |
| `test/app/form_keyboard_test.dart` | zwölf Eingaben der laufenden App (Gewicht, Schritte, Wasser eigene Menge und Tagesziel, Mahlzeit, Workout, Aufgabe, Gewohnheit, Ziele, Profil, Zurücksetzen, Aufgaben-Suche) auf einem kleinen Telefon mit 300 px Tastatur: Tippen daneben und Ziehen (Start in der Mitte des Feldes, bei einem zentrierten leeren Feld auf iOS neben dem Cursor) mit Android und iOS, die Grenze am Cursor für Gewicht und Wasser eigene Menge (Ziehen genau auf dem Cursor: auf iOS weder Scrollen noch Schließen, auf Android Schließen; Tippen daneben schließt), Speichern beim ersten Tipp, Wechsel zum nächsten Feld; abgelehntes Speichern bei offener Tastatur; ein Durchlauf über jede Seite der App ohne Kennung, dass kein Textfeld ohne die Funktion oder ohne Ziehen-Verhalten bleibt | AT33 |
| `test/features/onboarding/presentation/value_field_row_keyboard_test.dart` | Onboarding-Zeilen: Wechsel zur Karte der nächsten Zeile ohne `hide`, Tippen auf die eigene Karte, Tippen daneben | AT33 |
| `test/app/keyboard_rules_test.dart` | Quelltext-Regeln: Jedes `TextField` in `lib/` übergibt `dismissKeyboardOnTapOutside`, die Scrollbereiche der Rahmen übergeben `onDrag` | AT33 |
| `test/core/design/app_theme_test.dart`, `test/support/pump_app_test.dart` | Das Theme trägt die Plattform, die gerade gilt, in jeder Reihenfolge der Anfragen; je Plattform und Variante eine Instanz; `pumpApp` und `pumpRouterApp` geben der Seite die Plattform des Tests (BS-98, R1-01) | AT33 |

Mutationsproben (Produktivcode zurückgenommen, die neuen Tests scheitern): siehe den Pull Request zu BS-112 und den Bericht.

## 6. Offene Punkte

- Auf einem Gerät nicht geprüft: das Verhalten der echten Tastatur eines iPhones (Schließen, Ruckeln beim Wechsel zwischen Feldern, ob die Zifferntastatur ohne „Fertig“-Leiste reicht; Prüfung durch Tyler, [BS-96](https://spacy-cloud.atlassian.net/browse/BS-96)), das Verhalten unter Android (Zurück-Geste, Tippen daneben, Ziehen), TalkBack und VoiceOver.
- Auf einem Gerät nicht geprüft: die Grenze am Cursor (Ziehen genau auf dem Cursor auf iOS). Der Host belegt sie mit den Gesten von Flutter und dem Theme von iOS; wie groß der Griff auf einem iPhone ist und ob ein Ziehen dort wirklich nur den Cursor bewegt, zeigt erst ein Gerät.
- Das Wandern der angehefteten Schaltfläche beim Einfahren der Tastatur ist im Host nachgestellt (Einzug von einem Bild zum nächsten weggenommen), nicht als Animation einer echten Tastatur.
- Optional und nicht umgesetzt: „Fertig“-Leiste über der Zifferntastatur (nur iOS).
- Die Notiz der Fokus-Sitzung hat keinen eigenen Test (die Route trägt eine Kennung); sie ist ein `AppTextField` in `AppScaffold` und von den Regeltests erfasst.
