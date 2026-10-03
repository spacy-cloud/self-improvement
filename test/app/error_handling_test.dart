import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/bootstrap/error_handling.dart';

void main() {
  late FlutterExceptionHandler? savedHandler;
  late ErrorWidgetBuilder savedBuilder;
  late ui.ErrorCallback? savedPlatformHandler;
  var logs = <String>[];

  setUp(() {
    savedHandler = FlutterError.onError;
    savedBuilder = ErrorWidget.builder;
    savedPlatformHandler = ui.PlatformDispatcher.instance.onError;
    logs = <String>[];
  });

  tearDown(() {
    FlutterError.onError = savedHandler;
    ErrorWidget.builder = savedBuilder;
    ui.PlatformDispatcher.instance.onError = savedPlatformHandler;
  });

  /// Captures what the app logs for the rest of the test. Only plain tests use
  /// it: a widget test must leave the foundation debug variables unchanged.
  void captureLogs() {
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = saved);
  }

  test('a framework error is logged with its type only, never its message', () {
    captureLogs();
    installErrorHandling(debug: false);
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('Gewicht 71,5 kg von Max Mustermann'),
        library: 'widgets library',
      ),
    );
    expect(logs, hasLength(1));
    expect(logs.single, contains('StateError'));
    expect(logs.single, contains('widgets library'));
    expect(logs.single, isNot(contains('71,5')));
    expect(logs.single, isNot(contains('Mustermann')));
  });

  test('an uncaught async error is handled and logged with its type only', () {
    captureLogs();
    installErrorHandling(debug: false);
    final handled = ui.PlatformDispatcher.instance.onError!(
      ArgumentError('secret 123'),
      StackTrace.current,
    );
    expect(handled, isTrue, reason: 'nothing is rethrown to the engine');
    expect(logs.single, contains('ArgumentError'));
    expect(logs.single, isNot(contains('secret')));
  });

  test('outside debug builds a failed widget becomes a neutral sentence', () {
    installErrorHandling(debug: false);
    final widget = ErrorWidget.builder(
      FlutterErrorDetails(exception: StateError('Gewicht 71,5 kg')),
    );
    expect(widget, isA<NeutralErrorWidget>());
  });

  testWidgets('the neutral widget says one German sentence and nothing else', (
    tester,
  ) async {
    await tester.pumpWidget(const NeutralErrorWidget());
    expect(find.text(NeutralErrorWidget.message), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  test('a debug build keeps the framework default error widget', () {
    final before = ErrorWidget.builder;
    installErrorHandling(debug: true);
    expect(identical(ErrorWidget.builder, before), isTrue);
  });
}
