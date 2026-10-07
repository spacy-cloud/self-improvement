import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the interface to the health data of the phone must never offer
/// (BS-97): it reads, it aggregates, and it asks nothing else.
void main() {
  final source = File('lib/core/health/domain/health_steps_source.dart')
      .readAsStringSync();

  /// The members of `abstract interface class HealthStepsSource`.
  List<String> members() {
    final start = source.indexOf('abstract interface class HealthStepsSource');
    final body = source.substring(start);
    final names = <String>[];
    for (final line in body.split('\n')) {
      final text = line.trim();
      if (text.startsWith('///') || text.startsWith('//')) {
        continue;
      }
      final match = RegExp(r'^(?:Future<[^>]*>|String)\s+(?:get\s+)?(\w+)')
          .firstMatch(text);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }
    return names;
  }

  test('the interface has exactly the seven members of the contract '
      '(BS-97)', () {
    expect(members(), [
      'displayName',
      'availability',
      'access',
      'requestAccess',
      'totalSteps',
      'openInstallPage',
      'openAccessSettings',
    ]);
  });

  test('no member writes, deletes or reads single records (BS-97)', () {
    for (final name in members()) {
      expect(
        name,
        isNot(
          matches(
            RegExp(
              r'write|insert|delete|remove|update|record|sample',
              caseSensitive: false,
            ),
          ),
        ),
        reason: name,
      );
    }
  });

  test('the only data call is an aggregation of a time range (BS-97)', () {
    final flat = source.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat,
      contains(
        'Future<int?> totalSteps({ required DateTime startUtc, required '
        'DateTime endUtc, });',
      ),
    );
    // Only steps: no other data kind is named in the contract.
    for (final other in [
      'heart',
      'sleep',
      'weight',
      'calories',
      'distance',
      'blood',
    ]) {
      expect(source.toLowerCase(), isNot(contains(other)), reason: other);
    }
  });

  test('only the platform adapter folder may know a platform channel '
      '(BS-97)', () {
    final offenders = <String>[];
    for (final root in [
      'lib/core/health/domain',
      'lib/features/body/steps/application',
      'lib/features/body/steps/data',
      'lib/features/body/steps/domain',
    ]) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        for (final line in entity.readAsLinesSync()) {
          final isImport = line.trimLeft().startsWith('import ');
          if (isImport &&
              (line.contains('package:flutter/services.dart') ||
                  line.contains('package:health/'))) {
            offenders.add('${entity.path}: $line');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
