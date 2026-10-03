import 'package:flutter/material.dart';

/// Logical icon keys of the app. The glyphs are Flutter's built-in Material
/// icons, used as the equivalent of the Figma icons (see the table
/// "Icon-Zuordnung" in `docs/design-handoff.md`).
///
/// Use `AppIcons.of(AppIcon.home)` or the shortcut `AppIcon.home.data`.
enum AppIcon {
  /// Navigation: Home tab (selected variant is filled).
  home(Icons.home_outlined, filled: Icons.home_rounded),

  /// Navigation: Analyse tab (magnifier in Figma).
  analysis(Icons.search_rounded),

  /// Navigation: Habits tab.
  habits(Icons.checklist_rounded),

  /// Navigation: Profil tab (selected variant is filled).
  profile(Icons.person_outline_rounded, filled: Icons.person_rounded),

  /// Plus button.
  plus(Icons.add_rounded),

  /// Close (X).
  close(Icons.close_rounded),

  /// Back (chevron left).
  back(Icons.chevron_left_rounded),

  /// Chevron right (list rows with navigation).
  chevronRight(Icons.chevron_right_rounded),

  /// Expand (chevron down).
  expand(Icons.expand_more_rounded),

  /// Collapse (chevron up).
  collapse(Icons.expand_less_rounded),

  /// Weight (scale).
  weight(Icons.monitor_weight_outlined),

  /// Steps (sneaker in Figma).
  steps(Icons.directions_walk_rounded),

  /// Water (drop).
  water(Icons.water_drop_outlined),

  /// Meal (fork and knife).
  meal(Icons.restaurant_rounded),

  /// Workout (dumbbell).
  workout(Icons.fitness_center_rounded),

  /// Focus (clock face in Figma).
  focus(Icons.schedule_rounded),

  /// Clock (measurement time).
  clock(Icons.schedule_rounded),

  /// Task (checked square).
  task(Icons.check_box_outlined),

  /// Habit (checklist).
  habit(Icons.checklist_rounded),

  /// Streak (flame).
  streak(Icons.local_fire_department_rounded),

  /// Flame.
  flame(Icons.local_fire_department_rounded),

  /// Trophy / badge.
  trophy(Icons.emoji_events_outlined),

  /// Settings.
  settings(Icons.settings_outlined),

  /// Delete (trash).
  delete(Icons.delete_outline_rounded),

  /// Edit.
  edit(Icons.edit_outlined),

  /// Check mark.
  check(Icons.check_rounded),

  /// Information.
  info(Icons.info_outline_rounded),

  /// Local only (lock).
  lock(Icons.lock_outline_rounded),

  /// Hint or tip (light bulb).
  hint(Icons.lightbulb_outline_rounded),

  /// Validation or save error.
  error(Icons.error_outline_rounded),

  /// Load error (cloud with exclamation in Figma).
  cloudOff(Icons.cloud_off_rounded),

  /// Retry (circular arrow).
  retry(Icons.refresh_rounded),

  /// Empty state (sprout in Figma).
  sprout(Icons.eco_outlined),

  /// Appearance setting (half circle).
  theme(Icons.contrast_rounded),

  /// Reduced motion setting.
  reducedMotion(Icons.motion_photos_off_outlined),

  /// Haptic feedback setting.
  haptics(Icons.vibration_rounded),

  /// Reminders (bell).
  reminder(Icons.notifications_none_rounded),

  /// Manage modules (four squares).
  modules(Icons.grid_view_rounded),

  /// Export data (arrow up).
  export(Icons.file_upload_outlined),

  /// Import data (arrow down).
  import(Icons.file_download_outlined),

  /// Reset all data (counter-clockwise arrow).
  reset(Icons.restart_alt_rounded),

  /// Licences (document).
  licenses(Icons.description_outlined);

  const AppIcon(this.data, {this.filled});

  /// The glyph.
  final IconData data;

  /// Filled variant used for a selected tab, where Material has one.
  final IconData? filled;

  /// The glyph for a selected tab (filled where Material has a filled glyph,
  /// otherwise the same as [data]).
  IconData get selectedData => filled ?? data;
}

/// Lookup of the icon glyphs.
abstract final class AppIcons {
  /// Glyph of [icon]; [selected] picks the filled variant where there is one.
  static IconData of(AppIcon icon, {bool selected = false}) {
    return selected ? icon.selectedData : icon.data;
  }
}
