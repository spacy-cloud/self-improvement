/// Text length rule shared by the task and habit validation.
library;

/// Number of characters of [text] as SQLite's `length()` counts them (Unicode
/// code points, not UTF-16 code units).
///
/// The database `CHECK` constraints on titles and descriptions use SQLite's
/// `length()`; counting the same way guarantees that a value which passes the
/// validation can never violate a constraint, and an emoji counts as ONE
/// character for the user-facing limits.
int characterCount(String text) => text.runes.length;
