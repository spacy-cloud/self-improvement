import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/settings/application/external_link_opener.dart';

/// An [ExternalLinkOpener] for tests: it records every address and answers like
/// a device with a browser ([result] `true`) or without one (`false`). With
/// [hold] the answer waits until [release] is called, so a test can tap a
/// second time while the first tap is still being handled.
class FakeExternalLinkOpener implements ExternalLinkOpener {
  FakeExternalLinkOpener({this.result = true, this.hold = false});

  /// What the next calls answer.
  bool result;

  /// Whether calls wait for [release].
  bool hold;

  /// Every address that was asked for, in order.
  final List<Uri> opened = <Uri>[];

  final List<Completer<bool>> _waiting = <Completer<bool>>[];

  @override
  Future<bool> open(Uri uri) {
    opened.add(uri);
    if (!hold) {
      return Future<bool>.value(result);
    }
    final completer = Completer<bool>();
    _waiting.add(completer);
    return completer.future;
  }

  /// Answers every waiting call with [result].
  void release() {
    for (final completer in _waiting) {
      completer.complete(result);
    }
    _waiting.clear();
  }
}

/// What the app put into the clipboard, and whether the clipboard refuses.
class ClipboardRecorder {
  ClipboardRecorder({this.refuse = false});

  /// Whether `Clipboard.setData` fails with a platform error.
  bool refuse;

  /// The texts that were copied, in order.
  final List<String> texts = <String>[];
}

/// Replaces the platform clipboard for the test: copied texts are recorded, and
/// with [refuse] the copy fails like a clipboard that is not available.
ClipboardRecorder recordClipboard(WidgetTester tester, {bool refuse = false}) {
  final recorder = ClipboardRecorder(refuse: refuse);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        if (recorder.refuse) {
          throw PlatformException(code: 'unavailable');
        }
        final arguments = call.arguments as Map<Object?, Object?>;
        recorder.texts.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return recorder;
}
