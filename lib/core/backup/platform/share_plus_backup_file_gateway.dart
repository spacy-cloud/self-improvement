import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:self_improvement/core/backup/backup_codec.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/picked_copy_folder.dart';
import 'package:share_plus/share_plus.dart';

/// Production [BackupFileGateway]: temporary files in the app cache directory
/// and the system share sheet via `share_plus`.
///
/// Thin by design. The file handling is exercised on the host with a
/// temporary directory (see the tests); the real share sheet and the real
/// cache directory need a device and are NOT covered by automated tests.
///
/// Nothing is uploaded here: `share_plus` hands the file to the operating
/// system's share sheet, and the user picks the target.
final class SharePlusBackupFileGateway implements BackupFileGateway {
  SharePlusBackupFileGateway({
    Future<Directory> Function()? cacheDirectory,
    Future<ShareResult> Function(ShareParams params)? share,
    this.shareTitle = 'Sicherung teilen',
  }) : _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share;

  /// Sub folder of the cache directory that only holds export files.
  static const String directoryName = 'backup_exports';

  /// Folder in which Android's `share_plus` keeps the copies it makes of
  /// shared files.
  static const String shareCopiesDirectoryName = 'share_plus';

  final Future<Directory> Function() _cacheDirectory;
  final Future<ShareResult> Function(ShareParams params) _share;

  /// Title of the system share sheet where the platform shows one.
  final String shareTitle;

  Future<Directory> _directory(String name) async {
    final cache = await _cacheDirectory();
    return Directory('${cache.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<String> writeTemporaryExport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!BackupFileName.isBackupFileName(fileName)) {
      throw ArgumentError('fileName is not a backup file name');
    }
    final directory = await _directory(directoryName);
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<BackupShareStatus> shareExport(String path) async {
    final result = await _share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/json')],
        title: shareTitle,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => BackupShareStatus.shared,
      ShareResultStatus.dismissed => BackupShareStatus.dismissed,
      ShareResultStatus.unavailable => BackupShareStatus.unknown,
    };
  }

  @override
  Future<void> deleteTemporaryExports({
    bool includePlatformShareCopies = false,
  }) async {
    for (final name in [
      directoryName,
      if (includePlatformShareCopies) shareCopiesDirectoryName,
    ]) {
      final directory = await _directory(name);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    if (includePlatformShareCopies) {
      await _sweepPickedCopies();
    }
  }

  /// Removes copies the file picker left behind when the process ended before
  /// the picker adapter could delete them: UUID folders directly in the cache
  /// that hold nothing but files a backup copy can be (`.json`, `.txt`, `.bin`,
  /// see [pickedCopyExtensions]). Anything else stays.
  Future<void> _sweepPickedCopies() async {
    final cache = await _cacheDirectory();
    if (!await cache.exists()) {
      return;
    }
    await for (final entity in cache.list(followLinks: false)) {
      if (entity is Directory &&
          isPickedCopyFolderName(p.basename(entity.path)) &&
          await _holdsOnlyBackupFiles(entity)) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<bool> _holdsOnlyBackupFiles(Directory folder) async {
    var any = false;
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !isPickedCopyFileName(p.basename(entity.path))) {
        return false;
      }
      any = true;
    }
    return any;
  }
}
