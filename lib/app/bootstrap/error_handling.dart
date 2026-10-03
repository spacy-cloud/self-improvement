import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Central handling of unknown errors (spec 21): they are caught in one place
/// and logged WITHOUT personal data.
///
/// The log line carries only the type of the error and the library that
/// reported it, never its message (which may contain what the user entered)
/// and never a stack trace. In a debug build the framework's own report is
/// shown as well, so a developer sees the details on the console and in the red
/// error screen. Outside debug builds a widget that fails to build is replaced
/// by [NeutralErrorWidget] instead of an empty grey box.
///
/// Call once before `runApp`. [debug] exists for tests.
void installErrorHandling({bool debug = kDebugMode}) {
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint(
      'unhandled framework error: ${details.exception.runtimeType}'
      '${details.library == null ? '' : ' in ${details.library}'}',
    );
    if (debug) {
      FlutterError.presentError(details);
    }
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('unhandled error: ${error.runtimeType}');
    return true;
  };
  if (!debug) {
    ErrorWidget.builder = (FlutterErrorDetails details) =>
        const NeutralErrorWidget();
  }
}

/// Replaces a widget that failed to build (outside debug builds): a short,
/// neutral German sentence instead of a blank box. It shows no technical
/// text and nothing the user entered.
class NeutralErrorWidget extends StatelessWidget {
  const NeutralErrorWidget({super.key});

  /// What the widget says.
  static const String message = 'Dieser Bereich konnte nicht angezeigt werden.';

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFF6F7F9),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF3D4650),
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
