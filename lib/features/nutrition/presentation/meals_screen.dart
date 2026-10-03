import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_format.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_entry_row.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_labels.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// How many more days "Ältere Tage anzeigen" adds to the history window.
const int _historyStepDays = 30;

/// "Ernährung": today's meals with the count and the sum of the KNOWN
/// calories, the meals of earlier days, and the way to add one. A missing
/// calorie value is never shown as 0; there is no rating and no calorie goal.
class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  int _historyDays = defaultMealHistoryDays;

  /// Number of earlier days shown when the window was last extended; when the
  /// extended window shows the same number, there is nothing older.
  int? _earlierBeforeExpand;
  MealHistory? _lastHistory;

  void _retryLoading() {
    ref
      ..invalidate(mealsTodayProvider)
      ..invalidate(mealHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(mealsTodayProvider);
    final history = ref.watch(mealHistoryProvider(_historyDays));
    if (history.hasValue) {
      _lastHistory = history.value;
    }
    final shown = history.value ?? _lastHistory;
    final day = today.value;
    final earlier = [
      for (final past in shown?.daysNewestFirst ?? const <MealDay>[])
        if (day == null || past.date != day.date) past,
    ];
    final historyKnown = shown != null || history.hasError;
    // Nothing at all (today and the whole window): the first-use state with
    // the primary action inside it, no pinned button.
    final isEmpty =
        day != null && day.isEmpty && historyKnown && earlier.isEmpty;

    return AppScaffold.subpage(
      title: 'Ernährung',
      onBack: () => nutritionBackOrHome(context),
      scrollable: false,
      padding: EdgeInsets.zero,
      primaryAction: day == null || isEmpty
          ? null
          : PrimaryButton(
              label: 'Mahlzeit eintragen',
              icon: AppIcon.plus.data,
              onPressed: () => context.push(NutritionRoutes.create),
            ),
      body: today.when(
        loading: () => const SingleChildScrollView(child: NutritionLoading()),
        error: (error, stack) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: ErrorState(onRetry: _retryLoading),
        ),
        data: (day) {
          if (isEmpty) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: EmptyState(
                title: 'Noch keine Mahlzeit',
                message:
                    'Trage eine Mahlzeit ein, wenn du möchtest. Kalorien '
                    'sind freiwillig, ohne Angabe wird nichts geschätzt.',
                icon: AppIcon.meal,
                accent: AppAccent.nutrition,
                actionLabel: 'Mahlzeit eintragen',
                onAction: () => context.push(NutritionRoutes.create),
              ),
            );
          }
          if (!historyKnown && day.isEmpty) {
            return const SingleChildScrollView(child: NutritionLoading());
          }
          return _buildContent(day, earlier, history);
        },
      ),
    );
  }

  Widget _buildContent(
    MealDay day,
    List<MealDay> earlier,
    AsyncValue<MealHistory> history,
  ) {
    final exhausted =
        _earlierBeforeExpand != null &&
        !history.isLoading &&
        earlier.length == _earlierBeforeExpand;
    final colors = context.tokens.colors;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(child: _TodaySection(day: day)),
        ),
        if (history.hasError && _lastHistory == null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: ErrorState(
                onRetry: () => ref.invalidate(mealHistoryProvider),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.builder(
            itemCount: earlier.length,
            itemBuilder: (context, index) =>
                _DaySection(day: earlier[index], today: day.date),
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
                      color: colors.textSecondary,
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

/// The summary of today and today's meals.
class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.day});

  final MealDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(summary: day.summary),
        const SizedBox(height: 16),
        const AppSectionHeader(title: 'Mahlzeiten heute'),
        const SizedBox(height: 8),
        if (day.isEmpty)
          const EmptyState(
            title: 'Heute noch keine Mahlzeit',
            message:
                'Trage eine Mahlzeit ein, wenn du möchtest. Kalorien sind '
                'freiwillig.',
            icon: AppIcon.meal,
            accent: AppAccent.nutrition,
          )
        else
          AppListGroup(
            children: [
              for (final meal in day.entriesNewestFirst)
                MealEntryRow(meal: meal),
            ],
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'Kalorien sind freiwillig. Ohne Angabe wird nichts geschätzt.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Heute": the number of meals and the known calories. Without a single
/// calorie value no calorie figure is shown at all.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MealSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final known = summary.knownKcal;
    final Widget value;
    if (!summary.hasMeals) {
      value = Text(
        'Noch keine Mahlzeit',
        style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
      );
    } else if (known == null) {
      value = Text(
        'Keine Kalorien angegeben',
        style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
      );
    } else {
      value = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: formatThousands(known),
              style: AppTextStyles.displayL.copyWith(color: colors.textPrimary),
            ),
            TextSpan(
              text: ' kcal bekannt',
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconTile(
                      icon: AppIcon.meal.data,
                      accent: AppAccent.nutrition,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Heute',
                      style: AppTextStyles.titleCard.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  formatMealCount(summary.mealCount),
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            value,
            if (summary.isIncomplete) ...[
              const SizedBox(height: 10),
              AppBadge(
                label: mealIncompleteHint(summary),
                icon: AppIcon.info.data,
                accent: AppAccent.nutrition,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One earlier day: its name with the meal summary, then its meals.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.today});

  final MealDay day;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: formatRelativeDay(day.date, today),
            subtitle: mealSummaryText(day.summary),
          ),
          const SizedBox(height: 8),
          AppListGroup(
            children: [
              for (final meal in day.entriesNewestFirst)
                MealEntryRow(meal: meal),
            ],
          ),
        ],
      ),
    );
  }
}
