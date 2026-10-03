import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

import '../../../integration_test/flows/first_start_flow.dart';
import '../../../integration_test/flows/flow_context.dart';
import '../../../integration_test/flows/tasks_flow.dart';
import '../../../integration_test/flows/water_flow.dart';
import '../../../integration_test/flows/weight_flow.dart';
import '../support/app_harness.dart';

/// The host side of the flows: the whole app on an in-memory database with a
/// fake clock and a fake notification platform (see `pumpFullApp`).
final class _HostEnvironment implements FlowEnvironment {
  late DataHarness harness;

  Future<void> start(WidgetTester tester) async {
    final app = await pumpFullApp(tester, onboarded: false);
    harness = app.harness;
  }

  @override
  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  @override
  Future<void> openApp(WidgetTester tester) async {
    await pumpFullApp(tester, reuse: harness);
    await waitForAppStart(tester);
  }

  @override
  Future<Duration> letTimePass(WidgetTester tester, Duration wanted) async {
    harness.clock.advance(wanted);
    return wanted;
  }

  @override
  Future<void> expectDatabaseOnDisk() async {}

  @override
  Future<String> platformZoneId() async => 'Europe/Berlin';
}

/// Starts the app like a fresh install, runs [flow] and unmounts the app again
/// even when the flow fails: flutter_test closes the database before it
/// unmounts the widgets of a failed test, and a database that is closed under a
/// running app never finishes closing (the failed run would hang).
Future<void> _runFlow(
  WidgetTester tester,
  Future<void> Function(FlowContext ctx) flow,
) async {
  final environment = _HostEnvironment();
  await environment.start(tester);
  await waitForAppStart(tester);
  try {
    await flow(FlowContext(tester: tester, environment: environment));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('AT01 first start: onboarding leads to the home screen', (
    tester,
  ) async {
    await _runFlow(tester, firstStartFlow);
  });

  testWidgets(
    'AT02 and AT06 weight: saved, shown and still there after a restart',
    (tester) async {
      await _runFlow(tester, weightPersistsFlow);
    },
  );

  testWidgets('AT10 water: +250 ml from the home screen, undo once', (
    tester,
  ) async {
    await _runFlow(tester, waterQuickAddFlow);
  });

  testWidgets('AT13 task: create, complete, reopen, complete again', (
    tester,
  ) async {
    await _runFlow(tester, taskFlow);
  });
}
