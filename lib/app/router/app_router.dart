import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/guarded_routes.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/app/screens/not_found_screen.dart';
import 'package:self_improvement/app/shell/app_shell.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/features/modules/presentation/modules_screen.dart';
import 'package:self_improvement/features/onboarding/presentation/onboarding_screen.dart';
import 'package:self_improvement/features/profile/presentation/goals_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_edit_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_screen.dart';
import 'package:self_improvement/features/settings/presentation/data_screen.dart';
import 'package:self_improvement/features/settings/presentation/licenses_screen.dart';
import 'package:self_improvement/features/settings/presentation/settings_screen.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';

/// The root router (overridden at the app root).
final appRouterProvider = Provider<GoRouter>(
  (ref) => throw UnimplementedError('appRouterProvider must be overridden'),
);

/// Builders of the four tab screens. The defaults are the real screens; tests
/// replace them with small probes.
class AppTabBuilders {
  const AppTabBuilders({this.home, this.analysis, this.habits, this.profile});

  final GoRouterWidgetBuilder? home;
  final GoRouterWidgetBuilder? analysis;
  final GoRouterWidgetBuilder? habits;
  final GoRouterWidgetBuilder? profile;
}

/// All routes of the app, registered once:
///
/// - the four tabs in one `StatefulShellRoute` (every tab keeps its own
///   navigation and scroll state),
/// - the core sub pages, pushed over the shell (no navigation bar),
/// - the routes of every module, guarded by [guardModuleRoutes].
List<RouteBase> buildAppRoutes({
  required List<SelfImprovementModule> modules,
  AppTabBuilders tabs = const AppTabBuilders(),
}) {
  return <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: tabs.home ?? (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.analysis,
              builder:
                  tabs.analysis ?? (context, state) => const AnalysisScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.habits,
              builder:
                  tabs.habits ??
                  (context, state) => HabitsTabScreen(
                    showTasks: state.uri.queryParameters['tab'] == 'tasks',
                  ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.profile,
              builder:
                  tabs.profile ?? (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.profileEdit,
      builder: (context, state) => const ProfileEditScreen(),
    ),
    GoRoute(
      path: AppRoutes.goals,
      builder: (context, state) => const GoalsScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.modules,
      builder: (context, state) => const ModulesScreen(),
    ),
    GoRoute(
      path: AppRoutes.data,
      builder: (context, state) => const DataScreen(),
    ),
    GoRoute(
      path: AppRoutes.licenses,
      builder: (context, state) => const LicensesScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.notFound,
      builder: (context, state) => const NotFoundScreen(),
    ),
    for (final module in modules) ...guardModuleRoutes(module, module.routes),
  ];
}

/// Creates the router. [readGuard] answers synchronously from the current
/// start state; [refresh] fires when that state changes (onboarding finished
/// or reset), which re-runs the redirect.
GoRouter createAppRouter({
  required List<SelfImprovementModule> modules,
  required RouteGuardState Function() readGuard,
  required GlobalKey<NavigatorState> navigatorKey,
  Listenable? refresh,
  AppTabBuilders tabs = const AppTabBuilders(),
  String initialLocation = AppRoutes.home,
  List<NavigatorObserver>? observers,
}) {
  final routes = buildAppRoutes(modules: modules, tabs: tabs);
  assert(() {
    final duplicates = findDuplicatePaths(routes);
    if (duplicates.isNotEmpty) {
      throw StateError('Route paths registered twice: $duplicates');
    }
    return true;
  }());
  return GoRouter(
    routes: routes,
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    refreshListenable: refresh,
    observers: observers,
    redirect: (context, state) => guardRedirect(readGuard(), state.uri.path),
    errorBuilder: (context, state) => const NotFoundScreen(),
  );
}

/// The full path of every route, once per registration; paths that occur more
/// than once are returned (a second registration would never be reached).
List<String> findDuplicatePaths(List<RouteBase> routes) {
  final seen = <String>{};
  final duplicates = <String>[];
  void visit(RouteBase route, String parent) {
    if (route is GoRoute) {
      final full = _join(parent, route.path);
      if (!seen.add(full)) {
        duplicates.add(full);
      }
      for (final child in route.routes) {
        visit(child, full);
      }
    } else if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        for (final child in branch.routes) {
          visit(child, parent);
        }
      }
    } else {
      for (final child in route.routes) {
        visit(child, parent);
      }
    }
  }

  for (final route in routes) {
    visit(route, '');
  }
  return duplicates;
}

/// Every full path of [routes] (for the route table in tests and docs).
List<String> allRoutePaths(List<RouteBase> routes) {
  final paths = <String>[];
  void visit(RouteBase route, String parent) {
    if (route is GoRoute) {
      final full = _join(parent, route.path);
      paths.add(full);
      for (final child in route.routes) {
        visit(child, full);
      }
    } else if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        for (final child in branch.routes) {
          visit(child, parent);
        }
      }
    } else {
      for (final child in route.routes) {
        visit(child, parent);
      }
    }
  }

  for (final route in routes) {
    visit(route, '');
  }
  return paths;
}

String _join(String parent, String path) {
  if (path.startsWith('/')) {
    return path;
  }
  return parent == '/' || parent.isEmpty ? '/$path' : '$parent/$path';
}
