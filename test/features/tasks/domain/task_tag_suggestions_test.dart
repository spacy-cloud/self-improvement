import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/task_tag_suggestions.dart';

import '../support/task_test_support.dart';

void main() {
  test('suggests the tags of existing tasks, most used first', () {
    final tasks = [
      makeTask(id: 'a', tags: ['Schule', 'Privat']),
      makeTask(id: 'b', tags: ['Schule']),
      makeTask(id: 'c', tags: ['Arbeit']),
    ];
    expect(suggestTags(tasks, const []), ['Schule', 'Arbeit', 'Privat']);
  });

  test(
    'ties are alphabetical and case-insensitive, the first spelling stays',
    () {
      final tasks = [
        makeTask(id: 'a', tags: ['büro']),
        makeTask(id: 'b', tags: ['Büro', 'Auto']),
        makeTask(id: 'c', tags: ['zuhause']),
      ];
      expect(suggestTags(tasks, const []), ['büro', 'Auto', 'zuhause']);
    },
  );

  test('leaves out the tags that are already selected, ignoring case', () {
    final tasks = [
      makeTask(id: 'a', tags: ['Schule', 'Privat']),
    ];
    expect(suggestTags(tasks, ['schule']), ['Privat']);
    expect(suggestTags(tasks, ['SCHULE', 'privat']), isEmpty);
  });

  test('offers at most the limit and nothing without tags', () {
    final tasks = [
      makeTask(id: 'a', tags: ['a', 'b', 'c', 'd', 'e']),
      makeTask(id: 'b', tags: ['f', 'g', 'h']),
    ];
    expect(suggestTags(tasks, const []), hasLength(maxTagSuggestions));
    expect(suggestTags(tasks, const [], limit: 2), ['a', 'b']);
    expect(suggestTags(const [], const []), isEmpty);
    expect(suggestTags([makeTask()], const []), isEmpty);
  });
}
