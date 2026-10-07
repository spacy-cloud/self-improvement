import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/settings/presentation/data_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/backup/support/backup_fixtures.dart';
import '../../../support/pump_app.dart';

/// Route of the screen under test.
const String dataRoute = '/settings/data';

/// The environment of a data screen test: a real in-memory database (clock
/// 2026-10-03 10:00 Europe/Berlin) with unrelated "old" data, the fakes of the
/// platform adapters and the recording feedback service.
class DataEnv {
  DataEnv({
    required this.harness,
    required this.container,
    required this.feedback,
    required this.gateway,
    required this.recording,
    required this.picker,
    required this.canceller,
    required this.listener,
    required this.projection,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;
  final InMemoryBackupFileGateway gateway;
  final RecordingGateway recording;
  final FakeBackupFilePicker picker;
  final RecordingNotificationCanceller canceller;
  final RecordingBackupListener listener;
  final RecordingProjectionSynchronizer projection;

  /// All rows of the seventeen backup tables, as text.
  Future<Map<String, List<String>>> dump(WidgetTester tester) async =>
      (await tester.runAsync(() => backupTablesDump(harness.database)))!;

  /// All rows of every table (technical ones included), as text.
  Future<Map<String, List<String>>> dumpAll(WidgetTester tester) async =>
      (await tester.runAsync(() => dumpDatabase(harness.database)))!;
}

/// A snapshot checker that rejects every file (to make an export "not
/// restorable" without a file of more than 10 MiB).
final class RejectingSnapshotChecker implements SnapshotConsistencyChecker {
  const RejectingSnapshotChecker();

  @override
  List<ImportProblem> check(BackupData data) => [
    ImportProblem.record(
      BackupTable.dailyGoalSnapshots,
      0,
      'Der Tagesziel-Snapshot widerspricht der Zielhistorie.',
    ),
  ];
}

/// Wraps the in-memory gateway: keeps the bytes of every written file (the
/// gateway deletes them after sharing) and can hold a write back until the
/// test lets it go.
final class RecordingGateway implements BackupFileGateway {
  RecordingGateway(this.inner);

  final InMemoryBackupFileGateway inner;

  /// Content of every file that was written, in order.
  final List<Uint8List> written = [];

  /// While set, a write waits for it.
  Completer<void>? writeGate;

  @override
  Future<String> writeTemporaryExport({
    required String fileName,
    required Uint8List bytes,
  }) async {
    written.add(bytes);
    final gate = writeGate;
    if (gate != null) {
      await gate.future;
    }
    return inner.writeTemporaryExport(fileName: fileName, bytes: bytes);
  }

  @override
  Future<BackupShareStatus> shareExport(String path) => inner.shareExport(path);

  @override
  Future<void> deleteTemporaryExports({
    bool includePlatformShareCopies = false,
  }) => inner.deleteTemporaryExports(
    includePlatformShareCopies: includePlatformShareCopies,
  );
}

/// A projection that holds the replace of an import until the test completes
/// [gate]: the import is busy while it waits.
final class GatedProjection implements ProjectionSynchronizer {
  final Completer<void> gate = Completer<void>();
  int syncs = 0;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    syncs++;
    await gate.future;
  }

  @override
  Future<int> totalXp() async => 0;
}

/// A file picker that stays open until the test completes [gate].
final class GatedPicker implements BackupFilePicker {
  final Completer<PickedBackupFile?> gate = Completer<PickedBackupFile?>();
  int calls = 0;

  @override
  Future<PickedBackupFile?> pickBackupFile({
    int maxBytes = BackupFormat.maxFileBytes,
  }) {
    calls++;
    return gate.future;
  }
}

Future<DataEnv> createDataEnv(
  WidgetTester tester, {
  BackupFilePicker? pickerOverride,
  ProjectionSynchronizer? projectionOverride,
  bool oldData = true,
  bool realProjection = false,
  List<Override> overrides = const <Override>[],
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final projection = RecordingProjectionSynchronizer();
  final harness = (await tester.runAsync(
    () => DataHarness.create(
      projections: realProjection ? null : (projectionOverride ?? projection),
      realProjection: realProjection,
    ),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(harness.seedOnboarded);
  if (oldData) {
    await tester.runAsync(() => populateOtherData(harness.database));
  }
  final feedback = RecordingFeedbackService(ids: harness.ids);
  final gateway = InMemoryBackupFileGateway();
  final recording = RecordingGateway(gateway);
  final picker = FakeBackupFilePicker();
  final canceller = RecordingNotificationCanceller();
  final listener = RecordingBackupListener();
  final container = harness.createContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      backupFileGatewayProvider.overrideWithValue(recording),
      backupFilePickerProvider.overrideWithValue(pickerOverride ?? picker),
      notificationCancellerProvider.overrideWithValue(canceller),
      backupListenerProvider.overrideWithValue(listener),
      ...overrides,
    ],
  );
  return DataEnv(
    harness: harness,
    container: container,
    feedback: feedback,
    gateway: gateway,
    recording: recording,
    picker: picker,
    canceller: canceller,
    listener: listener,
    projection: projection,
  );
}

List<RouteBase> dataRoutes() => [
  GoRoute(
    path: '/',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Start'))),
  ),
  GoRoute(
    path: '/settings',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Einstellungen'))),
  ),
  GoRoute(path: dataRoute, builder: (context, state) => const DataScreen()),
];

Future<GoRouter> openData(
  WidgetTester tester,
  DataEnv env, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) => pumpRouterApp(
  tester,
  routes: dataRoutes(),
  initialLocation: dataRoute,
  container: env.container,
  size: size,
  textScale: textScale,
  viewInsets: viewInsets,
);

/// A backup file made from the "rich" database (every table filled, synthetic
/// person "Mia Muster") together with the rows a correct import must produce.
class SourceBackup {
  SourceBackup({
    required this.bytes,
    required this.expectedRows,
    required this.json,
  });

  final Uint8List bytes;
  final Map<String, List<String>> expectedRows;
  final Map<String, Object?> json;
}

Future<SourceBackup> makeSourceBackup(WidgetTester tester) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return (await tester.runAsync(() async {
    final source = await DataHarness.create();
    try {
      await populateRichDatabase(source.database);
      final exported = await BackupExporter(
        database: source.database,
        clock: source.clock,
      ).export();
      final rows = await expectedExportRows(source.database);
      final json =
          jsonDecode(utf8.decode(exported.bytes)) as Map<String, Object?>;
      return SourceBackup(
        bytes: exported.bytes,
        expectedRows: rows,
        json: json,
      );
    } finally {
      await source.dispose();
    }
  }))!;
}

/// Bytes of [json] as the content of a backup file.
Uint8List encodeJson(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// Makes [env]'s picker return [bytes] as a file called [name].
void pickFile(DataEnv env, Uint8List bytes, {String name = 'sicherung.json'}) {
  env.picker.next = PickedBackupFile(name: name, bytes: bytes);
}

/// Taps the widget with [text] and settles the animations.
Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}

/// Lets real async work (database, fakes) finish and the animations end.
Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}
