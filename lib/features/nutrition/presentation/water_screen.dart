import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/features/nutrition/presentation/water_custom_sheet.dart';
import 'package:self_improvement/features/nutrition/presentation/water_entry_row.dart';
import 'package:self_improvement/features/nutrition/presentation/water_goal_sheet.dart';
import 'package:self_improvement/features/nutrition/presentation/water_labels.dart';
import 'package:self_improvement/features/nutrition/presentation/water_quick_add.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// How many more days "Ältere Tage anzeigen" adds to the history window.
const int _historyStepDays = 30;

/// "Wasser eintragen": the ONE water screen. Day total with the progress ring,
/// the quick add (250 / 500 ml, "Eigene Menge"), the daily goal and the history
/// of today and earlier days with edit, delete and undo.
class WaterScreen extends ConsumerStatefulWidget {
  const WaterScreen({super.key});

  @override
  ConsumerState<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends ConsumerState<WaterScreen> {
  int _historyDays = defaultWaterHistoryDays;

  /// Number of earlier days shown when the window was last extended; when the
  /// extended window shows the same number, there is nothing older.
  int? _earlierBeforeExpand;
  WaterHistory? _lastHistory;

  void _retryLoading() {
    ref
      ..invalidate(waterTodayProvider)
      ..invalidate(waterHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(waterTodayProvider);
    return AppScaffold.subpage(
      title: 'Wasser eintragen',
      onBack: () => nutritionBackOrHome(context),
      scrollable: false,
      padding: EdgeInsets.zero,
      primaryAction: PrimaryButton(
        label: 'Fertig',
        onPressed: () => leaveNutritionScreen(context),
      ),
      body: today.when(
        loading: () => const SingleChildScrollView(child: NutritionLoading()),
        error: (error, stack) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: ErrorState(onRetry: _retryLoading),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(WaterToday model) {
    final history = ref.watch(waterHistoryProvider(_historyDays));
    if (history.hasValue) {
      _lastHistory = history.value;
    }
    final shown = history.value ?? _lastHistory;
    final earlier = [
      for (final day in shown?.daysNewestFirst ?? const <WaterHistoryDay>[])
        if (day.date != model.date) day,
    ];
    final exhausted =
        _earlierBeforeExpand != null &&
        !history.isLoading &&
        earlier.length == _earlierBeforeExpand;
    final todayDate = model.date;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(child: _TopSection(model: model)),
        ),
        if (history.hasError && shown == null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: ErrorState(
                onRetry: () => ref.invalidate(waterHistoryProvider),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.builder(
            itemCount: earlier.length,
            itemBuilder: (context, index) =>
                _DaySection(day: earlier[index], today: todayDate),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverToBoxAdapter(
            child: exhausted
                ? Text(
                    'Keine älteren Einträge.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: context.tokens.colors.textSecondary,
                    ),
                  )
                : Align(
                    child: SecondaryButton(
                      label: 'Ältere Tage anzeigen',
                      expand: false,
                      onPressed: () => setState(() {
                        _earlierBeforeExpand = earlier.length;
                        _historyDays += _historyStepDays;
                      }),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Everything above the earlier days: summary, quick add, goal and today's
/// entries.
class _TopSection extends ConsumerWidget {
  const _TopSection({required this.model});

  final WaterToday model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(waterGoalSettingsProvider).value;
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(model: model),
        const SizedBox(height: 12),
        const WaterQuickAddFailureNotice(),
        const AppSectionHeader(
          title: 'Schnell hinzufügen',
          subtitle: 'Ein Tippen genügt – wird sofort gespeichert.',
        ),
        const SizedBox(height: 8),
        AdaptiveGrid(
          children: [
            for (final amount in waterQuickAmountsMl)
              _QuickTile(
                title: waterQuickLabel(amount),
                subtitle: formatWaterMl(amount),
                icon: amount == waterQuickAmountsMl.first
                    ? Icons.local_drink_outlined
                    : Icons.water_drop_outlined,
                semanticLabel: waterQuickSemanticLabel(amount),
                onTap: () => runWaterQuickAdd(ref, amount),
              ),
            _QuickTile(
              title: 'Eigene Menge',
              subtitle: 'frei wählen',
              icon: AppIcon.plus.data,
              semanticLabel: 'Eigene Menge, frei wählen',
              onTap: () => showWaterCustomSheet(context),
            ),
          ],
        ),
        if (settings != null) ...[
          const SizedBox(height: 12),
          AppListGroup(
            children: [
              EntryListTile.chevron(
                title: 'Tagesziel',
                subtitle: waterGoalSubtitle(settings),
                icon: Icons.flag_outlined,
                accent: AppAccent.water,
                semanticLabel:
                    'Tagesziel ändern. ${waterGoalSubtitle(settings)}',
                onTap: () => showWaterGoalSheet(context, settings),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(child: AppSectionHeader(title: 'Heute getrunken')),
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: Text(
                formatEntryCount(model.entryCount),
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (model.isEmpty)
          const EmptyState(
            title: 'Noch nichts getrunken',
            message:
                'Tippe oben auf eine Menge. Sie wird sofort gespeichert und '
                'erscheint hier.',
            icon: AppIcon.water,
            accent: AppAccent.water,
          )
        else
          AppListGroup(
            children: [
              for (final entry in model.entriesNewestFirst)
                WaterEntryRow(entry: entry, today: model.date),
            ],
          ),
      ],
    );
  }
}

/// The progress ring with the real total, the target and what is missing. The
/// ring is capped at 100 %, the numbers are the real ones (112 % stays 112 %).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.model});

  final WaterToday model;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final target = model.targetMl;
    final percent = model.percent;
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 280;
          final ring = ProgressRing(
            value: model.fraction ?? 0,
            size: compact ? 88 : 110,
            strokeWidth: compact ? 9 : 11,
            color: colors.moduleWaterChart,
            semanticLabel: waterProgressLabel(model),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  percent == null ? '–' : formatWaterPercent(percent),
                  style: AppTextStyles.titleCard.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  percent == null ? 'kein Ziel' : 'vom Ziel',
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
          final details = MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Heute',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatLiters(model.totalMl),
                        style: AppTextStyles.displayL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: target == null
                            ? ' l'
                            : ' / ${formatWaterLiters(target)}',
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _StatusBadge(model: model),
              ],
            ),
          );
          if (scale > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ring,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: details),
              ],
            );
          }
          return Row(
            children: [
              ring,
              SizedBox(width: compact ? 12 : 16),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.model});

  final WaterToday model;

  @override
  Widget build(BuildContext context) {
    final remaining = model.remainingMl;
    if (model.targetMl == null || remaining == null) {
      return Text(
        'Kein Tagesziel aktiv',
        style: AppTextStyles.captionDefault.copyWith(
          color: context.tokens.colors.textSecondary,
        ),
      );
    }
    if (model.goalReached) {
      return AppBadge(
        label: 'Tagesziel erreicht',
        icon: AppIcon.check.data,
        accent: AppAccent.primary,
      );
    }
    return AppBadge(
      label: 'Noch ${formatWaterLiters(remaining)} bis zum Ziel',
      accent: AppAccent.water,
    );
  }
}

/// One quick add tile: one tap, one new entry.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      onTap: onTap,
      semanticLabel: semanticLabel,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AppIconTile(icon: icon, accent: AppAccent.water),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One earlier day: its name and total, then its entries.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.today});

  final WaterHistoryDay day;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final target = day.targetMl;
    final total = target == null
        ? formatWaterLiters(day.totalMl)
        : '${formatWaterLiters(day.totalMl)} von ${formatWaterLiters(target)}';
    final summary = [
      total,
      formatEntryCount(day.entryCount),
      if (day.goalReached) 'Ziel erreicht',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: formatRelativeDay(day.date, today),
            subtitle: summary,
          ),
          const SizedBox(height: 8),
          AppListGroup(
            children: [
              for (final entry in day.entriesNewestFirst)
                WaterEntryRow(entry: entry, today: today),
            ],
          ),
        ],
      ),
    );
  }
}
