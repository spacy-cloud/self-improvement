import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_codec.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';

/// In-memory [BackupFileGateway] for tests and previews: files live in a map,
/// sharing is recorded, failures can be injected. Not used in production.
final class InMemoryBackupFileGateway implements BackupFileGateway {
  /// Temporary files by path.
  final Map<String, Uint8List> files = {};

  /// Paths handed to the share sheet, in order.
  final List<String> sharedPaths = [];

  /// What [shareExport] returns.
  BackupShareStatus shareStatus = BackupShareStatus.shared;

  /// If set, the respective operation throws it.
  Object? writeFailure;
  Object? shareFailure;
  Object? deleteFailure;

  /// `includePlatformShareCopies` of every delete call.
  final List<bool> deleteCalls = [];

  /// Files still present when the share sheet was opened (to prove the file
  /// existed while sharing).
  final List<bool> fileExistedWhileSharing = [];

  @override
  Future<String> writeTemporaryExport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (writeFailure != null) {
      throw writeFailure!;
    }
    if (!BackupFileName.isBackupFileName(fileName)) {
      throw ArgumentError('fileName is not a backup file name');
    }
    final path = '/cache/backup_exports/$fileName';
    files[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<BackupShareStatus> shareExport(String path) async {
    if (shareFailure != null) {
      throw shareFailure!;
    }
    fileExistedWhileSharing.add(files.containsKey(path));
    sharedPaths.add(path);
    return shareStatus;
  }

  @override
  Future<void> deleteTemporaryExports({
    bool includePlatformShareCopies = false,
  }) async {
    deleteCalls.add(includePlatformShareCopies);
    if (deleteFailure != null) {
      throw deleteFailure!;
    }
    files.clear();
  }
}

/// [BackupFilePicker] that returns a prepared file (or `null` = cancelled).
final class FakeBackupFilePicker implements BackupFilePicker {
  FakeBackupFilePicker({this.next});

  /// The file the next pick returns; `null` simulates cancelling.
  PickedBackupFile? next;

  /// If set, picking throws it.
  Object? failure;

  /// `maxBytes` of every pick call.
  final List<int> requestedLimits = [];

  @override
  Future<PickedBackupFile?> pickBackupFile({
    int maxBytes = BackupFormat.maxFileBytes,
  }) async {
    requestedLimits.add(maxBytes);
    if (failure != null) {
      throw failure!;
    }
    return next;
  }
}

/// [NotificationCanceller] that counts calls and can fail or observe the
/// moment of the call (to prove it happens after the commit).
final class RecordingNotificationCanceller implements NotificationCanceller {
  RecordingNotificationCanceller({this.onCancel});

  /// Runs inside [cancelAllNotifications] before it completes or fails.
  final Future<void> Function()? onCancel;

  int calls = 0;

  /// If set, cancelling throws it (after [onCancel] ran).
  Object? failure;

  @override
  Future<void> cancelAllNotifications() async {
    calls++;
    await onCancel?.call();
    if (failure != null) {
      throw failure!;
    }
  }
}

/// [BackupListener] that counts calls and can fail or observe the call.
final class RecordingBackupListener implements BackupListener {
  RecordingBackupListener({this.onReplaced});

  final Future<void> Function()? onReplaced;

  int calls = 0;

  /// If set, the callback throws it (after [onReplaced] ran).
  Object? failure;

  @override
  Future<void> onDataReplaced() async {
    calls++;
    await onReplaced?.call();
    if (failure != null) {
      throw failure!;
    }
  }
}
