# Architektur

Dieses Dokument beschreibt die tatsächlich umgesetzte Architektur. Es wächst mit den Arbeitspaketen AP01 bis AP11 (Jira [BS-56](https://spacy-cloud.atlassian.net/browse/BS-56), [BS-55](https://spacy-cloud.atlassian.net/browse/BS-55) und folgende). Stand: Bootstrap (AP00).

## Schichten (Ziel)

```text
UI (Widgets) → Controller (Riverpod) → Use Case / Command → Repository → Drift (SQLite)
```

- Widgets enthalten weder SQL noch Punkteberechnung.
- Gemeinsame fachliche Regeln (Ziele, XP, Streak, Analyse, Validierung) sind reine Dart-Funktionen ohne Plattformabhängigkeit.
- Datenänderung und Projektion (Tagesziel-Snapshots, XP) laufen in einer Datenbanktransaktion; UI-Ereignisse entstehen erst nach dem Commit.
- Plattformfunktionen (Benachrichtigungen, Dateien) liegen hinter Schnittstellen, damit iOS später ohne Änderung der Domain folgen kann.

## Verzeichnisse

```text
lib/
  main.dart, app/            # Start, Router, Shell
  core/                      # config, database, design, modules, time, goals, commands, notifications, backup, errors
  features/                  # body, nutrition, focus, tasks, gamification (je domain/data/application/presentation nach Bedarf)
  shared/                    # kleine Domain-Primitive
test/, integration_test/, tool/, assets/, docs/
```

Details zu Datenmodell, Commands, Zeitmodell, Routen und Modulvertrag werden hier mit der Umsetzung ergänzt.
