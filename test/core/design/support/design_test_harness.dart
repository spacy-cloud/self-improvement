import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

/// The three theme variants every design test runs against.
const List<AppThemeVariant> allVariants = AppThemeVariant.values;

bool _fontsLoaded = false;

/// Loads the bundled Inter font and the Material icon font from the asset
/// bundle so that layout metrics and glyphs in tests match the real app (the
/// default test font is the wide Ahem font and icons render as boxes).
Future<void> loadInterFont() async {
  if (_fontsLoaded) {
    return;
  }
  final inter = FontLoader(AppTextStyles.fontFamily);
  for (final file in <String>['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$file.ttf'));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  _fontsLoaded = true;
}

/// Pumps [child] inside a themed `MaterialApp` and a `Scaffold` at the given
/// logical [width] and [height] (device pixel ratio 1) and text scale.
///
/// With [scrollable] the child is placed in a scroll view with a 16 px page
/// margin, otherwise it fills the body.
Future<void> pumpDesign(
  WidgetTester tester,
  Widget child, {
  AppThemeVariant variant = AppThemeVariant.light,
  double width = 393,
  double height = 852,
  double textScale = 1.0,
  bool scrollable = true,
  bool wrapScaffold = true,
  bool disableAnimations = false,
  bool? reduceMotion,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Widget home = child;
  if (wrapScaffold) {
    home = Scaffold(
      body: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            )
          : child,
    );
  }
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.forVariant(variant),
    builder: (context, appChild) {
      final media = MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      );
      return MediaQuery(data: media, child: appChild!);
    },
    home: home,
  );
  if (reduceMotion != null) {
    app = ReducedMotionScope(reduce: reduceMotion, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pump();
}

/// Variant name for test descriptions.
String variantName(AppThemeVariant variant) => variant.name;

/// Waits for animations of 250 ms plus a margin.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
}

/// Like `testWidgets`, but with the semantics tree enabled for the whole test
/// (the handle is disposed before the end-of-test verification).
void testSemantics(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await callback(tester);
    } finally {
      handle.dispose();
    }
  });
}

/// The [Material] of the first tappable surface below [finder].
Material materialOf(WidgetTester tester, Finder finder) {
  return tester.widget<Material>(
    find.descendant(of: finder, matching: find.byType(Material)).first,
  );
}

/// Text colour of the text [label].
Color? textColor(WidgetTester tester, String label) {
  return tester.widget<Text>(find.text(label)).style?.color;
}

/// Size of the semantics node of [finder].
Size semanticsSize(WidgetTester tester, Finder finder) {
  return tester.getSemantics(finder).rect.size;
}
