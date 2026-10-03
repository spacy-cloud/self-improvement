import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/onboarding/domain/daily_goal_stepper.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_cards.dart';

/// One adjustable daily goal: icon tile, name, period and a stepper.
///
/// Single row at normal text size and enough width; with large text or a
/// narrow screen the stepper moves below the name, so nothing clips and both
/// buttons keep their 48 x 48 tap area.
class GoalStepperRow extends StatelessWidget {
  const GoalStepperRow({
    required this.type,
    required this.icon,
    required this.accent,
    required this.value,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
  });

  final GoalType type;
  final IconData icon;
  final AppAccent accent;

  /// Current target in the unit of [type].
  final int value;

  /// `null` disables plus (maximum reached).
  final VoidCallback? onIncrease;

  /// `null` disables minus (minimum reached).
  final VoidCallback? onDecrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadii.cardBorder,
        border: Border.all(color: colors.borderDecorative),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 52: icon tile and gap, 72: the narrowest useful name column,
            // 8: gap, then the stepper (two 48 px buttons and the value).
            final stepperWidth = 104 + 58 * scale;
            final compact =
                constraints.maxWidth < 52 + 72 * scale + 8 + stepperWidth;
            final label = Semantics(
              container: true,
              label: '${goalTitle(type)}, ${goalPeriod(type)}',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  onboardingIconTile(icon, accent),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          goalTitle(type),
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          goalPeriod(type),
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
            final stepper = QuantityStepper(
              valueText: goalValueText(type, value),
              unit: goalUnitText(type),
              onIncrease: onIncrease,
              onDecrease: onDecrease,
              increaseLabel: goalIncreaseLabel(type),
              decreaseLabel: goalDecreaseLabel(type),
              valueSemanticLabel: goalSpokenValue(type, value),
              valueStyle: AppTextStyles.titleSection,
              expand: true,
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Align(alignment: AlignmentDirectional.centerStart, child: label),
                  const SizedBox(height: AppSpacing.s8),
                  stepper,
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: label),
                const SizedBox(width: AppSpacing.s8),
                SizedBox(width: stepperWidth, child: stepper),
              ],
            );
          },
        ),
      ),
    );
  }
}
