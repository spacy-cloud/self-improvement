import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_chart_section.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_goals_card.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_metric_card.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_screen.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_week_card.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';

/// Route of the module manager (the way out of the "no module active" state).
const String analysisModulesRoute = '/settings/modules';

/// The "Analyse" tab (Figma 4033:2): the period selector (7, 30 or 90 local
/// calendar days including today), the comparison with the equally long period
/// directly before it, the daily goals hero, the metric cards of the ACTIVE
/// modules, the separate workout week card and one chart with a text summary
/// and a table per series. "Als Tabelle" opens the full table (4056:421).
///
/// The screen reads only the analysis report provider; nothing is computed in
/// a widget and nothing is invented: without data it says so, without a fitting
/// base it says "Noch kein Vergleich". The selected period lives in a provider,
/// so it survives rotation and a rebuilt widget tree.
class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final length = ref.watch(analysisPeriodProvider);
    final spec = ref.watch(analysisPeriodSpecProvider);
    final async = ref.watch(analysisReportProvider);
    final report = async.value;

    final Widget body;
    if (async.hasError && !async.isLoading) {
      body = _WithSelector(
        length: length,
        child: ErrorState(
          onRetry: () => ref.invalidate(analysisReportProvider),
        ),
      );
    } else if (report == null) {
      body = _WithSelector(length: length, child: const _Loading());
    } else if (report.noModuleActive) {
      body = const _NoModules();
    } else {
      body = _Loaded(
        report: report,
        length: length,
        stale: report.period != spec,
      );
    }
    return AppScaffold(title: 'Analyse', safeAreaBottom: false, body: body);
  }
}

class _WithSelector extends StatelessWidget {
  const _WithSelector({required this.length, required this.child});

  final AnalysisPeriodLength length;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PeriodSelector(length: length),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.length});

  final AnalysisPeriodLength length;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PeriodSelector<AnalysisPeriodLength>(
      options: <PeriodOption<AnalysisPeriodLength>>[
        for (final option in AnalysisPeriodLength.values)
          PeriodOption<AnalysisPeriodLength>(
            value: option,
            label: option.label,
            semanticLabel: option.semanticsLabel,
          ),
      ],
      selected: length,
      semanticLabel: 'Zeitraum',
      onChanged: (value) =>
          ref.read(analysisPeriodProvider.notifier).select(value),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          'Wird geladen …',
          style: AppTextStyles.bodyRegular.copyWith(
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// All modules are off: nothing can be analysed. The state says so and offers
/// the way to the module manager.
class _NoModules extends StatelessWidget {
  const _NoModules();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Keine Module aktiv',
      message:
          'Aktiviere mindestens ein Modul, damit hier deine Auswertung '
          'erscheint. Bereits erfasste Daten bleiben erhalten.',
      actionLabel: 'Module verwalten',
      onAction: () => context.push(analysisModulesRoute),
      icon: AppIcon.modules,
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.report,
    required this.length,
    required this.stale,
  });

  final AnalysisReport report;
  final AnalysisPeriodLength length;

  /// Whether the report is still the one of the previous selection while the
  /// new one loads.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final goals = report.cardFor(AnalysisMetric.dailyGoals);
    final cards = <AnalysisMetric, Widget>{
      for (final card in report.cards)
        if (card.metric != AnalysisMetric.dailyGoals)
          card.metric: AnalysisMetricCard(card: card),
    };
    final grid = <Widget>[
      for (final metric in analysisGridOrder)
        if (cards[metric] != null) cards[metric]!,
    ];

    final Widget content;
    if (!report.hasAnyData) {
      content = EmptyState(
        title: 'Noch keine Daten',
        message:
            'In ${length.currentTitle.toLowerCase()} wurde noch nichts '
            'erfasst. Sobald du Einträge hast, siehst du hier deine '
            'Auswertung und den Vergleich mit den vorherigen '
            '${length.days} Tagen.',
        icon: AppIcon.sprout,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (goals != null) ...<Widget>[
            AnalysisGoalsCard(
              card: goals,
              completeDays: report.current.goals.completeDays,
              daysWithGoals: report.current.goals.daysWithGoals,
              goalDays: report.goalDays,
              today: report.period.today,
            ),
            const SizedBox(height: 12),
          ],
          if (grid.isNotEmpty) AdaptiveGrid(minCellWidth: 150, children: grid),
          if (report.workoutWeek != null) ...<Widget>[
            const SizedBox(height: 12),
            AnalysisWeekCard(week: report.workoutWeek!),
          ],
          const SizedBox(height: 16),
          AnalysisChartSection(report: report),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PeriodSelector(length: length),
        const SizedBox(height: 8),
        _PeriodHeader(report: report),
        const SizedBox(height: 8),
        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Wird aktualisiert …',
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        Opacity(opacity: stale ? 0.5 : 1, child: content),
      ],
    );
  }
}

/// Under the selector: the dates of the period (`27.09. bis 03.10.2026,
/// inklusive heute`), the link to the table, the comparison base with its dates
/// and, when comparisons are not possible yet, when they will be.
class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final period = Semantics(
      container: true,
      label: report.period.semanticsLabel,
      excludeSemantics: true,
      child: Text(report.periodText, style: secondary),
    );
    final link = AnalysisLinkAction(
      label: 'Als Tabelle',
      semanticLabel: 'Analyse als Tabelle öffnen',
      onPressed: () => AnalysisTableScreen.open(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (useStackedLayout(context))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[period, link],
          )
        else
          Row(
            children: <Widget>[
              Expanded(child: period),
              const SizedBox(width: 8),
              link,
            ],
          ),
        Text(report.previousPeriodText, style: secondary),
        if (report.comparisonNote != null) ...<Widget>[
          const SizedBox(height: 8),
          AnalysisNote(text: report.comparisonNote!),
        ],
      ],
    );
  }
}
