import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/file_selector_backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/share_plus_backup_file_gateway.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:share_plus/share_plus.dart';

/// The real share sheet, the real cache directory and the real picker dialog
/// need a device and are NOT covered here. What is covered: the file handling
/// of the gateway (on a temporary directory of the host), the mapping of the
/// share result, and the size handling of the picker.

const String fileName = 'self-improvement-backup-2026-07-15-2330.json';

Uint8List bytesOf(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('backup_gateway_test');
    addTearDown(() async {
      if (await cache.exists()) {
        await cache.delete(recursive: true);
      }
    });
  });

  group('SharePlusBackupFileGateway: temporary files', () {
    SharePlusBackupFileGateway gateway({
      Future<ShareResult> Function(ShareParams params)? share,
      String? title,
    }) => SharePlusBackupFileGateway(
      cacheDirectory: () async => cache,
      share:
          share ??
          (_) async => const ShareResult('ok', ShareResultStatus.success),
      shareTitle: title ?? 'Sicherung teilen',
    );

    String exportPath(String name) =>
        '${cache.path}${Platform.pathSeparator}backup_exports'
        '${Platform.pathSeparator}$name';

    test(
      'writes the bytes to a file in the export folder of the cache',
      () async {
        final path = await gateway().writeTemporaryExport(
          fileName: fileName,
          bytes: bytesOf('{"a":1}'),
        );
        expect(path, exportPath(fileName));
        expect(File(path).readAsStringSync(), '{"a":1}');
      },
    );

    test('creates the folder on demand and overwrites an older file', () async {
      final g = gateway();
      await g.writeTemporaryExport(fileName: fileName, bytes: bytesOf('first'));
      final path = await g.writeTemporaryExport(
        fileName: fileName,
        bytes: bytesOf('second'),
      );
      expect(File(path).readAsStringSync(), 'second');
      expect(Directory(exportPath('')).listSync(), hasLength(1));
    });

    test('writes all bytes of a large file', () async {
      final big = Uint8List(3 * 1024 * 1024)
        ..fillRange(0, 3 * 1024 * 1024, 0x61);
      final path = await gateway().writeTemporaryExport(
        fileName: fileName,
        bytes: big,
      );
      expect(File(path).lengthSync(), big.length);
    });

    test(
      'rejects anything that is not a backup file name, writing nothing',
      () async {
        for (final bad in [
          '',
          '../$fileName',
          'sub/$fileName',
          '$fileName.exe',
          'notes.json',
          r'..\self-improvement-backup-2026-07-15-2330.json',
        ]) {
          await expectLater(
            gateway().writeTemporaryExport(fileName: bad, bytes: bytesOf('x')),
            throwsArgumentError,
            reason: bad,
          );
        }
        expect(cache.listSync(recursive: true), isEmpty);
      },
    );

    test('deleting removes the export folder and nothing else', () async {
      final g = gateway();
      await g.writeTemporaryExport(fileName: fileName, bytes: bytesOf('x'));
      File('${cache.path}${Platform.pathSeparator}other.txt')
          .writeAsStringSync('keep');
      Directory('${cache.path}${Platform.pathSeparator}share_plus')
          .createSync();
      File(
        '${cache.path}${Platform.pathSeparator}share_plus${Platform.pathSeparator}copy.json',
      ).writeAsStringSync('{}');

      await g.deleteTemporaryExports();

      expect(Directory(exportPath('')).existsSync(), isFalse);
      expect(
        File('${cache.path}${Platform.pathSeparator}other.txt').existsSync(),
        isTrue,
      );
      expect(
        File(
          '${cache.path}${Platform.pathSeparator}share_plus${Platform.pathSeparator}copy.json',
        ).existsSync(),
        isTrue,
        reason: 'a receiving app may still read the plugin copy',
      );
    });

    test('at start (flag set) the platform share copies go as well', () async {
      final g = gateway();
      await g.writeTemporaryExport(fileName: fileName, bytes: bytesOf('x'));
      File('${cache.path}${Platform.pathSeparator}other.txt')
          .writeAsStringSync('keep');
      Directory('${cache.path}${Platform.pathSeparator}share_plus')
          .createSync();
      File(
        '${cache.path}${Platform.pathSeparator}share_plus${Platform.pathSeparator}copy.json',
      ).writeAsStringSync('{}');

      await g.deleteTemporaryExports(includePlatformShareCopies: true);

      expect(Directory(exportPath('')).existsSync(), isFalse);
      expect(
        Directory('${cache.path}${Platform.pathSeparator}share_plus')
            .existsSync(),
        isFalse,
      );
      expect(
        File('${cache.path}${Platform.pathSeparator}other.txt').existsSync(),
        isTrue,
      );
    });

    test(
      'at start the picker copies left in the cache go: UUID folders that hold '
      'only JSON files, nothing else',
      () async {
        final sep = Platform.pathSeparator;
        void put(String relative, [String content = '{}']) {
          final file = File('${cache.path}$sep$relative')
            ..createSync(recursive: true);
          file.writeAsStringSync(content);
        }

        const copy = '123e4567-e89b-42d3-a456-426614174000';
        const mixed = '223e4567-e89b-42d3-a456-426614174000';
        const foreign = '323e4567-e89b-42d3-a456-426614174000';
        put('$copy${sep}meine-sicherung.json');
        put('$mixed${sep}a.json');
        put('$mixed${sep}notes.txt', 'keep');
        put('$foreign${sep}image.png', 'keep');
        put('notes${sep}b.json');
        put('loose.json');

        // Without the flag nothing of the picker is touched.
        await gateway().deleteTemporaryExports();
        expect(Directory('${cache.path}$sep$copy').existsSync(), isTrue);

        await gateway().deleteTemporaryExports(
          includePlatformShareCopies: true,
        );

        expect(Directory('${cache.path}$sep$copy').existsSync(), isFalse);
        expect(
          File('${cache.path}$sep$mixed${sep}a.json').existsSync(),
          isTrue,
          reason: 'a folder with other content is not a picker copy',
        );
        expect(
          File('${cache.path}$sep$foreign${sep}image.png').existsSync(),
          isTrue,
        );
        expect(
          File('${cache.path}${sep}notes${sep}b.json').existsSync(),
          isTrue,
        );
        expect(File('${cache.path}${sep}loose.json').existsSync(), isTrue);
      },
    );

    test('deleting is idempotent when there is nothing to delete', () async {
      final g = gateway();
      await g.deleteTemporaryExports();
      await g.deleteTemporaryExports(includePlatformShareCopies: true);
      expect(cache.listSync(), isEmpty);
    });
  });

  group('SharePlusBackupFileGateway: share sheet', () {
    test('shares exactly one JSON file and nothing else', () async {
      ShareParams? seen;
      final g = SharePlusBackupFileGateway(
        cacheDirectory: () async => cache,
        share: (params) async {
          seen = params;
          return const ShareResult('ok', ShareResultStatus.success);
        },
      );
      final path = await g.writeTemporaryExport(
        fileName: fileName,
        bytes: bytesOf('{}'),
      );
      await g.shareExport(path);

      final params = seen!;
      expect(params.files, hasLength(1));
      expect(params.files!.single.path, path);
      expect(params.files!.single.mimeType, 'application/json');
      expect(params.text, isNull, reason: 'no personal values in a message');
      expect(params.uri, isNull);
      expect(params.subject, isNull);
      expect(params.title, 'Sicherung teilen');
    });

    test('the sheet title is configurable', () async {
      ShareParams? seen;
      final g = SharePlusBackupFileGateway(
        cacheDirectory: () async => cache,
        share: (params) async {
          seen = params;
          return ShareResult.unavailable;
        },
        shareTitle: 'Backup senden',
      );
      await g.shareExport('/x/$fileName');
      expect(seen!.title, 'Backup senden');
    });

    test('maps the plugin result to the domain status', () async {
      const mapping = {
        ShareResultStatus.success: BackupShareStatus.shared,
        ShareResultStatus.dismissed: BackupShareStatus.dismissed,
        ShareResultStatus.unavailable: BackupShareStatus.unknown,
      };
      for (final entry in mapping.entries) {
        final g = SharePlusBackupFileGateway(
          cacheDirectory: () async => cache,
          share: (_) async => ShareResult('raw', entry.key),
        );
        expect(await g.shareExport('/x/$fileName'), entry.value);
      }
    });

    test('a failing share call propagates', () async {
      final g = SharePlusBackupFileGateway(
        cacheDirectory: () async => cache,
        share: (_) async => throw StateError('no activity'),
      );
      await expectLater(g.shareExport('/x/$fileName'), throwsStateError);
    });
  });

  group('FileSelectorBackupFilePicker', () {
    XFile file(Uint8List bytes, {String name = 'meine-sicherung.json'}) =>
        XFile.fromData(bytes, path: '/downloads/$name', length: bytes.length);

    test('returns the bytes and the name of the chosen file', () async {
      final picker = FileSelectorBackupFilePicker(
        cacheDirectory: () async => cache,
        openFile: (groups) async => file(bytesOf('{"a":1}')),
      );
      final picked = await picker.pickBackupFile();
      expect(picked!.name, 'meine-sicherung.json');
      expect(picked.bytes, bytesOf('{"a":1}'));
    });

    group('the picker copy of the chosen document', () {
      const copyFolder = '123e4567-e89b-42d3-a456-426614174000';

      File writeFile(Directory directory, String relative, String content) {
        final file = File('${directory.path}${Platform.pathSeparator}$relative')
          ..createSync(recursive: true);
        file.writeAsStringSync(content);
        return file;
      }

      FileSelectorBackupFilePicker pickerFor(File file) =>
          FileSelectorBackupFilePicker(
            openFile: (groups) async => XFile(file.path),
            cacheDirectory: () async => cache,
          );

      test(
        'is removed from the cache as soon as the bytes were read (the backup '
        'must not stay behind unencrypted)',
        () async {
          final copy = writeFile(
            cache,
            '$copyFolder${Platform.pathSeparator}meine-sicherung.json',
            '{"a":1}',
          );
          final picked = await pickerFor(copy).pickBackupFile();
          expect(picked!.bytes, bytesOf('{"a":1}'));
          expect(copy.existsSync(), isFalse);
          expect(copy.parent.existsSync(), isFalse);
        },
      );

      test(
        'is removed after an oversized file was read up to the limit',
        () async {
          final copy = writeFile(
            cache,
            '$copyFolder${Platform.pathSeparator}gross.json',
            '0123456789',
          );
          final picked = await pickerFor(copy).pickBackupFile(maxBytes: 4);
          expect(picked!.bytes, hasLength(5));
          expect(copy.parent.existsSync(), isFalse);
        },
      );

      test(
        'a file outside the cache is never touched (desktop platforms return '
        'the user\'s own file)',
        () async {
          final other = await Directory.systemTemp.createTemp('picked_other');
          addTearDown(() async {
            if (await other.exists()) {
              await other.delete(recursive: true);
            }
          });
          final own = writeFile(
            other,
            '$copyFolder${Platform.pathSeparator}meine-sicherung.json',
            '{}',
          );
          await pickerFor(own).pickBackupFile();
          expect(own.existsSync(), isTrue);
        },
      );

      test(
        'a file in the cache that is not in a copy folder is never touched',
        () async {
          final loose = writeFile(cache, 'loose.json', '{}');
          final named = writeFile(
            cache,
            'notes${Platform.pathSeparator}b.json',
            '{}',
          );
          await pickerFor(loose).pickBackupFile();
          await pickerFor(named).pickBackupFile();
          expect(loose.existsSync(), isTrue);
          expect(named.existsSync(), isTrue);
        },
      );
    });

    test('returns null when the user cancels', () async {
      final picker = FileSelectorBackupFilePicker(
        cacheDirectory: () async => cache,
        openFile: (groups) async => null,
      );
      expect(await picker.pickBackupFile(), isNull);
    });

    test(
      'offers JSON files (and the type labels some providers use)',
      () async {
        List<XTypeGroup>? offered;
        final picker = FileSelectorBackupFilePicker(
          cacheDirectory: () async => cache,
          openFile: (groups) async {
            offered = groups;
            return null;
          },
        );
        await picker.pickBackupFile();
        final group = offered!.single;
        expect(group.extensions, ['json']);
        expect(group.mimeTypes, contains('application/json'));
        expect(group.uniformTypeIdentifiers, ['public.json']);
      },
    );

    test('a file at the limit is read completely', () async {
      final content = Uint8List.fromList(List.generate(100, (i) => i));
      final picker = FileSelectorBackupFilePicker(
        cacheDirectory: () async => cache,
        openFile: (groups) async => file(content),
      );
      final picked = await picker.pickBackupFile(maxBytes: 100);
      expect(picked!.bytes, content);
    });

    test(
      'a larger file is cut after limit + 1 bytes, enough to be rejected',
      () async {
        final content = Uint8List.fromList(List.generate(1000, (i) => i % 251));
        final picker = FileSelectorBackupFilePicker(
          cacheDirectory: () async => cache,
          openFile: (groups) async => file(content),
        );
        final picked = await picker.pickBackupFile(maxBytes: 100);
        expect(picked!.bytes, hasLength(101));
        expect(picked.bytes, content.sublist(0, 101));
      },
    );

    test(
      'with the real limit an oversized file still fails validation',
      () async {
        final huge = Uint8List(BackupFormat.maxFileBytes + 5000);
        final picker = FileSelectorBackupFilePicker(
          cacheDirectory: () async => cache,
          openFile: (groups) async => file(huge),
        );
        final picked = await picker.pickBackupFile();
        expect(picked!.bytes, hasLength(BackupFormat.maxFileBytes + 1));
        final result = const BackupValidator().validateBytes(picked.bytes);
        expect(result.isValid, isFalse);
        expect(result.report.problems.single.message, contains('10 MiB'));
      },
    );
  });

  group('in-memory fakes (used by the UI tests)', () {
    test('the gateway keeps files, records sharing and cleaning', () async {
      final gateway = InMemoryBackupFileGateway();
      final path = await gateway.writeTemporaryExport(
        fileName: fileName,
        bytes: bytesOf('x'),
      );
      expect(gateway.files.keys, [path]);
      expect(await gateway.shareExport(path), BackupShareStatus.shared);
      expect(gateway.sharedPaths, [path]);
      expect(gateway.fileExistedWhileSharing, [true]);
      await gateway.deleteTemporaryExports(includePlatformShareCopies: true);
      expect(gateway.files, isEmpty);
      expect(gateway.deleteCalls, [true]);
    });

    test('the gateway rejects bad names and can be told to fail', () async {
      final gateway = InMemoryBackupFileGateway();
      await expectLater(
        gateway.writeTemporaryExport(
          fileName: '../x.json',
          bytes: bytesOf('x'),
        ),
        throwsArgumentError,
      );
      gateway
        ..writeFailure = StateError('a')
        ..shareFailure = StateError('b')
        ..deleteFailure = StateError('c');
      await expectLater(
        gateway.writeTemporaryExport(fileName: fileName, bytes: bytesOf('x')),
        throwsStateError,
      );
      await expectLater(gateway.shareExport('/p'), throwsStateError);
      await expectLater(gateway.deleteTemporaryExports(), throwsStateError);
    });

    test(
      'the picker returns its prepared file and records the limit',
      () async {
        final picker = FakeBackupFilePicker(
          next: PickedBackupFile(name: 'a.json', bytes: bytesOf('{}')),
        );
        final picked = await picker.pickBackupFile(maxBytes: 7);
        expect(picked!.name, 'a.json');
        expect(picker.requestedLimits, [7]);
        picker.next = null;
        expect(await picker.pickBackupFile(), isNull);
        picker.failure = StateError('no picker');
        await expectLater(picker.pickBackupFile(), throwsStateError);
      },
    );
  });
}
