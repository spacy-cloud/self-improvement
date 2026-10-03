import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// Accent roles used for module and habit colours.
///
/// An accent never carries a free hex value: it only selects one of the colour
/// roles of [AppColors] (see [AppColors.accent], [AppColors.accentFill] and
/// [AppColors.accentTint]).
enum AppAccent {
  /// Brand green (accent fill, button green and green text are separate roles).
  primary,

  /// Weight / body module.
  weight,

  /// Water.
  water,

  /// Steps.
  steps,

  /// Workouts.
  workout,

  /// Focus timer.
  focus,

  /// Habits and tasks.
  habits,

  /// Nutrition / meals.
  nutrition,

  /// XP, level and badges.
  gamification,

  /// Streak flame.
  streak,

  /// Used for the habit icon `heart` (Figma uses error and error-tint there).
  error;

  /// The accent that represents a functional [module].
  static AppAccent forModule(ModuleId module) {
    return switch (module) {
      ModuleId.body => AppAccent.weight,
      ModuleId.nutrition => AppAccent.nutrition,
      ModuleId.focus => AppAccent.focus,
      ModuleId.tasks => AppAccent.habits,
      ModuleId.gamification => AppAccent.gamification,
    };
  }
}

/// Colour roles of one theme variant (Light, Dark or OLED).
///
/// The values mirror the Figma variable collection "App Tokens" (modes Light,
/// Dark, OLED, read on 2026-10-03). Deviations are documented in
/// `docs/design-handoff.md` section 8:
///
///XX
/// * Roles marked "not a Figma variable" come from hard-coded Figma values or
///   are derived and are listed in the same section.
///
/// Usage rules that keep the design accessible:
///
/// * [primary] is an accent *fill* (bars, rings, charts). Never put text on it.
/// * Buttons use [primaryButton] with [onPrimary] text.
/// * Green text and icons use [primaryText].
/// * Module colours for icons and text: [accent]; for chart fills: [accentFill].
@immutable
class AppColors {
  /// Creates a colour set. Prefer the constants [light], [dark] and [oled].
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.borderDecorative,
    required this.borderInput,
    required this.track,
    required this.primary,
    required this.primaryButton,
    required this.onPrimary,
    required this.primaryText,
    required this.primaryTint,
    required this.toggleOn,
    required this.error,
    required this.errorTint,
    required this.onError,
    required this.warningText,
    required this.warningTint,
    required this.moduleWeight,
    required this.moduleWater,
    required this.moduleWaterChart,
    required this.moduleSteps,
    required this.moduleWorkout,
    required this.moduleFocus,
    required this.moduleHabits,
    required this.moduleNutrition,
    required this.moduleGamification,
    required this.streak,
    required this.moduleGamificationText,
    required this.streakText,
    required this.tintWater,
    required this.tintSteps,
    required this.tintWorkout,
    required this.tintFocus,
    required this.tintHabits,
    required this.dayRing,
    required this.scrim,
    required this.shadow,
    required this.snackBarSurface,
    required this.snackBarErrorSurface,
    required this.onSnackBar,
    required this.snackBarAction,
    required this.snackBarErrorAction,
  });

  /// Figma `color/background`: page background.
  final Color background;

  /// Figma `color/surface`: cards, headers, sheets, navigation bar.
  final Color surface;

  /// Figma `color/surface-muted`: quiet secondary surface.
  final Color surfaceMuted;

  /// Figma `color/text-primary`.
  final Color textPrimary;

  /// Figma `color/text-secondary`.
  final Color textSecondary;

  /// Figma `color/text-tertiary`: disabled and quiet text.
  final Color textTertiary;

  /// Figma `color/border-decorative`: card and divider outlines (decorative).
  final Color borderDecorative;

  /// Figma `color/border-input`: input and control boundaries (>= 3:1).
  final Color borderInput;

  /// Figma `color/track`: progress tracks, segmented background, disabled fill.
  final Color track;

  /// Figma `color/primary`: accent fill (not for text, not for buttons).
  final Color primary;

  /// Figma `color/primary-button`: fill of primary buttons and checked boxes.
  ///
  /// Dark and OLED: corrected from the Figma value `#1F9D55` (white text 3.49:1,
  /// below 4.5:1) to `#1F8655` (4.57:1). Only the green channel changed.
  final Color primaryButton;

  /// Figma `color/on-primary`: text and icons on [primaryButton].
  final Color onPrimary;

  /// Figma `color/primary-text`: green text and icons.
  final Color primaryText;

  /// Figma `color/primary-tint`: selected background, icon tiles.
  final Color primaryTint;

  /// Figma `color/toggle-on`: track of a switched-on toggle.
  ///
  /// Dark and OLED: corrected from the Figma value `#2FCB6E` (white knob 2.12:1,
  /// below 3:1) to `#2FA26E` (3.22:1). Only the green channel changed.
  final Color toggleOn;

  /// Figma `color/error`: error text, borders and destructive actions.
  final Color error;

  /// Figma `color/error-tint`.
  final Color errorTint;

  /// Text and icons on a solid [error] fill. Not a Figma variable (derived).
  final Color onError;

  /// Figma `color/warning-text`.
  final Color warningText;

  /// Figma `color/warning-tint`.
  final Color warningTint;

  /// Figma `color/module/weight`.
  final Color moduleWeight;

  /// Figma `color/module/water`: water icons and text.
  final Color moduleWater;

  /// Figma `color/module/water-chart`: water bars and rings.
  final Color moduleWaterChart;

  /// Figma `color/module/steps`.
  final Color moduleSteps;

  /// Figma `color/module/workout`.
  final Color moduleWorkout;

  /// Figma `color/module/focus`.
  final Color moduleFocus;

  /// Figma `color/module/habits`.
  final Color moduleHabits;

  /// Figma `color/module/nutrition`.
  final Color moduleNutrition;

  /// Figma `color/module/gamification` (decorative fill; low contrast in Light).
  final Color moduleGamification;

  /// Figma `color/streak`: flame fill (decorative, never text).
  final Color streak;

  /// Legible variant of [moduleGamification] for text and icons.
  /// Not a Figma variable (derived: Light uses the nutrition amber).
  final Color moduleGamificationText;

  /// Legible variant of [streak] for text and icons.
  /// Not a Figma variable (derived: Light uses the workout orange).
  final Color streakText;

  /// Icon tile tint of the water accent. Not a Figma variable: Light is read
  /// from the Plus menu frame, Dark and OLED are derived (16 % accent on surface).
  final Color tintWater;

  /// Icon tile tint of the steps accent. See [tintWater].
  final Color tintSteps;

  /// Icon tile tint of the workout accent. See [tintWater].
  final Color tintWorkout;

  /// Icon tile tint of the focus accent. See [tintWater].
  final Color tintFocus;

  /// Icon tile tint of the habits accent. See [tintWater].
  final Color tintHabits;

  /// Arc colour of the day ring. Not a Figma variable: hard-coded `#E2D11E` in
  /// all Home frames. The ring always has a text alternative.
  final Color dayRing;

  /// Barrier colour behind modal sheets (Figma backdrop: black at 50 %).
  final Color scrim;

  /// Shadow colour of cards (Light 5 %, Dark and OLED 15 % black).
  final Color shadow;

  /// SnackBar surface (undo and success). Same in all modes (Figma has one).
  final Color snackBarSurface;

  /// SnackBar surface of the error variant.
  final Color snackBarErrorSurface;

  /// Text on SnackBars.
  final Color onSnackBar;

  /// Action text on undo SnackBars.
  final Color snackBarAction;

  /// Action text on error SnackBars.
  final Color snackBarErrorAction;

  /// Focus indicator colour for keyboard and switch access.
  Color get focus => primaryText;

  /// Colour for icons and text of an [accent] (>= 4.5:1 on surface/background).
  Color accent(AppAccent accent) {
    return switch (accent) {
      AppAccent.primary => primaryText,
      AppAccent.weight => moduleWeight,
      AppAccent.water => moduleWater,
      AppAccent.steps => moduleSteps,
      AppAccent.workout => moduleWorkout,
      AppAccent.focus => moduleFocus,
      AppAccent.habits => moduleHabits,
      AppAccent.nutrition => moduleNutrition,
      AppAccent.gamification => moduleGamificationText,
      AppAccent.streak => streakText,
      AppAccent.error => error,
    };
  }

  /// Fill colour for bars, rings and chart series of an [accent].
  /// Decorative: always paired with a text alternative, never used for text.
  Color accentFill(AppAccent accent) {
    return switch (accent) {
      AppAccent.primary || AppAccent.weight => primary,
      AppAccent.water => moduleWaterChart,
      AppAccent.steps => moduleSteps,
      AppAccent.workout => moduleWorkout,
      AppAccent.focus => moduleFocus,
      AppAccent.habits => moduleHabits,
      AppAccent.nutrition => moduleNutrition,
      AppAccent.gamification => moduleGamification,
      AppAccent.streak => streak,
      AppAccent.error => error,
    };
  }

  /// Tile or chip background behind an [accent] icon.
  Color accentTint(AppAccent accent) {
    return switch (accent) {
      AppAccent.primary || AppAccent.weight => primaryTint,
      AppAccent.water => tintWater,
      AppAccent.steps => tintSteps,
      AppAccent.workout || AppAccent.streak => tintWorkout,
      AppAccent.focus => tintFocus,
      AppAccent.habits => tintHabits,
      AppAccent.nutrition || AppAccent.gamification => warningTint,
      AppAccent.error => errorTint,
    };
  }

  /// All colours in declaration order (used for equality and tests).
  List<Color> get values => <Color>[
    background,
    surface,
    surfaceMuted,
    textPrimary,
    textSecondary,
    textTertiary,
    borderDecorative,
    borderInput,
    track,
    primary,
    primaryButton,
    onPrimary,
    primaryText,
    primaryTint,
    toggleOn,
    error,
    errorTint,
    onError,
    warningText,
    warningTint,
    moduleWeight,
    moduleWater,
    moduleWaterChart,
    moduleSteps,
    moduleWorkout,
    moduleFocus,
    moduleHabits,
    moduleNutrition,
    moduleGamification,
    streak,
    moduleGamificationText,
    streakText,
    tintWater,
    tintSteps,
    tintWorkout,
    tintFocus,
    tintHabits,
    dayRing,
    scrim,
    shadow,
    snackBarSurface,
    snackBarErrorSurface,
    onSnackBar,
    snackBarAction,
    snackBarErrorAction,
  ];

  /// Linear interpolation between two colour sets (animated theme changes).
  static AppColors lerp(AppColors a, AppColors b, double t) {
    Color mix(Color x, Color y) => Color.lerp(x, y, t) ?? y;
    return AppColors(
      background: mix(a.background, b.background),
      surface: mix(a.surface, b.surface),
      surfaceMuted: mix(a.surfaceMuted, b.surfaceMuted),
      textPrimary: mix(a.textPrimary, b.textPrimary),
      textSecondary: mix(a.textSecondary, b.textSecondary),
      textTertiary: mix(a.textTertiary, b.textTertiary),
      borderDecorative: mix(a.borderDecorative, b.borderDecorative),
      borderInput: mix(a.borderInput, b.borderInput),
      track: mix(a.track, b.track),
      primary: mix(a.primary, b.primary),
      primaryButton: mix(a.primaryButton, b.primaryButton),
      onPrimary: mix(a.onPrimary, b.onPrimary),
      primaryText: mix(a.primaryText, b.primaryText),
      primaryTint: mix(a.primaryTint, b.primaryTint),
      toggleOn: mix(a.toggleOn, b.toggleOn),
      error: mix(a.error, b.error),
      errorTint: mix(a.errorTint, b.errorTint),
      onError: mix(a.onError, b.onError),
      warningText: mix(a.warningText, b.warningText),
      warningTint: mix(a.warningTint, b.warningTint),
      moduleWeight: mix(a.moduleWeight, b.moduleWeight),
      moduleWater: mix(a.moduleWater, b.moduleWater),
      moduleWaterChart: mix(a.moduleWaterChart, b.moduleWaterChart),
      moduleSteps: mix(a.moduleSteps, b.moduleSteps),
      moduleWorkout: mix(a.moduleWorkout, b.moduleWorkout),
      moduleFocus: mix(a.moduleFocus, b.moduleFocus),
      moduleHabits: mix(a.moduleHabits, b.moduleHabits),
      moduleNutrition: mix(a.moduleNutrition, b.moduleNutrition),
      moduleGamification: mix(a.moduleGamification, b.moduleGamification),
      streak: mix(a.streak, b.streak),
      moduleGamificationText: mix(
        a.moduleGamificationText,
        b.moduleGamificationText,
      ),
      streakText: mix(a.streakText, b.streakText),
      tintWater: mix(a.tintWater, b.tintWater),
      tintSteps: mix(a.tintSteps, b.tintSteps),
      tintWorkout: mix(a.tintWorkout, b.tintWorkout),
      tintFocus: mix(a.tintFocus, b.tintFocus),
      tintHabits: mix(a.tintHabits, b.tintHabits),
      dayRing: mix(a.dayRing, b.dayRing),
      scrim: mix(a.scrim, b.scrim),
      shadow: mix(a.shadow, b.shadow),
      snackBarSurface: mix(a.snackBarSurface, b.snackBarSurface),
      snackBarErrorSurface: mix(a.snackBarErrorSurface, b.snackBarErrorSurface),
      onSnackBar: mix(a.onSnackBar, b.onSnackBar),
      snackBarAction: mix(a.snackBarAction, b.snackBarAction),
      snackBarErrorAction: mix(a.snackBarErrorAction, b.snackBarErrorAction),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AppColors) {
      return false;
    }
    final mine = values;
    final theirs = other.values;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);

  /// Light palette (Figma mode "Light").
  static const AppColors light = AppColors(
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF7F8FA),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF52555C),
    textTertiary: Color(0xFF5F636B),
    borderDecorative: Color(0xFFECECEC),
    borderInput: Color(0xFF8A8F98),
    track: Color(0xFFECEFF3),
    primary: Color(0xFF20B65C),
    primaryButton: Color(0xFF0E8540),
    onPrimary: Color(0xFFFFFFFF),
    primaryText: Color(0xFF087B3E),
    primaryTint: Color(0xFFE9F8EF),
    toggleOn: Color(0xFF13994C),
    error: Color(0xFFB42318),
    errorTint: Color(0xFFFDECEC),
    onError: Color(0xFFFFFFFF),
    warningText: Color(0xFF92400E),
    warningTint: Color(0xFFFFF7E6),
    moduleWeight: Color(0xFF0D7F3F),
    moduleWater: Color(0xFF1474C4),
    moduleWaterChart: Color(0xFF2E9FF7),
    moduleSteps: Color(0xFFC21FB7),
    moduleWorkout: Color(0xFFC2410C),
    moduleFocus: Color(0xFF4F5BD5),
    moduleHabits: Color(0xFF6A3FD0),
    moduleNutrition: Color(0xFFB45309),
    moduleGamification: Color(0xFFD97706),
    streak: Color(0xFFFF693F),
    moduleGamificationText: Color(0xFFB45309),
    streakText: Color(0xFFC2410C),
    tintWater: Color(0xFFE8F4FF),
    tintSteps: Color(0xFFFBEAFA),
    tintWorkout: Color(0xFFFFF3E8),
    tintFocus: Color(0xFFEEF0FD),
    tintHabits: Color(0xFFF3EFFD),
    dayRing: Color(0xFFE2D11E),
    scrim: Color(0x80000000),
    shadow: Color(0x0D000000),
    snackBarSurface: Color(0xFF1F2328),
    snackBarErrorSurface: Color(0xFF6B140F),
    onSnackBar: Color(0xFFFFFFFF),
    snackBarAction: Color(0xFF7DE2A8),
    snackBarErrorAction: Color(0xFFFFCCC7),
  );

  /// Dark palette (Figma mode "Dark").
  static const AppColors dark = AppColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceMuted: Color(0xFF26292E),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFB8BDC7),
    textTertiary: Color(0xFFA9AEB7),
    borderDecorative: Color(0xFF2C2F34),
    borderInput: Color(0xFF6B7079),
    track: Color(0xFF2C2F34),
    primary: Color(0xFF2FCB6E),
    primaryButton: Color(0xFF1F8655),
    onPrimary: Color(0xFFFFFFFF),
    primaryText: Color(0xFF5FD68F),
    primaryTint: Color(0xFF123222),
    toggleOn: Color(0xFF2FA26E),
    error: Color(0xFFFF8A80),
    errorTint: Color(0xFF3A1414),
    onError: Color(0xFF121212),
    warningText: Color(0xFFF5B75F),
    warningTint: Color(0xFF33260F),
    moduleWeight: Color(0xFF5FD68F),
    moduleWater: Color(0xFF6CB8FF),
    moduleWaterChart: Color(0xFF4AAEFF),
    moduleSteps: Color(0xFFE36AD9),
    moduleWorkout: Color(0xFFFF9A5C),
    moduleFocus: Color(0xFF8C95FF),
    moduleHabits: Color(0xFFB49BFF),
    moduleNutrition: Color(0xFFF5B75F),
    moduleGamification: Color(0xFFF5B75F),
    streak: Color(0xFFFF8A66),
    moduleGamificationText: Color(0xFFF5B75F),
    streakText: Color(0xFFFF8A66),
    tintWater: Color(0xFF2A3742),
    tintSteps: Color(0xFF3E2A3C),
    tintWorkout: Color(0xFF423228),
    tintFocus: Color(0xFF303142),
    tintHabits: Color(0xFF363242),
    dayRing: Color(0xFFE2D11E),
    scrim: Color(0x80000000),
    shadow: Color(0x26000000),
    snackBarSurface: Color(0xFF1F2328),
    snackBarErrorSurface: Color(0xFF6B140F),
    onSnackBar: Color(0xFFFFFFFF),
    snackBarAction: Color(0xFF7DE2A8),
    snackBarErrorAction: Color(0xFFFFCCC7),
  );

  /// OLED palette (Figma mode "OLED"): true black background.
  static const AppColors oled = AppColors(
    background: Color(0xFF000000),
    surface: Color(0xFF101010),
    surfaceMuted: Color(0xFF17191C),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFB8BDC7),
    textTertiary: Color(0xFFA9AEB7),
    borderDecorative: Color(0xFF24272B),
    borderInput: Color(0xFF6B7079),
    track: Color(0xFF24272B),
    primary: Color(0xFF2FCB6E),
    primaryButton: Color(0xFF1F8655),
    onPrimary: Color(0xFFFFFFFF),
    primaryText: Color(0xFF5FD68F),
    primaryTint: Color(0xFF0C2418),
    toggleOn: Color(0xFF2FA26E),
    error: Color(0xFFFF8A80),
    errorTint: Color(0xFF2A0E0E),
    onError: Color(0xFF121212),
    warningText: Color(0xFFF5B75F),
    warningTint: Color(0xFF241B0A),
    moduleWeight: Color(0xFF5FD68F),
    moduleWater: Color(0xFF6CB8FF),
    moduleWaterChart: Color(0xFF4AAEFF),
    moduleSteps: Color(0xFFE36AD9),
    moduleWorkout: Color(0xFFFF9A5C),
    moduleFocus: Color(0xFF8C95FF),
    moduleHabits: Color(0xFFB49BFF),
    moduleNutrition: Color(0xFFF5B75F),
    moduleGamification: Color(0xFFF5B75F),
    streak: Color(0xFFFF8A66),
    moduleGamificationText: Color(0xFFF5B75F),
    streakText: Color(0xFFFF8A66),
    tintWater: Color(0xFF1F2B36),
    tintSteps: Color(0xFF321E30),
    tintWorkout: Color(0xFF36261C),
    tintFocus: Color(0xFF242536),
    tintHabits: Color(0xFF2A2636),
    dayRing: Color(0xFFE2D11E),
    scrim: Color(0x80000000),
    shadow: Color(0x26000000),
    snackBarSurface: Color(0xFF1F2328),
    snackBarErrorSurface: Color(0xFF6B140F),
    onSnackBar: Color(0xFFFFFFFF),
    snackBarAction: Color(0xFF7DE2A8),
    snackBarErrorAction: Color(0xFFFFCCC7),
  );
}
