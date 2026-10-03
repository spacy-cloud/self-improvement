import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:self_improvement/core/design/components/app_header.dart';
import 'package:self_improvement/core/design/layout/adaptive_grid.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_spacing.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Page scaffold of the app: [AppHeader] on the surface colour (also behind
/// the status bar), a scrolling body on the page background, an optional pinned
/// [primaryAction] and an optional [bottomNavigationBar].
///
/// * The body scrolls (content never clips on large text); with
///   `scrollable: false` the body manages its own scrolling (lists).
/// * The [primaryAction] sits below the scroll area and moves above the
///   keyboard (`resizeToAvoidBottomInset`), so it stays reachable.
/// * Content is centred and limited to [maxContentWidth] on wide screens.
/// * Safe areas (status bar, gesture bar) are respected.
class AppScaffold extends StatelessWidget {
  /// Creates a scaffold with the header [type].
  const AppScaffold({
    required this.title,
    required this.body,
    super.key,
    this.type = AppHeaderType.tab,
    this.onBack,
    this.backLabel = 'Zurück',
    this.leading,
    this.actions = const <Widget>[],
    this.primaryAction,
    this.bottomNavigationBar,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s8,
      AppSpacing.s16,
      AppSpacing.s16,
    ),
    this.resizeToAvoidBottomInset = true,
    this.safeAreaBottom = true,
    this.scrollController,
    this.maxContentWidth = AppSizes.contentMaxWidth,
  });

  /// Scaffold of a sub page: the header shows a back button.
  const AppScaffold.subpage({
    required this.title,
    required this.body,
    super.key,
    this.onBack,
    this.backLabel = 'Zurück',
    this.leading,
    this.actions = const <Widget>[],
    this.primaryAction,
    this.bottomNavigationBar,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s8,
      AppSpacing.s16,
      AppSpacing.s16,
    ),
    this.resizeToAvoidBottomInset = true,
    this.safeAreaBottom = true,
    this.scrollController,
    this.maxContentWidth = AppSizes.contentMaxWidth,
  }) : type = AppHeaderType.subpage;

  /// Page title.
  final String title;

  /// Page content.
  final Widget body;

  /// Header variant.
  final AppHeaderType type;

  /// Back callback of sub pages; defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Spoken label of the back button.
  final String backLabel;

  /// Replaces the back button of a sub page.
  final Widget? leading;

  /// Trailing header actions.
  final List<Widget> actions;

  /// Action pinned below the scroll area, for example a `PrimaryButton`.
  final Widget? primaryAction;

  /// Bottom navigation (the shell passes `AppBottomNavBar` here).
  final Widget? bottomNavigationBar;

  /// Whether the scaffold wraps [body] in a scroll view.
  final bool scrollable;

  /// Padding around [body].
  final EdgeInsetsGeometry padding;

  /// Whether the body shrinks above the keyboard.
  final bool resizeToAvoidBottomInset;

  /// Whether the body keeps clear of the bottom system inset. It is ignored
  /// when [bottomNavigationBar] is set (the bar handles the inset itself). Set
  /// it to `false` when the page is nested in a shell whose navigation bar
  /// already covers the inset.
  final bool safeAreaBottom;

  /// Controller of the scroll view when [scrollable].
  final ScrollController? scrollController;

  /// Maximum content width on wide screens.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    // Only the status bar is styled: transparent, icons follow the theme. The
    // navigation bar of the system is left to the shell.
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: tokens.isDark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: tokens.isDark ? Brightness.dark : Brightness.light,
    );

    final content = Column(
      children: <Widget>[
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  controller: scrollController,
                  padding: padding,
                  child: body,
                )
              : Padding(padding: padding, child: body),
        ),
        if (primaryAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s8,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: primaryAction,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bottomNavigationBar: bottomNavigationBar,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Column(
          children: <Widget>[
            ColoredBox(
              color: colors.surface,
              child: SafeArea(
                bottom: false,
                child: MaxContentWidth(
                  maxWidth: maxContentWidth,
                  child: AppHeader(
                    title: title,
                    type: type,
                    onBack: onBack,
                    backLabel: backLabel,
                    leading: leading,
                    actions: actions,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: safeAreaBottom && bottomNavigationBar == null,
                child: MaxContentWidth(
                  maxWidth: maxContentWidth,
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
