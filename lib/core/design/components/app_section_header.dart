import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Heading of a section on a page: title (Title/Section), an optional line of
/// help text below and an optional text action on the right ("Bearbeiten",
/// "Alle anzeigen"). The title is announced as a heading, so screen reader
/// users can jump from section to section. The action has a 48 px tap area.
///
/// [AppSectionHeader.group] is the small upper-case label above a group of
/// settings ("DARSTELLUNG", "DATEN").
class AppSectionHeader extends StatelessWidget {
  /// Creates a section heading.
  const AppSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionSemanticLabel,
    this.padding = const EdgeInsets.only(left: 6, top: 4),
  }) : _group = false;

  /// Small upper-case label above a group of settings.
  const AppSectionHeader.group({
    required this.title,
    super.key,
    this.padding = const EdgeInsets.only(left: 8, top: 8),
  }) : subtitle = null,
       actionLabel = null,
       onAction = null,
       actionSemanticLabel = null,
       _group = true;

  /// Heading text.
  final String title;

  /// Help text below the title.
  final String? subtitle;

  /// Label of the text action on the right.
  final String? actionLabel;

  /// Callback of the text action.
  final VoidCallback? onAction;

  /// Spoken label of the action (defaults to [actionLabel]).
  final String? actionSemanticLabel;

  /// Space around the heading.
  final EdgeInsetsGeometry padding;

  final bool _group;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final titleStyle = _group
        ? AppTextStyles.captionStrong.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.66,
          )
        : AppTextStyles.titleSection.copyWith(color: colors.textPrimary);
    final heading = Semantics(
      container: true,
      header: true,
      child: Text(_group ? title.toUpperCase() : title, style: titleStyle),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        heading,
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
    final hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: padding,
      child: hasAction
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: texts),
                const SizedBox(width: 8),
                Semantics(
                  container: true,
                  button: true,
                  label: actionSemanticLabel ?? actionLabel,
                  onTap: onAction,
                  excludeSemantics: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.touchMin,
                      minWidth: AppSizes.touchMin,
                    ),
                    child: InkSurface(
                      onTap: onAction,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.controlBorder,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            actionLabel!,
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : texts,
    );
  }
}
