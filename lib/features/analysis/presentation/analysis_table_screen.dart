import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/analysis_table.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_views.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';

/// "Analyse als Tabelle" (Figma 4056:421): the accessible alternative to the
/// cards and charts. It shows the same figures with the same formulas as rows
/// of current period, previous period, change and basis, the workout week and
/// the values of every day. A screen reader reads it row by row.
///
/// The screen reads the report of the period that is selected on the analysis
/// tab, so the table never shows other numbers than the cards.
class AnalysisTableScreen extends ConsumerWidget {
  const AnalysisTableScreen({super.key});

  /// Pushes the table over the tab (without the bottom navigation, as in the
  /// design). It is an ordinary pushed page: Android back closes it.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'analysis-table'),
        builder: (context) => const AnalysisTableScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analysisReportProvider);
    final report = async.value;
    final Widget body;
    if (async.hasError && !async.isLoading) {
      body = ErrorState(onRetry: () => ref.invalidate(analysisReportProvider));
    } else if (report == null) {
      body = const _Loading();
    } else {
      body = _TableContent(report: report);
    }
    return AppScaffold.subpage(title: 'Analyse als Tabelle', body: body);
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

class _TableContent extends StatelessWidget {
  const _TableContent({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final table = report.table;
    if (!report.hasAnalysedModule || !report.hasCards) {
      return EmptyState(
        title: 'Noch keine Tabelle',
        message:
            'Sobald ein Modul aktiv ist, steht hier die Tabelle deiner '
            'Auswertung.',
        icon: AppIcon.info,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Semantics(
            container: true,
            header: true,
            child: Text(table.periodTable.caption, style: secondary),
          ),
        ),
        if (report.comparisonNote != null) ...<Widget>[
          const SizedBox(height: 8),
          AnalysisNote(text: report.comparisonNote!),
        ],
        const SizedBox(height: 12),
        if (table.periodTable.rows.isNotEmpty)
          AppCard(
            child: AnalysisFigureTableView(
              table: table.periodTable,
              hiddenReason: report.comparisonBaseProblem,
            ),
          ),
        if (table.weekTable != null) ...<Widget>[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Semantics(
              container: true,
              header: true,
              child: Text(table.weekTable!.caption, style: secondary),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: AnalysisFigureTableView(
              table: table.weekTable!,
              hiddenReason: report.comparisonBaseProblem,
            ),
          ),
        ],
        if (table.dayTable.headers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _DayTableCard(table: table.dayTable),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'Die Tabelle ist die zugängliche Alternative zu den Diagrammen '
            'und wird vom Screenreader zeilenweise vorgelesen.',
            style: secondary,
          ),
        ),
      ],
    );
  }
}

/// The per-day table behind a toggle: up to 90 blocks would otherwise push the
/// footnote far down. The toggle is a 48 px button that announces whether the
/// table is shown.
class _DayTableCard extends StatefulWidget {
  const _DayTableCard({required this.table});

  final AnalysisDayTable table;

  @override
  State<_DayTableCard> createState() => _DayTableCardState();
}

class _DayTableCardState extends State<_DayTableCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final label = _expanded
        ? 'Werte pro Tag ausblenden'
        : 'Werte pro Tag anzeigen';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            container: true,
            header: true,
            child: Text(
              'Werte pro Tag',
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.table.caption,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            button: true,
            expanded: _expanded,
            label: label,
            onTap: () => setState(() => _expanded = !_expanded),
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
              child: Material(
                color: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.controlBorder,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  customBorder: const RoundedRectangleBorder(
                    borderRadius: AppRadii.controlBorder,
                  ),
                  focusColor: colors.focus.withValues(alpha: 0.2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            label,
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? AppIcon.collapse.data
                              : AppIcon.expand.data,
                          color: colors.primaryText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_expanded) AnalysisDayTableView(table: widget.table),
        ],
      ),
    );
  }
}
