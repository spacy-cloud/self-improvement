import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/picked_copy_folder.dart';

/// Production [BackupFilePicker]: the system file picker via `file_selector`.
///
/// Thin by design; the picker dialog itself needs a device and is NOT covered
/// by automated tests. The size handling and the removal of the picker's copy
/// are exercised with a fake `XFile`.
///
/// On Android the plugin reads the whole document into memory and writes a copy
/// to the cache before it returns; that read happens before this adapter can
/// apply its size limit, so a very large file can exhaust memory there. The
/// copy is removed as soon as its bytes were read.
final class FileSelectorBackupFilePicker implements BackupFilePicker {
  FileSelectorBackupFilePicker({
    Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups)? openFile,
    Future<Directory> Function()? cacheDirectory,
  }) : _openFile = openFile ?? _systemOpenFile,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  /// JSON files. Some providers label `.json` downloads as plain text or as
  /// an unspecified binary type, so those are offered too; the validator is
  /// strict about the content anyway.
  static const XTypeGroup jsonFiles = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    mimeTypes: ['application/json', 'text/plain', 'application/octet-stream'],
    uniformTypeIdentifiers: ['public.json'],
  );

  final Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups) _openFile;
  final Future<Directory> Function() _cacheDirectory;

  static Future<XFile?> _systemOpenFile(List<XTypeGroup> acceptedTypeGroups) =>
      openFile(acceptedTypeGroups: acceptedTypeGroups);

  @override
  Future<PickedBackupFile?> pickBackupFile({
    int maxBytes = BackupFormat.maxFileBytes,
  }) async {
    final file = await _openFile(const [jsonFiles]);
    if (file == null) {
      return null;
    }
    try {
      final bytes = await file.length() > maxBytes
          ? await _readAtMost(file, maxBytes + 1)
          : await file.readAsBytes();
      return PickedBackupFile(name: file.name, bytes: bytes);
    } finally {
      await _discardPickedCopy(file);
    }
  }

  /// Removes the picker's copy of the chosen document (`<cache>/<uuid>/<name>`).
  /// Only a file inside such a folder directly below the cache directory is
  /// touched: on desktop platforms the picker returns the user's own file, and
  /// that must never be deleted. Best effort, never throws.
  Future<void> _discardPickedCopy(XFile file) async {
    try {
      final cache = await _cacheDirectory();
      final folder = p.dirname(file.path);
      if (p.equals(p.dirname(folder), cache.path) &&
          isPickedCopyFolderName(p.basename(folder))) {
        final directory = Directory(folder);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    } on Object catch (error) {
      debugPrint('picked backup copy not removed: ${error.runtimeType}');
    }
  }

  static Future<Uint8List> _readAtMost(XFile file, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, limit)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
