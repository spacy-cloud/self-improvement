import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';

/// One completed session as a list row: category, time and state, the saved
/// duration and a chevron. Tapping opens the session (note, delete).
class FocusSessionTile extends StatelessWidget {
  const FocusSessionTile({required this.entry, super.key});

  final FocusHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final spoken =
        '${entry.categoryLabel}, ${entry.endedLocalTime.toIso()} Uhr, '
        '${entry.status.label}, ${spokenDuration(entry.actualSeconds)}. '
        'Tippen zum Bearbeiten';
    return EntryListTile(
      title: entry.categoryLabel,
      subtitle: entry.subtitle,
      icon: AppIcon.focus.data,
      accent: AppAccent.focus,
      semanticLabel: spoken,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              entry.actualDurationText,
              textAlign: TextAlign.end,
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            AppIcon.chevronRight.data,
            size: 20,
            color: colors.textSecondary,
          ),
        ],
      ),
      onTap: () => context.push(FocusRoutes.historyDetail(entry.id)),
    );
  }
}
