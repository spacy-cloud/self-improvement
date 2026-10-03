# Bekannte Grenzen

Wird bis zur Abnahme laufend ergänzt. Offene Anforderungen stehen zusätzlich in [requirements-matrix.md](requirements-matrix.md).

## Umgebung und Verifikation

- **Kein lokales Android-SDK** im Entwicklungslauf (Lizenzen nicht akzeptiert). Debug-APK und Emulator-Integrationstests entstehen in der CI (GitHub Actions), nicht lokal. Prüfungen mit realem Gerät (TalkBack, echte Benachrichtigungszustellung, Force-Stop, Systemschrift, Performance) sind **nicht prüfbar** und in der Matrix als solche gekennzeichnet.
- **iOS** ist nur vorbereitet (Projektdateien, plattformunabhängige Domain, Adapter-Schnittstellen). Es gibt keinen iOS-Build und keine iOS-Prüfung; dafür sind macOS, Xcode, Signierung, VoiceOver- und Berechtigungsprüfung nötig.

## Formale offene Punkte (kein Implementierungsblocker)

- **App-Name** ([BS-47](https://spacy-cloud.atlassian.net/browse/BS-47)): sichtbarer Platzhalter „App-Name“ (`AppConfig.appName`).
- **Benannte Figma-Version** ([BS-49](https://spacy-cloud.atlassian.net/browse/BS-49)): „Design-Freigabe V1 – 2026-10-02“ ist laut Jira noch nicht manuell gespeichert; die Designfreigabe V1 vom 2026-10-02 gilt unabhängig davon.
- **Prototyp- und Präsentationsaufgaben** [BS-28](https://spacy-cloud.atlassian.net/browse/BS-28) / [BS-29](https://spacy-cloud.atlassian.net/browse/BS-29) sind separate Unterrichtsaufgaben und nicht Teil der App-Abnahme.

## Oberfläche und Bedienung

- Sehr lange einzelne Wörter in Titeln können bei 320 px Breite und 200 % Schrift mitten im Wort umbrechen.
- Ein erneuter Tipp auf den aktiven Tab scrollt die Seite nicht nach oben.
- Die vorhersagende Zurück-Geste von Android ist nicht aktiviert (ausdrücklicher Opt-out im Manifest, damit Android 16 sie nicht von sich aus einschaltet); Zurück läuft über die eigene Reihenfolge der App (siehe [docs/screens/shell.md](screens/shell.md)). Auf keinem Gerät geprüft.
- Die Rückgängig-Snackbar wird für TalkBack nicht verlängert: Sie bleibt wie vorgegeben 8 Sekunden sichtbar (`persist` ist aus).
- Beim Verschieben einer Dashboard-Karte sagt der Screenreader „verschoben“ auch dann an, wenn ein zweiter Zug ignoriert wurde, weil der erste noch lief.
- Reduzierte Bewegung: Der App-Schalter erreicht die eigenen Animationen, das Plus-Sheet, alle modalen Sheets, die Snackbars und die über `appPageFor` gebauten Seitenwechsel. Er erreicht nicht den Seitenübergang von „Karten anpassen“, „Analyse als Tabelle“ und dem Lizenztext (sie werden mit einer `MaterialPageRoute` geöffnet) und nicht die System-Datums- und Zeitwähler, die nur dem Systemflag folgen.
- Fokus-Timer: Beim Zurückkehren aus dem Hintergrund baut nur der geöffnete Sitzungsbildschirm den Countdown aus den gespeicherten Segmenten neu auf (`FocusRestorer.restore()`); die Verdrahtung der Shell ruft es nur beim Start und bei Reaktivierung des Moduls auf. Auf einem Gerät nicht geprüft.
- Gewicht: Der Anker des Wochenvergleichs ist die letzte Messung am oder vor „heute minus 7 Tage“ und kann deshalb auch länger als eine Woche zurückliegen; die Beschriftung nennt weiter „7 Tage“. Eine Messung wird nie mit sich selbst verglichen (dann steht „Noch kein Wochenvergleich“).
- Schritte: Nach einem abgelehnten Speichern springt der Fokus nicht auf das Eingabefeld (Gewicht, Mahlzeit und Workout tun es); die Meldung steht als Live-Region am Feld.
- Fortschritt: Die Liste „Heute verdient“ des Entwurfs ist nicht umgesetzt.
- Onboarding: Entwürfe überleben das Beenden des Prozesses nicht (gewollt: vor dem Abschluss wird nichts gespeichert).
- Analyse: Der Wochenstreifen gilt nur für 7 Tage, der gewählte Zeitraum wird nach einem Neustart auf 7 Tage zurückgesetzt, und die Tabellenseite hat keine eigene Route (kein Deep Link).
- Daten & Sicherung: „Letzte Sicherung“ wird nicht angezeigt, weil kein Zeitpunkt gespeichert wird.
- Import: Die Tages-Snapshots einer Sicherungsdatei werden nicht gegen die Ziel-, Modul- und Gewohnheitshistorie derselben Datei abgeglichen (der optionale Erweiterungspunkt `SnapshotConsistencyChecker` ist nicht belegt); die XP-Vergaben werden beim Import dagegen vollständig neu berechnet. Eine von Hand veränderte Datei könnte also falsche Tagesringe der Vergangenheit enthalten.
- Import: Android liest die gewählte Datei vollständig in den Speicher und kopiert sie in den Cache, bevor die App sie sieht; die Größenprüfung der App (10 MiB) kann das nicht verhindern. Eine sehr große Datei kann dort zu einem Speicherfehler führen (nicht auf einem Gerät geprüft). Die Kopie wird nach dem Lesen gelöscht.
- Import: Eine fremde Datei ohne Einträge in `dashboard_cards` wird akzeptiert; das Dashboard zeigt dann „Alle Karten sind ausgeblendet“, und „Karten anpassen“ hat nichts zum Einblenden. Die App exportiert immer alle Karten, betroffen sind nur von Hand erzeugte Dateien.
- Zeitzone: Die zuletzt bekannte Zeitzone in den Einstellungen wird nur beim ersten Start gesetzt und nicht nachgeführt; keine Rechnung liest sie (die Planung liest die Gerätezone bei jedem Start und jeder Rückkehr neu), sie steht aber in der Sicherung. Meldet ein Gerät eine Zeitzonenkennung, die die mitgelieferte Zeitzonen-Datenbank nicht kennt, rechnet die App in UTC, und Fachdaten rund um Mitternacht können dann verschoben erscheinen. Für Europe/Berlin ist das nicht zu erwarten; auf Geräten ist es nicht geprüft.

## Fachliche Grenzen von V1

- Keine Cloud, Konten, Telemetrie oder Laufzeit-Netzwerkfunktion; keine automatische Schrittzählung, keine Health-Anbindung (Health Connect / HealthKit / Samsung Health), keine KI-Analyse, keine MCP-Schnittstelle. Diese Punkte sind für später vorgemerkt und nicht als Platzhalter sichtbar.
- SQLite wird nicht zusätzlich verschlüsselt; Schutz durch Gerätesandbox und Gerätesperre.
- Lokale Erinnerungen nutzen ungenaue Android-Alarme ohne Exact-Alarm-Recht und ohne Foreground-Service. Zustellung kann vom Betriebssystem verzögert werden; nach einem Force-Stop kann die Zustellung bis zum nächsten App-Start ausbleiben.
- Die Uhr des Geräts ist ohne Server nicht manipulationssicher; XP und Streak sind ein lokaler Motivationsmechanismus.
