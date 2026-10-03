# Testbericht

Dokumentiert tatsächlich ausgeführte Prüfungen mit Umgebung und Ergebnis. Nicht ausgeführte oder nicht prüfbare Punkte sind als solche gekennzeichnet; ein gestarteter CI-Lauf gilt nicht als bestanden.

## Umgebung

| Aspekt | Wert |
|---|---|
| Toolchain | Flutter 3.47.6 stable, Dart 3.13.5 (siehe [implementation-decisions.md](implementation-decisions.md)) |
| Host-Tests | Linux x86_64, `flutter test` mit SQLite im Prozess |
| Lokales Android-Ziel | Keines (kein Android-SDK, kein Gerät, kein Emulator) |
| CI | GitHub Actions, siehe `.github/workflows/ci.yml` |

## Ergebnisse

### AP00 – Bootstrap (BS-52)

| Prüfung | Befehl | Ergebnis | Datum |
|---|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test tool` | bestanden (lokal) | 2026-10-03 |
| Statische Analyse | `flutter analyze` | bestanden, keine Befunde (lokal) | 2026-10-03 |
| Tests | `flutter test` | 5 Tests bestanden (lokal, Host) | 2026-10-03 |
| CI-Lauf | GitHub Actions | siehe PR | – |
