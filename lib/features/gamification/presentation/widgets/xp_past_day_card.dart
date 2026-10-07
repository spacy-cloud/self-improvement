import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/xp_dashboard_card.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `xp` card of Home for a day that is not today (BS-93): level and XP as
/// they stood at the end of [day], that is the sum of the awards dated on or
/// before it.
///
/// XP and level are a running total, not a value of one day, so the card says
/// which moment its numbers belong to ("Stand am Ende dieses Tages"); awards of
/// later days are not part of it. The card opens the progress page, which shows
/// the present. While the numbers are not read it shows a dash.
class XpPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const XpPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = ref.watch(totalXpThroughProvider(day));
    if (xp.hasError && !xp.isLoading) {
      return ErrorState(
        onRetry: () => ref.invalidate(totalXpThroughProvider(day)),
      );
    }
    final total = xp.value;
    return XpCardBody(
      level: total == null ? null : levelFor(total),
      totalXp: total,
      stand: 'Stand am Ende dieses Tages',
    );
  }
}
