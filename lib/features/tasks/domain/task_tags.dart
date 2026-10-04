/// Pure tag rules of a task (up to five tags, 1 to 20 characters each, trimmed,
/// deduplicated case-insensitively with the first spelling kept).
library;

import 'package:self_improvement/features/tasks/domain/text_rules.dart';

/// Maximum number of tags of one task.
const int maxTagsPerTask = 5;

/// Maximum length of one tag in characters.
const int maxTagLength = 20;

/// Comparison key of a tag: case-insensitive, diacritics as typed.
String tagKey(String tag) => tag.trim().toLowerCase();

/// Trims every tag, drops blanks and removes case-insensitive duplicates while
/// keeping the first spelling and the original order. Does NOT enforce the
/// count or length limits (validation reports those).
List<String> normalizeTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in tags) {
    final tag = raw.trim();
    if (tag.isEmpty) {
      continue;
    }
    if (seen.add(tagKey(tag))) {
      result.add(tag);
    }
  }
  return List.unmodifiable(result);
}

/// Why a tag could not be added to a task.
enum TagAddResult {
  /// The tag was added.
  added,

  /// Nothing (or only blanks) was entered.
  empty,

  /// Longer than 20 characters after trimming.
  tooLong,

  /// The list already has a tag with the same text (case-insensitive).
  duplicate,

  /// Five tags exist already.
  limitReached;

  /// German hint for the tag input, or null when the tag was added.
  String? get message => switch (this) {
    TagAddResult.added => null,
    TagAddResult.empty => 'Bitte gib ein Tag ein.',
    TagAddResult.tooLong =>
      'Ein Tag darf höchstens $maxTagLength Zeichen lang sein.',
    TagAddResult.duplicate => 'Dieses Tag gibt es schon.',
    TagAddResult.limitReached =>
      'Du kannst höchstens $maxTagsPerTask Tags vergeben.',
  };
}

/// The result of [addTagToList]: what happened and the resulting tags.
typedef TagAddition = ({TagAddResult result, List<String> tags});

/// Tries to add [raw] to [tags]. The returned list equals [tags] unless the
/// result is [TagAddResult.added]. The order of the checks decides which hint
/// wins: blank, too long, duplicate, then the limit (a duplicate of an existing
/// tag is reported as duplicate even when five tags exist).
TagAddition addTagToList(List<String> tags, String raw) {
  final tag = raw.trim();
  if (tag.isEmpty) {
    return (result: TagAddResult.empty, tags: tags);
  }
  if (characterCount(tag) > maxTagLength) {
    return (result: TagAddResult.tooLong, tags: tags);
  }
  final key = tagKey(tag);
  if (tags.any((existing) => tagKey(existing) == key)) {
    return (result: TagAddResult.duplicate, tags: tags);
  }
  if (tags.length >= maxTagsPerTask) {
    return (result: TagAddResult.limitReached, tags: tags);
  }
  return (result: TagAddResult.added, tags: List.unmodifiable([...tags, tag]));
}

/// Removes the tag that equals [tag] case-insensitively; unchanged when absent.
List<String> removeTagFromList(List<String> tags, String tag) {
  final key = tagKey(tag);
  return List.unmodifiable([
    for (final existing in tags)
      if (tagKey(existing) != key) existing,
  ]);
}
