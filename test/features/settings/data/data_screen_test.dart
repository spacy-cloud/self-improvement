import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

import '../../../core/backup/support/backup_fixtures.dart' show jsonCopy;
import '../../../core/backup/support/v1_backup_support.dart';
import 'data_test_support.dart';

/// Widget tests of "Daten & Sicherung" against a real in-memory database
/// (clock 2026-10-03 10:00 Europe/Berlin) and fakes of the platform adapters.
void main() {
  group('screen', () {
    testWidgets('shows export, import and reset with honest texts', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);

      expect(find.text('Daten & Sicherung'), findsOneWidget);
      expect(find.text('Daten exportieren'), findsOneWidget);
      expect(find.text('Daten importieren'), findsOneWidget);
      expect(find.text('Alle Daten zurücksetzen'), findsOneWidget);
      expect(find.text('Jetzt exportieren'), findsOneWidget);
      expect(find.text('Sicherung auswählen'), findsOneWidget);
      expect(find.text('Zurücksetzen …'), findsOneWidget);
      expect(find.textContaining('unverschlüsselt'), findsOneWidget);
      expect(find.textContaining('lädt nichts hoch'), findsOneWidget);
      // No cloud, no account, no invented "last backup".
      expect(find.textContaining('Cloud'), findsNothing);
      expect(find.textContaining('Letzte Sicherung'), findsNothing);
      expect(env.gateway.files, isEmpty);
    });

    testWidgets('back leads to the settings', (tester) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);
      await tester.tap(find.byType(AppIconButton).first);
      await settle(tester);
      expect(find.text('Einstellungen'), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets(
      'notice, file, share sheet, temp file removed, data untouched (AT30, C09)',
      (tester) async {
        final env = await createDataEnv(tester);
        await openData(tester, env);
        final before = await env.dumpAll(tester);

        await tapText(tester, 'Jetzt exportieren');
        expect(find.text('Sicherung erstellen?'), findsOneWidget);
        expect(find.textContaining('persönlichen Einträge'), findsOneWidget);
        expect(find.text('Fortfahren'), findsOneWidget);
        expect(
          env.recording.written,
          isEmpty,
          reason: 'nothing is created before the user continues',
        );

        await tapText(tester, 'Fortfahren');

        expect(env.gateway.sharedPaths, hasLength(1));
        expect(
          env.gateway.sharedPaths.single,
          endsWith('self-improvement-backup-2026-10-03-1000.json'),
        );
        expect(env.gateway.fileExistedWhileSharing, [true]);
        expect(env.gateway.files, isEmpty, reason: 'temp file is deleted');
        expect(env.feedback.events, hasLength(1));
        expect(env.feedback.last!.kind, 'saved');
        expect(
          env.feedback.last!.message,
          'Sicherung mit 3 Einträgen erstellt und weitergegeben.',
        );
        expect(await env.dumpAll(tester), before);
      },
    );

    testWidgets('cancelling the notice creates nothing (AT30)', (tester) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);
      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Abbrechen');

      expect(find.text('Sicherung erstellen?'), findsNothing);
      expect(env.recording.written, isEmpty);
      expect(env.gateway.sharedPaths, isEmpty);
      expect(env.feedback.events, isEmpty);
    });

    testWidgets('a cancelled share sheet says nothing was handed over', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.gateway.shareStatus = BackupShareStatus.dismissed;
      await openData(tester, env);
      final before = await env.dump(tester);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');

      expect(env.feedback.last!.kind, 'info');
      expect(env.feedback.last!.message, contains('Teilen abgebrochen'));
      expect(env.feedback.last!.message, contains('nichts weitergegeben'));
      expect(env.gateway.files, isEmpty);
      expect(await env.dump(tester), before);
    });

    testWidgets('an unknown share result is not reported as success', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.gateway.shareStatus = BackupShareStatus.unknown;
      await openData(tester, env);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');

      expect(env.feedback.last!.kind, 'info');
      expect(
        env.feedback.last!.message,
        contains('Ob sie angekommen ist, kann die App nicht prüfen'),
      );
    });

    testWidgets('a write failure shows an error, keeps data, retry works', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.gateway.writeFailure = const FileSystemException('disk full');
      await openData(tester, env);
      final before = await env.dumpAll(tester);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');

      expect(env.feedback.last!.kind, 'error');
      expect(
        env.feedback.last!.message,
        'Die Sicherung konnte nicht erstellt werden. Deine Daten sind '
        'unverändert.',
      );
      expect(env.feedback.last!.onRetry, isNotNull);
      expect(env.gateway.sharedPaths, isEmpty);
      expect(await env.dumpAll(tester), before);
      // The button is usable again.
      expect(find.text('Jetzt exportieren'), findsOneWidget);

      env.gateway.writeFailure = null;
      env.feedback.last!.onRetry!();
      await settle(tester);

      expect(env.gateway.sharedPaths, hasLength(1));
      expect(env.feedback.last!.kind, 'saved');
    });

    testWidgets('a failing share sheet shows an error and cleans up', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.gateway.shareFailure = StateError('no activity');
      await openData(tester, env);
      final before = await env.dumpAll(tester);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');

      expect(env.feedback.last!.kind, 'error');
      expect(
        env.feedback.last!.message,
        contains('konnte nicht geteilt werden'),
      );
      expect(env.gateway.files, isEmpty);
      expect(await env.dumpAll(tester), before);
    });

    testWidgets('the busy button ignores a second tap (AT30)', (tester) async {
      final env = await createDataEnv(tester);
      final gate = Completer<void>();
      env.recording.writeGate = gate;
      await openData(tester, env);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');
      expect(find.text('Sicherung wird erstellt …'), findsOneWidget);

      await tester.tap(find.text('Sicherung wird erstellt …'));
      await tester.tap(find.text('Sicherung auswählen'), warnIfMissed: false);
      await tester.tap(find.text('Zurücksetzen …'), warnIfMissed: false);
      await settle(tester);
      expect(find.text('Sicherung erstellen?'), findsNothing);
      expect(env.picker.requestedLimits, isEmpty);
      expect(find.text('Wirklich alles zurücksetzen?'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(env.recording.written, hasLength(1));
      expect(env.gateway.sharedPaths, hasLength(1));
    });

    testWidgets(
      'a file this app would refuse is flagged before sharing (AT31)',
      (tester) async {
        final env = await createDataEnv(
          tester,
          overrides: [
            snapshotConsistencyCheckerProvider.overrideWithValue(
              const RejectingSnapshotChecker(),
            ),
          ],
        );
        await openData(tester, env);

        await tapText(tester, 'Jetzt exportieren');
        await tapText(tester, 'Fortfahren');

        expect(find.text('Sicherung nicht wiederherstellbar'), findsOneWidget);
        expect(
          find.textContaining('Tagesziel-Snapshots, Eintrag 1'),
          findsOneWidget,
        );
        expect(env.gateway.sharedPaths, isEmpty, reason: 'not shared yet');

        await tapText(tester, 'Abbrechen');
        expect(env.gateway.sharedPaths, isEmpty);
        expect(env.gateway.files, isEmpty, reason: 'the file is removed again');
        expect(env.feedback.last!.kind, 'info');
      },
    );

    testWidgets('the flagged file can still be shared on purpose', (
      tester,
    ) async {
      final env = await createDataEnv(
        tester,
        overrides: [
          snapshotConsistencyCheckerProvider.overrideWithValue(
            const RejectingSnapshotChecker(),
          ),
        ],
      );
      await openData(tester, env);

      await tapText(tester, 'Jetzt exportieren');
      await tapText(tester, 'Fortfahren');
      await tapText(tester, 'Trotzdem teilen');

      expect(env.gateway.sharedPaths, hasLength(1));
      expect(env.feedback.last!.kind, 'saved');
    });
  });

  group('import', () {
    testWidgets(
      'the preview shows what the file holds; cancelling keeps all data (AT30, C09)',
      (tester) async {
        final env = await createDataEnv(tester);
        final source = await makeSourceBackup(tester);
        pickFile(env, source.bytes, name: 'sicherung-2026-09-07.json');
        await openData(tester, env);
        final before = await env.dumpAll(tester);

        await tapText(tester, 'Sicherung auswählen');

        expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);
        expect(find.text('sicherung-2026-09-07.json'), findsOneWidget);
        expect(find.text('Mia Muster'), findsOneWidget);
        expect(find.text('3. Okt. 2026, 10:00 Uhr'), findsOneWidget);
        expect(find.text('1.0.0'), findsOneWidget);
        expect(find.text('Version 2'), findsOneWidget);
        expect(find.text('25'), findsOneWidget, reason: 'entries in total');
        // Counts per area (the rich fixture holds these numbers).
        for (final row in <(String, String)>[
          ('Gewichtseinträge', '3'),
          ('Workouts', '2'),
          ('Gewohnheiten', '2'),
          ('Modulstatus-Verlauf', '7'),
          ('Erinnerungsregeln', '3'),
        ]) {
          expect(find.text(row.$1), findsOneWidget, reason: row.$1);
        }
        // Honest warnings derived from the file, and the replace notice with
        // the real number of current entries.
        expect(
          find.text(
            'Eine offene Fokus-Sitzung wird pausiert wiederhergestellt.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Erinnerungen sind in der Sicherung eingeschaltet',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Vorhandene App-Daten (3 Einträge) werden vollständig ersetzt',
          ),
          findsOneWidget,
        );
        expect(find.text('Ersetzen und wiederherstellen'), findsOneWidget);

        await tapText(tester, 'Abbrechen');

        expect(find.text('Sicherung wiederherstellen?'), findsNothing);
        expect(await env.dumpAll(tester), before);
        expect(env.canceller.calls, 0);
        expect(env.listener.calls, 0);
        expect(env.feedback.events, isEmpty);
      },
    );

    testWidgets(
      'a file of v0.1.0 shows its own format version; replacing keeps its data (AT30, BS-98)',
      (tester) async {
        final env = await createDataEnv(tester);
        pickFile(
          env,
          v1Bytes(richBackupFile),
          name: 'sicherung-aus-v0-1-0.json',
        );
        await openData(tester, env);

        await tapText(tester, 'Sicherung auswählen');

        expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);
        expect(find.text('sicherung-aus-v0-1-0.json'), findsOneWidget);
        expect(find.text('Version 1'), findsOneWidget, reason: 'of the file');
        expect(find.text('Version 2'), findsNothing);
        expect(find.text('Mia Muster'), findsOneWidget);

        await tapText(tester, 'Ersetzen und wiederherstellen');

        // The file is read through the upward step and the data is there with
        // the defaults of version 2.
        final dump = await env.dump(tester);
        expect(dump['workout_day_marks'], isEmpty);
        expect(dump['step_days'], hasLength(3));
        expect(
          dump['step_days']!.every((row) => row.contains('source: manual')),
          isTrue,
        );
        expect(dump['tasks'], hasLength(3));
        expect(
          dump['app_settings']!.single,
          contains('healthStepsSyncEnabled: false'),
        );
      },
    );

    testWidgets('the close button cancels like "Abbrechen"', (tester) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      pickFile(env, source.bytes);
      await openData(tester, env);
      final before = await env.dump(tester);

      await tapText(tester, 'Sicherung auswählen');
      await tester.tap(find.byType(AppIconButton).last);
      await settle(tester);

      expect(find.text('Sicherung wiederherstellen?'), findsNothing);
      expect(await env.dump(tester), before);
    });

    testWidgets(
      'confirming replaces everything atomically and tells the engine (AT30, C09)',
      (tester) async {
        final env = await createDataEnv(tester);
        final source = await makeSourceBackup(tester);
        pickFile(env, source.bytes);
        await openData(tester, env);
        expect(
          await env.dump(tester),
          isNot(source.expectedRows),
          reason: 'the old data differs from the file',
        );

        await tapText(tester, 'Sicherung auswählen');
        await tapText(tester, 'Ersetzen und wiederherstellen');

        expect(find.text('Sicherung wiederherstellen?'), findsNothing);
        expect(await env.dump(tester), source.expectedRows);
        // No leftover of the old data in the technical tables either.
        final all = await env.dumpAll(tester);
        for (final rows in all.values) {
          expect(rows.where((row) => row.contains('2025-06-02')), isEmpty);
        }
        expect(env.canceller.calls, 1, reason: 'OS notifications cancelled');
        expect(env.listener.calls, 1, reason: 'providers and reminders told');
        expect(env.feedback.events, hasLength(1));
        expect(env.feedback.last!.kind, 'saved');
        expect(
          env.feedback.last!.message,
          'Sicherung wiederhergestellt: 25 Einträge.',
        );
        // The days with facts went to the projection (XP is recomputed).
        expect(env.projection.syncs, hasLength(1));
        expect(env.projection.allDays, isNotEmpty);
      },
    );

    testWidgets(
      'the computed values are rebuilt from the facts of the file (AT30)',
      (tester) async {
        final env = await createDataEnv(tester, realProjection: true);
        final source = await makeSourceBackup(tester);
        pickFile(env, source.bytes);
        await openData(tester, env);

        await tapText(tester, 'Sicherung auswählen');
        await tapText(tester, 'Ersetzen und wiederherstellen');

        final xp = (await tester.runAsync(env.harness.totalXp))!;
        expect(xp, greaterThan(0));
        // The engine alone computes the same for the same file.
        final expected = (await tester.runAsync(() async {
          final other = await DataHarness.create(realProjection: true);
          try {
            final service = BackupService(
              database: other.database,
              clock: other.clock,
              files: InMemoryBackupFileGateway(),
              projections: other.projections,
            );
            final preparation = await service.prepareImport(source.bytes);
            await service.confirmImport((preparation as ImportReady).prepared);
            return await other.totalXp();
          } finally {
            await other.dispose();
          }
        }))!;
        expect(xp, expected);
      },
    );

    testWidgets(
      'a failing replace keeps the old data and says so (AT27, C09)',
      (tester) async {
        final env = await createDataEnv(tester);
        env.projection.failure = StateError('boom');
        final source = await makeSourceBackup(tester);
        pickFile(env, source.bytes);
        await openData(tester, env);
        final before = await env.dumpAll(tester);

        await tapText(tester, 'Sicherung auswählen');
        await tapText(tester, 'Ersetzen und wiederherstellen');

        // The sheet stays open with the reason; nothing was changed.
        expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);
        expect(
          find.textContaining('Deine bisherigen Daten sind unverändert'),
          findsOneWidget,
        );
        expect(await env.dumpAll(tester), before);
        expect(env.canceller.calls, 0);
        expect(env.listener.calls, 0);

        // The retry works once the cause is gone.
        env.projection.failure = null;
        await tapText(tester, 'Ersetzen und wiederherstellen');
        expect(await env.dump(tester), source.expectedRows);
        expect(env.feedback.last!.kind, 'saved');
      },
    );

    testWidgets('a double tap on the confirmation replaces once', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      pickFile(env, source.bytes);
      await openData(tester, env);
      await tapText(tester, 'Sicherung auswählen');

      final confirm = find.text('Ersetzen und wiederherstellen');
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await settle(tester);

      expect(env.listener.calls, 1);
      expect(env.canceller.calls, 1);
      expect(env.feedback.events.where((e) => e.kind == 'saved'), hasLength(1));
    });

    testWidgets('while the data is replaced the sheet cannot be closed', (
      tester,
    ) async {
      final gated = GatedProjection();
      final env = await createDataEnv(tester, projectionOverride: gated);
      final source = await makeSourceBackup(tester);
      pickFile(env, source.bytes);
      await openData(tester, env);
      await tapText(tester, 'Sicherung auswählen');

      await tester.tap(find.text('Ersetzen und wiederherstellen'));
      await settle(tester);
      expect(gated.syncs, 1, reason: 'the replace is running');
      expect(find.text('Wird wiederhergestellt …'), findsOneWidget);

      // Neither the close button, "Abbrechen", the barrier nor the system
      // back action closes the sheet half way.
      await tester.tap(find.byType(AppIconButton).last, warnIfMissed: false);
      await tester.tap(find.text('Abbrechen'), warnIfMissed: false);
      await tester.tapAt(const Offset(196, 20));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);

      gated.gate.complete();
      await settle(tester);
      expect(find.text('Sicherung wiederherstellen?'), findsNothing);
      expect(env.listener.calls, 1);
      expect(env.feedback.last!.kind, 'saved');
    });

    testWidgets('failing follow-up steps are reported, the data stays', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.canceller.failure = StateError('no plugin');
      final source = await makeSourceBackup(tester);
      pickFile(env, source.bytes);
      await openData(tester, env);

      await tapText(tester, 'Sicherung auswählen');
      await tapText(tester, 'Ersetzen und wiederherstellen');

      expect(await env.dump(tester), source.expectedRows);
      expect(env.feedback.last!.kind, 'info');
      expect(
        env.feedback.last!.message,
        contains('Einige Folgeschritte (Erinnerungen, Anzeige)'),
      );
    });

    testWidgets('another app version is named in the preview', (tester) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      pickFile(env, encodeJson({...source.json, 'appVersion': '0.9.2'}));
      await openData(tester, env);

      await tapText(tester, 'Sicherung auswählen');

      expect(find.text('0.9.2'), findsOneWidget);
      expect(
        find.textContaining('stammt aus App-Version 0.9.2 (diese App: 1.0.0)'),
        findsOneWidget,
      );
    });

    testWidgets(
      'while the file is chosen the button says so and ignores taps',
      (tester) async {
        final gated = GatedPicker();
        final env = await createDataEnv(tester, pickerOverride: gated);
        await openData(tester, env);

        await tapText(tester, 'Sicherung auswählen');
        expect(find.text('Datei wird geprüft …'), findsOneWidget);

        await tester.tap(find.text('Datei wird geprüft …'));
        await tester.tap(find.text('Jetzt exportieren'), warnIfMissed: false);
        await tester.tap(find.text('Zurücksetzen …'), warnIfMissed: false);
        await settle(tester);
        expect(gated.calls, 1);
        expect(find.text('Sicherung erstellen?'), findsNothing);
        expect(find.text('Wirklich alles zurücksetzen?'), findsNothing);

        gated.gate.complete(null);
        await settle(tester);
        expect(find.text('Sicherung auswählen'), findsOneWidget);
        expect(env.feedback.events, isEmpty);
      },
    );

    testWidgets('closing the file picker changes and says nothing', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);
      final before = await env.dumpAll(tester);

      env.picker.next = null;
      await tapText(tester, 'Sicherung auswählen');

      expect(env.picker.requestedLimits, hasLength(1));
      expect(find.text('Sicherung wiederherstellen?'), findsNothing);
      expect(find.text('Import nicht möglich'), findsNothing);
      expect(env.feedback.events, isEmpty);
      expect(await env.dumpAll(tester), before);
      expect(find.text('Sicherung auswählen'), findsOneWidget);
    });

    testWidgets('a failing file picker shows an error and changes nothing', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.picker.failure = const FileSystemException('no access');
      await openData(tester, env);
      final before = await env.dumpAll(tester);

      await tapText(tester, 'Sicherung auswählen');

      expect(env.feedback.last!.kind, 'error');
      expect(env.feedback.last!.message, contains('nicht gelesen werden'));
      expect(await env.dumpAll(tester), before);
    });
  });

  group('rejected files change nothing (AT31, C09)', () {
    final cases = <(String, Uint8List Function(SourceBackup), String)>[
      (
        'a foreign format marker',
        (s) => encodeJson({...s.json, 'format': 'other_app_backup'}),
        'keine Sicherung dieser App',
      ),
      (
        'a wrong schema version',
        (s) => encodeJson({...s.json, 'schemaVersion': 3}),
        'Schema-Version dieser Datei wird nicht unterstützt',
      ),
      (
        'broken JSON',
        (s) => Uint8List.fromList('{"format": "levelup'.codeUnits),
        'kein gültiges JSON',
      ),
      (
        'text that is not JSON at all',
        (s) => Uint8List.fromList('Hallo Welt'.codeUnits),
        'kein gültiges JSON',
      ),
      ('an empty file', (s) => Uint8List(0), 'Die Datei ist leer'),
      (
        'a file above 10 MiB',
        (s) => Uint8List(10 * 1024 * 1024 + 1),
        'größer als 10 MiB',
      ),
      (
        'more than 50.000 records',
        (s) => encodeJson(_withRecords(s.json, 'water_entries', 50001)),
        'mehr als 50.000 Datensätze',
      ),
      (
        'an impossible weight',
        (s) => encodeJson(
          _edit(s.json, (data) {
            _record(data, 'weight_entries', 0)['weight_grams'] = 5;
          }),
        ),
        'Gewichtseinträge, Eintrag 1: Gewicht außerhalb des erlaubten '
            'Bereichs',
      ),
      (
        'a duplicate id',
        (s) => encodeJson(
          _edit(s.json, (data) {
            _record(data, 'weight_entries', 1)['id'] = _record(
              data,
              'weight_entries',
              0,
            )['id'];
          }),
        ),
        'ID kommt mehrfach vor',
      ),
      (
        'a missing foreign key',
        (s) => encodeJson(
          _edit(s.json, (data) {
            _record(data, 'habit_checks', 0)['habit_id'] =
                '00000000-0000-4000-8000-00000000dead';
          }),
        ),
        'Verweis auf eine nicht vorhandene Gewohnheit',
      ),
      (
        'a technical table inside the data',
        (s) => encodeJson(
          _edit(s.json, (data) {
            data['xp_awards'] = <Object?>[];
          }),
        ),
        'Technische Tabelle ist nicht Teil einer Sicherung',
      ),
    ];

    for (final (name, build, reason) in cases) {
      testWidgets('$name: readable reason, no change (AT31)', (tester) async {
        final env = await createDataEnv(tester);
        final source = await makeSourceBackup(tester);
        pickFile(env, build(source), name: 'fotos.zip');
        await openData(tester, env);
        final before = await env.dumpAll(tester);

        await tapText(tester, 'Sicherung auswählen');

        expect(find.text('Import nicht möglich'), findsOneWidget);
        expect(
          find.textContaining(
            'Die Datei „fotos.zip“ ist keine gültige Sicherung',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('nicht verändert'), findsOneWidget);
        expect(find.textContaining(reason), findsOneWidget);
        expect(find.text('Sicherung wiederherstellen?'), findsNothing);
        expect(find.text('Andere Datei wählen'), findsOneWidget);

        await tapText(tester, 'Schließen');

        expect(await env.dumpAll(tester), before);
        expect(env.canceller.calls, 0);
        expect(env.listener.calls, 0);
        expect(env.feedback.events, isEmpty);
        expect(find.text('Sicherung auswählen'), findsOneWidget);
      });
    }

    testWidgets('"Andere Datei wählen" opens the picker again', (tester) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      pickFile(env, Uint8List.fromList('kein json'.codeUnits));
      await openData(tester, env);

      await tapText(tester, 'Sicherung auswählen');
      expect(find.text('Import nicht möglich'), findsOneWidget);

      pickFile(env, source.bytes, name: 'zweite.json');
      await tapText(tester, 'Andere Datei wählen');

      expect(env.picker.requestedLimits, hasLength(2));
      expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);
      expect(find.text('zweite.json'), findsOneWidget);
    });

    testWidgets('only the first five reasons are listed, with a note', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      pickFile(
        env,
        encodeJson(
          _edit(source.json, (data) {
            for (var i = 0; i < 3; i++) {
              _record(data, 'weight_entries', i)['weight_grams'] = 5;
              _record(data, 'water_entries', i)['amount_ml'] = 1;
            }
          }),
        ),
      );
      await openData(tester, env);

      await tapText(tester, 'Sicherung auswählen');

      expect(find.text('Gründe'), findsOneWidget);
      expect(find.textContaining('Eintrag '), findsNWidgets(5));
      expect(
        find.text('Ein weiteres Problem wird nicht angezeigt.'),
        findsOneWidget,
      );
    });
  });

  group('reset', () {
    Future<void> openReset(WidgetTester tester) async {
      await tapText(tester, 'Zurücksetzen …');
      expect(find.text('Wirklich alles zurücksetzen?'), findsOneWidget);
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
    }

    bool confirmEnabled(WidgetTester tester) =>
        tester
            .getSemantics(find.bySemanticsLabel('Alles löschen'))
            .flagsCollection
            .isEnabled ==
        Tristate.isTrue;

    testWidgets('cancelling keeps all data, timers and reminders (AT32, C09)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createDataEnv(tester);
      await openData(tester, env);
      final before = await env.dumpAll(tester);

      await openReset(tester);
      await type(tester, 'LÖSCHEN');
      await tapText(tester, 'Abbrechen');

      expect(find.text('Wirklich alles zurücksetzen?'), findsNothing);
      expect(await env.dumpAll(tester), before);
      expect(env.canceller.calls, 0);
      expect(env.listener.calls, 0);
      expect(env.feedback.events, isEmpty);
      handle.dispose();
    });

    testWidgets(
      'only the exact word confirms; every other text deletes nothing (AT32)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createDataEnv(tester);
        await openData(tester, env);
        final before = await env.dumpAll(tester);
        await openReset(tester);

        for (final wrong in <String>[
          '',
          'löschen',
          'Löschen',
          'LOESCHEN',
          'LOSCHEN',
          'LÖSCHEN ',
          ' LÖSCHEN',
          'LÖSCHEN!',
          'LÖSCH',
          'ALLES',
        ]) {
          await type(tester, wrong);
          expect(confirmEnabled(tester), isFalse, reason: '"$wrong"');
          await tester.tap(find.text('Alles löschen'), warnIfMissed: false);
          await settle(tester);
          expect(
            find.text('Wirklich alles zurücksetzen?'),
            findsOneWidget,
            reason: '"$wrong" must keep the sheet open',
          );
        }
        expect(await env.dumpAll(tester), before);
        expect(env.canceller.calls, 0);
        expect(env.listener.calls, 0);

        await type(tester, 'LÖSCHEN');
        expect(confirmEnabled(tester), isTrue);
        handle.dispose();
      },
    );

    testWidgets('a near miss gets a hint how to type it', (tester) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);
      await openReset(tester);

      await type(tester, 'löschen');
      expect(find.textContaining('Fast richtig'), findsOneWidget);
      await type(tester, 'LÖSCHEN ');
      expect(find.textContaining('Fast richtig'), findsOneWidget);
      await type(tester, 'LOESCHEN');
      expect(find.textContaining('Fast richtig'), findsNothing);
      await type(tester, 'LÖSCHEN');
      expect(find.textContaining('Fast richtig'), findsNothing);
    });

    testWidgets(
      'the exact word deletes everything and returns to the fresh start (AT32, C09, Q01)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createDataEnv(tester);
        final router = await openData(tester, env);
        // Old files must not survive the reset either.
        env.gateway.files['/cache/backup_exports/old.json'] = Uint8List(1);

        await openReset(tester);
        expect(
          find.textContaining('Dein Profil, 3 Einträge, deine Ziele'),
          findsOneWidget,
        );
        await type(tester, 'LÖSCHEN');
        expect(confirmEnabled(tester), isTrue);
        await tapText(tester, 'Alles löschen');

        final all = await env.dumpAll(tester);
        for (final entry in all.entries) {
          if (entry.key == 'profile' || entry.key == 'app_settings') {
            expect(entry.value, hasLength(1), reason: entry.key);
          } else {
            expect(entry.value, isEmpty, reason: entry.key);
          }
        }
        final profile = (await tester.runAsync(
          () => env.harness.database
              .select(env.harness.database.profile)
              .getSingle(),
        ))!;
        expect(profile.onboardingCompleted, isFalse);
        expect(profile.displayName, isNull);
        expect(env.canceller.calls, 1);
        expect(env.listener.calls, 1);
        expect(env.gateway.files, isEmpty);
        expect(env.gateway.deleteCalls, contains(true));
        expect(env.feedback.last!.kind, 'info');
        expect(env.feedback.last!.message, 'Alle App-Daten wurden gelöscht.');
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/',
          reason: 'the start route lets the router show the onboarding',
        );
        expect(find.text('Start'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('failing follow-up steps are reported, the data is gone', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      env.canceller.failure = StateError('no plugin');
      await openData(tester, env);

      await openReset(tester);
      await type(tester, 'LÖSCHEN');
      await tapText(tester, 'Alles löschen');

      final profile = (await tester.runAsync(
        () => env.harness.database
            .select(env.harness.database.profile)
            .getSingle(),
      ))!;
      expect(profile.onboardingCompleted, isFalse);
      expect(env.feedback.last!.kind, 'info');
      expect(env.feedback.last!.message, contains('Einige Folgeschritte'));
    });

    testWidgets('a failing reset keeps the sheet and the data (Q01)', (
      tester,
    ) async {
      final failing = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory().interceptWith(_FailingDeletes()),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(() => tester.runAsync(failing.close));
      final env = await createDataEnv(
        tester,
        overrides: [
          resetServiceProvider.overrideWith(
            (ref) => ResetService(
              database: failing,
              clock: ref.watch(clockProvider),
              notifications: ref.watch(notificationCancellerProvider),
              listener: ref.watch(backupListenerProvider),
            ),
          ),
        ],
      );
      await openData(tester, env);

      await openReset(tester);
      await type(tester, 'LÖSCHEN');
      await tapText(tester, 'Alles löschen');

      expect(find.text('Wirklich alles zurücksetzen?'), findsOneWidget);
      expect(
        find.textContaining('Das Zurücksetzen ist fehlgeschlagen'),
        findsOneWidget,
      );
      expect(find.text('LÖSCHEN'), findsWidgets, reason: 'the input is kept');
      expect(env.canceller.calls, 0);
      expect(env.listener.calls, 0);
    });

    testWidgets('a double tap on "Alles löschen" resets once', (tester) async {
      final env = await createDataEnv(tester);
      await openData(tester, env);
      await openReset(tester);
      await type(tester, 'LÖSCHEN');

      final confirm = find.text('Alles löschen');
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await settle(tester);

      expect(env.listener.calls, 1);
      expect(env.canceller.calls, 1);
    });

    testWidgets(
      '"Erst Sicherung exportieren" starts the export, deletes nothing',
      (tester) async {
        final env = await createDataEnv(tester);
        await openData(tester, env);
        final before = await env.dumpAll(tester);

        await openReset(tester);
        await tapText(tester, 'Erst Sicherung exportieren');

        expect(find.text('Wirklich alles zurücksetzen?'), findsNothing);
        expect(find.text('Sicherung erstellen?'), findsOneWidget);
        await tapText(tester, 'Fortfahren');

        expect(env.gateway.sharedPaths, hasLength(1));
        expect(await env.dumpAll(tester), before);
        expect(env.canceller.calls, 0);
      },
    );
  });

  group('round trip (AT30)', () {
    testWidgets(
      'export, change the data, import the exported file: the data is back',
      (tester) async {
        final env = await createDataEnv(tester);
        final source = await makeSourceBackup(tester);
        // Fill the app with the content of the rich file first.
        pickFile(env, source.bytes);
        await openData(tester, env);
        await tapText(tester, 'Sicherung auswählen');
        await tapText(tester, 'Ersetzen und wiederherstellen');
        final original = await env.dump(tester);
        expect(original, source.expectedRows);

        // 1. Export through the UI.
        await tapText(tester, 'Jetzt exportieren');
        await tapText(tester, 'Fortfahren');
        expect(env.recording.written, hasLength(1));
        final exported = env.recording.written.single;

        // 2. Change the data behind the app's back.
        await tester.runAsync(() async {
          final db = env.harness.database;
          await (db.delete(db.weightEntries)).go();
          await (db.update(db.profile)).write(
            const ProfileCompanion(displayName: Value('Jemand anderes')),
          );
        });
        expect(await env.dump(tester), isNot(original));

        // 3. Import the exported file through the UI.
        pickFile(env, exported, name: 'self-improvement-backup.json');
        await tapText(tester, 'Sicherung auswählen');
        expect(find.text('Mia Muster'), findsOneWidget);
        await tapText(tester, 'Ersetzen und wiederherstellen');

        expect(await env.dump(tester), original);
      },
    );
  });
}

Map<String, Object?> _edit(
  Map<String, Object?> json,
  void Function(Map<String, Object?> data) edit,
) {
  final copy = jsonCopy(json);
  edit(copy['data']! as Map<String, Object?>);
  return copy;
}

Map<String, Object?> _withRecords(
  Map<String, Object?> json,
  String table,
  int count,
) => _edit(json, (data) {
  data[table] = List<Object?>.generate(count, (_) => <String, Object?>{});
});

Map<String, Object?> _record(
  Map<String, Object?> data,
  String table,
  int index,
) => (data[table]! as List<Object?>)[index]! as Map<String, Object?>;

/// A query interceptor that fails every `DELETE`, so a reset cannot start.
class _FailingDeletes extends QueryInterceptor {
  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => throw StateError('disk I/O error');
}
