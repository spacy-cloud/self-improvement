# Schriftart Inter

Die App verwendet die Schrift **Inter** (Designsystem, Textstile Display bis Caption). Die Dateien liegen lokal im Repository und werden mit der App ausgeliefert; es gibt keinen Laufzeit-Download.

| Feld | Wert |
|---|---|
| Projekt | Inter, Autor: The Inter Project Authors |
| Quelle | <https://github.com/rsms/inter/releases/tag/v4.1> |
| Release | 4.1 (veröffentlicht 2024-11-16) |
| Archiv | `Inter-4.1.zip`, 33 707 794 Byte, SHA-256 `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e` |
| Herkunft der Dateien | Archivordner `extras/ttf/` (statische TrueType-Schnitte), Lizenz aus `LICENSE.txt` des Archivs |
| Schriftversion (name-Tabelle) | `Version 4.001;git-9221beed3` |
| Lizenz | SIL Open Font License 1.1, Volltext in `OFL.txt` |

## Enthaltene Dateien

| Datei | Gewicht (pubspec) | SHA-256 |
|---|---|---|
| `Inter-Regular.ttf` | 400 | `40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82` |
| `Inter-Medium.ttf` | 500 | `97ad806f526e41546d46365bb3a393145f75b7b1568913db74549ad8b8dba872` |
| `Inter-SemiBold.ttf` | 600 | `78a843fade9d4612a5567302fb595b56976eb5fcebf4fea5a5912d638bafcde3` |
| `Inter-Bold.ttf` | 700 | `288316099b1e0a47a4716d159098005eef7c0066921f34e3200393dbdb01947f` |
| `OFL.txt` | Lizenztext | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |

Die Dateien wurden unverändert aus dem Archiv übernommen (kein Subsetting, keine Umbenennung des Schriftnamens).

## Einbindung

- Familie `Inter` ist im `flutter:`-Abschnitt der `pubspec.yaml` mit den vier Gewichten deklariert.
- `OFL.txt` ist als Asset deklariert und wird von `registerDesignLicenses()` (`lib/core/design/design_licenses.dart`) in die Flutter-`LicenseRegistry` eingetragen. Dadurch erscheint der Lizenztext auf der Lizenzseite der App.
- Prüfung der Integrität: `sha256sum assets/fonts/*` muss die Werte der Tabelle ergeben.
