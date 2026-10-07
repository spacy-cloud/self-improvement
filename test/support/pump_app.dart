import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

import '../core/design/support/design_test_harness.dart' show loadInterFont;

export '../core/design/support/design_test_harness.dart'
    show loadInterFont, testSemantics;

/// Key of the boundary around the pumped app; used by [savePng].
const Key appBoundaryKey = ValueKey<String>('test-app-boundary');

/// Standard logical screen sizes (width x height) the responsive tests check.
const List<Size> responsiveSizes = <Size>[
  Size(320, 640),
  Size(360, 800),
  Size(393, 852),
  Size(430, 932),
];

/// Creates a [DataHarness] inside `runAsync` (real async I/O of the in-memory
/// database) and disposes it when the test ends, after taking down whatever the
/// test still has mounted.
///
/// With [onboarded] the onboarding state is seeded (all modules enabled, goal
/// versions, dashboard cards); pass [enabledModules] to enable only some.
Future<DataHarness> createTestHarness(
  WidgetTester tester, {
  bool onboarded = true,
  Set<String>? enabledModules,
  String nowIso = '2026-10-03T08:00:00Z',
  bool realProjection = false,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(nowIso: nowIso, realProjection: realProjection),
  ))!;
  addTearDown(() async {
    // Take the app down before the database closes. A failed test leaves its
    // widget tree mounted, Riverpod pauses the listeners of the pages that
    // another page covers, and Drift's close() waits for the end of every
    // listener, which a paused one never reaches: the tear down (and with it
    // the whole run) would hang instead of reporting the failure (BS-98, R1-04).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });
  if (onboarded) {
    await tester.runAsync(
      () => harness.seedOnboarded(enabledModules: enabledModules),
    );
  }
  return harness;
}

/// Pumps [child] the way the app shows a screen: German locale, the real
/// theme (Light by default), Inter font, text scale, screen size, and the
/// providers of [container] (or fresh [overrides]).
///
/// The first frame is pumped and the pending first database reads are
/// delivered, so the screen shows data right after this call returns.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  ProviderContainer? container,
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  bool reducedMotion = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool wrapInScaffold = false,
}) async {
  await _prepareView(tester, size, viewInsets);
  final app = _themedApp(
    theme: theme,
    textScale: textScale,
    reducedMotion: reducedMotion,
    builder: (context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forVariant(theme),
      locale: const Locale('de'),
      supportedLocales: const <Locale>[Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, appChild) => _scaled(context, textScale, appChild!),
      home: wrapInScaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pumpWidget(_scoped(app, container, overrides));
  await _deliverFirstReads(tester);
}

/// Like [pumpApp], but navigates with go_router (named screens, back button,
/// deep links). [routes] are typically `module.routes` plus helper routes.
Future<GoRouter> pumpRouterApp(
  WidgetTester tester, {
  required List<RouteBase> routes,
  required String initialLocation,
  ProviderContainer? container,
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  bool reducedMotion = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  await _prepareView(tester, size, viewInsets);
  final router = GoRouter(routes: routes, initialLocation: initialLocation);
  addTearDown(router.dispose);
  final app = _themedApp(
    theme: theme,
    textScale: textScale,
    reducedMotion: reducedMotion,
    builder: (context) => MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forVariant(theme),
      locale: const Locale('de'),
      supportedLocales: const <Locale>[Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, appChild) => _scaled(context, textScale, appChild!),
      routerConfig: router,
    ),
  );
  await tester.pumpWidget(_scoped(app, container, overrides));
  await _deliverFirstReads(tester);
  return router;
}

/// Writes a PNG of the pumped app (for the visual check against the Figma
/// frame). Use a path below the git-ignored `build/` folder.
Future<void> savePng(
  WidgetTester tester,
  String filePath, {
  double pixelRatio = 2,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(appBoundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(filePath)..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Helpers for tests that run commands against the in-memory database.
extension AppWidgetTester on WidgetTester {
  /// Runs [action] (a repository call or any real async work) outside the fake
  /// clock, lets drift deliver its stream updates and rebuilds the tree.
  ///
  /// A plain `pump()` after a command is NOT enough for drift streams.
  Future<T> runCommand<T>(Future<T> Function() action) async {
    final result = await runAsync(() async {
      final value = await action();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return value;
    });
    await pump(const Duration(milliseconds: 50));
    return result as T;
  }

  /// Waits (in real time) until [done] is true, pumping in between. Fails the
  /// test with [reason] after [timeout].
  Future<void> pumpUntil(
    bool Function() done, {
    String reason = 'condition not reached',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!done()) {
      if (stopwatch.elapsed > timeout) {
        fail('pumpUntil timed out: $reason');
      }
      await runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await pump(const Duration(milliseconds: 50));
    }
  }
}

Future<void> _prepareView(
  WidgetTester tester,
  Size size,
  EdgeInsets viewInsets,
) async {
  await tester.runAsync(loadInterFont);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(
    left: viewInsets.left,
    top: viewInsets.top,
    right: viewInsets.right,
    bottom: viewInsets.bottom,
  );
  addTearDown(tester.view.reset);
}

Widget _themedApp({
  required AppThemeVariant theme,
  required double textScale,
  required bool reducedMotion,
  required WidgetBuilder builder,
}) {
  return RepaintBoundary(
    key: appBoundaryKey,
    child: ReducedMotionScope(
      reduce: reducedMotion,
      child: Builder(builder: builder),
    ),
  );
}

Widget _scaled(BuildContext context, double textScale, Widget child) {
  final media = MediaQuery.of(context)
      .copyWith(textScaler: TextScaler.linear(textScale));
  return MediaQuery(data: media, child: child);
}

Widget _scoped(
  Widget app,
  ProviderContainer? container,
  List<Override> overrides,
) {
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: overrides,
    child: app,
  );
}

Future<void> _deliverFirstReads(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 50));
}
