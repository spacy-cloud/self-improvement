import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_icon_button.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/text_scale.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Variants of [AppHeader].
enum AppHeaderType {
  /// Title of a main tab: no back button.
  tab,

  /// Title of a sub page: back button on the left.
  subpage,
}

/// Page header: title (Title/Screen) and optional trailing actions. Sub pages
/// show a filled back button labelled "Zurück" (the Android back gesture closes
/// the page as well). The header grows when the title wraps on large text.
class AppHeader extends StatelessWidget {
  /// Creates a header of [type].
  const AppHeader({
    required this.title,
    super.key,
    this.type = AppHeaderType.tab,
    this.onBack,
    this.backLabel = 'Zurück',
    this.leading,
    this.actions = const <Widget>[],
  });

  /// Header of a sub page with a back button.
  const AppHeader.subpage({
    required this.title,
    super.key,
    this.onBack,
    this.backLabel = 'Zurück',
    this.leading,
    this.actions = const <Widget>[],
  }) : type = AppHeaderType.subpage;

  /// Page title.
  final String title;

  /// Variant.
  final AppHeaderType type;

  /// Back callback of sub pages; defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Spoken label of the back button.
  final String backLabel;

  /// Replaces the back button of a sub page.
  final Widget? leading;

  /// Trailing actions (for example [AppIconButton]s).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isSubpage = type == AppHeaderType.subpage;
    final back = isSubpage
        ? (leading ??
              AppIconButton(
                icon: AppIcon.back.data,
                semanticLabel: backLabel,
                filled: true,
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ))
        : null;
    final stacked =
        context.textScaleFactor > AppSizes.stackTextScale &&
        (back != null || actions.isNotEmpty);
    final titleWidget = Semantics(
      container: true,
      header: true,
      child: _HeaderTitle(
        title: title,
        style: AppTextStyles.titleScreen.copyWith(color: colors.textPrimary),
      ),
    );
    final padding = EdgeInsets.fromLTRB(isSubpage ? 20 : 24, 8, 16, 8);
    if (stacked) {
      // Large text: back button and actions get their own row, the title
      // uses the full width instead of breaking inside words.
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[?back, const Spacer(), ...actions]),
            Padding(
              padding: EdgeInsets.only(left: isSubpage ? 4 : 0, bottom: 4),
              child: titleWidget,
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
            if (back != null) ...<Widget>[back, const SizedBox(width: 8)],
            Expanded(child: titleWidget),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The title text. Titles wrap between words; a single word that is wider than
/// the line at the current text size (for example "Einstellungen" at 320 px and
/// 200 %) is set a little smaller instead of breaking in the middle of the
/// word.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.title, required this.style});

  final String title;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var effective = style;
        if (constraints.hasBoundedWidth) {
          var widest = 0.0;
          for (final word in title.split(RegExp(r'\s+'))) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            widest = math.max(widest, painter.width);
            painter.dispose();
          }
          if (widest > constraints.maxWidth && widest > 0) {
            final ratio = constraints.maxWidth / widest * 0.97;
            effective = style.copyWith(
              fontSize: (style.fontSize ?? 24) * ratio,
            );
          }
        }
        return Text(title, style: effective);
      },
    );
  }
}
