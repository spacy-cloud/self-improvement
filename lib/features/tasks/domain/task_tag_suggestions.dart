/// Tag suggestions for the task form: the tags other tasks already use.
library;

import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';

/// How many suggestions the task form offers at most.
const int maxTagSuggestions = 6;

/// The tags that existing [tasks] use and that are not in [selected] yet:
/// the most used first, ties alphabetical (case-insensitive). The spelling of
/// the first task that uses a tag is kept. Never more than [limit].
List<String> suggestTags(
  Iterable<Task> tasks,
  Iterable<String> selected, {
  int limit = maxTagSuggestions,
}) {
  final skip = {for (final tag in selected) tagKey(tag)};
  final spelling = <String, String>{};
  final counts = <String, int>{};
  for (final task in tasks) {
    for (final tag in normalizeTags(task.tags)) {
      final key = tagKey(tag);
      if (skip.contains(key)) {
        continue;
      }
      spelling.putIfAbsent(key, () => tag);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return List.unmodifiable([
    for (final key in keys.take(limit)) spelling[key]!,
  ]);
}
