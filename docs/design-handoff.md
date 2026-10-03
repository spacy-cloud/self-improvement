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
| IconButton | Plain, Filled (aktive Fläche 48 × 48) | `AppIconButton` (Semantics-Label ist Pflicht) |
| Toggle | On, Off | `AppSwitch` |
| Checkbox | Checked True/False | `RoundCheckbox` |
| Chip | Selected True/False | `AppChoiceChip`, `AppFilterChip` |
| AppCard | – | `AppCard` |
| ListRow | Chevron, Toggle, Value | `EntryListTile` |
| QuantityStepper | – | `QuantityStepper` |
| ProgressBar | Primary, Water, Steps, Focus | `AppProgressBar` (Tagesring: `ProgressRing`) |
| PeriodSelector | – | `PeriodSelector` |
| AppTextField | Default, Focus, Error | `AppTextField` |
| NavigationBar | Active Home/Analyse/Habits/Profil | `AppBottomNavBar` (Plus ist Aktion, kein fünfter Tab) |
| AppHeader | Tab, Subpage | `AppHeader`, eingebettet in `AppScaffold` |
| SnackBar | Undo, Success, Error | `UndoSnackBar` mit `showUndoSnackBar`, `showSuccessSnackBar`, `showErrorSnackBar` |
| EmptyState, ErrorState | – | `EmptyState`, `ErrorState` |
| ConfirmationSheet | – | `ConfirmationSheet`, `showConfirmationSheet` |

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

Die Tabelle nennt die in Figma gelesenen Werte. Im Code weichen `color/primary-button` und `color/toggle-on` in Dark und OLED wegen nachgewiesener Kontrastprobleme ab (Abschnitt 8.4).

Weitere Tokens: Modulfarben (`color/module/*`), Abstände 4/8/12/16/24/32, Radien Chip 18 / Control 14 / Card 16 / Sheet 20, `size/touch-min` 48, `size/button-height` 56. Textstile: Display, Title, Body, Label, Caption (12 Stile, Inter). Die vollständige, aus Figma gelesene Tokenliste steht in Abschnitt 8.2 (Umsetzung von [BS-54](https://spacy-cloud.atlassian.net/browse/BS-54)).

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
| Icons | Eigene SVG-Pfade im Figma | Projekt | Gleichwertige Material Icons (Flutter `Icons`, keine Material Symbols) als Fallback; Zuordnung in Abschnitt 8.3. |
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

Stand der Umsetzung [BS-54](https://spacy-cloud.atlassian.net/browse/BS-54): 2026-10-03. Der Code liegt in `lib/core/design` (Einstieg `design.dart`), die Tests in `test/core/design`. Gelesen wurde über den Figma-MCP (Designkontext, Variablen) und über Lesezugriffe auf Variablensammlung, Textstile und Knoteneigenschaften; es wurde nichts in Figma verändert. [BS-78](https://spacy-cloud.atlassian.net/browse/BS-78) ergänzt diesen Abschnitt um die Abnahmeläufe.

### 8.1 Gelesene Referenzscreens (2026-10-03)

| Gruppe | Knoten |
|---|---|
| Seite `Design System` (alle 18 Komponenten, Designkontext) | PrimaryButton `4050:23`, SecondaryButton `4050:30`, IconButton `4050:39`, Toggle `4050:46`, Checkbox `4050:53`, Chip `4050:60`, AppCard `4051:2`, ListRow `4051:26`, QuantityStepper `4051:27`, ProgressBar `4051:43`, PeriodSelector `4051:44`, AppTextField `4051:70`, NavigationBar `4052:88`, AppHeader `4052:105`, SnackBar `4052:116`, EmptyState `4052:117`, ErrorState `4052:123`, ConfirmationSheet `4052:129` |
| Screens (Designkontext) | Home `2013:2`, Plus-Menü `2037:18`, Gewicht eintragen `2093:2`, Wasser `4021:2`, Habits `4023:2`, Einstellungen `4024:2`, Gewicht bearbeiten `4053:314`, Löschen bestätigen `4053:422`, nach Löschen mit Undo `4053:541`, Validierungsfehler `4045:232`, Speicherfehler `4053:821`, Ladefehler `4045:340`, Home leer `4045:2`, Gewohnheit anlegen `4053:2`, Analyse als Tabelle `4056:421` |
| Lesezugriff auf Variablen und Textstile | Sammlung `App Tokens` (Modi Light, Dark, OLED, 41 Variablen), Sammlung `Collection 1` (`schriftGrau`, `gewichtFarbe`), 12 lokale Textstile; keine Effekt- und keine Farbstile |
| Lesezugriff auf Knoteneigenschaften (Füllungen, Konturen, Effekte, Maße) | Toggle `4050:41`, `4050:44`; Checkbox `4050:48`, `4050:52`; IconButton `4050:36`; AppCard `4051:2`; Stepper `4051:29`; ProgressBar `4051:35`, `4051:36`; Navigation `4052:5`, `4052:13`, `4052:14`; Tagesring `2033:34`, `2033:35`; Wasserring `4021:118`; Home Light `2013:2`, Dark `4044:188`, OLED `4044:344`; Gewicht Dark `4044:500`, OLED `4056:4276`; Wasser Dark `4056:1322`; Habits Dark `4056:1554`; Einstellungen Dark `4056:1894`, OLED `4056:3701`; Workout Dark `4056:1438`, OLED `4056:3245` |
| Bewegungsdaten (`get_motion_context`, rekursiv) | `2013:2`, `2037:18`, `4023:2`, `4045:2` |

Bewegung: Für `2013:2`, `4023:2` und `4045:2` liefert Figma nur am Knoten „Plus-Button“ eine Animation, nämlich einen Radius-Wechsel von 0 auf 0 px in einer unendlichen 2-Sekunden-Schleife (wirkungslos). `2037:18` enthält keine Animationsdaten. Eine Daueranimation wird daraus nicht abgeleitet. Sinnvoll und umgesetzt: kurze Zustandsübergänge von 150 bis 250 ms (Toggle, Checkbox, Chip, Fortschritt, Ring, Aufklappen) und der Wechsel des Plus-Buttons in den Schließen-Zustand (Drehung um 45 Grad, im Frame `2037:18` als roter X gezeichnet). Bei reduzierter Bewegung (Systemeinstellung oder App-Einstellung über `ReducedMotionScope`) ist jeder Wechsel sofort.

### 8.2 Umgesetzte Tokens

#### Farben (Variablensammlung `App Tokens`, 29 Variablen)

Werte in der Form Light / Dark / OLED, wie in Figma gelesen. Abweichungen im Code sind markiert (`*`, siehe 8.4).

| Figma-Variable | Dart-Konstante (`AppColors`) | Light | Dark | OLED |
|---|---|---|---|---|
| `color/background` | `background` | `#F7F8FA` | `#121212` | `#000000` |
| `color/surface` | `surface` | `#FFFFFF` | `#1E1E1E` | `#101010` |
| `color/surface-muted` | `surfaceMuted` | `#F7F8FA` | `#26292E` | `#17191C` |
| `color/text-primary` | `textPrimary` | `#111111` | `#F5F5F5` | `#F5F5F5` |
| `color/text-secondary` | `textSecondary` | `#52555C` | `#B8BDC7` | `#B8BDC7` |
| `color/text-tertiary` | `textTertiary` | `#5F636B` | `#A9AEB7` | `#A9AEB7` |
| `color/border-decorative` | `borderDecorative` | `#ECECEC` | `#2C2F34` | `#24272B` |
| `color/border-input` | `borderInput` | `#8A8F98` | `#6B7079` | `#6B7079` |
| `color/track` | `track` | `#ECEFF3` | `#2C2F34` | `#24272B` |
| `color/primary` (Akzentfläche) | `primary` | `#20B65C` | `#2FCB6E` | `#2FCB6E` |
| `color/primary-button` | `primaryButton` | `#0E8540` | `#1F9D55` → `#1F8655` * | `#1F9D55` → `#1F8655` * |
| `color/on-primary` | `onPrimary` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| `color/primary-text` | `primaryText` | `#087B3E` | `#5FD68F` | `#5FD68F` |
| `color/primary-tint` | `primaryTint` | `#E9F8EF` | `#123222` | `#0C2418` |
| `color/toggle-on` | `toggleOn` | `#13994C` | `#2FCB6E` → `#2FA26E` * | `#2FCB6E` → `#2FA26E` * |
| `color/error` | `error` | `#B42318` | `#FF8A80` | `#FF8A80` |
| `color/error-tint` | `errorTint` | `#FDECEC` | `#3A1414` | `#2A0E0E` |
| `color/warning-text` | `warningText` | `#92400E` | `#F5B75F` | `#F5B75F` |
| `color/warning-tint` | `warningTint` | `#FFF7E6` | `#33260F` | `#241B0A` |
| `color/module/weight` | `moduleWeight` | `#0D7F3F` | `#5FD68F` | `#5FD68F` |
| `color/module/water` | `moduleWater` | `#1474C4` | `#6CB8FF` | `#6CB8FF` |
| `color/module/water-chart` | `moduleWaterChart` | `#2E9FF7` | `#4AAEFF` | `#4AAEFF` |
| `color/module/steps` | `moduleSteps` | `#C21FB7` | `#E36AD9` | `#E36AD9` |
| `color/module/workout` | `moduleWorkout` | `#C2410C` | `#FF9A5C` | `#FF9A5C` |
| `color/module/focus` | `moduleFocus` | `#4F5BD5` | `#8C95FF` | `#8C95FF` |
| `color/module/habits` | `moduleHabits` | `#6A3FD0` | `#B49BFF` | `#B49BFF` |
| `color/module/nutrition` | `moduleNutrition` | `#B45309` | `#F5B75F` | `#F5B75F` |
| `color/module/gamification` | `moduleGamification` | `#D97706` | `#F5B75F` | `#F5B75F` |
| `color/streak` | `streak` | `#FF693F` | `#FF8A66` | `#FF8A66` |

Zugriff in Widgets: `context.tokens.colors.<Rolle>`. Module und Gewohnheiten wählen keine Hex-Werte, sondern eine `AppAccent`-Rolle (`AppColors.accent`, `accentFill`, `accentTint`; Modul-Zuordnung `AppAccent.forModule`).

#### Abstände, Radien und Größen

| Figma-Variable | Dart-Konstante | Wert |
|---|---|---|
| `space/4`, `space/8`, `space/12`, `space/16`, `space/24`, `space/32` | `AppSpacing.s4`, `s8`, `s12`, `s16`, `s24`, `s32` | 4, 8, 12, 16, 24, 32 |
| `radius/chip`, `radius/control`, `radius/card`, `radius/sheet` | `AppRadii.chip`, `control`, `card`, `sheet` | 18, 14, 16, 20 |
| `size/touch-min`, `size/button-height` | `AppSizes.touchMin`, `buttonHeight` | 48, 56 |

Alle Modi enthalten für diese 12 Variablen denselben Wert. Maße der Komponenten (aus den Komponentenknoten gemessen, nicht als Variablen vorhanden) stehen in `AppSizes` und `AppRadii`, zum Beispiel Toggle 44 × 26 mit Knauf 22, Checkbox 28, Fortschrittsbalken 12, Navigations-Pille 64 × 56, Plus-Hof 68 und -Button 56, Sekundärbutton 52, Radius Primärbutton 18 und Sekundärbutton 16.

#### Textstile (12, alle Inter, Zeichenabstand 0)

| Figma-Textstil | Dart (`AppTextStyles`) | Gewicht | Größe | Zeilenhöhe |
|---|---|---|---|---|
| `Display/XL` | `displayXl` | Bold 700 | 48 | 115 % |
| `Display/L` | `displayL` | Bold 700 | 34 | 115 % |
| `Title/Screen` | `titleScreen` | Bold 700 | 24 | 115 % |
| `Title/Section` | `titleSection` | Bold 700 | 17 | 135 % |
| `Title/Card` | `titleCard` | SemiBold 600 | 16 | 135 % |
| `Body/Strong` | `bodyStrong` | SemiBold 600 | 15 | 135 % |
| `Body/Default` | `bodyDefault` | Medium 500 | 15 | 135 % |
| `Body/Regular` | `bodyRegular` | Regular 400 | 14 | 135 % |
| `Label/Button` | `labelButton` | SemiBold 600 | 17 | 135 % |
| `Caption/Default` | `captionDefault` | Regular 400 | 12 | 135 % |
| `Caption/Strong` | `captionStrong` | SemiBold 600 | 12 | 135 % |
| `Caption/Nav` | `captionNav` | Medium 500 | 10 | 135 % |

Die Größen skalieren mit der Systemschrift; die Skalierung wird nirgends global begrenzt. Lokale Grenzen gelten nur für die Navigationslabels (bis 1,3) und die Größe des Tagesrings (bis 1,6); siehe 8.4.

#### Werte, die in Figma nicht an Variablen gebunden sind

| Wert | Dart | Quelle und Behandlung |
|---|---|---|
| Tagesring-Bogen `#E2D11E` (alle Modi) | `AppColors.dayRing` | Fest eingetragener Strich im Home-Frame (Light, Dark, OLED gleich). Die Spur nutzt `track`. |
| SnackBar `#1F2328` / Fehler `#6B140F`, Text `#FFFFFF`, Aktion `#7DE2A8` / `#FFCCC7` | `snackBarSurface`, `snackBarErrorSurface`, `onSnackBar`, `snackBarAction`, `snackBarErrorAction` | Komponente `4052:116`; Figma kennt keine Dark-Variante, in allen Modi gleich. |
| Scrim `#000000` bei 50 % | `scrim` | Hintergrundabdunklung der Frames `2037:18` und `4053:422`. |
| Kartenschatten (0, 4, Unschärfe 12) schwarz 5 % Light, 15 % Dark und OLED | `AppShadows.card`, `shadow` | Komponente `4051:2`; Prozentwerte aus den Dark/OLED-Frames. |
| Modul-Tönungen Light: Wasser `#E8F4FF`, Schritte `#FBEAFA`, Workout `#FFF3E8`, Fokus `#EEF0FD`, Habits `#F3EFFD` | `tintWater`, `tintSteps`, `tintWorkout`, `tintFocus`, `tintHabits` | Aus den Symbolkacheln des Plus-Menüs `2037:18` und des Symbol-Pickers `4053:2`; Gewicht, Aufgabe und Primär nutzen `primary-tint`, Ernährung und Gamification `warning-tint`, die Herz-Rolle `error-tint`. |
| Modul-Tönungen Dark und OLED | dieselben Konstanten | Figma definiert sie nicht. Abgeleitet: 16 % Modulfarbe über `surface`; Modulfarbe auf Tönung mindestens 4,58:1. |
| Text auf Fehlerfläche `onError` (Light `#FFFFFF`, Dark/OLED `#121212`) | `onError` | Nicht in Figma; für den Schließen-Zustand des Plus-Buttons (siehe 8.4). |
| Lesbare Varianten von Gamification und Streak | `moduleGamificationText`, `streakText` | Nicht in Figma; Light nutzt `module/nutrition` und `module/workout`, Dark/OLED die Originalfarben (siehe 8.4). |

### 8.3 Icon-Zuordnung

Die Figma-Icons sind eigene Vektorpfade. Eingesetzt werden gleichwertige Material Icons aus Flutter (`Icons`), gesammelt in `AppIcon` (`AppIcons.of(icon, selected:)`). Die Zuordnung ist nach Aussehen getroffen, nicht pfadgleich.

| Figma-Icon (Knotenname) | Flutter-Icon | `AppIcon`-Schlüssel |
|---|---|---|
| `Home / Icon` | `Icons.home_outlined`, aktiv `Icons.home_rounded` | `home` |
| `Analyse / Icon` (Lupe) | `Icons.search_rounded` | `analysis` |
| `Habits / Icon` (`Checklist`), Aufgabe/Gewohnheit im Plus-Menü | `Icons.checklist_rounded` | `habits`, `habit` |
| `Profil / Icon` | `Icons.person_outline_rounded`, aktiv `Icons.person_rounded` | `profile` |
| Plus im Navigations-Button, Stepper-Plus | `Icons.add_rounded` | `plus` |
| Stepper-Minus (Textzeichen in Figma) | `Icons.remove_rounded` | – (direkt in `QuantityStepper`) |
| Schließen im Plus-Sheet | `Icons.close_rounded` | `close` |
| `Chevron / left` | `Icons.chevron_left_rounded` | `back` |
| `Chevron / right` | `Icons.chevron_right_rounded` | `chevronRight` |
| Aufklappen, Zuklappen (neu für die Tabellenalternative) | `Icons.expand_more_rounded`, `Icons.expand_less_rounded` | `expand`, `collapse` |
| `Weight / scale` | `Icons.monitor_weight_outlined` | `weight` |
| `Steps / sneaker` | `Icons.directions_walk_rounded` | `steps` |
| `Water icon` | `Icons.water_drop_outlined` | `water` |
| Mahlzeit (Gabel und Messer) | `Icons.restaurant_rounded` | `meal` |
| `Workout / dumbbell` | `Icons.fitness_center_rounded` | `workout` |
| Fokus (Uhr) und `Icon / clock` | `Icons.schedule_rounded` | `focus`, `clock` |
| Aufgabe (Kasten mit Haken) | `Icons.check_box_outlined` | `task` |
| `Streak / flame` | `Icons.local_fire_department_rounded` | `streak`, `flame` |
| `Badge / trophy` | `Icons.emoji_events_outlined` | `trophy` |
| Haken in Chip, Checkbox und Listen | `Icons.check_rounded` | `check` |
| Eintrag löschen (Papierkorb) | `Icons.delete_outline_rounded` | `delete` |
| Bearbeiten | `Icons.edit_outlined` | `edit` |
| Einstellungen | `Icons.settings_outlined` | `settings` |
| Fehlerhinweis am Feld | `Icons.error_outline_rounded` | `error` |
| Hinweiskarte (`Hint / bulb`) | `Icons.lightbulb_outline_rounded` | `hint` |
| Ladefehler (Wolke mit Ausrufezeichen) | `Icons.cloud_off_rounded` | `cloudOff` |
| Erneut versuchen (Kreispfeil) | `Icons.refresh_rounded` | `retry` |
| Leerer Zustand (Pflanze, eigene Illustration) | `Icons.eco_outlined` | `sprout` |
| „Nur lokal“ (Schloss) | `Icons.lock_outline_rounded` | `lock` |
| Info (Version) | `Icons.info_outline_rounded` | `info` |
| Einstellungen: Design (Halbkreis), Reduzierte Bewegung, Haptik, Erinnerung | `Icons.contrast_rounded`, `Icons.motion_photos_off_outlined`, `Icons.vibration_rounded`, `Icons.notifications_none_rounded` | `theme`, `reducedMotion`, `haptics`, `reminder` |
| Einstellungen: Module, Export, Import, Zurücksetzen, Lizenzen | `Icons.grid_view_rounded`, `Icons.file_upload_outlined`, `Icons.file_download_outlined`, `Icons.restart_alt_rounded`, `Icons.description_outlined` | `modules`, `export`, `import`, `reset`, `licenses` |

Gewohnheits-Symbole (Symbol-Picker `4053:2`, gespeichert als `icon_key`, Standard `book`; Farbe und Tönung kommen aus der Akzentrolle):

| `icon_key` | Flutter-Icon | Akzentrolle | Figma-Farbe der Option |
|---|---|---|---|
| `book` | `Icons.menu_book_rounded` | `habits` | Violett, Tönung `#F3EFFD`, Auswahlrand `#6A3FD0` |
| `moon` | `Icons.bedtime_rounded` | `focus` | Indigo, Tönung `#EEF0FD` |
| `drop` | `Icons.water_drop_rounded` | `water` | Blau, Tönung `#E8F4FF` |
| `check` | `Icons.check_rounded` | `primary` | Grün, Tönung `#E9F8EF` |
| `flame` | `Icons.local_fire_department_rounded` | `workout` | Orange, Tönung `#FFF3E8` |
| `heart` | `Icons.favorite_rounded` | `error` | Rot, Tönung `#FDECEC` |

### 8.4 Soll-Ist-Abweichungen

#### Kontrastkorrekturen (gemessen nach WCAG 2.2, relative Luminanz)

| Token | Modi | Paar | Soll (Figma) | Ist (Code) | Verhältnis Soll → Ist |
|---|---|---|---|---|---|
| `color/primary-button` | Dark, OLED | Weiß (`on-primary`) auf `primary-button`, normaler Text, Mindestwert 4,5:1 | `#1F9D55` | `#1F8655` (nur Grünkanal geändert) | 3,49:1 → 4,57:1 |
| `color/toggle-on` | Dark, OLED | Weißer Knauf auf Toggle-Spur, Grafik, Mindestwert 3:1 | `#2FCB6E` | `#2FA26E` (nur Grünkanal geändert) | 2,12:1 → 3,22:1 |

Light bleibt unverändert (Weiß auf `primary-button` 4,72:1, Knauf auf Spur 3,69:1). Die freigegebenen Dark/OLED-Frames zeichnen Primärbuttons und Plus-Button mit `#0E8540` (4,72:1) und Toggles mit `#13994C` (3,69:1), also mit den Light-Werten; der Token trägt dort die helleren Werte, die nicht ausreichen. Gewählt wurde die jeweils kleinste Änderung am Token. Die Tabelle steht mit den gemessenen Werten in `test/core/design/contrast_test.dart`.

#### Gemessene Kontraste der Kernpaare (Code-Werte)

| Paar | Light | Dark | OLED | Mindestwert |
|---|---|---|---|---|
| `on-primary` auf `primary-button` | 4,72 | 4,57 | 4,57 | 4,5 |
| `text-primary` auf `background` / `surface` | 17,77 / 18,88 | 17,18 / 15,29 | 19,26 / 17,45 | 4,5 |
| `text-secondary` auf `background` / `surface` | 7,03 / 7,47 | 9,94 / 8,85 | 11,14 / 10,10 | 4,5 |
| `text-secondary` auf `track` (PeriodSelector) | 6,47 | 7,13 | 7,96 | 4,5 |
| `text-tertiary` auf `track` (Disabled-Button) | 5,23 | 6,03 | 6,73 | 4,5 |
| `primary-text` auf `background` / `surface` | 5,05 / 5,37 | 10,26 / 9,13 | 11,50 / 10,42 | 4,5 |
| `primary-text` auf `primary-tint` (Chip, Navigation) | 4,89 | 7,64 | 8,98 | 4,5 |
| `error` auf `background` / `surface` | 6,19 / 6,57 | 8,21 / 7,30 | 9,20 / 8,34 | 4,5 |
| `error` auf `error-tint` | 5,76 | 7,13 | 7,88 | 4,5 |
| `border-input` gegen `surface` | 3,25 | 3,35 | 3,82 | 3 |
| `primary-button` gegen `surface` | 4,72 | 3,65 | 4,17 | 3 |
| `primary-button` gegen `primary-tint` (Chip-Rand) | 4,30 | 3,06 | 3,59 | 3 |
| `toggle-on` gegen `surface` | 3,69 | 5,17 | 5,90 | 3 |

Modulfarben als Text und Icon (`AppColors.accent`) erreichen auf `surface` und `background` mindestens 4,57:1 (Light), 5,82:1 (Dark) und 6,64:1 (OLED), auf ihrer Tönung mindestens 3:1. Alle Paare stehen als Tests in `test/core/design/contrast_test.dart`; zusätzlich prüfen `meetsGuideline` (Tippflächen, Beschriftung, Textkontrast) die Komponentengalerie in allen drei Themes.

#### Bekannte Paare unter dem Richtwert (dekorativ, nie als Text oder allein tragende Information)

| Paar | Verhältnis | Behandlung |
|---|---|---|
| `color/primary` (Akzentfläche) gegen `surface` / `track`, Light | 2,66 / 2,30 | Nur Balken, Ringe und Diagramme, immer mit Textalternative. Weißer Text auf `primary` erreicht 2,66:1 (Light) und 2,12:1 (Dark): Texte stehen auf `primary-button`. |
| `color/module/water-chart` gegen `track`, Light | 2,45 | Balkenfüllung mit Textalternative („60 % erreicht“). |
| `color/streak` gegen `surface`, Light | 2,86 | Flammensymbol neben einem Textwert. Text und Symbol in Listen: `streakText`. |
| `color/module/gamification` gegen `surface`, Light | 3,19 | Füllfarbe; Text und Icon: `moduleGamificationText` (4,5:1 und mehr). |
| Tagesring-Bogen `#E2D11E` gegen `track`, Light | 1,36 | Wie in Figma; der Ring zeigt den Wert immer zusätzlich als Text (`3 von 4`) und trägt eine Textalternative. In Dark und OLED mindestens 3:1. |

#### Weitere Abweichungen und Entscheidungen

| Thema | Figma | Umsetzung |
|---|---|---|
| Undo-Dauer | Komponentenhinweis „Undo 5 s“ | 8 Sekunden (Vorgabe des Auftrags, `AppSnackBarDurations.undo`). Fehlermeldungen mit „Erneut“ bleiben bis zur Aktion oder zum Wegwischen stehen. |
| Dark/OLED-Tokens gegen Frames | OLED-Frames: Rand und Spur `#2C2F34`, Tönung `#123222`; Dark-Toggle aus `#4A4F56`; Checkbox aus `#3A3E44`; Akzent-Checkbox `#20B65C` | Es gelten die Variablen (OLED `#24272B`, `#0C2418`; Toggle aus und Checkbox-Rand `border-input` mit 3,35:1 bzw. 3,82:1 gegen die Fläche; der Frame-Toggle `#4A4F56` erreicht nur 2,02:1). |
| Radien | Token `radius/chip` 18; Chip-Komponente 24, Primärbutton 18, Sekundärbutton 16 | Chip als Pille (`StadiumBorder`), Button-Radien wie gemessen. |
| Kartenschatten | Designkontext meldet Unschärfe 6, Knoteneigenschaft 12 | 12 (Knoteneigenschaft). Home-Karten und Schatten der Screens weichen leicht ab (Radius 17, Versatz 5); es gilt die Komponente. |
| Tippflächen | Chip 46 bis 47 hoch, Segment 44, Aktionspille 32, Löschen-Symbol 28 | Chip und Segment mindestens 48 hoch, Aktionspille 36 mit 48 hoher Tippfläche, Symbol-Buttons 48 × 48. |
| Checkbox | Komponente rund (28); Screens eckig (26, Radius 8) | Rund wie in der Komponente. |
| Header | Komponente 12 + 48 + 12; Screens 40er Kreis mit Abstand 12 | 64 hoch mit 48er Tippfläche. Bei Schriftskala über 1,3 stehen Zurück-Button und Aktionen in einer eigenen Zeile über dem Titel. |
| Navigation | Aktiver Tab mit fetterem Icon | Gefülltes Icon, wo Material eines hat (Home, Profil), sonst fetteres Label (SemiBold). Labels wachsen bis Skala 1,3; die Pillen schrumpfen bei schmalen Breiten bis 48 px. Der Plus-Hof ragt wie im Frame 12 px über die Leiste. |
| Plus geöffnet | Frame `2037:18`: rote Festfarben `#F26F6F` und `#E8B8B8`, weißes Kreuz (2,89:1) | `error` mit `onError` und `error-tint`; Drehung um 45 Grad (150 ms). |
| Deaktivierter Speichern-Button | Frame `4045:232`: `#C4C8CF` mit `#52555C` (4,45:1) | Komponente: `track` mit `text-tertiary` (5,23:1 und mehr). |
| Texte in Figma-Frames | Streak-Text `#FF693F` (2,86:1); „Heute“-Zelle der Wochenleiste: Weiß auf `#20B65C` (2,66:1) | Streak-Text über `streakText`; Hervorhebung des heutigen Tags mit `primary-button` und `on-primary`. |
| Werte-Schriftgrößen der Screens | 20 bis 26 px, 44 und 52 px für Werte | Nur die 12 Textstile; `MetricCard` nutzt `titleScreen` (24), `QuantityStepper` `displayL` (34, per `valueStyle` überschreibbar). |
| Bestätigungs-Sheet | Kein eigener Schließen-Knopf | „Abbrechen“ ist die eigene Schließen-Aktion und startet im Fokus; Barriere-Label „Schließen“, Systemzurück bricht ab. Sheet schwebt mit 16 px Rand. |
| SnackBar-Position | 18 px über dem Primärbutton | `bottomOffset` der Helfer; `AppSizes.pinnedActionArea` (80) für den angehefteten Button von `AppScaffold`. |
| Icons | Eigene SVG-Pfade | Material Icons nach Abschnitt 8.3. Stepper-Zeichen und Haken sind Icons statt Textzeichen. |
| Illustrationen | Eigene SVG-Illustrationen (Pflanze, Wolke) | Symbol in getönter 64er Kreisfläche (`EmptyState`, `ErrorState`). |
| Tagesring-Größe | 118 px, Strich 10 (Home); 110 px mit Strich 11 (Wasser) | Parameter `size` und `strokeWidth`; Standard 118 und 10. Bei großer Schrift wächst der Ring bis zum 1,6-Fachen, der Inhalt skaliert nach unten. |
| Statusleiste und Systemleisten | iPhone-Rahmen | Nur die Statusleiste wird gestaltet (transparent, Symbolhelligkeit je Theme); die Navigationsleiste des Systems bleibt der Shell überlassen. |

Offene formale Punkte bleiben die gespeicherte Figma-Version und der App-Name (Abschnitt 7).
