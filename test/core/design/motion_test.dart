import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

AppMotionData? _read;

Widget _probe({bool disableAnimations = false, bool? scope}) {
  Widget app = MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Builder(
      builder: (context) {
        _read = AppMotion.of(context);
        return const SizedBox();
      },
    ),
  );
  if (scope != null) {
    app = ReducedMotionScope(reduce: scope, child: app);
  }
  return Directionality(textDirection: TextDirection.ltr, child: app);
}

void main() {
  test(
    'durations are 150, 200 and 250 ms (inside the 150 to 250 ms range)',
    () {
      expect(AppMotion.fast, const Duration(milliseconds: 150));
      expect(AppMotion.standard, const Duration(milliseconds: 200));
      expect(AppMotion.slow, const Duration(milliseconds: 250));
      for (final d in <Duration>[
        AppMotion.fast,
        AppMotion.standard,
        AppMotion.slow,
      ]) {
        expect(d, greaterThanOrEqualTo(const Duration(milliseconds: 150)));
        expect(d, lessThanOrEqualTo(const Duration(milliseconds: 250)));
      }
    },
  );

  testWidgets('without any request motion is not reduced', (tester) async {
    await tester.pumpWidget(_probe());
    expect(_read!.reduced, isFalse);
    expect(_read!.fast, AppMotion.fast);
    expect(_read!.standard, AppMotion.standard);
    expect(_read!.slow, AppMotion.slow);
  });

  testWidgets('the system flag disableAnimations makes everything immediate', (
    tester,
  ) async {
    await tester.pumpWidget(_probe(disableAnimations: true));
    expect(_read!.reduced, isTrue);
    expect(_read!.fast, Duration.zero);
    expect(_read!.standard, Duration.zero);
    expect(_read!.slow, Duration.zero);
    expect(_read!.resolve(const Duration(seconds: 1)), Duration.zero);
  });

  testWidgets(
    'the app setting through ReducedMotionScope makes everything immediate',
    (tester) async {
      await tester.pumpWidget(_probe(scope: true));
      expect(_read!.reduced, isTrue);
      expect(_read!.standard, Duration.zero);
    },
  );

  testWidgets('the app setting off does not override the system flag', (
    tester,
  ) async {
    await tester.pumpWidget(_probe(scope: false, disableAnimations: true));
    expect(_read!.reduced, isTrue);
    await tester.pumpWidget(_probe(scope: false));
    expect(_read!.reduced, isFalse);
  });

  testWidgets('changing the scope rebuilds dependants', (tester) async {
    var builds = 0;
    Widget build(bool reduce) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ReducedMotionScope(
          reduce: reduce,
          child: Builder(
            builder: (context) {
              builds++;
              _read = AppMotion.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(build(false));
    expect(_read!.reduced, isFalse);
    final before = builds;
    await tester.pumpWidget(build(true));
    expect(_read!.reduced, isTrue);
    expect(builds, greaterThan(before));
  });
}
