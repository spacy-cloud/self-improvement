import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';

/// Production [BackupFilePicker]: the system file picker via `file_selector`.
///
/// Thin by design; the picker dialog itself needs a device and is NOT covered
/// by automated tests. The size handling is exercised with a fake `XFile`.
final class FileSelectorBackupFilePicker implements BackupFilePicker {
  FileSelectorBackupFilePicker({
    Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups)? openFile,
  }) : _openFile = openFile ?? _systemOpenFile;

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
    final bytes = await file.length() > maxBytes
        ? await _readAtMost(file, maxBytes + 1)
        : await file.readAsBytes();
    return PickedBackupFile(name: file.name, bytes: bytes);
  }

  static Future<Uint8List> _readAtMost(XFile file, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, limit)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
