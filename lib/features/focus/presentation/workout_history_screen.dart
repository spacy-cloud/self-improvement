import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_groups.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/features/focus/presentation/workout_widgets.dart';

/// "Alle Trainings": every workout, newest first, grouped by calendar week
/// (Monday to Sunday). The list is built lazily and loads older workouts on
/// request, so a long history never blocks the screen.
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  /// Workouts loaded at once.
  static const int pageSize = 50;

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  var _limit = WorkoutHistoryScreen.pageSize;

  /// The last loaded page: stays visible while a larger page is loading, so
  /// the list does not jump back to the top.
  List<WorkoutEntry>? _shown;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workoutEntriesPageProvider(_limit));
    if (async.hasValue) {
      _shown = async.value;
    }
    final entries = async.value ?? _shown;
    return AppScaffold.subpage(
      title: 'Alle Trainings',
      onBack: () => leaveFocusScreen(context),
      scrollable: false,
      padding: EdgeInsets.zero,
      body: entries == null
          ? async.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: ErrorState(
                  onRetry: () =>
                      ref.invalidate(workoutEntriesPageProvider(_limit)),
                ),
              ),
              data: (_) => const SizedBox.shrink(),
            )
          : entries.isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: EmptyState(
                title: 'Noch kein Training',
                message: 'Hier erscheinen alle deine Trainings.',
                actionLabel: 'Training eintragen',
                onAction: () => context.push(WorkoutRoutes.create),
                icon: AppIcon.workout,
                accent: AppAccent.workout,
              ),
            )
          : _HistoryList(
              entries: entries,
              hasMore: entries.length >= _limit,
              loadingMore: async.isLoading,
              onLoadMore: () =>
                  setState(() => _limit += WorkoutHistoryScreen.pageSize),
            ),
    );
  }
}

sealed class _Item {
  const _Item();
}

final class _Header extends _Item {
  const _Header(this.group);

  final WorkoutWeekGroup group;
}

final class _Week extends _Item {
  const _Week(this.group);

  final WorkoutWeekGroup group;
}

final class _Footer extends _Item {
  const _Footer();
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.entries,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final List<WorkoutEntry> entries;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final today = ref.watch(todayProvider);
    final clock = ref.watch(clockProvider);
    final items = <_Item>[
      for (final group in groupWorkoutsByWeek(entries)) ...[
        _Header(group),
        _Week(group),
      ],
      const _Footer(),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        _Header(:final group) => AppSectionHeader.group(
          title: weekGroupLabel(group.weekStart, today),
        ),
        _Week(:final group) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: AppListGroup(
            children: [
              for (final entry in group.entries)
                WorkoutTile.list(entry: entry, today: today, clock: clock),
            ],
          ),
        ),
        _Footer() => Padding(
          padding: const EdgeInsets.only(top: 4, left: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tippe auf ein Training, um es zu bearbeiten oder zu löschen.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (hasMore) ...[
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Ältere Trainings laden',
                  expand: false,
                  onPressed: loadingMore ? null : onLoadMore,
                ),
              ],
            ],
          ),
        ),
      },
    );
  }
}
