# Anforderungsmatrix

Zuordnung **Jira-Key → Anforderungen/Arbeitspaket → Screen/Route → Implementierung → Tests → PR/Commit → Status**. Jira-Priorität und Abhängigkeiten bestimmen die Arbeitsreihenfolge, sind aber keine Scopekürzung. Alle P0- und P1-Anforderungen sind Bestandteil von V1.

**Statuswerte:** `offen` · `in Arbeit` · `umgesetzt` (Code und automatisierte Tests vorhanden und ausgeführt) · `Review` (umgesetzt, PR offen, Team-Abnahme ausstehend) · `nicht prüfbar` (mit Grund, z. B. kein Gerät) · `teilweise` (mit Angabe des offenen Teils).
Ein gestarteter CI-Lauf gilt nicht als bestanden. Prüfungen mit Fakes oder Host-Tests sind von realen Geräteprüfungen getrennt ausgewiesen.

Letzter Stand: 2026-10-03 (Beginn der Umsetzung). Diese Datei wird mit jedem Meilenstein aktualisiert.

## 1. Jira-Umsetzungstickets (Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51))

| Jira | AP | Prio | Arbeitspaket | Anforderungen | Abnahmetests | Screen / Route | Implementierung | Tests | PR / Commit | Jira-Status |
|---|---|---|---|---|---|---|---|---|---|---|
| [BS-52](https://spacy-cloud.atlassian.net/browse/BS-52) | AP00 | P0 | Projektstand, Flutter-Umgebung, Bootstrap und CI | C01, Q01 | – | – | offen | offen | offen | Backlog |
| [BS-56](https://spacy-cloud.atlassian.net/browse/BS-56) | AP01 | P0 | Lokales Drift-Schema, Repositories und Migrationen | C03, C05, Q01 | AT02, AT07, AT27 | – | offen | offen | offen | Backlog |
| [BS-55](https://spacy-cloud.atlassian.net/browse/BS-55) | AP01 | P0 | Zeitmodell, idempotente Commands und Undo | C05, G01, G02 | AT12, AT23, AT25, AT27 | – | offen | offen | offen | Backlog |
| [BS-54](https://spacy-cloud.atlassian.net/browse/BS-54) | AP02 | P0 | Figma-Tokens, Themes und gemeinsame Komponenten | C06, Q02, Q03 | AT33, AT35 | Design System | offen | offen | offen | Backlog |
| [BS-53](https://spacy-cloud.atlassian.net/browse/BS-53) | AP02 | P0 | Vier-Tab-Shell, Routen, Plus-Sheet, Android-Zurück | C02, Q02 | AT01, AT04, AT29, AT33, AT34 | `/`, `/analysis`, `/habits`, `/profile`, Plus-Modal `2037:18` | offen | offen | offen | Backlog |
| [BS-57](https://spacy-cloud.atlassian.net/browse/BS-57) | AP02 | P0 | Fünf Onboarding-Screens und freiwillige Startdaten | C01, C02, C03, C07 | AT01, AT02, AT04 | `/onboarding/*` (`4028:2`, `4028:59`, `4036:278`, `4028:137`, `4028:246`) | offen | offen | offen | Backlog |
| [BS-58](https://spacy-cloud.atlassian.net/browse/BS-58) | AP02/AP09 | P0 | Modulregistry und Dashboard-Kartenkonfiguration | C03, C04 | AT02, AT03, AT04, AT19, AT26 | `/settings/modules` (`4042:141`) | offen | offen | offen | Backlog |
| [BS-61](https://spacy-cloud.atlassian.net/browse/BS-61) | AP03 | P0 | Gewichtsflow: Erfassen, Bearbeiten, Löschen, Undo, Verlauf | W01, W02, C05, A01 | AT05–AT09, AT23, AT27 | `/weight`, `/weight/new`, `/weight/:id` (`4006:2`, `2093:2`, `4053:314`) | offen | offen | offen | Backlog |
| [BS-60](https://spacy-cloud.atlassian.net/browse/BS-60) | AP07 | P1 | Manuelle Schritte als Tagesgesamtwert und Verlauf | W03, C05, A01, G01 | AT15, AT23, AT24, AT26 | `/steps`, `/steps/new` (`4026:2`, `4040:141`) | offen | offen | offen | Backlog |
| [BS-62](https://spacy-cloud.atlassian.net/browse/BS-62) | AP04 | P0 | Wasser-Quick-Add, eigene Menge, Verlauf, Undo | N01, C05, G01 | AT10, AT11, AT12, AT24, AT27 | `/water` (`4021:2`) | offen | offen | offen | Backlog |
| [BS-59](https://spacy-cloud.atlassian.net/browse/BS-59) | AP04 | P1 | Mahlzeiten mit optionalen Kalorien und CRUD | N02, A01, C05 | AT14, AT23, AT27 | `/nutrition`, `/nutrition/new` (`4041:2`, `4041:136`) | offen | offen | offen | Backlog |
| [BS-65](https://spacy-cloud.atlassian.net/browse/BS-65) | AP05 | P0 | Aufgaben-CRUD, Filter und sichere Abschlüsse | T01, T02, C05, G01 | AT12, AT13, AT23, AT27, AT33 | `/habits?tab=tasks`, `/tasks/new` (`4036:2`, `4040:2`) | offen | offen | offen | Backlog |
| [BS-63](https://spacy-cloud.atlassian.net/browse/BS-63) | AP05 | P1 | Tägliche Habits, Symbolwahl, Historie, Archivierung | T02, G02, C08 | AT21, AT23, AT24, AT25 | `/habits`, `/habits/new`, `/habits/:id` (`4023:2`, `4053:2`, `4053:109`) | offen | offen | offen | Backlog |
| [BS-66](https://spacy-cloud.atlassian.net/browse/BS-66) | AP06 | P0 | Persistenter Fokus-Timer und Sitzungsverlauf | F01, F02, G01 | AT12, AT16–AT19, AT25, AT27 | `/focus`, `/focus/session` (`4038:2`, `4039:2`, `4039:106`, `4039:210`) | offen | offen | offen | Backlog |
| [BS-64](https://spacy-cloud.atlassian.net/browse/BS-64) | AP06 | P1 | Manuelle Workouts mit Kategorien, Muskelgruppen, Intensität | F03, A01, G01 | AT20, AT23, AT27 | `/workouts`, `/workouts/new` (`4027:2`, `4022:2`) | offen | offen | offen | Backlog |
| [BS-70](https://spacy-cloud.atlassian.net/browse/BS-70) | AP07 | P1 | Lokales Profil, Zieleeditor und Einstellungen | C06, C07, W02 | AT02, AT09, AT24, AT26, AT28, AT35 | `/profile`, `/profile/edit`, `/goals`, `/settings`, `/settings/licenses` (`4007:2`, `4043:166`, `4043:2`, `4024:2`, `4056:558`) | offen | offen | offen | Backlog |
| [BS-67](https://spacy-cloud.atlassian.net/browse/BS-67) | AP08 | P0 | Versionierte Tagesziele, Snapshots und Tagesring | C07, G02, A01 | AT23, AT24, AT25, AT26 | Dashboard-Ring (`2013:2`) | offen | offen | offen | Backlog |
| [BS-68](https://spacy-cloud.atlassian.net/browse/BS-68) | AP08 | P0 | Deterministische XP, Level und drei Badges | G01, G02 | AT11, AT12, AT13, AT17, AT18, AT23, AT26, AT27 | `/progress` (`4042:2`) | offen | offen | offen | Backlog |
| [BS-69](https://spacy-cloud.atlassian.net/browse/BS-69) | AP08 | P1 | Globale Streak, aktive Tage und Habit-Serien | G02, A01 | AT22–AT25 | `/streak` (`4004:2`) | offen | offen | offen | Backlog |
| [BS-71](https://spacy-cloud.atlassian.net/browse/BS-71) | AP09 | P1 | Analyse, Periodenvergleiche und Datentabelle | A01, Q02, Q03 | AT08, AT14, AT15, AT20, AT23, AT34 | `/analysis` (`4033:2`, Tabelle `4056:421`) | offen | offen | offen | Backlog |
| [BS-74](https://spacy-cloud.atlassian.net/browse/BS-74) | AP09 | P0 | Dashboard und gemeinsame Live-Projektionen | C01, C02, C03, C04, Q03 | AT01–AT04, AT10, AT13, AT20, AT23, AT26, AT27 | `/` (`2013:2`, `4044:188`, `4044:344`, `4045:2`, `4053:663`) | offen | offen | offen | Backlog |
| [BS-72](https://spacy-cloud.atlassian.net/browse/BS-72) | AP10 | P1 | Lokale Erinnerungen, Berechtigungen, Notification-Einstiege | C08 | AT19, AT21, AT25, AT28, AT29 | `/settings` (`4024:2`, `4055:317`, `4055:416`) | offen | offen | offen | Backlog |
| [BS-73](https://spacy-cloud.atlassian.net/browse/BS-73) | AP11 | P1 | Striktes JSON-Backup mit Vorschau und atomarem Import | C09, C05, G01 | AT12, AT23, AT27, AT30, AT31 | `/settings/data` (`4044:2`, `4055:160`, `4055:244`) | offen | offen | offen | Backlog |
| [BS-77](https://spacy-cloud.atlassian.net/browse/BS-77) | AP11 | P1 | Explizites Zurücksetzen und lokales Datenschutzverhalten | C09, Q01 | AT03, AT27, AT31, AT32 | `/settings/data` (`4044:117`) | offen | offen | offen | Backlog |
| [BS-78](https://spacy-cloud.atlassian.net/browse/BS-78) | AP12 | P1 | Responsive Screens, Tastatur, TalkBack und Themes abnehmen | Q02, Q03 | AT33, AT34, AT35 | alle (`4057:*`) | offen | offen | offen | Backlog |
| [BS-76](https://spacy-cloud.atlassian.net/browse/BS-76) | AP12 | P0 | Android-Debug-APK bauen und Kernflows prüfen | C01–Q03 | AT01–AT36 | – | offen | offen | offen | Backlog |
| [BS-75](https://spacy-cloud.atlassian.net/browse/BS-75) | AP12 | P1 | Lasttest mit 10000 Einträgen | Q01, A01 | AT36 | – | offen | offen | offen | Backlog |
| [BS-80](https://spacy-cloud.atlassian.net/browse/BS-80) | AP13 | P1 | Architektur-, Handoff-, Test- und Demo-Dokumentation | Q03 | – | – | offen | offen | offen | Backlog |
| [BS-79](https://spacy-cloud.atlassian.net/browse/BS-79) | AP13 | P0 | Unabhängige Gesamtprüfung und Abschlussübergabe | C01–Q03 | AT01–AT36 | – | offen | offen | offen | Backlog |

Weitere Tickets:

| Jira | Bedeutung | Behandlung |
|---|---|---|
| [BS-3](https://spacy-cloud.atlassian.net/browse/BS-3) | Historischer Einstieg „Entwicklung anfangen“ (mit dem Epic verknüpft) | Nur Fortschrittskommentar; keine eigene Zerlegung. |
| [BS-4](https://spacy-cloud.atlassian.net/browse/BS-4) | Technologie-Stack auswählen (mit BS-52 verknüpft) | Entscheidung in [implementation-decisions.md](implementation-decisions.md) (D-001). |
| BS-9 bis BS-27, BS-30 bis BS-46, BS-48, BS-50 | Erledigte Figma-Design- und Dokumentationsaufgaben | Nur Referenz, nicht wieder geöffnet. |
| [BS-47](https://spacy-cloud.atlassian.net/browse/BS-47) | App-Namen festlegen | Offen; Platzhalter „App-Name“. |
| [BS-49](https://spacy-cloud.atlassian.net/browse/BS-49) | Figma-Freigabeversion speichern | Offen; keine behauptete Speicherung. |
| [BS-28](https://spacy-cloud.atlassian.net/browse/BS-28), [BS-29](https://spacy-cloud.atlassian.net/browse/BS-29) | Prototyp testen, Präsentation vorbereiten | Separate Unterrichtsaufgaben, nicht Teil der App-Abnahme. |
| BS-5 bis BS-8 | Design-Epics | Unverändert. |

## 2. Anforderungen C01–Q03

| ID | Prio | Anforderung | Tickets | Implementierung / Tests | Evidenz | Status |
|---|---|---|---|---|---|---|
| C01 | P0 | App startet offline mit einem lokalen Profil. | BS-52, BS-57, BS-74 | offen | offen | offen |
| C02 | P0 | Onboarding, Hauptnavigation, Plus-Menü und Zurück funktionieren. | BS-53, BS-57, BS-74 | offen | offen | offen |
| C03 | P0 | Fünf Module lassen sich aktivieren, deaktivieren und wiederherstellen. | BS-56, BS-58, BS-57, BS-74 | offen | offen | offen |
| C04 | P0 | Dashboard liest echte Daten, Kacheln sind sortierbar. | BS-58, BS-74 | offen | offen | offen |
| C05 | P0 | Jede Änderung wird lokal gespeichert; Formulare validieren vor dem Commit. | BS-55, BS-56 und alle Feature-Tickets | offen | offen | offen |
| C06 | P1 | Light, Dark, OLED und reduzierte Bewegung. | BS-54, BS-70 | offen | offen | offen |
| C07 | P1 | Profil, Ziele, Modulverwaltung und Einstellungen. | BS-57, BS-67, BS-70 | offen | offen | offen |
| C08 | P1 | Lokale Erinnerungen, Berechtigungsablehnung, Einstieg aus Notification. | BS-63, BS-72 | offen | offen | offen |
| C09 | P1 | JSON-Export, geprüfter Import, Daten zurücksetzen. | BS-73, BS-77 | offen | offen | offen |
| W01 | P0 | Gewicht erfassen, korrigieren, löschen, Verlauf darstellen. | BS-61 | offen | offen | offen |
| W02 | P1 | Optionales Zielgewicht und optionaler BMI als neutrale Zahl. | BS-61, BS-70 | offen | offen | offen |
| W03 | P1 | Schritte manuell pro Tag erfassen. | BS-60 | offen | offen | offen |
| N01 | P0 | Wasser schnell und manuell hinzufügen; Verlauf, Korrektur, Undo. | BS-62 | offen | offen | offen |
| N02 | P1 | Mahlzeiten mit optionalen Kalorien erfassen. | BS-59 | offen | offen | offen |
| F01 | P0 | Countdown starten, pausieren, fortsetzen, beenden, wiederherstellen. | BS-66 | offen | offen | offen |
| F02 | P1 | Fokusverlauf und einfache Kategorien. | BS-66 | offen | offen | offen |
| F03 | P1 | Workouts manuell protokollieren (Kategorie, Dauer, Datum, Wochenziel). | BS-64 | offen | offen | offen |
| T01 | P0 | Aufgaben erstellen, bearbeiten, abschließen, zurücknehmen, löschen. | BS-65 | offen | offen | offen |
| T02 | P1 | Filter, Suche, Priorität und einfache tägliche Gewohnheiten. | BS-63, BS-65 | offen | offen | offen |
| G01 | P0 | Punkte deterministisch, begrenzt und gegen Doppelauslösung geschützt. | BS-55, BS-68 | offen | offen | offen |
| G02 | P1 | Level, drei Badges und Streak-Ansicht. | BS-67, BS-68, BS-69 | offen | offen | offen |
| A01 | P1 | Analyse aggregiert echte Daten über 7/30/90 Tage. | BS-71 | offen | offen | offen |
| Q01 | P0 | Keine abgestürzten oder dauerhaft blockierten Kernabläufe. | BS-52, BS-75, BS-77 | offen | offen | offen |
| Q02 | P1 | Große Schrift, TalkBack, Kontrast, Alternativen zu Gesten. | BS-53, BS-54, BS-78 | offen | offen | offen |
| Q03 | P1 | Freigegebenes Figma wird nachvollziehbar übertragen. | BS-54, BS-74, BS-78, BS-80 | offen | offen | offen |

## 3. Abnahmefälle AT01–AT36

| AT | Ablauf / Erwartung | Anforderungen | Automatisierter Test | Geräteprüfung | Status |
|---|---|---|---|---|---|
| AT01 | Frische Installation im Flugmodus → Onboarding → Home; keine vorgetäuschten Messwerte. | C01, C02 | offen | offen | offen |
| AT02 | Profil/Module ändern → Prozess beenden → Neustart; Zustand bleibt. | C03, C05, C07 | offen | offen | offen |
| AT03 | Körpermodul deaktivieren → Kacheln verschwinden; reaktivieren → Einträge vorhanden. | C03, W01 | offen | offen | offen |
| AT04 | Alle Module aus → verständlicher Leerzustand; Plus zeigt Modulwahl. | C02, C03, C04 | offen | offen | offen |
| AT05 | `71,5` und `71.5` speichern; leer, `71,55`, `NaN`, 19,9 und 350,1 abweisen. | W01, C05 | offen | offen | offen |
| AT06 | Gewicht mit drei Bedingungen speichern, editieren, nach Neustart prüfen. | W01 | offen | offen | offen |
| AT07 | Gleiche Messzeit erneut → keine zweite Anlage; anderer Zeitpunkt am selben Tag erlaubt. | W01, C05 | offen | offen | offen |
| AT08 | 0/1/mehrere Gewichtspunkte → Leerzustand/Marker/Verlauf; Deltas stimmen. | W01, A01 | offen | offen | offen |
| AT09 | Ziel Zu-/Abnahme, Ziel gleich Start, fehlendes Ziel → korrekte Darstellung. | W02 | offen | offen | offen |
| AT10 | Wasser `+250` von Home, höchstens zwei Aktionen; Undo zieht Menge/XP zurück. | N01, G01 | offen | offen | offen |
| AT11 | Fünf Wasserentries ≥100 ml → maximal 20 XP; Nachrücken nach Löschen. | G01 | offen | offen | offen |
| AT12 | Gleiche Command-ID mehrfach → genau ein Datensatz/Award; neue ID ist neue Eingabe. | C05, G01 | offen | offen | offen |
| AT13 | Aufgabe abschließen/zurücknehmen/erneut abschließen → keine XP-Anhäufung. | T01, G01 | offen | offen | offen |
| AT14 | Mahlzeit ohne kcal → „Kalorien unvollständig“, keine erfundene Null. | N02, A01 | offen | offen | offen |
| AT15 | Schritte 7.450, danach 8.000 → Tageswert 8.000, nicht 15.450. | W03 | offen | offen | offen |
| AT16 | Fokus starten/pause/resume → Anzeige und persistierte Zeit korrekt; Neustart holt Restzeit nach. | F01 | offen | offen | offen |
| AT17 | Fokusprozess bis nach Endzeit beenden → Bestätigung ausstehend, noch keine XP; doppeltes Speichern ergibt einen Abschluss. | F01, G01 | offen | offen | offen |
| AT18 | Fokus unter fünf Minuten speichern → Zeit vorhanden, 0 XP; verwerfen → keine Completedzeit. | F01, F02, G01 | offen | offen | offen |
| AT19 | Offene Sitzung bei Moduldeaktivierung → keine stille Datenlöschung, eindeutige Auflösung. | C03, F01 | offen | offen | offen |
| AT20 | Workout protokollieren → Wochenanzahl, Minuten, Dashboard korrekt; keine doppelte Fokuszeit. | F03, A01 | offen | offen | offen |
| AT21 | Habit abhaken/Undo/neuer Tag/Archivierung ab morgen → korrekte Checks und Reminder. | T02, C08 | offen | offen | offen |
| AT22 | Heute Ziel noch nicht erfüllt, gestern aktive Serie → Serie bleibt bis Tagesende. | G02 | offen | offen | offen |
| AT23 | Vergangenheit korrigieren → Tagesring, XP, längste Streak ändern konsistent. | G01, G02, A01 | offen | offen | offen |
| AT24 | Wasserziel heute ändern → alter Tageswert heute, neuer Schwellenwert morgen. | C07, G02 | offen | offen | offen |
| AT25 | Zeitzonen-/Sommerzeitwechsel → keine verschobenen Altdaten, lokale Reminder richtig. | C08, G02 | offen | offen | offen |
| AT26 | Gamification aus, Aktivität erfassen, wieder an → keine Nachvergütung; alte gültige XP bleiben. | C03, G01 | offen | offen | offen |
| AT27 | Datenbankschreibfehler → keine Menge/Completion/XP committed, Eingabe erhalten. | C05, Q01 | offen | offen | offen |
| AT28 | Notificationfreigabe ablehnen → App nutzbar, Status ehrlich; später erlauben → Planung möglich. | C08 | offen | offen | offen |
| AT29 | Reminder öffnen bei kaltem Start, fehlendem Eintrag, deaktiviertem Modul → verständlicher Einstieg. | C08, C02 | offen | offen | offen |
| AT30 | Export → Änderung → Import Vorschau/Ersetzen → Daten und berechnete Werte wiederhergestellt. | C09 | offen | offen | offen |
| AT31 | Falsche Version, doppelte IDs, fehlende FK, >10 MiB, >50.000 Datensätze → Import ohne Änderung abgewiesen. | C09 | offen | offen | offen |
| AT32 | Reset abbrechen → nichts ändern; bestätigen → Daten und Timer weg, Onboarding. | C09 | offen | offen | offen |
| AT33 | Home/Formular/Modal bei 200 % Text und Keyboard; alle Aktionen erreichbar. | Q02 | offen | offen | offen |
| AT34 | TalkBack liest Labels, Status, Fehler, Chart-Alternative, Modal; Sortieren ohne Drag. | Q02 | offen | offen | offen |
| AT35 | Light/Dark/OLED und reduzierte Bewegung gegen finalen Entwurf vergleichen. | C06, Q03 | offen | offen | offen |
| AT36 | 10.000 synthetische Einträge → messbare Start-/Commit-/Scrollwerte, keine UI-Blockade. | Q01, A01 | offen | offen | offen |

## 4. Ergänzungen des Umsetzungsauftrags

| Ergänzung | Inhalt | Ticket | Implementierung / Test | Status |
|---|---|---|---|---|
| Onboarding | Fünf Screens (Willkommen + vier nummerierte Schritte), freiwillige Ziele-Mehrfachauswahl `lose_weight`, `get_fitter`, `move_more`, `live_healthier`, `build_habits` ohne Vorauswahl, `motivation_goals` im Schema und Backup, Untertext „Trinken und Ernährung“, atomares Überspringen. | BS-57 | offen | offen |
| Workout F03 | `training_category` `strength`/`cardio`/`mobility`/`sport`, optionale `muscle_groups` (dedupliziert) und `intensity` `low`/`moderate`/`high`; Mapping alter `type`-Werte dokumentiert; Titel optional ≤ 80. | BS-64 | offen | offen |
| Habit-Symbole | `icon_key` `book`/`moon`/`drop`/`check`/`flame`/`heart` (Default `book`), nur täglich, unbekannte Enums werden abgelehnt. | BS-63 | offen | offen |
| Analyse | 7/30/90 Tage inkl. heute, Vergleich mit gleich langer Vorperiode, Ø pro Tag mit Nenner und Abdeckung x/N, Kompletttage, Tabellenansicht. | BS-71 | offen | offen |

## 5. Zugeordnete Jira-Akzeptanzkriterien mit Nachweisen

Die Akzeptanzkriterien jedes Tickets stehen in der Jira-Beschreibung. Mit Abschluss eines Tickets wird hier je Kriterium der konkrete Nachweis (Testdatei, Testname, CI-Lauf, Gerätenachweis) eingetragen. Noch keine Einträge.
