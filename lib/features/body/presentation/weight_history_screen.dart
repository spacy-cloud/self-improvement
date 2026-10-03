import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/presentation/weight_labels.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Alle Messungen": every active measurement, newest first, grouped by month.
/// Rows are built lazily, so thousands of entries scroll without blocking.
class WeightHistoryScreen extends ConsumerWidget {
  const WeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(weightEntriesProvider);
    return AppScaffold.subpage(
      title: 'Alle Messungen',
      onBack: () => leaveWeightScreen(context),
      scrollable: false,
      padding: EdgeInsets.zero,
      body: entries.when(
        loading: () => const SizedBox.shrink(),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: ErrorState(
            onRetry: () => ref.invalidate(weightEntriesProvider),
          ),
        ),
        data: (list) => list.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: EmptyState(
                  title: 'Noch keine Messung',
                  message: 'Hier erscheinen alle deine Messungen.',
                  actionLabel: 'Gewicht eintragen',
                  onAction: () => context.push(WeightRoutes.create),
                ),
              )
            : _HistoryList(entries: list),
      ),
    );
  }
}

/// How a row sits in the card of its month.
enum _Slot { only, first, middle, last }

sealed class _Item {
  const _Item();
}

final class _Header extends _Item {
  const _Header(this.label);

  final String label;
}

final class _Row extends _Item {
  const _Row(this.entry, this.delta, this.slot, this.isStart);

  final WeightEntry entry;
  final int? delta;
  final _Slot slot;
  final bool isStart;
}

final class _Footer extends _Item {
  const _Footer();
}

/// Flattens the entries into headers, rows and the footer hint.
List<_Item> _buildItems(List<WeightEntry> newestFirst, int? startGrams) {
  final deltas = deltasToPrevious([
    for (final entry in newestFirst)
      WeightSample(
        id: entry.id,
        occurredAtUtc: entry.occurredAtUtc,
        localDate: entry.localDate,
        grams: entry.weightGrams,
      ),
  ]);
  final oldestId = newestFirst.last.id;
  final items = <_Item>[];
  var index = 0;
  while (index < newestFirst.length) {
    final first = newestFirst[index].localDate;
    var end = index;
    while (end + 1 < newestFirst.length &&
        newestFirst[end + 1].localDate.year == first.year &&
        newestFirst[end + 1].localDate.month == first.month) {
      end++;
    }
    items.add(_Header('${monthLong(first.month)} ${first.year}'));
    for (var i = index; i <= end; i++) {
      final entry = newestFirst[i];
      final slot = index == end
          ? _Slot.only
          : i == index
          ? _Slot.first
          : i == end
          ? _Slot.last
          : _Slot.middle;
      items.add(
        _Row(
          entry,
          deltas[entry.id],
          slot,
          startGrams != null &&
              entry.id == oldestId &&
              entry.weightGrams == startGrams,
        ),
      );
    }
    index = end + 1;
  }
  items.add(const _Footer());
  return items;
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final startGrams = ref.watch(profileProvider).value?.startWeightGrams;
    final today = ref.watch(todayProvider);
    final items = _buildItems(entries, startGrams);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        _Header(:final label) => AppSectionHeader.group(title: label),
        _Row(:final entry, :final delta, :final slot, :final isStart) =>
          _HistoryRow(
            entry: entry,
            time: weightEntryTime(clock, entry),
            today: today,
            delta: delta,
            slot: slot,
            isStart: isStart,
          ),
        _Footer() => Padding(
          padding: const EdgeInsets.only(top: 12, left: 6),
          child: Text(
            'Tippe auf einen Eintrag, um ihn zu bearbeiten oder zu löschen.',
            style: AppTextStyles.captionDefault.copyWith(
              color: context.tokens.colors.textSecondary,
            ),
          ),
        ),
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.time,
    required this.today,
    required this.delta,
    required this.slot,
    required this.isStart,
  });

  final WeightEntry entry;
  final String time;
  final LocalDate today;
  final int? delta;
  final _Slot slot;
  final bool isStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = formatDateShort(entry.localDate, contextYear: today.year);
    final meta = weightMetaLine(time, entry, isStart: isStart);
    final value = '${formatKilograms(entry.weightGrams)} kg';
    final isFirst = slot == _Slot.first || slot == _Slot.only;
    final isLast = slot == _Slot.last || slot == _Slot.only;
    return CustomPaint(
      painter: _SlicePainter(
        fill: colors.surface,
        border: colors.borderDecorative,
        divider: colors.track,
        radius: AppRadii.card,
        first: isFirst,
        last: isLast,
      ),
      child: EntryListTile(
        title: title,
        subtitle: meta,
        semanticLabel:
            '$title, $meta, $value'
            '${delta == null ? '' : ', ${weightDeltaSpoken(delta!)}'}. '
            'Tippen zum Bearbeiten',
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
            if (delta != null)
              Text(
                weightDeltaText(delta!).replaceAll('  ', ' '),
                style: AppTextStyles.captionStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
        onTap: () => context.push(WeightRoutes.edit(entry.id)),
      ),
    );
  }
}

/// Paints one row of a month card: fill, the outline of the card where this
/// row touches its top and bottom, and the divider to the next row. Drawing
/// the card in slices keeps every row lazily buildable.
class _SlicePainter extends CustomPainter {
  const _SlicePainter({
    required this.fill,
    required this.border,
    required this.divider,
    required this.radius,
    required this.first,
    required this.last,
  });

  final Color fill;
  final Color border;
  final Color divider;
  final double radius;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    // The outline extends beyond the row where the card continues, so only
    // the side lines of that part remain visible after clipping.
    final top = first ? 0.5 : -2 * radius;
    final bottom = last ? size.height - 0.5 : size.height + 2 * radius;
    final outline = RRect.fromLTRBR(
      0.5,
      top,
      size.width - 0.5,
      bottom,
      Radius.circular(radius),
    );
    canvas
      ..drawRRect(outline, Paint()..color = fill)
      ..drawRRect(
        outline,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    if (!last) {
      canvas.drawLine(
        Offset(14, size.height - 0.5),
        Offset(size.width - 14, size.height - 0.5),
        Paint()
          ..color = divider
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.divider != divider ||
      old.first != first ||
      old.last != last;
}
