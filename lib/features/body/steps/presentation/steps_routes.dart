import 'package:go_router/go_router.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Routes of the steps screens (design handoff routes table).
abstract final class StepsRoutes {
  static const String overview = '/steps';
  static const String create = '/steps/new';

  /// The form for a specific date, used to correct an earlier day.
  static String createFor(LocalDate date) => '$create?date=${date.toIso()}';

  /// The date of a `/steps/new?date=YYYY-MM-DD` link, or null (today).
  static LocalDate? dateOf(GoRouterState state) =>
      LocalDate.tryParse(state.uri.queryParameters['date'] ?? '');
}
