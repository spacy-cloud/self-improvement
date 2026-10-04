import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';

/// Runs the lifecycle of the bundled modules (specification: idempotent
/// lifecycle, `dispose` ends resources and deletes no data):
///
/// - `initialize` runs once for every module that is active at the start and
///   once whenever a module is switched on again;
/// - `dispose` runs when a module is switched off and for every active module
///   when the app ends;
/// - the calls are serialized, so a module never sees two lifecycle calls at
///   once, and a failing module is logged by type only and never stops the
///   others.
///
/// Nothing here touches persisted data.
final class ModuleLifecycle {
  ModuleLifecycle(this._ref) : _modules = _ref.read(appModulesProvider);

  final Ref _ref;
  final List<SelfImprovementModule> _modules;
  final Set<ModuleId> _active = <ModuleId>{};
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  /// Follows the module statuses (and applies the current one right away).
  void start() {
    _ref.listen<AsyncValue<Map<ModuleId, bool>>>(moduleStatusesProvider, (
      previous,
      next,
    ) {
      final statuses = next.value;
      if (statuses != null) {
        _queue = _queue.then((_) => _apply(statuses));
      }
    }, fireImmediately: true);
  }

  Future<void> _apply(Map<ModuleId, bool> statuses) async {
    for (final module in _modules) {
      if (_disposed) {
        return;
      }
      final enabled = statuses[module.id] ?? true;
      final active = _active.contains(module.id);
      if (enabled && !active) {
        _active.add(module.id);
        try {
          await module.initialize(_ref);
        } on Object catch (error) {
          debugPrint(
            'module ${module.id.key} initialize failed: '
            '${error.runtimeType}',
          );
        }
      } else if (!enabled && active) {
        _active.remove(module.id);
        _release(module);
      }
    }
  }

  void _release(SelfImprovementModule module) {
    try {
      module.dispose();
    } on Object catch (error) {
      debugPrint(
        'module ${module.id.key} dispose failed: ${error.runtimeType}',
      );
    }
  }

  /// Ends the resources of every active module.
  void dispose() {
    _disposed = true;
    for (final module in _modules) {
      if (_active.remove(module.id)) {
        _release(module);
      }
    }
  }
}

/// The module lifecycle. Read it once at the app root after the start.
final moduleLifecycleProvider = Provider<ModuleLifecycle>((ref) {
  final lifecycle = ModuleLifecycle(ref);
  ref.onDispose(lifecycle.dispose);
  return lifecycle..start();
});
