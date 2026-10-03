# Daten & Sicherung und Erinnerungen (BS-72, BS-73, BS-77)

Dieses Dokument beschreibt die Oberfläche für die lokale Sicherung (Export, Import mit Vorschau, Zurücksetzen) und den Erinnerungsblock der Einstellungen mit dem Berechtigungs-Sheet. Die Fachlogik liegt in den Engines (`lib/core/backup`, `lib/core/notifications`, beschrieben in [backup-format.md](../backup-format.md) und in den Doc-Kommentaren von `ReminderService`); hier steht, was die Oberfläche daraus macht, wo sie vom Design abweicht und was die App beim Start verdrahten muss.

## 1. Screens und Figma-Knoten

| Screen / Baustein | Figma-Knoten | Route / Einbettung | Datei |
|---|---|---|---|
| Daten & Sicherung | `4044:2` | `/settings/data` (`DataScreen`) | `lib/features/settings/presentation/data_screen.dart` |
| Import-Vorschau (Sheet) | `4055:160` | Modal auf `/settings/data` | `lib/features/settings/presentation/data_sheets.dart` (`ImportPreviewSheet`) |
| Import nicht möglich (Sheet) | `4055:244` | Modal auf `/settings/data` | `data_sheets.dart` (`ImportRejectedSheet`) |
| Zurücksetzen bestätigen (Sheet) | `4044:117` | Modal auf `/settings/data` | `data_sheets.dart` (`ResetSheet`) |
| Erinnerungsblock | `4055:416` (Einstellungen, Erinnerungen abgelehnt) | `RemindersSection`, eingebettet in `/settings` | `lib/features/reminders/presentation/reminders_section.dart` |
| Erinnerungen erlauben (Sheet) | `4055:317` | Modal, nur beim Einschalten | `lib/features/reminders/presentation/reminder_permission_sheet.dart` |

Weitere Dateien: `lib/features/settings/application/data_backup_actions.dart` (Fassade über `BackupService`/`ResetService`, typisierte Ergebnisse), `data_backup_rules.dart` (reine Regeln: Wortprüfung, Zählung, lesbare Ablehnungsgründe, Import-Hinweise), `lib/features/reminders/application/reminder_actions.dart` (Fassade über `ReminderService`, Command-IDs nach dem `SubmissionTracker`-Muster), `reminder_data_ports.dart` (echter `NotificationCanceller`, Replan-Listener, `CompositeBackupListener`), `reminder_labels.dart` (alle Zustandstexte als reine Funktionen), `sheet_frame.dart` (gemeinsamer Rahmen der Sheets: Griff, Titelzeile mit Schließen, scrollender Inhalt, angeheftete Aktionen).

## 2. Verhalten

**Export.** "Jetzt exportieren" zeigt zuerst den Hinweis, dass die Sicherung persönliche Einträge unverschlüsselt enthält (Fortfahren / Abbrechen, Spezifikation 20.1). Danach wird die Datei im Cache erstellt (`exportBackup`) und das System-Teilen-Menü geöffnet (`shareBackup`). Rückmeldung: erfolgreich geteilt (Anzahl der Einträge), Teilen abgebrochen ("nichts weitergegeben"), unbekanntes Ergebnis ("Ob sie angekommen ist, kann die App nicht prüfen"), Fehler mit "Erneut". Wäre die Datei beim Import abgelehnt worden (`isRestorable == false`), fragt die App vor dem Teilen nach ("Trotzdem teilen"). Es gibt keinen Upload; die temporäre Datei wird nach dem Teilen gelöscht, ein abgebrochener Export räumt sie sofort weg. Auch die Kopie einer importierten Datei bleibt nicht liegen: Der Android-Picker legt sie im Cache an (`<Cache>/<UUID>/<Name>`), die App löscht sie, sobald die Bytes gelesen sind (`FileSelectorBackupFilePicker`); Reste nach einem beendeten Prozess entfernen App-Start und Zurücksetzen (UUID-Ordner des Caches, die nur JSON-Dateien enthalten).

**Import.** "Sicherung auswählen" öffnet die Systemauswahl; danach läuft die vollständige Prüfung ohne jede Änderung. Gültig: Vorschau mit Datei, Erstellzeitpunkt, Profilname, Zahl der Einträge, App-Version, Format, Inhalt je Bereich und Hinweisen aus dem echten Dateiinhalt (andere App-Version, keine Einträge, offene Fokus-Sitzung wird pausiert, Erinnerungswunsch wird nicht als Berechtigung gelesen). Die Warnung "Vorhandene App-Daten (N Einträge) werden vollständig ersetzt" steht direkt über der Bestätigung. Erst "Ersetzen und wiederherstellen" ersetzt alles in einer Transaktion; schlägt das fehl, bleibt das Sheet mit der Fehlermeldung offen und der Bestand unverändert. Ungültig oder fremd: "Import nicht möglich" mit lesbaren Gründen (Bereich und Position, zum Beispiel "Gewichtseinträge, Eintrag 4: …", höchstens fünf plus Hinweis auf weitere), nichts ändert sich, "Andere Datei wählen" öffnet die Auswahl erneut. Abbrechen der Auswahl oder des Sheets ändert nichts und sagt nichts.

**Zurücksetzen.** "Zurücksetzen …" öffnet das Sheet mit den Folgen und einem Feld. "Alles löschen" ist nur aktiv, wenn genau `LÖSCHEN` getippt wurde (Groß-/Kleinschreibung, keine Leerzeichen). Eine fast richtige Eingabe (anderer Fall, Leerzeichen am Rand) bekommt einen Hinweis statt Stille. "Erst Sicherung exportieren" startet den Exportablauf, "Abbrechen" ändert nichts. Nach dem Löschen (Profil und Einstellungen sind wie bei einer Neuinstallation neu angelegt, geplante Erinnerungen und Cache-Dateien entfernt) navigiert der Screen zur Startroute `/`; die Weiterleitung auf das Onboarding macht der Router.

**Erinnerungen.** Standard ist aus; nichts fragt früh nach der Berechtigung. Beim Einschalten liest die App den echten Gerätezustand. Ist die Berechtigung erteilt, wird direkt eingeschaltet und geplant. Sonst erscheint das Sheet "Erinnerungen erlauben?" mit dem Gerätestatus und drei Wegen: "Weiter zur Android-Abfrage" (Systemdialog, danach Planung), "Einstellungen öffnen" (Wunsch wird gespeichert, kein Systemdialog) und "Später" (Schließen, Zurück und Tippen neben das Sheet haben dasselbe Ergebnis, Erinnerungen bleiben aus). Wird die Berechtigung verweigert, bleibt der Wunsch an und der Block zeigt "Im System blockiert" mit Banner und "Öffnen" zu den Systemeinstellungen; die App bleibt voll nutzbar. Beim Zurückkehren aus den Einstellungen (App wird wieder aktiv) liest der Block den Zustand neu und plant, falls inzwischen erlaubt. Weitere Zustände: nicht verfügbar ("Erneut prüfen"), Planungsfehler mit Ursache und "Wiederholen", Ausschalten (alles Geplante wird entfernt; scheitert das beim System, sagt der Block es). Die Trink-Uhrzeiten 10, 12, 14, 16 und 18 Uhr sind als Chips frei kombinierbar, auch bei ausgeschalteten Erinnerungen; sie werden gespeichert und sofort geplant; schnelle Taps auf zwei Chips laufen nacheinander und landen beide im Bestand. Ist das Modul Ernährung aus, sagt der Block, dass keine Trink-Erinnerungen kommen. Die Liste "Geplante Erinnerungen" zeigt nur, was noch bevorsteht (keine Zustellhistorie); ein Tipp öffnet das Ziel wie ein Tipp auf die Benachrichtigung (ausgeschaltetes Modul: Dashboard, gelöschte Gewohnheit: Gewohnheitsliste). Der Block verspricht nie eine Zustellung: er nennt "geplant", den Systemstatus und den Hinweis aus `ReminderTexts.deliveryNotice` (ungenau getaktet, nach erzwungenem Beenden erst nach dem nächsten Öffnen), bei Überschreitung die Grenze aus `ReminderTexts.limitNotice`.

## 3. Abweichungen vom Figma-Design

| Thema | Figma | Umsetzung | Grund |
|---|---|---|---|
| "Letzte Sicherung: …" | Chip im Exportblock | entfällt | Es wird kein Zeitpunkt gespeichert (kein Schemafeld); kein erfundener Wert. Offener Punkt. |
| Text im Exportblock | "… in deinen Cloud-Speicher legen" | "Im Teilen-Menü entscheidest du, wohin sie geht." | Auftrag: kein Cloud-Bezug; die App lädt nichts hoch. |
| Vorschau "Zeitraum" | Zeitraum der Einträge | "Erstellt am", dazu App-Version, Format, Inhalt je Bereich, Hinweise | Die Engine liefert keinen Zeitraum; die Bereichszahlen und Hinweise verlangt der Auftrag. |
| Vorschau "214 Einträge seit 1. Aug." | aktuelle Daten mit Datum | "(N Einträge)" ohne Datum, live gezählt; ohne Zahl, wenn das Zählen scheitert | Kein Datum verfügbar, keine erfundene Zahl. |
| Reset-Sheet | zentriert, ohne Eingabefeld, ohne Schließen | Eingabefeld für `LÖSCHEN`, Titelzeile mit Schließen wie die anderen Sheets | Auftrag und Spezifikation 20.3 verlangen den getippten Text. |
| Export-Hinweis | nicht vorhanden | Bestätigungs-Sheet vor dem Export | Spezifikation 20.1. |
| Erinnerungsblock | drei Schalter (Wiege-, Trink-, Habit-Erinnerung) | ein Hauptschalter, Trink-Uhrzeiten als Chips, Hinweis zu Gewohnheiten und Fokus, Liste der geplanten Erinnerungen | V1 kennt Wasser (5 Slots), Gewohnheit (Uhrzeit je Gewohnheit) und Fokus-Ende; keine Wiege-Erinnerung, keine unimplementierten Schalter. |
| Banner "Benachrichtigungen sind blockiert" | Button rechts neben dem Text | Button unter dem Text | Passt auf 320 px und bei 200 % Schrift. |
| Sheets | randlos am unteren Rand | schweben mit 16 px Rand wie `ConfirmationSheet`, Aktionen bleiben angeheftet, solange Platz ist | Festlegung im Design-Handoff (8.4); lange Vorschau schiebt die Bestätigung nicht aus dem Bild. |
| Symbolkacheln | graue Kacheln | lokale graue Kachel, Zurücksetzen mit `AppIconTile` (Fehlerton) | Das Designsystem hat nur getönte Kacheln. |
| Hauptzeile bei sehr großer Schrift | Symbolkachel immer | Kachel entfällt ab 150 % Schrift | Das Wort "Erinnerungen" bräche sonst mitten im Wort. |
| Zurücksetzen-Button | gefüllt rot | gefüllt rot (lokal, `onError` auf `error`), grau bis das Wort stimmt | `SecondaryButton(danger)` ist nur umrandet. |

## 4. Konflikte und Entscheidungen

- **Eingabe `LÖSCHEN`.** `ResetService` akzeptiert auch andere Schreibweisen und Leerzeichen am Rand. Der Auftrag verlangt "genau". Entscheidung: Die Oberfläche aktiviert die Aktion nur bei exakt `LÖSCHEN` (reine Funktion `ResetPhrase.matches`) und weist bei einer Beinahe-Eingabe darauf hin. Die Toleranz der Engine wird von der Oberfläche nie erreicht; die Engine bleibt unverändert.
- **Was zählt als "Eintrag".** `ImportPreview.entryCount` zählt auch Verlauf (Modulstatus, Zielversionen, Snapshots, Erinnerungsregeln). Entscheidung: Die Kopfzahl zählt nur Einträge, die Nutzer als solche kennen (Gewicht, Schritte, Wasser, Mahlzeiten, Fokus, Workouts, Aufgaben, Gewohnheiten, Checks); die Liste je Bereich zeigt alle Bereiche mit Datensätzen.
- **Berechtigungszustand.** Der Auftrag nennt "dauerhaft abgelehnt"; Android (und damit `NotificationPermission`) unterscheidet nur erteilt, nicht erteilt, nicht verfügbar. Entscheidung: Nicht erteilt gilt nach einer Anfrage als "Im System blockiert", und der Weg zu den Systemeinstellungen wird im Sheet immer angeboten, damit auch die endgültige Ablehnung einen Ausweg hat.
- **Sheet bei erteilter Berechtigung.** Spezifikation 19: einmal kontextbezogen anfragen. Ist nichts zu erfragen, gibt es kein Sheet; der Gerätestatus steht im Block.
- **Bestätigungstext.** Spezifikation: "Vorhandene App-Daten ersetzen"; Figma: "Ersetzen und wiederherstellen". Entscheidung: Das Design bestimmt die Schaltfläche, die Spezifikationsformulierung steht als Warnung direkt darüber.
- **Dateiname.** Die Spezifikation nennt `levelup-life-backup-…`, Auftrag und Engine `self-improvement-backup-YYYY-MM-DD-HHmm.json`. Die Oberfläche zeigt, was die Engine erzeugt.

## 5. Barrierefreiheit

- Tippflächen mindestens 48 x 48 (Schalter, Chips, Schließen, Buttons); geprüft mit `androidTapTargetGuideline` und `labeledTapTargetGuideline` für Screen und alle Sheets.
- Jedes Sheet ist eine benannte Route (Titel als Überschrift), hat eigenes Schließen, schließt mit Android-Zurück und per Tipp neben das Sheet; "Abbrechen" beziehungsweise "Später" haben den Anfangsfokus. Sheets mit laufender Operation lassen sich nicht schließen.
- Zustand nie nur durch Farbe: Haken im ausgewählten Chip, Text "Im System blockiert", Banner mit Titel und Satz, Fehler mit Symbol und Text.
- Fehler und Banner sind Live-Regionen; das Eingabefeld des Reset-Sheets hat Label, Hilfetext und Hinweis zur Beinahe-Eingabe, die Eingabe bleibt bei Fehlern erhalten.
- Schalter melden "ein/aus" samt Statuswort, Chips "ausgewählt", die ausklappbare Liste "eingeklappt/ausgeklappt"; Slot-Chips werden als "10 Uhr" vorgelesen.
- Text bis 200 %: alles scrollt, Label/Wert-Zeilen der Vorschau stapeln ab 130 %, die Aktionen der Sheets bleiben angeheftet, solange der Platz reicht, sonst scrollen sie mit. Bekannte Grenze: Bei 320 px und 200 % bricht das lange Wort "Benachrichtigungen" im Banner mitten im Wort um.
- Keine Gesten als einzige Bedienung, keine Dauer-Animationen.

## 6. Tests

Befehl: `flutter test test/features/settings/data test/features/reminders`. Stand `c0ce096`: 89 Tests unter `test/features/settings/data` und 94 unter `test/features/reminders` (je 2 davon sind Bildtests); der Gesamtstand steht in [test-report.md](../test-report.md). Reale In-Memory-Datenbank, Uhr 2026-10-03 10:00 Europe/Berlin, Fakes der Plattformadapter (`InMemoryBackupFileGateway`, `FakeBackupFilePicker`, `FakeReminderPlatform`), nur synthetische Daten.

| Datei | Inhalt | Abnahme-IDs |
|---|---|---|
| `test/features/settings/data/data_screen_test.dart` | Export (Hinweis, Datei, Teilen, Abbruch, Fehler und Wiederholung, nicht wiederherstellbar, Sperre), Import (Vorschau, Abbrechen, Ersetzen mit Datenbank-Vergleich, Fehlerfall, Doppeltipp, Sheet nicht schließbar während der Ersetzung, Folgeschritte), elf abgelehnte Dateien, Reset (Abbrechen, falsche Wörter, exaktes Wort, Fehler, Doppeltipp), Rundlauf Export, Änderung, Import | AT27, AT30, AT31, AT32, C09, Q01 |
| `test/features/settings/data/data_backup_rules_test.dart` | Wortprüfung, Zählung, lesbare Gründe, Import-Hinweise | AT31, AT32, C09 |
| `test/features/settings/data/data_screen_a11y_test.dart` | 320/360/393/430 px bei 100 % und 200 %, Tastatur, Tippflächen, Labels, Live-Regionen | AT33, AT34 |
| `test/features/reminders/reminders_section_test.dart` | aus als Standard, Einschalten mit und ohne Berechtigung, Sheet-Wege, verweigert, später erteilt, entzogen, Ausschalten, Slots (Speichern, Neustart, schnelle Taps, Modul aus), Fehler mit gleicher Command-ID, Planungsfehler, geplante Liste (Ziele, abgelaufene Einträge, Planungsgrenze), Laden und Fehler | AT28, AT29, C08 |
| `test/features/reminders/reminder_permission_sheet_test.dart`, `reminders_a11y_test.dart`, `reminder_labels_test.dart` | Sheet (Zustände, Ergebnisse, Layout), Layout und Barrierefreiheit des Blocks, Texte | AT28, AT33, AT34 |
| `test/features/reminders/reminder_data_ports_test.dart` | Canceller, Replan-Listener und Composite mit der Backup-Engine: Import storniert alte Alarme und plant neu, der Wunsch aus der Datei ersetzt nicht die Berechtigung, Reset entfernt alles | AT28, C08, C09 |
| `*_visual_test.dart` | schreiben PNGs nach `build/screens/` für den Figma-Vergleich (keine Prüfung) | |

Zwei Mutationsproben bestätigen, dass die Tests greifen (großzügige Wortprüfung und fehlendes Berechtigungs-Sheet lassen je einen Test scheitern).

## 7. Verdrahtung beim App-Start

Die Oberflächen setzen voraus, dass die App beim Start einiges verdrahtet. Stand `c0ce096` ist das erledigt (`lib/app/wiring/app_overrides.dart`, `lib/app/wiring/app_wiring.dart`, `lib/app/app.dart`, `lib/app/router/`):

1. `feedbackServiceProvider` ist mit der Snackbar-Implementierung überschrieben (`SnackBarFeedbackService`); beide Oberflächen lesen sie.
2. `notificationCancellerProvider` ist mit `PlatformNotificationCanceller` überschrieben (storniert alle ausstehenden Systembenachrichtigungen der Plattform nach Import und Reset). Es ist dasselbe Verhalten wie `ReminderNotificationCanceller` aus `reminder_data_ports.dart`; die App nutzt ihre eigene Klasse.
3. `backupListenerProvider` ist mit `AppBackupListener` überschrieben: Daten-Epoche erhöhen, die Kernprovider (Profil, Einstellungen, Modulstatus, Dashboard-Karten, Zielversionen, Tagesstatus, Streak, offene Fokus-Sitzung) neu lesen, "heute" neu lesen und die Erinnerungen über `ReminderService.reconcile()` neu planen. Die Bausteine `CompositeBackupListener` und `reminderReplanListenerProvider` aus `reminder_data_ports.dart` sind getestet (`reminder_data_ports_test.dart`), werden von der App aber nicht verwendet.
4. Die Route `/settings/data` baut `DataScreen`; die Einstellungen betten `const RemindersSection()` zwischen den Darstellungs-Zeilen und "Module" ein, ohne eigene Gruppenüberschrift; der Block zeichnet seine eigene Karte, deren Hauptzeile "Erinnerungen" heißt.
5. Der Router leitet auf `/onboarding` um, solange `profile.onboardingCompleted` falsch ist, und wertet das bei Änderungen des Profils neu aus (Refresh über `profileProvider`). `DataScreen` ruft nach dem Zurücksetzen `context.go('/')`.
6. `backupServiceProvider.cleanUpTemporaryExports()` läuft einmal nach dem Start (`AppWiring.start`).

Reminder-Engine wie im Doc-Kommentar von `ReminderService` beschrieben, hier die Punkte, von denen die Oberfläche abhängt:

7. `reminderPlatformProvider` ist der echte Adapter; die App ruft `initialize()` einmal vor dem ersten Frame auf (`_prepare` in `lib/app/app.dart`). Tests überschreiben ihn mit `FakeReminderPlatform`.
8. `reminderAutoReconcileProvider` und `reminderLifecycleProvider` werden einmal beim Start gelesen (`AppWiring.start`); `waterGoalReachedTodayProvider` ist mit dem echten Tagesstatus überschrieben. Der Block plant beim Zurückkehren in die App zusätzlich selbst neu (`AppLifecycleState.resumed`), die Verdrahtung bleibt für Start, Zeitzone und Datenänderungen nötig.
9. Nicht belegt: `snapshotConsistencyCheckerProvider` aus dem Ziele-Feature. Ohne ihn gleicht der Import die Tages-Snapshots der Datei nicht gegen die Historie ab (siehe [known-limitations.md](../known-limitations.md)).

Keine Änderung an `lib/core/backup` oder `lib/core/notifications` war für die Oberfläche nötig. Neue Dateien liegen unter `lib/features/settings/{application,presentation}` (Präfix `data_`) und `lib/features/reminders/**`.

## 8. Offene Punkte

- "Letzte Sicherung" braucht einen gespeicherten Zeitpunkt (Einstellungsfeld); bis dahin entfällt die Anzeige.
- Auf einem Gerät zu prüfen (hier nicht möglich): echtes Teilen-Menü und Dateiauswahl, der Systemdialog der Benachrichtigungen samt endgültiger Ablehnung ab Android 13, die Zustellung der Erinnerungen, TalkBack, Systemschrift 200 %.
- Plattformkonfiguration für Teilen und Dateiauswahl (Android-Manifest, FileProvider) gehört zur Plattformintegration der Adapter, nicht zu dieser Oberfläche.
- Die Spezifikation nennt noch den alten Dateinamen `levelup-life-backup-…`; die Engine verwendet `self-improvement-backup-…`.
