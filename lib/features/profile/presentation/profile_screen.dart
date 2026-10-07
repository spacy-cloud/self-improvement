import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/application/profile_providers.dart';
import 'package:self_improvement/features/profile/domain/profile_formatting.dart';
import 'package:self_improvement/features/profile/domain/profile_overview.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/profile/presentation/profile_widgets.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The profile tab (Figma `4007:2`): name and initials, start date, streak and
/// weight change, the goals at a glance and the optional body data. Everything
/// comes from real data; a value that was never entered is simply not shown.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(profileOverviewProvider);
    return AppScaffold(
      title: 'Profil',
      safeAreaBottom: false,
      actions: [
        AppIconButton(
          icon: AppIcon.settings.data,
          semanticLabel: 'Einstellungen',
          filled: true,
          onPressed: () => context.push(SettingsRoutes.settings),
        ),
      ],
      body: overview.when(
        loading: () => const SizedBox(height: 160),
        error: (error, stack) =>
            ErrorState(onRetry: () => retryProfileOverview(ref)),
        data: (data) => _ProfileContent(overview: data),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.overview});

  final ProfileOverview overview;

  @override
  Widget build(BuildContext context) {
    final level = overview.level;
    final totalXp = overview.totalXp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentityCard(overview: overview),
        if (overview.showGamification) ...[
          const SizedBox(height: 12),
          AppListGroup(
            children: [
              EntryListTile.chevron(
                title: 'Fortschritt',
                subtitle: level == null || totalXp == null
                    ? 'Level, Punkte und Abzeichen'
                    : 'Level ${level.level} · ${formatThousands(totalXp)} XP',
                icon: AppIcon.trophy.data,
                accent: AppAccent.gamification,
                onTap: () => context.push(ProfileRoutes.progress),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        AppSectionHeader(
          title: 'Meine Ziele',
          actionLabel: 'Bearbeiten',
          actionSemanticLabel: 'Ziele bearbeiten',
          onAction: () => context.push(ProfileRoutes.goals),
        ),
        const SizedBox(height: 8),
        if (overview.goals.isEmpty)
          EmptyState(
            title: 'Keine Ziele sichtbar',
            message:
                'Ziele gehören zu den Modulen. Schalte ein Modul ein, '
                'dann siehst du seine Ziele hier.',
            actionLabel: 'Module verwalten',
            onAction: () => context.push(SettingsRoutes.modules),
          )
        else
          AppListGroup(
            children: [
              for (final goal in overview.goals) _GoalTile(goal: goal),
            ],
          ),
        if (overview.showBody && overview.hasBodyData) ...[
          const SizedBox(height: 20),
          const AppSectionHeader(title: 'Körperdaten'),
          const SizedBox(height: 8),
          _BodyDataCard(overview: overview),
        ],
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.overview});

  final ProfileOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final streak = overview.streak;
    final sinceStart = overview.sinceStartGrams;
    final stats = <_Stat>[
      if (streak != null) ...[
        _Stat(
          value: '${streak.current}',
          label: streak.current == 1 ? 'Tag Streak' : 'Tage Streak',
          spoken:
              '${streak.current} ${streak.current == 1 ? 'Tag' : 'Tage'} '
              'Streak, Details ansehen',
          color: colors.streakText,
          onTap: () => context.push(ProfileRoutes.streak),
        ),
        _Stat(
          value: '${streak.activeDays}',
          label: streak.activeDays == 1 ? 'Aktiver Tag' : 'Aktive Tage',
          spoken:
              '${streak.activeDays} '
              '${streak.activeDays == 1 ? 'aktiver Tag' : 'aktive Tage'}',
        ),
      ],
      if (sinceStart != null)
        _Stat(
          value: formatSignedWeightKg(sinceStart),
          label: 'seit Start',
          spoken: '${formatSignedWeightKg(sinceStart)} Gewicht seit Start',
        ),
    ];
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > AppSizes.stackTextScale;
    final editButton = AppIconButton(
      icon: AppIcon.edit.data,
      semanticLabel: 'Profil bearbeiten',
      iconColor: colors.primaryText,
      onPressed: () => context.push(ProfileRoutes.edit),
    );
    final names = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          overview.name,
          style: AppTextStyles.titleSection.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          overview.memberSince,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // With large text the name gets the full width below the picture,
          // instead of a sliver between picture and edit button.
          if (stacked) ...[
            Row(
              children: [
                ProfileAvatar(initials: overview.initials),
                const Spacer(),
                editButton,
              ],
            ),
            const SizedBox(height: 12),
            names,
          ] else
            Row(
              children: [
                ProfileAvatar(initials: overview.initials),
                const SizedBox(width: 16),
                Expanded(child: names),
                editButton,
              ],
            ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            _StatBlock(stats: stats, muted: true),
          ],
        ],
      ),
    );
  }
}

/// One goal of the summary: icon, title and value, opening the goal editor.
///
/// Title and value share one line while the text is of normal size (as in the
/// design); with large text the value moves below the title, so nothing is
/// clipped and the row keeps its 56 px height at least.
class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});

  final ProfileGoalLine goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final (icon, accent) = switch (goal.kind) {
      ProfileGoalKind.water => (AppIcon.water, AppAccent.water),
      ProfileGoalKind.steps => (AppIcon.steps, AppAccent.steps),
      ProfileGoalKind.focusMinutes => (AppIcon.focus, AppAccent.focus),
      ProfileGoalKind.weightEntry => (AppIcon.weight, AppAccent.weight),
      ProfileGoalKind.taskCompletion => (AppIcon.task, AppAccent.habits),
      ProfileGoalKind.workoutWeekly => (AppIcon.workout, AppAccent.workout),
      ProfileGoalKind.workoutDaily => (AppIcon.workout, AppAccent.workout),
      ProfileGoalKind.targetWeight => (AppIcon.weight, AppAccent.weight),
    };
    final pending = goal.pending;
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > AppSizes.stackTextScale;
    void open() => context.push(ProfileRoutes.goals);
    return Semantics(
      container: true,
      button: true,
      label:
          '${goal.title}, ${goal.value}${pending == null ? '' : ', $pending'}'
          ', bearbeiten',
      onTap: open,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.listRowMinHeight),
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  AppIconTile(icon: icon.data, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: AppTextStyles.bodyDefault.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        if (stacked)
                          Text(
                            goal.value,
                            style: AppTextStyles.bodyRegular.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        if (pending != null)
                          Text(
                            pending,
                            style: AppTextStyles.captionDefault.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.5,
                      ),
                      child: Text(
                        goal.value,
                        textAlign: TextAlign.end,
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    AppIcon.chevronRight.data,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyDataCard extends StatelessWidget {
  const _BodyDataCard({required this.overview});

  final ProfileOverview overview;

  @override
  Widget build(BuildContext context) {
    final height = overview.heightCm;
    final start = overview.startWeightGrams;
    final age = overview.ageYears;
    return AppCard(
      padding: const EdgeInsets.all(8),
      child: _StatBlock(
        muted: false,
        stats: [
          if (height != null)
            _Stat(
              value: '$height cm',
              label: 'Größe',
              spoken: 'Größe $height Zentimeter',
            ),
          if (start != null)
            _Stat(
              value: formatWeightKg(start),
              label: 'Startgewicht',
              spoken: 'Startgewicht ${formatWeightKg(start)}',
            ),
          if (age != null)
            _Stat(value: '$age J.', label: 'Alter', spoken: 'Alter $age Jahre'),
        ],
      ),
    );
  }
}

/// One figure of a [_StatBlock]: a value with its label, optionally a link.
class _Stat {
  const _Stat({
    required this.value,
    required this.label,
    required this.spoken,
    this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final String spoken;
  final Color? color;
  final VoidCallback? onTap;
}

/// Figures side by side with hairline dividers; below each other on large text
/// or narrow screens, so nothing is clipped.
class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.stats, required this.muted});

  final List<_Stat> stats;

  /// Whether the block sits on the muted surface (inside the identity card).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final divider = colors.borderDecorative;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted ? colors.surfaceMuted : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              scale > AppSizes.stackTextScale ||
              constraints.maxWidth / stats.length < 96;
          if (stacked) {
            return Column(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: divider),
                  _StatCell(stat: stats[i]),
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0)
                    VerticalDivider(width: 1, thickness: 1, color: divider),
                  Expanded(child: _StatCell(stat: stats[i])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final cell = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              stat.value,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSection.copyWith(
                color: stat.color ?? colors.textPrimary,
              ),
            ),
            Text(
              stat.label,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    final onTap = stat.onTap;
    return Semantics(
      container: true,
      button: onTap != null,
      label: stat.spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? cell
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: cell,
            ),
    );
  }
}
