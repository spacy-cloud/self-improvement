import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';

/// The page of a route.
///
/// go_router 18 chooses the page type by looking for the `MaterialApp` of the
/// separate `material_ui` package; the app uses the SDK's `MaterialApp`, so
/// without this every route change would be a hard cut. The page therefore
/// comes from here: the platform's Material transition, or no transition at
/// all when motion is reduced (the system flag or the app setting "Reduzierte
/// Bewegung", see [AppMotion.of]).
Page<void> appPageFor(BuildContext context, GoRouterState state, Widget child) {
  final key = state.pageKey;
  return AppMotion.of(context).reduced
      ? NoTransitionPage<void>(
          key: key,
          name: state.name,
          arguments: state.extra,
          restorationId: key.value,
          child: child,
        )
      : MaterialPage<void>(
          key: key,
          name: state.name,
          arguments: state.extra,
          restorationId: key.value,
          child: child,
        );
}

/// A route whose page comes from [appPageFor].
GoRoute appRoute({
  required String path,
  required GoRouterWidgetBuilder builder,
  String? name,
  List<RouteBase> routes = const <RouteBase>[],
}) => GoRoute(
  path: path,
  name: name,
  pageBuilder: (context, state) =>
      appPageFor(context, state, builder(context, state)),
  routes: routes,
);
