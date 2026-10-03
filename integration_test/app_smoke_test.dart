import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/core/config/app_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots on the target platform', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SelfImprovementApp()));
    await tester.pumpAndSettle();
    expect(find.text(AppConfig.appName), findsOneWidget);
  });
}
