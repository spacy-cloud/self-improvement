import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/app/bootstrap/bootstrap_screens.dart';
import 'package:self_improvement/app/router/app_back_dispatcher.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/app/wiring/app_overrides.dart';
import 'package:self_improvement/app/wiring/app_wiring.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// The app: starts the services, shows a neutral loading state meanwhile, a
/// clear error with a retry when the database cannot be opened, and the real
/// app (router, shell, theme from the settings) once everything is ready.
///
/// [starter], [modules] and [overrides] exist for tests (in-memory database,
/// fixture modules, fake platforms); the defaults are the production values.
class SelfImprovementApp extends StatefulWidget {
  const SelfImprovementApp({
    super.key,
    this.starter = startProductionServices,
    this.modules = bundledModules,
    this.overrides = const <Override>[],
    this.tabs = const AppTabBuilders(),
  });

  final AppStarter starter;
  final List<SelfImprovementModule> modules;
  final List<Override> overrides;
  final AppTabBuilders tabs;

  @override
  State<SelfImprovementApp> createState() => _SelfImprovementAppState();
}

class _SelfImprovementAppState extends State<SelfImprovementApp> {
  AppServices? _services;
  Object? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    try {
      final services = await widget.starter();
      if (!mounted || attempt != _attempt) {
        await services.dispose();
        return;
      }
      setState(() => _services = services);
    } on Object catch (error) {
      debugPrint('app start failed: ${error.runtimeType}');
      if (mounted && attempt == _attempt) {
        setState(() => _error = error);
      }
    }
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_start());
  }

  @override
  void dispose() {
    _attempt++;
    final services = _services;
    if (services != null) {
      unawaited(services.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services != null) {
      return _RunningApp(
        key: ObjectKey(services),
        services: services,
        modules: widget.modules,
        overrides: widget.overrides,
        tabs: widget.tabs,
      );
    }
    final error = _error;
    return bootstrapApp(
      home: error == null
          ? const BootstrapLoadingScreen()
          : BootstrapErrorScreen(error: error, onRetry: _retry),
    );
  }
}

/// Notifies the router when the start state (onboarding) changed.
class _GuardRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _RunningApp extends StatefulWidget {
  const _RunningApp({
    required this.services,
    required this.modules,
    required this.overrides,
    required this.tabs,
    super.key,
  });

  final AppServices services;
  final List<SelfImprovementModule> modules;
  final List<Override> overrides;
  final AppTabBuilders tabs;

  @override
  State<_RunningApp> createState() => _RunningAppState();
}

class _RunningAppState extends State<_RunningApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'root-navigator',
  );
  final _GuardRefresh _refresh = _GuardRefresh();
  late final GoRouter _router;
  late final ProviderContainer _container;
  late final AppBackButtonDispatcher _backDispatcher;
  ProviderSubscription<AsyncValue<UserProfile?>>? _guardSubscription;
  final List<ProviderSubscription<Object?>> _keepAlive =
      <ProviderSubscription<Object?>>[];
  AppWiring? _wiring;
  Object? _prepareError;
  bool _ready = false;

  RouteGuardState _readGuard() =>
      RouteGuardState.fromProfile(_container.read(profileProvider));

  /// The snack bar floats above the navigation bar on a tab and above a pinned
  /// primary action on every other screen.
  double _feedbackOffset() {
    return AppRoutes.isTabRoot(currentPath(_router))
        ? 0
        : AppSizes.pinnedActionArea;
  }

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(
      modules: widget.modules,
      readGuard: _readGuard,
      navigatorKey: _navigatorKey,
      refresh: _refresh,
      tabs: widget.tabs,
    );
    _container = ProviderContainer(
      // Automatic retry is off: a failure must reach the user, never repeat
      // silently.
      retry: (retryCount, error) => null,
      overrides: <Override>[
        ...buildAppOverrides(
          services: widget.services,
          modules: widget.modules,
          router: _router,
          navigatorKey: _navigatorKey,
          feedbackBottomOffset: _feedbackOffset,
        ),
        ...widget.overrides,
      ],
    );
    _backDispatcher = AppBackButtonDispatcher(
      router: () => _router,
      guard: _readGuard,
    );
    _guardSubscription = _container.listen<AsyncValue<UserProfile?>>(
      profileProvider,
      (previous, next) {
        if (RouteGuardState.fromProfile(previous ?? const AsyncLoading()) !=
            RouteGuardState.fromProfile(next)) {
          _refresh.notify();
        }
      },
    );
    // The start state, the module statuses and the settings are needed for the
    // whole lifetime of the app: keep them listened to (an unlistened stream
    // provider does not run).
    _keepAlive.addAll(<ProviderSubscription<Object?>>[
      _container.listen<AsyncValue<Object?>>(moduleStatusesProvider, (_, _) {}),
      _container.listen<AsyncValue<Object?>>(appSettingsProvider, (_, _) {}),
    ]);
    unawaited(_prepare());
  }

  /// Everything that has to be true before the first real frame: the reminder
  /// platform is initialized (so a tap on a notification is delivered), the
  /// device zone is known, and the data the router and the theme depend on has
  /// been read (no flash of a wrong theme or screen).
  Future<void> _prepare() async {
    setState(() => _prepareError = null);
    try {
      try {
        await _container.read(reminderPlatformProvider).initialize();
      } on Object catch (error) {
        // Reminders degrade (the settings show the problem); the app starts.
        debugPrint('reminder platform not initialized: ${error.runtimeType}');
      }
      await _container.read(deviceZoneTrackerProvider).refresh();
      await Future.wait<Object?>(<Future<Object?>>[
        _container.read(profileProvider.future),
        _container.read(moduleStatusesProvider.future),
        _container.read(appSettingsProvider.future),
      ]);
      if (!mounted) {
        return;
      }
      final wiring = AppWiring(
        container: _container,
        router: _router,
        guard: _readGuard,
      );
      _wiring = wiring;
      setState(() => _ready = true);
      await wiring.start();
    } on Object catch (error) {
      debugPrint('app preparation failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _prepareError = error);
      }
    }
  }

  void _retryPrepare() {
    _container
      ..invalidate(profileProvider)
      ..invalidate(moduleStatusesProvider)
      ..invalidate(appSettingsProvider);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _guardSubscription?.close();
    for (final subscription in _keepAlive) {
      subscription.close();
    }
    unawaited(_wiring?.dispose());
    _container.dispose();
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    final error = _prepareError;
    if (_ready) {
      content = _AppView(router: _router, backDispatcher: _backDispatcher);
    } else if (error != null) {
      content = bootstrapApp(
        home: BootstrapErrorScreen(error: error, onRetry: _retryPrepare),
      );
    } else {
      content = bootstrapApp(home: const BootstrapLoadingScreen());
    }
    return UncontrolledProviderScope(container: _container, child: content);
  }
}

/// The real app: theme and reduced motion from the settings, German locale,
/// the router and the back button handling.
class _AppView extends ConsumerWidget {
  const _AppView({required this.router, required this.backDispatcher});

  final GoRouter router;
  final AppBackButtonDispatcher backDispatcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    final mode =
        AppThemeMode.tryParse(settings?.themeModeKey) ?? AppThemeMode.system;
    return ReducedMotionScope(
      reduce: settings?.reduceMotion ?? false,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: AppConfig.appName,
        locale: const Locale('de', 'DE'),
        supportedLocales: const <Locale>[Locale('de', 'DE')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // System follows the platform (dark means Dark); OLED only when
        // chosen explicitly (see `themeFor`).
        theme: AppTheme.light(),
        darkTheme: mode == AppThemeMode.oled
            ? AppTheme.oled()
            : AppTheme.dark(),
        themeMode: mode.themeMode,
        routeInformationProvider: router.routeInformationProvider,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        backButtonDispatcher: backDispatcher,
      ),
    );
  }
}
