import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/core/config/app_config.dart';

void main() {
  testWidgets('bootstrap app starts and shows the configured app name', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SelfImprovementApp()));
    expect(find.text(AppConfig.appName), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, AppConfig.appName);
  });
}
