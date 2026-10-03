import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_session_tile.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// "Fokus-Verlauf": every completed session, newest first, grouped by the day
/// of the confirmation. The list is built lazily and loads older sessions on
/// request ("Ältere Sitzungen laden"), so a long history never blocks the
/// screen.
class FocusHistoryScreen extends ConsumerStatefulWidget {
  const FocusHistoryScreen({super.key});

  /// Sessions loaded at once.
  static const int pageSize = 50;

  @override
  ConsumerState<FocusHistoryScreen> createState() => _FocusHistoryScreenState();
}

class _FocusHistoryScreenState extends ConsumerState<FocusHistoryScreen> {
  var _limit = FocusHistoryScreen.pageSize;

  /// The last loaded page: stays visible while a larger page is loading, so
  /// the list does not jump back to the top.
  List<FocusHistoryEntry>? _shown;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(focusHistoryPageProvider(_limit));
    if (async.hasValue) {
      _shown = async.value;
    }
    final entries = async.value ?? _shown;
    return AppScaffold.subpage(
      title: 'Fokus-Verlauf',
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
                      ref.invalidate(focusHistoryPageProvider(_limit)),
                ),
              ),
              data: (_) => const SizedBox.shrink(),
            )
          : entries.isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: EmptyState(
                title: 'Noch keine Sitzung',
                message:
                    'Gespeicherte Fokus-Sitzungen erscheinen hier, sobald du '
                    'eine abgeschlossen hast.',
                actionLabel: 'Fokus starten',
                onAction: () => context.go(FocusRoutes.start),
                icon: AppIcon.focus,
                accent: AppAccent.focus,
              ),
            )
          : _HistoryList(
              entries: entries,
              hasMore: entries.length >= _limit,
              loadingMore: async.isLoading,
              onLoadMore: () =>
                  setState(() => _limit += FocusHistoryScreen.pageSize),
            ),
    );
  }
}

sealed class _Item {
  const _Item();
}

final class _Header extends _Item {
  const _Header(this.date);

  final LocalDate date;
}

final class _Day extends _Item {
  const _Day(this.entries);

  final List<FocusHistoryEntry> entries;
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

  final List<FocusHistoryEntry> entries;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final today = ref.watch(todayProvider);
    final items = <_Item>[
      for (final day in groupFocusHistoryByDay(entries)) ...[
        _Header(day.date),
        _Day(day.entries),
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
        _Header(:final date) => AppSectionHeader.group(
          title: formatRelativeDay(date, today),
        ),
        _Day(:final entries) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: AppListGroup(
            children: [
              for (final entry in entries) FocusSessionTile(entry: entry),
            ],
          ),
        ),
        _Footer() => Padding(
          padding: const EdgeInsets.only(top: 4, left: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tippe auf einen Eintrag, um ihn zu bearbeiten oder zu '
                'löschen.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (hasMore) ...[
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Ältere Sitzungen laden',
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
