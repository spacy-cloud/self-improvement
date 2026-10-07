import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Shows [builder] as a modal bottom sheet that looks like the confirmation
/// sheet of the design system (floating card with a 16 px margin) but holds
/// any content: the reminder permission sheet, the import preview, the reset
/// confirmation.
///
/// The sheet scrolls, keeps clear of the keyboard and closes with its own
/// button, the system back action or a tap on the barrier. Dragging its
/// content closes the keyboard. It cannot be
/// dragged away: sheets that run an operation must not disappear half way.
Future<T?> showAppModalSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final colors = context.tokens.colors;
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: (sheetContext) {
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + keyboard),
        child: builder(sheetContext),
      );
    },
  );
}

/// Frame of a sheet: handle, title row with an optional close button, the
/// [children] and the [footer] actions below.
///
/// The sheet is announced as a route with the [title] as its name, and the
/// title is a heading. With [closable] the close button (48 x 48, "Schließen")
/// sits right of the title; it is disabled while [onClose] is `null` (an
/// operation is running).
///
/// Nothing is ever clipped: when the sheet is higher than the screen the
/// [children] scroll. The [footer] (the actions) stays pinned below the
/// scrolling part as long as there is room for it, so a long preview never
/// pushes its confirmation off the screen; on small screens and at very large
/// text it scrolls along with the rest instead.
class AppSheetFrame extends StatelessWidget {
  /// Creates a sheet frame.
  const AppSheetFrame({
    required this.title,
    required this.children,
    super.key,
    this.footer = const <Widget>[],
    this.onClose,
    this.closable = true,
  });

  /// Question or name of the sheet, for example "Erinnerungen erlauben?".
  final String title;

  /// Content below the title row.
  final List<Widget> children;

  /// Actions below the content (buttons), pinned when there is room.
  final List<Widget> footer;

  /// Called by the close button; `null` disables it.
  final VoidCallback? onClose;

  /// Whether the title row has a close button.
  final bool closable;

  /// Smallest sheet height from which the footer is pinned.
  static const double _pinFromHeight = 560;

  List<Widget> _header(BuildContext context) {
    final colors = context.tokens.colors;
    return <Widget>[
      Center(
        child: ExcludeSemantics(
          child: Container(
            width: AppSizes.sheetHandleWidth,
            height: AppSizes.sheetHandleHeight,
            decoration: BoxDecoration(
              color: colors.borderInput,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                style: AppTextStyles.titleSection.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          if (closable) ...<Widget>[
            const SizedBox(width: 8),
            AppIconButton(
              icon: AppIcon.close.data,
              filled: true,
              semanticLabel: 'Schließen',
              onPressed: onClose,
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.sheetBorder,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pin =
                footer.isNotEmpty &&
                constraints.maxHeight.isFinite &&
                constraints.maxHeight >= _pinFromHeight &&
                scale <= 1.5;
            if (!pin) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ..._header(context),
                    ...children,
                    if (footer.isNotEmpty) const SizedBox(height: 16),
                    ...footer,
                  ],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _header(context),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: footer,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How a [SheetMessage] looks.
enum SheetMessageTone {
  /// Warning on the warning tint (for example "data will be replaced").
  warning,

  /// Error on the error tint; announced as a live region.
  error,

  /// Neutral note on the muted surface.
  neutral,
}

/// A short message block inside a sheet: icon and text on a tint, never colour
/// alone. Errors are a live region, so they are read out when they appear.
class SheetMessage extends StatelessWidget {
  /// Creates a message block.
  const SheetMessage({
    required this.text,
    super.key,
    this.tone = SheetMessageTone.neutral,
  });

  /// The message (German, without personal values).
  final String text;

  /// Visual role of the message.
  final SheetMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final (Color background, Color foreground, IconData icon) = switch (tone) {
      SheetMessageTone.warning => (
        colors.warningTint,
        colors.warningText,
        AppIcon.info.data,
      ),
      SheetMessageTone.error => (
        colors.errorTint,
        colors.error,
        AppIcon.error.data,
      ),
      SheetMessageTone.neutral => (
        colors.surfaceMuted,
        colors.textSecondary,
        AppIcon.info.data,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: tone == SheetMessageTone.error,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16, color: foreground),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.bodyRegular.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round tinted badge with a glyph, the illustration of a sheet (bell,
/// warning, error).
class SheetBadge extends StatelessWidget {
  /// Creates a badge.
  const SheetBadge({
    required this.icon,
    required this.accent,
    super.key,
    this.size = 64,
  });

  /// The glyph.
  final IconData icon;

  /// The accent that selects tint and glyph colour.
  final AppAccent accent;

  /// Diameter of the circle.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentTint(accent),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size * 0.45, color: colors.accent(accent)),
        ),
      ),
    );
  }
}
