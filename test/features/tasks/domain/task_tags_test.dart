import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';
import 'package:self_improvement/features/tasks/domain/text_rules.dart';

import '../support/task_test_support.dart';

void main() {
  group('normalizeTags', () {
    test('trims, drops blanks, keeps the order and the first spelling', () {
      expect(
        normalizeTags([
          ' Büro ',
          '',
          'büro',
          'Zuhause',
          ' ',
          'ZUHAUSE',
          'Sport',
        ]),
        ['Büro', 'Zuhause', 'Sport'],
      );
    });

    test('does not enforce the count or the length (validation does)', () {
      final many = [for (var i = 0; i < 8; i++) 'tag$i'];
      expect(normalizeTags(many), many);
      expect(normalizeTags(['x' * 30]), ['x' * 30]);
    });

    test('the result cannot be modified by the caller', () {
      final result = normalizeTags(['a']);
      expect(() => result.add('b'), throwsUnsupportedError);
    });
  });

  group('addTagToList', () {
    test('adds a trimmed tag at the end', () {
      final added = addTagToList(['a'], '  b  ');
      expect(added.result, TagAddResult.added);
      expect(added.tags, ['a', 'b']);
      expect(added.result.message, isNull);
    });

    test('a blank input is rejected and changes nothing', () {
      for (final raw in ['', ' ', '\t']) {
        final added = addTagToList(['a'], raw);
        expect(added.result, TagAddResult.empty, reason: '"$raw"');
        expect(added.tags, ['a']);
      }
      expect(TagAddResult.empty.message, 'Bitte gib ein Tag ein.');
    });

    test('20 characters are fine, 21 are too long', () {
      expect(addTagToList([], 't' * 20).result, TagAddResult.added);
      final tooLong = addTagToList([], 't' * 21);
      expect(tooLong.result, TagAddResult.tooLong);
      expect(tooLong.tags, isEmpty);
      expect(
        TagAddResult.tooLong.message,
        'Ein Tag darf höchstens 20 Zeichen lang sein.',
      );
    });

    test('the length is measured after trimming', () {
      expect(addTagToList([], '  ${'t' * 20}  ').result, TagAddResult.added);
    });

    test('a duplicate is rejected case-insensitively', () {
      final duplicate = addTagToList(['Haushalt'], ' haushalt ');
      expect(duplicate.result, TagAddResult.duplicate);
      expect(duplicate.tags, ['Haushalt'], reason: 'first spelling kept');
      expect(TagAddResult.duplicate.message, 'Dieses Tag gibt es schon.');
    });

    test('the sixth tag is rejected, the fifth is accepted', () {
      final four = ['a', 'b', 'c', 'd'];
      final fifth = addTagToList(four, 'e');
      expect(fifth.result, TagAddResult.added);
      expect(fifth.tags, hasLength(5));
      final sixth = addTagToList(fifth.tags, 'f');
      expect(sixth.result, TagAddResult.limitReached);
      expect(sixth.tags, hasLength(5));
      expect(
        TagAddResult.limitReached.message,
        'Du kannst höchstens 5 Tags vergeben.',
      );
    });

    test('a duplicate is reported as duplicate even when the list is full', () {
      final full = ['a', 'b', 'c', 'd', 'e'];
      expect(addTagToList(full, 'A').result, TagAddResult.duplicate);
    });

    test('the returned list is a new unmodifiable list', () {
      final original = <String>['a'];
      final added = addTagToList(original, 'b');
      expect(original, ['a']);
      expect(() => added.tags.add('c'), throwsUnsupportedError);
    });
  });

  group('removeTagFromList', () {
    test('removes case-insensitively and keeps the others in order', () {
      expect(removeTagFromList(['a', 'B', 'c'], 'b'), ['a', 'c']);
    });

    test('an unknown tag leaves the list unchanged', () {
      expect(removeTagFromList(['a'], 'z'), ['a']);
    });
  });

  test('characterCount counts code points like SQLite length()', () {
    expect(characterCount('abc'), 3);
    expect(characterCount('äöü'), 3);
    expect(characterCount(astralChar), 1);
    expect(astralChar.length, 2, reason: 'two UTF-16 code units');
    expect(characterCount(''), 0);
  });
}
