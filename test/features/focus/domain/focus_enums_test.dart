import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';

void main() {
  group('FocusCategory', () {
    test('the keys equal the persisted schema contract, in the same order', () {
      expect(
        FocusCategory.values.map((c) => c.key).toList(),
        SchemaKeys.focusCategories,
      );
    });

    test('the German labels are the five fixed categories', () {
      expect(
        {for (final c in FocusCategory.values) c.key: c.label},
        {
          'reading': 'Lesen',
          'learning': 'Lernen',
          'programming': 'Programmieren',
          'meditation': 'Meditation',
          'other': 'Sonstiges',
        },
      );
    });

    test('parsing accepts the keys only', () {
      for (final category in FocusCategory.values) {
        expect(FocusCategory.tryParse(category.key), category);
        expect(FocusCategory.fromKey(category.key), category);
      }
      expect(FocusCategory.tryParse('work'), isNull, reason: 'old design name');
      expect(FocusCategory.tryParse('Reading'), isNull, reason: 'case matters');
      expect(FocusCategory.tryParse(''), isNull);
      expect(() => FocusCategory.fromKey('arbeit'), throwsArgumentError);
    });
  });

  group('FocusStatus', () {
    test('the keys equal the persisted schema contract, in the same order', () {
      expect(
        FocusStatus.values.map((s) => s.key).toList(),
        SchemaKeys.focusStatuses,
      );
    });

    test('exactly the three open states occupy the single open slot', () {
      expect(
        FocusStatus.values.where((s) => s.isOpen).map((s) => s.key).toList(),
        SchemaKeys.focusOpenStatuses,
      );
      expect(FocusStatus.completed.isOpen, isFalse);
      expect(FocusStatus.discarded.isOpen, isFalse);
    });

    test('parsing accepts the keys only', () {
      for (final status in FocusStatus.values) {
        expect(FocusStatus.tryParse(status.key), status);
      }
      expect(FocusStatus.tryParse('awaitingConfirmation'), isNull);
      expect(FocusStatus.tryParse('aborted'), isNull);
      expect(() => FocusStatus.fromKey('aborted'), throwsArgumentError);
    });
  });
}
