import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_icon_tile.dart';
import 'package:self_improvement/core/design/components/app_switch.dart';
import 'package:self_improvement/core/design/components/round_checkbox.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

enum _TileTrailing { custom, chevron, toggle, check, value }

/// List row (Figma "ListRow"): icon tile, title, optional subtitle and a
/// trailing element. The whole row is tappable and at least 56 high; texts
/// wrap and the row grows with large text.
///
/// Variants: [EntryListTile.chevron] (opens something), [EntryListTile.toggle]
/// (the whole row switches a setting) and [EntryListTile.value] (shows a
/// value). Put rows into an `AppCard` with zero padding and separate them with
/// a `Divider` for grouped lists.
class EntryListTile extends StatelessWidget {
  /// Creates a row with a custom [trailing] widget.
  const EntryListTile({
    required this.title,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = AppAccent.primary,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.destructive = false,
  }) : _trailing = _TileTrailing.custom,
       valueText = null,
       toggleValue = false,
       onToggle = null,
       showChevron = false;

  /// Row with a trailing chevron: tapping opens a screen or a sheet.
  const EntryListTile.chevron({
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = AppAccent.primary,
    this.leading,
    this.semanticLabel,
    this.destructive = false,
  }) : _trailing = _TileTrailing.chevron,
       trailing = null,
       valueText = null,
       toggleValue = false,
       onToggle = null,
       showChevron = true;

  /// Row with a toggle: tapping anywhere switches the setting.
  const EntryListTile.toggle({
    required this.title,
    required bool value,
    required this.onToggle,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = AppAccent.primary,
    this.leading,
    this.semanticLabel,
  }) : _trailing = _TileTrailing.toggle,
       toggleValue = value,
       trailing = null,
       onTap = null,
       valueText = null,
       destructive = false,
       showChevron = false;

  /// Row with a trailing round checkbox for multi-select lists (for example
  /// the measurement conditions): tapping anywhere changes the choice; screen
  /// readers get one checkable row.
  const EntryListTile.check({
    required this.title,
    required bool value,
    required this.onToggle,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = AppAccent.primary,
    this.leading,
    this.semanticLabel,
  }) : _trailing = _TileTrailing.check,
       toggleValue = value,
       trailing = null,
       onTap = null,
       valueText = null,
       destructive = false,
       showChevron = false;

  /// Row with a trailing value text; [showChevron] adds a chevron when the row
  /// opens a screen.
  const EntryListTile.value({
    required this.title,
    required String value,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = AppAccent.primary,
    this.leading,
    this.onTap,
    this.semanticLabel,
    this.showChevron = false,
  }) : _trailing = _TileTrailing.value,
       valueText = value,
       trailing = null,
       toggleValue = false,
       onToggle = null,
       destructive = false;

  /// Row title.
  final String title;

  /// Optional second line (may wrap).
  final String? subtitle;

  /// Glyph of the icon tile; ignored when [leading] is set.
  final IconData? icon;

  /// Accent of the icon tile.
  final AppAccent accent;

  /// Replaces the icon tile.
  final Widget? leading;

  /// Trailing widget of the custom variant.
  final Widget? trailing;

  /// Tap callback of the row (not used by the toggle variant).
  final VoidCallback? onTap;

  /// Spoken label; defaults to title, subtitle and value joined with commas.
  final String? semanticLabel;

  /// Title in the error colour (for example "Alle Daten zurücksetzen").
  final bool destructive;

  /// Value of the toggle and check variants.
  final bool toggleValue;

  /// Change callback of the toggle and check variants.
  final ValueChanged<bool>? onToggle;

  /// Value text of the value variant.
  final String? valueText;

  /// Whether a chevron follows the value.
  final bool showChevron;

  final _TileTrailing _trailing;

  String get _label {
    if (semanticLabel != null) {
      return semanticLabel!;
    }
    final parts = <String>[title];
    if (subtitle != null && subtitle!.isNotEmpty) {
      parts.add(subtitle!);
    }
    if (valueText != null && valueText!.isNotEmpty) {
      parts.add(valueText!);
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isToggle = _trailing == _TileTrailing.toggle;
    final isCheck = _trailing == _TileTrailing.check;
    final VoidCallback? tap = isToggle || isCheck
        ? (onToggle == null ? null : () => onToggle!(!toggleValue))
        : onTap;

    final Widget? trailingWidget = switch (_trailing) {
      _TileTrailing.custom => trailing,
      _TileTrailing.chevron => Icon(
        AppIcon.chevronRight.data,
        size: 20,
        color: colors.textSecondary,
      ),
      _TileTrailing.toggle => ExcludeSemantics(
        child: IgnorePointer(
          child: AppSwitch(
            value: toggleValue,
            onChanged: onToggle,
            semanticLabel: title,
          ),
        ),
      ),
      _TileTrailing.check => ExcludeSemantics(
        child: IgnorePointer(
          child: RoundCheckbox(
            value: toggleValue,
            onChanged: onToggle == null ? null : (_) {},
            semanticLabel: title,
            squared: true,
          ),
        ),
      ),
      _TileTrailing.value => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              valueText ?? '',
              textAlign: TextAlign.end,
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          if (showChevron) ...<Widget>[
            const SizedBox(width: 4),
            Icon(
              AppIcon.chevronRight.data,
              size: 20,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    };

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null)
          leading!
        else if (icon != null)
          AppIconTile(icon: icon!, accent: accent),
        if (leading != null || icon != null) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: AppTextStyles.bodyDefault.copyWith(
                  color: destructive ? colors.error : colors.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailingWidget != null) ...<Widget>[
          const SizedBox(width: 12),
          Flexible(flex: 0, child: trailingWidget),
        ],
      ],
    );

    return Semantics(
      container: true,
      button: tap != null && !isToggle && !isCheck,
      toggled: isToggle ? toggleValue : null,
      checked: isCheck ? toggleValue : null,
      enabled: isToggle || isCheck ? onToggle != null : null,
      label: _label,
      onTap: tap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.listRowMinHeight),
        child: InkSurface(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: content,
          ),
        ),
      ),
    );
  }
}
