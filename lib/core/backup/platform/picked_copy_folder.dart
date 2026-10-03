/// Android's file picker (`file_selector`) copies the document the user chose
/// to `<cache>/<uuid>/<name>` and only schedules the deletion for the end of
/// the process. The copy holds the complete, unencrypted backup, so the app
/// removes it itself: right after reading ([FileSelectorBackupFilePicker]) and
/// as a sweep at start and reset ([SharePlusBackupFileGateway]).
///
/// Only folders that look exactly like such a copy folder are ever touched.
library;

import 'package:path/path.dart' as p;

final RegExp _uuidFolder = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

/// Whether [name] (a folder name directly below the cache directory) has the
/// shape of the picker's copy folders: a UUID.
bool isPickedCopyFolderName(String name) => _uuidFolder.hasMatch(name);

/// The extensions a picker copy can have. The plugin renames the copy to the
/// extension of the MIME type the document provider reports
/// (`file_selector_android`, `FileUtils`), and the picker offers JSON, plain
/// text and unspecified binary files (some providers label `.json` downloads
/// that way), so a copy of a backup ends in `.json`, `.txt` or `.bin`.
const Set<String> pickedCopyExtensions = <String>{'.json', '.txt', '.bin'};

/// Whether [name] (a file name) can be the picker's copy of a backup file.
bool isPickedCopyFileName(String name) =>
    pickedCopyExtensions.contains(p.extension(name).toLowerCase());
