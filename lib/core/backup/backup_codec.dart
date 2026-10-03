import 'dart:convert';
import 'dart:typed_data';

import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Serializes a [BackupDocument] to the bytes of the file.
abstract final class BackupCodec {
  /// Compact UTF-8 JSON (no indentation; the 10 MiB import limit applies to
  /// the file, so the export does not waste bytes on whitespace). The key
  /// order is fixed, so identical data always yields identical bytes.
  static Uint8List encode(BackupDocument document) =>
      Uint8List.fromList(utf8.encode(jsonEncode(document.toJson())));
}

/// Name of exported backup files.
abstract final class BackupFileName {
  static final RegExp _pattern = RegExp(
    '^${RegExp.escape(AppConfig.backupFileNamePrefix)}'
    r'-\d{4}-\d{2}-\d{2}-\d{4}\.'
    '${BackupFormat.fileExtension}\$',
  );

  /// `self-improvement-backup-YYYY-MM-DD-HHmm.json`, with the local date and
  /// time of [instantUtc] in the zone of [clock] (zero padded).
  static String forInstant(ClockService clock, DateTime instantUtc) {
    final local = clock.toLocal(instantUtc);
    final time = local.time.toIso().replaceAll(':', '');
    return '${AppConfig.backupFileNamePrefix}-${local.date.toIso()}-$time'
        '.${BackupFormat.fileExtension}';
  }

  /// Whether [name] has exactly the shape [forInstant] produces. Used to keep
  /// file adapters from touching or deleting anything else.
  static bool isBackupFileName(String name) => _pattern.hasMatch(name);
}
