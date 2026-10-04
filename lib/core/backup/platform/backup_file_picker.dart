import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';

/// A file the user picked for an import.
@immutable
final class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  /// File name for display only (never log it: it may contain a name).
  final String name;

  /// The content. A picker never returns more than `maxBytes + 1` bytes, so
  /// the validator can still tell "too large" without the app loading an
  /// arbitrarily large file.
  final Uint8List bytes;
}

/// Platform adapter for choosing a backup file with the system file picker.
abstract interface class BackupFilePicker {
  /// Lets the user pick a file. Returns `null` when the user cancels.
  Future<PickedBackupFile?> pickBackupFile({
    int maxBytes = BackupFormat.maxFileBytes,
  });
}
