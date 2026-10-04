import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// File name of the production database (without extension handling by drift).
const String appDatabaseName = 'self_improvement';

/// Opens the production connection in the application support directory.
///
/// The file lives in the app sandbox and is excluded from Android auto backup
/// (see the Android manifest). It is not additionally encrypted.
QueryExecutor openAppConnection() {
  return driftDatabase(
    name: appDatabaseName,
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
