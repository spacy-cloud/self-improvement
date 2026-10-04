import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';

/// The six habit symbols of the Figma icon picker. [key] is the value stored
/// as `icon_key`. Each symbol is coupled to an accent role of the design
/// tokens, so there is never a free hex colour in the data.
enum HabitIcon {
  /// Book, accent habits (purple). Default.
  book('book', Icons.menu_book_rounded, AppAccent.habits),

  /// Moon, accent focus (indigo).
  moon('moon', Icons.bedtime_rounded, AppAccent.focus),

  /// Drop, accent water (blue).
  drop('drop', Icons.water_drop_rounded, AppAccent.water),

  /// Check mark, accent primary (green).
  check('check', Icons.check_rounded, AppAccent.primary),

  /// Flame, accent workout (orange).
  flame('flame', Icons.local_fire_department_rounded, AppAccent.workout),

  /// Heart, accent error (red).
  heart('heart', Icons.favorite_rounded, AppAccent.error);

  const HabitIcon(this.key, this.icon, this.accent);

  /// Stable persisted identifier (`icon_key`).
  final String key;

  /// Material glyph.
  final IconData icon;

  /// Accent role that colours the icon, its tile and its selection border.
  final AppAccent accent;

  /// Default symbol for new habits.
  static const HabitIcon defaultIcon = HabitIcon.book;

  /// The symbol for a persisted [key], or `null` when the key is unknown.
  static HabitIcon? tryParse(String? key) {
    if (key == null) {
      return null;
    }
    for (final icon in values) {
      if (icon.key == key) {
        return icon;
      }
    }
    return null;
  }
}
