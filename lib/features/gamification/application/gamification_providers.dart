import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';

final xpProjectorProvider = Provider<XpProjector>(
  (ref) => XpProjector(ref.watch(appDatabaseProvider)),
);

final gamificationRepositoryProvider = Provider<GamificationRepository>(
  (ref) => GamificationRepository(
    database: ref.watch(appDatabaseProvider),
    xp: ref.watch(xpProjectorProvider),
    status: ref.watch(dayStatusRepositoryProvider),
  ),
);

/// Total XP (sum of valid awards).
final totalXpProvider = StreamProvider<int>(
  (ref) => ref.watch(gamificationRepositoryProvider).watchTotalXp(),
);

/// XP, level and the three badges for the progress page and dashboard card.
final gamificationSummaryProvider = StreamProvider<GamificationSummary>(
  (ref) => ref.watch(gamificationRepositoryProvider).watchSummary(),
);

/// A level reached by a just-committed activity.
@immutable
final class LevelUp {
  const LevelUp({required this.level, required this.xpAfter});

  final int level;
  final int xpAfter;
}

/// Emits a [LevelUp] only when a committed change crosses a level boundary.
///
/// It listens to the post-commit events, so it never fires again after an app
/// restart and a retry or screen rebuild can not trigger it. XP removed by a
/// correction never emits one.
final levelUpProvider = StreamProvider<LevelUp>((ref) {
  final controller = StreamController<LevelUp>();
  final subscription = ref.watch(commandEventsProvider).stream.listen((event) {
    if (event is ActivityCommitted && event.xpAfter > event.xpBefore) {
      final before = levelFor(event.xpBefore).level;
      final after = levelFor(event.xpAfter).level;
      if (after > before) {
        controller.add(LevelUp(level: after, xpAfter: event.xpAfter));
      }
    }
  });
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
