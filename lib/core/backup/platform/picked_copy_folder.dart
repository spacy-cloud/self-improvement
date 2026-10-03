/// Android's file picker (`file_selector`) copies the document the user chose
/// to `<cache>/<uuid>/<name>` and only schedules the deletion for the end of
/// the process. The copy holds the complete, unencrypted backup, so the app
/// removes it itself: right after reading ([FileSelectorBackupFilePicker]) and
/// as a sweep at start and reset ([SharePlusBackupFileGateway]).
///
/// Only folders that look exactly like such a copy folder are ever touched.
final RegExp _uuidFolder = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

/// Whether [name] (a folder name directly below the cache directory) has the
/// shape of the picker's copy folders: a UUID.
bool isPickedCopyFolderName(String name) => _uuidFolder.hasMatch(name);
