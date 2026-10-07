import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/guarded_routes.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/fake_modules.dart';

const RouteGuardState _onboarded = RouteGuardState(
  ready: true,
  onboardingCompleted: true,
);
const RouteGuardState _fresh = RouteGuardState(
  ready: true,
  onboardingCompleted: false,
);

UserProfile _profile({required bool onboarded}) => UserProfile(
  startedOn: LocalDate(2026, 10, 3),
  onboardingCompleted: onboarded,
  rowVersion: 1,
);

void main() {
  group('guardRedirect', () {
    test('without completed onboarding every location leads to it (AT01)', () {
      for (final path in <String>['/', '/analysis', '/weight/new', '/x']) {
        expect(guardRedirect(_fresh, path), AppRoutes.onboarding);
      }
      expect(guardRedirect(_fresh, AppRoutes.onboarding), isNull);
      expect(guardRedirect(_fresh, '/onboarding/2'), isNull);
    });

    test('with completed onboarding the flow leads to the dashboard', () {
      expect(guardRedirect(_onboarded, AppRoutes.onboarding), AppRoutes.home);
      expect(guardRedirect(_onboarded, '/onboarding/3'), AppRoutes.home);
      for (final path in <String>['/', '/analysis', '/weight/new', '/x']) {
        expect(guardRedirect(_onboarded, path), isNull);
      }
    });

    test('an unknown start state decides nothing', () {
      expect(guardRedirect(RouteGuardState.starting, '/weight'), isNull);
    });
  });

  group('RouteGuardState.fromProfile', () {
    test('reads the onboarding flag; a missing profile is not onboarded', () {
      expect(
        RouteGuardState.fromProfile(const AsyncLoading<UserProfile?>()),
        RouteGuardState.starting,
      );
      expect(
        RouteGuardState.fromProfile(
          AsyncData<UserProfile?>(_profile(onboarded: true)),
        ),
        _onboarded,
      );
      expect(
        RouteGuardState.fromProfile(
          AsyncData<UserProfile?>(_profile(onboarded: false)),
        ),
        _fresh,
      );
      expect(
        RouteGuardState.fromProfile(const AsyncData<UserProfile?>(null)),
        _fresh,
      );
    });
  });

  group('record id parameters', () {
    test('only canonical UUIDs pass', () {
      const good = '123e4567-e89b-42d3-a456-426614174000';
      expect(hasMalformedId(<String, String>{'id': good}), isFalse);
      for (final bad in <String>[
        '',
        'abc',
        '123',
        'new ',
        good.toUpperCase(),
        '$good/x',
        good.substring(1),
        '../etc',
      ]) {
        expect(
          hasMalformedId(<String, String>{'id': bad}),
          isTrue,
          reason: bad,
        );
      }
    });

    test('names ending in Id are record ids, other parameters are not', () {
      expect(isIdParameter('id'), isTrue);
      expect(isIdParameter('habitId'), isTrue);
      expect(isIdParameter('tab'), isFalse);
      expect(hasMalformedId(<String, String>{'tab': 'tasks'}), isFalse);
      expect(hasMalformedId(<String, String>{'habitId': 'nope'}), isTrue);
    });
  });

  group('route table', () {
    test(
      'every path is registered once, with all five bundled modules (AT01)',
      () {
        final routes = buildAppRoutes(modules: bundledModules);
        expect(findDuplicatePaths(routes), isEmpty);
        final paths = allRoutePaths(routes);
        for (final expected in <String>[
          '/',
          '/analysis',
          '/habits',
          '/profile',
          '/profile/edit',
          '/goals',
          '/goals/today',
          '/settings',
          '/settings/modules',
          '/settings/data',
          '/settings/licenses',
          '/onboarding',
          '/not-found',
          '/streak',
          '/progress',
          '/weight',
          '/weight/new',
          '/weight/all',
          '/weight/:id',
        ]) {
          expect(paths, contains(expected));
        }
      },
    );

    test('the weight routes keep their order: new and all before :id', () {
      final paths = allRoutePaths(buildAppRoutes(modules: bundledModules));
      final weight = paths.where((p) => p.startsWith('/weight')).toList();
      expect(weight, <String>[
        '/weight',
        '/weight/new',
        '/weight/all',
        '/weight/:id',
      ]);
    });

    test('a path registered twice is found', () {
      final routes = buildAppRoutes(
        modules: <FakeModule>[
          FakeModule(ModuleId.body, paths: const {'/same': 'a'}),
          FakeModule(ModuleId.nutrition, paths: const {'/same': 'b'}),
        ],
      );
      expect(findDuplicatePaths(routes), <String>['/same']);
    });

    test(
      'module routes that cannot be guarded are refused, never left open',
      () {
        expect(
          () => guardModuleRoutes(const FakeModule(ModuleId.body), <RouteBase>[
            ShellRoute(
              builder: (context, state, child) => child,
              routes: <RouteBase>[probeRoute('/a', 'a')],
            ),
          ]),
          throwsArgumentError,
        );
        expect(
          () => guardModuleRoutes(const FakeModule(ModuleId.body), <RouteBase>[
            GoRoute(
              path: '/page',
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: SizedBox()),
            ),
          ]),
          throwsArgumentError,
        );
      },
    );
  });
}
