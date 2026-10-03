import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

/// A pushed page follows the motion setting like every other motion of the app
/// (Q03): the Material transition normally, none when motion is reduced.
void main() {
  Future<Route<void>> routeIn(
    WidgetTester tester, {
    bool systemReduced = false,
    bool? appReduced,
  }) async {
    late Route<void> route;
    Widget app = MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: systemReduced),
        child: Builder(
          builder: (context) {
            route = appPageRoute<void>(context, (_) => const SizedBox());
            return const SizedBox();
          },
        ),
      ),
    );
    if (appReduced != null) {
      app = ReducedMotionScope(reduce: appReduced, child: app);
    }
    await tester.pumpWidget(app);
    return route;
  }

  testWidgets('the Material transition when motion is allowed', (tester) async {
    final route = await routeIn(tester);
    expect(route, isA<MaterialPageRoute<void>>());
  });

  testWidgets('no transition when the system reduces motion', (tester) async {
    final route = await routeIn(tester, systemReduced: true);
    expect(route, isA<PageRouteBuilder<void>>());
    expect((route as PageRouteBuilder<void>).transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('no transition when the app setting reduces motion', (
    tester,
  ) async {
    final route = await routeIn(tester, appReduced: true);
    expect(route, isA<PageRouteBuilder<void>>());
    expect((route as PageRouteBuilder<void>).transitionDuration, Duration.zero);
  });

  testWidgets('the app setting off keeps the Material transition', (
    tester,
  ) async {
    final route = await routeIn(tester, appReduced: false);
    expect(route, isA<MaterialPageRoute<void>>());
  });
}
