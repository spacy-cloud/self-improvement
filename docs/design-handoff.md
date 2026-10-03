# Design-Handoff

Übergabe des freigegebenen Designs (V1, 2026-10-02) an die Flutter-Umsetzung. Quelle sind das Confluence-Handoff „LF10a Design-Handoff“ (Version 1) und das lokale Übergabemanifest; die Figma-Datei wurde im Umsetzungslauf zusätzlich über Lesezugriff geprüft. Dieses Dokument ändert keine Fachregel. Die Confluence-Seite wird im Umsetzungslauf nicht verändert; bei Designänderungen sind beide zu aktualisieren.

## 1. Quelle, Freigabestand und verwendeter Stand

| Feld | Wert |
|---|---|
| Figma-Datei | [LF10-Desing-App](https://www.figma.com/design/K4IWQEjnzuNkRUzkq8JaKz/LF10-Desing-App), File-Key `K4IWQEjnzuNkRUzkq8JaKz` |
| Team / Plan | IA24, Figma Education |
| Seiten | `Screens` (86 Frames), `Design System` (18 Komponenten) |
| Freigabe | Design-Freigabe V1 vom 2026-10-02 (gilt) |
| Benannte Figma-Version „Design-Freigabe V1 – 2026-10-02“ | Laut Jira [BS-49](https://spacy-cloud.atlassian.net/browse/BS-49) noch **nicht gespeichert** (formaler Restpunkt, keine Implementierungssperre). Der Figma-MCP bietet keinen Zugriff auf die Versionshistorie; der Stand ist daher nicht unabhängig bestätigt. |
| Im Lauf gelesener Stand | 2026-10-03, Figma-MCP-Lesezugriff auf Designsystem-Variablen und die unten genannten Referenzscreens (Abschnitt 8) |
| Analyse-Screen | `4033:2` (aktuell; ersetzt die alte Analyse `2110:153`) |
| Prototyp-Startpunkte | „Onboarding“ (`4028:2`) und „App (Dashboard)“ (`2013:2`) |
| Entwurfsgröße | 393 × 852 (nur Referenz, keine feste Android-Größe) |
| Jira | [BS-Board](https://spacy-cloud.atlassian.net/jira/software/projects/BS/boards/34), Umsetzung im Epic [BS-51](https://spacy-cloud.atlassian.net/browse/BS-51) |

## 2. Screens, Routen und Varianten

Frames mit größerer Höhe sind Scroll-Screens. Die Routen sind die im `go_router` umgesetzten (Ergänzungen siehe [architecture.md](architecture.md)).

### 2.1 Shell und Tabs

| Screen | Node-ID | Route | Varianten |
|---|---|---|---|
| Dashboard / Home | `2013:2` | `/` | Dark `4044:188`, OLED `4044:344`, leer `4045:2`, nach Speichern `4053:663` |
| Plus-Menü (Modal) | `2037:18` | Modal über aktuellem Tab | Dark `4056:662`, OLED `4056:2469` |
| Analyse | `4033:2` | `/analysis` | Tabelle `4056:421`, Dark `4056:2285`, OLED `4056:4092` |
| Habits – Gewohnheiten | `4023:2` | `/habits` | Dark `4056:1554`, OLED `4056:3361` |
| Habits – Aufgaben | `4036:2` | `/habits?tab=tasks` | Dark `4056:1738`, OLED `4056:3545` |
| Profil | `4007:2` | `/profile` | Dark `4056:1186`, OLED `4056:2993` |

### 2.2 Erfassung und Module

| Screen | Node-ID | Route | Varianten / Zustände |
|---|---|---|---|
| Gewicht eintragen | `2093:2` | `/weight/new` | Dark `4044:500`, OLED `4056:4276`, Validierungsfehler `4045:232`, Speicherfehler `4053:821` |
| Gewicht bearbeiten | `4053:314` | `/weight/:id` | Löschen bestätigen `4053:422`, nach Löschen mit Undo `4053:541` |
| Gewicht – Übersicht | `4006:2` | `/weight` | Alle Messungen `4056:39`, Ladefehler `4045:340`, Dark `4056:928`, OLED `4056:2735` |
| Schritte – Übersicht | `4026:2` | `/steps` | Dark `4056:2056`, OLED `4056:3863` |
| Schritte eintragen | `4040:141` | `/steps/new` | 200 % Schrift `4057:39` |
| Wasser eintragen | `4021:2` | `/water` | Eigene Menge `4055:25`, 360 px `4057:92`, 320 px `4057:208`, Dark `4056:1322`, OLED `4056:3129` |
| Mahlzeiten – Übersicht | `4041:2` | `/nutrition` | – |
| Mahlzeit eintragen | `4041:136` | `/nutrition/new` | – |
| Workout eintragen | `4022:2` | `/workouts/new` | Dark `4056:1438`, OLED `4056:3245` |
| Workout – Übersicht | `4027:2` | `/workouts` | Alle Trainings `4056:183`, Dark `4056:2155`, OLED `4056:3962` |
| Fokus – Start | `4038:2` | `/focus` | Verlauf `4056:298` |
| Fokus – läuft / pausiert / abgeschlossen | `4039:2`, `4039:106`, `4039:210` | `/focus/session` | Zustände `running`, `paused`, `awaiting_confirmation` |
| Aufgabe anlegen | `4040:2` | `/tasks/new` | Tastatur offen `4057:324`, Verwerfen-Dialog `4053:929` |
| Gewohnheit anlegen | `4053:2` | `/habits/new` | – |
| Gewohnheit – Detail | `4053:109` | `/habits/:id` | 30-Tage-Verlauf, Bearbeiten, Archivieren, Löschen |
| Streak | `4004:2` | `/streak` | Dark `4056:1046`, OLED `4056:2853` |
| Fortschritt (Gamification) | `4042:2` | `/progress` | – |

### 2.3 Profil, Einstellungen, Daten, Onboarding

| Screen | Node-ID | Route | Varianten |
|---|---|---|---|
| Profil bearbeiten | `4043:166` | `/profile/edit` | – |
| Ziele bearbeiten | `4043:2` | `/goals` | – |
| Einstellungen | `4024:2` | `/settings` | Erinnerungen abgelehnt `4055:416`, Dark `4056:1894`, OLED `4056:3701` |
| Erinnerungen erlauben (Erklärung vor Systemdialog) | `4055:317` | Sheet | – |
| Module verwalten | `4042:141` | `/settings/modules` | – |
| Daten & Sicherung | `4044:2` | `/settings/data` | Import-Vorschau `4055:160`, Import ungültig `4055:244`, Zurücksetzen bestätigen `4044:117` |
| Lizenzen | `4056:558` | `/settings/licenses` | – |
| Onboarding 1–5 (Willkommen, Ziele, Module, Körperdaten, Tagesziele) | `4028:2`, `4028:59`, `4036:278`, `4028:137`, `4028:246` | `/onboarding/*` | Überspringen führt zum Dashboard |

## 3. Komponenten und Tokens

Seite `Design System`. Alle Farben sind an die Variablensammlung **App Tokens** (Modi Light, Dark, OLED) gebunden. Die Flutter-Entsprechungen liegen in `lib/core/design`.

| Komponente | Varianten | Flutter-Entsprechung |
|---|---|---|
| PrimaryButton | Default, Pressed, Disabled, Loading | `PrimaryButton` |
| SecondaryButton | Default, Disabled, Danger | `SecondaryButton` |
| IconButton | Plain, Filled (aktive Fläche 48 × 48) | `IconButton` mit Semantics-Label |
| Toggle | On, Off | `Switch` |
| Checkbox | Checked True/False | `Checkbox` (rund) |
| Chip | Selected True/False | `FilterChip` |
| AppCard | – | `AppCard` |
| ListRow | Chevron, Toggle, Value | `EntryListTile` |
| QuantityStepper | – | `QuantityStepper` |
| ProgressBar | Primary, Water, Steps, Focus | `ProgressBar` |
| PeriodSelector | – | `PeriodSelector` |
| AppTextField | Default, Focus, Error | `AppTextField` |
| NavigationBar | Active Home/Analyse/Habits/Profil | `AppScaffold` Bottom-Nav |
| AppHeader | Tab, Subpage | `AppScaffold` AppBar |
| SnackBar | Undo, Success, Error | `UndoSnackBar` |
| EmptyState, ErrorState | – | `EmptyState`, `ErrorState` |
| ConfirmationSheet | – | `ConfirmationSheet` |

Wichtigste Farbtokens (Light / Dark / OLED):

| Token | Light | Dark | OLED |
|---|---|---|---|
| color/background | `#F7F8FA` | `#121212` | `#000000` |
| color/surface | `#FFFFFF` | `#1E1E1E` | `#101010` |
| color/text-primary | `#111111` | `#F5F5F5` | `#F5F5F5` |
| color/text-secondary | `#52555C` | `#B8BDC7` | `#B8BDC7` |
| color/primary (Akzentfläche) | `#20B65C` | `#2FCB6E` | `#2FCB6E` |
| color/primary-button | `#0E8540` | `#1F9D55` | `#1F9D55` |
| color/primary-text | `#087B3E` | `#5FD68F` | `#5FD68F` |
| color/error | `#B42318` | `#FF8A80` | `#FF8A80` |

Weitere Tokens: Modulfarben (`color/module/*`), Abstände 4/8/12/16/24/32, Radien Chip 18 / Control 14 / Card 16 / Sheet 20, `size/touch-min` 48, `size/button-height` 56. Textstile: Display, Title, Body, Label, Caption (12 Stile, Inter). Die vollständige, aus Figma gelesene Tokenliste steht im Abschnitt „Umgesetzte Tokens“ (wird mit der Umsetzung von [BS-54](https://spacy-cloud.atlassian.net/browse/BS-54) ergänzt).

## 4. Responsive Regeln, Barrierefreiheit, Bewegung

- Layout aus Auto-Layout-Spalten mit 16 px Rand; keine absolute 393 × 852-Zeichnung übernehmen.
- Kleine Breiten (`4057:92`, `4057:208`): Karten füllen die Breite, Raster bleibt zweispaltig, Texte umbrechen. **Ergänzung des Auftrags:** bei großer Schrift oder Platzmangel darf auf eine Spalte gestapelt werden; Lesbarkeit und erreichbare Aktionen haben Vorrang.
- 200 % Schrift (`4057:39`): Labels stapeln, Karten wachsen, Inhalt scrollt, Speichern bleibt erreichbar.
- Tastatur (`4057:324`): Inhalt scrollt, Primäraktion bleibt über der Tastatur.
- Tippflächen mindestens 48 × 48 (IconButton, Stepper, Toggle, Checkbox, Chip-Höhe inkl. Abstand).
- Semantische Labels: Plus = „Eintrag hinzufügen“, Schließen, Zurück, Stepper „erhöhen/verringern“, Status „ausgewählt“, „erledigt“, „pausiert“.
- Diagramme haben Textalternativen (Werte in Karten, Tabelle `4056:421`, Habit-Raster mit Text pro Tag).
- Modale: Fokus in den Dialog, Hintergrund inaktiv, Systemzurück schließt.
- Animationen 150–250 ms, keine Endlosschleifen; bei reduzierter Bewegung sofortiger Zustandswechsel. Der Motion-Kontext des Analyse-Plus enthält nur eine wirkungslose Radius-Endlosschleife; daraus wird keine dekorative Daueranimation abgeleitet.

## 5. Assets und Lizenzen

| Asset | Quelle | Lizenz | Hinweis |
|---|---|---|---|
| Inter | Google Fonts / rsms | SIL Open Font License 1.1 | Lokal eingebunden (`assets/fonts`), kein Laufzeit-Download; Lizenztext liegt bei den Fontdateien. |
| Icons | Eigene SVG-Pfade im Figma | Projekt | Gleichwertige Material Symbols als Fallback; Zuordnung im Abschnitt „Icon-Zuordnung“ (wird mit BS-54 ergänzt). |
| Illustrationen (Empty State, Fehler) | Eigene SVG | Projekt | – |
| Diagramme, Ringe, Fortschritt | Datengetrieben | – | Im Code gerendert, keine Bilder. Keine temporären Figma-URLs zur Laufzeit. |

## 6. Freigegebene Abweichungen gegenüber älteren Frames

- iPhone-Statusleiste, Dynamic Island und Home-Indikator sind nur Figma-Rahmen; Android nutzt echte Systemleisten.
- Schlafwerte entfallen; keine erfundenen Werte (km, kcal, Aktivminuten ohne Datenquelle).
- Einstellungen ohne Konto/Cloud/Health; lokales Profil, „Alle Daten zurücksetzen“ statt „Konto löschen“.
- Plus-Menü mit 8 Einträgen und Schließen im Sheet; die rote X-Taste in der Navigation ist zusätzlich erlaubt.
- Detailseite Wasser entfällt; „Wasser eintragen“ deckt Tagesstand und Verlauf ab.
- Workout-Erfassung enthält zusätzlich Muskelgruppen und Intensität (optional, über F03 hinaus); die Trainingskategorie folgt Kraft/Cardio/Mobility/Sport.
- Beispielzahlen sind Platzhalter (Gewicht 71,5 kg, Ziel 68,0 kg, Start 74,0 kg, Streak 11 Tage); der Code berechnet alle Werte aus der Datenbank.
- Onboarding-Ziele-Auswahl: Untertext „Trinken, Schlaf und Ernährung“ lautet in der Umsetzung „Trinken und Ernährung“ (Schlaf entfällt in V1).
- Habit-Anlage: Die Häufigkeitsoptionen „Bestimmte Tage“ und „Morgens“ werden in V1 nicht angeboten (nur täglich).
- Analyse-Karten „Ø pro Tag“ zeigen zusätzlich Nenner und Erfassungsabdeckung (x/N).

## 7. Fallbacks für Details ohne eigenen Frame

- Bearbeiten/Löschen für Wasser, Workout, Mahlzeit und Aufgabe folgt exakt dem Muster Gewicht (`4053:314` → `4053:422` → `4053:541`).
- Speicherfehler, Erfolg und Undo für alle Formulare folgen `4053:821`, `4053:663` und `4053:541`.
- Leere Listen nutzen `EmptyState`, Ladefehler `ErrorState` (`4045:340`).
- Dark/OLED für nicht variierte Unterseiten ergeben sich aus den Variablen-Modi.
- App-Name: Platzhalter „App-Name“ als eine Konstante (`AppConfig.appName`), Ersetzen vor Release.

**Festlegung:** Keine weiteren fachlichen Designlücken für V1. Offene Punkte sind formal (App-Name, gespeicherte Figma-Version).

## 8. Verwendete Referenzscreens, umgesetzte Tokens und Soll-Ist-Vergleich

Die folgenden Abschnitte werden während der Umsetzung ergänzt ([BS-54](https://spacy-cloud.atlassian.net/browse/BS-54), [BS-78](https://spacy-cloud.atlassian.net/browse/BS-78)):

- Umgesetzte Tokens (Figma-Variable → Flutter-Konstante, je Modus)
- Icon-Zuordnung (Figma-Icon → Material Symbol)
- Gelesene Referenzscreens mit Datum
- Soll-Ist-Abweichungen und nachgewiesene Kontrastkorrekturen
