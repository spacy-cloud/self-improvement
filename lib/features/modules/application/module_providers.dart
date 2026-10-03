import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/data/open_focus_session_source.dart';

/// The modules the app is made of. The default is the fixed bundled set;
/// tests override it with fixture modules.
final appModulesProvider = Provider<List<SelfImprovementModule>>(
  (ref) => bundledModules,
);

final openFocusSessionSourceProvider = Provider<OpenFocusSessionSource>(
  (ref) => OpenFocusSessionSource(ref.watch(appDatabaseProvider)),
);

/// Whether a focus session is open (running, paused, waiting for confirmation).
final openFocusSessionProvider = StreamProvider<bool>(
  (ref) => ref.watch(openFocusSessionSourceProvider).watchOpen(),
);
