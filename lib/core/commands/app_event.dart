import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// Typed UI events, published only AFTER the database commit.
///
/// Database streams are authoritative; losing an event never loses business
/// data or XP. Events exist for transient feedback (animations, snackbars).
@immutable
sealed class AppEvent {
  const AppEvent();
}

/// A fact was created or changed.
final class ActivityCommitted extends AppEvent {
  const ActivityCommitted({
    required this.commandType,
    this.entityId,
    this.xpBefore = 0,
    this.xpAfter = 0,
  });

  final String commandType;
  final String? entityId;

  /// Total XP before and after the commit (equal if nothing was awarded).
  final int xpBefore;
  final int xpAfter;
}

/// A fact was removed or reverted (delete, undo).
final class ActivityRemoved extends AppEvent {
  const ActivityRemoved({
    required this.commandType,
    this.entityId,
    this.xpBefore = 0,
    this.xpAfter = 0,
  });

  final String commandType;
  final String? entityId;
  final int xpBefore;
  final int xpAfter;
}

/// Goal versions or snapshots changed.
final class GoalsChanged extends AppEvent {
  const GoalsChanged();
}

/// A module was activated or deactivated.
final class ModulesChanged extends AppEvent {
  const ModulesChanged(this.module, {required this.enabled});

  final ModuleId module;
  final bool enabled;
}

/// The focus session state changed (start, pause, resume, finish, discard).
final class FocusStateChanged extends AppEvent {
  const FocusStateChanged();
}
