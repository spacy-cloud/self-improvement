import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';

/// The page of every route of the app: the platform's Material page whose
/// transition follows the motion setting at the moment it runs.
///
/// go_router 18 chooses the page type by looking for the `MaterialApp` of the
/// separate `material_ui` package; the app uses the SDK's `MaterialApp`, so
/// without this every route change would be a hard cut.
///
/// It is ONE page class for both cases (motion allowed, motion reduced). A page
/// of another class cannot be updated in place, so choosing the class by the
/// setting would rebuild every open page when the setting flips (the scroll
/// position of the settings page, where the switch is, and every sheet above a
/// page would be lost). Only the route reads the setting, when it starts a
/// transition (see [AppMotion.of]: the system flag or the app setting
/// "Reduzierte Bewegung").
class AppPage<T> extends Page<T> {
  /// Creates the page of a route.
  const AppPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The content of the route.
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _AppPageRoute<T>(this);
}

// The page-based Material route (see `MaterialPage`), with transition
// durations of zero while motion is reduced. The framework reads both
// durations again at every push and pop, so a change of the setting applies
// to the next page change.
class _AppPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _AppPageRoute(AppPage<T> page) : super(settings: page);

  AppPage<T> get _page => settings as AppPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : super.reverseTransitionDuration;

  bool get _reduced {
    final context = navigator?.context;
    return context != null && AppMotion.of(context).reduced;
  }
}

/// The page of a route (see [AppPage]).
Page<void> appPageFor(GoRouterState state, Widget child) {
  final key = state.pageKey;
  return AppPage<void>(
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
  pageBuilder: (context, state) => appPageFor(state, builder(context, state)),
  routes: routes,
);
