import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_pages.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/app/screens/module_disabled_screen.dart';
import 'package:self_improvement/app/screens/not_found_screen.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';

/// Wraps the routes of [module] so the shell guards them centrally:
///
/// - a malformed record id (anything but a canonical UUID in a parameter
///   named `id` or `...Id`) shows the not-found screen, never the screen;
/// - a switched-off module shows [ModuleDisabledScreen] in place and swaps to
///   the real screen as soon as the module is on (the location is kept, so
///   going back works as usual).
///
/// Module routes must be `GoRoute`s with a `builder`; anything else is a
/// programming error and fails at router creation, never silently unguarded.
List<RouteBase> guardModuleRoutes(
  SelfImprovementModule module,
  List<RouteBase> routes,
) => <RouteBase>[for (final route in routes) _guard(module, route)];

RouteBase _guard(SelfImprovementModule module, RouteBase route) {
  if (route is! GoRoute) {
    throw ArgumentError(
      'Module routes must be GoRoute (module ${module.id.key}, found '
      '${route.runtimeType}).',
    );
  }
  if (route.pageBuilder != null) {
    throw ArgumentError(
      'Module route ${route.path} uses pageBuilder; module routes must use '
      'builder so the shell can guard them.',
    );
  }
  final builder = route.builder;
  return GoRoute(
    path: route.path,
    name: route.name,
    parentNavigatorKey: route.parentNavigatorKey,
    redirect: route.redirect,
    metadata: route.metadata,
    onExit: route.onExit,
    caseSensitive: route.caseSensitive,
    pageBuilder: builder == null
        ? null
        : (context, state) => appPageFor(
            state,
            ModuleRouteGate(
              module: module,
              pathParameters: state.pathParameters,
              builder: (gateContext) => builder(gateContext, state),
            ),
          ),
    routes: <RouteBase>[
      for (final child in route.routes) _guard(module, child),
    ],
  );
}

/// Builds the guarded content of one module route (see [guardModuleRoutes]).
class ModuleRouteGate extends ConsumerWidget {
  const ModuleRouteGate({
    required this.module,
    required this.pathParameters,
    required this.builder,
    super.key,
  });

  final SelfImprovementModule module;
  final Map<String, String> pathParameters;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasMalformedId(pathParameters)) {
      return const NotFoundScreen();
    }
    final statuses = ref.watch(moduleStatusesProvider);
    final value = statuses.value;
    if (value == null) {
      return AppScaffold.subpage(
        title: module.title,
        onBack: () => leaveOrHome(context),
        body: statuses.hasError
            ? ErrorState(onRetry: () => ref.invalidate(moduleStatusesProvider))
            : const SizedBox(height: 160, child: NeutralLoading()),
      );
    }
    if (!(value[module.id] ?? true)) {
      return ModuleDisabledScreen(module: module);
    }
    return builder(context);
  }
}
