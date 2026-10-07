import 'package:self_improvement/core/notifications/domain/notification_routes.dart';

/// Route paths the app shell itself registers (tabs and core sub pages). The
/// routes of the five modules (weight, water, focus, tasks, ...) belong to
/// their module class; the complete table is in `docs/screens/shell.md`.
abstract final class AppRoutes {
  /// Home tab (dashboard).
  static const String home = '/';

  /// Analysis tab.
  static const String analysis = '/analysis';

  /// Habits tab; `?tab=tasks` selects the tasks list.
  static const String habits = '/habits';

  /// Habits tab with the tasks list selected.
  static const String habitsTasks = '/habits?tab=tasks';

  /// Profile tab.
  static const String profile = '/profile';

  static const String profileEdit = '/profile/edit';
  static const String goals = '/goals';
  static const String settings = '/settings';
  static const String modules = '/settings/modules';
  static const String data = '/settings/data';
  static const String licenses = '/settings/licenses';

  /// "Über die App": version, author, website, privacy, technical versions.
  static const String about = '/settings/about';

  /// Onboarding (the five steps run inside this one route).
  static const String onboarding = '/onboarding';

  /// Target of malformed ids; also the screen for unknown locations.
  static const String notFound = '/not-found';

  /// The open focus session (module `focus`); the plus menu resumes it.
  static const String focusSession = NotificationRoutes.focusSession;

  /// The four tab roots in navigation order.
  static const List<String> tabRoots = <String>[
    home,
    analysis,
    habits,
    profile,
  ];

  /// Whether [path] is one of the four tab roots.
  static bool isTabRoot(String path) => tabRoots.contains(path);

  /// Whether [path] belongs to the onboarding flow.
  static bool isOnboarding(String path) =>
      path == onboarding || path.startsWith('$onboarding/');
}
