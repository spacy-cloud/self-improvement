import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  /// Runs the validation and returns the field errors (empty when valid).
  Map<String, String> errorsOf(TaskDraft draft) {
    try {
      validateTaskDraft(draft);
      return const {};
    } on ValidationFailure catch (failure) {
      return failure.fieldErrors;
    }
  }

  group('title (1 to 120 characters after trimming)', () {
    test('an empty or blank title is rejected with a hint', () {
      for (final title in ['', ' ', '   \t ']) {
        expect(errorsOf(TaskDraft(title: title)), {
          TaskFields.title: 'Bitte gib einen Titel ein.',
        }, reason: '"$title"');
      }
    });

    test('1 and 120 characters are accepted, 121 is rejected', () {
      expect(errorsOf(TaskDraft(title: 'a')), isEmpty);
      expect(errorsOf(TaskDraft(title: 'a' * 120)), isEmpty);
      expect(errorsOf(TaskDraft(title: 'a' * 121)), {
        TaskFields.title: 'Der Titel darf höchstens 120 Zeichen lang sein.',
      });
    });

    test('surrounding spaces do not count and are removed', () {
      final result = validateTaskDraft(TaskDraft(title: '  ${'a' * 120}  '));
      expect(result.title, 'a' * 120);
      expect(errorsOf(TaskDraft(title: '${'a' * 121} ')), isNotEmpty);
    });

    test('characters are counted like the database does (code points)', () {
      // One emoji is one character for the user and for SQLite length().
      expect(errorsOf(TaskDraft(title: '😀' * 120)), isEmpty);
      expect(errorsOf(TaskDraft(title: '😀' * 121)), isNotEmpty);
      expect(errorsOf(TaskDraft(title: 'ä' * 120)), isEmpty);
    });
  });

  group('description (optional, at most 1.000 characters)', () {
    test('null, empty and blank become no description', () {
      for (final description in [null, '', '   ', '\n']) {
        expect(
          validateTaskDraft(TaskDraft(title: 'x', description: description))
              .description,
          isNull,
          reason: '"$description"',
        );
      }
    });

    test('1000 characters are accepted, 1001 are rejected', () {
      expect(errorsOf(TaskDraft(title: 'x', description: 'd' * 1000)), isEmpty);
      expect(errorsOf(TaskDraft(title: 'x', description: 'd' * 1001)), {
        TaskFields.description:
            'Die Beschreibung darf höchstens 1.000 Zeichen lang sein.',
      });
    });

    test('the description is trimmed before counting', () {
      final result = validateTaskDraft(
        TaskDraft(title: 'x', description: '  ${'d' * 1000}  '),
      );
      expect(result.description, 'd' * 1000);
    });
  });

  group('tags (up to five, 1 to 20 characters, deduplicated)', () {
    test('no tags is the default', () {
      expect(validateTaskDraft(TaskDraft(title: 'x')).tags, isEmpty);
    });

    test('five tags are accepted, six are rejected', () {
      final five = ['a', 'b', 'c', 'd', 'e'];
      expect(errorsOf(TaskDraft(title: 'x', tags: five)), isEmpty);
      expect(errorsOf(TaskDraft(title: 'x', tags: [...five, 'f'])), {
        TaskFields.tags: 'Du kannst höchstens 5 Tags vergeben.',
      });
    });

    test('a tag of 20 characters is accepted, 21 is rejected', () {
      expect(errorsOf(TaskDraft(title: 'x', tags: ['t' * 20])), isEmpty);
      expect(errorsOf(TaskDraft(title: 'x', tags: ['t' * 21])), {
        TaskFields.tags: 'Ein Tag darf höchstens 20 Zeichen lang sein.',
      });
    });

    test('tags are trimmed before counting', () {
      final result = validateTaskDraft(
        TaskDraft(title: 'x', tags: ['  ${'t' * 20}  ']),
      );
      expect(result.tags, ['t' * 20]);
    });

    test('duplicates are removed case-insensitively, first spelling wins', () {
      final result = validateTaskDraft(
        TaskDraft(
          title: 'x',
          tags: ['Haushalt', 'haushalt', ' HAUSHALT ', 'Arbeit', 'arbeit'],
        ),
      );
      expect(result.tags, ['Haushalt', 'Arbeit']);
    });

    test('six tags with one duplicate are five tags and valid', () {
      final result = validateTaskDraft(
        TaskDraft(title: 'x', tags: ['a', 'b', 'c', 'd', 'e', 'A']),
      );
      expect(result.tags, ['a', 'b', 'c', 'd', 'e']);
    });

    test('blank tags are dropped and never count', () {
      final result = validateTaskDraft(
        TaskDraft(title: 'x', tags: ['', ' ', 'a', '  ']),
      );
      expect(result.tags, ['a']);
    });

    test('umlaut case is folded, other diacritics stay as typed', () {
      final folded = validateTaskDraft(
        TaskDraft(title: 'x', tags: ['Ärger', 'ärger']),
      );
      expect(folded.tags, ['Ärger']);
      final distinct = validateTaskDraft(
        TaskDraft(title: 'x', tags: ['uber', 'über']),
      );
      expect(distinct.tags, ['uber', 'über']);
    });
  });

  group('other fields and the normalised result', () {
    test('priority defaults to normal and there is no due date by default', () {
      final result = validateTaskDraft(TaskDraft(title: 'x'));
      expect(result.priority, TaskPriority.normal);
      expect(result.dueDate, isNull);
    });

    test('any due day is valid, including one in the past', () {
      final past = LocalDate(2020, 2, 29);
      expect(
        validateTaskDraft(TaskDraft(title: 'x', dueDate: past)).dueDate,
        past,
      );
    });

    test('all errors are reported at once', () {
      final errors = errorsOf(
        TaskDraft(
          title: '',
          description: 'd' * 1001,
          tags: ['a', 'b', 'c', 'd', 'e', 'f'],
        ),
      );
      expect(errors.keys, {
        TaskFields.title,
        TaskFields.description,
        TaskFields.tags,
      });
    });

    test('the normalised draft keeps the user content otherwise unchanged', () {
      final result = validateTaskDraft(
        TaskDraft(
          title: '  Steuer machen ',
          description: ' Belege sammeln ',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 15),
          tags: ['Finanzen'],
        ),
      );
      expect(result.title, 'Steuer machen');
      expect(result.description, 'Belege sammeln');
      expect(result.priority, TaskPriority.high);
      expect(result.dueDate, LocalDate(2026, 10, 15));
      expect(result.tags, ['Finanzen']);
    });
  });

  group('priority enum', () {
    test('keys equal the database contract', () {
      expect(
        TaskPriority.values.map((p) => p.key).toList(),
        SchemaKeys.taskPriorities,
      );
    });

    test('ranks order low < normal < high and unknown keys are rejected', () {
      expect(TaskPriority.low.rank, lessThan(TaskPriority.normal.rank));
      expect(TaskPriority.normal.rank, lessThan(TaskPriority.high.rank));
      expect(TaskPriority.tryParse('high'), TaskPriority.high);
      expect(TaskPriority.tryParse('urgent'), isNull);
      expect(TaskPriority.tryParse(''), isNull);
    });

    test('German labels', () {
      expect(TaskPriority.values.map((p) => p.label).toList(), [
        'Niedrig',
        'Normal',
        'Hoch',
      ]);
    });
  });
}
