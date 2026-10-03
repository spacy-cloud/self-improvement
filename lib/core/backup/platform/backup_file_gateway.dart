import 'package:flutter/foundation.dart';

/// How the user left the system share sheet.
enum BackupShareStatus {
  /// The user picked a target.
  shared,

  /// The user closed the sheet without choosing.
  dismissed,

  /// The platform cannot tell (Android reports only that a target was
  /// chosen, and not always).
  unknown,
}

/// Platform adapter for handing a backup to the user.
///
/// Keeps `dart:io`, `path_provider` and `share_plus` out of the domain.
/// Implementations must NOT upload anything by themselves: the file goes to
/// the system share sheet and the user decides where it ends up (no
/// automatic cloud transfer).
abstract interface class BackupFileGateway {
  /// Writes [bytes] to a temporary file named [fileName] in the app's cache
  /// directory and returns its path. [fileName] is a backup file name
  /// (`BackupFileName.isBackupFileName`); anything else is rejected.
  Future<String> writeTemporaryExport({
    required String fileName,
    required Uint8List bytes,
  });

  /// Opens the system share sheet for the file at [path]. Sharing can be
  /// cancelled; that changes no business data.
  Future<BackupShareStatus> shareExport(String path);

  /// Deletes the temporary export files. Idempotent.
  ///
  /// With [includePlatformShareCopies] it also removes copies the platform
  /// made: of earlier exports (Android's share plugin keeps one in its own
  /// cache folder) and of imported files (the file picker's copy in a UUID
  /// folder of the cache, left behind only if the process ended before the
  /// picker adapter removed it). Pass `true` only when no share is in progress
  /// (app start, reset): a receiving app may still be reading such a copy
  /// right after the sheet closed.
  Future<void> deleteTemporaryExports({
    bool includePlatformShareCopies = false,
  });
}
