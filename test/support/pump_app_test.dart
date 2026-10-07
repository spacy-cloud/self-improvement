import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';

import 'pump_app.dart';

class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(weightEntriesProvider);
    final scale = MediaQuery.textScalerOf(context).scale(10);
    return Scaffold(
      body: Column(
        children: [
          Text(
            entries.when(
              data: (list) => 'count=${list.length}',
              loading: () => 'loading',
              error: (e, _) => 'error',
            ),
          ),
          Text('scale=$scale'),
          Text('primary=${context.tokens.colors.primaryButton.toARGB32()}'),
          Text('width=${MediaQuery.sizeOf(context).width}'),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('pumpApp provides theme, size, text scale and database data', (
    tester,
  ) async {
    final harness = await createTestHarness(tester);
    final container = harness.createContainer();
    await pumpApp(
      tester,
      const _Probe(),
      container: container,
      size: const Size(320, 640),
      textScale: 2.0,
      theme: AppThemeVariant.dark,
    );
    expect(find.text('count=0'), findsOneWidget);
    expect(find.text('scale=20.0'), findsOneWidget);
    expect(find.text('width=320.0'), findsOneWidget);
    expect(
      find.text('primary=${AppTokens.dark.colors.primaryButton.toARGB32()}'),
      findsOneWidget,
    );

    await tester.runCommand(
      () => container
          .read(weightRepositoryProvider)
          .create(
            commandId: 'c1',
            draft: WeightDraft(
              weightGrams: 71500,
              occurredAtUtc: harness.clock.nowUtc(),
            ),
          ),
    );
    expect(find.text('count=1'), findsOneWidget);
  });

  group('the platform of a test variant reaches the screen (BS-112, R1-01)', () {
    const platforms = TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
    });

    /// The platform of the theme and the scroll physics a screen below the app
    /// sees: what decides how a Material text field and a scroll view behave.
    Widget probe(List<String> seen) => Builder(
      builder: (context) {
        seen
          ..add(Theme.of(context).platform.name)
          ..add(
            ScrollConfiguration.of(context)
                .getScrollPhysics(context)
                .runtimeType
                .toString(),
          );
        return const SizedBox();
      },
    );

    List<String> expected() => <String>[
      defaultTargetPlatform.name,
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'BouncingScrollPhysics'
          : 'ClampingScrollPhysics',
    ];

    testWidgets(
      'pumpApp shows the screen with the theme and the scroll physics of the platform of the test (BS-112, R1-01, AT33)',
      (tester) async {
        final seen = <String>[];
        await pumpApp(tester, probe(seen));
        expect(seen.take(2).toList(), expected());
      },
      variant: platforms,
    );

    testWidgets(
      'pumpRouterApp shows the screen with the theme and the scroll physics of the platform of the test (BS-112, R1-01, AT33)',
      (tester) async {
        final seen = <String>[];
        await pumpRouterApp(
          tester,
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(path: '/', builder: (context, state) => probe(seen)),
          ],
        );
        expect(seen.take(2).toList(), expected());
      },
      variant: platforms,
    );
  });

  testWidgets('pumpRouterApp navigates and the back button pops', (
    tester,
  ) async {
    final harness = await createTestHarness(tester);
    final container = harness.createContainer();
    final router = await pumpRouterApp(
      tester,
      container: container,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/detail'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) =>
              const AppScaffold.subpage(title: 'Detail', body: Text('inside')),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
    expect(router.canPop(), isTrue);
    await tester.tap(find.bySemanticsLabel('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
