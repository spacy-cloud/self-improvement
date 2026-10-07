import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/domain/day_browser.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The day the person picked on Home (BS-93); `null` follows today.
///
/// A new calendar day drops the choice, so the dashboard never opens on a stale
/// day: after the app was in the background over midnight it shows the new
/// today, whether it showed today or a day before (D-029). The same holds for
/// the habits tab (`SelectedHabitDayController`). The choice lives as long as
/// the app runs; it is not stored.
///
/// Only reachable days can be chosen ([BrowsedDay]): today and at most seven
/// days before it, never one before the profile started. A choice outside of
/// that is ignored.
class SelectedDayController extends Notifier<LocalDate?> {
  @override
  LocalDate? build() {
    ref.watch(todayProvider);
    return null;
  }

  /// The day shown now, resolved like [browsedDayProvider] does. (Reading that
  /// provider here would be a circle: it depends on this one.)
  BrowsedDay get _current => BrowsedDay.resolve(
    today: ref.read(todayProvider),
    choice: state,
    profileStart: ref.read(profileProvider).value?.startedOn,
  );

  /// Goes to the day before the one shown, if there is one.
  void previous() {
    final day = _current.previous;
    if (day != null) {
      state = day;
    }
  }

  /// Goes to the day after the one shown, if there is one.
  void next() {
    final current = _current;
    final day = current.next;
    if (day != null) {
      state = day == current.today ? null : day;
    }
  }

  /// Shows [day] if it can be reached; today follows the clock again.
  void select(LocalDate day) {
    final current = _current;
    if (day == current.today) {
      state = null;
    } else if (!day.isBefore(current.oldest) && day.isBefore(current.today)) {
      state = day;
    }
  }

  /// Back to today ("Zurück zu heute").
  void backToToday() => state = null;
}

final selectedDayProvider = NotifierProvider<SelectedDayController, LocalDate?>(
  SelectedDayController.new,
);

/// The day Home shows: the choice, or today. Follows the clock, the choice and
/// the first day of the profile.
final browsedDayProvider = Provider<BrowsedDay>((ref) {
  final today = ref.watch(todayProvider);
  final choice = ref.watch(selectedDayProvider);
  final profileStart = ref.watch(profileProvider).value?.startedOn;
  return BrowsedDay.resolve(
    today: today,
    choice: choice,
    profileStart: profileStart,
  );
});
