# Bekannte Grenzen

Wird bis zur Abnahme laufend ergänzt. Offene Anforderungen stehen zusätzlich in [requirements-matrix.md](requirements-matrix.md).

## Umgebung und Verifikation

- **Kein lokales Android-SDK** im Entwicklungslauf (Lizenzen nicht akzeptiert). Debug-APK und Emulator-Integrationstests entstehen in der CI (GitHub Actions), nicht lokal. Prüfungen mit realem Gerät (TalkBack, echte Benachrichtigungszustellung, Force-Stop, Systemschrift, Performance) sind **nicht prüfbar** und in der Matrix als solche gekennzeichnet.
- **iOS** ist nur vorbereitet (Projektdateien, plattformunabhängige Domain, Adapter-Schnittstellen). Es gibt keinen iOS-Build und keine iOS-Prüfung; dafür sind macOS, Xcode, Signierung, VoiceOver- und Berechtigungsprüfung nötig.

## Formale offene Punkte (kein Implementierungsblocker)

- **App-Name** ([BS-47](https://spacy-cloud.atlassian.net/browse/BS-47)): sichtbarer Platzhalter „App-Name“ (`AppConfig.appName`).
- **Benannte Figma-Version** ([BS-49](https://spacy-cloud.atlassian.net/browse/BS-49)): „Design-Freigabe V1 – 2026-10-02“ ist laut Jira noch nicht manuell gespeichert; die Designfreigabe V1 vom 2026-10-02 gilt unabhängig davon.
- **Prototyp- und Präsentationsaufgaben** [BS-28](https://spacy-cloud.atlassian.net/browse/BS-28) / [BS-29](https://spacy-cloud.atlassian.net/browse/BS-29) sind separate Unterrichtsaufgaben und nicht Teil der App-Abnahme.

## Fachliche Grenzen von V1

- Keine Cloud, Konten, Telemetrie oder Laufzeit-Netzwerkfunktion; keine automatische Schrittzählung, keine Health-Anbindung (Health Connect / HealthKit / Samsung Health), keine KI-Analyse, keine MCP-Schnittstelle. Diese Punkte sind für später vorgemerkt und nicht als Platzhalter sichtbar.
- SQLite wird nicht zusätzlich verschlüsselt; Schutz durch Gerätesandbox und Gerätesperre.
- Lokale Erinnerungen nutzen ungenaue Android-Alarme ohne Exact-Alarm-Recht und ohne Foreground-Service. Zustellung kann vom Betriebssystem verzögert werden; nach einem Force-Stop kann die Zustellung bis zum nächsten App-Start ausbleiben.
- Die Uhr des Geräts ist ohne Server nicht manipulationssicher; XP und Streak sind ein lokaler Motivationsmechanismus.
