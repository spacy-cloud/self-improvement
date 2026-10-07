# App-Shell, Routen, Plus-Menü und Modulverwaltung

Dieses Dokument beschreibt den tatsächlich umgesetzten Zustand von Start, Router, Tab-Gerüst, Plus-Menü (BS-53) und Modulverwaltung (BS-58) sowie die Verdrahtung der Erinnerungs- und Backup-Engines. Figma-Knoten: Plus-Menü `2037:18` (Dark `4056:662`), Module verwalten `4042:141`, Navigation wie auf Home `2013:2`.

## 1. Bausteine

| Datei | Aufgabe |
|---|---|
| `lib/main.dart` | installiert die zentrale Fehlerbehandlung, schaltet Edge-to-Edge ein, startet `SelfImprovementApp` |
| `lib/app/app.dart` | Start-Gate (Laden, Fehler mit Wiederholen, laufende App), Theme, Reduzierte Bewegung, Sprache |
| `lib/app/bootstrap/` | `AppServices` (Datenbank, Uhr, Zonenquelle), Produktionsstart über `AppRuntime`, neutrale Lade- und Fehlerseite, `error_handling.dart` (zentrale Fehlerbehandlung) |
| `lib/app/router/` | Routen (`app_routes.dart`, `app_router.dart`), Guards (`route_guard.dart`, `guarded_routes.dart`), Zurück-Verhalten (`app_back_dispatcher.dart`), Seitenbau (`app_pages.dart`: Material-Übergang, bei reduzierter Bewegung keiner) |
| `lib/app/shell/` | Tab-Gerüst mit Navigationsleiste (`app_shell.dart`), Plus-Menü (`plus_sheet.dart`, `plus_entries.dart`) |
| `lib/app/screens/` | Seiten "Nicht gefunden" und "Modul ausgeschaltet", dazu der Habits-Tab bei ausgeschaltetem Aufgabenmodul (`module_disabled_tab.dart`) |
| `lib/app/feedback/` | Snackbar-Umsetzung von `FeedbackService` |
| `lib/app/wiring/` | Overrides und Dauerverdrahtung (Erinnerungen, Backup, Uhr, Benachrichtigungs-Einstieg) |
| `lib/features/modules/` | Modulverwaltung (Bildschirm, Controller, Kartenreihenfolge) |

## 2. Start (Bootstrap)

1. `main()` installiert zuerst die zentrale Fehlerbehandlung (Abschnitt 8). `SelfImprovementApp` ruft den Starter auf. Produktion: `AppRuntime.create()` öffnet und migriert die lokale Datenbank, erkennt die Zeitzone und legt die Singleton-Zeilen an. Die Abfolge von `main()` bis zum ersten Frame steht als Sequenz in [architecture.md](../architecture.md) (Abschnitt 11).
2. Währenddessen zeigt die App eine neutrale Seite: leerer Hintergrund, nach 400 ms ein kleiner Fortschrittsanzeiger. Kein Logo, kein Fake-Splash.
3. Scheitert der Start (Datenbank nicht zu öffnen), erscheint "Daten konnten nicht geöffnet werden" mit "Erneut versuchen", dem Hinweis, dass nichts gelöscht wurde, und einem Fehlercode. Die Wiederholung startet den Starter neu. Es gibt keine automatische Zurücksetzung und keine technischen Meldungstexte.
4. Danach erzeugt die App einen eigenen `ProviderContainer` (automatischer Provider-Retry ist aus). Vor dem ersten echten Frame sind erledigt: Erinnerungs-Plattform initialisiert (Fehler dort lassen die App trotzdem starten), Gerätezone gelesen, Onboarding-Status, Modulstatus und Einstellungen gelesen. Dadurch gibt es weder einen Theme- noch einen Screen-Flackern.
5. Die Einstellung "Darstellung" (System, Hell, Dunkel, OLED) wird live angewendet: System folgt der Plattform und wählt nie OLED, OLED nur bei ausdrücklicher Wahl. "Reduzierte Bewegung" speist `ReducedMotionScope`; das Systemflag wirkt unabhängig davon (logisches ODER). Die Reichweite des App-Schalters: die eigenen `AppMotion`-Widgets, das Plus-Sheet, alle modalen Sheets und die Snackbars (über `AppMotion.surfaceStyleOf`, weil das Framework nur das Systemflag kennt) und die Seitenwechsel (`app_pages.dart`). Die System-Datums- und Zeitwähler folgen nur dem Systemflag.

## 3. Routen (final)

### 3.1 Vom Shell registriert

| Pfad | Screen | Art | Hinweise |
|---|---|---|---|
| `/` | `HomeScreen` | Tab 0 | Dashboard |
| `/analysis` | `AnalysisScreen` | Tab 1 | |
| `/habits` | `HabitsTabScreen` | Tab 2 | `?tab=tasks` wählt die Aufgabenliste (`showTasks`); bei ausgeschaltetem Aufgabenmodul ersetzt `ModuleTabGate` den Inhalt (Abschnitt 4) |
| `/profile` | `ProfileScreen` | Tab 3 | |
| `/profile/edit` | `ProfileEditScreen` | Unterseite | |
| `/goals` | `GoalsScreen` | Unterseite | |
| `/settings` | `SettingsScreen` | Unterseite | |
| `/settings/modules` | `ModulesScreen` | Unterseite | Modulverwaltung (Abschnitt 7) |
| `/settings/data` | `DataScreen` | Unterseite | |
| `/settings/licenses` | `LicensesScreen` | Unterseite | |
| `/settings/about` | `AboutScreen` | Unterseite | „Über die App“, öffnet über die Zeile „Version“ der Einstellungen (BS-118, [profile-settings.md](profile-settings.md)) |
| `/onboarding` | `OnboardingScreen` | eigener Fluss | die fünf Schritte laufen innerhalb dieser einen Route |
| `/not-found` | `NotFoundScreen` | Unterseite | Ziel für ungültige Kennungen; unbekannte Pfade zeigen dieselbe Seite |

### 3.2 Über die Modulklassen registriert (durch den Modulstatus geschützt)

Alle fünf mitgelieferten Module registrieren ihre Routen (`bundledModules`, Stand `c0ce096`). Die Reihenfolge ist die des jeweiligen `routes`-Getters.

| Modul | Pfade (Reihenfolge wie registriert) | Schnellaktionen (Plus-Position) und Dashboard-Karten (Rang) |
|---|---|---|
| `body` | `/weight`, `/weight/new`, `/weight/all`, `/weight/:id`, `/steps`, `/steps/new` | `weight` (0), `steps` (3); Karten `steps` (0), `weight` (2) |
| `nutrition` | `/water`, `/water/:id`, `/nutrition`, `/nutrition/new`, `/nutrition/:id` | `water` (2), `meal` (7); Karten `water` (1), `nutrition` (6) |
| `focus` | `/focus`, `/focus/session`, `/focus/history`, `/focus/history/:id`, `/workouts`, `/workouts/new`, `/workouts/all`, `/workouts/:id` | `workout` (1), `focus` (4); Karten `workout` (3), `focus` (4) |
| `tasks` | `/tasks/new`, `/tasks/:id`, `/habits/new`, `/habits/:id` mit dem Unterpfad `edit` (`/habits/:id/edit`) | `task` (5), `habit` (6); Karte `tasks` (5, volle Breite) |
| `gamification` | `/streak`, `/progress` | keine Schnellaktion; Karte `xp` (7, volle Breite); die Screens gehören zum Modul, ausgeschaltet zeigen sie "Modul aktivieren" |

Das Plus-Menü hat damit acht Einträge (Abschnitt 6), das Dashboard acht Karten (Standardreihenfolge Schritte, Wasser, Gewicht, Workout, Fokus, Aufgaben, Ernährung, XP). Die Aufgabenliste ist kein eigener Pfad: sie ist die Ansicht `/habits?tab=tasks` des Tabs.

Regeln: In jedem Modul stehen statische Pfade vor parametrischen (`/weight/new` und `/weight/all` vor `/weight/:id`, `/workouts/new` und `/workouts/all` vor `/workouts/:id`, `/nutrition/new` vor `/nutrition/:id`, `/focus/history` vor `/focus/history/:id`, `/tasks/new` vor `/tasks/:id`, `/habits/new` vor `/habits/:id`), damit ein Schlüsselwort nie als Kennung gelesen wird. Jeder Pfad ist genau einmal registriert; `findDuplicatePaths` prüft das beim Erzeugen des Routers (`assert`) und in Tests (`/streak` und `/progress` stehen nur bei der Gamification, nicht noch einmal in der Shell). Modulrouten müssen `GoRoute` mit `builder` sein; `pageBuilder` oder andere Routentypen scheitern beim Erzeugen des Routers, damit nie eine Route ungeschützt bleibt. Die Seite jeder Kern- und Modulroute entsteht über `appPageFor` und ist immer eine `AppPage` (Material-Übergang, bei reduzierter Bewegung dauert er null; die Route liest den Schalter erst, wenn der Übergang läuft, damit ein Umschalten offene Seiten nicht neu aufbaut). Die Shell mit ihren vier Tabs und die Fehlerseite „Nicht gefunden“ sind keine `AppPage`: go_router liefert dort `NoTransitionPage`, ein Tabwechsel hat nie einen Übergang.

### 3.3 Tab- und Unterseiten-Modell

Die vier Tabs liegen in einer `StatefulShellRoute` (indexierter Stapel): jeder Tab behält Navigation und Scroll-Zustand. Alle anderen Seiten liegen auf der Wurzel-Navigation und werden mit `push` über den aktuellen Tab gelegt (keine Navigationsleiste, wie in den Figma-Frames). Erneutes Tippen auf den gewählten Tab setzt ihn auf seine Wurzel zurück.

## 4. Guards

| Fall | Verhalten |
|---|---|
| Onboarding nicht abgeschlossen | jeder Ort führt zu `/onboarding` (Redirect); nach Abschluss oder Überspringen (Profilwechsel im Stream) führt der Router zu `/` |
| Zurücksetzen aller Daten | Profil ist wieder ohne Onboarding, der Router führt von selbst zu `/onboarding` |
| Modul ausgeschaltet | die Route bleibt erhalten, ihr Inhalt wird durch "Modul ausgeschaltet" ersetzt (Titel, Hinweis "Deine Daten bleiben erhalten", "Modul aktivieren", "Module verwalten"). Nach der Aktivierung wird derselbe Platz mit dem echten Screen gefüllt, ohne Navigation. Dasselbe gilt für eine bereits offene Seite, deren Modul ausgeschaltet wird |
| Habits-Tab bei ausgeschaltetem Aufgabenmodul | Der Tab bleibt ein Kernziel der Navigation, zeigt aber nur "Aufgaben und Gewohnheiten sind ausgeschaltet" ("Deine Einträge bleiben erhalten …") mit "Aufgaben und Gewohnheiten aktivieren" und "Module verwalten": keine Daten, keine Schreibaktion (`ModuleTabGate`, `module_disabled_tab.dart`). Nach der Aktivierung steht derselbe Platz wieder mit dem echten Inhalt |
| Ungültige Kennung | jeder Pfadparameter `id` oder `...Id`, der keine kanonische UUID ist, zeigt "Nicht gefunden", nie den Screen (hat Vorrang vor dem Modulstatus) |
| Gültige, aber unbekannte Kennung | der Screen zeigt seinen eigenen Zustand (z. B. "Eintrag nicht gefunden"), kein Absturz |
| Unbekannte Route | "Diese Seite gibt es nicht" mit Zurück-Pfeil und "Zur Startseite" |

## 5. Zurück-Reihenfolge (Android)

Modal, dann Unterseite, dann Home-Tab, dann das System:

1. Ein offenes Modal (Plus-Menü, Bestätigungs-Sheet, Dialog) schließt zuerst. Ein Formular mit Änderungen fragt vorher "Änderungen verwerfen?" (Weiter bearbeiten / Verwerfen); Zurück im Fragedialog entspricht "Weiter bearbeiten".
2. Dann schließt die oberste Unterseite und gibt den Tab frei, von dem aus sie geöffnet wurde.
3. Auf einem Tab außer Home führt Zurück zum Home-Tab (`PopScope` im Gerüst).
4. Nur auf Home übernimmt das System (App schließt). Während des Onboardings verlässt Zurück die App (der erste Schritt ist der Start).
5. Eine Seite ohne Verlauf darunter (mit `go` statt `push` geöffnet) führt zu Home statt aus der App (`AppBackButtonDispatcher`).

Die Navigations-Einstiege des Shells (Plus-Menü, Benachrichtigungen) öffnen Seiten immer mit `push` über dem aktuellen Stand, damit Zurück funktioniert.

## 6. Plus-Menü (modal, Figma `2037:18`)

- Das mittlere Plus der Navigationsleiste ist eine Aktion und kein fünfter Tab. Es öffnet ein modales Sheet über dem aktuellen Tab; die Leiste zeigt währenddessen den Schließen-Zustand (rotiertes Kreuz).
- Genau acht Einträge in fester Reihenfolge: Gewicht, Workout, Wasser, Schritte, Fokus, Aufgabe, Gewohnheit, Mahlzeit. Jeder Eintrag kommt aus den `quickActions` eines Moduls; Ids außerhalb dieser acht werden ignoriert. Es erscheinen nur Einträge aktiver Module, geordnet nach `plusOrder`.
- Läuft eine Fokus-Sitzung (laufend, pausiert oder unbestätigt), wird "Fokus" zu "Fokus fortsetzen" und führt zu `/focus/session`, statt eine zweite Sitzung zu starten.
- Eigener Schließen-Button im Sheet; außerdem schließen Scrim-Tipp und Android-Zurück. Beim Schließen kehrt der Fokus zum Plus-Button zurück (Flutter stellt den Fokus des öffnenden Elements wieder her; getestet mit Tastaturaktivierung).
- Nach einer Auswahl schließt das Sheet und der Zielscreen wird per `push` über den Tab gelegt. Speichern oder Abbrechen kehrt damit genau zu dem Tab zurück, an dem das Plus gedrückt wurde.
- Alle Module aus: das Sheet zeigt den Erklärtext, die fünf Modulschalter (ein Schalter macht sofort die zugehörigen Einträge sichtbar) und "Module verwalten". Kein Sackgassen-Zustand.
- Layout: zwei Spalten, bei Schriftskala über 1,3 oder schmaler Breite eine Spalte; bei großer Schrift steht der Schließen-Button in einer eigenen Zeile über dem Titel; der Inhalt scrollt.

## 7. Modulverwaltung (`/settings/modules`, Figma `4042:141`)

- Fünf Schalter in einer gruppierten Karte mit den Figma-Texten (zum Beispiel "Gewicht & Körper" mit "Gewicht, Zielgewicht, Schritte"). Die Schalter sind echte Daten: sie laufen über `ModuleManager.setEnabled` (Befehl mit Command-Id, atomar, mit Historie) und überleben den Neustart.
- Ausgeschaltet zeigt die Zeile "Aus. Deine Daten bleiben erhalten." Es wird nichts gelöscht; Reaktivierung stellt Daten und Kartenkonfiguration wieder bereit. Erfolgsmeldungen erscheinen erst nach dem Commit.
- Ein Wechsel sperrt den Schalter dieses Moduls, bis er abgeschlossen ist. Ein Fehler lässt den Schalter unverändert und bietet "Erneut" an (gleiche Command-Id bei unverändertem Inhalt).
- Offene Fokus-Sitzung: Das Ausschalten von Fokus wird nicht ausgeführt. Ein Sheet "Ausschalten nicht möglich" erklärt es und bietet "Zur Sitzung" (öffnet `/focus/session`, dort wird gespeichert oder verworfen) und "Abbrechen". Geprüft wird zuerst `canDeactivate` des Moduls, dann noch einmal atomar im Befehl (`ConflictFailure`), sodass auch eine zwischenzeitlich gestartete Sitzung erkannt wird.
- Alle Module aus: Erklärkarte mit "Alle Module einschalten"; der Abschnitt Dashboard-Karten erklärt, dass es ohne aktive Module keine Karten gibt.
- Abschnitt "Reihenfolge im Dashboard": alle acht Karten mit Position, Nach-oben/Nach-unten-Buttons (Alternative zum Ziehen) und Ausblenden/Einblenden; Reihenfolge und Sichtbarkeit werden gespeichert. Karten ausgeschalteter Module bleiben in der Liste, markiert mit "Modul ausgeschaltet". Sind alle Karten ausgeblendet, erklärt eine Karte das und bietet "Alle Karten einblenden".

## 8. Verdrahtung der Engines

- Modul-Lebenszyklus: `moduleLifecycleProvider` ruft `initialize` für jedes aktive Modul beim Start und bei erneuter Aktivierung und `dispose` beim Ausschalten sowie beim Beenden der App. Die Aufrufe laufen seriell, ein fehlschlagendes Modul wird nur mit dem Fehlertyp protokolliert und stoppt die anderen nicht. Es werden nie Daten angefasst.
- Zone: `RuntimeZoneSource` bindet die Gerätezone der Bootstrap-Uhr an `DeviceZoneTracker`; die Frage nach der Zone aktualisiert zuerst den gemeinsamen Wert, sodass die Uhr die neue Zone schon nutzt, wenn die Erinnerungsplanung neu rechnet. Beim Start liest die App die Zone einmal.
- Erinnerungen: Plattform-`initialize()` vor dem ersten Frame, `reminderAutoReconcileProvider` (ein Lauf beim Start, einer je Datenbankänderung), `reminderLifecycleProvider` (Resume: Zone lesen, dann `reconcile`), `waterGoalReachedTodayProvider` aus dem echten Tagesstatus (Wasserziel erfüllt und anwendbar).
- Benachrichtigungs-Einstieg: Kaltstart-Payload genau einmal und nur nach abgeschlossenem Onboarding, Taps über `tapStream`; jeder Payload geht durch `NotificationEntryResolver`. Unbekannt oder Modul aus: Dashboard; Gewohnheit fehlt oder archiviert: Habit-Liste; sonst die Route. Bildschirmziele werden über den aktuellen Stand gelegt (ein offenes Formular bleibt erhalten); Tab-Ziele wählen den Tab nur, wenn gerade ein Tab oben liegt.
- Backup: `notificationCancellerProvider` (alle ausstehenden Benachrichtigungen der Plattform), `backupListenerProvider` (Daten-Epoche erhöhen, Kernprovider neu lesen, heute neu lesen, Erinnerungen neu planen), `cleanUpTemporaryExports` einmal nach dem Start.
- Uhr: "Heute" wird beim Resume und zum lokalen Mitternacht (Timer, eine Sekunde danach) neu gelesen.
- Fehlerbehandlung: `installErrorHandling` (`lib/app/bootstrap/error_handling.dart`, aufgerufen in `main()`) fängt unbekannte Fehler an einer Stelle und protokolliert nur Fehlertyp und Bibliothek, nie Meldung oder Stacktrace. Im Debug-Modus bleiben die Details des Frameworks; sonst ersetzt der Satz "Dieser Bereich konnte nicht angezeigt werden." ein fehlgeschlagenes Widget.
- Feedback: `SnackBarFeedbackService` (Erfolg 4 s, Rückgängig 8 s mit höchstens einer sichtbaren Aktion, Fehler mit "Erneut" bleibt bis zur Aktion). Die Leiste schwebt auf Tabs über der Navigation und sonst über dem festen Primärbutton (`pinnedActionArea`); die Position wird erst nach dem Aufrufer-Code bestimmt, damit sie zum danach sichtbaren Screen passt.

## 9. Abweichungen von Figma und Gründe

| Figma | Umsetzung | Grund |
|---|---|---|
| Plus-Sheet ohne Scrim über der Leiste | Scrim deckt auch die Leiste ab; Plus bleibt als Kreuz sichtbar | Standard-Modal mit Systemverhalten (Zurück, Fokusfalle); das Sheet schwebt wie im Frame über der Leiste |
| Einträge mit eigenen SVG-Symbolen | Symbole kommen aus den `quickActions` der Module (Material-Symbole der Design-Zuordnung) | Modulvertrag; die Zuordnung steht in `docs/design-handoff.md` |
| Modulverwaltung: nur Nach-oben/Nach-unten | zusätzlich Ausblenden/Einblenden je Karte | BS-58 verlangt einzeln ausblendbare Karten; ohne Frame nach dem Muster der Zeilen |
| Frame zeigt sechs Karten | alle acht Karten der Konfiguration | der Frame ist abgeschnitten |
| Seiten "Nicht gefunden", "Modul ausgeschaltet", Startfehler, Habits-Tab bei ausgeschaltetem Aufgabenmodul | ohne Frame, aus `EmptyState` und `ErrorState` nach dem Fallback-Muster des Handoffs | kein eigener Frame |
| Onboarding `/onboarding/*` | eine Route `/onboarding`, Schritte innerhalb | Vertrag des Onboarding-Screens |
| iPhone-Chrome (Statusleiste, Insel, Home-Indikator) | nicht umgesetzt | nur Figma-Rahmen |

## 10. Konflikte zwischen Vorgaben

- Beschriftung des Fokus-Eintrags bei laufender Sitzung: Der Kommentar am Modulvertrag nennt "Sitzung fortsetzen", die Aufgabenvorgabe "Fokus fortsetzen". Die Aufgabenvorgabe gilt.
- Modulnamen: Die Platzhalter der Modulklassen ("Körper", "Fortschritt") wurden durch die Figma-Texte ersetzt (Figma hat Vorrang vor Platzhaltern).
- `/streak` und `/progress` sind als Modulrouten des Moduls `gamification` registriert (nicht als Kernrouten), damit der Modulstatus sie sperrt; sie sind im Handoff Screens der Gamification-Funktion.

## 11. Barrierefreiheit

- Plus-Menü: Route mit Namen "Was möchtest du eintragen?" (`scopesRoute`, `namesRoute`), Einträge als Schaltflächen mit Beschriftung, eigener Schließen-Button, Barriere-Label "Schließen", Fokusfalle durch die Modul-Route, Zurück schließt.
- Navigation: ausgewählter Tab wird angesagt; Plus heißt "Eintrag hinzufügen" bzw. "Schließen".
- Modulverwaltung: Schalter melden ihren Zustand, jede Zeile nennt Position und Zustand ("Position 1 von 8, Modul ausgeschaltet"), jeder Button hat eine deutsche Beschriftung mit Kartenname, Zustand nie nur über Farbe (Text "Aus", "Ausgeblendet", "Modul ausgeschaltet").
- Tippflächen mindestens 48 x 48; Schrift bis 200 % ohne Abschneiden (Inhalt scrollt, Kopfzeilen stapeln); Tastatur-Inset wird beachtet; keine Aktion nur per Geste.
- Systemleisten: Edge-to-Edge; die Navigationsleiste hält den unteren Systemabstand selbst frei, das Plus-Menü schwebt direkt darüber, die Systemnavigation übernimmt Farbe und Symbolhelligkeit des Themes.
- Snackbar: Live-Region; Fehler bleiben bis zur Aktion, wenn es "Erneut" gibt.
- Bewegung: nur `AppMotion`; mit reduzierter Bewegung (System oder App) sofortiger Wechsel in den eigenen Animationen, im Plus-Sheet, in allen modalen Sheets, in den Snackbars und beim Seitenwechsel. Die System-Datums- und Zeitwähler folgen nur dem Systemflag (Abschnitt 2).

## 12. Tests (Abnahme-Ids in den Testnamen)

| Datei | Inhalt | Ids |
|---|---|---|
| `test/app/bootstrap_smoke_test.dart` | Start, Onboarding-Fluss, neutrale Ladeseite, Startfehler mit Wiederholen, 200 % | AT01, AT33 |
| `test/app/route_guard_test.dart` | Guard-Regeln, ID-Prüfung, Routentabelle ohne Doppelungen | AT01 |
| `test/app/router_guards_test.dart` | unbekannte Routen, ungültige IDs, ausgeschaltete Module, Kernrouten | C02, AT03 |
| `test/app/about_route_test.dart` | Seite „Über die App“ (`/settings/about`) in der laufenden App: Zeile „Version“, Zurück, keine Navigationsleiste, Seitenwechsel mit und ohne reduzierte Bewegung (BS-118) | AT35 |
| `test/app/app_shell_test.dart` | Tabs mit Zustand, Plus-Modal, Filter nach Modulen, Fokus fortsetzen, Rückkehr zum Einstieg, Fokus-Rückgabe | C02, AT04 |
| `test/app/back_order_test.dart` | Zurück-Reihenfolge, Verwerfen-Verhalten | C02 |
| `test/app/app_wiring_test.dart` | Benachrichtigungs-Einstieg, Erinnerungen, Backup, Uhr | AT29, AT32, AT25 |
| `test/app/shell_accessibility_test.dart` | Semantik, Tippflächen, 200 % und Tastatur, PNG-Sichtprüfung | AT33, AT34, Q02 |
| `test/app/app_settings_test.dart` | Theme-Modi, reduzierte Bewegung, Sprache | C06, Q03 |
| `test/app/feedback_service_test.dart` | Snackbar, Rückgängig, Fehler mit Wiederholen | AT10, AT27 |
| `test/app/plus_entries_test.dart` | Auflösung der Plus-Einträge | C02, AT04 |
| `test/features/modules/...` | Schalter, Sperre, Karten, Neustart, Layout, Lebenszyklus | AT02, AT03, AT04, AT19, AT27, AT33, AT34 |
| `test/app/error_handling_test.dart` | zentrale Fehlerbehandlung: nur Typ im Log, neutrales Widget außerhalb des Debug-Modus (BS-85) | - |
| `test/app/module_tab_gate_test.dart` | Habits-Tab bei ausgeschaltetem Aufgabenmodul: Hinweis und Aktivieren, keine Daten, keine Schreibaktion (BS-88) | AT03 |
| `test/app/motion_test.dart` | Seitenwechsel und Plus-Sheet mit und ohne reduzierte Bewegung (App-Schalter und Systemflag), Umschalten bei offenen Seiten und Sheets (BS-87, BS-92) | - |
| `test/app/motion_rules_test.dart` | Quelltext-Regeln: Jedes Sheet, jede Snackbar, jedes Menü und jede gepushte Seite erreicht den Schalter „Reduzierte Bewegung“ (BS-87) | - |
| `test/app/route_sweep_test.dart` | jede Route ohne Kennung bei fünf Größen (bis 320 px mit 200 % Schrift), mit 30 Tagen Daten und in Dark und OLED: kein Überlauf, Tippflächen ab 48 px, Beschriftungen (BS-78) | AT33, AT35 |
| `test/app/confirmation_sheet_scope_test.dart` | Bestätigung von einem Tab aus deckt die ganze Fläche inklusive Navigationsleiste ab (BS-86) | AT34 |
| `test/app/empty_states_scroll_test.dart` | Leer- und Fehlerzustände der Verlaufsseiten scrollen auf kleinen Bildschirmen (BS-86) | AT33 |
| `integration_test/app_smoke_test.dart` | Start auf In-Memory-Datenbank hinter dem Onboarding, Tabwechsel, Plus öffnen und schließen (läuft im Emulator-Job; kein Abnahme-Id im Namen) | - |

## 13. Offene Punkte

- Alle acht Schnellaktionen und alle Modulrouten sind registriert; `findDuplicatePaths` bleibt leer (Test `route_guard_test.dart`: jeder Pfad einmal, mit allen fünf Modulen). Ein neuer Eintrag im Plus-Menü braucht eine neue Id in `plusEntryIds` und eine Schnellaktion in einer Modulklasse.
- Das Speichern oder Verwerfen einer offenen Fokus-Sitzung geschieht auf dem Sitzungs-Screen; die Modulverwaltung führt dorthin. Der Fokus-Eigentümer kann `canDeactivate` für eigene Texte überschreiben.
- Bei `resumed` liest die Verdrahtung Zone und Datum neu und stellt eine offene Fokus-Sitzung wieder her (`FocusRestorer.restore()`, siehe [focus-workouts.md](focus-workouts.md), Abschnitt 3.1).
- `dataEpochProvider` zählt Datenersetzungen (Import, Zurücksetzen) und wird nach jeder Ersetzung erhöht, aber von keinem Provider im Code beobachtet; Provider, die mehr als ihren Datenbank-Stream zwischenspeichern, sollten ihn beobachten.
- `snapshotConsistencyCheckerProvider` hat keine Umsetzung (Zielfunktion); der Standard übernimmt Snapshots unverändert.
- Scroll nach oben beim erneuten Tippen auf den Tab ist Sache der Tab-Screens (der Shell setzt den Tab nur auf seine Wurzel zurück).
- Das System-Zurück läuft über den klassischen Pfad: Das Android-Manifest schaltet das vorhersagende Zurück ausdrücklich ab (`android:enableOnBackInvokedCallback="false"`), weil Android 16 es mit targetSdk 36 sonst standardmäßig aktivierte und die App vor ihrer eigenen Zurück-Reihenfolge (eine Seite ohne Verlauf führt zu Home) schlösse. Das `PopScope` im Gerüst funktioniert in beiden Modi, der Zurück-Fallback für Seiten ohne Verlauf nur im klassischen. Auf keinem Gerät geprüft.
- Die Rückgängig-Snackbar wird für TalkBack nicht verlängert (`persist` ist aus, 8 Sekunden wie vorgegeben). Das ist eine bekannte, nicht behobene Grenze (siehe [known-limitations.md](../known-limitations.md)).
- Nicht auf dem Host prüfbar: echte Datenbankdatei, echtes Benachrichtigungs-Plugin, Emulator (der Integrationstest läuft in der CI).
